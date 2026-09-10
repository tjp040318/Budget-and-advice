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

        // An effect authored in Xcode's particle editor (File → New → File →
        // SceneKit Particle System) and dropped into the bundle as
        // `<identifier>.scnp` replaces the code-built one below, colours and
        // all: any hit can be designed by hand, with no code.
        if let authored = authoredSystem(identifier) {
            host.addParticleSystem(authored)
            host.scale = SCNVector3(scale, scale, scale)
            flash(at: position, in: scene, color: tint, radius: 1.4 * scale, duration: 0.2)
            host.runAction(.sequence([.wait(duration: 3.0), .removeFromParentNode()]))
            return
        }

        switch identifier {
        // A hit in each element, for every skill that has no effect of its
        // own: fire bursts up, water breaks and falls, wind scatters, light
        // flares, shadow smokes. The tint is the caster's aura, so a fire
        // Anubis and a fire Zeus burn in their own oranges.
        case "impact_ember":
            // The Veo explosion, when its sheet is in the bundle: 32 frames
            // of a fireball rolling out and thinning to smoke.
            if let burst = flipbook("fireburst", rows: 4, cols: 8, tint: tint.mixed(with: .white, amount: 0.5),
                                    size: 2.4 * CGFloat(scale), life: 0.75) {
                host.addParticleSystem(burst)
            }
            if let flameImage = sprite("flame"), let ember = sprite("ember") {
                host.addParticleSystem(puff(flameImage, tint: tint.mixed(with: .white, amount: 0.25), count: 9, speed: 1.8,
                                            size: 0.6 * CGFloat(scale), life: 0.5, spread: 45, lift: 2.4, spin: 0.8))
                host.addParticleSystem(puff(ember, tint: tint, count: 40, speed: 5, size: 0.13 * CGFloat(scale),
                                            life: 0.65, spread: 180, lift: -6, spin: 0))
            } else {
                host.addParticleSystem(sparks(tint: tint, count: 70, speed: 5, scale: scale))
                host.addParticleSystem(rising(tint: tint, count: 40, scale: scale * 0.8))
            }
            flash(at: position, in: scene, color: tint, radius: 1.4 * scale, duration: 0.2)
        case "impact_tide":
            if let splash = sprite("splash"), let shard = sprite("shard") {
                host.addParticleSystem(puff(splash, tint: tint.mixed(with: .white, amount: 0.3), count: 3, speed: 0.3,
                                            size: 1.3 * CGFloat(scale), life: 0.45, spread: 30, lift: 0.5, spin: 0.3, grow: 1.8))
                host.addParticleSystem(puff(shard, tint: tint, count: 24, speed: 4.5, size: 0.22 * CGFloat(scale),
                                            life: 0.6, spread: 180, lift: -9, spin: 4))
            } else {
                host.addParticleSystem(sparks(tint: tint, count: 50, speed: 4, scale: scale))
                host.addParticleSystem(falling(tint: tint, count: 60, scale: scale))
            }
            flash(at: position, in: scene, color: tint, radius: 1.2 * scale, duration: 0.2)
        case "impact_gale":
            if let slash = sprite("slash"), let leaf = sprite("leaf") {
                host.addParticleSystem(puff(slash, tint: tint.mixed(with: .white, amount: 0.4), count: 6, speed: 3.5,
                                            size: 0.8 * CGFloat(scale), life: 0.35, spread: 180, lift: 0, spin: 10, grow: 1.4))
                host.addParticleSystem(puff(leaf, tint: tint, count: 16, speed: 4, size: 0.16 * CGFloat(scale),
                                            life: 0.8, spread: 180, lift: -2, spin: 6))
            } else {
                host.addParticleSystem(sparks(tint: tint, count: 90, speed: 8, scale: scale * 0.8))
            }
            flash(at: position, in: scene, color: tint, radius: 1.0 * scale, duration: 0.14)
        case "impact_radiance":
            if let flare = sprite("flare"), let ring = sprite("ring") {
                host.addParticleSystem(puff(flare, tint: tint.mixed(with: .white, amount: 0.5), count: 1, speed: 0,
                                            size: 1.6 * CGFloat(scale), life: 0.4, spread: 0, lift: 0, spin: 0.5, grow: 1.9))
                host.addParticleSystem(puff(ring, tint: tint, count: 1, speed: 0, size: 0.6 * CGFloat(scale),
                                            life: 0.45, spread: 0, lift: 0, spin: 0, grow: 4.5))
                host.addParticleSystem(puff(flare, tint: tint, count: 14, speed: 4, size: 0.18 * CGFloat(scale),
                                            life: 0.6, spread: 180, lift: 1, spin: 2))
            } else {
                host.addParticleSystem(rising(tint: tint, count: 70, scale: scale))
            }
            flash(at: position, in: scene, color: tint, radius: 2.0 * scale, duration: 0.26)
        case "impact_umbra":
            if let wisp = sprite("wisp"), let smoke = sprite("smoke") {
                host.addParticleSystem(puff(smoke, tint: tint.mixed(with: .black, amount: 0.3), count: 5, speed: 0.8,
                                            size: 0.9 * CGFloat(scale), life: 0.8, spread: 90, lift: 0.6, spin: 0.6,
                                            blend: .alpha, grow: 2.0))
                host.addParticleSystem(puff(wisp, tint: tint, count: 8, speed: 1.6, size: 0.5 * CGFloat(scale),
                                            life: 0.7, spread: 60, lift: 1.8, spin: 1.5))
            } else {
                host.addParticleSystem(falling(tint: tint, count: 50, scale: scale * 1.2))
                host.addParticleSystem(sparks(tint: tint, count: 30, speed: 3, scale: scale))
            }
            flash(at: position, in: scene, color: tint, radius: 1.2 * scale, duration: 0.22)
        // The stroke of a closing strike: a bright arc across the victim that
        // grows in and fades in a quarter of a second.
        case "slash":
            addSlash(to: host, tint: tint, scale: scale)
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

        // Sekhmet. Claws, the beam of the sun, the Eye let loose on the line.
        case "lioness_rake":
            host.addParticleSystem(sparks(tint: tint, count: 70, speed: 6, scale: scale))
            flash(at: position, in: scene, color: tint, radius: 1.1 * scale, duration: 0.15)
        case "eye_of_ra":
            addBoltColumn(to: host, tint: tint, scale: scale)
            host.addParticleSystem(sparks(tint: tint, count: 150, speed: 9, scale: scale))
            flash(at: position, in: scene, color: tint, radius: 2.6 * scale, duration: 0.3)
        case "wrath_of_the_eye":
            addStormRing(to: host, tint: tint, scale: scale)
            host.addParticleSystem(sparks(tint: tint, count: 240, speed: 12, scale: scale * 1.3))
            flash(at: position, in: scene, color: tint, radius: 4.5 * scale, duration: 0.5)
        case "blood_thirst":
            host.addParticleSystem(rising(tint: UIColor(hex: "#E0453C")!, count: 80, scale: scale))

        // Zeus. Every effect is a real forked bolt out of the sky, and the sky
        // itself flashes: a second light far overhead lights the whole arena
        // for a frame or two, which is what makes lightning read as lightning.
        case "thunderbolt":
            addLightningBolt(to: host, tint: tint, scale: scale, thickness: 0.05, height: 9, forks: 1)
            skyFlash(over: position, in: scene, scale: scale, duration: 0.12)
            host.addParticleSystem(sparks(tint: tint, count: 90, speed: 7, scale: scale))
            flash(at: position, in: scene, color: tint, radius: 2.2 * scale, duration: 0.22)
        case "thunderclap":
            addLightningBolt(to: host, tint: tint, scale: scale, thickness: 0.035, height: 8, forks: 0)
            addStormRing(to: host, tint: tint, scale: scale * 0.6)
            skyFlash(over: position, in: scene, scale: scale, duration: 0.18)
            host.addParticleSystem(sparks(tint: tint, count: 120, speed: 8, scale: scale))
            flash(at: position, in: scene, color: tint, radius: 2.8 * scale, duration: 0.25)
        case "keraunos":
            addLightningBolt(to: host, tint: tint, scale: scale, thickness: 0.09, height: 11, forks: 3)
            addBoltColumn(to: host, tint: tint, scale: scale)
            skyFlash(over: position, in: scene, scale: scale, duration: 0.22)
            host.addParticleSystem(sparks(tint: tint, count: 260, speed: 12, scale: scale * 1.3))
            flash(at: position, in: scene, color: tint, radius: 4.5 * scale, duration: 0.45)
        case "olympian_decree":
            host.addParticleSystem(rising(tint: tint, count: 120, scale: scale))
            flash(at: position, in: scene, color: tint, radius: 2.0 * scale, duration: 0.3)
        default:
            host.addParticleSystem(sparks(tint: tint, count: 40, speed: 4, scale: scale))
        }

        // Particle hosts clean themselves up; nothing accumulates in the scene.
        host.runAction(.sequence([.wait(duration: 3.0), .removeFromParentNode()]))
    }

    // MARK: - Authored systems

    /// `<identifier>.scnp` from the bundle, looked up once per name; the
    /// file's own template is copied for every spawn.
    private static var authoredCache: [String: SCNParticleSystem?] = [:]

    private static func authoredSystem(_ identifier: String) -> SCNParticleSystem? {
        if let cached = authoredCache[identifier] {
            return cached?.copy() as? SCNParticleSystem
        }
        let system = SCNParticleSystem(named: "\(identifier).scnp", inDirectory: nil)
        authoredCache[identifier] = system
        return system?.copy() as? SCNParticleSystem
    }

    // MARK: - Painted sprites

    /// The painted effect sprites — `tools/batch/vfx_sprites.sh` paints them
    /// with Gemini on black, `tools/vfx_ship.py` ships them as `vfx_<name>`
    /// with a real alpha channel — by name. Nil until one ships, and every
    /// effect above keeps the spark it had. The owner: "the effects like the
    /// fire or hits and stuff we need to really work on ... a fireball, it
    /// cant be your bullshit red circle."
    private static var spriteCache: [String: UIImage?] = [:]

    static func sprite(_ name: String) -> UIImage? {
        if let cached = spriteCache[name] { return cached }
        let image = UIImage(named: "vfx_\(name)")
        spriteCache[name] = image
        return image
    }

    /// A curve for a particle property over its life.
    private static func curve(_ values: [NSNumber], _ times: [NSNumber]) -> SCNParticlePropertyController {
        let animation = CAKeyframeAnimation()
        animation.values = values
        animation.keyTimes = times
        return SCNParticlePropertyController(animation: animation)
    }

    /// A burst of painted sprites: `count` copies thrown from a point,
    /// screen-facing, spinning, growing by `grow` and fading out over `life`
    /// seconds, lifted (or dropped, negative) by `lift`.
    private static func puff(
        _ image: UIImage, tint: UIColor, count: Int, speed: CGFloat, size: CGFloat, life: CGFloat,
        spread: CGFloat, lift: Float, spin: CGFloat, blend: SCNParticleBlendMode = .additive, grow: CGFloat = 1.5
    ) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.loops = false
        system.emissionDuration = 0.08
        system.birthRate = CGFloat(count) / 0.08
        system.birthLocation = .volume
        system.emitterShape = SCNSphere(radius: 0.12)
        system.particleImage = image
        system.particleSize = size
        system.particleSizeVariation = size * 0.3
        system.particleLifeSpan = life
        system.particleLifeSpanVariation = life * 0.3
        system.particleVelocity = speed
        system.particleVelocityVariation = speed * 0.5
        system.spreadingAngle = spread
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.particleColor = tint
        system.particleAngleVariation = 180
        system.particleAngularVelocity = spin * 60
        system.particleAngularVelocityVariation = spin * 60
        system.acceleration = SCNVector3(0, lift, 0)
        system.isAffectedByGravity = false
        system.blendMode = blend
        system.isLightingEnabled = false
        system.orientationMode = .billboardScreenAligned
        system.sortingMode = .distance
        system.propertyControllers = [
            .size: curve([NSNumber(value: Double(size * 0.7)), NSNumber(value: Double(size * grow))], [0, 1]),
            .opacity: curve([1, 1, 0], [0, 0.45, 1]),
        ]
        return system
    }

    /// A flipbook: one big screen-facing particle playing a sheet of frames
    /// over its life — an explosion that rolls and dissipates, from a Veo
    /// clip cut by `tools/veo.py sheet` (rows by cols of frames, first frame
    /// top-left). Nil until the sheet ships.
    private static func flipbook(_ name: String, rows: Int, cols: Int, tint: UIColor, size: CGFloat, life: CGFloat)
        -> SCNParticleSystem? {
        guard let image = sprite("\(name)_sheet") else { return nil }
        let system = SCNParticleSystem()
        system.loops = false
        system.emissionDuration = 0.01
        system.birthRate = 100
        system.particleImage = image
        system.imageSequenceRowCount = rows
        system.imageSequenceColumnCount = cols
        system.imageSequenceFrameRate = CGFloat(rows * cols) / life
        system.imageSequenceInitialFrame = 0
        system.imageSequenceAnimationMode = .clamp
        system.particleSize = size
        system.particleLifeSpan = life
        system.particleVelocity = 0
        system.particleColor = tint
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.orientationMode = .billboardScreenAligned
        system.isAffectedByGravity = false
        // The sheet is the burst; the fade is the dissipating.
        system.propertyControllers = [.opacity: curve([1, 1, 0], [0, 0.5, 1])]
        return system
    }

    /// A painted sprite flying from the caster to the victim: the element's
    /// fireball, water, wind blade, flare or shadow, screen-facing, trailing,
    /// on a low arc for the thrown ones and nearly straight for the rest;
    /// gone on arrival, which is the frame the impact bursts on. Without the
    /// sprite nothing flies and the impact still lands.
    static func projectile(
        _ element: Element, from start: SCNVector3, to end: SCNVector3, in scene: SCNScene,
        tint: UIColor, duration: TimeInterval, scale: Float
    ) {
        let name: String
        let size: CGFloat
        let arc: Float
        let spin: CGFloat
        let trail: String
        switch element {
        case .ember: (name, size, arc, spin, trail) = ("fireball", 0.9, 1.1, 0, "ember")
        case .tide: (name, size, arc, spin, trail) = ("splash", 0.7, 0.7, 2, "shard")
        case .gale: (name, size, arc, spin, trail) = ("slash", 0.9, 0.15, 12, "leaf")
        case .radiance: (name, size, arc, spin, trail) = ("flare", 0.8, 0.3, 1.5, "flare")
        case .umbra: (name, size, arc, spin, trail) = ("wisp", 0.8, 0.6, 2, "wisp")
        }
        guard let image = sprite(name) else { return }

        let host = SCNNode()
        host.position = start
        host.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(host)

        let plane = SCNPlane(width: size * CGFloat(scale), height: size * CGFloat(scale))
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.emission.contents = image
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        plane.firstMaterial = material
        let spriteNode = SCNNode(geometry: plane)
        // The fireball's tail is painted to the left; when the shot flies
        // toward the camera's left the sprite is mirrored so the tail trails.
        let screenRight = SCNVector3(cos(CameraDirector.homeYaw), 0, sin(CameraDirector.homeYaw))
        let flight = SCNVector3(end.x - start.x, end.y - start.y, end.z - start.z)
        if flight.x * screenRight.x + flight.z * screenRight.z < 0 {
            spriteNode.scale = SCNVector3(-1, 1, 1)
        }
        if spin > 0 {
            spriteNode.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: spin, duration: 1)))
        }
        host.addChildNode(spriteNode)

        if let trailImage = sprite(trail) {
            let system = puff(trailImage, tint: tint, count: 1, speed: 0.6, size: 0.16 * CGFloat(scale), life: 0.35,
                              spread: 180, lift: element == .ember ? 1.5 : 0, spin: 3)
            system.loops = true
            system.emissionDuration = 1
            system.birthRate = 70
            host.addParticleSystem(system)
        }
        flash(at: start, in: scene, color: tint, radius: 0.8 * scale, duration: 0.12)

        let rise = arc * scale
        let fly = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = Float(elapsed / CGFloat(duration))
            node.position = SCNVector3(
                start.x + flight.x * t,
                start.y + flight.y * t + rise * sin(t * .pi),
                start.z + flight.z * t
            )
        }
        host.runAction(.sequence([fly, .removeFromParentNode()]))
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

    /// A brazier's fire: an endless rise of bright motes from a small disc,
    /// fast and short-lived, in the flame's colour.
    static func flame(tint: UIColor, scale: Float) -> SCNParticleSystem {
        let system = base(scale: scale)
        system.loops = true
        system.emissionDuration = 1.0
        system.idleDuration = 0
        system.birthRate = 34
        system.birthLocation = .volume
        system.emitterShape = SCNCylinder(radius: CGFloat(0.22 * scale), height: 0.02)
        system.particleSize = CGFloat(0.11 * scale)
        system.particleSizeVariation = CGFloat(0.05 * scale)
        system.particleVelocity = 1.3
        system.particleVelocityVariation = 0.5
        system.spreadingAngle = 12
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.particleColor = tint
        system.particleColorVariation = SCNVector4(0.06, 0.08, 0.02, 0)
        system.particleLifeSpan = 0.75
        system.particleLifeSpanVariation = 0.3
        system.acceleration = SCNVector3(0, 1.6, 0)
        system.isAffectedByGravity = false
        return system
    }

    /// Slow motes in the air over a stage: few, small, long-lived, drifting
    /// through a box volume.
    static func dust(tint: UIColor, volume: SCNVector3) -> SCNParticleSystem {
        let system = base(scale: 1)
        system.loops = true
        system.emissionDuration = 1.0
        system.idleDuration = 0
        system.birthRate = 7
        system.birthLocation = .volume
        system.emitterShape = SCNBox(width: CGFloat(volume.x), height: CGFloat(volume.y), length: CGFloat(volume.z), chamferRadius: 0)
        system.particleSize = 0.035
        system.particleSizeVariation = 0.02
        system.particleVelocity = 0.12
        system.particleVelocityVariation = 0.1
        system.spreadingAngle = 180
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.particleColor = tint.withAlphaComponent(0.6)
        system.particleLifeSpan = 7
        system.particleLifeSpanVariation = 3
        system.acceleration = SCNVector3(0, 0.02, 0)
        system.isAffectedByGravity = false
        return system
    }

    /// The awakened aura: a thin, endless rise of light from a disc at the
    /// feet. Attached to a unit's model node, not spawned and removed.
    static func aura(tint: UIColor, scale: Float) -> SCNParticleSystem {
        let system = base(scale: scale)
        system.loops = true
        system.emissionDuration = 1.0
        system.idleDuration = 0
        system.birthRate = 16
        system.birthLocation = .volume
        system.emitterShape = SCNCylinder(radius: CGFloat(0.42 * scale), height: 0.02)
        system.particleSize = CGFloat(0.045 * scale)
        system.particleSizeVariation = CGFloat(0.02 * scale)
        system.particleVelocity = 0.45
        system.particleVelocityVariation = 0.2
        system.spreadingAngle = 8
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.particleColor = tint.withAlphaComponent(0.85)
        system.particleLifeSpan = 1.6
        system.particleLifeSpanVariation = 0.4
        system.acceleration = SCNVector3(0, 0.35, 0)
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
    private static var slashCache: [String: UIImage] = [:]

    /// A slash arc: a long thin plane carrying a white-to-tint streak, tilted
    /// across the target, scaled up from nothing and faded. Billboarded, so
    /// it reads from the fixed camera whichever way the strike came.
    private static func addSlash(to host: SCNNode, tint: UIColor, scale: Float) {
        let plane = SCNPlane(width: CGFloat(1.9 * scale), height: CGFloat(0.42 * scale))
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = slashImage(tint: tint)
        material.blendMode = .add
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        node.renderingOrder = 900
        node.eulerAngles.z = Float.random(in: 0.5...0.9) * (Bool.random() ? 1 : -1)
        node.scale = SCNVector3(0.2, 0.2, 0.2)
        node.opacity = 0
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        host.addChildNode(node)

        let grow = SCNAction.scale(to: 1.0, duration: 0.1)
        grow.timingMode = .easeOut
        node.runAction(.sequence([
            .group([grow, .fadeIn(duration: 0.05)]),
            .wait(duration: 0.06),
            .group([.fadeOut(duration: 0.16), .scale(to: 1.15, duration: 0.16)]),
            .removeFromParentNode(),
        ]))
        host.runAction(.sequence([.wait(duration: 0.6), .removeFromParentNode()]))
    }

    private static func slashImage(tint: UIColor) -> UIImage {
        let key = "\(tint.hashValue)"
        if let cached = slashCache[key] { return cached }
        let size = CGSize(width: 256, height: 56)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            // A streak that is white-hot in the middle and the tint at the
            // ends, thinning to points, over a transparent ground.
            let colors = [UIColor.clear.cgColor, tint.cgColor, UIColor.white.cgColor, tint.cgColor, UIColor.clear.cgColor] as CFArray
            let locations: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addQuadCurve(to: CGPoint(x: size.width, y: size.height / 2), controlPoint: CGPoint(x: size.width / 2, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0, y: size.height / 2), controlPoint: CGPoint(x: size.width / 2, y: size.height))
            path.close()
            cg.saveGState()
            path.addClip()
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: 0), options: [])
            cg.restoreGState()
        }
        if slashCache.count > 32 { slashCache.removeAll() }
        slashCache[key] = image
        return image
    }

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

    /// A forked bolt from the sky to the impact point. Seven thin segments with a
    /// random sideways stagger, each a hot white core inside a wider tinted
    /// glow, plus `forks` branches that leave the trunk part-way down. It is
    /// on screen for a third of a second, which is the right amount of lightning.
    private static func addLightningBolt(
        to host: SCNNode,
        tint: UIColor,
        scale: Float,
        thickness: Float,
        height: Float,
        forks: Int
    ) {
        let bolt = SCNNode()
        bolt.opacity = 0
        host.addChildNode(bolt)

        let steps = 7
        var trunk: [SCNVector3] = []
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let wobble: Float = (i == 0 || i == steps) ? 0 : 0.45 * scale
            trunk.append(SCNVector3(
                Float.random(in: -wobble...wobble),
                height * scale * (1 - t),
                Float.random(in: -wobble...wobble)
            ))
        }
        addSegments(trunk, to: bolt, tint: tint, thickness: thickness * scale)

        for _ in 0..<max(0, forks) {
            let start = trunk[Int.random(in: 2...(steps - 2))]
            let sideX: Float = Bool.random() ? 1 : -1
            let sideZ: Float = Bool.random() ? 1 : -1
            var branch = [start]
            var point = start
            for _ in 0..<3 {
                point = SCNVector3(
                    point.x + sideX * Float.random(in: 0.25...0.6) * scale,
                    point.y - Float.random(in: 0.5...1.1) * scale,
                    point.z + sideZ * Float.random(in: 0.1...0.4) * scale
                )
                branch.append(point)
            }
            addSegments(branch, to: bolt, tint: tint, thickness: thickness * 0.55 * scale)
        }

        bolt.runAction(.sequence([
            .fadeOpacity(to: 1.0, duration: 0.03),
            .wait(duration: 0.06),
            .fadeOpacity(to: 0.0, duration: 0.24),
            .removeFromParentNode()
        ]))
    }

    /// Joins consecutive points with cylinders: a white core and a tinted glow
    /// around it. The cylinder's own axis is Y, so each one is rotated about
    /// the axis perpendicular to both Y and the segment it has to follow.
    private static func addSegments(_ points: [SCNVector3], to parent: SCNNode, tint: UIColor, thickness: Float) {
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
            let length = (dx * dx + dy * dy + dz * dz).squareRoot()
            guard length > 1e-4 else { continue }
            let direction = SCNVector3(dx / length, dy / length, dz / length)

            let segment = SCNNode()
            segment.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
            // Y × direction, the axis that turns the cylinder onto the segment.
            let axisX = direction.z, axisZ = -direction.x
            let axisLength = (axisX * axisX + axisZ * axisZ).squareRoot()
            if axisLength > 1e-4 {
                let angle = acos(max(-1, min(1, direction.y)))
                segment.rotation = SCNVector4(axisX / axisLength, 0, axisZ / axisLength, angle)
            }
            parent.addChildNode(segment)

            for (radius, color) in [(thickness, UIColor.white), (thickness * 2.8, tint.withAlphaComponent(0.55))] {
                let cylinder = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length * 1.04))
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = color
                material.emission.contents = color
                material.blendMode = .add
                material.writesToDepthBuffer = false
                cylinder.firstMaterial = material
                segment.addChildNode(SCNNode(geometry: cylinder))
            }
        }
    }

    /// The sky lighting up: a large white light far above the strike, gone in
    /// a few frames. Cheap, and the difference between a bolt and a lightning
    /// strike.
    private static func skyFlash(over position: SCNVector3, in scene: SCNScene, scale: Float, duration: TimeInterval) {
        let above = SCNVector3(position.x, position.y + 7 * scale, position.z)
        flash(at: above, in: scene, color: UIColor(white: 1.0, alpha: 1.0), radius: 7 * scale, duration: duration)
    }

    /// The expanding shockwave for the ultimate.
    private static func addStormRing(to host: SCNNode, tint: UIColor, scale: Float) {
        // The painted ring, flat on the floor, racing out under the line:
        // the shockwave a line-wide skill reads by.
        if let image = sprite("ring") {
            let plane = SCNPlane(width: CGFloat(1.2 * scale), height: CGFloat(1.2 * scale))
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.emission.contents = image
            material.multiply.contents = tint
            material.blendMode = .add
            material.writesToDepthBuffer = false
            material.isDoubleSided = true
            plane.firstMaterial = material
            let wave = SCNNode(geometry: plane)
            wave.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            // On the floor under the chest the host sits at; a hand above it
            // so it does not fight the stone for depth.
            wave.position = SCNVector3(0, -Float(0.9 * scale) + 0.06, 0)
            host.addChildNode(wave)
            wave.runAction(.sequence([
                .group([.scale(to: CGFloat(9 * scale), duration: 0.5), .fadeOut(duration: 0.5)]),
                .removeFromParentNode(),
            ]))
        }
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
