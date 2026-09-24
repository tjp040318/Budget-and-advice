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

    /// How many victims one cast of an effect lands on, and so how it is
    /// drawn (run 224's 8-b: Fenrir's Gleipnir Strain drew `duat_rite` on
    /// each of the four heroes it hit — a pure-white script sheet 3.7 m
    /// wide, a storm ring, 160 sparks and a light on every one, 2.4 m apart
    /// — and the four sheets added up to a white slab over the whole team,
    /// its middle band 21.8% blown and a 64-px patch 100%).
    enum Reach {
        /// One victim: the effect as designed.
        case single
        /// One of several victims that each draw their own (an element's
        /// hit, a heal, a blessing): the painted sheets off white (half
        /// the caster's tint, at 0.7) at 0.85 of their size, and no light —
        /// the cast lights the row once.
        case member
        /// The whole row at once, drawn ONCE at its centre: the sheets off
        /// white (0.6 of the caster's tint, at `rowSheetStrength`), as wide
        /// as the row asks up to `areaSheetLimit` and faded into the floor
        /// (`standingFlipbook`), half the sparks, one light at 0.6 strength
        /// no wider than 4 m.
        case row(span: Float)
    }

    /// The widest a painted sheet is ever drawn over a row, in metres: one
    /// additive layer of the sunburst wider than this reads as a wash. It
    /// was 4.4 until run 234's aoe-c, where the Wrath of the Eye over the
    /// team covered two fifths of the frame and its middle band was 9.5%
    /// blown.
    static let areaSheetLimit: CGFloat = 3.4

    /// How much of a sheet's paint reaches the frame when it stands over a
    /// row: the colour is scaled, not the alpha, so an additive sheet is
    /// dimmed whatever the blend reads. At 0.7 a sunburst's white core over
    /// the Duat's lit floor went past 240 across a 64-px patch (76%, run
    /// 234); at half it adds about 100 of luminance at its brightest.
    static let rowSheetStrength: CGFloat = 0.5

    /// The height, in metres above the floor, over which a sheet standing
    /// over a row fades out (`standingFlipbook`).
    static let floorFadeHeight: Float = 0.9

    /// A cast on several victims: an element's hit, a heal or a blessing
    /// lands on each of them, quietly, with one light at the row's centre; a
    /// named skill effect is drawn once over the row and every victim gets
    /// the element's sparks of its own.
    static func spawnArea(
        _ identifier: String,
        over positions: [SCNVector3],
        in scene: SCNScene,
        tint: UIColor,
        scale: Float = 1.0
    ) {
        guard positions.count > 1 else {
            if let only = positions.first {
                spawn(identifier, at: only, in: scene, tint: tint, scale: scale)
            }
            return
        }
        let count = Float(positions.count)
        let centre = SCNVector3(
            positions.reduce(Float(0)) { $0 + $1.x } / count,
            positions.reduce(Float(0)) { $0 + $1.y } / count,
            positions.reduce(Float(0)) { $0 + $1.z } / count
        )
        var span: Float = 0
        for first in positions {
            for second in positions {
                let across = hypotf(first.x - second.x, first.z - second.z)
                span = max(span, across)
            }
        }
        let eachDrawsItsOwn = identifier.hasPrefix("impact_") || memberEffects.contains(identifier)
            || authoredSystem(identifier) != nil
        if eachDrawsItsOwn {
            for position in positions {
                spawn(identifier, at: position, in: scene, tint: tint, scale: scale, reach: .member)
            }
            let reach: Float = min(4, span * 0.5 + 1)
            flash(at: centre, in: scene, color: tint, radius: reach, duration: 0.3, strength: 0.6)
            return
        }
        spawn(identifier, at: centre, in: scene, tint: tint, scale: scale, reach: .row(span: span))
        for position in positions {
            let host = SCNNode()
            host.name = "vfx_\(identifier)_sparks"
            host.position = position
            scene.rootNode.addChildNode(host)
            host.addParticleSystem(sparks(tint: tint, count: 36, speed: 5, scale: scale))
            retire(host, after: 3.0)
        }
    }

    /// The effects every victim of a cast draws for itself: an element's
    /// hit and the support effects, whose place is on the unit they touch.
    private static let memberEffects: Set<String> = [
        "heal", "maat_shield", "buff", "debuff", "olympian_decree", "blood_thirst", "crit",
    ]

    /// Named effects referenced from `Skill.vfx`. Unknown names fall through to
    /// the generic impact, so a skill can name an effect before it exists.
    static func spawn(
        _ identifier: String,
        at position: SCNVector3,
        in scene: SCNScene,
        tint: UIColor,
        scale: Float = 1.0,
        reach: Reach = .single
    ) {
        let host = SCNNode()
        // Named, so the console's retirement line (`retire`) says which
        // effect a host belonged to.
        host.name = "vfx_\(identifier)"
        host.position = position
        scene.rootNode.addChildNode(host)

        // Every painted sheet, light, sky flash and spark count below goes
        // through these, so a cast on several victims is drawn by `reach`'s
        // rules and a single victim's effect is exactly as designed.
        let crowded: Bool
        let spread: CGFloat
        switch reach {
        case .single:
            crowded = false
            spread = 1
        case .member:
            crowded = true
            spread = 0.85
        case .row(let span):
            crowded = true
            spread = CGFloat(min(1.5, max(1, span / 4.8)))
        }
        func paintedTint(_ sheetTint: UIColor) -> UIColor {
            switch reach {
            case .single:
                return sheetTint
            case .member:
                return sheetTint.mixed(with: tint, amount: 0.5).withAlphaComponent(0.7)
            case .row:
                return sheetTint.mixed(with: tint, amount: 0.6).withAlphaComponent(rowSheetStrength)
            }
        }
        func paintedSide(_ size: CGFloat) -> CGFloat {
            guard crowded else { return size }
            return min(areaSheetLimit, size * spread)
        }
        func drawSheet(_ name: String, tint sheetTint: UIColor, size: CGFloat, life: CGFloat, lift: Float = 0) {
            let side = paintedSide(size)
            // A sheet whose lower edge would pass through the floor stands
            // as a plane that fades into it: every sheet over a row, and a
            // single victim's big burst (a camera-facing sheet reaches
            // about 0.45 of its side below its centre at the home pitch).
            let lowerEdge: Float = position.y + lift - Float(side) * 0.45
            let reachesFloor: Bool
            if case .row = reach {
                reachesFloor = true
            } else {
                reachesFloor = lowerEdge < 0
            }
            if reachesFloor {
                standingFlipbook(name, at: position, in: scene, tint: paintedTint(sheetTint),
                                 size: side, life: TimeInterval(life), lift: lift)
            } else {
                addFlipbook(to: host, name, tint: paintedTint(sheetTint), size: side, life: life, lift: lift)
            }
        }
        func drawGround(_ name: String, tint groundTint: UIColor, size: CGFloat, life: TimeInterval) {
            groundFlipbook(name, at: position, in: scene, tint: paintedTint(groundTint), size: paintedSide(size), life: life)
        }
        func lightUp(_ color: UIColor, radius: Float, duration: TimeInterval) {
            switch reach {
            case .single:
                flash(at: position, in: scene, color: color, radius: radius, duration: duration)
            case .member:
                break
            case .row:
                let wide: Float = min(4, radius * Float(spread))
                flash(at: position, in: scene, color: color, radius: wide, duration: duration, strength: 0.6)
            }
        }
        func skyLight(duration: TimeInterval) {
            if case .member = reach { return }
            skyFlash(over: position, in: scene, scale: scale, duration: duration)
        }
        func sparkCount(_ count: Int) -> Int {
            crowded ? max(12, count / 2) : count
        }

        // An effect authored in Xcode's particle editor (File → New → File →
        // SceneKit Particle System) and dropped into the bundle as
        // `<identifier>.scnp` replaces the code-built one below, colours and
        // all: any hit can be designed by hand, with no code.
        if let authored = authoredSystem(identifier) {
            host.addParticleSystem(authored)
            host.scale = SCNVector3(scale, scale, scale)
            lightUp(tint, radius: 1.4 * scale, duration: 0.2)
            retire(host, after: 3.0)
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
            if let burst = flipbook("fireburst", rows: 4, cols: 8, tint: paintedTint(tint.mixed(with: .white, amount: 0.5)),
                                    size: paintedSide(2.4 * CGFloat(scale)), life: 0.75) {
                host.addParticleSystem(burst)
            }
            if let flameImage = sprite("flame"), let ember = sprite("ember") {
                host.addParticleSystem(puff(flameImage, tint: tint.mixed(with: .white, amount: 0.25), count: 9, speed: 1.8,
                                            size: 0.6 * CGFloat(scale), life: 0.5, spread: 45, lift: 2.4, spin: 0.8))
                host.addParticleSystem(puff(ember, tint: tint, count: 40, speed: 5, size: 0.13 * CGFloat(scale),
                                            life: 0.65, spread: 180, lift: -6, spin: 0))
            } else {
                host.addParticleSystem(sparks(tint: tint, count: sparkCount(70), speed: 5, scale: scale))
                host.addParticleSystem(rising(tint: tint, count: 40, scale: scale * 0.8))
            }
            lightUp(tint, radius: 1.4 * scale, duration: 0.2)
        case "impact_tide":
            if let splash = sprite("splash"), let shard = sprite("shard") {
                host.addParticleSystem(puff(splash, tint: tint.mixed(with: .white, amount: 0.3), count: 3, speed: 0.3,
                                            size: 1.3 * CGFloat(scale), life: 0.45, spread: 30, lift: 0.5, spin: 0.3, grow: 1.8))
                host.addParticleSystem(puff(shard, tint: tint, count: 24, speed: 4.5, size: 0.22 * CGFloat(scale),
                                            life: 0.6, spread: 180, lift: -9, spin: 4))
            } else {
                host.addParticleSystem(sparks(tint: tint, count: sparkCount(50), speed: 4, scale: scale))
                host.addParticleSystem(falling(tint: tint, count: 60, scale: scale))
            }
            lightUp(tint, radius: 1.2 * scale, duration: 0.2)
        case "impact_gale":
            if let slash = sprite("slash"), let leaf = sprite("leaf") {
                host.addParticleSystem(puff(slash, tint: tint.mixed(with: .white, amount: 0.4), count: 6, speed: 3.5,
                                            size: 0.8 * CGFloat(scale), life: 0.35, spread: 180, lift: 0, spin: 10, grow: 1.4))
                host.addParticleSystem(puff(leaf, tint: tint, count: 16, speed: 4, size: 0.16 * CGFloat(scale),
                                            life: 0.8, spread: 180, lift: -2, spin: 6))
            } else {
                host.addParticleSystem(sparks(tint: tint, count: sparkCount(90), speed: 8, scale: scale * 0.8))
            }
            lightUp(tint, radius: 1.0 * scale, duration: 0.14)
        case "impact_radiance":
            // No painted ring (run 220): `vfx_ring.png` was painted on WHITE
            // and ships as an opaque square, so its puff — additive, grown
            // 4.5× — laid a white slab over the victim on every light hit.
            // The flare carries the hit until the ring is repainted on black.
            if let flare = sprite("flare") {
                host.addParticleSystem(puff(flare, tint: tint.mixed(with: .white, amount: 0.5), count: 1, speed: 0,
                                            size: 1.6 * CGFloat(scale), life: 0.4, spread: 0, lift: 0, spin: 0.5, grow: 1.9))
                host.addParticleSystem(puff(flare, tint: tint, count: 14, speed: 4, size: 0.18 * CGFloat(scale),
                                            life: 0.6, spread: 180, lift: 1, spin: 2))
            } else {
                host.addParticleSystem(rising(tint: tint, count: 70, scale: scale))
            }
            lightUp(tint, radius: 2.0 * scale, duration: 0.26)
        case "impact_umbra":
            // The smoke stands on its own: the wisp was painted on white too,
            // and `sprite` refuses it (an opaque square, additive, eight to a
            // hit), so rising motes take its place until it is repainted.
            // In the dark element's VIOLET, not the caster's aura (run 221):
            // a draugr's blue-grey aura taken 30% to black, alpha-blended and
            // grown twice over, laid a flat grey see-through disc a hundred
            // points across over Anubis. The smoke is violet with a tenth of
            // black, three puffs grown 1.4 times, and more of the motes, so
            // the hit reads as shadow in the element's colour.
            let violet = (UIColor(hex: Element.umbra.accentHex) ?? tint).mixed(with: tint, amount: 0.25)
            if let smoke = sprite("smoke") {
                host.addParticleSystem(puff(smoke, tint: violet.mixed(with: .black, amount: 0.1), count: 3, speed: 0.8,
                                            size: 0.9 * CGFloat(scale), life: 0.8, spread: 90, lift: 0.6, spin: 0.6,
                                            blend: .alpha, grow: 1.4))
                if let wisp = sprite("wisp") {
                    host.addParticleSystem(puff(wisp, tint: violet, count: 8, speed: 1.6, size: 0.5 * CGFloat(scale),
                                                life: 0.7, spread: 60, lift: 1.8, spin: 1.5))
                } else {
                    host.addParticleSystem(rising(tint: violet.mixed(with: .white, amount: 0.15), count: 70, scale: scale))
                }
            } else {
                host.addParticleSystem(falling(tint: violet, count: 50, scale: scale * 1.2))
                host.addParticleSystem(sparks(tint: violet, count: sparkCount(30), speed: 3, scale: scale))
            }
            lightUp(violet, radius: 1.2 * scale, duration: 0.22)
        // The stroke of a closing strike: a bright arc across the victim that
        // grows in and fades in a quarter of a second.
        case "slash":
            addSlash(to: host, tint: tint, scale: scale)
        // THE PAINTED FLIPBOOKS (2026-09-15, "REAL animated attacks ... that
        // includes effects"): eight sheets of sixteen frames each, painted by
        // Meshy's text-to-image in Meshy credits while Gemini is paused
        // (`meshy.py picture`, shipped by tools/vfx_sheets.py) — a claw
        // rake, a solar burst, a shadow-and-scales burst, a lightning
        // strike, a crimson X, a golden script, a dust shockwave, a healing
        // lotus — so each god's skill lands as a DRAWN animation, the genre's
        // way, with the code-built parts (the bolt, the column, the ring,
        // the sparks, the flash) playing under it. Without its sheet an
        // effect keeps the code-built parts alone.

        // Anubis. The jackal's strike is a burst of shadow with the scales of
        // Ma'at in it; the weighing is the same in gold under a column of
        // judgment; a rite is golden script over the whole team; the shield
        // of Ma'at blooms.
        case "scale_strike":
            drawSheet("shadow", tint: tint.mixed(with: .white, amount: 0.35), size: 1.9 * CGFloat(scale), life: 0.5)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(40), speed: 5, scale: scale))
            lightUp(tint, radius: 1.2 * scale, duration: 0.18)
        case "heart_weigh":
            drawSheet("shadow", tint: UIColor(hex: "#FFD680") ?? .white, size: 3.0 * CGFloat(scale), life: 0.7)
            addBoltColumn(to: host, tint: tint, scale: scale)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(120), speed: 8, scale: scale))
            lightUp(tint, radius: 2.6 * scale, duration: 0.3)
        case "duat_rite":
            drawSheet("script", tint: .white, size: 3.2 * CGFloat(scale), life: 0.9)
            addStormRing(to: host, tint: tint, scale: scale)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(160), speed: 10, scale: scale * 1.2))
            lightUp(tint, radius: 4.0 * scale, duration: 0.45)
        case "maat_shield":
            drawSheet("bless", tint: UIColor(hex: "#FFE6A0") ?? .white, size: 2.6 * CGFloat(scale), life: 0.9)
            host.addParticleSystem(rising(tint: tint, count: 60, scale: scale))
        case "heal":
            drawSheet("bless", tint: .white, size: 2.6 * CGFloat(scale), life: 0.9)
            host.addParticleSystem(rising(tint: UIColor(hex: "#7FE8A0")!, count: 40, scale: scale))
        case "buff":
            host.addParticleSystem(rising(tint: UIColor(hex: "#6BD8F2")!, count: 40, scale: scale))
        case "debuff":
            host.addParticleSystem(falling(tint: UIColor(hex: "#C86BE0")!, count: 40, scale: scale))
        case "crit":
            host.addParticleSystem(sparks(tint: UIColor(hex: "#FFD24F")!, count: sparkCount(90), speed: 7, scale: scale))
            lightUp(UIColor(hex: "#FFD24F")!, radius: 1.6 * scale, duration: 0.2)

        // Sekhmet. Three claws rake across the victim; the Eye is the sun
        // itself bursting on it under a column of light; the Wrath is the
        // sun over the whole line with the sky flashing.
        case "lioness_rake":
            drawSheet("claw", tint: .white, size: 2.3 * CGFloat(scale), life: 0.5)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(50), speed: 6, scale: scale))
            lightUp(tint, radius: 1.1 * scale, duration: 0.15)
        case "eye_of_ra":
            drawSheet("sunburst", tint: .white, size: 3.4 * CGFloat(scale), life: 0.7)
            addBoltColumn(to: host, tint: tint, scale: scale)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(120), speed: 9, scale: scale))
            lightUp(tint, radius: 2.6 * scale, duration: 0.3)
        case "wrath_of_the_eye":
            drawSheet("sunburst", tint: .white, size: 4.8 * CGFloat(scale), life: 0.85)
            addStormRing(to: host, tint: tint, scale: scale)
            skyLight(duration: 0.2)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(200), speed: 12, scale: scale * 1.3))
            lightUp(tint, radius: 4.5 * scale, duration: 0.5)
        case "blood_thirst":
            host.addParticleSystem(rising(tint: UIColor(hex: "#E0453C")!, count: 80, scale: scale))

        // Ares. Slaughter is a crimson X cut across the victim.
        case "blood_slash":
            drawSheet("blood", tint: .white, size: 2.8 * CGFloat(scale), life: 0.6)
            host.addParticleSystem(sparks(tint: UIColor(hex: "#FF4040")!, count: sparkCount(90), speed: 8, scale: scale))
            lightUp(UIColor(hex: "#FF3030")!, radius: 2.2 * scale, duration: 0.25)

        // The ground breaking under a heavy blow: the dust ring laid flat on
        // the floor at the victim's feet (`groundFlipbook`), with the stone
        // chips as sparks.
        case "shockwave":
            drawGround("shockwave", tint: .white, size: 3.6 * CGFloat(scale), life: 0.7)
            host.addParticleSystem(sparks(tint: UIColor(hex: "#D8C0A0")!, count: sparkCount(50), speed: 5, scale: scale))

        // Zeus. Every effect is a real forked bolt out of the sky with the
        // painted strike drawn over it — the strike's impact at the feet, so
        // the sheet is lifted to stand on the ground — and the sky itself
        // flashes: a second light far overhead lights the whole arena for a
        // frame or two, which is what makes lightning read as lightning.
        case "thunderbolt":
            // A BASIC attack, cast every few seconds: a bolt and a burst on
            // the victim, no sky flash, and the sheet tinted off pure white
            // so an additive layer cannot climb past the bloom threshold by
            // itself.
            drawSheet("lightning", tint: tint.mixed(with: .white, amount: 0.6),
                        size: 2.6 * CGFloat(scale), life: 0.45, lift: 1.8 * scale - 1.1 * scale)
            addLightningBolt(to: host, tint: tint, scale: scale, thickness: 0.05, height: 7, forks: 1)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(55), speed: 7, scale: scale))
            lightUp(tint, radius: 1.5 * scale, duration: 0.2)
        case "thunderclap":
            drawSheet("lightning", tint: tint.mixed(with: .white, amount: 0.75),
                        size: 3.6 * CGFloat(scale), life: 0.6, lift: 2.0 * scale - 1.1 * scale)
            addLightningBolt(to: host, tint: tint, scale: scale, thickness: 0.035, height: 8, forks: 0)
            drawGround("shockwave", tint: tint.mixed(with: .white, amount: 0.5), size: 3.4 * CGFloat(scale), life: 0.7)
            skyLight(duration: 0.18)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(120), speed: 8, scale: scale))
            lightUp(tint, radius: 2.8 * scale, duration: 0.25)
        case "keraunos":
            drawSheet("lightning", tint: .white, size: 5.2 * CGFloat(scale), life: 0.65, lift: 2.6 * scale - 1.1 * scale)
            addLightningBolt(to: host, tint: tint, scale: scale, thickness: 0.09, height: 11, forks: 3)
            addBoltColumn(to: host, tint: tint, scale: scale)
            drawGround("shockwave", tint: tint.mixed(with: .white, amount: 0.5), size: 4.4 * CGFloat(scale), life: 0.8)
            skyLight(duration: 0.22)
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(260), speed: 12, scale: scale * 1.3))
            lightUp(tint, radius: 4.5 * scale, duration: 0.45)
        case "olympian_decree":
            drawSheet("script", tint: .white, size: 3.2 * CGFloat(scale), life: 0.9)
            host.addParticleSystem(rising(tint: tint, count: 120, scale: scale))
            lightUp(tint, radius: 2.0 * scale, duration: 0.3)
        default:
            host.addParticleSystem(sparks(tint: tint, count: sparkCount(40), speed: 4, scale: scale))
        }

        // Particle hosts clean themselves up; nothing accumulates in the
        // scene. Through `retire`, never a `.removeFromParentNode()` action:
        // see there for why.
        retire(host, after: 3.0)
    }

    /// A painted sheet on a screen-facing particle at the host, `lift` metres
    /// above it — the lightning sheets strike downward, so their impact
    /// point (the bottom of the frame) is raised to the victim's feet.
    /// Nothing is added when the sheet has not shipped.
    private static func addFlipbook(to host: SCNNode, _ name: String, tint: UIColor, size: CGFloat, life: CGFloat,
                                    lift: Float = 0) {
        guard let burst = flipbook(name, rows: 4, cols: 4, tint: tint, size: size, life: life) else { return }
        let carrier = SCNNode()
        carrier.position = SCNVector3(0, lift, 0)
        carrier.addParticleSystem(burst)
        host.addChildNode(carrier)
    }

    /// A painted sheet standing over a ROW (`Reach.row`), or a single
    /// victim's burst big enough to reach the floor: a camera-facing plane
    /// rather than a particle, so its colour can fade into the floor. A
    /// screen-facing sheet 3–4 m wide centred at chest height reaches below
    /// the floor, and the floor cut it with a hard straight line through
    /// the burst (run 234's aoe-b, c and d). Engines hide that seam with a
    /// depth fade — Unity's soft particles, Unreal's DepthFade — and
    /// SceneKit's particle system has none. The floor here is the plane
    /// y = 0 and the battle camera never turns, so the height of every row
    /// of the sheet is known when it is spawned: the fade is BAKED into the
    /// mask it is multiplied by (`floorFadeMask`), with the caster's tint
    /// and the sheet's strength. Run 235 drew it with a fragment modifier
    /// reading `_surface.position` instead, and the sheet was drawn nowhere
    /// in any of the four frames while its sparks and its light were: no
    /// shader here now, and one `[VFX]` line per sheet says it stood. The
    /// frames are stepped from the main thread on a timer, as
    /// `groundFlipbook` steps its own, and the sheet holds for half its
    /// life and fades over the rest by its opacity, as the slash does.
    private static func standingFlipbook(_ name: String, at position: SCNVector3, in scene: SCNScene, tint: UIColor,
                                         size: CGFloat, life: TimeInterval, lift: Float) {
        let cut = frames(of: name, rows: 4, cols: 4)
        guard !cut.isEmpty else { return }
        let centreHeight: Float = position.y + lift
        let upright: Float = cameraUpright(in: scene)
        let side = Float(size)
        guard let mask = floorFadeMask(tint: tint, side: side, centreHeight: centreHeight, upright: upright) else {
            return
        }
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = cut[0]
        material.multiply.contents = mask
        material.blendMode = .add
        material.colorBufferWriteMask = [.red, .green, .blue]
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        plane.firstMaterial = material
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(position.x, centreHeight, position.z)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
        if standingSheetsSeen.insert(name).inserted {
            let across = String(format: "%.2f", Double(side))
            let up = String(format: "%.2f", Double(centreHeight))
            let cosine = String(format: "%.2f", Double(upright))
            print("[VFX] \(name) stands: \(across) m, its centre \(up) m up, \(cosine) of it upright")
        }
        let count = cut.count
        let start = CACurrentMediaTime()
        var shown = 0
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak node] timer in
            guard let node, node.parent != nil else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - start
            guard elapsed < life else {
                timer.invalidate()
                node.removeFromParentNode()
                return
            }
            let index = min(count - 1, max(0, Int(elapsed / life * Double(count))))
            if index != shown {
                shown = index
                node.geometry?.firstMaterial?.diffuse.contents = cut[index]
            }
            let remaining: Double = 2.0 - 2.0 * elapsed / life
            node.opacity = CGFloat(min(1.0, max(0.0, remaining)))
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The standing sheets that have printed their line.
    private static var standingSheetsSeen: Set<String> = []

    /// How much of a camera-facing sheet's height stands upright: the
    /// cosine of the camera's pitch, read off the scene's camera (a sheet
    /// facing a camera 36° down leans back 36°, so its rows climb 0.81 of
    /// their spacing). 0.81, the home pitch's, when the scene has none.
    private static func cameraUpright(in scene: SCNScene) -> Float {
        let cameras = scene.rootNode.childNodes { node, _ in node.camera != nil }
        guard let camera = cameras.first else { return 0.81 }
        let front = camera.presentation.worldFront
        let down: Float = min(1, abs(front.y))
        return (1 - down * down).squareRoot()
    }

    /// The mask a standing sheet is multiplied by: one column of 64 rows,
    /// the image's top row the sheet's top. Each row is the tint scaled by
    /// the tint's alpha (the strength goes into the colour: an additive
    /// sheet's alpha may or may not weigh it, the colour always does) and by
    /// how far that row stands over the floor — nothing at the floor, all of
    /// it `floorFadeHeight` up, smoothstepped between.
    private static func floorFadeMask(tint: UIColor, side: Float, centreHeight: Float, upright: Float) -> CGImage? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let rows = 64
        var pixels = [UInt8](repeating: 255, count: rows * 4)
        for row in 0..<rows {
            let down: Float = (Float(row) + 0.5) / Float(rows)
            let drop: Float = (down - 0.5) * side * upright
            let height: Float = centreHeight - drop
            let ramp: Float = min(1, max(0, height / floorFadeHeight))
            let smooth: Float = ramp * ramp * (3 - 2 * ramp)
            let strength: CGFloat = alpha * CGFloat(smooth) * 255
            let at = row * 4
            pixels[at] = UInt8(clamping: Int((red * strength).rounded()))
            pixels[at + 1] = UInt8(clamping: Int((green * strength).rounded()))
            pixels[at + 2] = UInt8(clamping: Int((blue * strength).rounded()))
            pixels[at + 3] = 255
        }
        // A bitmap context's first row in memory is its image's top row.
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: 1, height: rows, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: space, bitmapInfo: info) else { return nil }
            return context.makeImage()
        }
    }

    private static var frameCache: [String: [CGImage]] = [:]

    /// The sixteen frames of a sheet as separate images, cut once and kept.
    private static func frames(of name: String, rows: Int, cols: Int) -> [CGImage] {
        if let cached = frameCache[name] { return cached }
        guard let image = sprite("\(name)_sheet"), let cg = image.cgImage else { return [] }
        let width = cg.width / cols, height = cg.height / rows
        var cut: [CGImage] = []
        for row in 0..<rows {
            for col in 0..<cols {
                if let frame = cg.cropping(to: CGRect(x: col * width, y: row * height, width: width, height: height)) {
                    cut.append(premultiplied(frame) ?? frame)
                }
            }
        }
        frameCache[name] = cut
        return cut
    }

    /// A cell with its colour multiplied by its alpha. The sheets ship
    /// UNPREMULTIPLIED: under a clear pixel lies the painting's colour, a
    /// mean of 100–200 of 255 (the lightning's cell border 197), and a plane
    /// drawn `.add` adds the colour whatever the alpha — run 236's lightning
    /// stood over the enemy row as a white rectangle the size of its cell,
    /// 15% of the middle band and a whole 64-px patch blown
    /// (18-dungeon_battle-a). A particle weighs its texture by its alpha; a
    /// plane (`standingFlipbook`, `groundFlipbook`) needs it done here.
    /// Drawn once per sheet, over clear, into a premultiplied context.
    private static func premultiplied(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A painted sheet laid FLAT on the floor under `position` and stepped
    /// through frame by frame — the shockwave ring of a heavy blow, which a
    /// screen-facing particle could only stand upright. The frames are
    /// swapped as the material's contents, so nothing depends on how a
    /// texture transform reads a sheet — and swapped from the MAIN thread on
    /// a timer, never inside an `SCNAction`: an action's block runs on
    /// SceneKit's render threads, and the first build swapped the texture
    /// there. The arena fight of 2026-09-15 died two seconds in on
    /// "Hidden nodes should have been removed from the pipeline already",
    /// six times across three render threads, with nothing else new off the
    /// main thread. Nothing here touches the scene off it now.
    private static func groundFlipbook(_ name: String, at position: SCNVector3, in scene: SCNScene, tint: UIColor,
                                       size: CGFloat, life: TimeInterval) {
        let cut = frames(of: name, rows: 4, cols: 4)
        guard !cut.isEmpty else { return }
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = cut[0]
        material.multiply.contents = tint
        material.blendMode = .add
        material.colorBufferWriteMask = [.red, .green, .blue]
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        plane.firstMaterial = material
        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.position = SCNVector3(position.x, 0.04, position.z)
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
        let count = cut.count
        let start = CACurrentMediaTime()
        var shown = 0
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak node] timer in
            guard let node, node.parent != nil else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - start
            guard elapsed < life else {
                timer.invalidate()
                node.removeFromParentNode()
                return
            }
            let index = min(count - 1, max(0, Int(elapsed / life * Double(count))))
            if index != shown {
                shown = index
                node.geometry?.firstMaterial?.diffuse.contents = cut[index]
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The gathering before an ultimate: motes of the element drawn up round
    /// the caster and a swelling flare at its chest for the wind-up, so the
    /// blow is announced the way the genre announces one. Removes itself.
    ///
    /// The host stands in the STAGE at the caster's chest, never under the
    /// figure (run 239): it was the one particle host in a fight that hung
    /// from a unit — beside the skinned model and its skeleton, under a node
    /// a wave change fades out and removes with an action — and everything
    /// else in this file already lives at the root. An ultimate is cast from
    /// the caster's mark (only a basic or a heavy closes), the emitter is a
    /// sphere and every direction here is world up, so the motes gather
    /// exactly where and how they did.
    static func charge(on caster: SCNNode, tint: UIColor, duration: TimeInterval, scale: Float) {
        guard let stage = caster.parent else { return }
        let host = SCNNode()
        host.name = "vfx_charge"
        host.position = caster.convertPosition(SCNVector3(0, 1.0 * scale, 0), to: stage)
        stage.addChildNode(host)
        // The motes are born through the wind-up and are gone by the blow.
        let moteLife = CGFloat(max(0.3, duration * 0.45))
        let emitting = CGFloat(max(0.2, duration * 0.85))
        if let flare = sprite("flare") {
            let motes = puff(flare, tint: tint, count: 28, speed: 0.9, size: 0.16 * CGFloat(scale), life: moteLife,
                             spread: 180, lift: 1.6, spin: 1)
            motes.emissionDuration = emitting
            motes.birthRate = 28 / emitting
            motes.emitterShape = SCNSphere(radius: CGFloat(0.9 * scale))
            host.addParticleSystem(motes)
            let core = puff(flare, tint: tint.mixed(with: .white, amount: 0.4), count: 1, speed: 0, size: 0.5 * CGFloat(scale),
                            life: CGFloat(max(0.3, duration)), spread: 0, lift: 0, spin: 0.3, grow: 3.2)
            host.addParticleSystem(core)
        }
        // The host outlives its last particle by a second (`puff` varies a
        // life by 30%: the last mote dies at 0.85 + 1.3 × 0.45 of the wind-up,
        // the core at 1.3 of it). A node removed while a one-shot system of
        // its is still alive was the crash of 2026-09-15, twice over: with
        // the removal in an action the pipeline asserted on hidden elements
        // (the arena); on the main thread SceneKit's particle manager
        // dereferenced the freed node when the system finished
        // (SCNNodeRemoveDeadParticleInstance, the dungeon's crash report).
        // The first build removed this host at the wind-up + 1.5 s with motes
        // living to 2.1 wind-ups. Every host in this file waits for its
        // systems to finish before it goes, and goes through `retire`.
        retire(host, after: duration * 1.5 + 1.0)
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
    ///
    /// A sprite painted on a LIGHT ground is refused (nil, and one console
    /// line): drawn additive, its ground is an opaque square of the tint,
    /// and two shipped that way — `vfx_ring` and `vfx_wisp`, white to the
    /// corners — put white slabs over the light and dark hits, the dark
    /// projectile and the deeps' weather (run 220). Every caller already
    /// has a code-built fallback for a missing sprite, so a refused one
    /// reads as a plainer effect, never a slab. A sprite repainted on black
    /// and shipped through `tools/vfx_ship.py` passes and returns by itself.
    private static var spriteCache: [String: UIImage?] = [:]

    static func sprite(_ name: String) -> UIImage? {
        if let cached = spriteCache[name] { return cached }
        var image = UIImage(named: "vfx_\(name)")
        if let found = image, paintedOnLightGround(found) {
            let line = "[VFX] vfx_\(name) refused: painted on a light ground (an opaque square when added)"
            print(line)
            DiagnosticsLog.shared.record(line)
            image = nil
        }
        spriteCache[name] = image
        return image
    }

    /// True when the image's outer border is bright and opaque — a sprite
    /// shipped with the white it was painted on. A sprite keyed off black
    /// has a border of nothing (premultiplied 0 in every shipped one); the
    /// two painted on white measure about 254 of 255. Read off a 32 × 32
    /// reduction, the way `PaintingPalette` reads a painting.
    private static func paintedOnLightGround(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let side = 32
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        var light = 0
        var samples = 0
        for row in 0..<side {
            for column in 0..<side where row == 0 || column == 0 || row == side - 1 || column == side - 1 {
                let at = (row * side + column) * 4
                light += Int(data[at]) + Int(data[at + 1]) + Int(data[at + 2])
                samples += 3
            }
        }
        return samples > 0 && light / samples > 96
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
        host.name = "vfx_projectile_\(name)"
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
        // Gone on arrival — the sprite and its trail together, as ever — but
        // the trail is a LOOPING system with motes alive in it, and removing
        // its node inside an action was the removal that tripped SceneKit's
        // hidden-element assertion on 2026-09-15. So the arrival only hops to
        // the main thread, where `dismiss` takes the trail off, hides the
        // host and lets it leave the scene once the particle manager has let
        // go of it.
        host.runAction(.sequence([
            fly,
            SCNAction.run { node in
                DispatchQueue.main.async { VFXLibrary.dismiss(node, reportsLive: false) }
            },
        ]))
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

    /// The air over a stage: what falls or rises through it all fight long
    /// (`StageBuilder.weather(for:)` picks one per place).
    enum Weather {
        case embers, leaves, petals, snow, wisps, motes
    }

    /// One looping system filling `volume` (a flat box: near the floor for
    /// what rises, six metres up for what falls), on the painted sprites —
    /// the ember and the wisp additive, the leaf and the snow alpha-blended
    /// so they read as things and not as light. Every count is low: the
    /// weather is felt at the edge of the eye, never watched.
    static func weather(_ kind: Weather, tint: UIColor, volume: SCNVector3) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.loops = true
        system.emissionDuration = 1
        system.idleDuration = 0
        system.birthLocation = .volume
        system.emitterShape = SCNBox(width: CGFloat(volume.x), height: CGFloat(volume.y), length: CGFloat(volume.z), chamferRadius: 0)
        system.isLightingEnabled = false
        system.sortingMode = .distance
        system.orientationMode = .billboardScreenAligned
        system.isAffectedByGravity = false
        system.particleColor = tint
        let spark = UIImage(named: "spark")
        switch kind {
        case .embers:
            system.particleImage = sprite("ember") ?? spark
            system.blendMode = .additive
            system.birthRate = 9
            system.particleSize = 0.09
            system.particleSizeVariation = 0.05
            system.emittingDirection = SCNVector3(0, 1, 0)
            system.spreadingAngle = 40
            system.particleVelocity = 0.5
            system.particleVelocityVariation = 0.3
            system.acceleration = SCNVector3(0.15, 0.25, 0)
            system.particleLifeSpan = 5
            system.particleLifeSpanVariation = 2
            system.particleAngularVelocity = 60
            system.particleAngularVelocityVariation = 40
        case .leaves, .petals:
            system.particleImage = kind == .leaves ? (sprite("leaf") ?? spark) : (sprite("flare") ?? spark)
            system.blendMode = .alpha
            system.birthRate = kind == .petals ? 7 : 5
            system.particleSize = kind == .petals ? 0.09 : 0.16
            system.particleSizeVariation = 0.05
            system.emittingDirection = SCNVector3(0, -1, 0)
            system.spreadingAngle = 30
            system.particleVelocity = 0.5
            system.particleVelocityVariation = 0.25
            system.acceleration = SCNVector3(0.35, -0.2, 0)
            system.particleLifeSpan = 7
            system.particleLifeSpanVariation = 2
            system.particleAngularVelocity = 90
            system.particleAngularVelocityVariation = 60
            system.particleAngleVariation = 180
            system.particleColorVariation = SCNVector4(0.05, 0.08, 0.03, 0)
        case .snow:
            system.particleImage = sprite("flare") ?? spark
            system.blendMode = .alpha
            system.birthRate = 26
            system.particleSize = 0.06
            system.particleSizeVariation = 0.03
            system.emittingDirection = SCNVector3(0, -1, 0)
            system.spreadingAngle = 25
            system.particleVelocity = 0.7
            system.particleVelocityVariation = 0.3
            system.acceleration = SCNVector3(0.25, -0.1, 0)
            system.particleLifeSpan = 8
            system.particleLifeSpanVariation = 2
        case .wisps:
            system.particleImage = sprite("wisp") ?? spark
            system.blendMode = .additive
            system.birthRate = 4
            system.particleSize = 0.35
            system.particleSizeVariation = 0.15
            system.emittingDirection = SCNVector3(0, 1, 0)
            system.spreadingAngle = 60
            system.particleVelocity = 0.2
            system.particleVelocityVariation = 0.1
            system.acceleration = SCNVector3(0.05, 0.08, 0)
            system.particleLifeSpan = 7
            system.particleLifeSpanVariation = 3
            system.particleColor = tint.withAlphaComponent(0.5)
        case .motes:
            system.particleImage = sprite("flare") ?? spark
            system.blendMode = .additive
            system.birthRate = 10
            system.particleSize = 0.05
            system.particleSizeVariation = 0.03
            system.emittingDirection = SCNVector3(0, 1, 0)
            system.spreadingAngle = 180
            system.particleVelocity = 0.15
            system.particleVelocityVariation = 0.1
            system.particleLifeSpan = 7
            system.particleLifeSpanVariation = 3
            system.particleColor = tint.withAlphaComponent(0.7)
        }
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
    /// The sky itself flashing, which is what makes lightning read as
    /// lightning: WIDE and WEAK, a fifth of an impact's strength, so the
    /// world changes for a frame or two without the floor going white. Spent
    /// on a heavy blow or an ultimate only — a basic attack does not flash
    /// the sky (2026-09-15).
    private static func skyFlash(over position: SCNVector3, in scene: SCNScene, scale: Float, duration: TimeInterval) {
        let above = SCNVector3(position.x, position.y + 7 * scale, position.z)
        flash(at: above, in: scene, color: UIColor(white: 1.0, alpha: 1.0),
              radius: 7 * scale, duration: duration, strength: 0.25)
    }

    /// The expanding shockwave for the ultimate: a torus of the element's
    /// light racing out from the victim.
    ///
    /// The painted ring that lay flat on the floor under it is GONE (run
    /// 220): `vfx_ring.png` was painted on white and ships as an opaque white
    /// square, and drawn additive and scaled 9× it was a slab of the tint
    /// over two thirds of the screen on every ultimate that calls this
    /// (18-dungeon_battle-a: the middle band 4.2% blown, a 64-px patch 75%).
    /// Put it back only once the ring is repainted on black and shipped
    /// through `tools/vfx_ship.py` (alpha from brightness).
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

    /// A short-lived point light, which is what actually sells an impact —
    /// and which must stay LOCAL.
    ///
    /// It was a flat 4,000 reaching four times its radius (2026-09-15, and
    /// every impact in the game since the first build). The battle's key
    /// light is 1,150, so every basic attack dropped a lamp three and a half
    /// times the sun into the set, nine metres wide for a thunderbolt and
    /// twenty-eight through `skyFlash`: it did not light the victim, it
    /// relit the arena, and the owner sent back the frame — a white blob
    /// over the enemy row with the floor bleached round it, 10.7% of that
    /// band with no detail in it. The camera's shoulder stops a bright
    /// surface clipping and can do nothing for a surface genuinely lit to
    /// four times white.
    ///
    /// So: the reach is one and a half radii, the falloff starts a third of
    /// the way out, and the intensity scales with the radius into the key
    /// light's neighbourhood rather than several times it. THE RULE: an
    /// effect may not relight the set. Brightness belongs to the additive
    /// sprite, which covers only its own pixels; a light in an effect
    /// reaches about as far as the thing it is lighting.
    private static func flash(
        at position: SCNVector3,
        in scene: SCNScene,
        color: UIColor,
        radius: Float,
        duration: TimeInterval,
        strength: CGFloat = 1
    ) {
        let peak = min(2_400, 900 + 420 * CGFloat(max(0.2, radius))) * strength
        let light = SCNLight()
        light.type = .omni
        light.color = color
        light.intensity = peak
        light.attenuationStartDistance = CGFloat(radius * 0.35)
        light.attenuationEndDistance = CGFloat(radius * 1.5)

        let node = SCNNode()
        node.light = light
        node.position = position
        scene.rootNode.addChildNode(node)

        node.runAction(.sequence([
            .customAction(duration: duration) { node, elapsed in
                let t = Float(elapsed) / Float(duration)
                node.light?.intensity = peak * CGFloat(1 - t)
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

        host.name = "vfx_summon_beam"
        host.addParticleSystem(rising(tint: tint, count: 200, scale: 2.0))
        retire(host, after: 4)
    }

    // MARK: - Retiring a node that carries particles

    /// Seconds of SCENE time a retired node stands hidden, its particle
    /// systems taken off, before it leaves the scene: frames enough for
    /// SceneKit's particle manager to let go of every instance it held on
    /// the node before the node can be freed.
    private static let retireSettle: TimeInterval = 0.5

    /// The one way a node that carries — or carried — a particle system
    /// leaves the scene: `delay` seconds of SCENE time from now (a hit-stop
    /// pauses the wait as it pauses the particles), then on the MAIN thread
    /// its systems are taken off and it is hidden, and `retireSettle`
    /// seconds of scene time later, on the main thread again, it goes.
    ///
    /// Run 239's arena died 3.1 s into Set's Red Land Blaze on SceneKit's
    /// render queue, drawing a particle system through a freed pointer
    /// (`C3DParticleSystemInstanceDraw` → `_executeDrawCommand` →
    /// `C3DSkinnerGetEffectiveCalculationMode`, EXC_BAD_ACCESS), a tenth of
    /// a second after the pipeline asserted on an element it should already
    /// have dropped ("Hidden nodes should have been removed from the
    /// pipeline already", the one such line in the whole tour's log) — the
    /// signature of 2026-09-15's two crashes. No host here was due to leave
    /// at that moment (the ultimate's swing trail was, and moving its
    /// geometry swaps off the render thread is the change most likely to
    /// answer the crash: `UnitNode.swingTrail`), but every one of them
    /// left by a `.removeFromParentNode()` ACTION, on the render thread in
    /// the middle of its update, with whatever the particle manager still
    /// kept for it, and a projectile's host went that way with its LOOPING
    /// trail alive. Now nothing that carries particles is removed there: the
    /// systems come off first, through a main-thread transaction the
    /// pipeline applies under its own lock, and the node itself only once
    /// the manager has had half a second of frames to drop them.
    /// `reportsLive` prints a line naming the node when it still carried a
    /// system at its time — a burst outliving its host's wait, the mistake
    /// of 2026-09-15 — and is off for the hosts whose looping systems are
    /// expected to be alive (a projectile's trail, a fallen unit's aura).
    static func retire(_ node: SCNNode, after delay: TimeInterval, reportsLive: Bool = true) {
        node.runAction(.sequence([
            .wait(duration: max(0, delay)),
            // SceneKit runs this block on its render thread: it only hops.
            SCNAction.run { target in
                DispatchQueue.main.async { VFXLibrary.dismiss(target, reportsLive: reportsLive) }
            },
        ]), forKey: retireKey)
    }

    private static let retireKey = "vfx_retire"

    /// On the main thread: every particle system in the node's subtree off,
    /// the node hidden, and its removal (on the main thread as well) queued
    /// `retireSettle` seconds of scene time on. A node already out of the
    /// scene (a battle torn down) is let go as it is.
    static func dismiss(_ node: SCNNode, reportsLive: Bool) {
        guard node.parent != nil else { return }
        var live = 0
        node.enumerateHierarchy { child, _ in
            guard let systems = child.particleSystems, !systems.isEmpty else { return }
            live += systems.count
            child.removeAllParticleSystems()
        }
        if live > 0, reportsLive {
            let line = "[VFX] \(node.name ?? "an unnamed host") still carried \(live) particle system(s) when it was retired"
            print(line)
            DiagnosticsLog.shared.record(line)
        }
        trace("\(node.name ?? "node") retired, \(live) system(s) taken off")
        node.isHidden = true
        node.runAction(.sequence([
            .wait(duration: retireSettle),
            SCNAction.run { target in
                DispatchQueue.main.async { target.removeFromParentNode() }
            },
        ]), forKey: retireKey)
    }

    /// Under the CI tour only: one stamped line per effect node leaving the
    /// stage, so a console that ends in a render-thread crash says which
    /// node went last and when, to set beside the system log's stamp.
    static func trace(_ message: String) {
        guard tracing else { return }
        print("[VFX] \(traceClock.string(from: Date())) \(message)")
    }

    private static let tracing = ProcessInfo.processInfo.arguments.contains("-tour")

    private static let traceClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
