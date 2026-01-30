import Foundation

/// Crisp preset: stronger detail with careful artifact prevention.
/// More legible crater edges and maria boundaries, still believable.
extension PresetConfiguration {

    /// Crisp preset for single photo enhancement
    static let crispStill = PresetConfiguration(
        tone: ToneParameters(
            highlightShoulderStart: 0.78,   // Earlier shoulder to prevent limb glow
            shoulderStrength: 0.65,         // Stronger compression
            midtoneContrastGain: 0.16,      // +16% contrast
            midtonePivot: 0.52
        ),
        denoise: DenoiseParameters(
            lumaDenoiseBase: 0.45,          // Stronger denoise needed before sharpening
            lumaDenoiseExponent: 1.1,       // Strength = 0.45 * (1-C)^1.1
            chromaDenoise: 0.65,
            guidedFilterRadius: 3,
            guidedFilterEpsilon: 0.008
        ),
        deconvolution: DeconvolutionParameters(
            enabled: true,
            minCircleConfidence: 0.7,       // Stricter requirements
            minMedianC: 0.40,
            maxClippedFraction: 0.003,      // Very strict on clipping
            iterations: 6,
            psfSigma: 0.7,
            updateMultiplierBase: 0.5,
            updateMultiplierCScale: 0.5,    // Multiplier = 0.5 + 0.5*C
            limbRingMultiplier: 0.25
        ),
        wavelet: WaveletParameters(
            fineGain: 0.32,                 // Stronger fine detail
            midGain: 0.22,
            coarseGain: 0.09,
            cExponent: 1.35,                // Steeper confidence gating
            limbMultiplier: 0.25,           // Less limb sharpening
            minSNR: 4.0,                    // Don't sharpen below SNR 4
            maxLuma: 0.90,
            maxLumaFade: 0.06
        ),
        microContrast: MicroContrastParameters(
            radius: 22,
            strength: 0.11,
            minC: 0.55,                     // Only where C > 0.55
            limbExclusionPixels: 10,        // Never in outer 10px
            maxLuma: 0.88
        ),
        haloGuard: HaloGuardParameters(
            overshootThreshold: 0.022,      // 2.2% threshold (slightly higher)
            sampleAngles: 36,
            fineGainReduction: 0.35,        // Reduce by 35% on detection
            rlIterationReduction: 2,
            limbRingExpansion: 3.0
        ),
        videoStacking: VideoStackingParameters(
            frameSelectionCount: 20,        // More frames for crisp
            sharpnessWeightExponent: 1.6,   // Sharper weighting
            drizzleEnabled: true,           // Enable drizzle for crisp
            drizzleMinShiftVariance: 0.15,
            sigmaClipSigma: 2.5,
            postStackDenoiseBase: 0.14      // Even less denoise after good stack
        ),
        mask: MaskParameters(
            moonMaskFeather: 3.0,
            limbRingWidth: 9.0
        )
    )

    /// Crisp preset for video/burst stacking
    static let crispVideo = PresetConfiguration(
        tone: ToneParameters(
            highlightShoulderStart: 0.78,
            shoulderStrength: 0.65,
            midtoneContrastGain: 0.16,
            midtonePivot: 0.52
        ),
        denoise: DenoiseParameters(
            lumaDenoiseBase: 0.14,          // Very low after stacking
            lumaDenoiseExponent: 1.1,
            chromaDenoise: 0.55,
            guidedFilterRadius: 3,
            guidedFilterEpsilon: 0.008
        ),
        deconvolution: DeconvolutionParameters(
            enabled: true,
            minCircleConfidence: 0.7,
            minMedianC: 0.40,
            maxClippedFraction: 0.003,
            iterations: 7,                  // More iterations with clean stack
            psfSigma: 0.7,
            updateMultiplierBase: 0.5,
            updateMultiplierCScale: 0.5,
            limbRingMultiplier: 0.25
        ),
        wavelet: WaveletParameters(
            fineGain: 0.29,                 // Slightly reduced if drizzle active
            midGain: 0.20,
            coarseGain: 0.08,
            cExponent: 1.35,
            limbMultiplier: 0.25,
            minSNR: 4.0,
            maxLuma: 0.90,
            maxLumaFade: 0.06
        ),
        microContrast: MicroContrastParameters(
            radius: 22,
            strength: 0.11,
            minC: 0.55,
            limbExclusionPixels: 10,
            maxLuma: 0.88
        ),
        haloGuard: HaloGuardParameters(
            overshootThreshold: 0.022,
            sampleAngles: 36,
            fineGainReduction: 0.35,
            rlIterationReduction: 2,
            limbRingExpansion: 3.0
        ),
        videoStacking: VideoStackingParameters(
            frameSelectionCount: 20,
            sharpnessWeightExponent: 1.6,
            drizzleEnabled: true,
            drizzleMinShiftVariance: 0.15,
            sigmaClipSigma: 2.5,
            postStackDenoiseBase: 0.14
        ),
        mask: MaskParameters(
            moonMaskFeather: 3.0,
            limbRingWidth: 9.0
        )
    )

    /// Get crisp preset for the given source type
    static func crisp(forVideo: Bool) -> PresetConfiguration {
        return forVideo ? crispVideo : crispStill
    }
}

// MARK: - Preset Selection Helper

extension PresetConfiguration {

    /// Get the appropriate preset for the given enhancement preset and source type
    static func preset(for preset: EnhancementPreset, isVideo: Bool) -> PresetConfiguration {
        switch preset {
        case .natural:
            return natural(forVideo: isVideo)
        case .crisp:
            return crisp(forVideo: isVideo)
        }
    }
}
