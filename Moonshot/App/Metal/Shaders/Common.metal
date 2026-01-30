//
//  Common.metal
//  Moonshot
//
//  Common types, utilities, and basic kernels for moon enhancement.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Common Types

/// Parameters for tone curve processing
struct ToneParams {
    float shoulderStart;     // Fraction of white point
    float shoulderStrength;  // Compression strength
    float contrastGain;      // Midtone contrast adjustment
    float contrastPivot;     // Pivot point for contrast
    float whitePoint;        // Calculated white point
};

/// Parameters for guided filter denoise
struct DenoiseParams {
    float strength;          // Base strength
    int radius;              // Filter radius
    float epsilon;           // Edge preservation
};

/// Parameters for Richardson-Lucy deconvolution
struct DeconvParams {
    float psfSigma;          // PSF sigma
    float updateBase;        // Base multiplier
    float updateScale;       // Confidence scale
    float limbMultiplier;    // Limb ring multiplier
};

/// Parameters for wavelet sharpening
struct WaveletParams {
    float fineGain;          // 1-2px features
    float midGain;           // 3-6px features
    float coarseGain;        // 7-14px features
    float cExponent;         // Confidence exponent
    float limbMultiplier;    // Limb protection
    float minSNR;            // Minimum SNR threshold
};

// MARK: - Utility Functions

/// Clamp value to 0-1 range
inline float clamp01(float x) {
    return clamp(x, 0.0f, 1.0f);
}

/// Linear interpolation
inline float lerp(float a, float b, float t) {
    return a + t * (b - a);
}

/// Convert RGB to luminance (BT.709)
inline float rgbToLuminance(float3 rgb) {
    return dot(rgb, float3(0.2126, 0.7152, 0.0722));
}

/// Convert RGB to luminance (simple average, faster)
inline float rgbToLuminanceSimple(float3 rgb) {
    return (rgb.r + rgb.g + rgb.b) / 3.0;
}

/// Soft shoulder curve for highlight compression
inline float shoulderCurve(float x, float start, float strength) {
    if (x < start) {
        return x;
    }
    float excess = x - start;
    return start + (1.0 - start) * tanh(excess * strength / (1.0 - start));
}

/// S-curve for contrast adjustment
inline float contrastCurve(float x, float gain, float pivot) {
    float shifted = x - pivot;
    return pivot + shifted * (1.0 + gain * (1.0 - abs(shifted)));
}

// MARK: - Basic Kernels

/// Convert RGBA to luminance (single channel)
kernel void rgbaToLuminance(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float4 pixel = input.read(gid);
    float luma = rgbToLuminance(pixel.rgb);
    output.write(float4(luma, 0, 0, 1), gid);
}

/// Apply subpixel shift with bilinear interpolation
kernel void applySubpixelShift(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant float2& shift [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) {
        return;
    }

    // Calculate source coordinate
    float2 sourceCoord = float2(gid) + shift;

    // Bilinear interpolation
    int2 coord0 = int2(floor(sourceCoord));
    int2 coord1 = coord0 + int2(1, 1);
    float2 frac = sourceCoord - float2(coord0);

    // Clamp to texture bounds
    coord0 = clamp(coord0, int2(0), int2(source.get_width() - 1, source.get_height() - 1));
    coord1 = clamp(coord1, int2(0), int2(source.get_width() - 1, source.get_height() - 1));

    // Sample four neighbors
    float4 s00 = source.read(uint2(coord0));
    float4 s10 = source.read(uint2(coord1.x, coord0.y));
    float4 s01 = source.read(uint2(coord0.x, coord1.y));
    float4 s11 = source.read(uint2(coord1));

    // Bilinear interpolation
    float4 result = mix(
        mix(s00, s10, frac.x),
        mix(s01, s11, frac.x),
        frac.y
    );

    destination.write(result, gid);
}

