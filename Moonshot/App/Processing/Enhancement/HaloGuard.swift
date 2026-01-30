import Foundation
import CoreGraphics

struct HaloGuardResult {
    let overshootMetric: Float
    let passed: Bool
}

/// Detects limb halos using radial overshoot sampling.
final class HaloGuard {
    func evaluate(
        luma: [Float],
        width: Int,
        height: Int,
        circle: FittedCircle,
        limbRing: MaskBuffer,
        params: PresetConfiguration.HaloGuardParameters
    ) -> HaloGuardResult {
        _ = limbRing
        guard width > 0, height > 0 else {
            return HaloGuardResult(overshootMetric: 0, passed: true)
        }

        let centerX = Float(circle.center.x)
        let centerY = Float(circle.center.y)
        let radius = Float(circle.radius)

        var maxOvershoot: Float = 0
        let sampleCount = max(8, params.sampleAngles)

        for i in 0..<sampleCount {
            let angle = Float(i) * (2 * Float.pi) / Float(sampleCount)
            let cosA = cos(angle)
            let sinA = sin(angle)

            let inside = sampleLuma(
                luma: luma,
                width: width,
                height: height,
                x: centerX + (radius - 2) * cosA,
                y: centerY + (radius - 2) * sinA
            )

            let outside = sampleLuma(
                luma: luma,
                width: width,
                height: height,
                x: centerX + (radius + 2) * cosA,
                y: centerY + (radius + 2) * sinA
            )

            let overshoot = max(outside - inside, 0) / max(inside, 1e-3)
            if overshoot > maxOvershoot {
                maxOvershoot = overshoot
            }
        }

        let passed = maxOvershoot <= params.overshootThreshold
        return HaloGuardResult(overshootMetric: maxOvershoot, passed: passed)
    }

    private func sampleLuma(luma: [Float], width: Int, height: Int, x: Float, y: Float) -> Float {
        let ix = min(width - 1, max(0, Int(round(x))))
        let iy = min(height - 1, max(0, Int(round(y))))
        return luma[iy * width + ix]
    }
}
