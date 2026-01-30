import Foundation

/// Complete configuration for moon enhancement processing.
/// All tunable parameters are defined here for reproducibility.
struct PresetConfiguration {

    // MARK: - Tone Parameters

    struct ToneParameters {
        /// Fraction of white point where highlight shoulder begins (0.0-1.0)
        let highlightShoulderStart: Float

        /// Strength of highlight compression (0.0-1.0)
        let shoulderStrength: Float

        /// Midtone contrast gain (+/- adjustment)
        let midtoneContrastGain: Float

        /// Pivot point for contrast curve (0.0-1.0)
        let midtonePivot: Float

        func scaled(by factor: Float) -> ToneParameters {
            return ToneParameters(
                highlightShoulderStart: highlightShoulderStart,
                shoulderStrength: shoulderStrength * factor,
                midtoneContrastGain: midtoneContrastGain * factor,
                midtonePivot: midtonePivot
            )
        }
    }

    // MARK: - Denoise Parameters

    struct DenoiseParameters {
        /// Base luminance denoise strength
        let lumaDenoiseBase: Float

        /// Exponent for confidence-based denoise: strength = base * (1-C)^exponent
        let lumaDenoiseExponent: Float

        /// Chroma denoise strength (uniform, not confidence-gated)
        let chromaDenoise: Float

        /// Guided filter radius in pixels
        let guidedFilterRadius: Int

        /// Guided filter epsilon (smoothness control)
        let guidedFilterEpsilon: Float

        func scaled(by factor: Float) -> DenoiseParameters {
            return DenoiseParameters(
                lumaDenoiseBase: lumaDenoiseBase * factor,
                lumaDenoiseExponent: lumaDenoiseExponent,
                chromaDenoise: chromaDenoise * factor,
                guidedFilterRadius: guidedFilterRadius,
                guidedFilterEpsilon: guidedFilterEpsilon
            )
        }
    }

    // MARK: - Deconvolution Parameters

    struct DeconvolutionParameters {
        /// Whether deconvolution is enabled
        let enabled: Bool

        /// Minimum circle fit confidence to run deconvolution
        let minCircleConfidence: Float

        /// Minimum median C to run deconvolution
        let minMedianC: Float

        /// Maximum clipped highlight fraction to run deconvolution
        let maxClippedFraction: Float

        /// Number of Richardson-Lucy iterations
        let iterations: Int

        /// PSF (point spread function) sigma in pixels
        let psfSigma: Float

        /// Base multiplier for RL update
        let updateMultiplierBase: Float

        /// Scale factor for confidence-gated update: multiplier = base + scale * C
        let updateMultiplierCScale: Float

        /// Multiplier applied within limb ring
        let limbRingMultiplier: Float

        func scaled(by factor: Float) -> DeconvolutionParameters {
            let scaledIterations = max(1, Int(Float(iterations) * factor))
            return DeconvolutionParameters(
                enabled: enabled && factor > 0.2,
                minCircleConfidence: minCircleConfidence,
                minMedianC: minMedianC,
                maxClippedFraction: maxClippedFraction,
                iterations: scaledIterations,
                psfSigma: psfSigma,
                updateMultiplierBase: updateMultiplierBase,
                updateMultiplierCScale: updateMultiplierCScale * factor,
                limbRingMultiplier: limbRingMultiplier
            )
        }
    }

    // MARK: - Wavelet Sharpening Parameters

    struct WaveletParameters {
        /// Gain for fine detail band (1-2px features)
        let fineGain: Float

        /// Gain for mid detail band (3-6px features)
        let midGain: Float

        /// Gain for coarse detail band (7-14px features)
        let coarseGain: Float

        /// Exponent for confidence gating: gain *= C^exponent
        let cExponent: Float

        /// Multiplier applied within limb ring (halo prevention)
        let limbMultiplier: Float

        /// Minimum local SNR to apply sharpening
        let minSNR: Float

        /// Max luma where sharpening is allowed (avoid chalky highlights)
        let maxLuma: Float

        /// Fade range above maxLuma (smooth rolloff)
        let maxLumaFade: Float

        func scaled(by factor: Float) -> WaveletParameters {
            return WaveletParameters(
                fineGain: fineGain * factor,
                midGain: midGain * factor,
                coarseGain: coarseGain * factor,
                cExponent: cExponent,
                limbMultiplier: limbMultiplier,
                minSNR: minSNR,
                maxLuma: maxLuma,
                maxLumaFade: maxLumaFade
            )
        }
    }

    // MARK: - Micro-Contrast Parameters

    struct MicroContrastParameters {
        /// Radius for local contrast computation in pixels
        let radius: Int

        /// Contrast enhancement strength
        let strength: Float

        /// Minimum confidence to apply micro-contrast
        let minC: Float

        /// Pixels from limb edge to exclude
        let limbExclusionPixels: Int

        /// Max luma where micro-contrast is allowed
        let maxLuma: Float

        func scaled(by factor: Float) -> MicroContrastParameters {
            return MicroContrastParameters(
                radius: radius,
                strength: strength * factor,
                minC: minC,
                limbExclusionPixels: limbExclusionPixels,
                maxLuma: maxLuma
            )
        }
    }

    // MARK: - Halo Guard Parameters

    struct HaloGuardParameters {
        /// Maximum allowed overshoot as fraction of interior peak
        let overshootThreshold: Float

        /// Number of angles to sample around limb
        let sampleAngles: Int

        /// Fine wavelet gain reduction on halo detection
        let fineGainReduction: Float

        /// RL iteration reduction on halo detection
        let rlIterationReduction: Int

        /// Limb ring expansion on halo detection (pixels)
        let limbRingExpansion: Float
    }

    // MARK: - Video Stacking Parameters

    struct VideoStackingParameters {
        /// Number of top frames to select for stacking
        let frameSelectionCount: Int

        /// Exponent for sharpness-based weights: weight = sharpness^exponent
        let sharpnessWeightExponent: Float

        /// Whether to enable drizzle 2x super-resolution
        let drizzleEnabled: Bool

        /// Minimum shift variance to enable drizzle (pixels)
        let drizzleMinShiftVariance: Float

        /// Sigma for sigma-clipped stacking (set to 0 to disable)
        let sigmaClipSigma: Float

        /// Adjusted denoise base after stacking
        let postStackDenoiseBase: Float
    }

    // MARK: - Mask Parameters

    struct MaskParameters {
        /// Feather width for moon mask edge (pixels)
        let moonMaskFeather: Float

        /// Width of limb ring for edge protection (pixels)
        let limbRingWidth: Float
    }

    // MARK: - Preset Properties

    let tone: ToneParameters
    let denoise: DenoiseParameters
    let deconvolution: DeconvolutionParameters
    let wavelet: WaveletParameters
    let microContrast: MicroContrastParameters
    let haloGuard: HaloGuardParameters
    let videoStacking: VideoStackingParameters
    let mask: MaskParameters

    // MARK: - Convenience

    /// Scale all strength-related parameters by a factor (0.0-1.0)
    func scaled(by factor: Float) -> PresetConfiguration {
        return PresetConfiguration(
            tone: tone.scaled(by: factor),
            denoise: denoise.scaled(by: factor),
            deconvolution: deconvolution.scaled(by: factor),
            wavelet: wavelet.scaled(by: factor),
            microContrast: microContrast.scaled(by: factor),
            haloGuard: haloGuard,
            videoStacking: videoStacking,
            mask: mask
        )
    }
}
