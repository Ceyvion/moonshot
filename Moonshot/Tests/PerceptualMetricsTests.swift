import XCTest
@testable import Moonshot

final class PerceptualMetricsTests: XCTestCase {
    func testBlurProbabilityHigherForBlurredEdge() {
        let width = 64
        let height = 64
        let sharp = stepEdge(width: width, height: height)
        let blurred = boxBlur(sharp, width: width, height: height, radius: 2)

        let mask = MaskBuffer.filled(width: width, height: height, value: 1.0)
        let limb = MaskBuffer.empty(width: width, height: height)
        let evaluator = PerceptualMetricsEvaluator()

        let sharpMetrics = evaluator.evaluate(luma: sharp, width: width, height: height, moonMask: mask, limbRing: limb)
        let blurMetrics = evaluator.evaluate(luma: blurred, width: width, height: height, moonMask: mask, limbRing: limb)

        XCTAssertGreaterThan(blurMetrics.blurProbability, sharpMetrics.blurProbability)
    }

    func testRingingScoreDetectsOvershoot() {
        let width = 64
        let height = 64
        var base = stepEdge(width: width, height: height)
        var ringing = base

        // Add a bright halo on the dark side near the edge.
        for y in 0..<height {
            ringing[y * width + 30] = 0.25
            ringing[y * width + 29] = 0.15
        }

        let mask = MaskBuffer.filled(width: width, height: height, value: 1.0)
        let limb = MaskBuffer.empty(width: width, height: height)
        let evaluator = PerceptualMetricsEvaluator()

        let baseMetrics = evaluator.evaluate(luma: base, width: width, height: height, moonMask: mask, limbRing: limb)
        let ringMetrics = evaluator.evaluate(luma: ringing, width: width, height: height, moonMask: mask, limbRing: limb)

        XCTAssertGreaterThan(ringMetrics.ringingScore, baseMetrics.ringingScore)
    }

    func testNoiseVisibilityIncreasesWithNoise() {
        let width = 64
        let height = 64
        let clean = [Float](repeating: 0.5, count: width * height)
        var noisy = clean

        for i in 0..<noisy.count {
            noisy[i] = clamp01(noisy[i] + (i % 2 == 0 ? 0.03 : -0.03))
        }

        let mask = MaskBuffer.filled(width: width, height: height, value: 1.0)
        let limb = MaskBuffer.empty(width: width, height: height)
        let evaluator = PerceptualMetricsEvaluator()

        let cleanMetrics = evaluator.evaluate(luma: clean, width: width, height: height, moonMask: mask, limbRing: limb)
        let noisyMetrics = evaluator.evaluate(luma: noisy, width: width, height: height, moonMask: mask, limbRing: limb)

        XCTAssertGreaterThan(noisyMetrics.noiseVisibility, cleanMetrics.noiseVisibility)
    }

    func testPhaseContrastLowForUniformDisk() {
        let width = 64
        let height = 64
        let luma = [Float](repeating: 0.7, count: width * height)

        let mask = MaskBuffer.filled(width: width, height: height, value: 1.0)
        let limb = MaskBuffer.empty(width: width, height: height)
        let evaluator = PerceptualMetricsEvaluator()

        let metrics = evaluator.evaluate(luma: luma, width: width, height: height, moonMask: mask, limbRing: limb)

        XCTAssertLessThan(metrics.phaseContrast, 0.01)
    }

    // MARK: - Helpers

    private func stepEdge(width: Int, height: Int) -> [Float] {
        var data = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                data[y * width + x] = x < width / 2 ? 0.0 : 1.0
            }
        }
        return data
    }

    private func boxBlur(_ input: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return input }
        let kernelSize = radius * 2 + 1
        let kernelScale = 1.0 / Float(kernelSize)

        var temp = [Float](repeating: 0, count: width * height)
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

    private func clamp01(_ value: Float) -> Float {
        return min(1, max(0, value))
    }
}
