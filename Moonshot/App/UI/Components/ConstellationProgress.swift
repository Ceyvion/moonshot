import SwiftUI

/// A progress indicator that morphs between 5 constellation patterns
struct ConstellationProgress: View {
    let progress: Double // 0.0 to 1.0

    // Define 5 constellation patterns (normalized coordinates 0-1)
    private let constellations: [[CGPoint]] = [
        // Stage 1: Single star (0-0.2)
        [
            CGPoint(x: 0.5, y: 0.5)
        ],

        // Stage 2: Crescent moon (0.2-0.4)
        [
            CGPoint(x: 0.4, y: 0.3),
            CGPoint(x: 0.35, y: 0.5),
            CGPoint(x: 0.4, y: 0.7)
        ],

        // Stage 3: Triangle constellation (0.4-0.6)
        [
            CGPoint(x: 0.5, y: 0.2),
            CGPoint(x: 0.3, y: 0.7),
            CGPoint(x: 0.7, y: 0.7)
        ],

        // Stage 4: Diamond/Orion pattern (0.6-0.8)
        [
            CGPoint(x: 0.5, y: 0.2),
            CGPoint(x: 0.3, y: 0.5),
            CGPoint(x: 0.7, y: 0.5),
            CGPoint(x: 0.5, y: 0.8)
        ],

        // Stage 5: Complete star circle (0.8-1.0)
        [
            CGPoint(x: 0.5, y: 0.15),
            CGPoint(x: 0.7, y: 0.3),
            CGPoint(x: 0.75, y: 0.6),
            CGPoint(x: 0.5, y: 0.8),
            CGPoint(x: 0.25, y: 0.6),
            CGPoint(x: 0.3, y: 0.3)
        ]
    ]

    var body: some View {
        Canvas { context, size in
            let currentPoints = interpolatedConstellation(size: size)

            // Draw constellation lines
            if currentPoints.count > 1 {
                var path = Path()
                for i in 0..<currentPoints.count {
                    let current = currentPoints[i]
                    let next = currentPoints[(i + 1) % currentPoints.count]

                    path.move(to: current)
                    path.addLine(to: next)
                }

                context.stroke(
                    path,
                    with: .color(.white.opacity(0.3)),
                    lineWidth: 1
                )
            }

            // Draw stars at constellation points
            for point in currentPoints {
                drawStar(at: point, in: context)
            }
        }
        .frame(width: 140, height: 140)
    }

    private func interpolatedConstellation(size: CGSize) -> [CGPoint] {
        // Determine which two constellations to interpolate between
        let clampedProgress = max(0, min(1, progress))
        let stageIndex = clampedProgress * Double(constellations.count - 1)
        let fromIndex = Int(floor(stageIndex))
        let toIndex = min(fromIndex + 1, constellations.count - 1)
        let t = CGFloat(stageIndex - Double(fromIndex)) // 0-1 within stage

        let fromConstellation = constellations[fromIndex]
        let toConstellation = constellations[toIndex]

        // Interpolate between constellations
        let maxPoints = max(fromConstellation.count, toConstellation.count)
        var result: [CGPoint] = []

        for i in 0..<maxPoints {
            let fromPoint = fromConstellation[safe: i] ?? fromConstellation.last ?? .zero
            let toPoint = toConstellation[safe: i] ?? toConstellation.last ?? .zero

            // Smooth interpolation
            let interpolated = CGPoint(
                x: fromPoint.x + (toPoint.x - fromPoint.x) * t,
                y: fromPoint.y + (toPoint.y - fromPoint.y) * t
            )

            // Convert normalized coordinates to actual size
            let actual = CGPoint(
                x: interpolated.x * size.width,
                y: interpolated.y * size.height
            )

            // Fade out extra points when transitioning to fewer points
            let alpha: CGFloat
            if i >= toConstellation.count {
                alpha = 1 - t // Fade out
            } else if i >= fromConstellation.count {
                alpha = t // Fade in
            } else {
                alpha = 1
            }

            if alpha > 0.1 {
                result.append(actual)
            }
        }

        return result
    }

    private func drawStar(at point: CGPoint, in context: GraphicsContext) {
        // Draw glow
        let glowPath = Path(ellipseIn: CGRect(
            x: point.x - 8,
            y: point.y - 8,
            width: 16,
            height: 16
        ))
        context.fill(
            glowPath,
            with: .radialGradient(
                Gradient(colors: [
                    .white.opacity(0.4),
                    .clear
                ]),
                center: point,
                startRadius: 0,
                endRadius: 8
            )
        )

        // Draw star center
        let starPath = Path(ellipseIn: CGRect(
            x: point.x - 2.5,
            y: point.y - 2.5,
            width: 5,
            height: 5
        ))
        context.fill(starPath, with: .color(.white))

        // Draw sparkle cross
        var crossPath = Path()
        crossPath.move(to: CGPoint(x: point.x, y: point.y - 6))
        crossPath.addLine(to: CGPoint(x: point.x, y: point.y + 6))
        crossPath.move(to: CGPoint(x: point.x - 6, y: point.y))
        crossPath.addLine(to: CGPoint(x: point.x + 6, y: point.y))

        context.stroke(
            crossPath,
            with: .color(.white.opacity(0.8)),
            style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
        )
    }
}

// Helper extension for safe array access
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            ConstellationProgress(progress: 0.0)
            ConstellationProgress(progress: 0.25)
            ConstellationProgress(progress: 0.5)
            ConstellationProgress(progress: 0.75)
            ConstellationProgress(progress: 1.0)
        }
    }
}
