import Foundation
import CoreGraphics
import Accelerate

/// Result of moon detection, containing all information needed for processing.
struct MoonDetectionResult {
    /// Fitted circle representing the moon
    let circle: FittedCircle

    /// Padded crop rectangle around the moon
    let cropRect: CGRect

    /// Soft mask for the moon region (0..1, feathered edge)
    let moonMask: MaskBuffer

    /// Inner band mask for limb protection (0..1)
    let limbRingMask: MaskBuffer

    /// Detection confidence metrics
    let confidence: DetectionConfidence

    /// Fraction of pixels within moon that are clipped (0..1)
    let clippedHighlightFraction: Float

    /// Detection was not successful
    static let notDetected = MoonDetectionResult?.none
}

/// A fitted circle with center and radius
struct FittedCircle {
    let center: CGPoint
    let radius: CGFloat
    let residualError: CGFloat  // RMS error of fit

    /// Check if a point is inside the circle
    func contains(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return sqrt(dx * dx + dy * dy) <= radius
    }

    /// Distance from point to circle edge (negative if inside)
    func distanceToEdge(_ point: CGPoint) -> CGFloat {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return sqrt(dx * dx + dy * dy) - radius
    }
}

/// Confidence metrics for moon detection
struct DetectionConfidence {
    /// Overall detection confidence (0..1)
    let circleConfidence: Float

    /// How well the circle fits the detected edge
    let fitQuality: Float

    /// Size ratio of moon to image (penalizes very small/large)
    let sizeScore: Float

    /// Brightness consistency within detected region
    let brightnessConsistency: Float

    /// Circularity of the detected blob (1.0 = perfect circle)
    let circularity: Float
}

/// Wrapper for mask data (grayscale buffer)
struct MaskBuffer {
    let width: Int
    let height: Int
    let data: [Float]

    /// Create an empty mask
    static func empty(width: Int, height: Int) -> MaskBuffer {
        return MaskBuffer(
            width: width,
            height: height,
            data: [Float](repeating: 0, count: width * height)
        )
    }

    /// Create a filled mask
    static func filled(width: Int, height: Int, value: Float = 1.0) -> MaskBuffer {
        return MaskBuffer(
            width: width,
            height: height,
            data: [Float](repeating: value, count: width * height)
        )
    }

    /// Get value at position
    func value(at x: Int, y: Int) -> Float {
        guard x >= 0 && x < width && y >= 0 && y < height else { return 0 }
        return data[y * width + x]
    }

    /// Create a vImage buffer (caller must free)
    func makeVImageBuffer() -> vImage_Buffer {
        var buffer = vImage_Buffer()
        buffer.width = vImagePixelCount(width)
        buffer.height = vImagePixelCount(height)
        buffer.rowBytes = width * MemoryLayout<Float>.stride

        let dataPtr = UnsafeMutablePointer<Float>.allocate(capacity: data.count)
        dataPtr.initialize(from: data, count: data.count)
        buffer.data = UnsafeMutableRawPointer(dataPtr)

        return buffer
    }

    /// Resize mask using nearest-neighbor sampling.
    func resized(toWidth width: Int, height: Int) -> MaskBuffer {
        guard self.width > 0, self.height > 0, width > 0, height > 0 else {
            return MaskBuffer.empty(width: width, height: height)
        }

        if self.width == width && self.height == height {
            return self
        }

        var resized = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let srcY = Int(Float(y) / Float(height) * Float(self.height - 1))
            for x in 0..<width {
                let srcX = Int(Float(x) / Float(width) * Float(self.width - 1))
                resized[y * width + x] = data[srcY * self.width + srcX]
            }
        }

        return MaskBuffer(width: width, height: height, data: resized)
    }
}

/// Information about a detected blob
struct BlobInfo {
    let boundingBox: CGRect
    let area: Int
    let centroid: CGPoint
    let circularity: Float  // 4 * pi * area / perimeter^2
    let edgePoints: [CGPoint]
}
