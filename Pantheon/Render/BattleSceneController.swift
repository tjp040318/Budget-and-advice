import Foundation
import SceneKit
import SpriteKit
import UIKit

protocol BattleSceneDelegate: AnyObject {
    /// Called as each event begins presenting, so the HUD stays in step with
    /// what is on screen rather than with what the engine already decided.
    func battleScene(_ controller: BattleSceneController, willPresent event: BattleEvent)
    /// Called when the queue drains.
    func battleSceneDidFinishPlayback(_ controller: BattleSceneController)
}

/// One survivor's experience across a won fight, for the gold bar its plate
/// fills on the field while the team poses (Docs/FEEL.md W1.7,
/// `BattleSceneController.celebrate(experience:)`). The battle's view builds
/// these from the settle; the scene only draws them.
struct ExperienceGain: Equatable, Sendable {
    let from: Double          // the unit's EXP bar before the fight, 0...1
    let to: Double            // after it, 0...1 of the level it ended on
    let levelsGained: Int
}

/// Owns the 3D battle: the stage, the lighting, the units, and the playback of
/// the engine's event stream.
///
/// The engine has already decided everything by the time this runs. Playback is
/// pure presentation, which is why a battle can be fast-forwarded, skipped or
/// replayed without the outcome changing.
final class BattleSceneController: NSObject {

    let scene = SCNScene()
    weak var delegate: BattleSceneDelegate?

    /// One line per fight gone (2026-09-24): a chapter is fight after fight,
    /// each in its own cover, and the owner's phone crashed "sometimes when
    /// I play chapters". CI's battle stress climbed 340 → 391 → 417 MB over
    /// three stages, which the model cache filling would also do; this line
    /// says whether each fight's stage really leaves — `[Mem] battle stage
    /// released`, with the cache's files and live clones beside the
    /// footprint.
    deinit {
        // The slow motion's tick holds its target, not this; it is stopped
        // here so it does not tick once more into nothing — on the main
        // queue, where it runs.
        let ticker = slowTicker
        DispatchQueue.main.async { ticker?.stop() }
        #if DEBUG
        MemoryProbe.log("battle stage released")
        #endif
    }

    /// The speed the player picked: ×1, ×2 or ×3 (Docs/FEEL.md W1.1; the
    /// stress tour runs ×4). `BattleViewModel.speed` sets it, and it is the
    /// only way the player's speed reaches the feel (`Juice`).
    ///
    /// It used to divide the event queue's holds and nothing else: every
    /// skeletal clip still played at its authored speed, so at the x2 the
    /// auto-repeat actually runs at, each attack was about half finished when
    /// the next event replaced it and the figures twitched between fragments
    /// of swings. SceneKit has no per-node speed multiplier to lean on (that
    /// is SpriteKit), so the units are told and scale their own clips and
    /// actions by hand.
    var speedMultiplier: Double = 1.0 {
        didSet { applyPace() }
    }

    /// The final blow's slow motion (W1.7): 1 at rest, `slowestShare` at its
    /// deepest, tweened by a main-thread tick (`stepSlowMotion`). It multiplies
    /// the player's speed rather than replacing it, so the pace comes back to
    /// exactly the speed the player picked, whatever he picked meanwhile.
    private var timeScale: Double = 1.0 {
        didSet { applyPace() }
    }

    /// What every clip and every timer in the fight runs at: the player's
    /// speed through the slow motion.
    private var pace: Double { speedMultiplier * timeScale }

    private func applyPace() {
        let now = pace
        for node in unitNodes.values { node.playbackSpeed = now }
    }

    /// Authored seconds at the current pace. Every duration in this file is
    /// written for x1 and passes through here on its way to a timer, so
    /// fast-forward shortens the whole fight by one factor rather than by
    /// several that drift apart.
    private func beat(_ seconds: TimeInterval) -> TimeInterval {
        seconds / max(0.25, pace)
    }

    /// How long a melee unit takes to close on its victim.
    private static let dashDuration: TimeInterval = 0.30
    /// The leap `dashDuration` was tuned for, in metres of travel, and the
    /// most a longer one may stretch it (2026-09-24, review). With the rows
    /// about ten metres apart (`position(for:)`) a leap covers about nine,
    /// half as far again as on the old six-metre field, and at 0.30 s it
    /// flew at some 43 m/s, which reads as a teleport; stretched by its
    /// length over this, to at most 1.6 times, it keeps near the old pace.
    private static let dashReach: Float = 6
    private static let dashStretchCap: Double = 1.6

    /// Where in a clip the blow actually lands, as a fraction of the clip's
    /// contract duration.
    ///
    /// Nothing in the pipeline has ever known this: `AnimationClip` carries a
    /// duration and no contact frame, so the impact was spawned on a detached
    /// timer at a flat 45% of the clip while the damage event — the flash, the
    /// number, the sound, the haptic and the freeze — waited for the WHOLE
    /// clip to finish. Every basic attack therefore played as a slash arc, six
    /// tenths of a second of nothing, and then a victim flinching at something
    /// that had already happened; on an ultimate the gap was over a second.
    /// Two half-hits are why the fight read as numbers changing rather than as
    /// something being struck. This table is the one place the moment of
    /// contact is written down, and `UnitNode.play` retimes every one-shot to
    /// its contract so the fraction means the same thing whatever length Meshy
    /// happened to author the clip at.
    /// The size an effect is drawn at on a unit: its height over a hero's
    /// 1.9 m, no taller than 2.6 m. Unclamped, a hit on the 8 m Colossus drew
    /// at 4.2 times — a basic's fireburst ten metres across, Keraunos's
    /// lightning sheet twenty-two — and filled the upper frame with a wash
    /// of magnified texels (run 223, 18-c). The same on a boss's own wind-up.
    static func effectScale(for node: UnitNode) -> Float {
        min(node.spec.height, 2.6) / 1.9
    }

    /// Where in a clip the blow lands, as a fraction of its length. The stock
    /// clips' values first; a bespoke clip's blow lands where its sentence
    /// put it, read off the clip's frames when it shipped (2026-09-15: the
    /// five gods' fourteen clips, `preview.py --frame`), so the freeze, the
    /// flash and the damage number meet the claw as it closes. `castRelease`
    /// plays the heavy clip, so it reads the heavy's row.
    private static func contactFraction(of clip: AnimationClip, for asset: String = "") -> Double {
        let bespoke: [String: [AnimationClip: Double]] = [
            "anubis":  [.attackBasic: 0.38, .attackHeavy: 0.50, .ultimate: 0.55],
            "sekhmet": [.attackBasic: 0.45, .attackHeavy: 0.42, .ultimate: 0.45],
            // Zeus's ultimate is the 2026-09-17 take (the first one's motion
            // task had expired at Meshy before the meshy-7 rig could use it):
            // arms overhead to 0.3, a crouched lunge, the hurl at 0.78.
            "zeus":    [.attackBasic: 0.47, .attackHeavy: 0.40, .ultimate: 0.78],
            "ares":    [.attackBasic: 0.47, .attackHeavy: 0.50, .ultimate: 0.45],
            "thoth":   [.attackBasic: 0.55, .attackHeavy: 0.60, .ultimate: 0.65],
        ]
        let row = clip == .castRelease ? AnimationClip.attackHeavy : clip
        if let value = bespoke[asset]?[row] { return value }
        switch clip {
        case .attackBasic: return 0.42
        case .attackHeavy: return 0.55
        case .castRelease: return 0.60
        case .ultimate: return 0.62
        default: return 0.50
        }
    }

    /// How far a blow shoves its victim, by weight: a glance barely moves it,
    /// a killing blow throws it off its stance.
    private static func recoilStrength(for weight: HitWeight) -> Float {
        switch weight {
        case .light: return 0.45
        case .normal: return 1.00
        case .heavy: return 1.60
        case .critical: return 1.90
        case .lethal: return 2.40
        }
    }

    private(set) var unitNodes: [UUID: UnitNode] = [:]
    /// The unit plates — every fighter's health and attack bars — drawn over
    /// the view in points (`UnitPlateOverlay`); `layoutPlates` stands each
    /// one over its unit's head on every frame.
    let plates = UnitPlateOverlay(size: CGSize(width: 2, height: 2))
    /// The plates and the nodes they follow, snapshotted for the render
    /// thread under a lock whenever the units change — each with its
    /// figure's head joint when the rig has one (`headJoint(of:)`), so a
    /// body going down takes its plate down with it.
    private let plateLock = NSLock()
    private var plateTargets: [(UnitPlate, UnitNode, SCNNode?)] = []
    /// The bosses on the field, for the same thread: a plate is not drawn
    /// over a boss's chest for a unit standing inside the boss's body.
    private var plateBosses: [UnitNode] = []
    /// The render thread's own memory of each plate, eased from frame to
    /// frame so nothing pops: how far it is lifted off a neighbour it would
    /// overlap, and how far a fallen body has taken it down.
    private var plateLifts: [UUID: CGFloat] = [:]
    private var plateDrops: [UUID: Float] = [:]
    /// Where `place` stood each unit — its MARK — on the main thread, and
    /// the render thread's copy, taken with the targets: a plate whose unit
    /// is off its mark is a visitor to the declutter (`layoutPlates`).
    private var homeMarks: [UUID: SCNVector3] = [:]
    private var plateHomes: [UUID: SCNVector3] = [:]
    /// The render thread's clock for a visiting plate's fade.
    private var lastPlateLayout: TimeInterval = 0
    /// A plate as it is drawn this frame: its unit, and the box the
    /// declutter keeps others off — the level badge's left edge to the
    /// track's (or the marker's) right end, the badge's height, the status
    /// tiles' row while any are up.
    private typealias PlateBox = (id: UUID, left: CGFloat, right: CGFloat, bottom: CGFloat, top: CGFloat, tiles: Bool)
    /// Metres off its mark at which a unit's plate is a visitor: a dash
    /// carries a unit metres, and nothing else moves one off it.
    private static let offMark: Float = 0.15
    /// Seconds a visiting plate takes to fade back in at a clear spot. It
    /// goes out at once: a fade out is a plate drawn over another.
    private static let visitorFade: CGFloat = 0.12
    private var cameraNode = SCNNode()
    private var director: CameraDirector?
    private var queue: [BattleEvent] = []
    private var isPlaying = false
    /// Bumped by flush(). A playNext continuation scheduled before the flush
    /// compares its captured value and steps aside, instead of draining an
    /// empty queue and reporting "finished" a second time — which in auto-battle
    /// would take a second turn.
    private var playbackGeneration = 0
    private(set) var environment: BattleEnvironment = .duatGate
    /// The painting's own colours, read when the stage is built, so the
    /// lights match it (`StageBuilder.PaintingPalette`).
    private var palette = StageBuilder.PaintingPalette.neutral
    /// The rock under the boss's mark, built once per fight.
    private var ledge: SCNNode?
    /// The clip of the most recent cast, so its hits know how hard to land.
    private var lastCastClip: AnimationClip = .attackBasic
    /// What the last caster was, so a hit can sound like what struck it: a
    /// blade for a melee cut, a heavier body for a two-handed blow, and the
    /// caster's element for anything cast from a distance.
    private var lastCastColour: Juice.HitColour = .blade
    /// How long the event being presented should hold, in authored seconds,
    /// when the event's own declared duration is not what the picture needs:
    /// a cast holds only as far as the contact frame, and a heavy hit dwells
    /// on it. Set inside `present`, consumed by `playNext`, cleared before
    /// every event — only the arm that presents one knows, for instance,
    /// whether the caster had to close the distance first.
    private var holdOverride: TimeInterval?
    /// The rest of that clip — the follow-through after contact — repaid at
    /// the next turn boundary. The cast no longer waits for it (the damage
    /// lands on the contact frame and the swing finishes underneath), but the
    /// NEXT unit must, or it begins its turn over the top of the last one's
    /// swing and its walk back to its mark.
    private var castRecovery: TimeInterval = 0

    /// The multi-hit runs still open, for the gold TOTAL each earns after its
    /// last hit (Docs/FEEL.md W1.2, `MultiHitLedger`).
    private var hitLedger = MultiHitLedger()
    /// Whether this cast has spent its one impact frame (W1.3): a crit or a
    /// kill punches the grade once per cast at most. Cleared by every cast.
    private var impactFrameSpent = false
    /// The last caster's element: the colour of a kill's speed lines and of
    /// a normal hit's rim when the attacker has left the field.
    private var lastCasterElement: Element = .radiance
    /// Whether the last cast was an ultimate: its hits keep their haptic at ×3.
    private var lastCastWasUltimate = false
    /// The unit whose turn it is (`highlight`), for the reticle's colour and
    /// whether a tap may stamp one.
    private var actingID: UUID?
    /// Each unit's skills by id, with the painted icon its square wears
    /// (`SkillArt.keys`, resolved over the kit as the battle's squares are),
    /// for the skill banner over a caster (W1.9).
    private var skillArt: [UUID: [String: String]] = [:]
    /// Set once the triumph has played (`celebrate`), and cleared by a new run.
    private var celebrated = false

    // MARK: - Setup

    func build(combatants: [Combatant], environment: BattleEnvironment) {
        self.environment = environment
        scene.rootNode.removeAction(forKey: "cast_impact")
        // A new run of an auto-repeat is built in the same scene: whatever
        // the last one's end changed goes back. The slow motion stops and the
        // pace returns to the player's; a freeze or a tremble still pending
        // lets go; the camera — its colour drained on a loss, its framing on
        // the team after a win — is built anew below with the realm's grade;
        // the plates, their EXP bars and every float go with the old units.
        endSlowMotion()
        Juice.release(scene)
        retirePreviousStage()
        ledge = nil
        unitNodes.removeAll()
        homeMarks.removeAll()
        skillArt.removeAll()
        plates.removeAllPlates()
        plates.removeAllFloats()
        refreshPlateTargets()
        holdOverride = nil
        castRecovery = 0
        hitLedger = MultiHitLedger()
        impactFrameSpent = false
        lastCastWasUltimate = false
        actingID = nil
        celebrated = false

        buildStage()
        buildLighting()
        buildCamera()
        registerMaxHealth(combatants)
        place(combatants: combatants)
        startTourAreaDrill()
        startTourTriumph()
        awaitFirstFrames()
    }

    /// Takes the last run's stage out of a scene the view is still drawing,
    /// the way every other particle carrier leaves the fight.
    ///
    /// An auto-repeat lap rebuilds the fight in the SAME scene a second after
    /// the outcome (`BattleViewModel.conclude` → `restart` → `build`), and
    /// this used to take every root child off on the spot and free it: the
    /// weather, the braziers, every awakened unit's and boss's aura, and at
    /// ×4 a heal's or buff's one-shot motes spawned after the killing blow
    /// that were still alive — the removal of 2026-09-15's
    /// `SCNNodeRemoveDeadParticleInstance` crash, and the one path in the
    /// fight that still skipped `VFXLibrary.dismiss` (2026-09-24). Now the
    /// old camera goes at once (it carries nothing, and the view must find
    /// the new one), every other node stops its actions — a stale clip or
    /// dash completion must not reach the new fight — and moves under one
    /// holder that `dismiss` strips of its systems, hides this frame and
    /// removes half a second of frames later, on the main thread.
    private func retirePreviousStage() {
        cameraNode.removeFromParentNode()
        let leaving = scene.rootNode.childNodes
        guard !leaving.isEmpty else { return }
        let previous = SCNNode()
        previous.name = "previous_run"
        scene.rootNode.addChildNode(previous)
        for child in leaving {
            child.enumerateHierarchy { node, _ in node.removeAllActions() }
            previous.addChildNode(child)
        }
        VFXLibrary.dismiss(previous, reportsLive: false)
    }

