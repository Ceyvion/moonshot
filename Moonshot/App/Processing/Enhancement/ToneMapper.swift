import Foundation

/// Applies highlight shoulder and midtone contrast curve to luminance.
final class ToneMapper {
    func apply(luma: inout [Float], params: PresetConfiguration.ToneParameters, whitePoint: Float) {
        guard whitePoint > 0 else { return }

        for i in 0..<luma.count {
            let normalized = luma[i] / whitePoint
            let shouldered = shoulderCurve(normalized, start: params.highlightShoulderStart, strength: params.shoulderStrength)
            let contrasted = contrastCurve(shouldered, gain: params.midtoneContrastGain, pivot: params.midtonePivot)
            luma[i] = max(0, min(1, contrasted * whitePoint))
        }
    }

    private func shoulderCurve(_ x: Float, start: Float, strength: Float) -> Float {
        if x < start { return x }
        let excess = x - start
        let denom = max(1e-3 as Float, 1.0 - start)
        return start + (1.0 - start) * tanh(excess * strength / denom)
    }

    private func contrastCurve(_ x: Float, gain: Float, pivot: Float) -> Float {
        let shifted = x - pivot
        return pivot + shifted * (1.0 + gain * (1.0 - abs(shifted)))
    }
}
