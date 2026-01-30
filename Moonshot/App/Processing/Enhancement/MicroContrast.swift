import Foundation

/// Large-radius local contrast enhancement, gated by confidence and limb protection.
final class MicroContrast {
    func apply(
        luma: inout [Float],
        width: Int,
        height: Int,
        params: PresetConfiguration.MicroContrastParameters,
        confidence: MaskBuffer,
        limbRing: MaskBuffer
    ) {
        guard width > 0, height > 0 else { return }
        guard confidence.width == width, confidence.height == height else { return }
        guard limbRing.width == width, limbRing.height == height else { return }
        guard params.radius > 0, params.strength > 0 else { return }

        let maxSide = max(width, height)
        if maxSide > 1024 || params.radius >= 16 {
            applyDownsampled(
                luma: &luma,
                width: width,
                height: height,
                params: params,
                confidence: confidence,
                limbRing: limbRing,
                maxDimension: 512
            )
            return
        }

        let blur = boxBlurIntegral(luma, width: width, height: height, radius: params.radius)
        let exclusionMask = dilateSeparable(mask: limbRing, width: width, height: height, radius: params.limbExclusionPixels)

        for i in 0..<luma.count {
            if confidence.data[i] < params.minC { continue }
            if exclusionMask[i] > 0.1 { continue }
            if luma[i] > params.maxLuma { continue }

            let detail = luma[i] - blur[i]
            luma[i] = min(1, max(0, luma[i] + detail * params.strength))
        }
    }

    func applyDownsampled(
        luma: inout [Float],
        width: Int,
        height: Int,
        params: PresetConfiguration.MicroContrastParameters,
        confidence: MaskBuffer,
        limbRing: MaskBuffer,
        maxDimension: Int = 512
    ) {
        guard width > 0, height > 0 else { return }
        guard confidence.width == width, confidence.height == height else { return }
        guard limbRing.width == width, limbRing.height == height else { return }
        guard params.radius > 0, params.strength > 0 else { return }

        let maxSide = max(width, height)
        guard maxSide > 0 else { return }
        let scale = min(1.0, Float(maxDimension) / Float(maxSide))
        let dsWidth = max(1, Int(round(Float(width) * scale)))
        let dsHeight = max(1, Int(round(Float(height) * scale)))

        if dsWidth == width && dsHeight == height {
            let blur = boxBlurIntegral(luma, width: width, height: height, radius: params.radius)
            let exclusionMask = dilateSeparable(mask: limbRing, width: width, height: height, radius: params.limbExclusionPixels)
            for i in 0..<luma.count {
                if confidence.data[i] < params.minC { continue }
                if exclusionMask[i] > 0.1 { continue }
                if luma[i] > params.maxLuma { continue }
                let detail = luma[i] - blur[i]
                luma[i] = min(1, max(0, luma[i] + detail * params.strength))
            }
            return
        }

        let downsampledLuma = resizeBilinear(luma, width: width, height: height, newWidth: dsWidth, newHeight: dsHeight)
        let downsampledLimb = resizeBilinear(limbRing.data, width: width, height: height, newWidth: dsWidth, newHeight: dsHeight)

        let scaledRadius = max(1, Int(round(Float(params.radius) * scale)))
        let blur = boxBlurIntegral(downsampledLuma, width: dsWidth, height: dsHeight, radius: scaledRadius)
        var detailBand = [Float](repeating: 0, count: downsampledLuma.count)
        for i in 0..<downsampledLuma.count {
            detailBand[i] = downsampledLuma[i] - blur[i]
        }

        let scaledExclusion = max(0, Int(round(Float(params.limbExclusionPixels) * scale)))
        let exclusionLow = dilateSeparable(
            mask: MaskBuffer(width: dsWidth, height: dsHeight, data: downsampledLimb),
            width: dsWidth,
            height: dsHeight,
            radius: scaledExclusion
        )

        let detailUpsampled = resizeBilinear(detailBand, width: dsWidth, height: dsHeight, newWidth: width, newHeight: height)
        let exclusionMask = resizeBilinear(exclusionLow, width: dsWidth, height: dsHeight, newWidth: width, newHeight: height)

        for i in 0..<luma.count {
            if confidence.data[i] < params.minC { continue }
            if exclusionMask[i] > 0.1 { continue }
            if luma[i] > params.maxLuma { continue }

            let detail = detailUpsampled[i]
            luma[i] = min(1, max(0, luma[i] + detail * params.strength))
        }
    }

