import Foundation
import SceneKit
import UIKit

/// Particle and flash effects, built in code.
///
/// Everything here is procedural rather than a `.scnp` file, for one reason: a
/// code-built system can be tinted per element and scaled per unit height at the
/// moment it is spawned. `Docs/ART_PIPELINE.md` lists the texture slots that
/// upgrade these in place — drop `spark.png` into the bundle and every effect
/// that references it improves without a code change.
enum VFXLibrary {

    /// Named effects referenced from `Skill.vfx`. Unknown names fall through to
    /// the generic impact, so a skill can name an effect before it exists.
    static func spawn(
        _ identifier: String,
        at position: SCNVector3,
        in scene: SCNScene,
        tint: UIColor,
        scale: Float = 1.0
    ) {
        let host = SCNNode()
        host.position = position
        scene.rootNode.addChildNode(host)

        switch identifier {
        case "scale_strike":
            host.addParticleSystem(sparks(tint: tint, count: 60, speed: 5, scale: scale))
            flash(at: position, in: scene, color: tint, radius: 1.2 * scale, duration: 0.18)
        case "heart_weigh":
            addBoltColumn(to: host, tint: tint, scale: scale)
            host.addParticleSystem(sparks(tint: tint, count: 160, speed: 9, scale: scale))
            flash(at: position, in: scene, color: tint, radius: 2.6 * scale, duration: 0.3)
        case "duat_rite":
            addStormRing(to: host, tint: tint, scale: scale)
            host.addParticleSystem(sparks(tint: tint, count: 260, speed: 12, scale: scale * 1.4))
            flash(at: position, in: scene, color: tint, radius: 4.5 * scale, duration: 0.5)
        case "maat_shield":
            host.addParticleSystem(rising(tint: tint, count: 90, scale: scale))
        case "heal":
            host.addParticleSystem(rising(tint: UIColor(hex: "#7FE8A0")!, count: 50, scale: scale))
        case "buff":
            host.addParticleSystem(rising(tint: UIColor(hex: "#6BD8F2")!, count: 40, scale: scale))
        case "debuff":
            host.addParticleSystem(falling(tint: UIColor(hex: "#C86BE0")!, count: 40, scale: scale))
        case "crit":
            host.addParticleSystem(sparks(tint: UIColor(hex: "#FFD24F")!, count: 90, speed: 7, scale: scale))
            flash(at: position, in: scene, color: UIColor(hex: "#FFD24F")!, radius: 1.6 * scale, duration: 0.2)
        default:
            host.addParticleSystem(sparks(tint: tint, count: 40, speed: 4, scale: scale))
        }

        // Particle hosts clean themselves up; nothing accumulates in the scene.
        host.runAction(.sequence([.wait(duration: 3.0), .removeFromParentNode()]))
    }

    // MARK: - Particle systems

