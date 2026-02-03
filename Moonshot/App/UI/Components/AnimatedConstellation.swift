import SwiftUI

/// A self-animating constellation that morphs between 5 patterns with glowing stars
struct AnimatedConstellation: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Animation timing
    private let cycleDuration: Double = 10.0  // Full cycle through all constellations
    private let twinklePeriod: Double = 1.5   // Individual star twinkle period

    // 5 constellation patterns (normalized coordinates, positioned around center)
    // Designed to orbit around a central moon
    private let constellations: [[CGPoint]] = [
        // Pattern 1: Single bright star at top
        [
            CGPoint(x: 0.5, y: 0.12)
        ],

        // Pattern 2: Crescent arc (3 stars on left side)
        [
            CGPoint(x: 0.22, y: 0.28),
            CGPoint(x: 0.15, y: 0.5),
            CGPoint(x: 0.22, y: 0.72)
        ],

        // Pattern 3: Triangle surrounding moon
        [
            CGPoint(x: 0.5, y: 0.1),
            CGPoint(x: 0.18, y: 0.78),
            CGPoint(x: 0.82, y: 0.78)
        ],

        // Pattern 4: Diamond/cardinal points
        [
            CGPoint(x: 0.5, y: 0.08),
            CGPoint(x: 0.12, y: 0.5),
            CGPoint(x: 0.88, y: 0.5),
            CGPoint(x: 0.5, y: 0.92)
        ],

        // Pattern 5: Hexagonal ring around moon
        [
            CGPoint(x: 0.5, y: 0.08),
            CGPoint(x: 0.78, y: 0.24),
            CGPoint(x: 0.78, y: 0.76),
            CGPoint(x: 0.5, y: 0.92),
            CGPoint(x: 0.22, y: 0.76),
            CGPoint(x: 0.22, y: 0.24)
        ]
    ]

    var body: some View {
        if reduceMotion {
            // Static view for reduced motion - show the hexagon pattern
            staticConstellation
        } else {
            animatedConstellation
        }
    }

    // MARK: - Static Version (Reduced Motion)

    private var staticConstellation: some View {
        Canvas { context, size in
            let points = constellations[4].map { normalizedPoint in
                CGPoint(
                    x: normalizedPoint.x * size.width,
                    y: normalizedPoint.y * size.height
                )
            }
            drawConstellationLines(points: points, in: &context, alpha: 0.25)
            for point in points {
                drawStar(at: point, in: &context, twinkle: 1.0, baseAlpha: 0.9)
            }
        }
        .frame(width: 200, height: 200)
    }

    // MARK: - Animated Version

    private var animatedConstellation: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawAnimatedConstellation(
                    time: time,
                    context: &context,
                    size: size
                )
            }
        }
        .frame(width: 200, height: 200)
        // Subtle bloom effect
        .blur(radius: 0.3)
        .overlay {
            // Additional glow layer
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let breathe = (sin(time * 0.8) + 1) / 2 * 0.15 + 0.85

                Canvas { context, size in
                    drawAnimatedConstellation(
                        time: time,
                        context: &context,
                        size: size
                    )
                }
                .blur(radius: 8)
                .opacity(0.4 * breathe)
            }
        }
    }

    // MARK: - Drawing

    private func drawAnimatedConstellation(
        time: Double,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        // Calculate which constellations we're interpolating between
        let cycleProgress = (time.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
        let totalPatterns = Double(constellations.count)
        let rawIndex = cycleProgress * totalPatterns
        let fromIndex = Int(floor(rawIndex)) % constellations.count
        let toIndex = (fromIndex + 1) % constellations.count

        // Smooth easing for transition
        let rawT = rawIndex - floor(rawIndex)
        let t = smootherStep(rawT)

        // Get interpolated points
        let points = interpolateConstellations(
            from: constellations[fromIndex],
            to: constellations[toIndex],
            t: CGFloat(t),
            size: size
        )

        // Draw connecting lines first (behind stars)
        drawConstellationLines(points: points.map { $0.point }, in: &context, alpha: 0.2 + 0.1 * CGFloat(t))

        // Draw each star with individual twinkle
        for (index, pointData) in points.enumerated() {
            // Each star has its own twinkle phase
            let twinkleOffset = Double(index) * 0.7
            let twinkle = (sin((time + twinkleOffset) * (2 * .pi / twinklePeriod)) + 1) / 2
            let twinkleAmount = 0.7 + twinkle * 0.3

            drawStar(
                at: pointData.point,
                in: &context,
                twinkle: twinkleAmount,
                baseAlpha: pointData.alpha
            )
        }
    }

    private struct InterpolatedPoint {
        let point: CGPoint
        let alpha: CGFloat
    }

    private func interpolateConstellations(
        from: [CGPoint],
        to: [CGPoint],
        t: CGFloat,
        size: CGSize
    ) -> [InterpolatedPoint] {
        let maxPoints = max(from.count, to.count)
        var result: [InterpolatedPoint] = []

        for i in 0..<maxPoints {
            let fromPoint = from[safe: i] ?? from.last ?? CGPoint(x: 0.5, y: 0.5)
            let toPoint = to[safe: i] ?? to.last ?? CGPoint(x: 0.5, y: 0.5)

            // Interpolate position
            let interpolated = CGPoint(
                x: (fromPoint.x + (toPoint.x - fromPoint.x) * t) * size.width,
                y: (fromPoint.y + (toPoint.y - fromPoint.y) * t) * size.height
            )

            // Calculate alpha for appearing/disappearing stars
            let alpha: CGFloat
            if i >= to.count {
                // Star is fading out
                alpha = 1 - t
            } else if i >= from.count {
                // Star is fading in
                alpha = t
            } else {
                alpha = 1
            }

            if alpha > 0.05 {
                result.append(InterpolatedPoint(point: interpolated, alpha: alpha))
            }
        }

        return result
    }

    private func drawConstellationLines(
        points: [CGPoint],
        in context: inout GraphicsContext,
        alpha: CGFloat
    ) {
        guard points.count > 1 else { return }

        // Draw lines connecting adjacent stars
        var path = Path()
        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]
            path.move(to: current)
            path.addLine(to: next)
        }

        // Soft glowing line
        context.stroke(
            path,
            with: .color(.white.opacity(Double(alpha))),
            style: StrokeStyle(lineWidth: 1, lineCap: .round)
        )
    }

    private func drawStar(
        at point: CGPoint,
        in context: inout GraphicsContext,
        twinkle: Double,
        baseAlpha: CGFloat
    ) {
        let alpha = Double(baseAlpha) * twinkle
        let glowRadius: CGFloat = 12 * CGFloat(twinkle)

        // Outer glow (large, soft)
        let outerGlow = Path(ellipseIn: CGRect(
            x: point.x - glowRadius,
            y: point.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        ))
        context.fill(
            outerGlow,
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.3 * alpha),
                    Color.white.opacity(0.1 * alpha),
                    Color.clear
                ]),
                center: point,
                startRadius: 0,
                endRadius: glowRadius
            )
        )

        // Mid glow (medium, brighter)
        let midGlowRadius: CGFloat = 6 * CGFloat(twinkle)
        let midGlow = Path(ellipseIn: CGRect(
            x: point.x - midGlowRadius,
            y: point.y - midGlowRadius,
            width: midGlowRadius * 2,
            height: midGlowRadius * 2
        ))
        context.fill(
            midGlow,
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.6 * alpha),
                    Color.clear
                ]),
                center: point,
                startRadius: 0,
                endRadius: midGlowRadius
            )
        )

        // Core (bright center point)
        let coreRadius: CGFloat = 2.5
        let core = Path(ellipseIn: CGRect(
            x: point.x - coreRadius,
            y: point.y - coreRadius,
            width: coreRadius * 2,
            height: coreRadius * 2
        ))
        context.fill(core, with: .color(.white.opacity(alpha)))

        // Sparkle rays (cross pattern)
        let rayLength: CGFloat = 8 * CGFloat(twinkle)
        var rays = Path()

        // Vertical ray
        rays.move(to: CGPoint(x: point.x, y: point.y - rayLength))
        rays.addLine(to: CGPoint(x: point.x, y: point.y + rayLength))

        // Horizontal ray
        rays.move(to: CGPoint(x: point.x - rayLength, y: point.y))
        rays.addLine(to: CGPoint(x: point.x + rayLength, y: point.y))

        // Diagonal rays (smaller)
        let diagLength = rayLength * 0.5
        rays.move(to: CGPoint(x: point.x - diagLength, y: point.y - diagLength))
        rays.addLine(to: CGPoint(x: point.x + diagLength, y: point.y + diagLength))
        rays.move(to: CGPoint(x: point.x + diagLength, y: point.y - diagLength))
        rays.addLine(to: CGPoint(x: point.x - diagLength, y: point.y + diagLength))

        context.stroke(
            rays,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0.8 * alpha),
                    Color.white.opacity(0.1 * alpha)
                ]),
                startPoint: CGPoint(x: point.x - rayLength, y: point.y),
                endPoint: CGPoint(x: point.x + rayLength, y: point.y)
            ),
            style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
        )
    }

    // Smoother easing function (Ken Perlin's smootherstep)
    private func smootherStep(_ t: Double) -> Double {
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("Animated Constellation") {
    ZStack {
        Color.black.ignoresSafeArea()

        AnimatedConstellation()
    }
}

#Preview("With Moon") {
    ZStack {
        Color.black.ignoresSafeArea()

        ZStack {
            AnimatedConstellation()

            Image(systemName: "moon.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(white: 0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .white.opacity(0.4), radius: 20, x: 0, y: 0)
        }
    }
}
