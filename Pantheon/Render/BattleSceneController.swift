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

    /// The size an effect is drawn at on a unit: its height over a hero's
    /// 1.9 m, no taller than 2.6 m. Unclamped, a hit on the 8 m Colossus drew
    /// at 4.2 times — a basic's fireburst ten metres across, Keraunos's
    /// lightning sheet twenty-two — and filled the upper frame with a wash
    /// of magnified texels (run 223, 18-c). The same on a boss's own wind-up.
    static func effectScale(for node: UnitNode) -> Float {
        min(node.spec.height, 2.6) / 1.9
    }

    /// Where in a clip each of a cast's `hits` lands, as fractions of the
    /// clip's contract duration.
    ///
    /// Nothing in the pipeline had ever known this: `AnimationClip` carries a
    /// duration and no contact frame, so the impact was spawned on a detached
    /// timer at a flat 45% of the clip while the damage event — the flash, the
    /// number, the sound, the haptic and the freeze — waited for the WHOLE
    /// clip to finish. Every basic attack therefore played as a slash arc, six
    /// tenths of a second of nothing, and then a victim flinching at something
    /// that had already happened; on an ultimate the gap was over a second.
    /// Two half-hits are why the fight read as numbers changing rather than as
    /// something being struck. `UnitNode.play` retimes every one-shot to its
    /// contract so a fraction means the same thing whatever length Meshy
    /// happened to author the clip at.
    ///
    /// And then it was ONE number per clip (Docs/PLAN.md *Skills that look
    /// like themselves*, 2026-09-25), and every later hit of a multi-hit
    /// skill landed 0.30–0.55 s after the one before whatever the body was
    /// doing: a three-hit skill was one swing and three numbers. The
    /// contacts are data now, measured per clip file (`ClipTimings`): the
    /// clip's own strikes, a flurry the clip does not show spread past its
    /// last, and for a clip with no entry the old defaults and the five
    /// gods' bespoke rows (2026-09-15, read off their frames), which live in
    /// `ClipTimings.standInContacts` beside the numbers they replaced — keyed
    /// by the asset whose clips PLAY, so a stand-in fighting in a god's mesh
    /// strikes where the god's clip does. `clipAsset` is that asset
    /// (`UnitNode.clipAsset`) and `clip` the clip it really plays
    /// (`ModelLibrary.resolvedClip`), so a flurry a family has no clip for is
    /// timed on the heavy blow it falls back to.
    private static func hitFractions(of clip: AnimationClip, clipAsset: String, hits: Int) -> [Double] {
        ClipTimings.hitFractions(asset: clipAsset, clip: clip, hits: hits)
    }

    /// Whether a blow of `clip` lands heavy — its freeze, its shake, its
    /// number and its dwell: the heavy blow, a rite's release, an
    /// ultimate's hits and a strike on the whole line; of a flurry
    /// (`skillX2…X5`) its last strike alone, the finisher, so the strikes
    /// before it keep the quick cadence a flurry reads by. Read off the clip
    /// the skill ASKED for (the engine's), not the one a family falls back
    /// to: a flurry played over the heavy blow is still a flurry.
    static func landsHeavy(_ clip: AnimationClip, hitIndex: Int, hitCount: Int) -> Bool {
        switch clip {
        case .ultimate, .attackHeavy, .castRelease, .skillArea:
            return true
        case .skillX2, .skillX3, .skillX4, .skillX5:
            return hitIndex >= hitCount - 1
        default:
            return false
        }
    }

    /// Whether a melee caster leaps at its one victim for this clip: a
    /// basic, a heavy blow and a flurry, which strike at arm's length; a
    /// blow on the whole line, a rite and an ultimate are cast from where it
    /// stands.
    static func closesToStrike(_ clip: AnimationClip) -> Bool {
        switch clip {
        case .attackBasic, .attackHeavy, .skillX2, .skillX3, .skillX4, .skillX5:
            return true
        default:
            return false
        }
    }

    /// Whether a cast strikes its whole line at once: an area skill's own
    /// clip, or a basic, a heavy blow or an ultimate whose first hit fell on
    /// each of its two or more targets once. Never a flurry, whose random
    /// victims only happen to be the line.
    static func strikesTheLine(_ clip: AnimationClip, targets: [UUID], firstVictims: [UUID]) -> Bool {
        switch clip {
        case .skillArea:
            return true
        case .skillX2, .skillX3, .skillX4, .skillX5:
            return false
        default:
            let line = Set(targets)
            return line.count >= 2 && firstVictims.count == line.count && Set(firstVictims) == line
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
    /// How far under the crown, in points, a head mark circles (W2.22), and
    /// how much larger it is round a boss's head.
    private static let markBelowCrown: CGFloat = 4
    private static let bossMarkScale: CGFloat = 1.8
    /// Seconds a visiting plate takes to fade back in at a clear spot. It
    /// goes out at once: a fade out is a plate drawn over another.
    private static let visitorFade: CGFloat = 0.12
    private var cameraNode = SCNNode()
    /// The rig the camera hangs under (Docs/FEEL.md W2.18): the director
    /// moves it, and the shake moves only `cameraNode` inside it.
    private var cameraRig = SCNNode()
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

    /// The cast being presented, hit by hit (Docs/PLAN.md *Skills that look
    /// like themselves*, 2026-09-25): its timeline (`CastTimeline`), its own
    /// slice of the queue as it was read ahead, cast first, which event of
    /// that slice is on screen, and the authored seconds since the cast
    /// began (a freeze's time left out, as the clip it is timed against
    /// stood still through it). `playNext` holds each event of the slice
    /// until the next is due, so every hit lands on its own contact; a
    /// counter, a new cast, a turn, a wave, the end, a skip, a forfeit or a
    /// new run ends it. Main thread.
    private var castTimeline: CastTimeline?
    private var castEvents: [BattleEvent] = []
    private var castCursor = 0
    private var castElapsed: TimeInterval = 0
    /// Set by the final blow's own hold (`afterTheFinalBlow`, with its slow
    /// motion handed back as frozen time), which no timeline overrides.
    /// Cleared before every event.
    private var holdIsFinalBlow = false

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

    // MARK: The beats over the field (Docs/FEEL.md W2.1, W2.8–W2.11)

    /// Told, on the main thread, of every beat the battle view draws over
    /// the field — an ultimate's splash, a wave's stamp, a boss's entrance —
    /// and of each one's end (`FieldCue`). The view sets and clears it, and
    /// it holds nothing of the view model's, so no cycle.
    var onFieldCue: ((FieldCue) -> Void)?
    /// Each fighter's card, name and colour, for its splash.
    private var castCards: [UUID: (portrait: String, name: String, accentHex: String)] = [:]
    /// The fighters whose ultimate has owned the screen this fight, for
    /// "First each fight".
    private var splashedCasters: Set<UUID> = []
    private var splashSerial = 0
    private var stampSerial = 0
    private var entranceSerial = 0
    /// The wave the field is on, as this scene has put it there: 1 from the
    /// build, raised by each `.waveStarted` that brings a NEW wave. A raid's
    /// guard coming back is reported as `.waveStarted` under the wave the
    /// fight is already on (`BattleEngine.summonGuard`, so the HUD's counter
    /// never lies): it walks on, but it is no wave of its own and wears no
    /// stamp — every Titan's guard was stamped FINAL WAVE, drum and all, each
    /// time it came back (review, 2026-09-24).
    private var fieldWave = 1
    /// The boss making its entrance, and a boss in the opening line waiting
    /// below the rim for the stage to be seen.
    private weak var entranceBoss: UnitNode?
    private weak var openingBoss: UnitNode?
    /// The playback queue waits past an event's own hold while a beat that
    /// is not the event's holds it: until `queueHeldUntil` on
    /// `CACurrentMediaTime`'s clock, or for as long as `queueHeldOpen`
    /// (an opening boss waiting for its stage to be seen). `queueDueAt` is
    /// when the event now playing is due to hand on, for a CI frame's hold
    /// to add to (`freezeForTour`).
    private var queueHeldUntil: CFTimeInterval = 0
    private var queueHeldOpen = false
    private var queueDueAt: CFTimeInterval = 0
    /// Whether the renderer has drawn this build's stage, and what waits to
    /// be seen. `buildSerial` tells a late wait which build it was for.
    private var stageIsShown = false
    private var stageShownActions: [() -> Void] = []
    private var buildSerial = 0
    /// The spotlight (W2.9, W2.11): the lights it dims and its timeline,
    /// both read by the renderer's thread under `firstFramesLock`; whether
    /// the rest is owed at once (a skip, a new run); whether the camera's
    /// colour is the drain's for good; and whether an ultimate's dim waits
    /// for its blow to land.
    private var spotlightRig: SpotlightRig?
    private var spotlightTimeline: SpotlightTimeline?
    private var spotlightRestoreDue = false
    private var spotlightGradeHeld = false
    private var spotlightAwaitsBlow = false
    /// The lights `buildLighting` made that the spotlight turns: the key, the
    /// figures' own key, and the set's fill and ambient. Nil under
    /// `-tour-layers off`, where there are no set lights to dim apart.
    private var riggedLights: (key: SCNLight, figureKey: SCNLight, fill: SCNLight, ambient: SCNLight)?
    #if DEBUG
    /// The CI labs' one-shot holds (`-tour-cutin`, `-tour-waves`,
    /// `-tour-dissolve`): each beat is held once for its frame.
    private var tourCutInSpent = false
    private var tourSpotlightSpent = false
    private var tourStampSpent = false
    private var tourRibbonSpent = false
    private var tourDissolveVictim: UUID?
    #endif

    // MARK: - Setup

    func build(combatants: [Combatant], environment: BattleEnvironment) {
        self.environment = environment
        // The last run's cast draws nothing more into this one.
        SkillFX.cancel(in: scene)
        endCastTimeline()
        // A new run of an auto-repeat is built in the same scene: whatever
        // the last one's end changed goes back. The slow motion stops and the
        // pace returns to the player's; a freeze or a tremble still pending
        // lets go; the camera — its colour drained on a loss, its framing on
        // the team after a win — is built anew below with the realm's grade;
        // the plates, their EXP bars and every float go with the old units.
        endSlowMotion()
        cancelImpact()
        // The last run's beats over the field end with it (W2.1–W2.11): the
        // splash and the stamp come down, the queue waits for nothing, the
        // set's lights are the new build's.
        cancelBeats()
        Juice.release(scene)
        retirePreviousStage()
        ledge = nil
        unitNodes.removeAll()
        homeMarks.removeAll()
        skillArt.removeAll()
        castCards.removeAll()
        splashedCasters.removeAll()
        fieldWave = 1
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
        buildSerial += 1
        stageIsShown = false
        stageShownActions.removeAll()
        // The stage card's hold and its pre-draw are the first run's alone
        // (Docs/FEEL.md W2.24): an auto-repeat's later builds neither hold
        // their queue nor draw anything in advance.
        cardHolds = holdsForStageCard
        let plan: EffectPlan? = holdsForStageCard ? predrawPlan : nil
        holdsForStageCard = false
        predraw = nil
        predrawLights.removeAll()

        // Where the build's main-thread seconds go (task #138): run 245's
        // arena fight kept the main thread about 4.3 s at its build, under
        // the veil, and nothing said which part. One line per build, on the
        // phone's Diagnostics as well as the console.
        let began = Perf.begin()
        buildStage()
        let stageMs = Perf.end(began, "battle stage", over: .infinity)
        let lightBegan = Perf.begin()
        buildLighting()
        buildCamera()
        installSpotlightRig()
        let lightMs = Perf.end(lightBegan, "battle light", over: .infinity)
        registerMaxHealth(combatants)
        let unitsBegan = Perf.begin()
        place(combatants: combatants)
        let unitsMs = Perf.end(unitsBegan, "battle units", over: .infinity)
        if let plan { beginPredraw(plan) }
        startTourAreaDrill()
        startTourTriumph()
        startTourDissolve()
        startTourStatusDrill()
        startTourShakeDrill()
        awaitFirstFrames()
        let totalMs = Perf.end(began, "battle build", over: .infinity)
        Perf.note(String(format: "battle build: stage %.0f ms, light and camera %.0f ms, %d unit(s) %.0f ms, %.0f ms in all",
                         stageMs, lightMs, combatants.count, unitsMs, totalMs))
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
        // The rig, with the camera inside it.
        cameraRig.removeFromParentNode()
        firstFramesLock.lock()
        shakeTarget = nil
        firstFramesLock.unlock()
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
        riggedLights = nil
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

        // The figures' own key (Docs/FEEL.md W2.9): the key's colour, from
        // the key's place, on the figures alone and with no shadow. Idle at
        // a thousandth of the key; an ultimate's spotlight turns the shared
        // key down to 35% and this up by what it took, so the figures keep
        // the key's whole light while the stone loses most of it. Built with
        // the stage and never at nothing: a light lit from nothing in the
        // middle of a fight changes every figure material's light list, and
        // the ultimate would pay for the shaders on its first frame.
        let figureKey = SCNLight()
        figureKey.type = .directional
        figureKey.color = key.color
        figureKey.intensity = key.intensity * Spotlight.figureKeyIdle
        figureKey.categoryBitMask = StageBuilder.figureLights
        let figureKeyNode = SCNNode()
        figureKeyNode.light = figureKey
        figureKeyNode.position = keyNode.position
        figureKeyNode.eulerAngles = keyNode.eulerAngles
        scene.rootNode.addChildNode(figureKeyNode)
        riggedLights = (key: key, figureKey: figureKey, fill: fill, ambient: ambient)
    }

    /// The spotlight's rig for this build (Docs/FEEL.md W2.9): the lights
    /// `buildLighting` left for it, the painting's material — its intensity
    /// set a hair off 1 now, under the veil, so dimming it later changes a
    /// number rather than building a shader — and the camera, whose rest
    /// saturation is read here, before any impact frame can move it. The
    /// braziers' dimmer back at 1 for the new set.
    private func installSpotlightRig() {
        // The new stage's painting: the last run's stands hidden under
        // `previous_run` for a moment, so the search starts from the stage
        // that is a direct child of the root.
        let stage = scene.rootNode.childNodes.first { $0.name == "stage" }
        let backdrop = stage?.childNode(withName: "backdrop", recursively: false)?.geometry?.firstMaterial
        backdrop?.diffuse.intensity = Spotlight.backdropRest
        StageBuilder.battleSetDimmer.level = 1
        var rig: SpotlightRig?
        if let lights = riggedLights {
            rig = SpotlightRig(key: lights.key, figureKey: lights.figureKey, fill: lights.fill, ambient: lights.ambient,
                               backdrop: backdrop, camera: cameraNode.camera, dimmer: StageBuilder.battleSetDimmer)
        }
        firstFramesLock.lock()
        spotlightRig = rig
        spotlightTimeline = nil
        spotlightRestoreDue = false
        spotlightGradeHeld = false
        firstFramesLock.unlock()
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

        // The camera HANGS UNDER A RIG (Docs/FEEL.md W2.18): the director's
        // framing, zoom and eases move the rig, and the camera node sits at
        // rest inside it, moved only by the shake on the render thread
        // (`renderUpdate`) in the rig's own frame — so a shake in the middle
        // of a dolly no longer pulls the camera back to where the dolly
        // began, and it jolts along the lens's own axes, never toward it.
        cameraRig = SCNNode()
        cameraRig.name = "camera_rig"
        cameraRig.position = SCNVector3(0, 7.2, 11.0)
        cameraRig.eulerAngles = SCNVector3(-0.524, 0, 0)
        cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = camera
        cameraRig.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraRig)

        let made = CameraDirector(rig: cameraRig, lens: cameraNode)
        director = made
        firstFramesLock.lock()
        shakeTarget = (made.shaker, cameraNode)
        firstFramesLock.unlock()
        onCameraBuilt?(cameraNode)
    }

    /// Positions both teams. The camera sits on the +Z side, so the player's
    /// line stands nearest it at +Z and faces away, toward the enemies at -Z,
    /// who face +Z — toward the player and the camera. A model's authored
    /// facing is +Z (Docs/ART_PIPELINE.md), hence the half-turn on the near
    /// side. Ranks are staggered so nobody is hidden behind anybody.
    ///
    /// Returns, for a wave that walks on (Docs/FEEL.md W2.10), the longest
    /// walk in authored seconds, which the wave's hold waits out; 0 when
    /// nobody walks.
    @discardableResult
    private func place(combatants: [Combatant], entering: Bool = false) -> TimeInterval {
        var longestWalk: TimeInterval = 0
        // A 5v5 is ten characters plus a full post stack; a 1v1 can afford the
        // detailed mesh. The loader falls back to the full model when no reduced
        // export has been shipped.
        let detail = ModelLibrary.detail(forCombatantCount: combatants.count + (entering ? unitNodes.count : 0))
        noteLineWidth(combatants)
        let paleSet = StageBuilder.isPaleSet(environment)
        for combatant in combatants {
            let unitBegan = Perf.begin()
            let node = UnitNode(combatant: combatant, detail: detail)
            Perf.end(unitBegan, "unit \(combatant.model.assetName) built", over: 120)
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
            // Its card for its splash (W2.1), and the battle told when its
            // death has played out, to take it off the field (W2.8).
            castCards[combatant.id] = (portrait: combatant.model.portraitName(awakened: combatant.isAwakened),
                                       name: combatant.name, accentHex: combatant.element.accentHex)
            node.onFallen = { [weak self] fallen in self?.leaveTheField(fallen) }
            // How long this arrival walks, when it walks (W2.10).
            var walk: TimeInterval?
            if combatant.isBoss, entering || openingBoss == nil {
                // A boss RISES over the far rim from the dark under the
                // platform, rather than walking on: there is no floor where
                // it stands. It waits below, unseen, for its entrance
                // (W2.11, `beginBossEntrance`): at once for a wave's boss,
                // once it is in the scene below; for one in the opening
                // line (a Titan), when the stage has been seen
                // (`.battleStart`).
                node.position = SCNVector3(home.x, home.y - BossEntrance.depth, home.z)
                node.opacity = 0
                if !entering { openingBoss = node }
            } else if entering, WalkOn.walks(hasClip: node.hasWalkClip, speed: speedMultiplier) {
                // A later wave WALKS on from two metres behind its marks
                // (W2.10): its walk clip, at the stride the clip was made
                // for, started once the unit is in the scene below.
                node.position = SCNVector3(home.x, home.y, home.z - WalkOn.distance)
                node.opacity = 0
                let seconds = WalkOn.duration(distance: WalkOn.distance, height: combatant.model.height)
                walk = seconds
                longestWalk = max(longestWalk, seconds)
            } else if entering, Juice.isFast(speedMultiplier) {
                // At ×3 a wave's stamp is all of its arrival that plays: the
                // arrivals fade up on their marks.
                node.position = home
                node.opacity = 0
                node.runAction(.fadeIn(duration: beat(0.3)))
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
                // A family whose rig has no walk (those rigged before
                // 2026-09-17) still glides the two metres, as every arrival
                // did before W2.10.
                node.position = SCNVector3(home.x, home.y, home.z - WalkOn.distance)
                node.opacity = 0
                let slide = SCNAction.move(to: home, duration: beat(0.7))
                slide.timingMode = .easeOut
                node.runAction(.group([slide, .fadeIn(duration: beat(0.45))]))
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
                if entering { plate.enter(over: beat(0.45)) }
            }
            // Its statuses on its plate, and a mark round its head while it
            // cannot act — a boss's too, which wears no plate (W2.22).
            node.markOverlay = plates
            node.setStatuses(combatant.statuses)
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
            // Its arrival, now that it is in the scene (a clip attached
            // before that never starts): a wave's boss makes its entrance
            // (W2.11), a walker walks on (W2.10).
            if entering, combatant.isBoss {
                beginBossEntrance(node)
            } else if let walk {
                node.walkOn(to: home, over: beat(walk), fadeIn: beat(WalkOn.fadeIn))
            }
        }
        refreshPlateTargets()
        return longestWalk
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
        guard !isPlaying else { return }
        // A beat still holding the field (a CI frame's hold over an idle
        // turn) keeps a new turn waiting for it rather than playing it
        // under the held world; so does the stage card (W2.24), under which
        // the fight's opening — its horn call, a boss's rise — would be
        // spent on nobody.
        if queueHeldOpen || cardHolds || queueHeldUntil > CACurrentMediaTime() {
            isPlaying = true
            continueWhenFree(playbackGeneration)
        } else {
            playNext()
        }
    }

    /// Drops queued animation and snaps to the end state. Used by the skip button.
    func flush(combatants: [Combatant]) {
        playbackGeneration += 1
        queue.removeAll()
        isPlaying = false
        holdOverride = nil
        castRecovery = 0
        endCastTimeline()
        // A cast's hits are scene actions waiting for their contacts
        // (`SkillFX`); a skip must take them with the rest of the queue
        // rather than let them burst over a field that has already jumped
        // to the end state.
        SkillFX.cancel(in: scene)
        // And the same for a swing still waiting out its dash: the queue it
        // belonged to is gone, so it would otherwise land a lone attack over
        // a battle that has already been resolved.
        for node in unitNodes.values { node.cancelPendingClip() }
        // Skip is the one way to watch a turn with no feedback (W1.1): no
        // freeze, no tremble, no slow motion left running, and no TOTAL
        // owed to a multi-hit whose last hit will never be shown. Nor a
        // splash, a stamp or an entrance: the set's lights come straight
        // back and a rising boss stands on its mark (W2.1–W2.11).
        endSlowMotion()
        cancelBeats()
        Juice.release(scene)
        director?.shaker.stop()
        hitLedger = MultiHitLedger()
        sync(combatants: combatants)
        // And the field comes to rest as a drained queue leaves it
        // (`playNext`): the units back on their marks first, then the camera
        // home (2026-09-25). An ultimate's push now holds on its caster until
        // its first contact (`CameraDirector.perform`'s `holdUntil`), up to
        // three seconds at ×1, so a skip in its wind-up left the camera pushed
        // in on a caster whose blow would never come; and a striker a skip
        // caught beside its victim stood in the enemy line until the next
        // turn began.
        returnEveryoneHome()
        director?.returnHome()
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
        endCastTimeline()
        SkillFX.cancel(in: scene)
        for node in unitNodes.values { node.cancelPendingClip() }
        endSlowMotion()
        cancelBeats()
        Juice.release(scene)
        director?.shaker.stop()
        hitLedger = MultiHitLedger()
        returnEveryoneHome()
        director?.returnHome()
    }

    /// Forces every node to match engine truth. Called after a skip and at the
    /// end of each turn, so a dropped animation can never desync the display.
    func sync(combatants: [Combatant]) {
        for combatant in combatants {
            guard let node = unitNodes[combatant.id] else { continue }
            // A revive the skip dropped: the engine has the unit standing
            // again, and since a fallen body leaves the field (W2.8) a unit
            // left defeated here would fight on as a glyph on the floor with
            // no body — `revive` takes the glyph up and brings it back.
            if combatant.isAlive, node.isDefeated {
                node.revive(healthFraction: combatant.healthFraction)
            }
            node.setHealth(fraction: combatant.healthFraction, animated: false)
            node.setStatuses(combatant.statuses)
            node.plate?.setAttackBar(combatant.attackBar, animated: true)
            if !combatant.isAlive { node.markDefeated() }
        }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            endCastTimeline()
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
        holdIsFinalBlow = false
        followCastTimeline(to: event)
        let frozen = present(event)

        // A cast holds only until the blade lands — `holdOverride` — so the damage
        // event that carries the flash, the flinch, the shove, the number and
        // the freeze is presented ON the contact frame with the rest of the
        // swing still playing underneath it. Everything else keeps the
        // duration the event itself declares. While a cast's timeline runs
        // (2026-09-25) each of its events holds until the next is due
        // instead — every hit on its own contact, a line's victims 40 ms
        // apart, whatever the kit puts between two hits sharing the gap —
        // and its last hit keeps the dwell its blows earn.
        var span = timelineHold() ?? holdOverride ?? event.presentationDuration
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
        let running = max(0.02, beat(span))
        let hold = running + frozen
        advanceCastClock(by: running)
        let generation = playbackGeneration
        queueDueAt = CACurrentMediaTime() + hold
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.continueWhenFree(generation)
        }
    }

    /// Plays the next event once nothing holds the queue past its own hold:
    /// an opening boss's entrance waiting for its stage to be seen
    /// (`queueHeldOpen`), or a beat running longer than the event it came
    /// with (`queueHeldUntil`). It looks again a few times a second rather
    /// than scheduling the whole wait ahead, so a wait that grows (a CI
    /// frame's hold) is honoured, and a skip — the generation — is heard at
    /// once. With nothing holding it, it is the plain `playNext` it always
    /// was.
    private func continueWhenFree(_ generation: Int) {
        let wait: TimeInterval = queueHeldOpen || cardHolds ? Self.queuePoll : queueHeldUntil - CACurrentMediaTime()
        guard wait > 0.005 else {
            playNext()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + min(Self.queuePoll, wait)) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.continueWhenFree(generation)
        }
    }

    /// How often a held queue looks again.
    private static let queuePoll: TimeInterval = 0.1

    // MARK: - A cast's hits, each on its own contact (2026-09-25)

    /// A cast's timeline takes over the holds of its own events from here
    /// (`present`, `.skillCast`): `events` is its slice of the queue as it
    /// was read ahead, the cast first.
    private func beginCastTimeline(_ timeline: CastTimeline, events: [BattleEvent]) {
        castTimeline = timeline
        castEvents = events
        castCursor = 0
        castElapsed = 0
    }

    /// The cast's timeline ends: every hold is the event's own again.
    private func endCastTimeline() {
        castTimeline = nil
        castEvents = []
        castCursor = 0
        castElapsed = 0
    }

    /// Main thread, as each event is taken off the queue: while a timeline
    /// runs, the cast's own next event moves it on and anything else ends
    /// it — a counter, a new cast (which begins its own), a turn, a wave,
    /// the end. The slice was copied off this queue in order, so its next
    /// event is the one taken now unless the queue was cut.
    private func followCastTimeline(to event: BattleEvent) {
        guard castTimeline != nil else { return }
        let next = castCursor + 1
        if next < castEvents.count, castEvents[next].id == event.id {
            castCursor = next
        } else {
            endCastTimeline()
        }
    }

    /// The hold the running timeline gives the event on screen, in authored
    /// seconds; nil with no timeline, past its last hit, and under the final
    /// blow's own hold.
    private func timelineHold() -> TimeInterval? {
        guard let timeline = castTimeline, !holdIsFinalBlow else { return nil }
        return timeline.hold(after: castCursor, in: castEvents, elapsed: castElapsed)
    }

    /// The timeline's clock after an event's hold of `running` wall seconds
    /// (a freeze's time is not in it): the authored seconds it stood for at
    /// the pace it ran at, so a hold the queue had to floor is made up by
    /// the next one and no hit drifts off its contact.
    private func advanceCastClock(by running: TimeInterval) {
        guard castTimeline != nil else { return }
        castElapsed += running * max(0.25, pace)
    }

    /// Every beat drawn over the field ends where it stands — a skip, a
    /// forfeit, a new run (Docs/FEEL.md W2.1–W2.11): a boss still rising or
    /// still waiting below stands on its mark, the queue waits for nothing,
    /// the set's lights come straight back, the plates come up from under a
    /// splash, and the view takes the splash, the stamp and the ribbon down.
    private func cancelBeats() {
        for boss in [entranceBoss, openingBoss].compactMap({ $0 }) {
            boss.removeAction(forKey: "boss_entrance")
            if let home = homeMarks[boss.combatantID] { boss.position = home }
            boss.opacity = 1
        }
        entranceBoss = nil
        openingBoss = nil
        queueHeldOpen = false
        queueHeldUntil = 0
        spotlightAwaitsBlow = false
        endSpotlight()
        plates.setPlatesDimmed(false)
        onFieldCue?(.clear)
    }

    // MARK: - Presenting one event

    /// Returns how long the world froze for this event, if it did.
    @discardableResult
    private func present(_ event: BattleEvent) -> TimeInterval {
        // An ultimate's blow has landed — whatever comes after its cast is
        // presented on the contact frame — and the set comes back up round
        // its caster over 0.4 s (Docs/FEEL.md W2.9).
        if spotlightAwaitsBlow {
            spotlightAwaitsBlow = false
            releaseSpotlight(over: beat(Spotlight.releaseAfterBlow))
        }
        // What came just before, for the push chips (W2.22): the unit a hit
        // struck, and whose turn is opening. A relic's quiet top-up is read
        // off them (`BarPush`).
        let struckBefore: UUID? = lastStruck
        if case .damage(_, let struck, _, _, _, _, _, _, _) = event { lastStruck = struck } else { lastStruck = nil }
        switch event {
        case .turnBegan(let actor, _):
            openingActor = actor
        case .battleStart, .skillCast, .turnSkipped, .counterattack, .waveStarted, .battleEnded:
            openingActor = nil
        default:
            break
        }
        switch event {
        case .battleStart:
            for node in unitNodes.values { node.play(.idleCombat) }
            // The fight was silent between its blows (Docs/FEEL.md W1.4,
            // 2026-09-24): the realm's horn call opens it, a boss's arrival
            // its own boom, roar and cymbal.
            if openingBoss != nil {
                // A boss in the opening line (a Titan) makes its entrance the
                // moment its stage is seen — under the veil it would be spent
                // on nobody — and the fight waits for it (W2.11). Its boom
                // comes WITH its rise: here it sounded under the veil, seconds
                // before anyone saw the boss come (review, 2026-09-24).
                queueHeldOpen = true
                let generation = playbackGeneration
                whenStageShown { [weak self] in
                    guard let self, self.playbackGeneration == generation else { return }
                    self.queueHeldOpen = false
                    guard let boss = self.openingBoss else { return }
                    self.openingBoss = nil
                    AudioLibrary.shared.play(.bossArrival, volume: 0.85)
                    let span = self.beginBossEntrance(boss)
                    self.queueHeldUntil = max(self.queueHeldUntil, CACurrentMediaTime() + span)
                }
            } else {
                AudioLibrary.shared.play(unitNodes.values.contains(where: { $0.side == .opponent && $0.isBoss })
                                         ? .bossArrival : .waveCall(for: environment.pantheon), volume: 0.85)
            }

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
            lastCastClip = animation
            lastCasterElement = casterNode.element
            lastCastWasUltimate = animation == .ultimate
            // One impact frame per cast at most (W1.3).
            impactFrameSpent = false
            // A melee unit swinging is steel or stone; anything else is its
            // element. `castRelease` and the ultimate are always the element,
            // because that is what the effect on screen already shows. A blow
            // on the whole line lands as the heavy blow does.
            if animation == .castRelease || animation == .ultimate || !casterNode.spec.melee {
                lastCastColour = .element(casterNode.element)
            } else {
                lastCastColour = animation == .attackHeavy || animation == .skillArea ? .blunt : .blade
            }
            // A melee unit closes on its one victim before the swing and stays
            // there through the hits — a flurry's as well as a single blow's
            // (`closesToStrike`); casters, archers and line-wide skills strike
            // from where they stand. A boss has no floor to cross: it strikes
            // from where it towers.
            let closes = targetNode.map { victim in
                casterNode.spec.melee && !casterNode.isBoss && targets.count == 1
                    && victim.side != casterNode.side && Self.closesToStrike(animation)
            } ?? false
            // The camera is told where the leap will land before it begins:
            // a push-in aimed at the caster's mark held on empty floor while
            // the caster fought four metres away (2026-09-15).
            let landing = closes ? targetNode.map { casterNode.dashDestination(toward: $0) } : nil
            var leap: TimeInterval = 0
            var walkUp: TimeInterval = 0
            if closes {
                let from = casterNode.position
                let to = landing ?? from
                let dx = to.x - from.x
                let dz = to.z - from.z
                let travel: Float = (dx * dx + dz * dz).squareRoot()
                let stretch: Double = max(1, min(Self.dashStretchCap, Double(travel / Self.dashReach)))
                leap = Self.dashDuration * stretch
                // The swing waits for the feet. The clip and the leap used to
                // start on the same frame, so the wind-up — the only part of
                // an attack that carries anticipation — played four metres
                // away in mid-air; the figure arrived a quarter of the way
                // through its own cut. The 80 ms overlap is deliberate: the
                // wind-up begins as the weight comes down, which is what ties
                // a leap and a swing into one motion.
                walkUp = max(0, leap
                    * (UnitNode.dashGather + UnitNode.dashFlight) - 0.08)
            }

            // EVERY HIT ON ITS OWN CONTACT (2026-09-25; Docs/PLAN.md *Skills
            // that look like themselves*). The queue is read ahead to the next
            // turn, cast, wave, end or counter: the cast's own events, and
            // among them its hits, each with its victims. The clip that will
            // really play for the skill (a family without the flurry's own
            // file swings its heavy blow, `ModelLibrary.resolvedClip`) says
            // how long it plays (`ClipTimings.contract`) and where each hit
            // lands in it, measured from the start of the CLIP rather than of
            // the turn: hit k at the leap plus the contract times its
            // fraction. The queue holds each event of the cast until the next
            // is due (`CastTimeline`, `playNext`), so each hit's damage — the
            // flash, the flinch, the number, the freeze — is presented on its
            // own contact with the swing still playing underneath it. A rite
            // deals no damage: its release is its one contact.
            let reading = CastReading.ahead(in: queue, caster: actor)
            let clipAsset = casterNode.clipAsset
            let resolved = ModelLibrary.shared.resolvedClip(animation, for: clipAsset)
            let contract = ClipTimings.contract(asset: clipAsset, clip: resolved)
            let hitCount = max(1, reading.hitCount)
            let fractions = Self.hitFractions(of: resolved, clipAsset: clipAsset, hits: hitCount)
            let firstVictims: [UUID] = reading.hits.first?.victims ?? []
            let isArea = Self.strikesTheLine(animation, targets: targets, firstVictims: firstVictims)
            // A ranged cast's contact is its RELEASE — the hand thrown out,
            // the string let go — and the shot it throws lands a flight
            // later: each hit is presented that much after its contact, so
            // the orb or the arrow leaves the hand instead of before it.
            let flight: TimeInterval = reading.hitCount == 0 ? 0
                : SkillFX.flight(family: casterNode.spec.assetName, ranged: !casterNode.spec.melee,
                                 isBoss: casterNode.isBoss, isArea: isArea, isUltimate: animation == .ultimate)
            let timeline = CastTimeline.planned(walkUp: walkUp + flight, contract: contract, fractions: fractions,
                                                heavy: Self.landsHeavy(animation, hitIndex: hitCount - 1, hitCount: hitCount))
            let slice: [BattleEvent] = [event] + reading.events
            let contact: TimeInterval = timeline.times.first ?? walkUp + contract * 0.5
            let castHold: TimeInterval = timeline.hold(after: 0, in: slice, elapsed: 0) ?? contact
            holdOverride = castHold
            // What is left of the clip once the cast has held: every later
            // event's hold comes off it, the hits' included, and the next
            // turn repays the rest.
            castRecovery = max(0, walkUp + contract - castHold)
            if !timeline.times.isEmpty { beginCastTimeline(timeline, events: slice) }
            // Stamped, so a console that ends mid-fight says which cast it
            // ended in (the arena crash of 2026-09-15 was read off the last
            // clip loaded, which is a poorer clock).
            let played = String(format: "%.2f", contract)
            Perf.note("cast \(name) by \(casterNode.spec.assetName) as \(animation) (plays \(resolved), \(played) s), \(reading.hits.count) hit(s) on \(targets.count) target(s)")

            // Each hit's time and victims, for what the cast draws (`SkillFX`);
            // a rite's release, on the cast's own targets.
            var hits: [(time: TimeInterval, victims: [UUID])] = []
            if reading.hitCount == 0 {
                hits.append((time: contact, victims: targets))
            } else {
                for struck in reading.hits {
                    hits.append((time: timeline.time(ofHit: struck.hit), victims: struck.victims))
                }
            }
            let plan = CastPlan(actor: actor, skillID: skillID, name: name, targets: targets, shot: shot,
                                animation: animation, resolved: resolved, vfx: vfx, closes: closes, landing: landing,
                                leap: leap, walkUp: walkUp, contact: contact, clipEnd: walkUp + contract, hits: hits,
                                isRite: reading.hitCount == 0, isArea: isArea)
            // AN ULTIMATE OWNS THE SCREEN FIRST (Docs/FEEL.md W2.1): the
            // world held under the caster's card and the skill's name, and
            // only then the cast. The splash's length is handed back as
            // time the world stood still, so the queue still presents the
            // damage on the contact frame — the hold is added in front of
            // the clip, never inside it.
            if animation == .ultimate, let splash = splashCue(for: actor, skillName: name) {
                return holdForCutIn(splash, then: plan)
            }
            // With the splash off (or spent, under "First each fight") an
            // ultimate still arrives as light: the same two-frame exposure
            // punch the splash ends on (W2.9).
            if animation == .ultimate, let punch = director?.exposurePunch() {
                queueImpact(punch)
            }
            performCast(plan)

        case .damage(let source, let target, let amount, let isCritical, let isGlancing, _, let remaining, let hitIndex, let hitCount):
            guard let node = unitNodes[target] else { return 0 }

            // How hard did that land? Lethal beats critical beats the clip.
            let lethal = remaining <= 0
            let weight: HitWeight
            if lethal {
                weight = .lethal
            } else if isCritical {
                weight = .critical
            } else if Self.landsHeavy(lastCastClip, hitIndex: hitIndex, hitCount: hitCount) {
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
            if punches, let grade = director?.impactFrame() {
                queueImpact(grade)
            }
            if punches {
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
            // A cast's timeline gives its hits their own holds, each on its
            // contact, and keeps this dwell for its last (`CastTimeline`).
            switch weight {
            case .lethal: holdOverride = CastTimeline.lethalDwell
            case .critical: holdOverride = CastTimeline.criticalDwell
            case .heavy: holdOverride = CastTimeline.heavyDwell
            case .normal, .light: break
            }

            guard finalBlow else {
                return Juice.impact(weight, colour: lastCastColour, share: damageShare(amount, of: target),
                                    early: early, ultimate: lastCastWasUltimate, victim: node,
                                    striker: unitNodes[source]?.chestWorldPosition,
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
            holdIsFinalBlow = true
            return freeze + slow

        case .healed(_, let target, let amount, let remaining):
            guard let node = unitNodes[target] else { return 0 }
            node.setHealth(fraction: healthFraction(remaining: remaining, node: node))
            floatText("+\(Int(amount.rounded()))", over: node, color: UIColor(hex: "#7FE8A0")!)
            // The rite's look lands on each ally with its own event
            // (2026-09-25): the painted heal standing on the healed, with the
            // green motes, once it ships; the lotus until then.
            let healGreen = UIColor(hex: "#7FE8A0") ?? .green
            if VFXLibrary.supportColumn("heal", feet: node.position, in: scene, height: node.spec.height) {
                VFXLibrary.risingMotes(at: node.position, in: scene, tint: healGreen, count: 30, scale: 1)
            } else {
                VFXLibrary.spawn("heal", at: node.position, in: scene, tint: healGreen)
            }
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
            // The painted column of the status's kind once it ships — a
            // shield's dome, a buff's rising light, a debuff's chains — and
            // the motes until then (2026-09-25).
            let column: String
            if kind == .shield {
                column = "shield"
            } else {
                column = kind.isBuff ? "buff" : "debuff"
            }
            if !VFXLibrary.supportColumn(column, feet: node.position, in: scene, height: node.spec.height) {
                VFXLibrary.spawn(kind.isBuff ? "buff" : "debuff", at: node.position, in: scene, tint: .white)
            }
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

        case .statusExpired(let target, let kind):
            unitNodes[target]?.removeStatus(kind)

        case .statusRemoved(let target, let kind, let byStrip):
            // A debuff taken off by a cleanse is WIPED off its plate
            // (Docs/FEEL.md W2.22); a buff stripped by an enemy, a shield
            // broken, an endure spent or a bomb gone off shrink away.
            let cleansed: Bool = !byStrip && !kind.isBuff && kind != .bomb
            unitNodes[target]?.removeStatus(kind, cleansed: cleansed)

        case .attackBarChanged(let target, let delta, let newValue):
            guard let node = unitNodes[target] else { return 0 }
            node.plate?.setAttackBar(newValue, animated: true)
            // A push READS (W2.22): "+25%" in blue or "−50%" in red floats
            // over its unit and stops under the bar it moved (`floatPush`).
            // It used to move the bar and nothing else, so "push back 50%"
            // read as nothing happening. A relic's quiet top-up — Ichor's as
            // its wearer's turn opens, Nemesis's on every blow its wearer
            // takes — moves the bar alone (review, 2026-09-24: a chip every
            // turn, and one per hit of a multi-hit on the same spot).
            let percent: Int? = BarPush.chipPercent(
                delta: delta,
                ichorTopUp: target == openingActor && ichorWearers.contains(target),
                nemesisGain: target == struckBefore && nemesisWearers.contains(target)
            )
            if let percent, !node.isDefeated { floatPush(percent, on: node) }

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
            // The painted resurrection standing on the risen, once it ships.
            if let node = unitNodes[target] {
                VFXLibrary.supportColumn("revive", feet: node.position, in: scene, height: node.spec.height)
            }
            AudioLibrary.shared.play(.revive)

        case .defeated(let target):
            unitNodes[target]?.markDefeated()
            AudioLibrary.shared.play(.death, volume: 0.85)

        case .waveStarted(let wave, let count, let opponents):
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
                castCards[id] = nil
                plates.removePlate(for: id)
            }
            closeOpenTotals()
            registerMaxHealth(opponents)
            // A new wave, or a raid's guard back under the wave the fight is
            // already on (`fieldWave`): only a new one is stamped.
            let bossArrives = opponents.contains(where: \.isBoss)
            let stamped = WaveStamp.stamps(wave: wave, onField: fieldWave, bossArrives: bossArrives)
            fieldWave = max(fieldWave, wave)
            let walk = place(combatants: opponents, entering: true)
            AudioLibrary.shared.play(bossArrives ? .bossArrival : .waveCall(for: environment.pantheon))
            // Measure the field with the new wave on it now, not at the next
            // drain: in an auto fight the queue never drains between turns,
            // so a boss arriving with the third wave was never measured and
            // the boss framing never came — three runs of frames had the
            // Colossus at the far end of the ordinary 58° shot.
            director?.frameField()
            Juice.haptic(.light)
            // The wave holds until its arrivals stand on their marks (W2.10)
            // or its boss has made its entrance (W2.11); the stamp names a
            // new wave that has no boss to announce it.
            var span: TimeInterval = event.presentationDuration
            if walk > 0 { span = max(span, walk + WalkOn.settle) }
            if entranceBoss != nil { span = max(span, BossEntrance.length + BossEntrance.settle) }
            holdOverride = span
            if stamped { showWaveStamp(wave: wave, count: count) }

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

    // MARK: - Drawing a cast

    /// What a cast puts on the field, worked out as it is presented
    /// (`present`, `.skillCast`) and drawn by `performCast`: at once, or —
    /// for an ultimate that owns the screen first — when its splash lets go
    /// (`holdForCutIn`).
    private struct CastPlan {
        let actor: UUID
        let skillID: String
        let name: String
        let targets: [UUID]
        let shot: CameraShot
        /// The clip the skill asked for (the engine's), and the one that
        /// really plays for it (`ModelLibrary.resolvedClip`).
        let animation: AnimationClip
        let resolved: AnimationClip
        let vfx: String
        /// Whether a melee caster leaps at its victim first, where it lands,
        /// and the leap's authored length.
        let closes: Bool
        let landing: SCNVector3?
        let leap: TimeInterval
        /// Authored seconds from the start of the cast to the clip's start,
        /// to its first blow, and to its end.
        let walkUp: TimeInterval
        let contact: TimeInterval
        let clipEnd: TimeInterval
        /// Each hit's authored time and victims (`CastReading`); a rite's
        /// release on its targets.
        let hits: [(time: TimeInterval, victims: [UUID])]
        /// No damage (a rite), and a strike on the whole line.
        let isRite: Bool
        let isArea: Bool
    }

    /// Draws a cast: the camera's move, the leap, the clip, the banner, an
    /// ultimate's spotlight round its caster through the wind-up (W2.9), and
    /// everything the cast itself draws, hit by hit — the circle it stands
    /// on, the blade's trail, the shots, the bursts, a line's pillars, an
    /// ultimate's signature and every sound of it — which is `SkillFX`'s
    /// (2026-09-25): the one burst on the first contact that stood here is
    /// that file's fallback now.
    private func performCast(_ plan: CastPlan) {
        guard let casterNode = unitNodes[plan.actor] else { return }
        let targetNode = plan.targets.first.flatMap { unitNodes[$0] }
        let animation = plan.animation
        Juice.prepareHaptics()
        // A leap is heard. Every other sound of the cast is its own, timed
        // to its blows (`SkillFX`: a swing at each, a spell's release, a
        // string's loose, an ultimate's gathering swell and its boom).
        if plan.closes { AudioLibrary.shared.play(.whoosh, volume: 0.5) }
        // THE ULTIMATE'S CAMERA (Summoners War's): the push on the caster
        // holds until the first contact, then dollies home over 0.3 s as the
        // blow lands, so the big effect is seen in the home frame. Every
        // other shot is as it was.
        let holdUntil: TimeInterval? = animation == .ultimate ? beat(plan.contact) : nil
        director?.perform(plan.shot, on: casterNode, target: targetNode, focus: plan.landing, holdUntil: holdUntil)
        if let targetNode, plan.closes {
            casterNode.dash(toward: targetNode, duration: beat(plan.leap))
        }
        // The clip the skill asked for: the unit plays the one its family
        // ships, down the fallback chain, through the same resolution the
        // times above were read off.
        casterNode.play(animation, after: beat(plan.walkUp))
        if animation == .ultimate {
            // THE SPOTLIGHT (Docs/FEEL.md W2.9): the set's lights fall to
            // 35% round the caster, the painting to 0.45 and the colour
            // 0.35, the figures keeping their light, until the blow lands
            // (`present`, the next event) and 0.4 s after it.
            beginSpotlight(.ultimate, attack: beat(Spotlight.attack), longest: Spotlight.longest + tourHoldAllowance())
            spotlightAwaitsBlow = true
            holdSpotlightForTour(contact: plan.contact)
        }
        // The skill's BANNER over its caster (Docs/FEEL.md W1.9, the
        // owner's Summoners War frame): its painted icon in a gold frame
        // beside its name, followed through the leap (a plain name hung
        // over the EMPTY mark a closing caster had left, run 220). It
        // replaces the plain name that floated here in pale gold. Not for
        // an ultimate: the splash is its name (W2.1), and the two at once
        // put it on the screen twice.
        if animation != .ultimate {
            floatBanner(plan.name, iconKey: skillArt[plan.actor]?[plan.skillID], over: casterNode)
        }
        // Everything the cast draws, hit by hit, each piece timed as a scene
        // action (a freeze holds it with the clip) and each victim found as
        // its hit lands, never where it stood when the cast began.
        let family = casterNode.spec.assetName
        let cast = CastFX(caster: casterNode, element: casterNode.element, clip: plan.resolved, vfx: plan.vfx,
                          family: family, isUltimate: animation == .ultimate, isRite: plan.isRite,
                          isArea: plan.isArea, ranged: !casterNode.spec.melee,
                          archer: SkillFX.archers.contains(family), walkUp: plan.walkUp, hits: plan.hits,
                          clipEnd: plan.clipEnd)
        SkillFX.play(cast, in: scene, node: { [weak self] id in self?.unitNodes[id] },
                     beat: { [weak self] seconds in self?.beat(seconds) ?? seconds })
    }

    // MARK: - The ultimate's splash (Docs/FEEL.md W2.1)

    /// The splash an ultimate cast now would play, or nil: the player's
    /// choice (`UltimateSplash.choice`: always, each unit's first in the
    /// fight, or never), at the form the speed allows.
    private func splashCue(for actor: UUID, skillName: String) -> UltimateSplashCue? {
        guard UltimateSplash.plays(UltimateSplash.choice(), castBefore: splashedCasters.contains(actor)),
              let card = castCards[actor] else { return nil }
        splashedCasters.insert(actor)
        splashSerial += 1
        let form = UltimateSplash.form(speed: speedMultiplier)
        return UltimateSplashCue(serial: splashSerial, portrait: card.portrait, unitName: card.name, skillName: skillName,
                                 accentHex: card.accentHex, form: form, duration: UltimateSplash.duration(of: form),
                                 frozenFor: tourSplashHold())
    }

    /// Holds the world for an ultimate's splash and returns how long, for
    /// the queue to add to the cast's hold as time the world stood still:
    /// the scene paused (`Juice.holdWorld`) with every clip and action in
    /// it, the plates dimmed under the band, the view told (`onFieldCue`),
    /// the band's whoosh; the sting and the heavy haptic as the name lands;
    /// and at its end the world let go on a two-frame exposure punch — the
    /// fight's own light where the white full-screen flash used to be
    /// (W2.9) — and the cast drawn (`performCast`), strictly before its clip
    /// starts. A skip or a forfeit in between (the generation) leaves the
    /// cast undrawn and `cancelBeats` takes the splash down.
    private func holdForCutIn(_ cue: UltimateSplashCue, then plan: CastPlan) -> TimeInterval {
        let generation = playbackGeneration
        let hold = Juice.holdWorld(scene)
        plates.setPlatesDimmed(true)
        onFieldCue?(.splash(cue))
        AudioLibrary.shared.play(.whoosh, volume: 0.7)
        let element = unitNodes[plan.actor]?.element
        DispatchQueue.main.asyncAfter(deadline: .now() + UltimateSplash.landing(of: cue.form)) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            // The sting: a summon's burst over the caster's element.
            AudioLibrary.shared.play(.summonBurst, volume: 0.55)
            if let element {
                AudioLibrary.shared.play(Juice.HitColour.element(element).sound, volume: 0.5, delay: 0.02)
            }
            Juice.haptic(.heavy)
        }
        #if DEBUG
        if cue.frozenFor > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + cue.duration * 0.5 + 0.2) { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                print("[TourCue] cutin")
            }
        }
        #endif
        let span: TimeInterval = cue.duration + cue.frozenFor
        DispatchQueue.main.asyncAfter(deadline: .now() + span) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            Juice.releaseWorld(self.scene, hold: hold)
            self.plates.setPlatesDimmed(false)
            self.onFieldCue?(.splashEnded(cue.serial))
            if let punch = self.director?.exposurePunch() { self.queueImpact(punch) }
            self.performCast(plan)
        }
        return span
    }

    /// Decodes, off the main thread and at the size the band draws them, the
    /// cards of the fighters whose ultimate's splash may play next — the
    /// battle's model names them as it hands the scene a turn's events
    /// (`BattleViewModel.splashCasters`: every ultimate the turn casts, and
    /// the unit the engine now waits on when its ultimate is ready) — so the
    /// decode (tens of milliseconds for a 1,024-pixel card) never lands on
    /// the splash's first frame. Only where a splash would draw one: the
    /// player's choice lets this caster's play (`UltimateSplash.plays`) and
    /// the speed draws the band, not the ×3 name flash, which has no card.
    /// It used to decode every fighter's card at each of its turns, four
    /// megabytes apiece kept in the thumbnail cache, whatever the setting
    /// (review, 2026-09-24).
    func warmSplashCards(for casters: [Combatant]) {
        guard UltimateSplash.form(speed: speedMultiplier) != .flash else { return }
        let choice = UltimateSplash.choice()
        var names: [String] = []
        for caster in casters where UltimateSplash.plays(choice, castBefore: splashedCasters.contains(caster.id)) {
            let name = caster.model.portraitName(awakened: caster.isAwakened)
            if !names.contains(name) { names.append(name) }
        }
        guard !names.isEmpty else { return }
        let cards: [String] = names
        DispatchQueue.global(qos: .userInitiated).async {
            BundleArt.warmThumbnails(cards, maxPixel: UltimateSplash.cardPixels)
        }
    }

    // MARK: - The spotlight (Docs/FEEL.md W2.9, W2.11)

    /// Dims the set to `look` over `attack` seconds and holds it there until
    /// `releaseSpotlight` (or `longest`). Nothing without a rig: under
    /// `-tour-layers off` the set and the figures share their lights, and a
    /// dim would darken the caster with the stone.
    private func beginSpotlight(_ look: SpotlightLook, attack: TimeInterval, longest: TimeInterval = Spotlight.longest) {
        firstFramesLock.lock()
        defer { firstFramesLock.unlock() }
        guard spotlightRig != nil else { return }
        spotlightTimeline = SpotlightTimeline(look: look, began: CACurrentMediaTime(), attack: max(0.01, attack),
                                              longest: longest, release: Spotlight.releaseAfterBlow)
    }

    /// Lets the set come back up over `seconds`, from wherever the dim
    /// stands; a dim already coming back is left to it.
    private func releaseSpotlight(over seconds: TimeInterval) {
        firstFramesLock.lock()
        defer { firstFramesLock.unlock() }
        guard var timeline = spotlightTimeline else { return }
        let now = CACurrentMediaTime()
        guard now < timeline.letGo else { return }
        timeline.releasedAt = now
        timeline.release = max(0.01, seconds)
        spotlightTimeline = timeline
    }

    /// The set's lights back at once, on the next frame the renderer draws.
    private func endSpotlight() {
        firstFramesLock.lock()
        if spotlightTimeline != nil { spotlightRestoreDue = true }
        spotlightTimeline = nil
        firstFramesLock.unlock()
    }

    // MARK: - A boss's entrance (Docs/FEEL.md W2.11)

    /// A boss's entrance, 2.4 s at ×1: the HUD fades and the key light dims
    /// 40% (`.bossEntrance`); the ground rumbles as the boss climbs through
    /// the rim's dust and thrown stone from `BossEntrance.depth` below it,
    /// fading up; at 1.2 s it ROARS in its heavy attack — a big shake and a
    /// heavy thump in the hand — and its wine ribbon lands with its name and
    /// epithet (a Titan's weakness on it) while its bar fills from empty;
    /// then the lights and the HUD come back. Scene actions on the boss,
    /// keyed, so a hit-stop or a CI frame's hold pauses it and `cancelBeats`
    /// ends it. Under Reduce Motion it fades up on its mark instead of
    /// climbing (the camera's shake already keeps still there). Returns its
    /// length on the wall clock and the breath after it, the queue's wait.
    @discardableResult
    private func beginBossEntrance(_ node: UnitNode) -> TimeInterval {
        guard let home = homeMarks[node.combatantID] else { return 0 }
        entranceSerial += 1
        let serial = entranceSerial
        let generation = playbackGeneration
        entranceBoss = node
        let span = beat(BossEntrance.length)
        let roarAt = beat(BossEntrance.roarAt)
        onFieldCue?(.bossEntrance(BossEntranceCue(serial: serial, bossID: node.combatantID)))
        beginSpotlight(.bossEntrance, attack: beat(0.3), longest: span + Spotlight.longest + tourHoldAllowance())
        node.removeAction(forKey: "boss_entrance")
        node.opacity = 0
        let rise: SCNAction
        if MotionComfort.isReduced {
            node.position = home
            rise = .fadeIn(duration: beat(0.6))
        } else {
            node.position = SCNVector3(home.x, home.y - BossEntrance.depth, home.z)
            let climb = SCNAction.move(to: home, duration: roarAt)
            climb.timingMode = .easeOut
            rise = .group([climb, .fadeIn(duration: beat(0.5))])
        }
        let rim = SCNVector3(home.x, 0, home.z)
        VFXLibrary.rimDust(at: rim, in: scene, tint: rimDustTint, width: node.spec.height * 0.6)
        // The ground rumbles under the team as it climbs: trauma held at a
        // floor for the climb (W2.18), on the lens, so the wave's re-framing
        // (`.waveStarted` measures the field with the boss on it once it is
        // placed) moves the rig under it without cutting it short.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.playbackGeneration == generation, self.entranceSerial == serial else { return }
            self.director?.rumble(BossEntrance.rumbleTrauma, for: roarAt)
        }
        // SceneKit runs these blocks on its render thread: they only hop.
        let roars = SCNAction.run { [weak self, weak node] _ in
            DispatchQueue.main.async {
                guard let self, let node, self.playbackGeneration == generation else { return }
                self.roar(node, serial: serial)
            }
        }
        let end = SCNAction.run { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.endBossEntrance(serial)
            }
        }
        node.runAction(.sequence([rise, roars, .wait(duration: max(0, span - roarAt)), end]), forKey: "boss_entrance")
        return span + beat(BossEntrance.settle)
    }

    /// The roar: its heavy attack played where it towers, the shake, the
    /// thump, a second burst of dust off the rim, and the ribbon.
    private func roar(_ node: UnitNode, serial: Int) {
        guard serial == entranceSerial, !node.isDefeated else { return }
        node.play(.attackHeavy)
        director?.addTrauma(BossEntrance.roarTrauma, speed: speedMultiplier)
        Juice.haptic(.heavy)
        AudioLibrary.shared.play(.hitHeavy, volume: 0.9)
        if let home = homeMarks[node.combatantID] {
            VFXLibrary.rimDust(at: SCNVector3(home.x, 0, home.z), in: scene, tint: rimDustTint,
                               width: node.spec.height * 0.6, strength: 0.5)
        }
        onFieldCue?(.bossRibbon(serial))
        holdRibbonForTour()
    }

    private func endBossEntrance(_ serial: Int) {
        guard serial == entranceSerial, entranceBoss != nil else { return }
        entranceBoss = nil
        releaseSpotlight(over: beat(0.5))
        onFieldCue?(.entranceEnded(serial))
    }

    /// The dust a boss throws off the rim: the set's own dust, taken toward
    /// a stone grey.
    private var rimDustTint: UIColor {
        let dust = UIColor(hex: StageBuilder.recipe(for: environment).dustHex) ?? .white
        return dust.mixed(with: UIColor(white: 0.42, alpha: 1), amount: 0.55)
    }

    // MARK: - A wave's stamp (Docs/FEEL.md W2.10)

    /// WAVE 2, or FINAL WAVE, carved and sweeping across as the arrivals
    /// walk on, with a drum as it lands (the realm's horn has already
    /// called the wave). Half its length at ×2 and ×3, where at ×3 it is
    /// all of the arrival that plays; the thumb only at ×1 and ×2.
    private func showWaveStamp(wave: Int, count: Int) {
        stampSerial += 1
        let length = WaveStamp.length(speed: speedMultiplier)
        let frozen = tourStampHold()
        onFieldCue?(.waveStamp(WaveStampCue(serial: stampSerial, wave: wave, count: count, duration: length,
                                            frozenFor: frozen)))
        let generation = playbackGeneration
        let fast = Juice.isFast(speedMultiplier)
        DispatchQueue.main.asyncAfter(deadline: .now() + length * WaveStamp.landsAt) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            AudioLibrary.shared.play(.hitBlunt, volume: 0.8)
            if !fast { Juice.haptic(.medium) }
            #if DEBUG
            if frozen > 0 { self.freezeForTour(frozen, cue: "wave-stamp") }
            #endif
        }
    }

    // MARK: - Leaving the field (Docs/FEEL.md W2.8)

    /// A fallen unit leaves the field once its death has played
    /// (`UnitNode.onFallen`): the body fades over 0.7 s as a column of its
    /// element's motes rises out of it, a small soul light lifts 2 m and
    /// winks out with a chime, and a faint glyph of its element stays on its
    /// mark until a revive — a tap on it reaches the unit, so a reviver's
    /// target is where the body lay. A boss sinks back below the rim in
    /// dust instead. ×2 halves it all; ×3 keeps the fade, a sparser column
    /// and the glyph; Reduce Motion keeps all but the rising light. No
    /// shader anywhere in it (the run-235 rule): an opacity, particles and
    /// quads.
    private func leaveTheField(_ node: UnitNode) {
        guard unitNodes[node.combatantID] === node, node.isDefeated else { return }
        let feet = node.position
        if node.isBoss {
            let sink = beat(Dissolve.bossSink)
            node.sinkBelowRim(over: sink)
            VFXLibrary.rimDust(at: SCNVector3(feet.x, 0, feet.z), in: scene, tint: rimDustTint,
                               width: node.spec.height * 0.6, strength: 0.8)
            director?.rumble(BossEntrance.rumbleTrauma * 1.2, for: sink * 0.7)
            AudioLibrary.shared.play(.hitBlunt, volume: 0.6)
            return
        }
        let tint = UIColor(hex: node.element.accentHex) ?? .white
        let fade = beat(Dissolve.fade)
        node.dissolveBody(over: fade)
        VFXLibrary.soulColumn(at: feet, in: scene, tint: tint, height: node.spec.height, duration: fade,
                              sparse: Juice.isFast(speedMultiplier))
        if Dissolve.showsSoulLight(speed: speedMultiplier, calm: MotionComfort.isReduced) {
            let start = SCNVector3(feet.x, feet.y + node.spec.height * 0.3, feet.z)
            VFXLibrary.soulLight(from: start, in: scene, tint: tint, rise: Dissolve.soulRise,
                                 duration: beat(Dissolve.soulFlight), size: CGFloat(node.spec.height) * 0.22) {
                AudioLibrary.shared.play(.starTick, volume: 0.45)
            }
        }
        let pale: CGFloat = StageBuilder.isPaleSet(environment) ? Dissolve.paleMarkShare : 1
        node.leaveMark(opacity: Dissolve.markOpacity * pale, fade: beat(Dissolve.markFade))
        holdDissolveForTour(node, fade: fade)
    }

    // MARK: - The stage, seen (the veil)

    /// Runs `action` once this build's stage has been drawn, or now if it
    /// has: an opening boss's entrance, a CI lab.
    private func whenStageShown(_ action: @escaping () -> Void) {
        if stageIsShown {
            action()
        } else {
            stageShownActions.append(action)
        }
    }

    /// Main thread: this build's stage has been drawn (or the wait for it
    /// ran out): whatever waited to be seen begins.
    private func runStageShownActions() {
        guard !stageIsShown else { return }
        stageIsShown = true
        let waiting = stageShownActions
        stageShownActions.removeAll()
        for action in waiting { action() }
    }

    /// The longest a build waits to be seen before what waits for it begins
    /// anyway: the battle view's veil lifts by its own limit then too
    /// (`BattleView.veilLimit`), and an opening boss must never hold the
    /// fight for good behind a renderer that draws nothing.
    static let stageShownLimit: TimeInterval = 5

    // MARK: - The CI labs (-tour-cutin, -tour-waves, -tour-dissolve)

    /// How long a lab holds its beat: a simulator screenshot of a live
    /// fight lands six to nine seconds after it is asked for (run 245), so
    /// a beat is held long past that for its frame.
    static let tourHold: TimeInterval = 16

    #if DEBUG
    private static let tourArguments = ProcessInfo.processInfo.arguments
    /// `-tour-cutin`: the first splash stands at its middle, and then its
    /// caster's wind-up under the spotlight (the view model casts the first
    /// ultimate the player has, `BattleViewModel.castTourUltimate`).
    private static let touringCutIn = tourArguments.contains("-tour") && tourArguments.contains("-tour-cutin")
    /// `-tour-waves`: the first WAVE stamp over its walkers, and the first
    /// boss's ribbon over its roar.
    private static let touringWaves = tourArguments.contains("-tour") && tourArguments.contains("-tour-waves")
    /// `-tour-dissolve`: an enemy falls three seconds after the stage is
    /// seen, the scene's picture only, and is held half dissolved.
    private static let touringDissolve = tourArguments.contains("-tour") && tourArguments.contains("-tour-dissolve")
    /// `-tour-status`: statuses landing and bars pushed, held at the pop.
    private static let touringStatus = tourArguments.contains("-tour") && tourArguments.contains("-tour-status")
    /// `-tour-shake`: the camera held at the shake's peak.
    private static let touringShake = tourArguments.contains("-tour") && tourArguments.contains("-tour-shake")

    /// Holds the world `seconds` for a CI frame, and the queue with it —
    /// the event now playing keeps what was left of its hold after the
    /// frame — and prints the cue the job waits on.
    private func freezeForTour(_ seconds: TimeInterval, cue: String) {
        let hold = Juice.holdWorld(scene)
        let generation = playbackGeneration
        let base: CFTimeInterval = max(queueHeldUntil, queueDueAt, CACurrentMediaTime())
        queueHeldUntil = base + seconds
        print("[TourCue] \(cue)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            Juice.releaseWorld(self.scene, hold: hold)
        }
    }
    #endif

    /// The first splash's hold under `-tour-cutin`; nothing otherwise.
    private func tourSplashHold() -> TimeInterval {
        #if DEBUG
        guard Self.touringCutIn, !tourCutInSpent else { return 0 }
        tourCutInSpent = true
        return Self.tourHold
        #else
        return 0
        #endif
    }

    /// Under `-tour-cutin`, the wind-up after the held splash is held too,
    /// three fifths of the way to its blow, with the set dimmed round it.
    private func holdSpotlightForTour(contact: TimeInterval) {
        #if DEBUG
        guard Self.touringCutIn, tourCutInSpent, !tourSpotlightSpent else { return }
        tourSpotlightSpent = true
        let generation = playbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + beat(contact) * 0.6) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.freezeForTour(Self.tourHold - 2, cue: "spotlight")
        }
        #endif
    }

    /// The first WAVE stamp's hold under `-tour-waves`; nothing otherwise.
    private func tourStampHold() -> TimeInterval {
        #if DEBUG
        guard Self.touringWaves, !tourStampSpent else { return 0 }
        tourStampSpent = true
        return Self.tourHold - 2
        #else
        return 0
        #endif
    }

    /// What a dim may be held for under a lab that holds its beat (the
    /// ultimate's wind-up under `-tour-cutin`, the roar under `-tour-waves`),
    /// so the set stays dark through the frame; nothing otherwise.
    private func tourHoldAllowance() -> TimeInterval {
        #if DEBUG
        return Self.touringCutIn || Self.touringWaves ? Self.tourHold : 0
        #else
        return 0
        #endif
    }

    /// Under `-tour-waves`, the first ribbon is held a moment after it lands,
    /// over the roar.
    private func holdRibbonForTour() {
        #if DEBUG
        guard Self.touringWaves, !tourRibbonSpent else { return }
        tourRibbonSpent = true
        let generation = playbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.freezeForTour(Self.tourHold - 2, cue: "boss-ribbon")
        }
        #endif
    }

    /// Under `-tour-dissolve`, three seconds after the stage is seen the
    /// first standing enemy falls — the scene's picture only; the engine
    /// fights on — and `holdDissolveForTour` holds its dissolve half way.
    private func startTourDissolve() {
        #if DEBUG
        guard Self.touringDissolve else { return }
        let serial = buildSerial
        whenStageShown { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.buildSerial == serial else { return }
                let standing = self.unitNodes.values.filter { $0.side == .opponent && !$0.isBoss && !$0.isDefeated }
                guard let victim = standing.min(by: { $0.position.x < $1.position.x }) else { return }
                self.tourDissolveVictim = victim.combatantID
                victim.markDefeated()
            }
        }
        #endif
    }

    /// `-tour-status` (Docs/FEEL.md W2.22): three seconds after the stage is
    /// seen, the leftmost enemy takes a Defence Down and a stun, the enemy
    /// beside it is pushed back 50%, and the first of the team takes an
    /// Attack Up and is pushed forward 25%, as the engine's events would put
    /// them; the plates are held at the top of the tiles' pop, the chips at
    /// rest under their plates and the stun's stars round the head, and
    /// `[TourCue] status` says so.
    private func startTourStatusDrill() {
        #if DEBUG
        guard Self.touringStatus else { return }
        let serial = buildSerial
        whenStageShown { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.buildSerial == serial else { return }
                self.tourStatusBeat()
            }
        }
        #endif
    }

    #if DEBUG
    private func tourStatusBeat() {
        let enemies = unitNodes.values.filter { $0.side == .opponent && !$0.isBoss && !$0.isDefeated }
        let team = unitNodes.values.filter { $0.side == .player && !$0.isDefeated }
        let row = enemies.sorted { $0.position.x < $1.position.x }
        guard let enemy = row.first else { return }
        enemy.applyStatus(.defenseDown, turns: 2)
        enemy.applyStatus(.stun, turns: 1)
        // The push on the NEXT enemy where there is one: a chip rests under
        // its plate, over the head, and on the stunned one it would lie over
        // the stars the frame is there to judge.
        let pushed = row.count > 1 ? row[1] : enemy
        floatPush(-50, on: pushed, hold: Self.tourHold)
        if let ally = team.min(by: { $0.position.x < $1.position.x }) {
            ally.applyStatus(.attackUp, turns: 3)
            floatPush(25, on: ally, hold: Self.tourHold)
        }
        // The tiles grow to 1.28 over 0.11 s: held a beat into it. The
        // chips are floats, placed from their age every frame: they rise to
        // rest under their plates through the hold (`hold`). The stun's
        // stars are held at full strength (`holdForTour` settles a mark's
        // fade-in, which the hold would have caught half way).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self else { return }
            self.plates.holdForTour(Self.tourHold)
            self.freezeForTour(Self.tourHold, cue: "status")
        }
    }
    #endif

    /// `-tour-shake` (Docs/FEEL.md W2.18): three seconds after the stage is
    /// seen the camera stands at the shake's PEAK — the most roll, yaw,
    /// pitch and shift full trauma can reach, all at once — held for the
    /// frame, `[TourCue] shake`: the frame the owner judges "slanted" on.
    private func startTourShakeDrill() {
        #if DEBUG
        guard Self.touringShake else { return }
        let serial = buildSerial
        whenStageShown { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.buildSerial == serial else { return }
                self.director?.shaker.pinPeak(for: Self.tourHold)
                self.freezeForTour(Self.tourHold, cue: "shake")
            }
        }
        #endif
    }

    private func holdDissolveForTour(_ node: UnitNode, fade: TimeInterval) {
        #if DEBUG
        guard tourDissolveVictim == node.combatantID else { return }
        tourDissolveVictim = nil
        let generation = playbackGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + fade * 0.45) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.freezeForTour(Self.tourHold - 2, cue: "dissolve")
        }
        #endif
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

    /// The units wearing the two sets that top a bar up on their own clock
    /// (Docs/FEEL.md W2.22, `BarPush`): Ichor as each of the wearer's turns
    /// opens, Nemesis on every blow the wearer takes.
    private var ichorWearers: Set<UUID> = []
    private var nemesisWearers: Set<UUID> = []
    /// What the event just presented was, for the push chips: the unit a hit
    /// struck, and the unit whose turn is opening — from its `.turnBegan`
    /// until its cast or its skip. Main thread.
    private var lastStruck: UUID?
    private var openingActor: UUID?

    func registerMaxHealth(_ combatants: [Combatant]) {
        for combatant in combatants {
            maxHealthByUnit[combatant.id] = combatant.maxHealth
            if combatant.hasRelicSet(.ichor) { ichorWearers.insert(combatant.id) }
            if combatant.hasRelicSet(.nemesis) { nemesisWearers.insert(combatant.id) }
        }
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
        // Each head a mark may circle (W2.22): the crown as the plate reads
        // it, before the declutter lifts the plate off it.
        var markPlaces: [UUID: (point: CGPoint, scale: CGFloat)] = [:]
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
            if onScreen, !node.isDefeated {
                markPlaces[key] = (point: CGPoint(x: CGFloat(projected.x),
                                                  y: height - CGFloat(projected.y) - Self.markBelowCrown),
                                   scale: 1)
            }
        }
        // A boss wears no plate, but a stun still circles its head, larger.
        for boss in bosses where !boss.isDefeated {
            let feet = boss.worldPosition
            let crown = renderer.projectPoint(SCNVector3(feet.x, feet.y + boss.spec.height * 0.95, feet.z))
            guard crown.z > 0, crown.z < 1 else { continue }
            markPlaces[boss.combatantID] = (point: CGPoint(x: CGFloat(crown.x), y: height - CGFloat(crown.y)),
                                            scale: Self.bossMarkScale)
        }
        plates.placeHeadMarks(markPlaces)

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

    /// The impact frame (Docs/FEEL.md W1.3) is put on the camera and taken
    /// off it on the renderer's thread, in `renderUpdate` (the coordinator's
    /// `renderer(_:updateAtTime:)`, where SceneKit applies a change
    /// directly), `impactFrames` drawn frames apart, counted in `frameDrawn`
    /// under the veil's lock. The main thread only queues the two changes
    /// (`CameraDirector.impactFrame`): run 245's 8-b photographed the arena
    /// held grey under THUNDERCLAP while a restore queued on the main queue
    /// waited out a stall, and a restore written on the render thread could
    /// land before a punch still waiting in the main thread's transaction.
    static let impactFrames = 2
    /// The shake and the lens it moves (Docs/FEEL.md W2.18), for the
    /// renderer's thread under `firstFramesLock`: set with each camera
    /// (`buildCamera`), dropped with it.
    private var shakeTarget: (shaker: CameraShake, lens: SCNNode)?
    /// Told on the main thread of each camera a build makes: it hangs under
    /// a rig now, so the view makes it the point of view by name rather
    /// than trusting SceneKit's search for the first camera in the graph.
    var onCameraBuilt: ((SCNNode) -> Void)?
    /// The camera the last build made, for a view made after it.
    var currentLens: SCNNode? { cameraNode.camera == nil ? nil : cameraNode }
    /// A still of the field from the view (Docs/FEEL.md W2.2): set by
    /// `BattleSceneView` to the view's own `snapshot()`, nil without a view.
    var snapshotter: (() -> UIImage?)?

    /// The field as the view last drew it, for the reward box's backdrop.
    /// Main thread.
    func snapshotField() -> UIImage? { snapshotter?() }
    private var impactPunch: (() -> Void)?
    private var impactRestore: (() -> Void)?
    private var impactFramesLeft = 0
    private var impactRestoreDue = false

    /// Main thread: the next frame the renderer prepares wears `punch`, and
    /// `restore` follows `impactFrames` drawn frames later. A later impact
    /// replaces an earlier one's pair; the camera's rest grade is the same.
    private func queueImpact(_ grade: (punch: () -> Void, restore: () -> Void)) {
        firstFramesLock.lock()
        impactPunch = grade.punch
        impactRestore = grade.restore
        impactFramesLeft = 0
        impactRestoreDue = false
        firstFramesLock.unlock()
    }

    /// Main thread: a queued or pending impact is dropped — the field's
    /// colour is draining (the drain puts the grade back itself), or a new
    /// run builds a new camera.
    private func cancelImpact() {
        firstFramesLock.lock()
        impactPunch = nil
        impactRestore = nil
        impactFramesLeft = 0
        impactRestoreDue = false
        firstFramesLock.unlock()
    }

    /// The renderer's thread, before each frame's animations
    /// (`BattleSceneView.Coordinator`, `renderer(_:updateAtTime:)`): the
    /// impact frame's punch goes on, or its restore once it is due; and the
    /// camera's shake is written on the lens for this frame (W2.18), before
    /// the plates are laid out from it (`layoutPlates`, in
    /// `willRenderScene`), so the bars shake with the world they hang over.
    func renderUpdate(at time: TimeInterval) {
        firstFramesLock.lock()
        let shake = shakeTarget
        let punch = impactPunch
        impactPunch = nil
        var restore: (() -> Void)?
        if punch != nil {
            impactFramesLeft = Self.impactFrames
            impactRestoreDue = false
        } else if impactRestoreDue {
            impactRestoreDue = false
            restore = impactRestore
            impactRestore = nil
        }
        // The spotlight's lights for this frame (Docs/FEEL.md W2.9, W2.11),
        // written here with the impact frame's so the two never race for
        // the camera: its colour is the spotlight's to write only outside an
        // impact frame's two frames — after a restore, in the same frame —
        // and never once a loss has taken the colour.
        let rig = spotlightRig
        var shares: SpotlightShares?
        if let timeline = spotlightTimeline {
            let now = CACurrentMediaTime()
            if timeline.isOver(at: now) {
                spotlightTimeline = nil
                shares = Spotlight.rest
            } else {
                shares = Spotlight.shares(for: timeline.look, level: timeline.level(at: now))
            }
        } else if spotlightRestoreDue {
            shares = Spotlight.rest
        }
        spotlightRestoreDue = false
        let grades: Bool = punch == nil && impactFramesLeft == 0 && !spotlightGradeHeld
        firstFramesLock.unlock()
        punch?()
        restore?()
        if let rig, let shares { rig.apply(shares, grade: grades) }
        if let shake { shake.shaker.apply(to: shake.lens, at: time, paused: scene.isPaused) }
    }

    /// The renderer's thread, after every frame (`BattleSceneView`).
    func frameDrawn() {
        firstFramesLock.lock()
        if impactFramesLeft > 0 {
            impactFramesLeft -= 1
            if impactFramesLeft == 0 { impactRestoreDue = true }
        }
        let left = framesToShow
        if let left {
            framesToShow = left > 1 ? left - 1 : nil
        }
        // The pre-draw's next step, once its frames are drawn (W2.24).
        var step: PredrawStep?
        if predrawing {
            framesSinceBuild += 1
            step = PredrawStep.step(afterFrame: framesSinceBuild, laterBoss: predrawBoss)
            if step == .retire { predrawing = false }
        }
        firstFramesLock.unlock()
        if let step {
            DispatchQueue.main.async { [weak self] in self?.stepPredraw(step) }
        }
        guard let left, left <= 1 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let told = self.onStageShown {
                self.onStageShown = nil
                told()
            }
            // And whatever waited for this build's stage to be seen: an
            // opening boss's entrance, a CI lab (W2.11) — at once with no
            // card over the stage, and as the card leaves when there is one
            // (`revealField`).
            if !self.cardHolds { self.runStageShownActions() }
        }
    }

    private func awaitFirstFrames() {
        firstFramesLock.lock()
        // A build drawing its effects in advance is seen once they have been
        // drawn and taken off (W2.24): its steps, then the frames every
        // build waits.
        let predrawFrames: Int = predraw == nil ? 0 : PredrawStep.frames(laterBoss: predrawLaterBoss)
        framesToShow = Self.framesBeforeShown + predrawFrames
        framesSinceBuild = 0
        predrawing = predraw != nil
        predrawBoss = predrawLaterBoss
        firstFramesLock.unlock()
        // Never later than the stage card's own limit: a renderer that draws
        // nothing must not hold an opening boss's entrance, and the fight
        // behind it, for good. Under a card the card's own limit reveals the
        // field (`revealField`, `StageCardTiming.limit`), and that is when
        // what waits begins.
        let serial = buildSerial
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stageShownLimit) { [weak self] in
            guard let self, self.buildSerial == serial, !self.cardHolds else { return }
            self.runStageShownActions()
        }
    }

    // MARK: - The stage card (Docs/FEEL.md W2.24)

    /// Set by the battle view before its first `begin()`: that build holds
    /// its queue for the stage card and draws `predrawPlan` under it. A
    /// build takes it and clears it, so an auto-repeat's later runs neither
    /// hold nor draw anything in advance.
    var holdsForStageCard = false
    /// What the fight can draw (`BattleViewModel.effectPlan`), for the
    /// pre-draw under the card.
    var predrawPlan: EffectPlan?
    /// This build's queue waits for the card to leave (`revealField`).
    private var cardHolds = false
    /// The pre-draw's holder while it is on the stage, the lights its step
    /// has standing, and whether a later wave brings a boss (whose warm spot
    /// is a light of its own to compile).
    private var predraw: SCNNode?
    private var predrawLights: [SCNNode] = []
    private var predrawLaterBoss = false
    /// The renderer's thread, under `firstFramesLock`: frames drawn since the
    /// build, whether the pre-draw's steps are still to come, and its boss.
    private var framesSinceBuild = 0
    private var predrawing = false
    private var predrawBoss = false

    /// Draws the fight's effects once under the stage card, at the middle of
    /// the field in front of the camera, and the plates' additive sprites
    /// with them; the lights a fight adds come in steps as frames are drawn
    /// (`stepPredraw`).
    private func beginPredraw(_ plan: EffectPlan) {
        let spot = SCNVector3(0, 1.2, StageBuilder.arenaCentre.z)
        predraw = VFXLibrary.predraw(plan, in: scene, at: spot)
        predrawLaterBoss = plan.laterBoss
        plates.predraw()
    }

    /// Main thread: the pre-draw's next step. Each stands the light count it
    /// names over the field (the effects' own stay quiet under a pre-draw),
    /// and the last takes the holder off through `retire`.
    private func stepPredraw(_ step: PredrawStep) {
        guard let holder = predraw, holder.parent != nil else { return }
        for light in predrawLights { light.removeFromParentNode() }
        predrawLights.removeAll()
        let middle = SCNVector3(0, 3, StageBuilder.arenaCentre.z)
        // Fourteen metres × 1.5 reaches the team, the enemy row and a boss
        // on the far rim from the middle of the field.
        let reach: Float = 14
        switch step {
        case .lights(let count):
            for index in 0..<count {
                let offset: Float = Float(index) * 1.5
                let at = SCNVector3(middle.x + offset, middle.y, middle.z)
                predrawLights.append(VFXLibrary.predrawLight(at: at, radius: reach, in: holder))
            }
        case .spot(let withFlash):
            let category: Int? = StageBuilder.lightLayers ? StageBuilder.figureLights : nil
            let aim = SCNVector3(0, 1.5, StageBuilder.arenaCentre.z)
            predrawLights.append(VFXLibrary.predrawSpot(aimedAt: aim, in: holder, category: category))
            if withFlash {
                predrawLights.append(VFXLibrary.predrawLight(at: middle, radius: reach, in: holder))
            }
        case .retire:
            predraw = nil
            plates.endPredraw()
            VFXLibrary.retire(holder, after: 0, reportsLive: false)
        }
    }

    /// Main thread: whatever is still drawn in advance goes this frame — the
    /// card is leaving before its steps ended (its limit, a slow renderer).
    private func finishPredraw() {
        firstFramesLock.lock()
        predrawing = false
        firstFramesLock.unlock()
        predrawLights.removeAll()
        guard let holder = predraw else { return }
        predraw = nil
        plates.endPredraw()
        VFXLibrary.dismiss(holder, reportsLive: false)
    }

    /// Main thread: the stage card is leaving (W2.24). Whatever is still
    /// drawn in advance goes, the queue the card held plays on — the fight's
    /// horn call sounds as the field appears — and what waited for the stage
    /// to be seen (an opening boss's entrance, a CI lab) begins as the card
    /// dissolves.
    func revealField() {
        finishPredraw()
        cardHolds = false
        runStageShownActions()
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

    /// An attack-bar push over its unit (Docs/FEEL.md W2.22): the chip
    /// (`PlateArt.pushChip`) as one of the unit's floats — popping at the
    /// chest and rising to stop under its plate, just under the attack bar
    /// it moved — so a second push, or a number or a status's name landing
    /// with it, stacks over it newest-lowest rather than on it, and it keeps
    /// off every other plate and the HUD as every float does
    /// (`layoutFloats`). Off the plate's right end, where it stood first, it
    /// lay across the next unit's level badge (review, 2026-09-24). A boss's
    /// stands beside its head, as its words do. Under Reduce Motion it fades
    /// in rather than pops. `hold` keeps it at rest longer, for a CI frame.
    private func floatPush(_ percent: Int, on node: UnitNode, hold: TimeInterval = 0) {
        let chip = PlateArt.pushChip(percent: percent)
        let tall = node.spec.height
        let pop = !MotionComfort.isReduced
        if node.isBoss {
            plates.addFloat(image: chip, over: node, lift: tall * 0.9, side: -tall * 0.16, align: -1,
                            pop: pop, scatter: 0, rise: 24, hold: hold)
        } else {
            plates.addFloat(image: chip, over: node, lift: tall * 0.55, pop: pop, scatter: 0, rise: 30, hold: hold)
        }
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
    /// tenth of it, so the 2.0-s pose lasts about twenty: a simulator
    /// screenshot of a live fight lands six to nine seconds after it is
    /// asked for (run 245's victory step; two to three on a still screen,
    /// build.yml's relic_awaken note), and at a quarter the pose was over
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
    static let tourPosePace: Double = 0.1

    /// Main thread, once, on a WIN's last run: survivors turn to face the
    /// camera (look(at:), yaw only) and play their own victory clip at ×1
    /// (`triumphPosePace`), whatever the fight's speed was; the
    /// camera frames the team along the home line of sight (the floor never
    /// turns); each plate swaps health for a gold EXP bar that fills from ->
    /// to, with LEVEL UP rising over a unit whose levelsGained > 0. Units
    /// missing from the map just pose.
    ///
    /// Returns the longest victory it started, in seconds of the beat
    /// (`triumphHold(forVictory:)` holds the reckoning for it), 0 for none.
    @discardableResult
    func celebrate(experience: [UUID: ExperienceGain]) -> TimeInterval {
        guard !celebrated else { return 0 }
        celebrated = true
        endSlowMotion()
        let survivors = unitNodes.values.filter { $0.side == .player && !$0.isDefeated }
        guard !survivors.isEmpty else { return 0 }
        // Where each stands when it has walked the last of the way home.
        let team = survivors.map { node in
            (position: homeMarks[node.combatantID] ?? node.position, height: node.spec.height)
        }
        let lens = director?.frameTeam(team, over: Self.triumphFraming) ?? cameraRig.position
        // The plates stand through the beat (the reckoning takes them).
        plates.setFieldHidden(false)
        let posePace = Self.triumphPosePace
        var longest: TimeInterval = 0
        for node in survivors {
            node.setHighlighted(false)
            node.setMatchup(nil)
            longest = max(longest, node.celebrate(facing: lens, turn: Self.triumphTurn, pace: posePace))
            guard let gain = experience[node.combatantID] else { continue }
            node.plate?.showExperience(from: gain.from, to: gain.to, levels: gain.levelsGained,
                                       after: Self.experienceDelay)
        }
        return longest
    }

    /// How long the reckoning waits on the field after `celebrate`: the
    /// beat's 2.4 s, or long enough for the longest victory posing to finish
    /// and settle (the mystics' bow runs about 2.9 s), never past
    /// `triumphLongest` — so the field's still behind the reward box shows
    /// the team standing, not bent double.
    static func triumphHold(forVictory window: TimeInterval) -> TimeInterval {
        min(triumphLongest, max(triumphDuration, window + triumphSettle))
    }
    static let triumphLongest: TimeInterval = 3.6
    static let triumphSettle: TimeInterval = 0.3

    /// Main thread, on a LOSS: the camera's saturation eases to 0.15 over
    /// the duration (restored when a new run is built).
    func drainColour(duration: TimeInterval) {
        endSlowMotion()
        cancelImpact()
        // The colour is the drain's from here (W2.9): a spotlight still
        // coming back up gives its lights back and never writes the
        // camera's saturation again.
        firstFramesLock.lock()
        spotlightGradeHeld = true
        firstFramesLock.unlock()
        endSpotlight()
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

/// A cast's own events, read off the queue ahead of it as it is presented
/// (Docs/PLAN.md *Skills that look like themselves*, 2026-09-25): everything
/// up to the next turn, cast, wave, end or counter — each a beat of its own
/// — and among them the caster's hits, each with its victims, in the order
/// the engine struck them. A random volley's victims are rolled per hit, so
/// they are read off the damage, never off the cast's own target list.
struct CastReading {
    /// The events after the cast, up to (not including) the boundary.
    var events: [BattleEvent] = []
    /// Each hit that landed, in order: its index in the skill and its
    /// victims (a victim a random volley struck twice is named twice).
    var hits: [(hit: Int, victims: [UUID])] = []
    /// How many hits the skill strikes, from its damage; 0 for a rite,
    /// which deals none.
    var hitCount = 0

    /// Reads a cast's events off `queue`, the events still to come after
    /// the cast itself.
    static func ahead(in queue: [BattleEvent], caster: UUID) -> CastReading {
        var reading = CastReading()
        for event in queue {
            switch event {
            case .turnBegan, .skillCast, .waveStarted, .battleEnded, .counterattack:
                return reading
            case .damage(let source, let target, _, _, _, _, _, let hit, let count):
                reading.events.append(event)
                guard source == caster else { continue }
                reading.hitCount = max(reading.hitCount, count)
                if let known = reading.hits.firstIndex(where: { $0.hit == hit }) {
                    reading.hits[known].victims.append(target)
                } else {
                    reading.hits.append((hit: hit, victims: [target]))
                }
            default:
                reading.events.append(event)
            }
        }
        return reading
    }
}

/// When each hit of a cast lands, and how long each of the cast's events
/// holds so every hit is presented on its own contact (Docs/PLAN.md *Skills
/// that look like themselves*, 2026-09-25). The engine hands a three-hit
/// skill over as three damage events after its cast, and the queue used to
/// hold each 0.30–0.55 s whatever the body was doing; the body strikes when
/// its clip says (`ClipTimings`), and this puts the numbers there.
///
/// In authored seconds from the cast's start (the leap included), before
/// the pace and with a freeze's time left out, as the clip it is timed
/// against stood still through it: the controller converts (`beat`) and
/// hands back what each hold really stood for (`elapsed`).
struct CastTimeline: Equatable {
    /// Each hit's contact, by the hit's index in the skill.
    let times: [TimeInterval]
    /// The clip's follow-through after its last contact.
    let recovery: TimeInterval
    /// Whether the skill's last hit lands heavy: it earns `heavyDwell`.
    var heavy: Bool = false

    /// Another victim of the same hit: a line struck at once reads as one
    /// blow travelling along it.
    static let victimStep: TimeInterval = 0.04
    /// What lands before the first hit (a shield's or a barrier's soak on
    /// its first victim) is pressed against the first contact this far
    /// apart, rather than spread through the wind-up before the blow.
    static let leadStep: TimeInterval = 0.02
    /// The shortest hold the timeline gives: a hold running late is made up
    /// by the next one, down to this.
    static let shortestStep: TimeInterval = 0.02
    /// The dwell after a blow worth dwelling on, by what it earned: the
    /// frame just after contact held so the shove and the shake are seen
    /// finishing before the next number (`present`'s own, the same values).
    static let heavyDwell: TimeInterval = 0.42
    static let criticalDwell: TimeInterval = 0.48
    static let lethalDwell: TimeInterval = 0.55

    /// A clip's hits at `fractions` of its `contract`, after a leap of
    /// `walkUp`: hit k at `walkUp + contract × fractions[k]`, and the clip's
    /// follow-through after its last contact.
    static func planned(walkUp: TimeInterval, contract: TimeInterval, fractions: [Double], heavy: Bool) -> CastTimeline {
        let times: [TimeInterval] = fractions.map { walkUp + contract * $0 }
        let last: Double = fractions.last ?? 0
        let recovery: TimeInterval = max(0, contract * (1 - last))
        return CastTimeline(times: times, recovery: recovery, heavy: heavy)
    }

    /// The contact of the hit with index `hit`, the last one for an index
    /// past the clip's.
    func time(ofHit hit: Int) -> TimeInterval {
        guard !times.isEmpty else { return 0 }
        return times[min(max(0, hit), times.count - 1)]
    }

    /// The hold after presenting event `index` of `events` (the cast's own
    /// slice, cast first), `elapsed` authored seconds after the cast began:
    /// so each hit's first damage event is presented on its contact,
    /// another victim of the same hit `victimStep` later, anything the kit
    /// puts between two hits (a per-hit status, a shield's soak, a bar
    /// push, a defeat) sharing the gap evenly, and the last hit's last
    /// victim keeping the dwell its blows earn — `heavyDwell`,
    /// `criticalDwell`, `lethalDwell`, or the damage's own hold. A rite's
    /// cast, with no hit after it, holds to its release. Nil past the last
    /// hit's last victim, and for a slice that does not open on a cast:
    /// those events keep their own holds.
    func hold(after index: Int, in events: [BattleEvent], elapsed: TimeInterval) -> TimeInterval? {
        guard index >= 0, index < events.count else { return nil }
        let due = dues(in: events)
        guard due[index] != nil else { return nil }
        let lastDue = due.lastIndex { $0 != nil } ?? 0
        if index == lastDue {
            guard index > 0 else {
                // A rite's cast: its release is its one contact.
                let release: TimeInterval = times.first ?? 0
                return max(Self.shortestStep, release - elapsed)
            }
            return dwell(after: index, in: events)
        }
        guard let next = due[index + 1] else { return nil }
        return max(Self.shortestStep, next - elapsed)
    }

    /// When each event of the slice is due, in authored seconds from the
    /// cast's start: the cast at 0; each damage its caster deals on a hit
    /// this timeline times on the hit's contact, the next victims of the
    /// same hit `victimStep` apart (never before the victim before them);
    /// anything between two of those sharing the gap evenly; anything
    /// between the cast and the first hit pressed against the first contact
    /// `leadStep` apart; nil for every event after the last hit's last
    /// victim.
    func dues(in events: [BattleEvent]) -> [TimeInterval?] {
        var due = [TimeInterval?](repeating: nil, count: events.count)
        guard let opening = events.first, case .skillCast(let caster, _, _, _, _, _, _) = opening else { return due }
        due[0] = 0
        var anchors: [(index: Int, due: TimeInterval)] = [(index: 0, due: 0)]
        var struck: [Int: Int] = [:]
        for index in events.indices.dropFirst() {
            guard case .damage(let source, _, _, _, _, _, _, let hit, _) = events[index], source == caster,
                  hit >= 0, hit < times.count else { continue }
            let before = struck[hit] ?? 0
            struck[hit] = before + 1
            let wanted: TimeInterval = times[hit] + Self.victimStep * TimeInterval(before)
            let floor: TimeInterval = anchors[anchors.count - 1].due
            anchors.append((index: index, due: max(wanted, floor)))
        }
        for (from, to) in zip(anchors, anchors.dropFirst()) {
            due[to.index] = to.due
            let between = to.index - from.index - 1
            guard between > 0 else { continue }
            // A hit's own lead-in — a barrier's or a shield's soak, the
            // barrier shattering and its stun, an Endure spent — comes out
            // of the engine just before its damage and is shown on the blow,
            // `leadStep` apart; only what comes before it (the last hit's
            // aftermath) shares the gap. Everything before the first hit is
            // lead-in.
            let leadIn: Int = from.index == 0
                ? from.index + 1
                : Self.leadInStart(before: to.index, after: from.index, in: events)
            let pressedFrom: TimeInterval = leadIn < to.index
                ? max(from.due, to.due - Self.leadStep * TimeInterval(to.index - leadIn))
                : to.due
            let shared = leadIn - from.index - 1
            for step in 1...between {
                let index = from.index + step
                let at: TimeInterval
                if index >= leadIn {
                    let back: TimeInterval = Self.leadStep * TimeInterval(to.index - index)
                    at = max(from.due, to.due - back)
                } else {
                    let share: TimeInterval = TimeInterval(step) / TimeInterval(shared + 1)
                    at = from.due + (pressedFrom - from.due) * share
                }
                due[index] = at
            }
        }
        return due
    }

    /// Where the lead-in of the damage at `index` begins: the first of the
    /// events `BattleEngine.applyDamage` tells before a hit's own number — a
    /// barrier's or a shield's soak on its target (then a shattering, its
    /// stun, a shield worn through) or an Endure spent — or `index` itself
    /// when the hit has none. Only `applyDamage` tells a soak or spends an
    /// Endure, so the previous hit's aftermath is never taken for it.
    static func leadInStart(before index: Int, after start: Int, in events: [BattleEvent]) -> Int {
        guard index > start + 1, index < events.count,
              case .damage(_, let target, _, _, _, _, _, _, _) = events[index] else { return index }
        var first = index
        for position in stride(from: index - 1, to: start, by: -1) {
            switch events[position] {
            case .shieldAbsorbed(let soaked, _, _) where soaked == target:
                first = position
            case .statusRemoved(let removed, .endure, _) where removed == target:
                first = position
            case .statusRemoved(let removed, .shield, _) where removed == target:
                continue
            case .passiveTriggered(let actor, _) where actor == target:
                continue
            case .statusApplied(_, let stunned, .stun, _) where stunned == target:
                continue
            default:
                return first
            }
        }
        return first
    }

    /// The dwell after the last hit: the longest any of its damage earned.
    private func dwell(after index: Int, in events: [BattleEvent]) -> TimeInterval {
        guard case .damage(let caster, _, _, _, _, _, _, let lastHit, _) = events[index] else {
            return events[index].presentationDuration
        }
        var longest: TimeInterval = 0
        for event in events {
            guard case .damage(let source, _, _, let critical, _, _, let remaining, let hit, _) = event,
                  source == caster, hit == lastHit else { continue }
            let earned: TimeInterval
            if remaining <= 0 {
                earned = Self.lethalDwell
            } else if critical {
                earned = Self.criticalDwell
            } else if heavy {
                earned = Self.heavyDwell
            } else {
                earned = event.presentationDuration
            }
            longest = max(longest, earned)
        }
        return longest
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
