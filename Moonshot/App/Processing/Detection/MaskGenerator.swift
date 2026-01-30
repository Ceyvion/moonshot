import Foundation
import CoreGraphics

/// Result of mask generation
struct MaskGenerationResult {
    let cropRect: CGRect
    let moonMask: MaskBuffer
    let limbRingMask: MaskBuffer
}

/// Generates masks for moon processing
final class MaskGenerator {

    let featherWidth: Float
    let limbRingWidth: Float

    init(featherWidth: Float = 3.0, limbRingWidth: Float = 9.0) {
        self.featherWidth = featherWidth
        self.limbRingWidth = limbRingWidth
    }

    /// Generate moon mask and limb ring mask for the given circle
    func generate(
        circle: FittedCircle,
        imageSize: CGSize,
        paddingFactor: Float = 1.3
    ) -> MaskGenerationResult {

        // Calculate crop rect with padding
        let padding = circle.radius * CGFloat(paddingFactor - 1.0)
        let cropRect = calculateCropRect(
            circle: circle,
            padding: padding,
            imageSize: imageSize
        )

        // Generate masks at crop rect resolution
        let maskWidth = Int(cropRect.width)
        let maskHeight = Int(cropRect.height)

        // Moon center relative to crop rect
        let localCenter = CGPoint(
            x: circle.center.x - cropRect.origin.x,
            y: circle.center.y - cropRect.origin.y
        )

        // Generate moon mask with feathered edge
        let moonMask = generateMoonMask(
            width: maskWidth,
            height: maskHeight,
            center: localCenter,
            radius: circle.radius,
            featherWidth: CGFloat(featherWidth)
        )

        // Generate limb ring mask
        let limbRingMask = generateLimbRingMask(
            width: maskWidth,
            height: maskHeight,
            center: localCenter,
            radius: circle.radius,
            ringWidth: CGFloat(limbRingWidth)
        )

        return MaskGenerationResult(
            cropRect: cropRect,
            moonMask: moonMask,
            limbRingMask: limbRingMask
        )
    }

    // MARK: - Private

    private func calculateCropRect(
        circle: FittedCircle,
        padding: CGFloat,
        imageSize: CGSize
    ) -> CGRect {

        let diameter = circle.radius * 2
        let size = diameter + padding * 2

        var rect = CGRect(
            x: circle.center.x - size / 2,
            y: circle.center.y - size / 2,
            width: size,
            height: size
        )

        // Clamp to image bounds
        rect = rect.intersection(CGRect(origin: .zero, size: imageSize))

        return rect
    }

    private func generateMoonMask(
        width: Int,
        height: Int,
        center: CGPoint,
        radius: CGFloat,
        featherWidth: CGFloat
    ) -> MaskBuffer {

        var data = [Float](repeating: 0, count: width * height)

        let innerRadius = Float(radius - featherWidth)
        let outerRadius = Float(radius + featherWidth)
        let centerX = Float(center.x)
        let centerY = Float(center.y)

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                let dist = sqrt(dx * dx + dy * dy)

                let value: Float
                if dist <= innerRadius {
                    // Inside: full mask
                    value = 1.0
                } else if dist >= outerRadius {
                    // Outside: no mask
                    value = 0.0
                } else {
                    // Feather zone: smooth falloff using cosine
                    let t = (dist - innerRadius) / (outerRadius - innerRadius)
                    value = 0.5 * (1 + cos(t * Float.pi))
                }

                data[y * width + x] = value
            }
        }

        return MaskBuffer(width: width, height: height, data: data)
    }

    private func generateLimbRingMask(
        width: Int,
        height: Int,
        center: CGPoint,
        radius: CGFloat,
        ringWidth: CGFloat
    ) -> MaskBuffer {

        var data = [Float](repeating: 0, count: width * height)

        let innerRadius = Float(radius - ringWidth)
        let outerRadius = Float(radius)
        let centerX = Float(center.x)
        let centerY = Float(center.y)

        // Smooth transition width at boundaries
        let transitionWidth: Float = 2.0

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                let dist = sqrt(dx * dx + dy * dy)

                let value: Float
                if dist < innerRadius - transitionWidth {
                    // Well inside the moon: no limb ring effect
                    value = 0.0
                } else if dist > outerRadius + transitionWidth {
                    // Outside the moon: no limb ring effect
                    value = 0.0
                } else if dist >= innerRadius && dist <= outerRadius {
                    // In the ring: full effect
                    value = 1.0
                } else if dist < innerRadius {
                    // Transition from inside
                    let t = (innerRadius - dist) / transitionWidth
                    value = 1.0 - t
                } else {
                    // Transition from outside
                    let t = (dist - outerRadius) / transitionWidth
                    value = 1.0 - t
                }

                data[y * width + x] = max(0, min(1, value))
            }
        }

        return MaskBuffer(width: width, height: height, data: data)
    }
}