    private func boxBlurIntegral(_ input: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return input }
        let integral = integralImage(input, width: width, height: height)
        var output = [Float](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let x0 = max(0, x - radius)
                let y0 = max(0, y - radius)
                let x1 = min(width - 1, x + radius)
                let y1 = min(height - 1, y + radius)

                let area = Float((x1 - x0 + 1) * (y1 - y0 + 1))
                let sum = rectSum(integral, width: width, x0: x0, y0: y0, x1: x1, y1: y1)
                output[y * width + x] = sum / area
            }
        }

        return output
    }

    private func dilateSeparable(mask: MaskBuffer, width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return mask.data }

        var temp = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var maxVal: Float = 0
                for kx in -radius...radius {
                    let sampleX = min(width - 1, max(0, x + kx))
                    let value = mask.data[y * width + sampleX]
                    if value > maxVal { maxVal = value }
                }
                temp[y * width + x] = maxVal
            }
        }

        var output = [Float](repeating: 0, count: width * height)
        for x in 0..<width {
            for y in 0..<height {
                var maxVal: Float = 0
                for ky in -radius...radius {
                    let sampleY = min(height - 1, max(0, y + ky))
                    let value = temp[sampleY * width + x]
                    if value > maxVal { maxVal = value }
                }
                output[y * width + x] = maxVal
            }
        }

        return output
    }

    private func integralImage(_ data: [Float], width: Int, height: Int) -> [Float] {
        let stride = width + 1
        var integral = [Float](repeating: 0, count: stride * (height + 1))

        for y in 0..<height {
            var rowSum: Float = 0
            for x in 0..<width {
                rowSum += data[y * width + x]
                let idx = (y + 1) * stride + (x + 1)
                integral[idx] = integral[idx - stride] + rowSum
            }
        }

        return integral
    }

    private func rectSum(_ integral: [Float], width: Int, x0: Int, y0: Int, x1: Int, y1: Int) -> Float {
        let stride = width + 1
        let ax = x0
        let ay = y0
        let bx = x1 + 1
        let by = y1 + 1

        let idxA = ay * stride + ax
        let idxB = ay * stride + bx
        let idxC = by * stride + ax
        let idxD = by * stride + bx

        return integral[idxD] - integral[idxB] - integral[idxC] + integral[idxA]
    }

    private func resizeBilinear(_ input: [Float], width: Int, height: Int, newWidth: Int, newHeight: Int) -> [Float] {
        guard width > 0, height > 0, newWidth > 0, newHeight > 0 else {
            return []
        }
        if width == newWidth && height == newHeight {
            return input
        }

        var output = [Float](repeating: 0, count: newWidth * newHeight)
        let scaleX = Float(width - 1) / Float(max(1, newWidth - 1))
        let scaleY = Float(height - 1) / Float(max(1, newHeight - 1))

        for y in 0..<newHeight {
            let srcY = Float(y) * scaleY
            let y0 = Int(floor(srcY))
            let y1 = min(height - 1, y0 + 1)
            let fy = srcY - Float(y0)

            for x in 0..<newWidth {
                let srcX = Float(x) * scaleX
                let x0 = Int(floor(srcX))
                let x1 = min(width - 1, x0 + 1)
                let fx = srcX - Float(x0)

                let v00 = input[y0 * width + x0]
                let v10 = input[y0 * width + x1]
                let v01 = input[y1 * width + x0]
                let v11 = input[y1 * width + x1]

                let v0 = v00 * (1 - fx) + v10 * fx
                let v1 = v01 * (1 - fx) + v11 * fx
                output[y * newWidth + x] = v0 * (1 - fy) + v1 * fy
            }
        }

        return output
    }
}
