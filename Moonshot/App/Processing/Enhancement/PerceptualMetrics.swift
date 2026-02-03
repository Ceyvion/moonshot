import Foundation

struct PerceptualMetrics {
    let blurProbability: Float        // 0..1 (higher = blurrier)
    let ringingScore: Float           // 0..1 (higher = more ringing visibility)
    let noiseVisibility: Float        // 0..1 (higher = more visible noise)
    let localContrast: Float          // 0..1 (higher = more contrast already present)
    let edgeDensity: Float            // 0..1 (fraction of strong edges)
    let phaseContrast: Float          // 0..1 (low = full moon, high = terminator present)
}

/// Evaluates perceptual quality metrics on a downsampled luminance crop.
final class PerceptualMetricsEvaluator {
    private let maxDimension = 512

    func evaluate(
        luma: [Float], width: Int, height: Int,
        moonMask: MaskBuffer, limbRing: MaskBuffer
    ) -> PerceptualMetrics {
        guard width > 0, height > 0, luma.count == width * height else {
            return PerceptualMetrics(
                blurProbability: 1.0,
                ringingScore: 0.0,
                noiseVisibility: 0.0,
                localContrast: 0.0,
                edgeDensity: 0.0,
                phaseContrast: 0.0
            )
        }

        let downsampled = downsampleLuma(luma, width: width, height: height, maxDimension: maxDimension)
        let dsLuma = downsampled.data
        let dsWidth = downsampled.width
        let dsHeight = downsampled.height

        let dsMoonMask = moonMask.resized(toWidth: dsWidth, height: dsHeight)
        let dsLimbRing = limbRing.resized(toWidth: dsWidth, height: dsHeight)

        let gradients = sobelGradients(luma: dsLuma, width: dsWidth, height: dsHeight)

        var maskCount = 0
        var gradientValues: [Float] = []
        gradientValues.reserveCapacity(dsWidth * dsHeight / 4)

        for i in 0..<dsLuma.count {
            if dsMoonMask.data[i] > 0.5 && dsLimbRing.data[i] < 0.5 {
                maskCount += 1
                gradientValues.append(gradients.magnitude[i])
            }
        }

        let edgeThreshold: Float
        if gradientValues.isEmpty {
            edgeThreshold = 0.0
        } else {
            gradientValues.sort()
            let index = Int(Float(gradientValues.count - 1) * 0.9)
            edgeThreshold = gradientValues[max(0, min(index, gradientValues.count - 1))]
        }

        var edgeIndices: [(x: Int, y: Int, gx: Float, gy: Float, mag: Float)] = []
        edgeIndices.reserveCapacity(gradientValues.count / 4)

        var edgeMask = [Bool](repeating: false, count: dsLuma.count)

        for y in 1..<(dsHeight - 1) {
            for x in 1..<(dsWidth - 1) {
                let idx = y * dsWidth + x
                if dsMoonMask.data[idx] <= 0.5 || dsLimbRing.data[idx] >= 0.5 {
                    continue
                }

                let mag = gradients.magnitude[idx]
                if mag >= edgeThreshold && mag > 0 {
                    edgeIndices.append((x, y, gradients.gx[idx], gradients.gy[idx], mag))
                    edgeMask[idx] = true
                }
            }
        }

        let edgeDensity = maskCount > 0 ? Float(edgeIndices.count) / Float(maskCount) : 0

        let meanLuma = meanLuminance(luma: dsLuma, mask: dsMoonMask)
        let localContrast = computeLocalContrast(
            luma: dsLuma,
            width: dsWidth,
            height: dsHeight,
            mask: dsMoonMask,
            meanLuma: meanLuma
        )

        let blurProbability = computeBlurProbability(
            luma: dsLuma,
            width: dsWidth,
            height: dsHeight,
            edges: edgeIndices,
            edgeDensity: edgeDensity
        )

        let ringingScore = computeRingingScore(
            luma: dsLuma,
            width: dsWidth,
            height: dsHeight,
            edges: edgeIndices
        )

        let noiseVisibility = computeNoiseVisibility(
            luma: dsLuma,
            width: dsWidth,
            height: dsHeight,
            moonMask: dsMoonMask,
            edgeMask: edgeMask,
            meanLuma: meanLuma
        )

        let phaseContrast = computePhaseContrast(
            luma: dsLuma,
            width: dsWidth,
            height: dsHeight,
            mask: dsMoonMask
        )

        return PerceptualMetrics(
            blurProbability: clamp01(blurProbability),
            ringingScore: clamp01(ringingScore),
            noiseVisibility: clamp01(noiseVisibility),
            localContrast: clamp01(localContrast),
            edgeDensity: clamp01(edgeDensity),
            phaseContrast: clamp01(phaseContrast)
        )
    }