    /// Under the CI tour's `-tour-aoe <effect>:<element>` (`duat_rite:tide`,
    /// `wrath_of_the_eye:ember`) the named effect is cast over the player's
    /// row once a second from four seconds in, through the same
    /// `VFXLibrary.spawnArea` a real area skill takes, so every run
    /// photographs what an enemy's area ultimate does to the team — run
    /// 224's 8-b caught one by chance, a white slab over all four heroes.
    private func startTourAreaDrill() {
        scene.rootNode.removeAction(forKey: "tour_aoe")
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-tour"), let flag = arguments.firstIndex(of: "-tour-aoe"),
              flag + 1 < arguments.count else { return }
        let parts = arguments[flag + 1].split(separator: ":").map(String.init)
        guard let effect = parts.first else { return }
        let element = parts.count > 1 ? Element(rawValue: parts[1]) : nil
        let tint = UIColor(hex: element?.accentHex ?? "#FFFFFF") ?? .white
        let fire = SCNAction.run { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let row = self.unitNodes.values.filter { $0.side == .player && !$0.isDefeated }
                guard !row.isEmpty else { return }
                let scale = row.map { Self.effectScale(for: $0) }.reduce(0, +) / Float(row.count)
                VFXLibrary.spawnArea(effect, over: row.map { $0.chestWorldPosition }, in: self.scene,
                                     tint: tint, scale: scale)
            }
        }
        scene.rootNode.runAction(.sequence([
            .wait(duration: 4),
            .repeatForever(.sequence([fire, .wait(duration: 1.0)]))
        ]), forKey: "tour_aoe")
    }

    private func buildStage() {
        // A real environment scene wins; otherwise a clean procedural platform,
        // which is enough to read positions and shadows correctly.
        if let url = Bundle.main.url(
            forResource: environment.sceneName, withExtension: "scn", subdirectory: "Environments"
        ) ?? Bundle.main.url(forResource: environment.sceneName, withExtension: "scn"),
           let loaded = try? ModelLibrary.parseScene(at: url) {
            for child in loaded.rootNode.childNodes {
                scene.rootNode.addChildNode(child)
            }
        } else {
            // The 3D set: a floating platform, ruins and statues, braziers,
            // mist and dust, with the environment's painting far behind it
            // for parallax. `StageBuilder` also sets the fog and the sky,
            // and hands back the painting's palette for the lights.
            palette = StageBuilder.buildBattleStage(environment, into: scene)
        }

        // Image-based lighting if the HDR shipped; a coloured ambient if not.
        if let iblURL = Bundle.main.url(forResource: environment.environmentMap, withExtension: "hdr")
            ?? Bundle.main.url(forResource: environment.environmentMap, withExtension: "exr") {
            scene.lightingEnvironment.contents = iblURL
            scene.lightingEnvironment.intensity = 1.15
        } else if let map = palette.environment {
            // The painting's own environment (2026-09-20; `StageBuilder.
            // environmentMap`): the set's sky, painting and ground wrapped
            // round the figures, so a metal reflects the place it stands in
            // and the physically based model has a world to light from.
            scene.lightingEnvironment.contents = map
            scene.lightingEnvironment.intensity = StageBuilder.environmentIntensity
        } else {
            // A flat colour as the lighting environment lights every surface
            // uniformly in that colour, which is what washed the whole stage
            // green. It is a stand-in for the procedural fallback, which has
            // no painting to wrap, so keep it weak enough to be ambient fill
            // and let the three real lights shape the figure.
            scene.lightingEnvironment.contents = UIColor(hex: environment.keyLightHex)
            scene.lightingEnvironment.intensity = 0.35
        }

    }

    /// Opaque over the near three-quarters of the stage, fading to nothing at
    /// the far edge, so the platform dissolves into the backdrop instead of
    /// ending in a hard line. The image's top row maps to the plane's far edge.
    private static let floorFade: UIImage = {
        let size = CGSize(width: 4, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            for row in 0..<Int(size.height) {
                let fromTop = CGFloat(row) / size.height
                let alpha = min(1, max(0, (fromTop - 0.04) / 0.30))
                context.cgContext.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                context.cgContext.fill(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 1))
            }
        }
    }()

    /// The centre of `image` at the aspect ratio of `size`.
    static func cropped(_ image: UIImage, toAspectOf size: CGSize) -> UIImage {
        guard size.width > 0, size.height > 0, let cg = image.cgImage else { return image }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let target = size.width / size.height
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > target {
            rect.size.width = height * target
            rect.origin.x = (width - rect.size.width) / 2
        } else {
            rect.size.height = width / target
            rect.origin.y = (height - rect.size.height) / 2
        }
        guard let piece = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: piece, scale: image.scale, orientation: image.imageOrientation)
    }

    private func buildLighting() {
        // Key: a shadow-casting directional light from the front-left.
        let key = SCNLight()
        key.type = .directional
        // The sun is nearly white (the realm's colour lifted 45% toward
        // it) since 2026-09-15: with the fill and the ambient now carrying
        // the painting's hue, a coloured key on top of them painted every
        // figure the set's colour — Zeus green in the marsh, blue in
        // Jötunheim on the first run of frames. The genre keeps its
        // monsters their own colours inside a tinted world.
        // 70% of the way to white since 2026-09-24: the owner's Summoners War
        // frames measure their highlights at (224, 225, 183) — hue 61°, 18%
        // saturated, a sun barely warm — where ours were hue 34–39° at 62%,
        // orange. The set keeps its hue in the fill, the ambient and the
        // painting; the sun that shapes every figure is nearly white.
        key.color = (UIColor(hex: environment.keyLightHex) ?? .white).mixed(with: .white, amount: 0.70)
        // 1,300 (was 1,150) against a fill and an ambient taken DOWN: the
        // genre's figures measure twice our contrast (a spread of 42–66
        // against 21–38, their brightest 2% at 215–240 against 98–170), which
        // is a stronger key over a weaker fill, not more light everywhere.
        // The 1.85 white point is what lets the key rise without clipping.
        key.intensity = 1_300
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        key.shadowColor = UIColor.black.withAlphaComponent(0.55)
        // 34 (was 30) since 2026-09-24: the camera stands square behind the
        // team at z ≈ +18, and the sets' back row (the columns at −7, the
        // statues at −6.3, the far parapet at −8.4) is 25–27 m out, on the
        // edge of 30. The contact under a figure is its own oval now
        // (`UnitNode.attachGroundShadow`), so this shadow is for the set.
        // With the far edge at −11 and the back row carried back with it
        // (`StageBuilder.withTheFarEdge`, the same day) the statues stand
        // at −8.9, the columns at −9.6 and the parapet at −11: 28–31 m from
        // every ordinary camera, still inside 34.
        key.maximumShadowDistance = 34
        key.automaticallyAdjustsShadowProjection = true

        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-6, 10, 6)
        keyNode.eulerAngles = SCNVector3(-0.85, -0.6, 0)
        scene.rootNode.addChildNode(keyNode)

        // Fill: from the painting's side, no shadow — keeps dark models
        // readable. In the PAINTING'S sky colour since 2026-09-15 (lifted
        // halfway to white so a night sky still fills): the fixed blue it
        // was pulled every warm set toward the same neutral, and one hue
        // per place is what the genre's sets have.
        //
        // The SET's since 2026-09-24 (Docs/FEEL.md L1, `StageBuilder.
        // lightLayers`): the figures have a fill and an ambient of their own,
        // the same strength from the same side, 80% of the way to white, so
        // the realm's hue stays in the stone and the figures keep their own
        // paint. The key above lights both, and casts the set's shadows as
        // one light. Under `-tour-layers off` the rig is the shared one of
        // before, for the CI lab's control frame.
        let layered = StageBuilder.lightLayers
        let fill = SCNLight()
        fill.type = .directional
        fill.color = palette.sky.mixed(with: .white, amount: 0.62)
        // 330 (was 400): see the key.
        fill.intensity = 330
        if layered { fill.categoryBitMask = StageBuilder.setLights }
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(7, 5, -5)
        fillNode.eulerAngles = SCNVector3(-0.5, 2.3, 0)
        scene.rootNode.addChildNode(fillNode)

        // Ambient floor so nothing goes fully black — in the painting's
        // horizon colour, mixed with the hand-picked fog so a very dark
        // painting keeps its intended hue, and lifted toward white.
        let ambient = SCNLight()
        ambient.type = .ambient
        let hand = UIColor(hex: environment.fogHex) ?? .darkGray
        // Lifted 60% toward white (was 50%): the genre's shadows are a
        // near-neutral grey (19% saturated in the arena frame) where ours
        // were a 73–80% saturated brown.
        let horizon = palette.horizon.mixed(with: hand, amount: 0.35)
        ambient.color = horizon.mixed(with: .white, amount: 0.6)
        // Lower where the painting's environment map now fills the shadow
        // side (2026-09-20); the flat-colour fallback keeps the old floor.
        ambient.intensity = palette.environment != nil ? 150 : 240
        if layered { ambient.categoryBitMask = StageBuilder.setLights }
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        guard layered else { return }
        // The figures' pair: the same fill and ambient, near-neutral.
        let figureFill = SCNLight()
        figureFill.type = .directional
        figureFill.color = palette.sky.mixed(with: .white, amount: Self.figureFillWhite)
        figureFill.intensity = fill.intensity
        figureFill.categoryBitMask = StageBuilder.figureLights
        let figureFillNode = SCNNode()
        figureFillNode.light = figureFill
        figureFillNode.position = fillNode.position
        figureFillNode.eulerAngles = fillNode.eulerAngles
        scene.rootNode.addChildNode(figureFillNode)

        let figureAmbient = SCNLight()
        figureAmbient.type = .ambient
        figureAmbient.color = horizon.mixed(with: .white, amount: Self.figureFillWhite)
        figureAmbient.intensity = ambient.intensity
        figureAmbient.categoryBitMask = StageBuilder.figureLights
        let figureAmbientNode = SCNNode()
        figureAmbientNode.light = figureAmbient
        scene.rootNode.addChildNode(figureAmbientNode)
    }

    /// How far toward white the figures' own fill and ambient are taken from
    /// the set's hue (Docs/FEEL.md L1): the realm's colour a hint on the
    /// figures, their own paint the colour.
    static let figureFillWhite: CGFloat = 0.8

    /// The turn circle's peak on the pale marble sets: 60% of the 0.9 it
    /// stands at elsewhere (`UnitNode.turnDiscPeak`, W1.9).
    static let paleDiscPeak: CGFloat = 0.54

    private func buildCamera() {
        let camera = SCNCamera()
        // Solved numerically for a landscape phone (852 × 393 points): the
        // genre's view is higher and further back than the first landscape
        // solve (35°, 5.5 m up, 24° down), which stood the player line a
        // third of the screen tall and hid the far edge of the platform. From
        // 7.2 m up, 11 m back and 30° down at 34°, the near player rank's
        // feet land at 77% of the screen height and its heads at 53% (a
        // figure a quarter of the screen tall), the near enemy rank's feet at
        // 46% and heads at 27%, the far rank's heads at 20%, the platform's
        // far edge at 22% with the painting above it — both lines in one
        // frame with room round them, and a boss seen whole.
        camera.fieldOfView = 34
        camera.zNear = 0.1
        camera.zFar = 120
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        // THE SHOULDER (2026-09-15). `whitePoint` is where the tone curve
        // stops climbing, and it sat at SceneKit's default 1.0 for the life
        // of the project: every surface at or over 1.0 clipped flat to
        // paper. `tools/framelight.py` measured a quarter of Olympus's near
        // floor and a sixth of the fjord's sky with no detail left in them
        // while the Duat sat at 0.2%; the owner: "Lighting and contrast
        // feels too bright doesnt it?" At 1.85 the curve keeps rolling past
        // 1.0, so lit marble keeps its grain and only a real emissive
        // reaches white.
        camera.whitePoint = 1.85
        // Bloom only on real highlights: at 0.55 over 0.85 a sunlit sandstone
        // floor became a sheet of light and a boss's glow a wall of yellow,
        // and 0.3 over 0.94 still spread a clipped floor over the figures
        // standing on it.
        // 0.14 over 0.975, radius 8 (was 0.22, 10) since 2026-09-24: the
        // owner's frames are CLEAN — a glow on a real highlight and no haze
        // round the braziers — and Olympus's back row photographed as a pale
        // bloom of bowls and columns.
        camera.bloomIntensity = 0.14
        camera.bloomThreshold = 0.975
        camera.bloomBlurRadius = 8
        // Chromatic aberration at 0.35 read as a filter (2026-09-20): a trace.
        // None since 2026-09-24: a colour fringe is a soft red-blue edge on
        // every figure's silhouette, and the genre's figures measure twice
        // our edge strength (a 99th-percentile gradient of 680–750 against
        // 320–370). Nothing in a clean frame is fringed.
        camera.colorFringeStrength = 0
        // One grade per place (2026-09-15): the genre's sets are each one
        // hue, pushed. `StageBuilder.grade(for:)` holds the numbers.
        let grade = StageBuilder.grade(for: environment)
        camera.saturation = grade.saturation
        camera.contrast = grade.contrast
        // The grade's hand-picked exposure, plus what the painting itself
        // asks for: a pale painting is pulled down up to half a stop, a
        // night lifted a quarter (`PaintingPalette.exposureCompensation`),
        // so each set is lit to MATCH its backdrop rather than on top of it.
        // A set of pale marble takes no more than a tenth of a stop of that
        // lift (`Grade.maxLift`): the Forum's night painting lifted its
        // marble to a sunlit cream in the skill zoom (run 221).
        camera.exposureOffset = grade.exposure + min(grade.maxLift, palette.exposureCompensation)
        camera.vignettingIntensity = grade.vignette
        camera.vignettingPower = 1.2
        // Kept, and weighed (2026-09-24): SceneKit's SSAO is one half-size
        // pass over the depth the deferred shadow already writes, and it is
        // what seats a sole on the stone and darkens the grout between the
        // tiles — the contact the genre's frames have everywhere. Its radius
        // stays at 0.6 m: wider, it rings the figures in grey halos.
        camera.screenSpaceAmbientOcclusionIntensity = 0.6
        camera.screenSpaceAmbientOcclusionRadius = 0.6
        // NO motion blur (run 220). SceneKit blurs by velocity, and the
        // camera's own velocity counts: every skill camera's push-in and
        // pull-out (`CameraDirector.zoom`, 0.22 s in, 0.30 s out) smeared the
        // whole frame into a radial orange streak with ghosted doubles of
        // the statues — 8-arena_battle-a measured a third of the sharpness
        // of the same frame at rest. The genre's skill camera is crisp; the
        // swing trail and the dash already carry the speed.
        camera.motionBlurIntensity = 0

        cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 7.2, 11.0)
        cameraNode.eulerAngles = SCNVector3(-0.524, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        director = CameraDirector(cameraNode: cameraNode)
    }

    /// Positions both teams. The camera sits on the +Z side, so the player's
    /// line stands nearest it at +Z and faces away, toward the enemies at -Z,
    /// who face +Z — toward the player and the camera. A model's authored
    /// facing is +Z (Docs/ART_PIPELINE.md), hence the half-turn on the near
    /// side. Ranks are staggered so nobody is hidden behind anybody.
    private func place(combatants: [Combatant], entering: Bool = false) {
        // A 5v5 is ten characters plus a full post stack; a 1v1 can afford the
        // detailed mesh. The loader falls back to the full model when no reduced
        // export has been shipped.
        let detail = ModelLibrary.detail(forCombatantCount: combatants.count + (entering ? unitNodes.count : 0))
        noteLineWidth(combatants)
        let paleSet = StageBuilder.isPaleSet(environment)
        for combatant in combatants {
            let node = UnitNode(combatant: combatant, detail: detail)
            node.playbackSpeed = pace
            // The turn circle at 60% on the pale marble (W1.9).
            if paleSet { node.turnDiscPeak = Self.paleDiscPeak }
            // The icon each skill's square wears, for the banner over the
            // caster: resolved over the kit the squares resolve over (the
            // skills that are not passive, in order), so the two match.
            let kit = combatant.skills.filter { !$0.isPassive }
            let icons = SkillArt.keys(for: kit, element: combatant.element, ranged: !combatant.model.melee)
            var art: [String: String] = [:]
            for (index, skill) in kit.enumerated() where index < icons.count {
                art[skill.id] = icons[index]
            }
            skillArt[combatant.id] = art
            // The genre's soft oval under the feet, and the figure's textures
            // filtered like the set's (2026-09-24).
            node.attachGroundShadow()
            StageBuilder.sharpenTextures(in: node, mipsBeyondDiffuse: false)
            let home = position(for: combatant, teamSize: lineWidth[combatant.side] ?? 1)
            homeMarks[combatant.id] = home
            // A model is authored facing +Z: the player's line turns its back
            // on the camera's old side, the enemy line faces it, and a boss,
            // standing off the centre line, turns to face the middle of the
            // field (a character faces with `atan2(dx, dz)`; only a camera
            // needs `look(at:)`).
            // A model is authored facing +Z: the team turns its back on the
            // camera and faces the enemy row, the enemy row faces the
            // camera, and a boss, standing off the centre line, turns to
            // face the middle of the field.
            node.eulerAngles.y = combatant.isBoss
                ? atan2(-home.x, -home.z)
                : (combatant.side == .player ? .pi : 0)
            if entering, combatant.isBoss {
                // A boss RISES over the far rim from the dark under the
                // platform, rather than walking on: there is no floor where
                // it stands.
                node.position = SCNVector3(home.x, home.y - 4.5, home.z)
                node.opacity = 0
                let rise = SCNAction.move(to: home, duration: beat(1.2))
                rise.timingMode = .easeOut
                node.runAction(.group([rise, .fadeIn(duration: beat(0.6))]))
            } else if entering {
                // A later wave walks on from the far side of the field —
                // from two metres behind its mark since 2026-09-24 (three
                // before). The enemy row came forward to −3.4/−4.4 that day,
                // and from three metres a three-a-side's outer arrivals
                // started inside the ±3.8 braziers; even with the back row
                // carried back to the new far edge
                // (`StageBuilder.withTheFarEdge`) three metres would start a
                // four-a-side's outer arrivals inside the colossi and the
                // Lair's trees. Measured against every set's pieces,
                // footprint by footprint on the shipped meshes: from two
                // metres the widest line that ever walks on (three; a raid's
                // guard is two) starts 1.45 m clear of everything, the
                // guard 0.82 m, and even a four-a-side's outer start keeps
                // 0.18 m from the Lair's dead tree, where the figure is
                // still fading in.
                node.position = SCNVector3(home.x, home.y, home.z - 2.0)
                node.opacity = 0
                let walk = SCNAction.move(to: home, duration: beat(0.7))
                walk.timingMode = .easeOut
                node.runAction(.group([walk, .fadeIn(duration: beat(0.45))]))
            } else {
                node.position = home
            }
            scene.rootNode.addChildNode(node)
            unitNodes[combatant.id] = node
            if !combatant.isBoss {
                // The unit's bars, on the overlay: a boss keeps the HUD's
                // wide bar and wears no plate.
                // An opponent's plate keeps room at its right end for the
                // matchup marker a player's turn puts there.
                let plate = plates.addPlate(for: combatant.id, elementHex: combatant.element.accentHex,
                                            wearsMarker: combatant.side == .opponent)
                node.plate = plate
                plate.setLevel(combatant.level)
                plate.setHealth(combatant.healthFraction, animated: false)
                plate.setAttackBar(combatant.attackBar, animated: false)
                plate.setStatuses(combatant.statuses)
                if entering { plate.enter(over: beat(0.45)) }
            }
            if combatant.isBoss {
                // A boss is LIT: a warm spot from its front, riding with it,
                // aimed at its chest. The owner, with the Coils of Apep on
                // his phone: "it's hard to see the boss" — a dark serpent
                // against a night painting behind two columns.
                let spot = SCNLight()
                spot.type = .spot
                spot.color = (UIColor(hex: environment.keyLightHex) ?? .white).mixed(with: .white, amount: 0.55)
                // A SPOT, not a second sun. It was 3,000 through a 75°
                // cone reaching 34 m — the key light is 1,150 and the slab
                // is 44 m across, so the moment a boss walked on, the whole
                // set was lit two and a half times over: the owner's
                // Labyrinth frame of wave 3 is the arena as a pale wash with
                // only the health bars in it. Same mistake as the impact
                // flash, one screen further on. The lamp stands about 8.5 m
                // from the chest it aims at, so a 46° cone covers a boss
                // three and a half metres wide with margin and nothing else,
                // and the light is gone by 14 m — before the player's row,
                // which is behind it anyway.
                // Full for a dark hide, less for pale paint (run 221): the
                // sandstone Colossus under all 2,400 was paper white across
                // the chest and arms, 79% of its worst patch clipped, so the
                // spot is scaled by what the paint gives back
                // (`UnitNode.bossLightScale`: the Colossus about 1,390, the
                // serpent, the Hydra and the Jötunn the whole 2,400).
                spot.intensity = 2_400 * node.bossLightScale
                print("[Boss] \(combatant.model.assetName): paint \(node.paintAlbedo.map { String(format: "%.3f", $0) } ?? "unread") linear, warm spot \(Int(spot.intensity.rounded()))")
                spot.spotInnerAngle = 22
                spot.spotOuterAngle = 46
                spot.attenuationStartDistance = 5
                spot.attenuationEndDistance = 14
                let height = combatant.model.height
                let chest = SCNNode()
                chest.position = SCNVector3(0, height * 0.42, 0)
                node.addChildNode(chest)
                let lamp = SCNNode()
                lamp.light = spot
                lamp.position = SCNVector3(3.0, height * 0.95, 7.0)
                let aim = SCNLookAtConstraint(target: chest)
                aim.isGimbalLockEnabled = true
                lamp.constraints = [aim]
                node.addChildNode(lamp)
                // The spot is the boss's, a figure light (Docs/FEEL.md L1):
                // it no longer reaches the stone round the breach at all,
                // and the lamp and its aim join the figure's layer.
                if StageBuilder.lightLayers { spot.categoryBitMask = StageBuilder.figureLights }
                node.markFigure()
            }
            if combatant.isBoss, ledge == nil {
                let recipe = StageBuilder.recipe(for: environment)
                let rock = StageBuilder.breach(
                    rock: recipe.rock, floor: recipe.floor, floorRepeats: recipe.floorRepeats,
                    floorTint: recipe.floorTint, at: home
                )
                // Built after the set, so it joins the set's layer here.
                if StageBuilder.lightLayers { StageBuilder.separateBattleSet(rock) }
                scene.rootNode.addChildNode(rock)
                ledge = rock
            }
        }
        refreshPlateTargets()
    }

    /// The width of each side's line, in marks, fixed when the fight opens.
    ///
    /// Centring on who is ALIVE was wrong and the owner saw it: in a dungeon a
    /// wave arrives beside survivors, and a line centred on the current count
    /// slides sideways every time somebody dies or walks on, so the enemies
    /// never look like they are standing anywhere in particular. A mark is a
    /// place on the floor. It belongs to a slot, it does not move, and
    /// `BattleEngine.freeOpponentSlots` already hands an arrival the lowest
    /// mark nobody is standing on — so an arrival now fills the gap its
    /// predecessor left instead of shoving the line over.
    private var lineWidth: [BattleSide: Int] = [:]

    /// The slots a boss holds, per side. A boss stands off the line — over
    /// the far rim — so its slot is not a mark, and the units whose slots
    /// come after it close up over the gap it would otherwise leave: the
    /// Coils of Apep lists the serpent third of four, and without this its
    /// two adds and Ammit stood on marks 1, 2 and 4 of a four-wide line.
    private var bossSlots: [BattleSide: Set<Int>] = [:]

    /// Records the width once per side, from the opening line-up, and never
    /// narrows it: a stage that opens with three and calls in two more is five
    /// marks wide from the first frame, so nothing shifts when they arrive.
    private func noteLineWidth(_ combatants: [Combatant]) {
        for side in [BattleSide.player, .opponent] {
            let mine = combatants.filter { $0.side == side }
            for boss in mine where boss.isBoss {
                bossSlots[side, default: []].insert(boss.slot)
            }
            let wanted = mine.filter { !$0.isBoss }.map { markIndex(for: $0) + 1 }.max() ?? 0
            lineWidth[side] = max(lineWidth[side] ?? 0, max(wanted, 1))
        }
    }

    /// A unit's mark along its line: its slot, less the bosses holding lower
    /// slots, who stand off the line. A boss's slot never changes once it is
    /// on the field, so a unit's mark never changes either.
    private func markIndex(for combatant: Combatant) -> Int {
        let bosses = bossSlots[combatant.side] ?? []
        return combatant.slot - bosses.filter { $0 < combatant.slot }.count
    }

    /// Where a boss stands: over the far rim, behind the enemy line, sunk
    /// `bossSink` of its height below the platform so the rock hides its
    /// legs and the rest of it towers over the field. The owner: "the boss
    /// towers over them and half of it is under a bridge or cliff and the
    /// top half is fighting and hitting." The platform's far edge is at
    /// z = −8.4 (`StageBuilder`), so 9.8 puts it a stride beyond the edge,
    /// which is what makes the rim read as a cliff it has climbed to; on
    /// the centre line, between the two columns that close the back of
    /// every set, because a boss fight is framed from behind the team
    /// (`CameraDirector.bossYaw`) and the gate is centred from there.
    /// On the rim itself since 2026-09-15 (a stride beyond it, at −9.8,
    /// before): the genre's boss stands close over its adds and fills the
    /// frame, and the camera is solved low and near for it
    /// (`CameraDirector.bossPitch`). Sunk 32% rather than 42% for the same
    /// reason: more of it above the floor.
    /// On the floor's far edge wherever the floor puts it
    /// (`StageBuilder.battleFloorFarEdge`, −8.4 when this was written, −11
    /// since 2026-09-24: 6.6 m behind the enemy row's deeper marks, the breach's thrown
    /// tiles no longer reaching the adds' marks, and the columns it stands
    /// between carried back with it by `StageBuilder.withTheFarEdge`).
    private static let bossMark = SCNVector3(0, 0, StageBuilder.battleFloorFarEdge)
    static let bossSink: Float = 0.32

    /// TWO ROWS ABREAST, the team's nearest the camera (2026-09-11, the
    /// fourth layout and the genre's own).
    ///
    /// The owner, on the wings that came before this: "That camera angle
    /// is AWFUL. How do you expect me to click on the target I attack?
    /// Summoners War has it from the back but slightly off to the right."
    /// Which is exactly the genre's field: the player's team in a row
    /// across the bottom of the frame with its back to the camera, the
    /// enemy's in a row across the middle facing it, every enemy standing
    /// alone against the floor where a finger finds it, and the camera
    /// behind the team, above it, a little to the right
    /// (`CameraDirector.homeYaw` −15°, `homePitch` 26°). The two rows are
    /// 6 m apart, which at that pitch puts the enemy row's feet a tenth of
    /// the frame above the team's heads, and 2.4 m from mark to mark, a
    /// tenth of the frame across. The enemy row is pushed 0.6 m sideways so
    /// no enemy ever stands straight behind a player; a side of more than
    /// five falls back to a second rank rather than spreading wider than
    /// the camera will frame.
    ///
    /// SUPERSEDED IN ITS NUMBERS (2026-09-24): the paragraph above is the
    /// history. The camera is square behind the team now (`homeYaw` 0,
    /// `homePitch` 19°), the rows stand `StageBuilder.arenaRowDepth` either
    /// side of `StageBuilder.arenaCentre` (team z +7.0, enemies −3.4, ten
    /// metres apart), the team 2.4 m and the enemies 3.2 m from mark to
    /// mark, every other mark staggered in depth, and no sideways push —
    /// see the body.
    private func position(for combatant: Combatant, teamSize: Int) -> SCNVector3 {
        let sideSign: Float = combatant.side == .player ? 1 : -1
        if combatant.isBoss {
            // The mark is written on the far side already (a boss is only
            // ever an opponent); multiplying its z by the side's sign, as
            // the line marks below do, put the Colossus at +9.8 — behind
            // the player's own column, over the NEAR rim, in the bottom
            // left corner of two runs' frames, where it was taken for a
            // hanging rock.
            return SCNVector3(Self.bossMark.x, -combatant.model.height * Self.bossSink, Self.bossMark.z)
        }
        let perRank = 5
        let mark = markIndex(for: combatant)
        let rank = Float(mark / perRank)
        let indexInRank = mark % perRank
        let inThisRank = max(1, min(perRank, teamSize - Int(rank) * perRank))
        // THE OWNER'S FIELD (2026-09-24, with `CameraDirector.homeYaw` 0 and
        // `homePitch` 19°): his Summoners War arena frame, back-solved, has
        // the rows about ten metres apart, the team's marks 2.4–2.6 m apart
        // and the enemy's 1.3 times wider, each row staggered in depth. So
        // the team stands at z +7.0 and the enemy row at −3.4 (below) — the field
        // moved toward the camera rather than the enemies pushed back, so
        // the sets' back rows (the columns at −7, the braziers at −5.6, the
        // statues at −6.3) stay clear of every mark — the team 2.4 m apart
        // with every other unit half a metre nearer the camera, the enemies
        // 3.2 m apart with every other one a metre further back. From
        // straight behind, the enemy row's feet land above the team's heads
        // on screen, so no lateral stagger is needed to keep an enemy
        // findable; the old 0.6 m would only have pushed the enemy row off
        // the centre of the frame.
        // Measured by footprint, those back rows did NOT stay clear: the
        // colossi, statues, trees and roots at −6.3 reach forward to −4.6,
        // onto a four-a-side's outer marks at (±4.8, −4.4). They go back
        // with the far edge now (`StageBuilder.withTheFarEdge`), a metre
        // clear of every enemy mark.
        // A FIVE-wide team stands 2.0 m apart (2026-09-24): at 2.4 its outer
        // figures stood at 0.15 and 0.85 of the width, the right one under
        // the skill squares, and holding them inside 0.24–0.76
        // (`CameraDirector.teamWidthMargin`) at 2.4 m would have stepped the
        // camera back to a team 0.22 of the frame tall; at 2.0 it is 0.27.
        // Inside 0.24–0.76 the right-hand figure's feet still stand behind
        // the first skill square on the player's turn (it starts at 0.67);
        // `teamWidthMargin` says why that is kept.
        let isPlayer = combatant.side == .player
        let spacing: Float = isPlayer ? (inThisRank >= 5 ? 2.0 : 2.4) : 3.2
        let centred = Float(indexInRank) - Float(inThisRank - 1) / 2
        let odd = indexInRank % 2 == 1
        // Positive is away from the centre line: the team's nearer the camera,
        // the enemy's further from it.
        let staggerDepth: Float = odd ? (isPlayer ? 0.5 : 1.0) : 0
        // A second rank stands further from the camera than the first and
        // half a step over, so nobody hides behind the unit in front.
        let halfStep: Float = rank.truncatingRemainder(dividingBy: 2) == 0 ? 0 : spacing / 2
        // Each row `arenaRowDepth` (5.2 m) from the arena's centre, which is
        // at z +1.8 (`StageBuilder.arenaCentre`): the floor's medallion is
        // drawn round the same two numbers, so the rows and its gold band
        // cannot drift apart.
        let depth = StageBuilder.arenaRowDepth + staggerDepth + rank * 1.7
        return SCNVector3(centred * spacing + halfStep, 0, StageBuilder.arenaCentre.z + sideSign * depth)
    }

    // MARK: - Playback

    func enqueue(_ events: [BattleEvent]) {
        queue.append(contentsOf: events)
        if !isPlaying { playNext() }
    }

    /// Drops queued animation and snaps to the end state. Used by the skip button.
    func flush(combatants: [Combatant]) {
        playbackGeneration += 1
        queue.removeAll()
        isPlaying = false
        holdOverride = nil
        castRecovery = 0
        // A cast's impact is a scene action waiting for its contact frame; a
        // skip must take it with the rest of the queue rather than let it
        // burst over a field that has already jumped to the end state.
        scene.rootNode.removeAction(forKey: "cast_impact")
        // And the same for a swing still waiting out its dash: the queue it
        // belonged to is gone, so it would otherwise land a lone attack over
        // a battle that has already been resolved.
        for node in unitNodes.values { node.cancelPendingClip() }
        // Skip is the one way to watch a turn with no feedback (W1.1): no
        // freeze, no tremble, no slow motion left running, and no TOTAL
        // owed to a multi-hit whose last hit will never be shown.
        endSlowMotion()
        Juice.release(scene)
        hitLedger = MultiHitLedger()
        sync(combatants: combatants)
        delegate?.battleSceneDidFinishPlayback(self)
    }

    /// Stops the fight where it stands, for a forfeit (review, 2026-09-24):
    /// what `flush` does for a skip, without jumping the field to the turn's
    /// end and without handing the turn back. The end of a fight is shown on
    /// the field now (DEFEAT over the drained set, Docs/FEEL.md W1.7), and a
    /// forfeit in the middle of a turn's playback left the rest of that turn
    /// playing under the word — its blows, a final blow's slow motion and
    /// camera ease, a win's `.battleEnded` haptic. Everyone walks back to
    /// their mark and the camera goes home; the health stands as last shown.
    func halt() {
        playbackGeneration += 1
        queue.removeAll()
        isPlaying = false
        holdOverride = nil
        castRecovery = 0
        scene.rootNode.removeAction(forKey: "cast_impact")
        scene.rootNode.removeAction(forKey: "cast_projectile")
        for node in unitNodes.values { node.cancelPendingClip() }
        endSlowMotion()
        Juice.release(scene)
        hitLedger = MultiHitLedger()
        returnEveryoneHome()
        director?.returnHome()
    }

    /// Forces every node to match engine truth. Called after a skip and at the
    /// end of each turn, so a dropped animation can never desync the display.
    func sync(combatants: [Combatant]) {
        for combatant in combatants {
            guard let node = unitNodes[combatant.id] else { continue }
            node.setHealth(fraction: combatant.healthFraction, animated: false)
            node.setStatuses(combatant.statuses)
            node.plate?.setAttackBar(combatant.attackBar, animated: true)
            if !combatant.isAlive { node.markDefeated() }
        }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            // The units first (2026-09-24): a melee attacker still standing
            // where its dash landed has its walk back running by the time the
            // camera re-measures the field, so it is skipped rather than
            // measured at its landing spot (`CameraDirector.measureField`).
            returnEveryoneHome()
            director?.returnHome()
            delegate?.battleSceneDidFinishPlayback(self)
            return
        }

        isPlaying = true
        let event = queue.removeFirst()
        delegate?.battleScene(self, willPresent: event)
        holdOverride = nil
        let frozen = present(event)

        // A cast holds only until the blade lands — `holdOverride` — so the damage
        // event that carries the flash, the flinch, the shove, the number and
        // the freeze is presented ON the contact frame with the rest of the
        // swing still playing underneath it. Everything else keeps the
        // duration the event itself declares.
        var span = holdOverride ?? event.presentationDuration
        switch event {
        case .turnBegan, .waveStarted, .battleEnded:
            // Repay whatever is left of the follow-through the cast did not
            // wait for, so the last attacker finishes its swing and walks back
            // to its mark before the next one moves. Two units moving at once
            // for no reason on screen is most of what made the fight hard to
            // read.
            span += castRecovery
            castRecovery = 0
        case .skillCast:
            // The cast's own hold IS the run-up to contact; its follow-through
            // starts where that ends.
            break
        default:
            // Everything that plays after the contact frame — the numbers, the
            // statuses, the later hits of a multi-hit skill — is time the
            // swing is finishing in, so it comes off what is still owed.
            // Without this a five-hit skill would add three quarters of a
            // second of nothing to the front of the next turn.
            castRecovery = max(0, castRecovery - span)
        }

        // A freeze-frame steals time from the event's hold; give it back so the
        // cadence between hits stays what the event durations say it is.
        let hold = max(0.02, beat(span)) + frozen
        let generation = playbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.playNext()
        }
    }

    // MARK: - Presenting one event

    /// Returns how long the world froze for this event, if it did.
    @discardableResult
    private func present(_ event: BattleEvent) -> TimeInterval {
        switch event {
        case .battleStart:
            for node in unitNodes.values { node.play(.idleCombat) }
            // The fight was silent between its blows (Docs/FEEL.md W1.4,
            // 2026-09-24): the realm's horn call opens it, a boss's arrival
            // its own boom, roar and cymbal.
            AudioLibrary.shared.play(unitNodes.values.contains(where: { $0.side == .opponent && $0.isBoss })
                                     ? .bossArrival : .waveCall(for: environment.pantheon), volume: 0.85)

        case .turnBegan(let actor, _):
            // A random-target multi-hit's victim missed on its last hit
            // still earns its TOTAL, as the turn ends.
            closeOpenTotals()
            returnEveryoneHome()
            highlight(actor)
            showMatchups(for: actor)
            // The actor's attack bar is full: that is why it is acting.
            unitNodes[actor]?.plate?.setAttackBar(1, animated: true)
            // The walk-ons of the last wave are on their marks by now.
            director?.frameField()

        case .turnSkipped(let actor, let reason):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("SKIPPED", over: node, color: UIColor(hex: "#C8C8C8")!)
            if speedMultiplier < 3 { AudioLibrary.shared.play(.status(reason), volume: 0.45) }

        case .skillCast(let actor, let skillID, let name, let targets, let shot, let animation, let vfx):
            guard let casterNode = unitNodes[actor] else { return 0 }
            let targetNode = targets.first.flatMap { unitNodes[$0] }
            // Stamped, so a console that ends mid-fight says which cast it
            // ended in (the arena crash of 2026-09-15 was read off the last
            // clip loaded, which is a poorer clock).
            Perf.note("cast \(name) by \(casterNode.spec.assetName) as \(animation) on \(targets.count) target(s)")
            lastCastClip = animation
            lastCasterElement = casterNode.element
            lastCastWasUltimate = animation == .ultimate
            // One impact frame per cast at most (W1.3).
            impactFrameSpent = false
            // A melee unit swinging is steel or stone; anything else is its
            // element. `castRelease` and the ultimate are always the element,
            // because that is what the effect on screen already shows.
            if animation == .castRelease || animation == .ultimate || !casterNode.spec.melee {
                lastCastColour = .element(casterNode.element)
            } else {
                lastCastColour = animation == .attackHeavy ? .blunt : .blade
            }
            Juice.prepareHaptics()
            AudioLibrary.shared.play(.whoosh, volume: animation == .ultimate ? 1.0 : 0.6)
            // A melee unit closes on its one victim before the swing and stays
            // there through the hits; casters, archers and line-wide skills
            // strike from where they stand. A boss has no floor to cross: it
            // strikes from where it towers.
            let closes = targetNode.map { victim in
                casterNode.spec.melee && !casterNode.isBoss && targets.count == 1
                    && victim.side != casterNode.side
                    && (animation == .attackBasic || animation == .attackHeavy)
            } ?? false
            // The camera is told where the leap will land before it begins:
            // a push-in aimed at the caster's mark held on empty floor while
            // the caster fought four metres away (2026-09-15).
            let landing = closes ? targetNode.map { casterNode.dashDestination(toward: $0) } : nil
            director?.perform(shot, on: casterNode, target: targetNode, focus: landing)
            var walkUp: TimeInterval = 0
            if let targetNode, closes {
                let from = casterNode.position
                let to = landing ?? from
                let dx = to.x - from.x
                let dz = to.z - from.z
                let travel: Float = (dx * dx + dz * dz).squareRoot()
                let stretch: Double = max(1, min(Self.dashStretchCap, Double(travel / Self.dashReach)))
                let leap: TimeInterval = Self.dashDuration * stretch
                casterNode.dash(toward: targetNode, duration: beat(leap))
                // The swing waits for the feet. These two lines used to be
                // consecutive statements, so the clip and the leap started on
                // the same frame and the wind-up — the only part of an attack
                // that carries anticipation — played four metres away in
                // mid-air; the figure arrived a quarter of the way through its
                // own cut. The 80 ms overlap is deliberate: the wind-up begins
                // as the weight comes down, which is what ties a leap and a
                // swing into one motion.
                walkUp = max(0, leap
                    * (UnitNode.dashGather + UnitNode.dashFlight) - 0.08)
            }
            casterNode.play(animation, after: beat(walkUp))
            // What the swing leaves behind and what the spell stands on: a
            // blade's trail through every melee clip, in steel for a strike
            // and in the element for an ultimate; a rune ring under a caster
            // for the length of the cast. The owner: "the effects of attacks
            // ... summoners war quality — even animations of characters."
            let elementTint = UIColor(hex: casterNode.element.accentHex) ?? .white
            let clipLength = beat(animation.fallbackDuration)
            if animation == .castRelease || animation == .ultimate {
                casterNode.castRing(tint: elementTint, duration: clipLength, after: beat(walkUp))
            }
            // An ultimate gathers before it lands: motes drawn up round the
            // caster and a swelling core through the wind-up (2026-09-15).
            if animation == .ultimate {
                VFXLibrary.charge(on: casterNode, tint: elementTint,
                                  duration: beat(walkUp + animation.fallbackDuration * Self.contactFraction(of: animation, for: casterNode.spec.assetName)),
                                  scale: Self.effectScale(for: casterNode))
            }
            if casterNode.spec.melee, animation != .castRelease, !casterNode.isBoss {
                let steel = UIColor(hex: "#D9E4F2") ?? .white
                casterNode.swingTrail(tint: animation == .ultimate ? elementTint : steel,
                                      duration: clipLength, after: beat(walkUp), in: scene)
            }
            // The skill's BANNER over its caster (Docs/FEEL.md W1.9, the
            // owner's Summoners War frame): its painted icon in a gold frame
            // beside its name, followed through the leap (a plain name hung
            // over the EMPTY mark a closing caster had left, run 220). It
            // replaces the plain name that floated here in pale gold. Not for
            // an ultimate: the cut-in is its name, and the two at once put it
            // on the screen twice.
            if animation != .ultimate {
                floatBanner(name, iconKey: skillArt[actor]?[skillID], over: casterNode)
            }

            // The frame the blade lands, measured from the start of the CLIP
            // rather than of the turn, and held by the queue so the damage
            // event arrives on it. What is left of the clip is repaid to the
            // next turn as recovery.
            let blowAt = Self.contactFraction(of: animation, for: casterNode.spec.assetName)
            let contact = walkUp + animation.fallbackDuration * blowAt
            holdOverride = contact
            castRecovery = animation.fallbackDuration * (1 - blowAt)

            // A ranged strike flies: the element's painted sprite leaves the
            // caster's chest and lands on the victim's on the frame of
            // contact, where the burst below is waiting for it.
            scene.rootNode.removeAction(forKey: "cast_projectile")
            if let targetNode, !casterNode.spec.melee, !casterNode.isBoss, targets.count == 1,
               targetNode.side != casterNode.side,
               animation == .attackBasic || animation == .attackHeavy || animation == .castRelease {
                let flight = min(0.45, max(0.22, beat(contact) * 0.6))
                let victimID = targets[0]
                let tint = UIColor(hex: casterNode.spec.auraHex) ?? .white
                scene.rootNode.runAction(.sequence([
                    .wait(duration: max(0, beat(contact) - flight)),
                    SCNAction.run { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self, let victim = self.unitNodes[victimID] else { return }
                            VFXLibrary.projectile(
                                casterNode.element, from: casterNode.chestWorldPosition, to: victim.chestWorldPosition,
                                in: self.scene, tint: tint, duration: flight, scale: casterNode.spec.height / 1.9
                            )
                        }
                    }
                ]), forKey: "cast_projectile")
            }

            // A skill with no effect of its own lands in its caster's element,
            // and a closing strike draws its slash across the victim.
            let tint = UIColor(hex: casterNode.spec.auraHex) ?? .white
            let effect = vfx == "impact_generic" ? "impact_\(casterNode.element.rawValue)" : vfx
            let slashes = casterNode.spec.melee && targets.count == 1
                && (animation == .attackBasic || animation == .attackHeavy)
            // The burst is a SCENE action, not a `DispatchQueue.asyncAfter`: a
            // hit freezes the scene for up to 150 ms and a wall-clock timer
            // keeps counting through a freeze that the animation it is timed
            // against does not. The key means a second cast cancels the first
            // one's pending burst instead of letting it fire into a field that
            // has moved on, and the position is read when it fires, so an
            // effect can no longer bloom where a victim used to stand.
            scene.rootNode.removeAction(forKey: "cast_impact")
            scene.rootNode.runAction(.sequence([
                .wait(duration: beat(contact)),
                SCNAction.run { [weak self] _ in
                    // SceneKit runs this on its rendering thread; everything
                    // below touches the scene graph, so it hops to main first.
                    DispatchQueue.main.async {
                        guard let self else { return }
                        // Lightning has its own sound; everything else lands on
                        // the hit sound `Juice` picks from the damage that
                        // arrives on this same frame.
                        if vfx == "thunderbolt" || vfx == "thunderclap" || vfx == "keraunos" {
                            AudioLibrary.shared.play(.thunder, volume: vfx == "keraunos" ? 1.0 : 0.7)
                        }
                        let victims = targets.compactMap { self.unitNodes[$0] }
                        // A cast on several victims is drawn ONCE over the
                        // row (`VFXLibrary.spawnArea`): drawn on each of
                        // them, four white sheets 2.4 m apart added up to a
                        // slab over the whole team (run 224, 8-b).
                        if victims.count > 1 {
                            let scale = victims.map { Self.effectScale(for: $0) }.reduce(0, +) / Float(victims.count)
                            VFXLibrary.spawnArea(
                                effect, over: victims.map { $0.chestWorldPosition }, in: self.scene,
                                tint: tint, scale: scale
                            )
                            // A heavy blow on the row breaks the ground once,
                            // under its middle.
                            if animation == .attackHeavy, casterNode.spec.melee {
                                let feet = victims.map { $0.position }
                                let count = Float(feet.count)
                                let middle = SCNVector3(
                                    feet.reduce(Float(0)) { $0 + $1.x } / count, 0,
                                    feet.reduce(Float(0)) { $0 + $1.z } / count
                                )
                                VFXLibrary.spawn("shockwave", at: middle, in: self.scene, tint: tint, scale: scale,
                                                 reach: .row(span: 0))
                            }
                            return
                        }
                        for node in victims {
                            let scale = Self.effectScale(for: node)
                            VFXLibrary.spawn(
                                effect, at: node.chestWorldPosition, in: self.scene,
                                tint: tint, scale: scale
                            )
                            if slashes {
                                VFXLibrary.spawn(
                                    "slash", at: node.chestWorldPosition, in: self.scene,
                                    tint: tint, scale: scale * (animation == .attackHeavy ? 1.3 : 1.0)
                                )
                            }
                            // A heavy blow breaks the ground under its victim.
                            if animation == .attackHeavy, casterNode.spec.melee {
                                VFXLibrary.spawn("shockwave", at: node.position, in: self.scene, tint: tint,
                                                 scale: scale)
                            }
                        }
                    }
                }
            ]), forKey: "cast_impact")

        case .damage(let source, let target, let amount, let isCritical, let isGlancing, _, let remaining, let hitIndex, let hitCount):
            guard let node = unitNodes[target] else { return 0 }

            // How hard did that land? Lethal beats critical beats the clip.
            let lethal = remaining <= 0
            let weight: HitWeight
            if lethal {
                weight = .lethal
            } else if isCritical {
                weight = .critical
            } else if lastCastClip == .ultimate || lastCastClip == .attackHeavy || lastCastClip == .castRelease {
                weight = .heavy
            } else if isGlancing {
                weight = .light
            } else {
                weight = .normal
            }
            let profile = Juice.profile(for: weight)
            let early = Self.isEarlyHit(hitIndex: hitIndex, hitCount: hitCount)
            // THE FINAL BLOW (W1.7): the kill that leaves its side with no
            // one standing, which ends a wave or the fight.
            let standing = unitNodes.values.filter { $0 !== node && $0.side == node.side && !$0.isDefeated }.count
            let finalBlow = Self.endsItsSide(lethal: lethal, othersStanding: standing)
            // THE IMPACT FRAME (W1.3): on a crit or a kill, ONCE a cast,
            // never under Reduce Motion. The final blow owns the cast's frame
            // (W1.7): a crit or a kill earlier in a cast that goes on to end
            // its side leaves the frame for it. The final blow used to punch
            // past the once-a-cast rule, so an area ultimate that crit or
            // killed and then wiped the wave punched twice inside a second
            // (review, 2026-09-24).
            let calm = MotionComfort.isReduced
            let punches: Bool
            if calm || impactFrameSpent {
                punches = false
            } else if finalBlow {
                punches = true
            } else if isCritical || lethal {
                punches = !finalBlowComing(on: node.side, standingAfter: lethal ? standing : standing + 1)
            } else {
                punches = false
            }
            if punches { impactFrameSpent = true }
            let attackerElement = unitNodes[source]?.element ?? lastCasterElement

            // Everything a blow does now happens on ONE frame: the burst and
            // the slash arc (spawned by the cast, timed to this instant), the
            // white flash, the flinch, the shove, the number, the sound, the
            // haptic and the freeze. They used to be spread over more than a
            // second, which is why a hit read as a light show followed by a
            // bookkeeping update. The shove is the part that was missing
            // altogether: a body that never moves is not being hit. The final
            // blow's victim begins to FALL on the blow, so the slow motion
            // after its freeze has the fall to slow.
            if finalBlow {
                node.beginFinalFall()
            } else {
                node.play(.hitReact)
            }
            node.flashHit(strength: punches ? Self.impactBurn : 1)
            node.recoil(strength: Self.recoilStrength(for: weight))
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))

            if isCritical {
                VFXLibrary.spawn("crit", at: node.chestWorldPosition, in: scene, tint: UIColor(hex: "#FFD24F") ?? .yellow)
            }
            // The number (W1.2): CRITICAL or GLANCING as a word over it, a
            // crit in gold to orange, anything else cream edged in the
            // attacker's colour — never the heal's green, whatever the
            // matchup (the arrow over the plate already says that) — and a
            // multi-hit's early hits fainter, its run closed by a gold TOTAL.
            floatHit(amount, on: node, critical: isCritical, glancing: isGlancing,
                     weightScale: profile.numberScale, early: early, rim: attackerElement)
            if let total = hitLedger.record(source: source, target: target, amount: amount,
                                            hitIndex: hitIndex, hitCount: hitCount, lethal: lethal) {
                floatTotal(total, on: node)
            }
            if isGlancing { AudioLibrary.shared.play(.dodge, volume: 0.5) }
            if punches {
                director?.impactFrame()
                // A kill's speed lines, in the striker's colour.
                if lethal {
                    plates.burstSpeedLines(over: node, lift: node.spec.height * 0.55,
                                           tint: UIColor(hex: attackerElement.accentHex) ?? .white)
                }
            }

            // A heavy blow is worth dwelling on. The freeze punctuates the
            // frame of contact itself; this holds the frame just after it, so
            // the shove and the shake are seen finishing before the next
            // number starts. An ordinary hit keeps the fast cadence a
            // multi-hit skill needs, and a glance is not worth a beat at all.
            switch weight {
            case .lethal: holdOverride = 0.55
            case .critical: holdOverride = 0.48
            case .heavy: holdOverride = 0.42
            case .normal, .light: break
            }

            guard finalBlow else {
                return Juice.impact(weight, colour: lastCastColour, share: damageShare(amount, of: target),
                                    early: early, ultimate: lastCastWasUltimate, victim: node,
                                    scene: scene, director: director, speed: speedMultiplier)
            }
            // The final blow: a fifth of a second held with the impact frame,
            // then the slow motion, and only then the next event — the
            // victim's `.defeated`, the wave or the end — so nothing is
            // presented while time runs slow.
            let freeze = Juice.scaledFreeze(Juice.finalBlowFreeze, speed: speedMultiplier)
            Juice.impact(weight, colour: lastCastColour, ultimate: lastCastWasUltimate, freezeFor: freeze,
                         shakes: false, victim: node, scene: scene, director: director, speed: speedMultiplier)
            let slow = beginSlowMotion(on: node, after: freeze)
            holdOverride = Self.afterTheFinalBlow
            return freeze + slow

        case .healed(_, let target, let amount, let remaining):
            guard let node = unitNodes[target] else { return 0 }
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))
            floatText("+\(Int(amount.rounded()))", over: node, color: UIColor(hex: "#7FE8A0")!)
            VFXLibrary.spawn("heal", at: node.position, in: scene, tint: UIColor(hex: "#7FE8A0")!)
            // A drain heals once per hit, so the harp is quieter and skipped
            // at the top speed.
            if speedMultiplier < 3 { AudioLibrary.shared.play(.heal, volume: 0.7) }

        case .shieldAbsorbed(let target, let amount, _):
            guard let node = unitNodes[target] else { return 0 }
            floatText("\(Int(amount.rounded())) blocked", over: node, color: UIColor(hex: "#6BD8F2")!, scale: 0.8)
            if speedMultiplier < 3 { AudioLibrary.shared.play(.statusShield, volume: 0.35) }

        case .statusApplied(_, let target, let kind, let turns):
            guard let node = unitNodes[target] else { return 0 }
            node.applyStatus(kind, turns: turns)
            VFXLibrary.spawn(kind.isBuff ? "buff" : "debuff", at: node.position, in: scene, tint: .white)
            if speedMultiplier < 3 { AudioLibrary.shared.play(.status(kind), volume: 0.8) }
            floatText(kind.displayName, over: node,
                      color: kind.isBuff ? UIColor(hex: "#6BD8F2")! : UIColor(hex: "#F2726B")!, scale: 0.7)

        case .statusResisted(_, let target, _):
            guard let node = unitNodes[target] else { return 0 }
            // In the carved word style of CRITICAL and GLANCING (W1.2); a unit
            // wearing Immunity resisted nothing — it was immune.
            let immune = node.hasStatus(.immunity)
            floatWord(immune ? "IMMUNE" : "RESIST", over: node,
                      colour: UIColor(hex: immune ? Self.immuneHex : Self.resistHex) ?? .white)
            if speedMultiplier < 3 { AudioLibrary.shared.play(.block, volume: 0.6) }

        case .statusExpired(let target, let kind), .statusRemoved(let target, let kind, _):
            unitNodes[target]?.removeStatus(kind)

        case .attackBarChanged(let target, _, let newValue):
            unitNodes[target]?.plate?.setAttackBar(newValue, animated: true)

        case .cooldownStarted:
            break

        case .counterattack(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            // A counter is an attack of its own: its crit, its kill or its
            // final blow may take an impact frame (W1.3) whatever the cast
            // it answered spent.
            impactFrameSpent = false
            floatText("COUNTER", over: node, color: UIColor(hex: "#FFD24F")!, scale: 0.9)
            AudioLibrary.shared.play(.counter)
            node.play(.attackBasic)
            // A counter interrupts whatever the caster was in the middle of,
            // so the follow-through owed by that cast is void; leaving it
            // would add a second of nothing to the next turn.
            castRecovery = 0

        case .extraTurnGranted(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("EXTRA TURN", over: node, color: UIColor(hex: "#FFD24F")!, scale: 0.9)
            AudioLibrary.shared.play(.extraTurn)

        case .passiveTriggered(let actor, let name):
            guard let node = unitNodes[actor] else { return 0 }
            floatText(name, over: node, color: UIColor(hex: "#E8C86A")!, scale: 0.9)
            VFXLibrary.spawn("stormlord_surge", at: node.position, in: scene, tint: UIColor(hex: "#E8C86A")!)

        case .revived(let target, _):
            unitNodes[target]?.revive(healthFraction: 0.3)
            AudioLibrary.shared.play(.revive)

        case .defeated(let target):
            unitNodes[target]?.markDefeated()
            AudioLibrary.shared.play(.death, volume: 0.85)

        case .waveStarted(_, _, let opponents):
            // The fallen wave leaves the field so the marks are free, and
            // the next one comes on from the back.
            for (id, node) in unitNodes where node.side == .opponent && node.isDefeated {
                // Faded as before, but taken off the stage through
                // `VFXLibrary.retire`, never by a removal action: an awakened
                // unit or a boss carries a LOOPING aura on its model, alive
                // as it lies there, and a node removed on the render thread
                // with a particle instance on it is the crash of 2026-09-15
                // (the family run 239's arena crash belongs to).
                node.runAction(.fadeOut(duration: 0.3))
                VFXLibrary.retire(node, after: 0.3, reportsLive: false)
                unitNodes[id] = nil
                skillArt[id] = nil
                plates.removePlate(for: id)
            }
            closeOpenTotals()
            registerMaxHealth(opponents)
            place(combatants: opponents, entering: true)
            AudioLibrary.shared.play(opponents.contains(where: \.isBoss) ? .bossArrival : .waveCall(for: environment.pantheon))
            // Measure the field with the new wave on it now, not at the next
            // drain: in an auto fight the queue never drains between turns,
            // so a boss arriving with the third wave was never measured and
            // the boss framing never came — three runs of frames had the
            // Colossus at the far end of the ordinary 58° shot.
            director?.frameField()
            Juice.haptic(.light)

        case .battleEnded(let result):
            closeOpenTotals()
            director?.returnHome()
            Juice.notify(result.outcome == .victory ? .success : .error)
            // The fanfare is the reckoning's, played once with its ribbon
            // (`BattleView.beginReckoning`); played here as well, victory
            // sounded twice. The fight's music stops under it.
            AudioLibrary.shared.stopMusic(fade: 0.6)
            // The victors pose. The ENEMY's face the camera already; the
            // player's team poses in the triumph instead (W1.7,
            // `celebrate(experience:)`), turned to the lens — posed here it
            // played facing away and was covered a second later, so no one
            // had ever seen a victory clip from the front. An auto-repeat's
            // runs before its last go straight on and do not pose.
            for (_, node) in unitNodes where !node.isDefeated {
                if result.outcome == .defeat && node.side == .opponent {
                    node.play(.victory)
                }
            }
        }
        return 0
    }

    /// The share of its victim's maximum health a blow took (W1.3's freeze
    /// grows with it); 0 for a unit whose maximum is unknown.
    private func damageShare(_ amount: Double, of target: UUID) -> Double {
        guard let maximum = maxHealthByUnit[target], maximum > 0 else { return 0 }
        return amount / maximum
    }

    /// The TOTALs still owed at the end of a turn (a random-target
    /// multi-hit whose victim was missed on the last hit), each on its unit.
    private func closeOpenTotals() {
        for owed in hitLedger.closeAll() {
            guard let node = unitNodes[owed.target], !node.isDefeated else { continue }
            floatTotal(owed.total, on: node)
        }
    }

    /// The engine reports absolute remaining health; the node only knows its
    /// own geometry, so the caller converts. Kept in one place to avoid drift.
    private var maxHealthByUnit: [UUID: Double] = [:]

    func registerMaxHealth(_ combatants: [Combatant]) {
        for combatant in combatants { maxHealthByUnit[combatant.id] = combatant.maxHealth }
    }

    private func healthFraction(remaining: Double, node: UnitNode) -> Double {
        guard let maxHealth = maxHealthByUnit[node.combatantID], maxHealth > 0 else { return 1 }
        return remaining / maxHealth
    }

    private func highlight(_ actorID: UUID) {
        actingID = actorID
        for (id, node) in unitNodes { node.setHighlighted(id == actorID) }
    }

    // MARK: - The reticle (Docs/FEEL.md W1.9)

    /// A tap on an enemy while the player's unit waits for its command stamps
    /// a reticle on it in the acting unit's element — the colour its skill
    /// squares are lit in — from `BattleSceneView.Coordinator.handleTap`, the
    /// main thread, with the view that was tapped. Not on the fallen, not on
    /// the player's own, and not while a turn plays (the queue is running:
    /// the tap commits nothing then).
    func stampReticle(on unit: UnitNode, in view: SCNView) {
        guard unit.side == .opponent, !unit.isDefeated, !isPlaying,
              let actor = actingID.flatMap({ unitNodes[$0] }), actor.side == .player, !actor.isDefeated else { return }
        let projected = view.projectPoint(unit.chestWorldPosition)
        guard projected.z > 0, projected.z < 1 else { return }
        let height = view.bounds.height
        guard height > 2 else { return }
        // The overlay's origin is at the bottom.
        let point = CGPoint(x: CGFloat(projected.x), y: height - CGFloat(projected.y))
        plates.stampReticle(at: point, tint: UIColor(hex: actor.element.accentHex) ?? .white)
    }

    // MARK: - Unit plates

    /// The plates and the nodes they follow, for the render thread.
    private func refreshPlateTargets() {
        let triples: [(UnitPlate, UnitNode, SCNNode?)] = unitNodes.values.compactMap { node in
            guard let plate = node.plate else { return nil }
            return (plate, node, Self.headJoint(of: node))
        }
        let bosses = unitNodes.values.filter { $0.isBoss }
        let homes = homeMarks
        plateLock.lock()
        plateTargets = triples
        plateBosses = bosses
        plateHomes = homes
        plateLock.unlock()
    }

    /// The joint a plate reads a falling body's height off: the top of the
    /// skull (`head_end` on a Meshy rig), else the head (Zeus's rig names
    /// only `Head`), else nil — an unrigged mesh keeps its standing height.
    /// Case blind, as every bone lookup here is.
    private static func headJoint(of node: UnitNode) -> SCNNode? {
        var skullTop: SCNNode?
        var head: SCNNode?
        node.enumerateHierarchy { child, stop in
            guard let name = child.name?.lowercased() else { return }
            if name == "head_end" || name == "headtop_end" {
                skullTop = child
                stop.pointee = true
            } else if head == nil, name == "head" {
                head = child
            }
        }
        return skullTop ?? head
    }

    /// The attack bars after a turn resolves, from the engine's truth: the
    /// actor back at zero, everyone else advanced toward their turn. The
    /// view model calls it as playback settles.
    func syncPlates(combatants: [Combatant]) {
        for combatant in combatants {
            unitNodes[combatant.id]?.plate?.setAttackBar(combatant.attackBar, animated: true)
        }
    }

    /// Stands every plate over its unit's head for the frame about to be
    /// drawn, clear of its neighbours. Called by the view's renderer
    /// delegate on the render thread, with the camera where it will be for
    /// that frame, so a plate follows a dash and a zoom without a frame of
    /// lag.
    ///
    /// `projectPoint` answers in the view's points with the origin at the
    /// top; the overlay's origin is at the bottom, so y is flipped by the
    /// overlay's height.
    func layoutPlates(in renderer: SCNSceneRenderer) {
        if let view = renderer as? SCNView {
            let size = view.bounds.size
            if size.width > 0, size.height > 0, plates.size != size { plates.size = size }
        }
        // Everything the main thread asked of the plates since the last
        // frame, applied here on the renderer's thread, then the positions.
        plates.drainPending()
        let height = plates.size.height
        guard height > 2 else { return }
        // A kill's speed lines, where its unit stands in this frame.
        plates.placeBursts(in: renderer)
        plateLock.lock()
        let targets = plateTargets
        let bosses = plateBosses
        let homes = plateHomes
        plateLock.unlock()
        let now = CACurrentMediaTime()
        let step = CGFloat(min(0.1, max(0, now - lastPlateLayout)))
        lastPlateLayout = now
        // The HUD's top strip, as a ceiling a plate's top keeps under
        // (2026-09-24, review): with the far row's feet 37% down
        // (`CameraDirector.farFeetLine`) a left-hand enemy's status tiles
        // reached the stage and wave chips, and a 2.6 m enemy's badge sat
        // on them. The same corners `layoutFloats` keeps its words under:
        // the chips over the row's length, and the boss bar, while a boss
        // stands, across the whole width. The overlay's origin is at the
        // bottom, so a ceiling is a height.
        let safe = plates.safeArea
        let bossStands = bosses.contains { !$0.isDefeated }
        let hudTop = height - safe.top - Self.hudPadding
        let chipsRoof = hudTop - (bossStands ? Self.hudChipsFootUnderBar : Self.hudChipsFoot)
        let barRoof = bossStands ? hudTop - Self.hudBarFoot : height
        let chipsReach = safe.left + Self.hudPadding + Self.hudChipsLength

        // Each plate where it would stand on its own.
        var standing: [(plate: UnitPlate, id: UUID, point: CGPoint, roof: CGFloat, blocks: Bool, visiting: Bool)] = []
        for (plate, node, headJoint) in targets {
            // Over the head: the top of the figure, projected, and the
            // track's bottom edge a little above it (the genre's place;
            // under the feet before 2026-09-15).
            let feet = node.worldPosition
            let tall = node.spec.height
            // The top of the figure AS IT IS NOW, read off the head joint.
            // Standing, breathing, swinging or leaping, the head stays within
            // a quarter of the height of where a standing figure's is, and
            // the plate does not move with it; a body going DOWN — a fall, a
            // knock-down, a death before the plate has faded — takes the
            // plate down with it past that, eased, so no bar is left hanging
            // in the air where a head stood (run 217's judge read a plate
            // over the Colossus's chest as exactly that).
            let key = node.combatantID
            var drop: Float = 0
            if let headJoint {
                let skull = headJoint.presentation.worldPosition.y + tall * 0.04
                drop = max(0, feet.y + tall - skull - tall * 0.25)
            }
            let easedDrop = (plateDrops[key] ?? drop) * 0.7 + drop * 0.3
            plateDrops[key] = easedDrop
            let top = SCNVector3(feet.x, feet.y + tall - easedDrop, feet.z)
            // A unit standing INSIDE a boss's body — a melee dash that ends a
            // stride from the boss's centre, which is inside the Colossus's
            // fist — is hidden by it, and its plate hung alone over the
            // boss's chest where it read as the boss's own (run 217). It is
            // shown again the moment the unit walks back out.
            let insideBoss = bosses.contains { boss in
                guard !boss.isDefeated else { return false }
                let centre = boss.worldPosition
                let reach = boss.spec.height * 0.3
                let dx = feet.x - centre.x, dz = feet.z - centre.z
                return dx * dx + dz * dz < reach * reach
            }
            let projected = renderer.projectPoint(top)
            let onScreen = projected.z > 0 && projected.z < 1 && !insideBoss
            plate.isHidden = !onScreen
            var point = CGPoint(
                x: CGFloat(projected.x),
                y: height - CGFloat(projected.y) + UnitPlate.riseAboveHead + UnitPlate.trackHeight / 2
            )
            // Held under the chips and the boss bar: the plate's top — its
            // badge, or its status tiles while any are up — no higher than
            // the ceiling over its left end, before the declutter, so the
            // neighbours stagger round where it really stands.
            let plateLeft = point.x + min(-UnitPlate.reachLeft, plate.tilesLeft)
            let roof = plateLeft < chipsReach ? min(chipsRoof, barRoof) : barRoof
            point.y = min(point.y, roof - plate.reachAbove)
            // Off its MARK (`homeMarks`) — leaping at a victim, standing over
            // it through the hits, walking back, or a later wave walking on
            // — a unit's plate is a VISITOR to the declutter below.
            var visiting = false
            if let mark = homes[key] {
                let dx = feet.x - mark.x
                let dz = feet.z - mark.z
                visiting = dx * dx + dz * dz > Self.offMark * Self.offMark
            }
            // A plate on its way out (its unit has fallen) or off the frame
            // stands in nobody's way.
            standing.append((plate, key, point, roof, onScreen && !node.isDefeated, visiting))
        }

        // The declutter (run 217's arena: four challengers abreast put each
        // plate's level badge on its neighbour's health bar, so the row read
        // as one broken bar). Left to right, a plate whose box meets one
        // already placed moves the least distance that clears every placed
        // plate — up a plate's height over its neighbour, or a little down
        // under a neighbour that was itself lifted — which staggers a crowded
        // row, the genre's answer. The box is the level badge's left edge to
        // the track's right end — or, for an opponent's, the matchup marker
        // beside it (`UnitPlate.reachRight`) — and the badge's height; a
        // badge grazing the rounded end of the next track (under 3 points)
        // is left alone, or every row of five abreast would zigzag. Nothing
        // is lifted past the top of the frame, and the move is eased, so a
        // dash past a neighbour slides its plate rather than popping it.
        //
        // A plate wearing status tiles is TALLER and may be wider: its box
        // runs up to the tiles' top (`reachAbove`) and across the row with
        // its turn chips (`tilesLeft`/`tilesRight`), and a tile row keeps
        // four points clear of anything across and two up and down — lifted
        // clear of the badge alone, a neighbour's badge landed on the row's
        // last chip and read "240" (run 224, 8-c). Without tiles the box is
        // the badge's height, as before.
        //
        // A VISITOR is placed LAST, and drawn only where it is clear (run
        // 234, 8-arena_battle-aoe-a: the green-40 plate of a unit in mid-leap
        // at its victim lay across the purple-26 enemy's track). A dashing
        // unit's plate crosses the field in a fifth of a second, so its clear
        // spot jumped from one side of a row to the other between frames, and
        // the eased lift DREW it partway between the two, over whatever stood
        // there, while `placed` held only where it was going; taken in its
        // turn from the left, it also pushed every plate right of it off its
        // place and let them fall back as it passed. Now every plate whose
        // unit is on its mark is placed first and never moves for a visitor;
        // the visitor finds its spot among them as before, and where its box
        // AS DRAWN would meet a plate drawn before it — mid-ease, or with no
        // clear spot at all — it goes out of sight at once, straight to its
        // spot, and fades back in there when the spot is clear
        // (`UnitPlate.crowdAlpha`). Replayed in Python through 8-aoe-a's
        // field and three hundred random dashes: never drawn over a plate,
        // and out of sight in 4% of the frames of a leap and its landing.
        let spacing: CGFloat = 3
        let deepestDrop: CGFloat = 10
        let headroom = UnitPlate.tallestReach + 4
        let fade = step / Self.visitorFade
        var placed: [(left: CGFloat, right: CGFloat, bottom: CGFloat, top: CGFloat, tiles: Bool)] = []
        // Every plate as it is drawn this frame: what a visitor keeps clear
        // of, and what the floating words keep off (`layoutFloats`).
        var drawn: [PlateBox] = []
        let order = standing.sorted { first, second in
            if first.visiting != second.visiting { return !first.visiting }
            return first.point.x < second.point.x
        }
        for entry in order {
            let key = entry.id
            let x = entry.point.x
            let baseY = entry.point.y
            let tiles = entry.plate.wearsTiles
            let left = x + min(-UnitPlate.reachLeft, entry.plate.tilesLeft)
            let right = x + max(entry.plate.reachRight, entry.plate.tilesRight)
            let reachUp = entry.plate.reachAbove
            let reachDown = UnitPlate.reachBelow
            var lift: CGFloat = 0
            if entry.blocks {
                let beside = placed.filter { other in
                    let across = min(right, other.right) - max(left, other.left)
                    return across > (tiles || other.tiles ? -4 : 3)
                }
                let isClear: (CGFloat) -> Bool = { y in
                    !beside.contains { other in
                        let upright = min(y + reachUp, other.top) - max(y - reachDown, other.bottom)
                        return upright > (tiles || other.tiles ? -2 : 0)
                    }
                }
                if !isClear(baseY) {
                    var candidates: [CGFloat] = []
                    for other in beside {
                        candidates.append(other.top + spacing + reachDown - baseY)
                        candidates.append(other.bottom - spacing - reachUp - baseY)
                    }
                    // The nearest spot that clears everything placed and
                    // stays on the frame; failing that the nearest that
                    // clears and stays on it, however far down (a far row's
                    // plates are near the top edge, and a lift there put a
                    // plate off it); failing that the nearest that clears;
                    // failing that, where it stands.
                    let clearing = candidates
                        .filter { isClear(baseY + $0) }
                        .sorted { abs($0) < abs($1) }
                    // Nor lifted back up into the HUD's top strip.
                    let onFrame = clearing.filter { candidate in
                        let lifted: CGFloat = baseY + candidate
                        return lifted + headroom < height && lifted + reachUp <= entry.roof
                    }
                    let fitting = onFrame.filter { $0 >= -deepestDrop }
                    lift = fitting.first ?? onFrame.first ?? clearing.first ?? 0
                }
                placed.append((left: left, right: right, bottom: baseY + lift - reachDown,
                               top: baseY + lift + reachUp, tiles: tiles))
            }
            let eased = (plateLifts[key] ?? lift) * 0.65 + lift * 0.35
            var shown = abs(eased - lift) < 0.25 ? lift : eased
            // A plate not wholly shown — hidden, or fading back in — goes
            // straight to its spot: eased, it lagged a moving spot, met a
            // plate and went out again, a flicker at a seventh.
            let crowd = entry.plate.crowdAlpha
            if crowd < 1 { shown = lift }
            var clear = true
            if entry.visiting, entry.blocks {
                // The declutter's own allowances: a graze is not a meeting.
                let meets: (CGFloat) -> Bool = { lifted in
                    let foot: CGFloat = baseY + lifted - reachDown
                    let crown: CGFloat = baseY + lifted + reachUp
                    return drawn.contains { other in
                        let loose = tiles || other.tiles
                        let acrossAllowed: CGFloat = loose ? -4 : 3
                        let uprightAllowed: CGFloat = loose ? -2 : 0
                        let across = min(right, other.right) - max(left, other.left)
                        let upright = min(crown, other.top) - max(foot, other.bottom)
                        return across > acrossAllowed && upright > uprightAllowed
                    }
                }
                // Never drawn over a plate: where the eased step would meet
                // one, the visitor is out of sight at once and at its spot,
                // and it fades back in there once the spot is clear.
                if meets(shown) {
                    clear = false
                    shown = lift
                }
            }
            plateLifts[key] = shown
            entry.plate.position = CGPoint(x: x, y: baseY + shown)
            let bottom = baseY + shown - reachDown
            let top = baseY + shown + reachUp
            entry.plate.crowdAlpha = clear ? min(1, crowd + fade) : 0
            if !entry.plate.isHidden, entry.plate.parent != nil,
               entry.plate.alpha * entry.plate.crowdAlpha > 0.05 {
                drawn.append((id: key, left: left, right: right, bottom: bottom, top: top, tiles: tiles))
            }
        }
        // The floating words and numbers, over the plates just placed and
        // off every one of them.
        layoutFloats(in: renderer, bossStands: bossStands, plateBoxes: drawn)
        // Forget the plates that have left (a fallen wave's), now and then.
        if plateLifts.count > standing.count + 8 {
            let live = Set(standing.map { $0.id })
            plateLifts = plateLifts.filter { live.contains($0.key) }
            plateDrops = plateDrops.filter { live.contains($0.key) }
        }
    }

    /// The genre's arrows. With one of the player's units up, every enemy
    /// wears the matchup of that unit's element against its own — green up
    /// for advantage, yellow for even, red down for disadvantage — so who to
    /// hit is read off the field rather than worked out; on an enemy's turn
    /// they come off. The owner: "I like the way summoners war shows
    /// element advantage using red, yellow, green arrows on who to attack."
    ///
    /// Not on the fallen — a dead Colossus kept its yellow disc on its face
    /// as it sank (run 220) — and not on a boss at all: its 3D badge landed
    /// on its body, so a boss's arrow goes to the HUD's boss bar beside its
    /// name instead, where the genre shows it (`onBossMatchups`).
    private func showMatchups(for actorID: UUID) {
        guard let actor = unitNodes[actorID] else { return }
        var bossMatchups: [UUID: Element.Matchup] = [:]
        for node in unitNodes.values where node.side == .opponent {
            let matchup = actor.side == .player ? actor.element.matchup(against: node.element) : nil
            if node.isBoss {
                if let matchup, !node.isDefeated { bossMatchups[node.combatantID] = matchup }
                node.setMatchup(nil)
            } else {
                node.setMatchup(node.isDefeated ? nil : matchup)
            }
        }
        onBossMatchups?(bossMatchups)
    }

    /// Told on every turn's start with the acting player unit's matchup
    /// against each living boss — empty on an enemy's turn — for the boss
    /// bar's arrow. Main thread (`present` runs there). The view sets and
    /// clears it; it holds nothing of the view model's, so no cycle.
    var onBossMatchups: (([UUID: Element.Matchup]) -> Void)?

    // MARK: The first frames (2026-09-24)
    //
    // Run 243 photographed the fight's first moment as a white frame under
    // the HUD: the main thread builds the stage (about five seconds in CI)
    // and the first frames then compile their shaders (about four more),
    // and until a frame of the built stage is drawn the view shows no stage
    // at all. The battle view keeps a dark veil over the scene until the
    // renderer has drawn a few frames of it, and this is what tells it.

    /// Called once, on the main thread, when the first build's stage has
    /// been drawn (`framesBeforeShown` frames after the build). The view
    /// sets it; an auto-repeat's later builds find it spent.
    var onStageShown: (() -> Void)?
    /// Frames the renderer draws after a build before the veil lifts: the
    /// first one can still be compiling what it draws.
    static let framesBeforeShown = 3
    private let firstFramesLock = NSLock()
    /// Frames still to draw before `onStageShown`; nil when not waiting.
    private var framesToShow: Int?

    /// The renderer's thread, after every frame (`BattleSceneView`).
    func frameDrawn() {
        firstFramesLock.lock()
        guard let left = framesToShow else {
            firstFramesLock.unlock()
            return
        }
        let remaining = left - 1
        framesToShow = remaining > 0 ? remaining : nil
        firstFramesLock.unlock()
        guard remaining <= 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let told = self.onStageShown else { return }
            self.onStageShown = nil
            told()
        }
    }

    private func awaitFirstFrames() {
        firstFramesLock.lock()
        framesToShow = Self.framesBeforeShown
        firstFramesLock.unlock()
    }

    /// The field's chrome — the plates and the floating words — faded out
    /// while the reckoning is up, and back (run 220: three plates showed
    /// through the result's scrim).
    func setPlatesHidden(_ hidden: Bool) {
        plates.setFieldHidden(hidden)
    }

    /// Every unit that dashed walks back to its mark. Called as a turn begins
    /// and when the queue drains, so nobody is left standing in the enemy line.
    private func returnEveryoneHome() {
        for node in unitNodes.values { node.returnHome(duration: beat(0.30)) }
    }

    // MARK: - The final blow's slow motion (Docs/FEEL.md W1.7)
    //
    // When a blow ends a wave or the fight: a fifth of a second held with the
    // impact frame (`Juice.finalBlowFreeze`), then time at 0.3 for 0.6 s while
    // the camera eases toward the victim along the home line of sight (the
    // floor never turns: `CameraDirector.easeToward`), then back to the
    // player's speed with a low whoomp. *Juice it or lose it* says to dwell on
    // a kill, and the genre's last blow of a stage is its slowest moment.
    //
    // The slow motion is `timeScale`, tweened by a main-thread tick and
    // multiplied into the player's speed (`pace`): every clip already running
    // follows it (`UnitNode.playbackSpeed`, which re-times a running clip and
    // its ending), every particle system in the scene is slowed with it
    // (`speedFactor`), and the queue presents nothing while it runs — the
    // blow's hold covers it (`beginSlowMotion` returns its length) — so no
    // event's hold is stretched by a pace that is gone a moment later. At ×2
    // and ×3 the whole beat is shorter by the speed; under Reduce Motion the
    // camera stays where it is and time still slows.

    /// The deepest the slow motion goes, as a share of the player's speed.
    static let slowestShare: Double = 0.3
    /// Its three spans at ×1: into the slow, held, and back.
    static let slowIn: TimeInterval = 0.06
    static let slowHold: TimeInterval = 0.6
    static let slowOut: TimeInterval = 0.25

    /// The slow motion's whole length at the player's speed.
    static func slowMotionSpan(speed: Double) -> TimeInterval {
        let divisor: Double = max(1, speed)
        let span: TimeInterval = slowIn + slowHold + slowOut
        return span / divisor
    }

    /// The share of the player's speed time runs at, `t` seconds after the
    /// freeze released: eased down to `slowestShare`, held, eased back to 1.
    static func slowMotionShare(at t: TimeInterval, speed: Double) -> Double {
        let divisor: Double = max(1, speed)
        let into: TimeInterval = slowIn / divisor
        let held: TimeInterval = into + slowHold / divisor
        let done: TimeInterval = held + slowOut / divisor
        guard t > 0 else { return 1 }
        if t < into {
            let raw: Double = t / into
            let eased: Double = raw * raw * (3 - 2 * raw)
            return 1 - (1 - slowestShare) * eased
        }
        if t < held { return slowestShare }
        if t < done {
            let raw: Double = (t - held) / (done - held)
            let eased: Double = raw * raw * (3 - 2 * raw)
            return slowestShare + (1 - slowestShare) * eased
        }
        return 1
    }

    /// The tick driving it (its target holds this weakly: `FrameTicker`).
    private var slowTicker: FrameTicker?
    /// When the slow began (the freeze's release), on `CACurrentMediaTime`'s
    /// clock, and the player's speed it was scaled for.
    private var slowBegins: CFTimeInterval = 0
    private var slowSpeed: Double = 1
    private var whoomped = false
    /// Every particle system in the scene when it began, with its own speed.
    private var slowedSystems: [(system: SCNParticleSystem, speed: CGFloat)] = []

    /// Starts the slow motion on the final blow's victim, `freeze` seconds
    /// from now (the freeze's release), and returns how long it lasts.
    private func beginSlowMotion(on victim: UnitNode, after freeze: TimeInterval) -> TimeInterval {
        endSlowMotion()
        slowSpeed = speedMultiplier
        slowBegins = CACurrentMediaTime() + freeze
        whoomped = false
        var systems: [(system: SCNParticleSystem, speed: CGFloat)] = []
        scene.rootNode.enumerateHierarchy { node, _ in
            for system in node.particleSystems ?? [] {
                systems.append((system: system, speed: system.speedFactor))
            }
        }
        slowedSystems = systems
        slowTicker = FrameTicker { [weak self] in
            self?.stepSlowMotion() ?? false
        }
        let span = Self.slowMotionSpan(speed: slowSpeed)
        // The camera eases in through the slow and back out as time returns;
        // its action waits out the freeze with the scene.
        if !MotionComfort.isReduced {
            let divisor: Double = max(1, slowSpeed)
            director?.easeToward(victim, over: (Self.slowIn + Self.slowHold) / divisor, back: Self.slowOut / divisor)
        }
        return span
    }

    /// One frame of the slow motion; false once it is over.
    private func stepSlowMotion() -> Bool {
        let t: TimeInterval = CACurrentMediaTime() - slowBegins
        let divisor: Double = max(1, slowSpeed)
        if !whoomped, t >= (Self.slowIn + Self.slowHold) / divisor {
            // Time comes back with a low whoomp.
            whoomped = true
            AudioLibrary.shared.play(.whoosh, volume: 0.9)
        }
        guard t < Self.slowMotionSpan(speed: slowSpeed) else {
            endSlowMotion()
            return false
        }
        let share = Self.slowMotionShare(at: t, speed: slowSpeed)
        if abs(share - timeScale) > 0.0005 { timeScale = share }
        let factor = CGFloat(share)
        for entry in slowedSystems { entry.system.speedFactor = entry.speed * factor }
        return true
    }

    /// Ends the slow motion where it stands: the pace back to the player's,
    /// every particle system to its own speed, the tick stopped. Called as
    /// it finishes, by a skip, and by every new run.
    private func endSlowMotion() {
        slowTicker?.stop()
        slowTicker = nil
        for entry in slowedSystems { entry.system.speedFactor = entry.speed }
        slowedSystems = []
        if timeScale != 1 { timeScale = 1 }
    }

    // MARK: - Floating text

    /// The size of a floating number or word at weight 1, and its floor and
    /// cap in points. The cap is the run-220 crit: a plane in the scene grew
    /// with the skill camera's push-in to 75 points and ran off the top of
    /// the frame. On the overlay a size is a size — a crit at weight 1.4 is
    /// 31 points, a killing blow stops at 32 — and the pop's overshoot is
    /// a twelfth over it for 70 ms.
    private static let floatBase: CGFloat = 22
    private static let floatFloor: CGFloat = 14
    private static let floatCap: CGFloat = 32

    /// The HUD's corners as `BattleView` lays them out (read there, never
    /// set from here): the top inside the safe area with 8 points of
    /// padding at the sides; the gear, the speed and auto three 42-point
    /// squares 16 apart at the bottom left (`controls`, `squareControl`); the
    /// skills three 65-point squares 13 apart at the bottom right
    /// (`skillRow`, `SkillButton`), a picked one 6% larger, with Skip (42
    /// tall) in their place while a turn plays. At the top, 4 points down:
    /// the stage and wave chips (`hudChip`, 30 tall), their row about 250
    /// points long, and over them while a boss stands its bar — its name on
    /// a 30-point chip, 4 points, then the channels, 18.5 points with a
    /// raid's barrier row 24 — so the bar ends 62 points down at most and
    /// the chips under it 98. Change one there, change it here.
    ///
    /// The BOTTOM corners stand ON the safe area's edges since 2026-09-24
    /// (Summoners War's place, `BattleView.cornerMargin`), and 16 points off
    /// the glass on a phone with no inset there. `layoutFloats` still adds
    /// `hudPadding` at the corners, so on a Face ID phone a float keeps 14
    /// points from them rather than 6 — the safe side — and on a phone with
    /// no insets may reach 2 points over them, which is inside the float's
    /// own clear edge (its outline and five points of air).
    private static let hudPadding: CGFloat = 8
    /// Plain numbers: as `3 * 36 + 2 * 6` inside `CGSize` (or `CGFloat(…)`)
    /// the literals' types were solved against every numeric overload,
    /// 0.3 s, then 1.4 s wrapped, on CI's type checker (runs 229 and 233).
    private static let hudControls = CGSize(width: 158, height: 42)    // three 42-point controls, two 16-point gaps
    private static let hudSkills = CGSize(width: 223, height: 67)      // three 65-point squares, two 13-point gaps, a picked end one 2 points out
    private static let hudChipsLength: CGFloat = 250
    /// How far down the top strip ends: the chips alone, the boss bar, and
    /// the chips under the bar. `layoutPlates` and `layoutFloats` both keep
    /// under them.
    private static let hudChipsFoot: CGFloat = 34
    private static let hudBarFoot: CGFloat = 62
    private static let hudChipsFootUnderBar: CGFloat = 98
    /// How far a float keeps from the HUD.
    private static let hudClearance: CGFloat = 6
    /// How far a float keeps from its unit's plate and from the float under
    /// it on the same unit. The pictures carry about six points of clear
    /// edge of their own, so the letters stand eight from the plate and
    /// about fifteen from each other.
    private static let floatGap: CGFloat = 2
    /// How far past its own half width a float may be moved sideways off
    /// another unit's plate (`layoutFloats`). Clearing a badge or a track's
    /// end takes twenty-odd points; a float over the middle of a plate would
    /// need sixty, which puts it beside a stranger — that one fades instead.
    private static let floatSlideSpare: CGFloat = 8
    /// The clear edge of a float's picture that may lie over ANOTHER unit's
    /// plate: `FloatingTextRenderer` pads the letters by their outline and
    /// five points more, so four of those points are shadow's tail or air.
    /// Replayed on 8-aoe-a's "RESIST", boxed by Thoth's tile row and the
    /// next plate's badge, the whole picture had no clear place for its
    /// entire second; four points in, it shows from a quarter second.
    private static let floatEdge: CGFloat = 4
    /// Seconds a float takes to fade out when its unit leaves the frame, and
    /// back in when it returns.
    private static let floatFade: CGFloat = 0.15
    /// The render thread's clock for those fades.
    private var lastFloatLayout: TimeInterval = 0

    /// A number or a word off a unit, on the plate overlay (run 220): a
    /// fixed size in points whatever the camera does, drawn OVER every plate
    /// — the 3D planes were under the overlay, so a plate covered "810!" —
    /// Manrope-Bold for a number and Cinzel for a word, each with a dark
    /// edge. `scale` is the weight of the moment: a glance 0.85, a crit 1.4,
    /// a killing blow 1.6 (`Juice.Profile.numberScale`).
    private func floatText(_ text: String, over node: UnitNode, color: UIColor, scale: CGFloat = 1.0, pop: Bool = false) {
        let isNumber = text.contains { $0.isNumber }
        // A word is read, not felt: it stops at 20 points however heavy the
        // moment, and only a number grows to the cap.
        let points = min(isNumber ? Self.floatCap : 20, max(Self.floatFloor, Self.floatBase * scale))
        guard let image = FloatingTextRenderer.image(text: text, color: color, size: points, carved: !isNumber) else { return }
        let tall = node.spec.height
        if node.isBoss {
            // BESIDE THE HEAD (run 221). Off the chest, at 0.6 of its height,
            // a boss's words sat on the brightest thing in the frame — the
            // spot-lit chest — and "RESIST" all but vanished into the
            // Colossus's chin. They stand to the head's left now, on the dark
            // of the set behind it, their trailing edge a stride clear of the
            // headdress, and a newer one lifts the older toward the bar.
            plates.addFloat(image: image, over: node, lift: tall * 0.9, side: -tall * 0.16, align: -1,
                            pop: pop, scatter: 0, rise: 24)
            return
        }
        // OVER THE BODY, the genre's place (run 221): every float pops at the
        // chest and rises toward the plate, and stops under it
        // (`layoutFloats`). Off the head at 0.85 of the height, a 30-point
        // rise carried "1520!" across its own plate's bar. A newer float
        // lifts the unit's older ones by its own height, so a word and a
        // number never share a line. Numbers scatter a little sideways so a
        // multi-hit reads as a burst rather than a column.
        let scatter: CGFloat = pop ? CGFloat.random(in: -14...14) : 0
        plates.addFloat(image: image, over: node, lift: tall * 0.55, pop: pop, scatter: scatter, rise: 30)
    }

    // MARK: - The numbers that read (Docs/FEEL.md W1.2)

    /// A hit's number off its victim: bold Manrope under a small carved word
    /// — CRITICAL in orange-gold over a gold-to-orange number 1.8 times the
    /// size, popping past it and trembling a moment; GLANCING in slate over a
    /// slate one — or, for an ordinary blow, cream edged thinly in the
    /// ATTACKER's element colour. Green is the heal's alone: an advantage hit
    /// takes no colour, the matchup arrow says it. A multi-hit's early hits
    /// are 0.85 of the size at 80% (`multiHitLook`). `weightScale` is the
    /// blow's weight (`Juice.Profile.numberScale`).
    private func floatHit(_ amount: Double, on node: UnitNode, critical: Bool, glancing: Bool,
                          weightScale: CGFloat, early: Bool, rim: Element) {
        let look = Self.multiHitLook(early: early)
        let digits = Self.digits(amount)
        let word: HitWord?
        let ink: FloatInk
        let size: CGFloat
        if critical {
            word = .critical
            ink = .critical
            size = min(Self.critCap, Self.floatBase * Self.critScale * look.scale)
        } else if glancing {
            word = .glancing
            ink = .glancing
            size = max(Self.floatFloor, Self.floatBase * weightScale * look.scale)
        } else {
            word = nil
            ink = .rimmed(UIColor(hex: rim.accentHex) ?? .white)
            size = min(Self.floatCap, max(Self.floatFloor, Self.floatBase * weightScale * look.scale))
        }
        guard let image = FloatingTextRenderer.number(digits, word: word, ink: ink, size: size,
                                                      opacity: look.opacity) else { return }
        placeNumber(image, on: node, punch: critical)
    }

    /// The gold TOTAL after a multi-hit's last hit (W1.2): the run's sum
    /// under the word, a quarter again the size of a hit, popped.
    private func floatTotal(_ total: Double, on node: UnitNode) {
        let size = min(Self.floatCap, Self.floatBase * Self.totalScale)
        guard let image = FloatingTextRenderer.number(Self.digits(total), word: .total, ink: .total,
                                                      size: size, opacity: 1) else { return }
        placeNumber(image, on: node, punch: false)
    }

    /// A number where every number stands: popped at the chest and risen
    /// toward the plate (`floatText` says why), beside the head of a boss.
    /// `punch` is a crit's: a bigger overshoot and a tremble as it lands.
    private func placeNumber(_ image: UIImage, on node: UnitNode, punch: Bool) {
        let tall = node.spec.height
        // A crit's tremble is a shake, and its big spring a lunge at the
        // eye: neither under Reduce Motion, where the camera's shake is off
        // too (it lands as any number does).
        let hard: Bool = punch && !MotionComfort.isReduced
        let overshoot: CGFloat = hard ? Self.critOvershoot : FloatingLabel.standardOvershoot
        let jitter: TimeInterval = hard ? Self.critJitter : 0
        if node.isBoss {
            plates.addFloat(image: image, over: node, lift: tall * 0.9, side: -tall * 0.16, align: -1,
                            pop: true, scatter: 0, rise: 24, overshoot: overshoot, jitter: jitter)
            return
        }
        let scatter = CGFloat.random(in: -14...14)
        plates.addFloat(image: image, over: node, lift: tall * 0.55, pop: true, scatter: scatter, rise: 30,
                        overshoot: overshoot, jitter: jitter)
    }

    /// A word on its own in the carved style of the words over the numbers
    /// (RESIST, IMMUNE; W1.2), a little larger since it stands alone.
    private func floatWord(_ text: String, over node: UnitNode, colour: UIColor) {
        guard let image = FloatingTextRenderer.word(text, colour: colour, size: Self.wordAloneSize) else { return }
        let tall = node.spec.height
        if node.isBoss {
            plates.addFloat(image: image, over: node, lift: tall * 0.9, side: -tall * 0.16, align: -1,
                            pop: false, scatter: 0, rise: 24)
            return
        }
        plates.addFloat(image: image, over: node, lift: tall * 0.55, pop: false, scatter: 0, rise: 30)
    }

    /// The skill's banner over its caster (W1.9): the painted icon its square
    /// wears (`SkillArt`, the kit's own resolution) in a gold frame beside
    /// its name at 20 points, on a dark ribbon. It hangs a little longer than
    /// a number and barely rises: it is read, not felt. The float's clamps
    /// read the picture's own size, so the banner's full width is held
    /// inside the frame and off the HUD like any other float.
    private func floatBanner(_ name: String, iconKey: String?, over node: UnitNode) {
        let key = iconKey ?? SkillArt.elementMark(node.element)
        let painting: UIImage? = SkillArt.hasPainting(key)
            ? BundleArt.thumbnail(SkillArt.imageName(key), maxPixel: 128)
            : nil
        guard let image = FloatingTextRenderer.banner(name, icon: painting, glyph: SkillArt.glyph(key),
                                                      key: key, tint: UIColor(hex: node.element.accentHex) ?? .white)
        else { return }
        let tall = node.spec.height
        if node.isBoss {
            plates.addFloat(image: image, over: node, lift: tall * 0.9, side: -tall * 0.16, align: -1,
                            pop: false, scatter: 0, rise: 12, hold: Self.bannerHold)
            return
        }
        plates.addFloat(image: image, over: node, lift: tall * 0.62, pop: false, scatter: 0, rise: 12,
                        hold: Self.bannerHold)
    }

    /// A hit's figures, whole and ungrouped, as the genre prints them.
    static func digits(_ amount: Double) -> String {
        String(Int(amount.rounded()))
    }

    /// A multi-hit's hit before its last: every hit of a run of two or more
    /// but the final one.
    static func isEarlyHit(hitIndex: Int, hitCount: Int) -> Bool {
        hitCount > 1 && hitIndex < hitCount - 1
    }

    /// How an early hit is drawn against a whole one (W1.2): 0.85 of the
    /// size at 80%. The last hit, and a lone one, are drawn whole.
    static func multiHitLook(early: Bool) -> (scale: CGFloat, opacity: CGFloat) {
        early ? (0.85, 0.8) : (1, 1)
    }

    /// Whether a blow is the FINAL one (W1.7): a kill that leaves its side
    /// with no one else standing, which ends a wave or the fight.
    static func endsItsSide(lethal: Bool, othersStanding: Int) -> Bool {
        lethal && othersStanding == 0
    }

    /// Whether a later blow of the cast ends the side (W1.3, W1.7): as many
    /// of that side's units die later in the cast as will be standing after
    /// this blow, and at least one is.
    static func finalBlowFollows(standingAfter: Int, killedLater: Int) -> Bool {
        standingAfter > 0 && killedLater >= standingAfter
    }

    /// Whether the final blow is still to come in the cast being played:
    /// the kills on `side` in the queue up to the next cast, counter or turn
    /// (each its own impact frame), against the units of the side standing
    /// after this blow. The engine appends a kill's `.defeated` right after
    /// its `.damage`, so a lethal `.damage` read here is a unit that falls.
    private func finalBlowComing(on side: BattleSide, standingAfter: Int) -> Bool {
        guard standingAfter > 0 else { return false }
        var doomed = Set<UUID>()
        for event in queue {
            switch event {
            case .skillCast, .counterattack, .turnBegan, .battleEnded:
                return false
            case .damage(_, let target, _, _, _, _, let remaining, _, _):
                guard remaining <= 0, unitNodes[target]?.side == side else { continue }
                doomed.insert(target)
                if Self.finalBlowFollows(standingAfter: standingAfter, killedLater: doomed.count) { return true }
            default:
                continue
            }
        }
        return false
    }

    /// A crit's number: 1.8 times a hit's, up to 40 points (the genre draws
    /// its crits at 150–200%; the 32-point cap is every other number's).
    static let critScale: CGFloat = 1.8
    static let critCap: CGFloat = 40
    /// A crit pops a quarter past its size, where a hit pops an eighth, and
    /// trembles for 0.15 s as it lands.
    static let critOvershoot: CGFloat = 1.28
    static let critJitter: TimeInterval = 0.15
    /// The TOTAL, a quarter again a hit's size.
    static let totalScale: CGFloat = 1.25
    /// RESIST and IMMUNE, alone: 16 points.
    static let wordAloneSize: CGFloat = 16
    /// How much longer the skill banner hangs than a word.
    static let bannerHold: TimeInterval = 0.45
    /// The two words' colours: a cool silver for a resist, the shield's cyan
    /// for an immunity.
    static let resistHex = "#C9D3DE"
    static let immuneHex = "#8FE3F5"
    /// The impact frame's burn on its victim (`UnitNode.flashHit`): fully
    /// white at 1.4 times the flash's strength, for two frames.
    static let impactBurn: CGFloat = 1.4
    /// What the queue holds after the final blow's slow motion before the
    /// victim's fall is presented and the wave or the fight moves on.
    static let afterTheFinalBlow: TimeInterval = 0.15

    /// Every floating word and number for the frame about to be drawn: over
    /// the unit it came off, popped, risen and faded by its age, stacked on
    /// its unit's other floats and stopped under its plate — or under any
    /// plate in its way — held INSIDE the frame, inside the safe area and
    /// clear of the HUD at every corner, and never drawn on another unit's
    /// plate. Render thread, from `layoutPlates`, after the plates are
    /// placed: `plateBoxes` is every plate as it is drawn this frame.
    private func layoutFloats(in renderer: SCNSceneRenderer, bossStands: Bool, plateBoxes: [PlateBox]) {
        let size = plates.size
        guard size.width > 2, size.height > 2 else { return }
        let now = CACurrentMediaTime()
        let step = CGFloat(min(0.1, max(0, now - lastFloatLayout)))
        lastFloatLayout = now

        // The frame a float is held inside. The view runs under the notch
        // and the home indicator and the HUD does not, so the sides are the
        // safe area and the HUD's padding: a flat eight points from the
        // view's edge put "542 blocked" in the notch's inset (run 221).
        let safe = plates.safeArea
        let pad = Self.hudPadding
        let leftEdge = safe.left + pad
        let rightEdge = size.width - safe.right - pad
        // The overlay's origin is at the bottom: a ceiling is a height.
        let top = size.height - safe.top - pad
        let barFoot: CGFloat = bossStands ? Self.hudBarFoot : 0
        let chipsFoot: CGFloat = bossStands ? Self.hudChipsFootUnderBar : Self.hudChipsFoot
        let chipsReach = leftEdge + Self.hudChipsLength
        // And the floor over the bottom corners, the way the chips make a
        // ceiling at the top: the controls at the left, the skills and Skip
        // at the right.
        let bottom = safe.bottom + pad
        let controlsRight = leftEdge + Self.hudControls.width + Self.hudClearance
        let controlsTop = bottom + Self.hudControls.height + Self.hudClearance
        let skillsLeft = rightEdge - Self.hudSkills.width - Self.hudClearance
        let skillsTop = bottom + Self.hudSkills.height + Self.hudClearance
        // The band of heights a float's centre keeps inside at a place
        // across: under the boss bar and the chips, over the bottom corners'
        // controls and skills — and so, for a float moved sideways off a
        // plate, the band where it lands.
        let band: (CGFloat, CGFloat, CGFloat) -> (low: CGFloat, high: CGFloat) = { x, halfWidth, halfHeight in
            var ceiling = top - barFoot
            if x - halfWidth < chipsReach { ceiling = min(ceiling, top - chipsFoot) }
            var ground = bottom
            if x - halfWidth < controlsRight { ground = max(ground, controlsTop) }
            if x + halfWidth > skillsLeft { ground = max(ground, skillsTop) }
            return (low: ground + halfHeight, high: ceiling - halfHeight)
        }

        var finished: [FloatingLabel] = []
        // What is on the frame, and where each would stand by itself.
        var shown: [(label: FloatingLabel, x: CGFloat, natural: CGFloat, start: CGFloat,
                     halfWidth: CGFloat, halfHeight: CGFloat)] = []
        for label in plates.floats {
            let age = now - label.born
            guard age < label.life else {
                finished.append(label)
                continue
            }
            let projected = renderer.projectPoint(label.anchor)
            let px = CGFloat(projected.x)
            let py = CGFloat(projected.y)
            // OFF THE FRAME, IT FADES WHERE IT STANDS (run 221). A float whose
            // unit had left the frame — the skill camera's zoom leaves most
            // of the field outside it — was pinned eight points inside the
            // nearest edge, so every number off a zoom landed on an edge and
            // one in a corner on the gear. Behind the camera or past any edge
            // it goes out over `floatFade`, and comes back when its unit does.
            let inFrame = projected.z > 0 && projected.z < 1
                && px >= 0 && px <= size.width && py >= 0 && py <= size.height
            if inFrame {
                if label.placed {
                    label.visibility = min(1, label.visibility + step / Self.floatFade)
                } else {
                    // Born on the frame it shows at once; born off it, it
                    // fades in when its unit arrives.
                    label.visibility = label.laidOut ? 0 : 1
                }
            } else {
                label.visibility = label.placed ? max(0, label.visibility - step / Self.floatFade) : 0
            }
            label.laidOut = true
            let scale = label.scale(at: age)
            label.node.setScale(scale)
            label.node.alpha = label.alpha(at: age) * label.visibility * label.crowdAlpha
            label.node.isHidden = label.visibility * label.crowdAlpha < 0.01
            guard inFrame else { continue }
            label.placed = true
            let halfWidth = label.node.size.width / 2 * scale
            let halfHeight = label.node.size.height / 2 * scale
            let start = size.height - py
            shown.append((label: label,
                          x: px + label.scatter + label.align * (halfWidth + 4),
                          natural: start + label.risen(at: age),
                          start: start,
                          halfWidth: halfWidth,
                          halfHeight: halfHeight))
        }

        // PER UNIT, NEWEST AT THE BOTTOM (run 221: "1138!" and "SCALES OF
        // MA'AT" on one line over Anubis's plate). Each float stands at least
        // its own height over the one newer than it on the same unit, and
        // stops under the unit's plate — its rise capped there — unless the
        // floats under it leave it no room, when it goes over the plate
        // instead. Nothing a float does covers its own bar. And it stops
        // under the FIRST plate in its way (run 234): a neighbour's plate
        // lifted over this unit's head caps the rise as its own would.
        // A float whose unit has left the field stands alone.
        var owners: [UUID: [Int]] = [:]
        var strays: [[Int]] = []
        for (index, entry) in shown.enumerated() {
            if let unit = entry.label.unit {
                owners[unit.combatantID, default: []].append(index)
            } else {
                strays.append([index])
            }
        }
        // Where each float stands across, and the band of heights its centre
        // must keep inside there (`band`).
        var across = [CGFloat](repeating: 0, count: shown.count)
        var highest = [CGFloat](repeating: 0, count: shown.count)
        var lowestAllowed = [CGFloat](repeating: 0, count: shown.count)
        for (index, entry) in shown.enumerated() {
            let x = min(rightEdge - entry.halfWidth, max(leftEdge + entry.halfWidth, entry.x))
            let heights = band(x, entry.halfWidth, entry.halfHeight)
            across[index] = x
            highest[index] = heights.high
            lowestAllowed[index] = heights.low
        }

        var targets = [CGFloat](repeating: 0, count: shown.count)
        for members in Array(owners.values) + strays {
            let ordered = members.sorted { shown[$0].label.born > shown[$1].label.born }
            // The plate the unit wears, as it is drawn this frame (tile row
            // and all).
            let owner = ordered.first.flatMap { shown[$0].label.unit?.combatantID }
            let zone = owner.flatMap { id in plateBoxes.first { $0.id == id } }
            var below: CGFloat?
            for index in ordered {
                let entry = shown[index]
                let stacked = below.map { $0 + Self.floatGap + entry.halfHeight }
                var y = max(entry.natural, stacked ?? entry.natural)
                let left = entry.x - entry.halfWidth
                let right = entry.x + entry.halfWidth
                // The lowest foot of a plate across its path that it rose
                // from under: its unit's own, or a neighbour's (across by
                // more than the picture's clear edge).
                var ceiling: CGFloat?
                for box in plateBoxes {
                    let edge: CGFloat = box.id == owner ? 0 : Self.floatEdge
                    guard left + edge < box.right, right - edge > box.left else { continue }
                    let under = box.bottom - Self.floatGap - entry.halfHeight
                    if entry.start <= under + 0.5 { ceiling = min(ceiling ?? under, under) }
                }
                if let ceiling, y > ceiling, (stacked ?? ceiling) <= ceiling {
                    // Risen as far as it may: it stops under the plate.
                    y = ceiling
                } else if let zone, left < zone.right, right > zone.left {
                    let under = zone.bottom - Self.floatGap - entry.halfHeight
                    if y > under, y - entry.halfHeight < zone.top + Self.floatGap {
                        // No room under its own plate: over it.
                        y = zone.top + Self.floatGap + entry.halfHeight
                    }
                }
                targets[index] = y
                below = y + entry.halfHeight
            }
            // A stack that reaches past the HUD moves WHOLE, so the newest
            // stays lowest and none lands on another: clamped float by float,
            // every float over a boss — whose head stands just under the bar —
            // was pinned to the one line under it, a word on its number.
            // Raised off the bottom corners first, then brought under the
            // top, which wins: nothing is drawn under the boss bar.
            let short = ordered.map { lowestAllowed[$0] - targets[$0] }.max() ?? 0
            if short > 0 { for index in ordered { targets[index] += short } }
            let over = ordered.map { targets[$0] - highest[$0] }.max() ?? 0
            if over > 0 { for index in ordered { targets[index] -= over } }
        }

        for (index, entry) in shown.enumerated() {
            let label = entry.label
            // A push slides rather than jumps: a float lifted by a newer one
            // eases up over a tenth of a second. A float's first frame takes
            // its place outright.
            let push = targets[index] - entry.natural
            if label.pushed {
                label.push += (push - label.push) * 0.35
                if abs(push - label.push) < 0.3 { label.push = push }
            } else {
                label.push = push
                label.pushed = true
            }
            let y = min(highest[index], max(lowestAllowed[index], entry.natural + label.push))

            // NEVER ON ANOTHER UNIT'S PLATE (run 234, 8-arena_battle-aoe-a:
            // "RESIST", stopped under its own unit's plate, lay across the
            // next plate's red-26 badge; and the register's "1163", pushed
            // over its own plate by a newer word, covered a dasher's badge).
            // Where its letters (`floatEdge`) meet a plate that is not its
            // unit's, it moves the least distance sideways that clears every
            // plate, no further than its own half width and `floatSlideSpare`
            // — so it still reads as its unit's — and inside the frame and
            // the HUD's band where it lands; the side it is already on wins,
            // so a float between two plates never swaps sides. With no such place it
            // goes out at once where it stands — a fade out would be letters
            // drawn over a badge for a sixth of a second — and fades back in
            // when it has one.
            let x = across[index]
            let owner = label.unit?.combatantID
            let halfWidth = entry.halfWidth
            let halfHeight = entry.halfHeight
            // The letters and their outline: the picture less its clear edge.
            let letterWidth: CGFloat = max(0, halfWidth - Self.floatEdge)
            let letterHeight: CGFloat = max(0, halfHeight - Self.floatEdge)
            let foot: CGFloat = y - letterHeight
            let crown: CGFloat = y + letterHeight
            let abreast = plateBoxes.filter { box in
                box.id != owner && foot < box.top && crown > box.bottom
            }
            let lands: (CGFloat) -> Bool = { spot in
                let leftEnd: CGFloat = spot - letterWidth
                let rightEnd: CGFloat = spot + letterWidth
                return abreast.contains { box in leftEnd < box.right && rightEnd > box.left }
            }
            var slide: CGFloat = 0
            var blocked = false
            if lands(x) {
                let reach = halfWidth + Self.floatSlideSpare
                var candidates: [CGFloat] = []
                for box in abreast {
                    candidates.append(box.left - Self.floatGap - letterWidth - x)
                    candidates.append(box.right + Self.floatGap + letterWidth - x)
                }
                let fits = candidates.filter { dx in
                    let spot: CGFloat = x + dx
                    let heights = band(spot, halfWidth, halfHeight)
                    let near: Bool = abs(dx) <= reach
                    let inside: Bool = spot - halfWidth >= leftEdge && spot + halfWidth <= rightEdge
                    let held: Bool = y >= heights.low && y <= heights.high
                    return near && inside && held && !lands(spot)
                }
                if let best = fits.min(by: { abs($0 - label.slide) < abs($1 - label.slide) }) {
                    slide = best
                } else {
                    slide = label.slide
                    blocked = true
                }
            }
            // Out of a plate's way at once, back into place eased.
            var next = label.slide + (slide - label.slide) * 0.35
            if abs(slide - next) < 0.3 || lands(x + next) { next = slide }
            label.slide = next
            let crowdStep = step / Self.floatFade
            label.crowdAlpha = blocked ? 0 : min(1, label.crowdAlpha + crowdStep)
            let age = now - label.born
            label.node.alpha = label.alpha(at: age) * label.visibility * label.crowdAlpha
            label.node.isHidden = label.visibility * label.crowdAlpha < 0.01
            // A crit's tremble as it lands (W1.2), a couple of points either
            // way round the place the clamps gave it.
            let shake = label.shake(at: age)
            label.node.position = CGPoint(x: x + label.slide + shake.x, y: y + shake.y)
        }
        plates.retireFloats(finished)
    }
}

