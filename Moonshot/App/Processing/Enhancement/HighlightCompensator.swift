import Foundation

/// Softens clipped highlight regions without inventing detail.
final class HighlightCompensator {
    func apply(
        luma: inout [Float],
        width: Int,
        height: Int,
        moonMask: MaskBuffer,
        clipStart: Float,
        strength: Float
    ) {
        guard width > 0, height > 0 else { return }
        guard luma.count == width * height else { return }
        guard moonMask.width == width, moonMask.height == height else { return }
        guard strength > 0 else { return }

        let clippedStart = min(1, max(0, clipStart))
        let clippedStrength = min(1, max(0, strength))

        var clipMask = [Float](repeating: 0, count: luma.count)
        for i in 0..<luma.count {
            let t = smoothstep(edge0: clippedStart, edge1: 1.0, x: luma[i])
            clipMask[i] = t * moonMask.data[i]
        }

        let blurredMask = boxBlurIntegral(clipMask, width: width, height: height, radius: 3)

        for i in 0..<luma.count {
            let t = min(1, max(0, blurredMask[i]))
            if t <= 0 { continue }

            let value = luma[i]
            let compressed = clippedStart + (value - clippedStart) * (1 - clippedStrength)
            luma[i] = value * (1 - t) + compressed * t
        }
    }

    private func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        guard edge1 != edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
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
}
