import Foundation
import CoreGraphics

/// Scores detection confidence based on multiple factors
final class ConfidenceScorer {

    /// Score the detection confidence
    func score(
        circle: FittedCircle,
        blob: BlobInfo,
        luminance: LuminanceBuffer,
        imageSize: CGSize
    ) -> DetectionConfidence {

        // 1. Fit quality: how well the circle matches the edge
        let fitQuality = scoreFitQuality(circle: circle)

        // 2. Size score: penalize very small or very large moons
        let sizeScore = scoreSizeRatio(circle: circle, imageSize: imageSize)

        // 3. Brightness consistency: moon should be relatively uniform
        let brightnessConsistency = scoreBrightnessConsistency(
            luminance: luminance,
            circle: circle
        )

        // 4. Circularity from blob detection
        let circularity = blob.circularity

        // Combined confidence
        // Weighted combination favoring fit quality and circularity
        let confidence = 0.35 * fitQuality +
                        0.25 * circularity +
                        0.20 * sizeScore +
                        0.20 * brightnessConsistency

        return DetectionConfidence(
            circleConfidence: max(0, min(1, confidence)),
            fitQuality: fitQuality,
            sizeScore: sizeScore,
            brightnessConsistency: brightnessConsistency,
            circularity: circularity
        )
    }

    // MARK: - Private Scoring Functions

    private func scoreFitQuality(circle: FittedCircle) -> Float {
        // Lower residual error = better fit
        // Normalize by radius (error should be small relative to radius)
        let normalizedError = Float(circle.residualError / circle.radius)

        // Score decreases with error
        // Perfect fit (0 error) = 1.0
        // 5% error = ~0.5
        let score = exp(-normalizedError * 20)

        return max(0, min(1, score))
    }

    private func scoreSizeRatio(circle: FittedCircle, imageSize: CGSize) -> Float {
        // Moon diameter as fraction of image width
        let sizeRatio = Float(circle.radius * 2 / imageSize.width)

        // Ideal range: 5% to 60% of image width
        // Very small moons (< 3%) lack detail
        // Very large moons (> 80%) may be cropped or filling frame

        if sizeRatio < 0.03 {
            return 0.3  // Too small, but still valid
        } else if sizeRatio > 0.80 {
            return 0.4  // Too large, may have issues
        } else if sizeRatio >= 0.05 && sizeRatio <= 0.60 {
            return 1.0  // Ideal range
        } else if sizeRatio < 0.05 {
            // Linearly interpolate from 0.3 at 3% to 1.0 at 5%
            return 0.3 + (sizeRatio - 0.03) / 0.02 * 0.7
        } else {
            // Linearly interpolate from 1.0 at 60% to 0.4 at 80%
            return 1.0 - (sizeRatio - 0.60) / 0.20 * 0.6
        }
    }

    private func scoreBrightnessConsistency(luminance: LuminanceBuffer, circle: FittedCircle) -> Float {
        // Calculate coefficient of variation (std/mean) within the moon
        let mean = luminance.meanInCircle(center: circle.center, radius: circle.radius * 0.9)
        let std = luminance.stdInCircle(center: circle.center, radius: circle.radius * 0.9)

        guard mean > 0.01 else { return 0.5 }

        let cv = std / mean

        // Moon should have some variation (maria, craters) but not too much
        // Typical CV for good moon photo: 0.1 to 0.4
        // Too low: possibly overexposed/clipped
        // Too high: might not be moon or has clouds

        if cv < 0.05 {
            return 0.4  // Very uniform, possibly clipped
        } else if cv > 0.6 {
            return 0.3  // Too variable, might not be moon
        } else if cv >= 0.1 && cv <= 0.4 {
            return 1.0  // Good range
        } else if cv < 0.1 {
            return 0.4 + (cv - 0.05) / 0.05 * 0.6
        } else {
            return 1.0 - (cv - 0.4) / 0.2 * 0.7
        }
    }
}
