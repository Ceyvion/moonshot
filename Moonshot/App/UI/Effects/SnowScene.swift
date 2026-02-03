import SpriteKit
import SwiftUI
import UIKit

class SnowScene: SKScene {
    private var backgroundStars: SKEmitterNode?
    private var midgroundStars: SKEmitterNode?
    private var foregroundStars: SKEmitterNode?
    private var twinkleStars: SKEmitterNode?

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        setupStarsIfNeeded()
        updateEmitterLayout()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateEmitterLayout()
    }

    private func setupStarsIfNeeded() {
        guard backgroundStars == nil else { return }

        // Create 3 parallax layers for warp zoom depth effect
        // Stars spawn near center and zoom outward, growing larger
        backgroundStars = createWarpLayer(
            birthRate: 12,
            startScale: 0.05,
            scaleSpeed: 0.15,
            speed: 80,
            alpha: 0.5
        )

        midgroundStars = createWarpLayer(
            birthRate: 10,
            startScale: 0.08,
            scaleSpeed: 0.25,
            speed: 120,
            alpha: 0.7
        )

        foregroundStars = createWarpLayer(
            birthRate: 6,
            startScale: 0.12,
            scaleSpeed: 0.4,
            speed: 180,
            alpha: 0.9
        )

        // Add twinkle layer - stars that pulse/flicker
        twinkleStars = createTwinkleLayer()

        // Add layers in order (back to front)
        addChild(backgroundStars!)
        addChild(midgroundStars!)
        addChild(foregroundStars!)
        addChild(twinkleStars!)
    }

    private func createWarpLayer(
        birthRate: CGFloat,
        startScale: CGFloat,
        scaleSpeed: CGFloat,
        speed: CGFloat,
        alpha: CGFloat
    ) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeStarTexture()
        emitter.particleBirthRate = birthRate
        emitter.numParticlesToEmit = 0

        // Lifetime - how long stars travel before disappearing
        emitter.particleLifetime = 2.0
        emitter.particleLifetimeRange = 0.5

        // Start small, grow as they travel outward (zoom effect)
        emitter.particleScale = startScale
        emitter.particleScaleRange = startScale * 0.3
        emitter.particleScaleSpeed = scaleSpeed

        // White stars
        emitter.particleColor = .white
        emitter.particleColorBlendFactor = 1.0

        // Fade in quickly, then fade out at edges
        emitter.particleAlpha = 0.0
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = alpha * 0.8

        // Radial outward motion from center (warp effect)
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.3
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2

        // Slight acceleration for more dramatic zoom feel
        emitter.xAcceleration = 0
        emitter.yAcceleration = 0

        // Soft glow blend
        emitter.particleBlendMode = .add

        return emitter
    }

    private func createTwinkleLayer() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeStarTexture()
        emitter.particleBirthRate = 4
        emitter.numParticlesToEmit = 0

        // Longer lifetime for twinkle stars
        emitter.particleLifetime = 1.5
        emitter.particleLifetimeRange = 0.5

        // Medium size, slight growth
        emitter.particleScale = 0.15
        emitter.particleScaleRange = 0.1
        emitter.particleScaleSpeed = 0.3

        emitter.particleColor = .white
        emitter.particleColorBlendFactor = 1.0

        // Twinkle effect via rapid alpha oscillation
        emitter.particleAlpha = 0.0
        emitter.particleAlphaRange = 0.8
        emitter.particleAlphaSpeed = 2.0

        // Slower outward motion for twinkle layer
        emitter.particleSpeed = 100
        emitter.particleSpeedRange = 40
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2

        emitter.particleBlendMode = .add

        return emitter
    }

    private func updateEmitterLayout() {
        backgroundColor = .black

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Small spawn area near center - stars emanate from middle
        let spawnRange = CGVector(dx: 40, dy: 40)

        // All layers emit from center
        backgroundStars?.position = center
        backgroundStars?.particlePositionRange = spawnRange

        midgroundStars?.position = center
        midgroundStars?.particlePositionRange = spawnRange

        foregroundStars?.position = center
        foregroundStars?.particlePositionRange = spawnRange

        twinkleStars?.position = center
        twinkleStars?.particlePositionRange = spawnRange
    }

    private func makeStarTexture() -> SKTexture {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Soft glow
            context.cgContext.setShadow(
                offset: .zero,
                blur: 3,
                color: UIColor.white.withAlphaComponent(0.9).cgColor
            )

            UIColor.white.setFill()

            // Center bright point
            let pointSize: CGFloat = 2.0
            let pointRect = CGRect(
                x: center.x - pointSize / 2,
                y: center.y - pointSize / 2,
                width: pointSize,
                height: pointSize
            )
            context.cgContext.fillEllipse(in: pointRect)

            // Cross sparkle for star shape
            context.cgContext.setLineWidth(0.6)
            context.cgContext.setLineCap(.round)
            UIColor.white.setStroke()

            // Vertical line
            context.cgContext.move(to: CGPoint(x: center.x, y: center.y - 3))
            context.cgContext.addLine(to: CGPoint(x: center.x, y: center.y + 3))

            // Horizontal line
            context.cgContext.move(to: CGPoint(x: center.x - 3, y: center.y))
            context.cgContext.addLine(to: CGPoint(x: center.x + 3, y: center.y))

            context.cgContext.strokePath()
        }
        return SKTexture(image: image)
    }
}

// SwiftUI wrapper for SpriteKit scene (star field effect)
struct SnowView: View {
    let scene: SnowScene

    init() {
        let scene = SnowScene()
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .black
        self.scene = scene
    }

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .ignoresSafeArea()
            .background(Color.black)
    }
}
