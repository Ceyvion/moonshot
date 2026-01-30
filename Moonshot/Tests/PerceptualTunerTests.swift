import XCTest
@testable import Moonshot

final class PerceptualTunerTests: XCTestCase {
    func testTunerReducesFineGainOnRinging() {
        let preset = PresetConfiguration.naturalStill
        let metrics = PerceptualMetrics(
            blurProbability: 0.2,
            ringingScore: 0.2,
            noiseVisibility: 0.1,
            localContrast: 0.2,
            edgeDensity: 0.3,
            phaseContrast: 0.1
        )

        let tuning = PerceptualTuner().tune(
            scaledPreset: preset,
            metrics: metrics,
            sharpnessScore: 0.5,
            clippedFraction: 0.0
        )

        XCTAssertLessThan(tuning.wavelet.fineGain, preset.wavelet.fineGain)
    }

    func testTunerBoostsDenoiseOnNoise() {
        let preset = PresetConfiguration.naturalStill
        let metrics = PerceptualMetrics(
            blurProbability: 0.1,
            ringingScore: 0.05,
            noiseVisibility: 0.9,
            localContrast: 0.2,
            edgeDensity: 0.3,
            phaseContrast: 0.1
        )

        let tuning = PerceptualTuner().tune(
            scaledPreset: preset,
            metrics: metrics,
            sharpnessScore: 0.5,
            clippedFraction: 0.0
        )

        XCTAssertGreaterThan(tuning.denoise.lumaDenoiseBase, preset.denoise.lumaDenoiseBase)
    }

    func testPhaseGateReducesMicroContrast() {
        let preset = PresetConfiguration.naturalStill
        let metrics = PerceptualMetrics(
            blurProbability: 0.2,
            ringingScore: 0.05,
            noiseVisibility: 0.1,
            localContrast: 0.2,
            edgeDensity: 0.3,
            phaseContrast: 0.0
        )

        let tuning = PerceptualTuner().tune(
            scaledPreset: preset,
            metrics: metrics,
            sharpnessScore: 0.5,
            clippedFraction: 0.0
        )

        XCTAssertLessThan(tuning.microContrast.strength, preset.microContrast.strength)
    }
}
