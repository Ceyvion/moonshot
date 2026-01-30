import Foundation

struct ConfidenceMapResult {
    let map: MaskBuffer
    let medianC: Float
    let snrMap: MaskBuffer?
}

/// Builds a confidence map based on gradient SNR and limb protection.
final class ConfidenceMapBuilder {
    func build(
        luma: [Float],
        width: Int,
        height: Int,
        moonMask: MaskBuffer,
        limbRing: MaskBuffer
    ) -> ConfidenceMapResult {
        guard width > 0, height > 0 else {
            return ConfidenceMapResult(map: .empty(width: width, height: height), medianC: 0, snrMap: nil)
        }

        let noise = estimateNoise(luma: luma, width: width, height: height, moonMask: moonMask)
        let gradient = sobelGradient(luma: luma, width: width, height: height)

        var snrData = [Float](repeating: 0, count: width * height)
        let denom = max(noise, 1e-3)
        for i in 0..<snrData.count {
            snrData[i] = gradient[i] / denom
        }

        var cData = [Float](repeating: 0, count: width * height)
        for i in 0..<cData.count {
            let snr = snrData[i]
            var c = (snr - 2.0) / 6.0
            c = max(0, min(1, c))

            let limb = min(1, max(0, limbRing.data[i]))
            c *= (1.0 - limb * 0.75)
            c *= min(1, max(0, moonMask.data[i]))
            cData[i] = c
        }

        let median = medianConfidence(values: cData, moonMask: moonMask)

        return ConfidenceMapResult(
            map: MaskBuffer(width: width, height: height, data: cData),
            medianC: median,
            snrMap: MaskBuffer(width: width, height: height, data: snrData)
        )
    }

    private func estimateNoise(luma: [Float], width: Int, height: Int, moonMask: MaskBuffer) -> Float {
        var sum: Float = 0
        var sumSq: Float = 0
        var count = 0

        for i in 0..<luma.count {
            if moonMask.data[i] > 0.05 { continue }
            let value = luma[i]
            sum += value
            sumSq += value * value
            count += 1
        }

        if count < 64 {
            sum = 0
            sumSq = 0
            count = 0
            for value in luma {
                sum += value
                sumSq += value * value
                count += 1
            }
        }

        guard count > 1 else { return 0.01 }

        let mean = sum / Float(count)
        let variance = max(0, sumSq / Float(count) - mean * mean)
        return max(0.001, sqrt(variance))
    }

    private func sobelGradient(luma: [Float], width: Int, height: Int) -> [Float] {
        var output = [Float](repeating: 0, count: width * height)

        guard width > 2, height > 2 else { return output }

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

                let gx = -tl - 2 * l - bl + tr + 2 * r + br
                let gy = -tl - 2 * t - tr + bl + 2 * b + br

                output[idx] = sqrt(gx * gx + gy * gy)
            }
        }

        return output
    }

    private func medianConfidence(values: [Float], moonMask: MaskBuffer) -> Float {
        var samples: [Float] = []
        samples.reserveCapacity(values.count / 2)

        for i in 0..<values.count {
            if moonMask.data[i] > 0.5 {
                samples.append(values[i])
            }
        }

        if samples.isEmpty {
            samples = values
        }

        samples.sort()
        return samples[samples.count / 2]
    }
}