    private static func base(scale: Float) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.loops = false
        system.birthLocation = .volume
        system.emissionDuration = 0.12
        system.particleSize = CGFloat(0.05 * scale)
        system.particleSizeVariation = CGFloat(0.03 * scale)
        system.particleLifeSpan = 0.7
        system.particleLifeSpanVariation = 0.3
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.sortingMode = .distance
        // Upgraded automatically if `spark.png` ships in the bundle.
        if let image = UIImage(named: "spark") {
            system.particleImage = image
        }
        return system
    }

    private static func sparks(tint: UIColor, count: Int, speed: CGFloat, scale: Float) -> SCNParticleSystem {
        let system = base(scale: scale)
        system.birthRate = CGFloat(count) / 0.12
        system.particleVelocity = speed
        system.particleVelocityVariation = speed * 0.6
        system.spreadingAngle = 180
        system.particleColor = tint
        system.particleColorVariation = SCNVector4(0.05, 0.05, 0.1, 0)
        system.acceleration = SCNVector3(0, -6, 0)
        system.dampingFactor = 0.6
        return system
    }

    private static func rising(tint: UIColor, count: Int, scale: Float) -> SCNParticleSystem {
        let system = base(scale: scale)
        system.birthRate = CGFloat(count) / 0.4
        system.emissionDuration = 0.4
        system.particleVelocity = 1.6
        system.particleVelocityVariation = 0.5
        system.spreadingAngle = 25
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.particleColor = tint
        system.particleLifeSpan = 1.1
        system.acceleration = SCNVector3(0, 1.2, 0)
        return system
    }

    private static func falling(tint: UIColor, count: Int, scale: Float) -> SCNParticleSystem {
        let system = rising(tint: tint, count: count, scale: scale)
        system.emittingDirection = SCNVector3(0, -1, 0)
        system.acceleration = SCNVector3(0, -2.0, 0)
        return system
    }

    // MARK: - Geometry effects

    /// The vertical strike for Thunderbolt.
    private static func addBoltColumn(to host: SCNNode, tint: UIColor, scale: Float) {
        let column = SCNCylinder(radius: CGFloat(0.09 * scale), height: CGFloat(9 * scale))
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = tint
        material.emission.contents = tint
        material.blendMode = .add
        material.writesToDepthBuffer = false
        column.firstMaterial = material

        let node = SCNNode(geometry: column)
        node.position = SCNVector3(0, Float(4.4 * scale), 0)
        node.opacity = 0
        host.addChildNode(node)

        node.runAction(.sequence([
            .fadeOpacity(to: 1.0, duration: 0.04),
            .fadeOpacity(to: 0.0, duration: 0.28),
            .removeFromParentNode()
        ]))
    }

    /// The expanding shockwave for the ultimate.
    private static func addStormRing(to host: SCNNode, tint: UIColor, scale: Float) {
        let ring = SCNTorus(ringRadius: CGFloat(0.4 * scale), pipeRadius: CGFloat(0.05 * scale))
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = tint
        material.emission.contents = tint
        material.blendMode = .add
        material.writesToDepthBuffer = false
        ring.firstMaterial = material

        let node = SCNNode(geometry: ring)
        node.position = SCNVector3(0, 0.15, 0)
        host.addChildNode(node)

        node.runAction(.sequence([
            .group([
                .scale(to: CGFloat(9 * scale), duration: 0.55),
                .fadeOpacity(to: 0, duration: 0.55)
            ]),
            .removeFromParentNode()
        ]))
    }

    /// A short-lived point light, which is what actually sells an impact.
    private static func flash(
        at position: SCNVector3,
        in scene: SCNScene,
        color: UIColor,
        radius: Float,
        duration: TimeInterval
    ) {
        let light = SCNLight()
        light.type = .omni
        light.color = color
        light.intensity = 4_000
        light.attenuationEndDistance = CGFloat(radius * 4)

        let node = SCNNode()
        node.light = light
        node.position = position
        scene.rootNode.addChildNode(node)

        node.runAction(.sequence([
            .customAction(duration: duration) { node, elapsed in
                let t = Float(elapsed) / Float(duration)
                node.light?.intensity = CGFloat(4_000 * (1 - t))
            },
            .removeFromParentNode()
        ]))
    }

    /// The beam that drops a summoned unit onto the reveal stage.
    static func summonBeam(at position: SCNVector3, in scene: SCNScene, tint: UIColor) {
        let host = SCNNode()
        host.position = position
        scene.rootNode.addChildNode(host)

        let beam = SCNCylinder(radius: 0.8, height: 14)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = tint.withAlphaComponent(0.25)
        material.emission.contents = tint
        material.blendMode = .add
        material.writesToDepthBuffer = false
        beam.firstMaterial = material

        let node = SCNNode(geometry: beam)
        node.position = SCNVector3(0, 7, 0)
        node.scale = SCNVector3(0.05, 1, 0.05)
        host.addChildNode(node)

        node.runAction(.sequence([
            .scale(to: 1.0, duration: 0.35),
            .wait(duration: 0.5),
            .group([.scale(to: 0.02, duration: 0.5), .fadeOut(duration: 0.5)]),
            .removeFromParentNode()
        ]))

        host.addParticleSystem(rising(tint: tint, count: 200, scale: 2.0))
        host.runAction(.sequence([.wait(duration: 4), .removeFromParentNode()]))
    }
}
