import Foundation

/// Metrics describing enhancement behavior for logging and QA.
struct EnhancementMetrics {
    let circleConfidence: Float
    let clippedFraction: Float
    let medianC: Float
    let sharpnessScore: Float
    let overshootMetric: Float
    let blurProbability: Float
    let ringingScore: Float
    let noiseVisibility: Float
    let localContrast: Float
    let phaseContrast: Float
}
