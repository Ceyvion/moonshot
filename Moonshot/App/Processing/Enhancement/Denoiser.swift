import Foundation

/// Confidence-gated denoiser for luminance and chroma.
final class Denoiser {
    func apply(
        luma: inout [Float],
        cb: inout [Float],
        cr: inout [Float],
        width: Int,
        height: Int,
        params: PresetConfiguration.DenoiseParameters,
        confidence: MaskBuffer
    ) {
        guard width > 0, height > 0 else { return }
        guard confidence.width == width, confidence.height == height else { return }

        let lumaBlur = boxBlur(luma, width: width, height: height, radius: params.guidedFilterRadius)

        for i in 0..<luma.count {
            let c = min(1, max(0, confidence.data[i]))
            let strength = params.lumaDenoiseBase * pow(1 - c, params.lumaDenoiseExponent)
            luma[i] = luma[i] * (1 - strength) + lumaBlur[i] * strength
        }

        let chromaRadius = max(1, params.guidedFilterRadius * 2)
        let cbBlur = boxBlur(cb, width: width, height: height, radius: chromaRadius)
        let crBlur = boxBlur(cr, width: width, height: height, radius: chromaRadius)

        let chromaStrength = min(1, max(0, params.chromaDenoise))
        for i in 0..<cb.count {
            cb[i] = cb[i] * (1 - chromaStrength) + cbBlur[i] * chromaStrength
            cr[i] = cr[i] * (1 - chromaStrength) + crBlur[i] * chromaStrength
        }
    }

    private func boxBlur(_ input: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return input }
        let kernelSize = radius * 2 + 1
        let kernelScale = 1.0 / Float(kernelSize)

        var temp = [Float](repeating: 0, count: width * height)

        // Horizontal pass
        for y in 0..<height {
            let rowStart = y * width
            var sum: Float = 0

            for x in -radius...radius {
                let clampedX = min(width - 1, max(0, x))
                sum += input[rowStart + clampedX]
            }

            for x in 0..<width {
                temp[rowStart + x] = sum * kernelScale

                let removeX = x - radius
                let addX = x + radius + 1
                let clampedRemove = min(width - 1, max(0, removeX))
                let clampedAdd = min(width - 1, max(0, addX))

                sum += input[rowStart + clampedAdd] - input[rowStart + clampedRemove]
            }
        }

        // Vertical pass
        var output = [Float](repeating: 0, count: width * height)
        for x in 0..<width {
            var sum: Float = 0
            for y in -radius...radius {
                let clampedY = min(height - 1, max(0, y))
                sum += temp[clampedY * width + x]
            }

            for y in 0..<height {
                output[y * width + x] = sum * kernelScale

                let removeY = y - radius
                let addY = y + radius + 1
                let clampedRemove = min(height - 1, max(0, removeY))
                let clampedAdd = min(height - 1, max(0, addY))

                sum += temp[clampedAdd * width + x] - temp[clampedRemove * width + x]
            }
        }

        return output
    }
}
