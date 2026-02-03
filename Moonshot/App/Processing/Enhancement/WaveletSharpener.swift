import Foundation

/// Multi-band sharpening using difference of Gaussians.
final class WaveletSharpener {
    func apply(
        luma: inout [Float],
        width: Int,
        height: Int,
        params: PresetConfiguration.WaveletParameters,
        confidence: MaskBuffer,
        snrMap: MaskBuffer?,
        limbRing: MaskBuffer
    ) {
        guard width > 0, height > 0 else { return }
        guard confidence.width == width, confidence.height == height else { return }
        guard limbRing.width == width, limbRing.height == height else { return }
        if let snrMap, (snrMap.width != width || snrMap.height != height) {
            return
        }

        let fineBlur = gaussianBlur(luma, width: width, height: height, sigma: 1.0)
        let midBlur = gaussianBlur(luma, width: width, height: height, sigma: 2.5)
        let coarseBlur = gaussianBlur(luma, width: width, height: height, sigma: 5.0)

        for i in 0..<luma.count {
            let c = min(1, max(0, confidence.data[i]))
            if c <= 0 { continue }

            if let snrMap, snrMap.data[i] < params.minSNR {
                continue
            }

            let limb = min(1, max(0, limbRing.data[i]))
            let limbFactor = 1 - limb * (1 - params.limbMultiplier)
            let lumaGate = 1 - smoothstep(edge0: params.maxLuma, edge1: params.maxLuma + params.maxLumaFade, x: luma[i])
            let gainScale = pow(c, params.cExponent) * limbFactor * lumaGate
            if gainScale <= 0 { continue }

            let fineDetail = luma[i] - fineBlur[i]
            let midDetail = fineBlur[i] - midBlur[i]
            let coarseDetail = midBlur[i] - coarseBlur[i]

            let adjustment = fineDetail * params.fineGain * gainScale
                + midDetail * params.midGain * gainScale
                + coarseDetail * params.coarseGain * gainScale

            luma[i] = min(1, max(0, luma[i] + adjustment))
        }
    }

    private func gaussianBlur(_ input: [Float], width: Int, height: Int, sigma: Float) -> [Float] {
        let kernel = gaussianKernel1D(sigma: sigma)
        let radius = kernel.count / 2

        var temp = [Float](repeating: 0, count: width * height)
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

    private func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        guard edge1 != edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private func gaussianKernel1D(sigma: Float) -> [Float] {
        return GaussianKernelCache.shared.kernel(sigma: sigma)
    }
}
