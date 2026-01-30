import UIKit
import Accelerate
import CoreGraphics

/// Orchestrates moon detection from an input image.
/// Produces circle fit, masks, and confidence scores.
final class MoonDetector {

    // MARK: - Configuration

    struct Configuration {
        /// Minimum blob area as fraction of image area
        let minBlobAreaFraction: Float = 0.001

        /// Maximum blob area as fraction of image area
        let maxBlobAreaFraction: Float = 0.8

        /// Minimum circularity to consider as moon candidate
        let minCircularity: Float = 0.6

        /// Feather width for moon mask (pixels)
        let maskFeatherWidth: Float = 3.0

        /// Width of limb ring for edge protection (pixels)
        let limbRingWidth: Float = 9.0

        /// Padding factor for crop rect (1.0 = no padding)
        let cropPaddingFactor: Float = 1.3
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let luminanceExtractor: LuminanceExtractor
    private let thresholdAnalyzer: ThresholdAnalyzer
    private let componentAnalyzer: ConnectedComponentsAnalyzer
    private let circleFitter: CircleFitter
    private let confidenceScorer: ConfidenceScorer
    private let maskGenerator: MaskGenerator

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.luminanceExtractor = LuminanceExtractor()
        self.thresholdAnalyzer = ThresholdAnalyzer()
        self.componentAnalyzer = ConnectedComponentsAnalyzer()
        self.circleFitter = CircleFitter()
        self.confidenceScorer = ConfidenceScorer()
        self.maskGenerator = MaskGenerator(
            featherWidth: configuration.maskFeatherWidth,
            limbRingWidth: configuration.limbRingWidth
        )
    }

    // MARK: - Detection

