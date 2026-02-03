import CoreGraphics
import Foundation

final class EnhancementPipeline {
    struct Input {
        let cgImage: CGImage
        let detection: MoonDetectionResult
        let preset: EnhancementPreset
        let strength: Float
        let isVideo: Bool
    }

    struct Output {
        let enhanced: CGImage
        let originalCrop: CGImage
        let warnings: [String]
        let metrics: EnhancementMetrics
    }

    enum PipelineError: Error {
        case invalidCrop
        case conversionFailed
        case maskMismatch
    }

    private let confidenceBuilder = ConfidenceMapBuilder()
    private let sharpnessScorer = SharpnessScorer()
    private let perceptualEvaluator = PerceptualMetricsEvaluator()
    private let perceptualTuner = PerceptualTuner()
    private let toneMapper = ToneMapper()
    private let denoiser = Denoiser()
    private let highlightCompensator = HighlightCompensator()
    private let deconvolver = Deconvolver()
    private let wavelet = WaveletSharpener()
    private let microContrast = MicroContrast()
    private let haloGuard = HaloGuard()

    func run(_ input: Input, progress: ((String, Double) -> Void)? = nil) throws -> Output {
        var warnings: [String] = []

        progress?("Cropping", 0.05)
        guard let cropRect = ImageCropper.clampedRect(for: input.cgImage, rect: input.detection.cropRect),
              let cropped = input.cgImage.cropping(to: cropRect) else {
            throw PipelineError.invalidCrop
        }

        progress?("Converting color", 0.1)
        let conversion = ColorConverter.rgbToYCbCrFloat(cropped)
        guard conversion.width > 0, conversion.height > 0 else {
            throw PipelineError.conversionFailed
        }

        let width = conversion.width
        let height = conversion.height
        var luma = conversion.y
        var cb = conversion.cb
        var cr = conversion.cr

        let moonMask = input.detection.moonMask.resized(toWidth: width, height: height)
        let limbRing = input.detection.limbRingMask.resized(toWidth: width, height: height)

        progress?("Building confidence", 0.2)
        let confidenceResult = confidenceBuilder.build(
            luma: luma,
            width: width,
            height: height,
            moonMask: moonMask,
            limbRing: limbRing
        )

        let sharpnessScore = sharpnessScorer.score(luma: luma, width: width, height: height, mask: moonMask)

        progress?("Perceptual analysis", 0.25)
        let perceptualMetrics = perceptualEvaluator.evaluate(
            luma: luma,
            width: width,
            height: height,
            moonMask: moonMask,
            limbRing: limbRing
        )

        let basePreset = PresetConfiguration.preset(for: input.preset, isVideo: input.isVideo)
        let scaledPreset = basePreset.scaled(by: max(0, min(1, input.strength / 100.0)))

        var toneParams = scaledPreset.tone
        var waveletParams = scaledPreset.wavelet
        var deconvParams = scaledPreset.deconvolution
        var denoiseParams = scaledPreset.denoise
        var microContrastParams = scaledPreset.microContrast

        if input.detection.clippedHighlightFraction > deconvParams.maxClippedFraction {
            toneParams = PresetConfiguration.ToneParameters(
                highlightShoulderStart: toneParams.highlightShoulderStart,
                shoulderStrength: toneParams.shoulderStrength * 0.7,
                midtoneContrastGain: toneParams.midtoneContrastGain * 0.7,
                midtonePivot: toneParams.midtonePivot
            )

            waveletParams = PresetConfiguration.WaveletParameters(
                fineGain: waveletParams.fineGain * 0.6,
                midGain: waveletParams.midGain,
                coarseGain: waveletParams.coarseGain,
                cExponent: waveletParams.cExponent,
                limbMultiplier: waveletParams.limbMultiplier,
                minSNR: waveletParams.minSNR,
                maxLuma: waveletParams.maxLuma,
                maxLumaFade: waveletParams.maxLumaFade
            )

            deconvParams = PresetConfiguration.DeconvolutionParameters(
                enabled: false,
                minCircleConfidence: deconvParams.minCircleConfidence,
                minMedianC: deconvParams.minMedianC,
                maxClippedFraction: deconvParams.maxClippedFraction,
                iterations: deconvParams.iterations,
                psfSigma: deconvParams.psfSigma,
                updateMultiplierBase: deconvParams.updateMultiplierBase,
                updateMultiplierCScale: deconvParams.updateMultiplierCScale,
                limbRingMultiplier: deconvParams.limbRingMultiplier
            )

            warnings.append("Highlights clipped. Kept the result natural.")
        }

        let guardedPreset = PresetConfiguration(
            tone: toneParams,
            denoise: denoiseParams,
            deconvolution: deconvParams,
            wavelet: waveletParams,
            microContrast: microContrastParams,
            haloGuard: scaledPreset.haloGuard,
            videoStacking: scaledPreset.videoStacking,
            mask: scaledPreset.mask
        )

        let tuning = perceptualTuner.tune(
            scaledPreset: guardedPreset,
            metrics: perceptualMetrics,
            sharpnessScore: sharpnessScore,
            clippedFraction: input.detection.clippedHighlightFraction
        )

        toneParams = tuning.tone
        denoiseParams = tuning.denoise
        deconvParams = tuning.deconvolution
        waveletParams = tuning.wavelet
        microContrastParams = tuning.microContrast
        warnings.append(contentsOf: tuning.warnings)

        progress?("Tone mapping", 0.3)
        let originalLuma = luma
        let whitePoint = percentile(luma: luma, mask: moonMask, percentile: 0.99)
        toneMapper.apply(luma: &luma, params: toneParams, whitePoint: whitePoint)
        luma = blend(base: originalLuma, processed: luma, mask: moonMask)

        progress?("Denoising", 0.45)
        denoiser.apply(
            luma: &luma,
            cb: &cb,
            cr: &cr,
            width: width,
            height: height,
            params: denoiseParams,
            confidence: confidenceResult.map
        )

        if input.detection.clippedHighlightFraction > 0.01 {
            progress?("Softening highlights", 0.5)
            highlightCompensator.apply(
                luma: &luma,
                width: width,
                height: height,
                moonMask: moonMask,
                clipStart: 0.90,
                strength: 0.6
            )
            warnings.append("Highlights softened (clipped capture).")
        }

        let baseLuma = luma

        let deconvolutionAllowed = deconvParams.enabled
            && input.detection.confidence.circleConfidence >= deconvParams.minCircleConfidence
            && confidenceResult.medianC >= deconvParams.minMedianC
            && input.detection.clippedHighlightFraction <= deconvParams.maxClippedFraction

        if deconvolutionAllowed {
            progress?("Deconvolving", 0.6)
            deconvolver.apply(
                luma: &luma,
                width: width,
                height: height,
                params: deconvParams,
                confidence: confidenceResult.map,
                limbRing: limbRing
            )
        }

        progress?("Sharpening", 0.75)
        wavelet.apply(
            luma: &luma,
            width: width,
            height: height,
            params: waveletParams,
            confidence: confidenceResult.map,
            snrMap: confidenceResult.snrMap,
            limbRing: limbRing
        )

        let applyMicroContrast = microContrastParams.strength > 0.015
            && confidenceResult.medianC >= (microContrastParams.minC * 0.8)
            && perceptualMetrics.edgeDensity > 0.02

        if applyMicroContrast {
            progress?("Micro-contrast", 0.85)
            microContrast.apply(
                luma: &luma,
                width: width,
                height: height,
                params: microContrastParams,
                confidence: confidenceResult.map,
                limbRing: limbRing
            )
        }

        luma = blend(base: baseLuma, processed: luma, mask: moonMask)

        progress?("Checking halos", 0.9)
        let localCircle = localCircle(from: input.detection, cropRect: cropRect)
        var haloResult = haloGuard.evaluate(
            luma: luma,
            width: width,
            height: height,
            circle: localCircle,
            limbRing: limbRing,
            params: scaledPreset.haloGuard
        )

        if !haloResult.passed {
            warnings.append("Halo mitigation applied.")

            var mitigatedWavelet = waveletParams
            mitigatedWavelet = PresetConfiguration.WaveletParameters(
                fineGain: waveletParams.fineGain * (1 - scaledPreset.haloGuard.fineGainReduction),
                midGain: waveletParams.midGain,
                coarseGain: waveletParams.coarseGain,
                cExponent: waveletParams.cExponent,
                limbMultiplier: waveletParams.limbMultiplier,
                minSNR: waveletParams.minSNR,
                maxLuma: waveletParams.maxLuma,
                maxLumaFade: waveletParams.maxLumaFade
            )

            var mitigatedDeconv = deconvParams
            if mitigatedDeconv.enabled {
                let reduced = mitigatedDeconv.iterations - scaledPreset.haloGuard.rlIterationReduction
                if reduced <= 0 {
                    mitigatedDeconv = PresetConfiguration.DeconvolutionParameters(
                        enabled: false,
                        minCircleConfidence: mitigatedDeconv.minCircleConfidence,
                        minMedianC: mitigatedDeconv.minMedianC,
                        maxClippedFraction: mitigatedDeconv.maxClippedFraction,
                        iterations: mitigatedDeconv.iterations,
                        psfSigma: mitigatedDeconv.psfSigma,
                        updateMultiplierBase: mitigatedDeconv.updateMultiplierBase,
                        updateMultiplierCScale: mitigatedDeconv.updateMultiplierCScale,
                        limbRingMultiplier: mitigatedDeconv.limbRingMultiplier
                    )
                } else {
                    mitigatedDeconv = PresetConfiguration.DeconvolutionParameters(
                        enabled: mitigatedDeconv.enabled,
                        minCircleConfidence: mitigatedDeconv.minCircleConfidence,
                        minMedianC: mitigatedDeconv.minMedianC,
                        maxClippedFraction: mitigatedDeconv.maxClippedFraction,
                        iterations: reduced,
                        psfSigma: mitigatedDeconv.psfSigma,
                        updateMultiplierBase: mitigatedDeconv.updateMultiplierBase,
                        updateMultiplierCScale: mitigatedDeconv.updateMultiplierCScale,
                        limbRingMultiplier: mitigatedDeconv.limbRingMultiplier
                    )
                }
            }

            let expandedLimbRing = dilateMask(
                limbRing,
                width: width,
                height: height,
                radius: Int(ceil(Double(scaledPreset.haloGuard.limbRingExpansion)))
            )
            let expandedMask = MaskBuffer(width: width, height: height, data: expandedLimbRing)

            luma = baseLuma

            let mitigatedDeconvAllowed = mitigatedDeconv.enabled
                && input.detection.confidence.circleConfidence >= mitigatedDeconv.minCircleConfidence
                && confidenceResult.medianC >= mitigatedDeconv.minMedianC
                && input.detection.clippedHighlightFraction <= mitigatedDeconv.maxClippedFraction

            if mitigatedDeconvAllowed {
                progress?("Mitigating halos", 0.92)
                deconvolver.apply(
                    luma: &luma,
                    width: width,
                    height: height,
                    params: mitigatedDeconv,
                    confidence: confidenceResult.map,
                    limbRing: expandedMask
                )
            }

            wavelet.apply(
                luma: &luma,
                width: width,
                height: height,
                params: mitigatedWavelet,
                confidence: confidenceResult.map,
                snrMap: confidenceResult.snrMap,
                limbRing: expandedMask
            )

            if applyMicroContrast {
                microContrast.apply(
                    luma: &luma,
                    width: width,
                    height: height,
                    params: microContrastParams,
                    confidence: confidenceResult.map,
                    limbRing: expandedMask
                )
            }

            luma = blend(base: baseLuma, processed: luma, mask: moonMask)

            haloResult = haloGuard.evaluate(
                luma: luma,
                width: width,
                height: height,
                circle: localCircle,
                limbRing: expandedMask,
                params: scaledPreset.haloGuard
            )
        }

        progress?("Finalizing", 0.95)
        let outputImage = ColorConverter.yCbCrToCGImage(y: luma, cb: cb, cr: cr, width: width, height: height)

        progress?("Done", 1.0)
        let metrics = EnhancementMetrics(
            circleConfidence: input.detection.confidence.circleConfidence,
            clippedFraction: input.detection.clippedHighlightFraction,
            medianC: confidenceResult.medianC,
            sharpnessScore: sharpnessScore,
            overshootMetric: haloResult.overshootMetric,
            blurProbability: perceptualMetrics.blurProbability,
            ringingScore: perceptualMetrics.ringingScore,
            noiseVisibility: perceptualMetrics.noiseVisibility,
            localContrast: perceptualMetrics.localContrast,
            phaseContrast: perceptualMetrics.phaseContrast
        )

        return Output(
            enhanced: outputImage,
            originalCrop: cropped,
            warnings: warnings,
            metrics: metrics
        )
    }

