import SpriteKit
import SwiftUI
import UIKit

class SnowScene: SKScene {
    private var backgroundStars: SKEmitterNode?
    private var midgroundStars: SKEmitterNode?
    private var foregroundStars: SKEmitterNode?

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

        // Create 3 parallax layers for depth
        backgroundStars = createStarLayer(
            birthRate: 5,
            scale: 0.3,
            scaleRange: 0.15,
            speed: 1,
            alpha: 0.4,
            alphaSpeed: 0.4
        )

        midgroundStars = createStarLayer(
            birthRate: 6,
            scale: 0.5,
            scaleRange: 0.2,
            speed: 3,
            alpha: 0.6,
            alphaSpeed: 0.5
        )

        foregroundStars = createStarLayer(
            birthRate: 4,
            scale: 0.7,
            scaleRange: 0.3,
            speed: 6,
            alpha: 0.8,
            alphaSpeed: 0.6
        )

        // Add layers in order (back to front)
        addChild(backgroundStars!)
        addChild(midgroundStars!)
        addChild(foregroundStars!)
    }

    private func createStarLayer(
        birthRate: CGFloat,
        scale: CGFloat,
        scaleRange: CGFloat,
        speed: CGFloat,
        alpha: CGFloat,
        alphaSpeed: CGFloat
    ) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = makeStarTexture()
        emitter.particleBirthRate = birthRate
        emitter.numParticlesToEmit = 0 // Continuous emission

        // Particle lifetime (stars stay visible throughout splash)
        emitter.particleLifetime = 2.5
        emitter.particleLifetimeRange = 0.3

        // Particle size varies per layer for depth
        emitter.particleScale = scale
        emitter.particleScaleRange = scaleRange
        emitter.particleScaleSpeed = 0

        // Particle color (white stars)
        emitter.particleColor = .white
        emitter.particleColorBlendFactor = 1.0

        // Particle opacity varies per layer (distant = dimmer)
        emitter.particleAlpha = 0.0 // Start invisible
        emitter.particleAlphaRange = 0.3
        emitter.particleAlphaSpeed = alphaSpeed // Fade in creates appearance

        // Parallax motion - faster = closer
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.5
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2

        // Gentle drift across screen
        emitter.xAcceleration = 0
        emitter.yAcceleration = 0

        // Blend mode for soft glow on black background
        emitter.particleBlendMode = .alpha

        return emitter
    }

    private func updateEmitterLayout() {
        // Set black background to match app theme
        backgroundColor = .black

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let range = CGVector(dx: size.width * 0.9, dy: size.height * 0.9)

        // Position all layers in center with full screen coverage
        backgroundStars?.position = center
        backgroundStars?.particlePositionRange = range

        midgroundStars?.position = center
        midgroundStars?.particlePositionRange = range

        foregroundStars?.position = center
        foregroundStars?.particlePositionRange = range
    }

    private func makeStarTexture() -> SKTexture {
        let size = CGSize(width: 6, height: 6)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Add soft glow
            context.cgContext.setShadow(
                offset: .zero,
                blur: 2,
                color: UIColor.white.withAlphaComponent(0.8).cgColor
            )

            // Draw star as a bright point with cross pattern
            UIColor.white.setFill()

            // Center bright point
            let pointSize: CGFloat = 1.5
            let pointRect = CGRect(
                x: center.x - pointSize / 2,
                y: center.y - pointSize / 2,
                width: pointSize,
                height: pointSize
            )
            context.cgContext.fillEllipse(in: pointRect)

            // Add subtle cross sparkle
            context.cgContext.setLineWidth(0.5)
            context.cgContext.setLineCap(.round)
            UIColor.white.setStroke()

            // Vertical line
            context.cgContext.move(to: CGPoint(x: center.x, y: center.y - 2))
            context.cgContext.addLine(to: CGPoint(x: center.x, y: center.y + 2))

            // Horizontal line
            context.cgContext.move(to: CGPoint(x: center.x - 2, y: center.y))
            context.cgContext.addLine(to: CGPoint(x: center.x + 2, y: center.y))

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
