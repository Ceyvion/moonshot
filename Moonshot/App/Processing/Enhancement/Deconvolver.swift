import Foundation

/// Richardson-Lucy deconvolution with confidence gating.
final class Deconvolver {
    func apply(
        luma: inout [Float],
        width: Int,
        height: Int,
        params: PresetConfiguration.DeconvolutionParameters,
        confidence: MaskBuffer,
        limbRing: MaskBuffer
    ) {
        guard params.enabled else { return }
        guard width > 0, height > 0 else { return }
        guard confidence.width == width, confidence.height == height else { return }
        guard limbRing.width == width, limbRing.height == height else { return }

        let psf = gaussianKernel1D(sigma: params.psfSigma)
        var estimate = luma
        let observed = luma

        for _ in 0..<params.iterations {
            let blurred = gaussianBlur(estimate, width: width, height: height, kernel: psf)

            var ratio = [Float](repeating: 0, count: width * height)
            for i in 0..<ratio.count {
                let denom = max(blurred[i], 1e-4)
                ratio[i] = observed[i] / denom
            }

            let correction = gaussianBlur(ratio, width: width, height: height, kernel: psf)

            for i in 0..<estimate.count {
                let c = min(1, max(0, confidence.data[i]))
                let limb = min(1, max(0, limbRing.data[i]))

                let updateBase = params.updateMultiplierBase + params.updateMultiplierCScale * c
                let limbFactor = 1 - limb * (1 - params.limbRingMultiplier)
                let updateMultiplier = updateBase * limbFactor

                let corr = max(correction[i], 1e-3)
                estimate[i] = max(0, estimate[i] * pow(corr, updateMultiplier))
            }
        }

        luma = estimate
    }

    private func gaussianKernel1D(sigma: Float) -> [Float] {
        let radius = max(1, Int(ceil(3 * Double(sigma))))
        let size = radius * 2 + 1
        var kernel = [Float](repeating: 0, count: size)

        let sigma2 = 2 * sigma * sigma
        var sum: Float = 0
        for i in -radius...radius {
            let x = Float(i)
            let value = exp(-(x * x) / sigma2)
            kernel[i + radius] = value
            sum += value
        }

        if sum > 0 {
            for i in 0..<kernel.count {
                kernel[i] /= sum
            }
        }

        return kernel
    }

    private func gaussianBlur(_ input: [Float], width: Int, height: Int, kernel: [Float]) -> [Float] {
        let radius = kernel.count / 2
        var temp = [Float](repeating: 0, count: width * height)

        // Horizontal pass
        for y in 0..<height {
            let rowStart = y * width
            for x in 0..<width {
                var sum: Float = 0
                for k in -radius...radius {
                    let sampleX = min(width - 1, max(0, x + k))
                    sum += input[rowStart + sampleX] * kernel[k + radius]
                }
                temp[rowStart + x] = sum
            }
        }

        // Vertical pass
        var output = [Float](repeating: 0, count: width * height)
        for x in 0..<width {
            for y in 0..<height {
                var sum: Float = 0
                for k in -radius...radius {
                    let sampleY = min(height - 1, max(0, y + k))
                    sum += temp[sampleY * width + x] * kernel[k + radius]
                }
                output[y * width + x] = sum
            }
        }

        return output
    }
}