    private func percentile(luma: [Float], mask: MaskBuffer, percentile: Float) -> Float {
        let value = Histogram.percentile(values: luma, mask: mask, percentile: percentile, bins: 1024)
        return max(0.001, value)
    }

    private func localCircle(from detection: MoonDetectionResult, cropRect: CGRect) -> FittedCircle {
        let center = CGPoint(
            x: detection.circle.center.x - cropRect.origin.x,
            y: detection.circle.center.y - cropRect.origin.y
        )
        return FittedCircle(center: center, radius: detection.circle.radius, residualError: detection.circle.residualError)
    }

    private func blend(base: [Float], processed: [Float], mask: MaskBuffer) -> [Float] {
        guard base.count == processed.count, mask.data.count == base.count else { return processed }
        var output = base
        for i in 0..<base.count {
            let t = min(1, max(0, mask.data[i]))
            output[i] = base[i] * (1 - t) + processed[i] * t
        }
        return output
    }

    private func dilateMask(_ mask: MaskBuffer, width: Int, height: Int, radius: Int) -> [Float] {
        guard radius > 0 else { return mask.data }
        var output = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var maxVal: Float = 0
                for ky in -radius...radius {
                    for kx in -radius...radius {
                        let sampleX = min(width - 1, max(0, x + kx))
                        let sampleY = min(height - 1, max(0, y + ky))
                        let value = mask.data[sampleY * width + sampleX]
                        if value > maxVal { maxVal = value }
                    }
                }
                output[y * width + x] = maxVal
            }
        }
        return output
    }
}