// MARK: - The end of the fight on the field (Docs/FEEL.md W1.7)

extension BattleSceneController {

    /// The victory beat on the field before the reckoning: the survivors
    /// turned to the lens in their victory clips, the camera on the team,
    /// the EXP bars filling (`celebrate`). `BattleView` holds its reckoning
    /// this long.
    static let triumphDuration: TimeInterval = 2.4

    /// How long the survivors take to turn to the lens, and how long the
    /// camera takes to come in on them.
    static let triumphTurn: TimeInterval = 0.45
    static let triumphFraming: TimeInterval = 0.9
    /// When the EXP bars begin to fill: once the turn has settled.
    static let experienceDelay: TimeInterval = 0.5

    /// The pace the survivors pose at: their own (×1), whatever speed the
    /// fight was watched at (`UnitNode.celebrate`). Under the CI tour's
    /// victory beat (`-tour-victory`, or this file's `-tour-triumph` lab) a
    /// quarter of it, so the 2.0-s pose lasts about eight: a simulator
    /// screenshot lands two to three seconds after it is asked for
    /// (build.yml's relic_awaken note, run 234), and at ×1 the pose was over
    /// before either of the step's frames landed. A still of the slowed clip
    /// is the clip's own picture at that moment — the battle camera has no
    /// motion blur — so the frame judges the pose the player sees.
    static var triumphPosePace: Double {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-tour"), arguments.contains("-tour-victory") || arguments.contains("-tour-triumph") {
            return tourPosePace
        }
        #endif
        return 1
    }
    static let tourPosePace: Double = 0.25

    /// Main thread, once, on a WIN's last run: survivors turn to face the
    /// camera (look(at:), yaw only) and play their own victory clip at ×1
    /// (`triumphPosePace`), whatever the fight's speed was; the
    /// camera frames the team along the home line of sight (the floor never
    /// turns); each plate swaps health for a gold EXP bar that fills from ->
    /// to, with LEVEL UP rising over a unit whose levelsGained > 0. Units
    /// missing from the map just pose.
    func celebrate(experience: [UUID: ExperienceGain]) {
        guard !celebrated else { return }
        celebrated = true
        endSlowMotion()
        let survivors = unitNodes.values.filter { $0.side == .player && !$0.isDefeated }
        guard !survivors.isEmpty else { return }
        // Where each stands when it has walked the last of the way home.
        let team = survivors.map { node in
            (position: homeMarks[node.combatantID] ?? node.position, height: node.spec.height)
        }
        let lens = director?.frameTeam(team, over: Self.triumphFraming) ?? cameraNode.position
        // The plates stand through the beat (the reckoning takes them).
        plates.setFieldHidden(false)
        let posePace = Self.triumphPosePace
        for node in survivors {
            node.setHighlighted(false)
            node.setMatchup(nil)
            node.celebrate(facing: lens, turn: Self.triumphTurn, pace: posePace)
            guard let gain = experience[node.combatantID] else { continue }
            node.plate?.showExperience(from: gain.from, to: gain.to, levels: gain.levelsGained,
                                       after: Self.experienceDelay)
        }
    }

    /// Main thread, on a LOSS: the camera's saturation eases to 0.15 over
    /// the duration (restored when a new run is built).
    func drainColour(duration: TimeInterval) {
        endSlowMotion()
        director?.drainColour(to: Self.drainedSaturation, over: duration)
    }

    /// What a lost field's colour drains to.
    static let drainedSaturation: CGFloat = 0.15

    /// Under the CI tour's `-tour-triumph` (`win`, the default, or `loss`),
    /// the end of a fight is played on the field six seconds in, whatever
    /// the fight is doing, so a run photographs the scene's half of the
    /// beat without winning one: the survivors turned to the lens in their
    /// victory clips with the camera on them, a bar filling on every plate
    /// and one unit levelling — or, for `loss`, the colour draining.
    func startTourTriumph() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-tour"), let flag = arguments.firstIndex(of: "-tour-triumph") else { return }
        let loss = flag + 1 < arguments.count && arguments[flag + 1] == "loss"
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            if loss {
                self.drainColour(duration: 1.2)
                return
            }
            let team = self.unitNodes.values
                .filter { $0.side == .player && !$0.isDefeated }
                .sorted { $0.position.x < $1.position.x }
            var gains: [UUID: ExperienceGain] = [:]
            for (index, node) in team.enumerated() {
                let from: Double = 0.18 + 0.17 * Double(index % 4)
                let levelled = index == 0
                let to: Double = levelled ? 0.32 : min(1, from + 0.38)
                gains[node.combatantID] = ExperienceGain(from: from, to: to, levelsGained: levelled ? 1 : 0)
            }
            print("[TourCue] scene triumph")
            self.celebrate(experience: gains)
        }
        #endif
    }
}

