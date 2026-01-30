import Foundation
import CoreGraphics

/// Result of threshold analysis
struct ThresholdResult {
    let binaryMask: BinaryMask
    let optimalThreshold: Float
}

/// Binary mask for blob detection
struct BinaryMask {
    let width: Int
    let height: Int
    let data: [Bool]

    func value(at x: Int, y: Int) -> Bool {
        guard x >= 0 && x < width && y >= 0 && y < height else { return false }
        return data[y * width + x]
    }
}

/// Analyzes luminance to find optimal threshold for moon detection
final class ThresholdAnalyzer {

    /// Analyze luminance and produce binary mask
    func analyze(luminance: LuminanceBuffer, imageSize: CGSize) -> ThresholdResult {
        // For moon photos, we want to find the bright region
        // Use a high percentile threshold since moon is typically the brightest object

        // Compute histogram
        let histogram = computeHistogram(luminance: luminance, bins: 256)

        // Find optimal threshold using adaptive method
        let threshold = findOptimalThreshold(histogram: histogram, luminance: luminance)

        // Create binary mask
        let binaryMask = createBinaryMask(luminance: luminance, threshold: threshold)

        return ThresholdResult(
            binaryMask: binaryMask,
            optimalThreshold: threshold
        )
    }

    // MARK: - Private

    private func computeHistogram(luminance: LuminanceBuffer, bins: Int) -> [Int] {
        var histogram = [Int](repeating: 0, count: bins)

        for value in luminance.data {
            let bin = min(bins - 1, max(0, Int(value * Float(bins))))
            histogram[bin] += 1
        }

        return histogram
    }

    private func findOptimalThreshold(histogram: [Int], luminance: LuminanceBuffer) -> Float {
        let totalPixels = luminance.data.count

        // For moon photos, start from high values and work down
        // We're looking for a bright, compact region

        // Method: Find the threshold that isolates the brightest ~10% as a starting point,
        // then refine using Otsu's method in that range

        // Find 90th percentile as starting point
        var cumulative = 0
        var startBin = histogram.count - 1

        for i in (0..<histogram.count).reversed() {
            cumulative += histogram[i]
            if Float(cumulative) / Float(totalPixels) > 0.15 {
                startBin = i
                break
            }
        }

        // Apply Otsu's method in the upper range
        let threshold = otsuThreshold(histogram: histogram, minBin: startBin / 2)

        return threshold
    }

    private func otsuThreshold(histogram: [Int], minBin: Int = 0) -> Float {
        let bins = histogram.count
        var total = 0
        var sumTotal: Float = 0

        for i in minBin..<bins {
            total += histogram[i]
            sumTotal += Float(i) * Float(histogram[i])
        }

        guard total > 0 else { return 0.5 }

        var sumBackground: Float = 0
        var weightBackground = 0
        var maxVariance: Float = 0
        var threshold = minBin

        for i in minBin..<bins {
            weightBackground += histogram[i]
            if weightBackground == 0 { continue }

            let weightForeground = total - weightBackground
            if weightForeground == 0 { break }

            sumBackground += Float(i) * Float(histogram[i])

            let meanBackground = sumBackground / Float(weightBackground)
            let meanForeground = (sumTotal - sumBackground) / Float(weightForeground)

            let variance = Float(weightBackground) * Float(weightForeground) *
                           (meanBackground - meanForeground) * (meanBackground - meanForeground)

            if variance > maxVariance {
                maxVariance = variance
                threshold = i
            }
        }

        return Float(threshold) / Float(bins)
    }

    private func createBinaryMask(luminance: LuminanceBuffer, threshold: Float) -> BinaryMask {
        var data = [Bool](repeating: false, count: luminance.data.count)

        for i in 0..<luminance.data.count {
            data[i] = luminance.data[i] >= threshold
        }

        return BinaryMask(width: luminance.width, height: luminance.height, data: data)
    }
}