    /// Detect moon in the given image.
    /// Returns nil if detection fails.
    func detect(in image: UIImage) async throws -> MoonDetectionResult? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        return try await detect(in: cgImage)
    }

    /// Detect moon in the given CGImage.
    func detect(in cgImage: CGImage) async throws -> MoonDetectionResult? {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // 1. Extract luminance
        guard let luminance = luminanceExtractor.extract(from: cgImage) else {
            return nil
        }

        // 2. Analyze and threshold
        let thresholdResult = thresholdAnalyzer.analyze(luminance: luminance, imageSize: imageSize)

        // 3. Find connected components (blobs)
        let minArea = Int(Float(cgImage.width * cgImage.height) * configuration.minBlobAreaFraction)
        let maxArea = Int(Float(cgImage.width * cgImage.height) * configuration.maxBlobAreaFraction)

        let blobs = componentAnalyzer.findBlobs(
            in: thresholdResult.binaryMask,
            minArea: minArea,
            maxArea: maxArea
        )

        // 4. Find best moon candidate
        guard let bestBlob = findBestCandidate(blobs: blobs) else {
            return nil
        }

        // 5. Fit circle to edge points
        guard let circle = circleFitter.fit(edgePoints: bestBlob.edgePoints) else {
            return nil
        }

        // 6. Score detection confidence
        let confidence = confidenceScorer.score(
            circle: circle,
            blob: bestBlob,
            luminance: luminance,
            imageSize: imageSize
        )

        // 7. Generate masks
        let masks = maskGenerator.generate(
            circle: circle,
            imageSize: imageSize,
            paddingFactor: configuration.cropPaddingFactor
        )

        // 8. Calculate clipped highlight fraction
        let clippedFraction = calculateClippedFraction(
            luminance: luminance,
            circle: circle
        )

        return MoonDetectionResult(
            circle: circle,
            cropRect: masks.cropRect,
            moonMask: masks.moonMask,
            limbRingMask: masks.limbRingMask,
            confidence: confidence,
            clippedHighlightFraction: clippedFraction
        )
    }

    /// Fast detection for preview/tracking (lower resolution)
    func detectFast(in cgImage: CGImage, targetWidth: Int = 512) async throws -> MoonDetectionResult? {
        // Downsample luminance for speed
        guard let luminance = luminanceExtractor.extractDownsampled(from: cgImage, targetWidth: targetWidth) else {
            return try await detect(in: cgImage)
        }

        let imageSize = CGSize(width: luminance.width, height: luminance.height)

        // 1. Analyze and threshold
        let thresholdResult = thresholdAnalyzer.analyze(luminance: luminance, imageSize: imageSize)

        // 2. Find connected components (blobs)
        let minArea = Int(Float(luminance.width * luminance.height) * configuration.minBlobAreaFraction)
        let maxArea = Int(Float(luminance.width * luminance.height) * configuration.maxBlobAreaFraction)

        let blobs = componentAnalyzer.findBlobs(
            in: thresholdResult.binaryMask,
            minArea: minArea,
            maxArea: maxArea
        )

        // 3. Find best moon candidate
        guard let bestBlob = findBestCandidate(blobs: blobs) else {
            return nil
        }

        // 4. Fit circle to edge points
        guard let circle = circleFitter.fit(edgePoints: bestBlob.edgePoints) else {
            return nil
        }

        // 5. Score detection confidence
        let confidence = confidenceScorer.score(
            circle: circle,
            blob: bestBlob,
            luminance: luminance,
            imageSize: imageSize
        )

        // 6. Generate masks (at downsampled size)
        let masks = maskGenerator.generate(
            circle: circle,
            imageSize: imageSize,
            paddingFactor: configuration.cropPaddingFactor
        )

        // 7. Calculate clipped highlight fraction
        let clippedFraction = calculateClippedFraction(
            luminance: luminance,
            circle: circle
        )

        let result = MoonDetectionResult(
            circle: circle,
            cropRect: masks.cropRect,
            moonMask: masks.moonMask,
            limbRingMask: masks.limbRingMask,
            confidence: confidence,
            clippedHighlightFraction: clippedFraction
        )

        // Scale results back to original resolution
        let scale = CGFloat(cgImage.width) / CGFloat(luminance.width)
        return scaleResult(result, by: scale, originalSize: CGSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Private Helpers

    private func findBestCandidate(blobs: [BlobInfo]) -> BlobInfo? {
        // Filter by circularity and find the best
        let candidates = blobs.filter { $0.circularity >= configuration.minCircularity }

        // Prefer larger, more circular blobs
        return candidates.max { a, b in
            let scoreA = Float(a.area) * a.circularity
            let scoreB = Float(b.area) * b.circularity
            return scoreA < scoreB
        }
    }

    private func calculateClippedFraction(luminance: LuminanceBuffer, circle: FittedCircle) -> Float {
        var clippedCount = 0
        var totalCount = 0

        let centerX = Int(circle.center.x)
        let centerY = Int(circle.center.y)
        let radiusInt = Int(circle.radius)

        for y in max(0, centerY - radiusInt)..<min(luminance.height, centerY + radiusInt) {
            for x in max(0, centerX - radiusInt)..<min(luminance.width, centerX + radiusInt) {
                let dx = Float(x - centerX)
                let dy = Float(y - centerY)
                let dist = sqrt(dx * dx + dy * dy)

                if dist <= Float(circle.radius) {
                    totalCount += 1
                    let value = luminance.value(at: x, y: y)
                    if value > 0.98 {
                        clippedCount += 1
                    }
                }
            }
        }

        guard totalCount > 0 else { return 0 }
        return Float(clippedCount) / Float(totalCount)
    }

    private func scaleResult(_ result: MoonDetectionResult, by scale: CGFloat, originalSize: CGSize) -> MoonDetectionResult {
        let scaledCircle = FittedCircle(
            center: CGPoint(x: result.circle.center.x * scale, y: result.circle.center.y * scale),
            radius: result.circle.radius * scale,
            residualError: result.circle.residualError * scale
        )

        // Regenerate masks at full resolution
        let masks = maskGenerator.generate(
            circle: scaledCircle,
            imageSize: originalSize,
            paddingFactor: configuration.cropPaddingFactor
        )

        return MoonDetectionResult(
            circle: scaledCircle,
            cropRect: masks.cropRect,
            moonMask: masks.moonMask,
            limbRingMask: masks.limbRingMask,
            confidence: result.confidence,
            clippedHighlightFraction: result.clippedHighlightFraction
        )
    }
}