/// The TOTAL a multi-hit earns (Docs/FEEL.md W1.2): each run of hits one
/// source lands on one target is summed as it lands, and the run closes on
/// its last hit (`hitIndex == hitCount - 1`) or on a kill, which ends it
/// early. A run of two hits or more earns its total; a lone hit, a skill of
/// one hit, and a run cut to one by a kill earn none. Keyed by source AND
/// target, so a counter landed in the middle of a run is a run of its own.
/// A random-target skill can miss a victim on its last hit, so a turn's end
/// closes what is still open (`closeAll`).
struct MultiHitLedger {
    private struct HitRunKey: Hashable {
        let source: UUID
        let target: UUID
    }

    private var runs: [HitRunKey: (sum: Double, hits: Int)] = [:]

    /// Records one hit; the total to show after it, when it closes a run of
    /// two or more.
    mutating func record(source: UUID, target: UUID, amount: Double, hitIndex: Int, hitCount: Int,
                         lethal: Bool) -> Double? {
        guard hitCount > 1 else { return nil }
        let key = HitRunKey(source: source, target: target)
        let before = runs[key] ?? (sum: 0, hits: 0)
        let run = (sum: before.sum + amount, hits: before.hits + 1)
        let closes: Bool = hitIndex >= hitCount - 1 || lethal
        guard closes else {
            runs[key] = run
            return nil
        }
        runs[key] = nil
        return run.hits >= 2 ? run.sum : nil
    }