/// Accumulate weighted frame for stacking
kernel void accumulateWeighted(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::read_write> accumulator [[texture(1)]],
    constant float& weight [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= accumulator.get_width() || gid.y >= accumulator.get_height()) {
        return;
    }

    float4 current = accumulator.read(gid);
    float4 addition = source.read(gid) * weight;
    accumulator.write(current + addition, gid);
}

/// Apply tone curve to luminance
kernel void applyToneCurve(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant ToneParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float4 pixel = input.read(gid);
    float luma = pixel.r;

    // Normalize by white point
    float normalized = luma / params.whitePoint;

    // Apply shoulder curve for highlights
    float shouldered = shoulderCurve(
        normalized,
        params.shoulderStart,
        params.shoulderStrength
    );

    // Apply contrast curve
    float contrasted = contrastCurve(
        shouldered,
        params.contrastGain,
        params.contrastPivot
    );

    // Denormalize
    float result = contrasted * params.whitePoint;

    output.write(float4(result, pixel.gba), gid);
}

/// Compute local gradient magnitude (Sobel)
kernel void computeGradientMagnitude(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x == 0 || gid.y == 0 ||
        gid.x >= output.get_width() - 1 || gid.y >= output.get_height() - 1) {
        output.write(float4(0), gid);
        return;
    }

    // Sobel kernels
    float tl = input.read(uint2(gid.x - 1, gid.y - 1)).r;
    float t  = input.read(uint2(gid.x,     gid.y - 1)).r;
    float tr = input.read(uint2(gid.x + 1, gid.y - 1)).r;
    float l  = input.read(uint2(gid.x - 1, gid.y    )).r;
    float r  = input.read(uint2(gid.x + 1, gid.y    )).r;
    float bl = input.read(uint2(gid.x - 1, gid.y + 1)).r;
    float b  = input.read(uint2(gid.x,     gid.y + 1)).r;
    float br = input.read(uint2(gid.x + 1, gid.y + 1)).r;

    float gx = -tl - 2*l - bl + tr + 2*r + br;
    float gy = -tl - 2*t - tr + bl + 2*b + br;

    float magnitude = sqrt(gx * gx + gy * gy);

    output.write(float4(magnitude, 0, 0, 1), gid);
}

/// Compute Laplacian for sharpness scoring
kernel void computeLaplacian(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x == 0 || gid.y == 0 ||
        gid.x >= output.get_width() - 1 || gid.y >= output.get_height() - 1) {
        output.write(float4(0), gid);
        return;
    }

    // Laplacian kernel: [0, 1, 0; 1, -4, 1; 0, 1, 0]
    float center = input.read(gid).r;
    float top    = input.read(uint2(gid.x, gid.y - 1)).r;
    float bottom = input.read(uint2(gid.x, gid.y + 1)).r;
    float left   = input.read(uint2(gid.x - 1, gid.y)).r;
    float right  = input.read(uint2(gid.x + 1, gid.y)).r;

    float laplacian = top + bottom + left + right - 4 * center;

    output.write(float4(laplacian, 0, 0, 1), gid);
}

/// Box blur (horizontal pass)
kernel void boxBlurHorizontal(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant int& radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float4 sum = float4(0);
    int count = 0;

    for (int dx = -radius; dx <= radius; dx++) {
        int x = int(gid.x) + dx;
        if (x >= 0 && x < int(input.get_width())) {
            sum += input.read(uint2(x, gid.y));
            count++;
        }
    }

    output.write(sum / float(count), gid);
}

/// Box blur (vertical pass)
kernel void boxBlurVertical(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant int& radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float4 sum = float4(0);
    int count = 0;

    for (int dy = -radius; dy <= radius; dy++) {
        int y = int(gid.y) + dy;
        if (y >= 0 && y < int(input.get_height())) {
            sum += input.read(uint2(gid.x, y));
            count++;
        }
    }

    output.write(sum / float(count), gid);
}

/// Apply mask to texture
kernel void applyMask(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::read> mask [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float4 pixel = input.read(gid);
    float maskValue = mask.read(gid).r;

    output.write(pixel * maskValue, gid);
}
