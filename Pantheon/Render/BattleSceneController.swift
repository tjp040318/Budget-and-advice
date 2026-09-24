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

/// Owns the 3D battle: the stage, the lighting, the units, and the playback of
/// the engine's event stream.
///
/// The engine has already decided everything by the time this runs. Playback is
/// pure presentation, which is why a battle can be fast-forwarded, skipped or
/// replayed without the outcome changing.
final class BattleSceneController: NSObject {

    let scene = SCNScene()
    weak var delegate: BattleSceneDelegate?

    /// 1.0 is normal, 2.0 is the fast-forward toggle, 4.0 is "skip animation".
    ///
    /// It used to divide the event queue's holds and nothing else: every
    /// skeletal clip still played at its authored speed, so at the x2 the
    /// auto-repeat actually runs at, each attack was about half finished when
    /// the next event replaced it and the figures twitched between fragments
    /// of swings. SceneKit has no per-node speed multiplier to lean on (that
    /// is SpriteKit), so the units are told and scale their own clips and
    /// actions by hand.
    var speedMultiplier: Double = 1.0 {
        didSet {
            for node in unitNodes.values { node.playbackSpeed = speedMultiplier }
        }
    }

    /// Authored seconds at the current playback speed. Every duration in this
    /// file is written for x1 and passes through here on its way to a timer,
    /// so fast-forward shortens the whole fight by one factor rather than by
    /// several that drift apart.
    private func beat(_ seconds: TimeInterval) -> TimeInterval {
        seconds / max(0.25, speedMultiplier)
    }

    /// How long a melee unit takes to close on its victim.
    private static let dashDuration: TimeInterval = 0.30

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

    // MARK: - Setup

