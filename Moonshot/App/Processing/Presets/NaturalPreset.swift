import Foundation

/// Natural preset: conservative enhancement that preserves the original character.
/// Accepts softness in low-confidence regions.
extension PresetConfiguration {

    /// Natural preset for single photo enhancement
    static let naturalStill = PresetConfiguration(
        tone: ToneParameters(
            highlightShoulderStart: 0.82,   // Start shoulder at 82% of white point
            shoulderStrength: 0.55,
            midtoneContrastGain: 0.10,      // Gentle +10% contrast
            midtonePivot: 0.55
        ),
        denoise: DenoiseParameters(
            lumaDenoiseBase: 0.35,
            lumaDenoiseExponent: 1.3,       // Strength = 0.35 * (1-C)^1.3
            chromaDenoise: 0.55,
            guidedFilterRadius: 3,
            guidedFilterEpsilon: 0.006
        ),
        deconvolution: DeconvolutionParameters(
            enabled: true,
            minCircleConfidence: 0.6,
            minMedianC: 0.35,
            maxClippedFraction: 0.01,       // Disable if >1% clipped
            iterations: 3,
            psfSigma: 0.8,
            updateMultiplierBase: 0.6,
            updateMultiplierCScale: 0.4,    // Multiplier = 0.6 + 0.4*C
            limbRingMultiplier: 0.35
        ),
        wavelet: WaveletParameters(
            fineGain: 0.18,                 // 1-2px features
            midGain: 0.12,                  // 3-6px features
            coarseGain: 0.05,               // 7-14px features
            cExponent: 1.2,                 // Gain *= C^1.2
            limbMultiplier: 0.35,           // Strong limb protection
            minSNR: 3.0,
            maxLuma: 0.92,
            maxLumaFade: 0.05
        ),
        microContrast: MicroContrastParameters(
            radius: 18,
            strength: 0.07,
            minC: 0.45,                     // Only where C > 0.45
            limbExclusionPixels: 6,
            maxLuma: 0.90
        ),
        haloGuard: HaloGuardParameters(
            overshootThreshold: 0.015,      // 1.5% threshold
            sampleAngles: 36,
            fineGainReduction: 0.25,        // Reduce by 25% on detection
            rlIterationReduction: 1,
            limbRingExpansion: 2.0
        ),
        videoStacking: VideoStackingParameters(
            frameSelectionCount: 12,
            sharpnessWeightExponent: 1.2,
            drizzleEnabled: false,
            drizzleMinShiftVariance: 0.15,
            sigmaClipSigma: 2.5,
            postStackDenoiseBase: 0.18      // Reduced after stacking
        ),
        mask: MaskParameters(
            moonMaskFeather: 3.0,
            limbRingWidth: 9.0
        )
    )

    /// Natural preset for video/burst stacking
    static let naturalVideo = PresetConfiguration(
        tone: ToneParameters(
            highlightShoulderStart: 0.82,
            shoulderStrength: 0.55,
            midtoneContrastGain: 0.10,
            midtonePivot: 0.55
        ),
        denoise: DenoiseParameters(
            lumaDenoiseBase: 0.18,          // Reduced after stacking
            lumaDenoiseExponent: 1.3,
            chromaDenoise: 0.45,
            guidedFilterRadius: 3,
            guidedFilterEpsilon: 0.006
        ),
        deconvolution: DeconvolutionParameters(
            enabled: true,
            minCircleConfidence: 0.6,
            minMedianC: 0.35,
            maxClippedFraction: 0.01,
            iterations: 4,                  // Can use 4 with cleaner stack
            psfSigma: 0.8,
            updateMultiplierBase: 0.6,
            updateMultiplierCScale: 0.4,
            limbRingMultiplier: 0.35
        ),
        wavelet: WaveletParameters(
            fineGain: 0.18,
            midGain: 0.12,
            coarseGain: 0.05,
            cExponent: 1.2,
            limbMultiplier: 0.35,
            minSNR: 3.0,
            maxLuma: 0.92,
            maxLumaFade: 0.05
        ),
        microContrast: MicroContrastParameters(
            radius: 18,
            strength: 0.07,
            minC: 0.45,
            limbExclusionPixels: 6,
            maxLuma: 0.90
        ),
        haloGuard: HaloGuardParameters(
            overshootThreshold: 0.015,
            sampleAngles: 36,
            fineGainReduction: 0.25,
            rlIterationReduction: 1,
            limbRingExpansion: 2.0
        ),
        videoStacking: VideoStackingParameters(
            frameSelectionCount: 12,
            sharpnessWeightExponent: 1.2,
            drizzleEnabled: false,
            drizzleMinShiftVariance: 0.15,
            sigmaClipSigma: 2.5,
            postStackDenoiseBase: 0.18
        ),
        mask: MaskParameters(
            moonMaskFeather: 3.0,
            limbRingWidth: 9.0
        )
    )

    /// Get natural preset for the given source type
    static func natural(forVideo: Bool) -> PresetConfiguration {
        return forVideo ? naturalVideo : naturalStill
    }
}