    /// Closes every run still open: the totals owed, by target.
    mutating func closeAll() -> [(target: UUID, total: Double)] {
        var owed: [(target: UUID, total: Double)] = []
        for (key, run) in runs where run.hits >= 2 {
            owed.append((target: key.target, total: run.sum))
        }
        runs.removeAll()
        return owed
    }

    /// How many runs are open.
    var openRuns: Int { runs.count }
}

/// Renders damage numbers and words to a picture for the plate overlay.
///
/// SCNText produces real geometry, which is expensive and hard to read at small
/// sizes. A rasterised label with a dark edge stays legible against any
/// background and costs one picture per string, which is cached. The game's
/// own two faces since run 220 (grey SF Rounded before): Manrope-Bold for a
/// number, Cinzel for a word — the HUD's faces — each with a dark OUTER edge
/// drawn as a stroke pass under the fill, so the edge never eats into the
/// letters as a fill-and-stroke pass does, and a soft shadow under both.
enum FloatingTextRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(text: String, color: UIColor, size: CGFloat, carved: Bool) -> UIImage? {
        let key = "\(text)|\(color.hashValue)|\(Int(size * 2))|\(carved)"
        if let cached = cache[key] { return cached }

        let face = carved ? Theme.carvedFace : Theme.numberFace
        let font = UIFont(name: face, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: carved ? .heavy : .bold)
        // The edge: about a sixteenth of the size outside the letters (1.4
        // points on a 22-point number, 2 on a crit). A stroke is centred on
        // the outline, so it is drawn twice as wide and the fill covers the
        // inner half. A WORD's edge is a ninth, two points at least, over a
        // darker, wider shadow: Cinzel's thin strokes in pale gold on the
        // pale Olympus marble read at about 1.2 : 1 with the number's edge
        // ("BULL RUSH", run 224's 29-a; "RESIST" on the Colossus's chin,
        // run 221).
        let edge: CGFloat = carved ? max(2.0, size / 9) : max(1.2, size / 16)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(carved ? 0.9 : 0.7)
        shadow.shadowBlurRadius = carved ? 4.5 : 3
        shadow.shadowOffset = CGSize(width: 0, height: 1.5)
        let outline = NSAttributedString(string: text, attributes: [
            .font: font,
            .strokeColor: UIColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.95),
            .strokeWidth: 2 * edge / size * 100,
            .shadow: shadow,
        ])
        let fill = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let measured = fill.size()
        guard measured.width > 0, measured.height > 0 else { return nil }

        let pad = edge + 5
        let padded = CGSize(width: ceil(measured.width + 2 * pad), height: ceil(measured.height + 2 * pad))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: padded, format: format).image { context in
            context.cgContext.setLineJoin(.round)
            let origin = CGPoint(x: pad, y: pad)
            outline.draw(at: origin)
            fill.draw(at: origin)
        }

        // Bound the cache: strings are mostly numbers and repeat heavily, but a
        // long battle should not grow it without limit.
        remember(image, as: key)
        return image
    }

    private static func remember(_ image: UIImage, as key: String) {
        if cache.count > 400 { cache.removeAll() }
        cache[key] = image
    }

    // MARK: - The numbers that read (Docs/FEEL.md W1.2)

    /// The small carved word over a number: 13 points, over the 11-point
    /// floor, tracked out as an inscription is.
    static let wordSize: CGFloat = 13
    private static let wordTracking: CGFloat = 1.3

    /// A hit's number with its word over it (`HitWord`), in its ink
    /// (`FloatInk`): Manrope-Bold for the figures, Cinzel for the word, each
    /// with the dark OUTER edge every float carries and the same clear edge
    /// round the whole picture (the letters' edge and five points), which
    /// `BattleSceneController.floatEdge` counts on. `opacity` is baked in (a
    /// multi-hit's early hits are drawn at 80%), composited once, so the
    /// outline does not show through the fill.
    static func number(_ digits: String, word: HitWord?, ink: FloatInk, size: CGFloat, opacity: CGFloat) -> UIImage? {
        let key = "n|\(digits)|\(word?.text ?? "")|\(ink.key)|\(Int(size * 2))|\(Int(opacity * 100))"
        if let cached = cache[key] { return cached }
        let font = UIFont(name: Theme.numberFace, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
        let edge: CGFloat = max(1.2, size / 16)
        let image = lettering(digits, font: font, edge: edge, tracking: 0, ink: ink, word: word, opacity: opacity)
        if let image { remember(image, as: key) }
        return image
    }

    /// A carved word in a number's ink, for a moment the word itself is:
    /// LEVEL UP over a plate (W1.7).
    static func flourish(_ text: String, ink: FloatInk, size: CGFloat) -> UIImage? {
        let key = "f|\(text)|\(ink.key)|\(Int(size * 2))"
        if let cached = cache[key] { return cached }
        let font = UIFont(name: Theme.carvedFace, size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        let edge: CGFloat = max(2.0, size / 9)
        let image = lettering(text, font: font, edge: edge, tracking: 1.1, ink: ink, word: nil, opacity: 1)
        if let image { remember(image, as: key) }
        return image
    }

    /// A word alone in the style of the words over the numbers: RESIST,
    /// IMMUNE (W1.2).
    static func word(_ text: String, colour: UIColor, size: CGFloat) -> UIImage? {
        let key = "w|\(text)|\(rgbaKey(colour))|\(Int(size * 2))"
        if let cached = cache[key] { return cached }
        let font = UIFont(name: Theme.carvedFace, size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        let edge: CGFloat = max(2.0, size / 9)
        let image = lettering(text, font: font, edge: edge, tracking: wordTracking, ink: .solid(colour), word: nil, opacity: 1)
        if let image { remember(image, as: key) }
        return image
    }

    /// The dark edge's colour, and the shadow under the letters.
    private static let edgeColour = UIColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.95)

    private static func letterShadow(carved: Bool) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(carved ? 0.9 : 0.7)
        shadow.shadowBlurRadius = carved ? 4.5 : 3
        shadow.shadowOffset = CGSize(width: 0, height: 1.5)
        return shadow
    }

    /// One line of letters and, over it, its word: measured, then drawn in
    /// passes — the dark edge with its shadow, the ink's own rim if it has
    /// one, then the fill, a gradient through a transparency layer (the
    /// letters in white, the gradient laid over them `sourceIn`).
    private static func lettering(_ text: String, font: UIFont, edge: CGFloat, tracking: CGFloat, ink: FloatInk,
                                  word: HitWord?, opacity: CGFloat) -> UIImage? {
        let size = font.pointSize
        let carved = font.fontName == Theme.carvedFace
        let fill = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor.white, .kern: tracking,
        ])
        let measured = fill.size()
        guard measured.width > 0, measured.height > 0 else { return nil }
        let outline = NSAttributedString(string: text, attributes: [
            .font: font, .kern: tracking,
            .strokeColor: edgeColour,
            .strokeWidth: 2 * edge / size * 100,
            .shadow: letterShadow(carved: carved),
        ])

        // The word over it: Cinzel at `wordSize`, its own edge.
        let wordFont = UIFont(name: Theme.carvedFace, size: wordSize) ?? UIFont.systemFont(ofSize: wordSize, weight: .heavy)
        let wordEdge: CGFloat = max(2.0, wordSize / 9)
        var wordFill: NSAttributedString?
        var wordOutline: NSAttributedString?
        var wordMeasured = CGSize.zero
        if let word {
            let colour = UIColor(hex: word.colourHex) ?? .white
            let lettered = NSAttributedString(string: word.text, attributes: [
                .font: wordFont, .foregroundColor: colour, .kern: wordTracking,
            ])
            wordFill = lettered
            wordOutline = NSAttributedString(string: word.text, attributes: [
                .font: wordFont, .kern: wordTracking,
                .strokeColor: edgeColour,
                .strokeWidth: 2 * wordEdge / wordSize * 100,
                .shadow: letterShadow(carved: true),
            ])
            wordMeasured = lettered.size()
        }
        // The word sits a fifth into the figures' ascent, so the two read as
        // one label rather than two lines.
        let overlap: CGFloat = word == nil ? 0 : wordMeasured.height * 0.22
        let pad: CGFloat = max(edge, word == nil ? 0 : wordEdge) + 5
        let wordBlock: CGFloat = word == nil ? 0 : wordMeasured.height - overlap
        let width: CGFloat = ceil(max(measured.width, wordMeasured.width) + 2 * pad)
        let height: CGFloat = ceil(measured.height + wordBlock + 2 * pad)
        let wordOrigin = CGPoint(x: (width - wordMeasured.width) / 2, y: pad)
        let origin = CGPoint(x: (width - measured.width) / 2, y: pad + wordBlock)
        let gradient: UIImage? = ink.gradient.map { stops in gradientImage(stops, size: measured) }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            cg.setLineJoin(.round)
            cg.setAlpha(opacity)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            if let wordOutline, let wordFill {
                wordOutline.draw(at: wordOrigin)
                wordFill.draw(at: wordOrigin)
            }
            outline.draw(at: origin)
            if let rim = ink.rim {
                // A thin rim in the attacker's colour just outside the
                // letters, inside the dark edge.
                let rimmed = NSAttributedString(string: text, attributes: [
                    .font: font, .kern: tracking,
                    .strokeColor: rim,
                    .strokeWidth: 2 * (edge * 0.6) / size * 100,
                ])
                rimmed.draw(at: origin)
            }
            if let gradient {
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
                fill.draw(at: origin)
                gradient.draw(in: CGRect(origin: origin, size: measured), blendMode: .sourceIn, alpha: 1)
                cg.endTransparencyLayer()
            } else {
                let solid = NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: ink.fill, .kern: tracking,
                ])
                solid.draw(at: origin)
            }
            cg.endTransparencyLayer()
        }
    }

    /// A vertical gradient the size of a line of letters.
    private static func gradientImage(_ stops: [(CGFloat, String)], size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colours = stops.map { (UIColor(hex: $0.1) ?? .white).cgColor } as CFArray
            let locations: [CGFloat] = stops.map { $0.0 }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours,
                                            locations: locations) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    /// A colour as a cache key.
    static func rgbaKey(_ colour: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "\(Int(red * 255)),\(Int(green * 255)),\(Int(blue * 255)),\(Int(alpha * 255))"
    }

    // MARK: - The skill banner (Docs/FEEL.md W1.9)

    /// The banner a caster wears as its skill goes off: the skill's painted
    /// icon (or its glyph until the painting ships) in a dark socket lit in
    /// the caster's element, framed in gold, beside its name in Cinzel at 20
    /// points, on a dark ribbon that fades out past the name — Summoners
    /// War's banner in the owner's frame. The same clear edge round it as
    /// every float, so the float's clamps hold it by its own size.
    static func banner(_ name: String, icon: UIImage?, glyph: String, key iconKey: String, tint: UIColor) -> UIImage? {
        let key = "b|\(name)|\(iconKey)|\(icon == nil ? "g" : "p")|\(rgbaKey(tint))"
        if let cached = cache[key] { return cached }
        let size: CGFloat = bannerNameSize
        let font = UIFont(name: Theme.carvedFace, size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        let edge: CGFloat = max(2.0, size / 9)
        let title = NSAttributedString(string: name, attributes: [
            .font: font, .foregroundColor: UIColor(hex: "#F7E7B4") ?? .white, .kern: 0.6,
        ])
        let titleOutline = NSAttributedString(string: name, attributes: [
            .font: font, .kern: 0.6,
            .strokeColor: edgeColour,
            .strokeWidth: 2 * edge / size * 100,
            .shadow: letterShadow(carved: true),
        ])
        let measured = title.size()
        guard measured.width > 0, measured.height > 0 else { return nil }
        let frame: CGFloat = 34
        let gap: CGFloat = 8
        let pad: CGFloat = edge + 5
        let width: CGFloat = ceil(pad + frame + gap + measured.width + 14 + pad)
        let height: CGFloat = ceil(max(frame, measured.height) + 2 * pad)
        let midY: CGFloat = height / 2
        let socketRect = CGRect(x: pad, y: midY - frame / 2, width: frame, height: frame)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            // The ribbon: dark glass from under the frame to past the name,
            // fading out, with a gold hairline along each edge.
            let ribbon = CGRect(x: socketRect.midX, y: midY - 13, width: width - pad - socketRect.midX, height: 26)
            let shade = [
                UIColor.black.withAlphaComponent(0.62).cgColor,
                UIColor.black.withAlphaComponent(0.45).cgColor,
                UIColor.black.withAlphaComponent(0).cgColor,
            ] as CFArray
            let shadeStops: [CGFloat] = [0, 0.7, 1]
            if let gradient = CGGradient(colorsSpace: space, colors: shade, locations: shadeStops) {
                cg.saveGState()
                cg.clip(to: ribbon)
                cg.drawLinearGradient(gradient, start: CGPoint(x: ribbon.minX, y: midY),
                                      end: CGPoint(x: ribbon.maxX, y: midY), options: [])
                cg.restoreGState()
            }
            let hairlines = [
                (UIColor(hex: "#E8C877") ?? .yellow).withAlphaComponent(0.7).cgColor,
                (UIColor(hex: "#E8C877") ?? .yellow).withAlphaComponent(0).cgColor,
            ] as CFArray
            let hairlineStops: [CGFloat] = [0, 1]
            if let gradient = CGGradient(colorsSpace: space, colors: hairlines, locations: hairlineStops) {
                for y in [ribbon.minY, ribbon.maxY - 1] {
                    let line = CGRect(x: ribbon.minX, y: y, width: ribbon.width, height: 1)
                    cg.saveGState()
                    cg.clip(to: line)
                    cg.drawLinearGradient(gradient, start: CGPoint(x: line.minX, y: y),
                                          end: CGPoint(x: line.maxX, y: y), options: [])
                    cg.restoreGState()
                }
            }

            // The gold frame, the dark socket, the element's light in it.
            let outer = UIBezierPath(roundedRect: socketRect, cornerRadius: 8)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 4, color: UIColor.black.withAlphaComponent(0.8).cgColor)
            (UIColor(hex: "#5C4611") ?? .brown).setFill()
            outer.fill()
            cg.restoreGState()
            let goldStops = [
                (UIColor(hex: "#FBE7A1") ?? .yellow).cgColor,
                (UIColor(hex: "#D2A844") ?? .yellow).cgColor,
                (UIColor(hex: "#8C6D22") ?? .brown).cgColor,
            ] as CFArray
            let goldLocations: [CGFloat] = [0, 0.5, 1]
            if let gradient = CGGradient(colorsSpace: space, colors: goldStops, locations: goldLocations) {
                cg.saveGState()
                outer.addClip()
                cg.drawLinearGradient(gradient, start: CGPoint(x: socketRect.midX, y: socketRect.minY),
                                      end: CGPoint(x: socketRect.midX, y: socketRect.maxY), options: [])
                cg.restoreGState()
            }
            let socket = socketRect.insetBy(dx: 2.5, dy: 2.5)
            let well = UIBezierPath(roundedRect: socket, cornerRadius: 6)
            (UIColor(hex: "#15100B") ?? .black).setFill()
            well.fill()
            let glowStops = [tint.withAlphaComponent(0.6).cgColor, tint.withAlphaComponent(0).cgColor] as CFArray
            let glowLocations: [CGFloat] = [0, 1]
            if let gradient = CGGradient(colorsSpace: space, colors: glowStops, locations: glowLocations) {
                cg.saveGState()
                well.addClip()
                let centre = CGPoint(x: socket.midX, y: socket.midY)
                cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                      endCenter: centre, endRadius: socket.width * 0.62, options: [])
                cg.restoreGState()
            }
            // The icon: the painting fitted, or the glyph in white.
            let art = socket.insetBy(dx: 2, dy: 2)
            let glyphLook = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            let glyphImage: UIImage? = UIImage(systemName: glyph, withConfiguration: glyphLook)
            cg.saveGState()
            well.addClip()
            if let icon, icon.size.width > 0, icon.size.height > 0 {
                let fit = min(art.width / icon.size.width, art.height / icon.size.height)
                let drawn = CGSize(width: icon.size.width * fit, height: icon.size.height * fit)
                icon.draw(in: CGRect(x: art.midX - drawn.width / 2, y: art.midY - drawn.height / 2,
                                     width: drawn.width, height: drawn.height))
            } else if let symbol = glyphImage?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let box: CGFloat = 18
                let fit = min(box / max(1, symbol.size.width), box / max(1, symbol.size.height))
                let drawn = CGSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
                symbol.draw(in: CGRect(x: art.midX - drawn.width / 2, y: art.midY - drawn.height / 2,
                                       width: drawn.width, height: drawn.height))
            }
            cg.restoreGState()

            // The name, carved, centred on the ribbon.
            cg.setLineJoin(.round)
            let origin = CGPoint(x: socketRect.maxX + gap, y: midY - measured.height / 2)
            titleOutline.draw(at: origin)
            title.draw(at: origin)
        }
        remember(image, as: key)
        return image
    }

    /// The skill's name on its banner: 20 points (W1.9).
    static let bannerNameSize: CGFloat = 20
}