    func build(combatants: [Combatant], environment: BattleEnvironment) {
        self.environment = environment
        scene.rootNode.removeAction(forKey: "cast_impact")
        retirePreviousStage()
        ledge = nil
        unitNodes.removeAll()
        homeMarks.removeAll()
        plates.removeAllPlates()
        plates.removeAllFloats()
        refreshPlateTargets()
        holdOverride = nil
        castRecovery = 0

        buildStage()
        buildLighting()
        buildCamera()
        registerMaxHealth(combatants)
        place(combatants: combatants)
        startTourAreaDrill()
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
        key.color = (UIColor(hex: environment.keyLightHex) ?? .white).mixed(with: .white, amount: 0.45)
        key.intensity = 1_150
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        key.shadowColor = UIColor.black.withAlphaComponent(0.55)
        key.maximumShadowDistance = 30
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
        let fill = SCNLight()
        fill.type = .directional
        fill.color = palette.sky.mixed(with: .white, amount: 0.55)
        fill.intensity = 400
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
        ambient.color = palette.horizon.mixed(with: hand, amount: 0.35).mixed(with: .white, amount: 0.5)
        // Lower where the painting's environment map now fills the shadow
        // side (2026-09-20); the flat-colour fallback keeps the old floor.
        ambient.intensity = palette.environment != nil ? 150 : 240
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

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
        camera.bloomIntensity = 0.22
        camera.bloomThreshold = 0.975
        camera.bloomBlurRadius = 10
        // Chromatic aberration at 0.35 read as a filter (2026-09-20): a trace.
        camera.colorFringeStrength = 0.12
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
        for combatant in combatants {
            let node = UnitNode(combatant: combatant, detail: detail)
            node.playbackSpeed = speedMultiplier
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
                // A later wave walks on from the far side of the field.
                node.position = SCNVector3(home.x, home.y, home.z - 3.0)
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
            }
            if combatant.isBoss, ledge == nil {
                let recipe = StageBuilder.recipe(for: environment)
                let rock = StageBuilder.breach(
                    rock: recipe.rock, floor: recipe.floor, floorRepeats: recipe.floorRepeats,
                    floorTint: recipe.floorTint, at: home
                )
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
    private static let bossMark = SCNVector3(0, 0, -8.4)
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
        let spacing: Float = 2.4
        let centred = Float(indexInRank) - Float(inThisRank - 1) / 2
        let stagger: Float = combatant.side == .player ? 0 : 0.6
        // A second rank stands further from the camera than the first and
        // half a step over, so nobody hides behind the unit in front.
        let halfStep: Float = rank.truncatingRemainder(dividingBy: 2) == 0 ? 0 : spacing / 2
        let depth = 3.0 + rank * 1.7
        return SCNVector3(centred * spacing + stagger + halfStep, 0, sideSign * depth)
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
        Juice.release(scene)
        sync(combatants: combatants)
        delegate?.battleSceneDidFinishPlayback(self)
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
            director?.returnHome()
            returnEveryoneHome()
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

        case .turnBegan(let actor, _):
            returnEveryoneHome()
            highlight(actor)
            showMatchups(for: actor)
            // The actor's attack bar is full: that is why it is acting.
            unitNodes[actor]?.plate?.setAttackBar(1, animated: true)
            // The walk-ons of the last wave are on their marks by now.
            director?.frameField()

        case .turnSkipped(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("SKIPPED", over: node, color: UIColor(hex: "#C8C8C8")!)

        case .skillCast(let actor, _, let name, let targets, let shot, let animation, let vfx):
            guard let casterNode = unitNodes[actor] else { return 0 }
            let targetNode = targets.first.flatMap { unitNodes[$0] }
            // Stamped, so a console that ends mid-fight says which cast it
            // ended in (the arena crash of 2026-09-15 was read off the last
            // clip loaded, which is a poorer clock).
            Perf.note("cast \(name) by \(casterNode.spec.assetName) as \(animation) on \(targets.count) target(s)")
            lastCastClip = animation
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
                casterNode.dash(toward: targetNode, duration: beat(Self.dashDuration))
                // The swing waits for the feet. These two lines used to be
                // consecutive statements, so the clip and the leap started on
                // the same frame and the wind-up — the only part of an attack
                // that carries anticipation — played four metres away in
                // mid-air; the figure arrived a quarter of the way through its
                // own cut. The 80 ms overlap is deliberate: the wind-up begins
                // as the weight comes down, which is what ties a leap and a
                // swing into one motion.
                walkUp = max(0, Self.dashDuration
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
            // The skill's name over its caster, followed through the leap
            // (it hung over the EMPTY mark a closing caster had left, run
            // 220), in the HUD's pale gold. Not for an ultimate: the cut-in
            // is its name, and the two at once put it on the screen twice.
            if animation != .ultimate {
                floatText(name, over: casterNode, color: UIColor(hex: "#F3DFA6") ?? .white, scale: 0.7)
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

        case .damage(_, let target, let amount, let isCritical, let isGlancing, let matchup, let remaining, _, _):
            guard let node = unitNodes[target] else { return 0 }

            // How hard did that land? Lethal beats critical beats the clip.
            let weight: HitWeight
            if remaining <= 0 {
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

            // Everything a blow does now happens on ONE frame: the burst and
            // the slash arc (spawned by the cast, timed to this instant), the
            // white flash, the flinch, the shove, the number, the sound, the
            // haptic and the freeze. They used to be spread over more than a
            // second, which is why a hit read as a light show followed by a
            // bookkeeping update. The shove is the part that was missing
            // altogether: a body that never moves is not being hit.
            node.play(.hitReact)
            node.flashHit()
            node.recoil(strength: Self.recoilStrength(for: weight))
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))

            let color: UIColor
            var label = "\(Int(amount.rounded()))"
            if isCritical {
                color = UIColor(hex: "#FFD24F")!
                label = "\(label)!"
                VFXLibrary.spawn("crit", at: node.chestWorldPosition, in: scene, tint: color)
            } else if isGlancing {
                color = UIColor(hex: "#9AA3B0")!
                label = "\(label) glance"
            } else if matchup == .advantage {
                color = UIColor(hex: "#7FE8A0")!
            } else {
                color = .white
            }
            floatText(label, over: node, color: color, scale: profile.numberScale, pop: true)

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

            return Juice.impact(weight, colour: lastCastColour, scene: scene, director: director, speed: speedMultiplier)

        case .healed(_, let target, let amount, let remaining):
            guard let node = unitNodes[target] else { return 0 }
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))
            floatText("+\(Int(amount.rounded()))", over: node, color: UIColor(hex: "#7FE8A0")!)
            VFXLibrary.spawn("heal", at: node.position, in: scene, tint: UIColor(hex: "#7FE8A0")!)

        case .shieldAbsorbed(let target, let amount, _):
            guard let node = unitNodes[target] else { return 0 }
            floatText("\(Int(amount.rounded())) blocked", over: node, color: UIColor(hex: "#6BD8F2")!, scale: 0.8)

        case .statusApplied(_, let target, let kind, let turns):
            guard let node = unitNodes[target] else { return 0 }
            node.applyStatus(kind, turns: turns)
            VFXLibrary.spawn(kind.isBuff ? "buff" : "debuff", at: node.position, in: scene, tint: .white)
            floatText(kind.displayName, over: node,
                      color: kind.isBuff ? UIColor(hex: "#6BD8F2")! : UIColor(hex: "#F2726B")!, scale: 0.7)

        case .statusResisted(_, let target, _):
            guard let node = unitNodes[target] else { return 0 }
            floatText("RESIST", over: node, color: UIColor(hex: "#C8C8C8")!, scale: 0.8)

        case .statusExpired(let target, let kind), .statusRemoved(let target, let kind, _):
            unitNodes[target]?.removeStatus(kind)

        case .attackBarChanged(let target, _, let newValue):
            unitNodes[target]?.plate?.setAttackBar(newValue, animated: true)

        case .cooldownStarted:
            break

        case .counterattack(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("COUNTER", over: node, color: UIColor(hex: "#FFD24F")!, scale: 0.9)
            node.play(.attackBasic)
            // A counter interrupts whatever the caster was in the middle of,
            // so the follow-through owed by that cast is void; leaving it
            // would add a second of nothing to the next turn.
            castRecovery = 0

        case .extraTurnGranted(let actor, _):
            guard let node = unitNodes[actor] else { return 0 }
            floatText("EXTRA TURN", over: node, color: UIColor(hex: "#FFD24F")!, scale: 0.9)

        case .passiveTriggered(let actor, let name):
            guard let node = unitNodes[actor] else { return 0 }
            floatText(name, over: node, color: UIColor(hex: "#E8C86A")!, scale: 0.9)
            VFXLibrary.spawn("stormlord_surge", at: node.position, in: scene, tint: UIColor(hex: "#E8C86A")!)

        case .revived(let target, _):
            unitNodes[target]?.revive(healthFraction: 0.3)

        case .defeated(let target):
            unitNodes[target]?.markDefeated()

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
                plates.removePlate(for: id)
            }
            registerMaxHealth(opponents)
            place(combatants: opponents, entering: true)
            // Measure the field with the new wave on it now, not at the next
            // drain: in an auto fight the queue never drains between turns,
            // so a boss arriving with the third wave was never measured and
            // the boss framing never came — three runs of frames had the
            // Colossus at the far end of the ordinary 58° shot.
            director?.frameField()
            Juice.haptic(.light)

        case .battleEnded(let result):
            director?.returnHome()
            Juice.notify(result.outcome == .victory ? .success : .error)
            AudioLibrary.shared.play(result.outcome == .victory ? .victory : .defeat)
            for (_, node) in unitNodes where !node.isDefeated {
                if (result.outcome == .victory && node.side == .player)
                    || (result.outcome == .defeat && node.side == .opponent) {
                    node.play(.victory)
                }
            }
        }
        return 0
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
        for (id, node) in unitNodes { node.setHighlighted(id == actorID) }
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
        plateLock.lock()
        let targets = plateTargets
        let bosses = plateBosses
        let homes = plateHomes
        plateLock.unlock()
        let now = CACurrentMediaTime()
        let step = CGFloat(min(0.1, max(0, now - lastPlateLayout)))
        lastPlateLayout = now

        // Each plate where it would stand on its own.
        var standing: [(plate: UnitPlate, id: UUID, point: CGPoint, blocks: Bool, visiting: Bool)] = []
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
            let point = CGPoint(
                x: CGFloat(projected.x),
                y: height - CGFloat(projected.y) + UnitPlate.riseAboveHead + UnitPlate.trackHeight / 2
            )
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
            standing.append((plate, key, point, onScreen && !node.isDefeated, visiting))
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
                    let onFrame = clearing.filter { baseY + $0 + headroom < height }
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
        layoutFloats(in: renderer, bossStands: bosses.contains { !$0.isDefeated }, plateBoxes: drawn)
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
    /// set from here): inside the safe area with 8 points of padding at the
    /// sides and the bottom; the gear, the speed and auto three 36-point
    /// squares 6 apart at the bottom left (`controls`, `squareControl`); the
    /// skills three 60-point squares 10 apart at the bottom right
    /// (`skillRow`, `SkillButton`), a picked one 6% larger, with Skip (36
    /// tall) in their place while a turn plays. At the top, 4 points down:
    /// the stage and wave chips (`hudChip`, 30 tall), their row about 250
    /// points long, and over them while a boss stands its bar — its name on
    /// a 30-point chip, 4 points, then the channels, 18.5 points with a
    /// raid's barrier row 24 — so the bar ends 62 points down at most and
    /// the chips under it 98. Change one there, change it here.
    private static let hudPadding: CGFloat = 8
    /// Plain numbers: as `3 * 36 + 2 * 6` inside `CGSize` (or `CGFloat(…)`)
    /// the literals' types were solved against every numeric overload,
    /// 0.3 s, then 1.4 s wrapped, on CI's type checker (runs 229 and 233).
    private static let hudControls = CGSize(width: 120, height: 36)    // three 36-point controls, two 6-point gaps
    private static let hudSkills = CGSize(width: 200, height: 64)      // three 60-point squares, two 10-point gaps
    private static let hudChipsLength: CGFloat = 250
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
        let barFoot: CGFloat = bossStands ? 62 : 0
        let chipsFoot: CGFloat = bossStands ? 98 : 34
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
            label.node.position = CGPoint(x: x + label.slide, y: y)
        }
        plates.retireFloats(finished)
    }
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
        if cache.count > 400 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
