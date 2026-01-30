import Foundation

struct PerceptualTuningResult {
    let tone: PresetConfiguration.ToneParameters
    let denoise: PresetConfiguration.DenoiseParameters
    let deconvolution: PresetConfiguration.DeconvolutionParameters
    let wavelet: PresetConfiguration.WaveletParameters
    let microContrast: PresetConfiguration.MicroContrastParameters
    let warnings: [String]
}

/// Adjusts enhancement parameters based on perceptual quality metrics.
final class PerceptualTuner {
    func tune(
        scaledPreset: PresetConfiguration,
        metrics: PerceptualMetrics,
        sharpnessScore: Float,
        clippedFraction: Float
    ) -> PerceptualTuningResult {
        var warnings: [String] = []

        let ringGate = smoothstep(edge0: 0.04, edge1: 0.10, x: metrics.ringingScore)
        let noiseGate = smoothstep(edge0: 0.35, edge1: 0.65, x: metrics.noiseVisibility)
        let blurGate = smoothstep(edge0: 0.45, edge1: 0.75, x: metrics.blurProbability)
        let contrastGate = smoothstep(edge0: 0.25, edge1: 0.45, x: metrics.localContrast)
        let edgeGate = smoothstep(edge0: 0.02, edge1: 0.08, x: metrics.edgeDensity)
        let phaseGate = smoothstep(edge0: 0.03, edge1: 0.08, x: metrics.phaseContrast)

        var tone = scaledPreset.tone
        var denoise = scaledPreset.denoise
        var deconvolution = scaledPreset.deconvolution
        var wavelet = scaledPreset.wavelet
        var microContrast = scaledPreset.microContrast

        // Contrast sensitivity shaping: favor mid frequencies.
        let fineWeight: Float = 0.85
        let midWeight: Float = 1.0
        let coarseWeight: Float = 0.70

        let edgeFactor = 0.6 + 0.4 * edgeGate
        let phaseMicroScale = 0.6 + 0.4 * phaseGate
        let phaseFineScale = 0.7 + 0.3 * phaseGate

        wavelet = PresetConfiguration.WaveletParameters(
            fineGain: wavelet.fineGain * fineWeight * edgeFactor * phaseFineScale * (1 - 0.35 * ringGate) * (1 - 0.20 * noiseGate),
            midGain: wavelet.midGain * midWeight * edgeFactor * (1 - 0.15 * noiseGate),
            coarseGain: wavelet.coarseGain * coarseWeight,
            cExponent: wavelet.cExponent,
            limbMultiplier: wavelet.limbMultiplier,
            minSNR: wavelet.minSNR,
            maxLuma: wavelet.maxLuma,
            maxLumaFade: wavelet.maxLumaFade
        )

        if sharpnessScore > 0.70 {
            wavelet = PresetConfiguration.WaveletParameters(
                fineGain: wavelet.fineGain * 0.85,
                midGain: wavelet.midGain,
                coarseGain: wavelet.coarseGain,
                cExponent: wavelet.cExponent,
                limbMultiplier: wavelet.limbMultiplier,
                minSNR: wavelet.minSNR,
                maxLuma: wavelet.maxLuma,
                maxLumaFade: wavelet.maxLumaFade
            )
        }

        microContrast = PresetConfiguration.MicroContrastParameters(
            radius: microContrast.radius,
            strength: microContrast.strength * phaseMicroScale * (1 - 0.30 * noiseGate) * (1 - 0.20 * contrastGate),
            minC: microContrast.minC,
            limbExclusionPixels: microContrast.limbExclusionPixels,
            maxLuma: microContrast.maxLuma
        )

        tone = PresetConfiguration.ToneParameters(
            highlightShoulderStart: tone.highlightShoulderStart,
            shoulderStrength: tone.shoulderStrength,
            midtoneContrastGain: tone.midtoneContrastGain * (1 - 0.30 * contrastGate),
            midtonePivot: tone.midtonePivot
        )

        denoise = PresetConfiguration.DenoiseParameters(
            lumaDenoiseBase: clamp(denoise.lumaDenoiseBase + 0.08 * noiseGate, min: 0.05, max: 0.70),
            lumaDenoiseExponent: denoise.lumaDenoiseExponent,
            chromaDenoise: clamp(denoise.chromaDenoise + 0.10 * noiseGate, min: 0.20, max: 0.80),
            guidedFilterRadius: denoise.guidedFilterRadius,
            guidedFilterEpsilon: denoise.guidedFilterEpsilon
        )

        if ringGate > 0.5 {
            warnings.append("Ringing risk detected. Reduced sharpening.")
            let reduced = deconvolution.iterations - 2
            if reduced <= 0 {
                deconvolution = PresetConfiguration.DeconvolutionParameters(
                    enabled: false,
                    minCircleConfidence: deconvolution.minCircleConfidence,
                    minMedianC: deconvolution.minMedianC,
                    maxClippedFraction: deconvolution.maxClippedFraction,
                    iterations: deconvolution.iterations,
                    psfSigma: deconvolution.psfSigma,
                    updateMultiplierBase: deconvolution.updateMultiplierBase,
                    updateMultiplierCScale: deconvolution.updateMultiplierCScale,
                    limbRingMultiplier: deconvolution.limbRingMultiplier
                )
            } else {
                deconvolution = PresetConfiguration.DeconvolutionParameters(
                    enabled: deconvolution.enabled,
                    minCircleConfidence: deconvolution.minCircleConfidence,
                    minMedianC: deconvolution.minMedianC,
                    maxClippedFraction: deconvolution.maxClippedFraction,
                    iterations: reduced,
                    psfSigma: deconvolution.psfSigma,
                    updateMultiplierBase: deconvolution.updateMultiplierBase,
                    updateMultiplierCScale: deconvolution.updateMultiplierCScale,
                    limbRingMultiplier: deconvolution.limbRingMultiplier
                )
            }
        }

        if noiseGate > 0.5 {
            warnings.append("Noise visibility high. Extra denoise applied.")
        }

        if blurGate > 0.6 && sharpnessScore < 0.35 {
            warnings.append("Low detail. Kept the result natural.")
            deconvolution = PresetConfiguration.DeconvolutionParameters(
                enabled: false,
                minCircleConfidence: deconvolution.minCircleConfidence,
                minMedianC: deconvolution.minMedianC,
                maxClippedFraction: deconvolution.maxClippedFraction,
                iterations: deconvolution.iterations,
                psfSigma: deconvolution.psfSigma,
                updateMultiplierBase: deconvolution.updateMultiplierBase,
                updateMultiplierCScale: deconvolution.updateMultiplierCScale,
                limbRingMultiplier: deconvolution.limbRingMultiplier
            )

            wavelet = PresetConfiguration.WaveletParameters(
                fineGain: wavelet.fineGain * 0.75,
                midGain: wavelet.midGain,
                coarseGain: wavelet.coarseGain,
                cExponent: wavelet.cExponent,
                limbMultiplier: wavelet.limbMultiplier,
                minSNR: wavelet.minSNR,
                maxLuma: wavelet.maxLuma,
                maxLumaFade: wavelet.maxLumaFade
            )
        }

        _ = clippedFraction

        if phaseMicroScale < 0.9 {
            warnings.append("Full-moon phase detected. Reduced micro-contrast.")
        }

        return PerceptualTuningResult(
            tone: tone,
            denoise: denoise,
            deconvolution: deconvolution,
            wavelet: wavelet,
            microContrast: microContrast,
            warnings: warnings
        )
    }

    private func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        guard edge1 != edge0 else { return x >= edge1 ? 1 : 0 }
        let t = clamp((x - edge0) / (edge1 - edge0), min: 0, max: 1)
        return t * t * (3 - 2 * t)
    }

    private func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        return max(minValue, min(maxValue, value))
    }
}