    // MARK: - Core Metrics

    private func computeLocalContrast(
        luma: [Float], width: Int, height: Int,
        mask: MaskBuffer, meanLuma: Float
    ) -> Float {
        let blurred = gaussianBlur(luma, width: width, height: height, sigma: 4.0)
        var sum: Float = 0
        var count: Int = 0

        for i in 0..<luma.count {
            if mask.data[i] > 0.5 {
                sum += abs(luma[i] - blurred[i])
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let denom = max(meanLuma, 1e-3)
        return min(1, (sum / Float(count)) / denom)
    }

    private func computeBlurProbability(
        luma: [Float], width: Int, height: Int,
        edges: [(x: Int, y: Int, gx: Float, gy: Float, mag: Float)],
        edgeDensity: Float
    ) -> Float {
        guard !edges.isEmpty else { return 1.0 }

        let maxSamples = 1500
        let step = max(1, edges.count / maxSamples)
        let radius = 6

        var sum: Float = 0
        var count: Int = 0

        for i in stride(from: 0, to: edges.count, by: step) {
            let edge = edges[i]
            let mag = edge.mag
            if mag <= 0 { continue }

            let invMag = 1.0 / mag
            let ux = edge.gx * invMag
            let uy = edge.gy * invMag

            var samples = [Float](repeating: 0, count: radius * 2 + 1)
            for offset in -radius...radius {
                let fx = Float(edge.x) + Float(offset) * ux
                let fy = Float(edge.y) + Float(offset) * uy
                samples[offset + radius] = sampleBilinear(luma, width: width, height: height, x: fx, y: fy)
            }

            guard let minIndex = samples.indices.min(by: { samples[$0] < samples[$1] }),
                  let maxIndex = samples.indices.max(by: { samples[$0] < samples[$1] }) else {
                continue
            }

            let minVal = samples[minIndex]
            let maxVal = samples[maxIndex]
            let contrast = maxVal - minVal
            if contrast < 0.02 { continue }

            let low = minVal + 0.1 * contrast
            let high = minVal + 0.9 * contrast

            guard let lowPos = crossingPosition(samples: samples, start: minIndex, end: maxIndex, target: low),
                  let highPos = crossingPosition(samples: samples, start: minIndex, end: maxIndex, target: high) else {
                continue
            }

            let edgeWidth = abs(highPos - lowPos)
            let jnbWidth = 1.0 + 6.0 * exp(-10.0 * contrast)
            let pBlur = 1.0 / (1.0 + exp(-(edgeWidth - jnbWidth)))

            sum += pBlur
            count += 1
        }

        if count == 0 {
            return edgeDensity < 0.02 ? 1.0 : 0.6
        }

        var result = sum / Float(count)
        if edgeDensity < 0.02 {
            result = max(result, 0.8)
        }

        return result
    }

    private func computeRingingScore(
        luma: [Float], width: Int, height: Int,
        edges: [(x: Int, y: Int, gx: Float, gy: Float, mag: Float)]
    ) -> Float {
        guard !edges.isEmpty else { return 0 }

        let maxSamples = 1500
        let step = max(1, edges.count / maxSamples)

        let lumaIntegral = integralImage(luma, width: width, height: height)
        let lumaSqIntegral = integralImage(luma.map { $0 * $0 }, width: width, height: height)

        var ringValues: [Float] = []
        ringValues.reserveCapacity(edges.count / step)

        for i in stride(from: 0, to: edges.count, by: step) {
            let edge = edges[i]
            let mag = edge.mag
            if mag <= 0 { continue }

            let invMag = 1.0 / mag
            let ux = edge.gx * invMag
            let uy = edge.gy * invMag

            let brightSample = sampleBilinear(luma, width: width, height: height, x: Float(edge.x) + ux, y: Float(edge.y) + uy)
            let darkSample = sampleBilinear(luma, width: width, height: height, x: Float(edge.x) - ux, y: Float(edge.y) - uy)

            let direction: Float = brightSample >= darkSample ? -1.0 : 1.0
            let s1 = sampleBilinear(luma, width: width, height: height, x: Float(edge.x) + direction * ux, y: Float(edge.y) + direction * uy)
            let s3 = sampleBilinear(luma, width: width, height: height, x: Float(edge.x) + direction * 3.0 * ux, y: Float(edge.y) + direction * 3.0 * uy)

            let ringAmp = max(0, s1 - s3)
            if ringAmp <= 0 { continue }

            let activity = localStdDev(
                x: edge.x,
                y: edge.y,
                radius: 2,
                integral: lumaIntegral,
                integralSq: lumaSqIntegral,
                width: width,
                height: height
            )

            let ringVisibility = ringAmp / (activity + 0.02)
            ringValues.append(ringVisibility)
        }

        guard !ringValues.isEmpty else { return 0 }

        ringValues.sort()
        let start = Int(Float(ringValues.count) * 0.9)
        let slice = ringValues[start..<ringValues.count]
        let avg = slice.reduce(0, +) / Float(slice.count)
        return min(1, avg)
    }

    private func computeNoiseVisibility(
        luma: [Float], width: Int, height: Int,
        moonMask: MaskBuffer, edgeMask: [Bool], meanLuma: Float
    ) -> Float {
        let blurred = gaussianBlur(luma, width: width, height: height, sigma: 1.0)
        var residual = [Float](repeating: 0, count: luma.count)
        for i in 0..<luma.count {
            residual[i] = luma[i] - blurred[i]
        }

        let residualIntegral = integralImage(residual, width: width, height: height)
        let residualSqIntegral = integralImage(residual.map { $0 * $0 }, width: width, height: height)

        let jnd = clamp(0.02 + 0.15 * sqrt(max(0, meanLuma)), min: 0.02, max: 0.2)

        var sum: Float = 0
        var count: Int = 0

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if moonMask.data[idx] <= 0.5 || edgeMask[idx] { continue }

                let noiseStd = localStdDev(
                    x: x,
                    y: y,
                    radius: 2,
                    integral: residualIntegral,
                    integralSq: residualSqIntegral,
                    width: width,
                    height: height
                )

                sum += noiseStd / (jnd + 1e-3)
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        return min(1, sum / Float(count))
    }

    private func computePhaseContrast(
        luma: [Float], width: Int, height: Int,
        mask: MaskBuffer
    ) -> Float {
        guard width > 0, height > 0 else { return 0 }

        var sumX: Float = 0
        var count: Float = 0
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask.data[idx] > 0.5 {
                    sumX += Float(x)
                    count += 1
                }
            }
        }

        guard count > 0 else { return 0 }
        let centerX = sumX / count

        var sumLeft: Float = 0
        var sumRight: Float = 0
        var countLeft: Float = 0
        var countRight: Float = 0
        var sumAll: Float = 0

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if mask.data[idx] <= 0.5 {
                    continue
                }

                let value = luma[idx]
                sumAll += value

                if Float(x) < centerX {
                    sumLeft += value
                    countLeft += 1
                } else {
                    sumRight += value
                    countRight += 1
                }
            }
        }

        guard countLeft > 0, countRight > 0 else { return 0 }
        let meanAll = sumAll / count
        if meanAll <= 1e-4 { return 0 }

        let meanLeft = sumLeft / countLeft
        let meanRight = sumRight / countRight
        return abs(meanLeft - meanRight) / meanAll
    }

    // MARK: - Helpers

    private struct DownsampledLuma {
        let data: [Float]
        let width: Int
        let height: Int
    }

    private func downsampleLuma(_ luma: [Float], width: Int, height: Int, maxDimension: Int) -> DownsampledLuma {
        let maxSide = max(width, height)
        guard maxSide > maxDimension else {
            return DownsampledLuma(data: luma, width: width, height: height)
        }

        let scale = Float(maxDimension) / Float(maxSide)
        let newWidth = max(1, Int(round(Float(width) * scale)))
        let newHeight = max(1, Int(round(Float(height) * scale)))

        var output = [Float](repeating: 0, count: newWidth * newHeight)

        for y in 0..<newHeight {
            let srcY = Float(y) / Float(max(1, newHeight - 1)) * Float(height - 1)
            let y0 = Int(floor(srcY))
            let y1 = min(height - 1, y0 + 1)
            let fy = srcY - Float(y0)

            for x in 0..<newWidth {
                let srcX = Float(x) / Float(max(1, newWidth - 1)) * Float(width - 1)
                let x0 = Int(floor(srcX))
                let x1 = min(width - 1, x0 + 1)
                let fx = srcX - Float(x0)

                let v00 = luma[y0 * width + x0]
                let v10 = luma[y0 * width + x1]
                let v01 = luma[y1 * width + x0]
                let v11 = luma[y1 * width + x1]

                let v0 = v00 * (1 - fx) + v10 * fx
                let v1 = v01 * (1 - fx) + v11 * fx
                let v = v0 * (1 - fy) + v1 * fy

                output[y * newWidth + x] = v
            }
        }

        return DownsampledLuma(data: output, width: newWidth, height: newHeight)
    }

    private struct GradientResult {
        let gx: [Float]
        let gy: [Float]
        let magnitude: [Float]
    }

    private func sobelGradients(luma: [Float], width: Int, height: Int) -> GradientResult {
        var gx = [Float](repeating: 0, count: width * height)
        var gy = [Float](repeating: 0, count: width * height)
        var mag = [Float](repeating: 0, count: width * height)

        guard width > 2, height > 2 else {
            return GradientResult(gx: gx, gy: gy, magnitude: mag)
        }

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x

                let tl = luma[idx - width - 1]
                let t = luma[idx - width]
                let tr = luma[idx - width + 1]
                let l = luma[idx - 1]
                let r = luma[idx + 1]
                let bl = luma[idx + width - 1]
                let b = luma[idx + width]
                let br = luma[idx + width + 1]

                let gxVal = -tl - 2 * l - bl + tr + 2 * r + br
                let gyVal = -tl - 2 * t - tr + bl + 2 * b + br

                gx[idx] = gxVal
                gy[idx] = gyVal
                mag[idx] = sqrt(gxVal * gxVal + gyVal * gyVal)
            }
        }

        return GradientResult(gx: gx, gy: gy, magnitude: mag)
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

    private func gaussianKernel1D(sigma: Float) -> [Float] {
        return GaussianKernelCache.shared.kernel(sigma: sigma)
    }

    private func sampleBilinear(_ data: [Float], width: Int, height: Int, x: Float, y: Float) -> Float {
        let clampedX = min(Float(width - 1), max(0, x))
        let clampedY = min(Float(height - 1), max(0, y))

        let x0 = Int(floor(clampedX))
        let y0 = Int(floor(clampedY))
        let x1 = min(width - 1, x0 + 1)
        let y1 = min(height - 1, y0 + 1)

        let fx = clampedX - Float(x0)
        let fy = clampedY - Float(y0)

        let v00 = data[y0 * width + x0]
        let v10 = data[y0 * width + x1]
        let v01 = data[y1 * width + x0]
        let v11 = data[y1 * width + x1]

        let v0 = v00 * (1 - fx) + v10 * fx
        let v1 = v01 * (1 - fx) + v11 * fx
        return v0 * (1 - fy) + v1 * fy
    }

    private func crossingPosition(samples: [Float], start: Int, end: Int, target: Float) -> Float? {
        guard start != end else { return nil }
        let step = start < end ? 1 : -1
        var i = start
        while i != end {
            let next = i + step
            let v0 = samples[i]
            let v1 = samples[next]
            if (v0 - target) * (v1 - target) <= 0 {
                let denom = v1 - v0
                let t = abs(denom) < 1e-6 ? 0.0 : (target - v0) / denom
                return Float(i) + t * Float(step)
            }
            i = next
        }
        return nil
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

    private func localStdDev(
        x: Int,
        y: Int,
        radius: Int,
        integral: [Float],
        integralSq: [Float],
        width: Int,
        height: Int
    ) -> Float {
        let x0 = max(0, x - radius)
        let y0 = max(0, y - radius)
        let x1 = min(width - 1, x + radius)
        let y1 = min(height - 1, y + radius)

        let area = Float((x1 - x0 + 1) * (y1 - y0 + 1))
        let sum = rectSum(integral: integral, width: width, x0: x0, y0: y0, x1: x1, y1: y1)
        let sumSq = rectSum(integral: integralSq, width: width, x0: x0, y0: y0, x1: x1, y1: y1)

        let mean = sum / area
        let meanSq = sumSq / area
        return sqrt(max(0, meanSq - mean * mean))
    }

    private func rectSum(integral: [Float], width: Int, x0: Int, y0: Int, x1: Int, y1: Int) -> Float {
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

    private func meanLuminance(luma: [Float], mask: MaskBuffer) -> Float {
        var sum: Float = 0
        var count: Int = 0
        for i in 0..<luma.count {
            if mask.data[i] > 0.5 {
                sum += luma[i]
                count += 1
            }
        }
        return count > 0 ? sum / Float(count) : 0
    }

    private func clamp01(_ value: Float) -> Float {
        return min(1, max(0, value))
    }

    private func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        return max(minValue, min(maxValue, value))
    }
}