/// The small carved word a number wears over it (Docs/FEEL.md W1.2): it
/// replaces the "!" a crit wore and the "glance" suffix, in the word's own
/// colour, and the gold TOTAL that closes a multi-hit.
enum HitWord {
    case critical, glancing, total

    var text: String {
        switch self {
        case .critical: return "CRITICAL"
        case .glancing: return "GLANCING"
        case .total: return "TOTAL"
        }
    }

    var colourHex: String {
        switch self {
        case .critical: return "#FFB43A"
        case .glancing: return "#A6AFBC"
        case .total: return "#F5D57A"
        }
    }
}

/// The ink a number is drawn in (W1.2): an ordinary blow cream with a thin
/// rim in the attacker's element colour; a crit a gradient from gold to
/// orange; a glance slate; a multi-hit's TOTAL a gradient of gold; a word
/// alone its own colour. Green is the heal's (`floatText`) and nothing here
/// is green.
enum FloatInk {
    case rimmed(UIColor)
    case critical
    case glancing
    case total
    case solid(UIColor)

    /// The fill, for an ink that is one colour.
    var fill: UIColor {
        switch self {
        case .rimmed: return UIColor(hex: "#FFF4DE") ?? .white
        case .critical: return UIColor(hex: "#FFC53D") ?? .yellow
        case .glancing: return UIColor(hex: "#A6AFBC") ?? .gray
        case .total: return UIColor(hex: "#F6D06A") ?? .yellow
        case .solid(let colour): return colour
        }
    }

    /// The rim just outside the letters, for the ink that has one.
    var rim: UIColor? {
        switch self {
        case .rimmed(let colour): return colour
        case .critical, .glancing, .total, .solid: return nil
        }
    }

    /// The gradient's stops, top to foot, for an ink that is one.
    var gradient: [(CGFloat, String)]? {
        switch self {
        case .critical: return [(0, "#FFF1A8"), (0.45, "#FFC53D"), (1, "#FF7A1F")]
        case .total: return [(0, "#FFF6CF"), (0.5, "#F6D06A"), (1, "#D9A12E")]
        case .rimmed, .glancing, .solid: return nil
        }
    }

    var key: String {
        switch self {
        case .rimmed(let colour): return "r\(FloatingTextRenderer.rgbaKey(colour))"
        case .critical: return "c"
        case .glancing: return "g"
        case .total: return "t"
        case .solid(let colour): return "s\(FloatingTextRenderer.rgbaKey(colour))"
        }
    }
}
