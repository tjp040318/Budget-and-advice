import Foundation
import SceneKit
import UIKit

/// One combatant on the 3D stage.
///
/// Owns the model, its animation state, the world-space health bar and the
/// status pips. The battle scene talks to it in game terms — "play a hit react",
/// "set health to 0.4" — and never touches SceneKit nodes directly.
final class UnitNode: SCNNode {

    let combatantID: UUID
    let spec: ModelSpec
    let element: Element
    let side: BattleSide
    private(set) var isDefeated = false
    /// The asset whose clips this unit plays: the awakened mesh's own when
    /// one has shipped, otherwise the base's.
    private let clipAsset: String

    private let modelContainer: SCNNode
    private let healthBarRoot: SCNNode
    private let healthFill: SCNNode
    private let statusRow: SCNNode
    private let selectionRing: SCNNode
    private let elementTint: UIColor

    /// Nil until the first clip plays. It used to start as `.idleCombat`, so
    /// the `play(.idleCombat)` in `init` was refused as "already running" and
    /// every unit stood in its bind pose — the A-pose in the first battle
    /// screenshots — until its first attack.
    private var currentClip: AnimationClip?

    /// Where the model container rests, read before anything has had a chance
    /// to animate it. The dash writes the container's height every frame to
    /// arc the leap and a recoil writes its depth, so both need a rest value
    /// to come back to that no bob, no interrupted leap and no accumulated
    /// `moveBy` can have drifted.
    private let containerRest: SCNVector3

    /// Whether this unit has taken up its idle once already. The FIRST idle
    /// starts on a random beat, because every unit is built in the same frame
    /// from the same cached animation and a rank that rises and falls in
    /// perfect unison reads as a screensaver rather than as a squad. Every
    /// idle after an action starts at once: a pause after a swing reads as a
    /// dropped frame.
    private var hasIdled = false

    /// Whether the dash arc is the thing writing the model container's pitch
    /// at the moment.
    ///
    /// The arc drives that angle as an ABSOLUTE value every frame, and the
    /// procedural clips below rotate it RELATIVELY, so the two must never
    /// both hold it: the arc's last frame would become the rotation's zero
    /// and the figure would finish every swing leaning a few degrees further
    /// back than it began — once per attack, compounding, for the rest of the
    /// fight. Ownership passes to the clip in `playProcedural` and is only
    /// ever set and cleared on the main thread; the arc's own blocks, which
    /// run on the render thread, do nothing but read it. A rigged family is
    /// untouched by any of this: a real clip animates the skeleton INSIDE the
    /// container and never touches the container's own angles, so it keeps
    /// the lean through the whole landing.
    private var dashOwnsPitch = false

    /// 1.0 normally, 2.0 on the fast-forward toggle, 4.0 on skip.
    ///
    /// SceneKit has no per-node speed multiplier — that is SpriteKit's `speed`
    /// — so the scale is applied by hand: to the CAAnimations in `play` and to
    /// every action duration through `beat`. Until it was, the event queue ran
    /// at x2 over clips that still played at x1, so each swing was about half
    /// finished when the next event replaced it and the field twitched between
    /// fragments of motion. The mode the player spends most of his time in had
    /// the worst motion in the game.
    var playbackSpeed: Double = 1.0 {
        didSet {
            guard abs(playbackSpeed - oldValue) > 0.01, let clip = currentClip, clip.loops else { return }
            // `play` refuses to restart a loop that is already running, so the
            // idle is re-seated by hand to pick up the new pace.
            currentClip = nil
            play(clip)
        }
    }

    /// Authored seconds at the current playback speed. Every duration in this
    /// file is written for x1 and divided here, so fast-forward shortens the
    /// dash, the recoil and the procedural motion by exactly as much as it
    /// shortens the clips.
    private func beat(_ seconds: TimeInterval) -> TimeInterval {
        seconds / max(0.25, playbackSpeed)
    }

    /// Where the unit stands between actions, captured the first time it
    /// dashes, so `returnHome` can put it back. Nil until then.
    private var homePosition: SCNVector3?
    private var homeYaw: Float = 0

    init(combatant: Combatant, detail: ModelLibrary.DetailLevel = .high) {
        // Everything is built into locals first: Swift forbids touching `self`
        // before `super.init()`, so the scene graph is assembled here and wired
        // up immediately afterwards.
        let tint = UIColor(hex: combatant.element.accentHex) ?? .white
        let modelHeight = CGFloat(combatant.model.height)
        // A CONSTANT world size, not a fraction of the model's height.
        //
        // Two things were wrong with scaling it. The readability study named
        // the first: a bar whose full length is the unit's height means a
        // 1.85 m unit at full health and a 2.20 m unit at 84% draw the same
        // bar, so health is not comparable between two units even when you can
        // see both. And the CI tour showed the second on 2026-09-10 — at
        // `height * 0.85` a bar is 1.7 m wide for an ordinary unit and 3.8 m
        // for the Colossus, and the line is 2.0 m apart, so every bar lay
        // across its neighbours and one ran straight through two figures at
        // chest height. 1.15 m is under that spacing by enough that they never
        // touch, and every unit in the fight now draws the same bar, which is
        // the whole point of a bar.
        let barHeight: CGFloat = 0.125
        let width: CGFloat = 1.15

        let container = ModelLibrary.shared.node(
            for: combatant.model,
            archetype: combatant.archetype,
            element: combatant.element,
            detail: detail,
            awakened: combatant.isAwakened
        )
        if combatant.isAwakened {
            // The awakened aura: a slow rise of light in the element colour
            // from the feet, for as long as the unit stands.
            container.addParticleSystem(VFXLibrary.aura(tint: tint, scale: Float(modelHeight) / 1.9))
        }

        // Health bar: a dark plate with a coloured fill that scales from its
        // left edge, parented to a billboard so it always faces the camera.
        let barRoot = SCNNode()
        let backing = SCNNode(geometry: SCNPlane(width: width, height: barHeight))
        backing.geometry?.firstMaterial = UnitNode.flatMaterial(UIColor.black.withAlphaComponent(0.65))
        barRoot.addChildNode(backing)

        let fillGeometry = SCNPlane(width: width, height: barHeight * 0.78)
        fillGeometry.firstMaterial = UnitNode.flatMaterial(
            combatant.side == .player ? UIColor(hex: "#5FD98A")! : UIColor(hex: "#E8574F")!
        )
        let fill = SCNNode(geometry: fillGeometry)
        // Pivot on the left edge so scaling shrinks toward the left.
        fill.pivot = SCNMatrix4MakeTranslation(Float(-width / 2), 0, 0)
        fill.position = SCNVector3(Float(-width / 2), 0, 0.001)
        barRoot.addChildNode(fill)

        let statuses = SCNNode()
        statuses.position = SCNVector3(0, Float(barHeight * 1.4), 0)
        barRoot.addChildNode(statuses)

        let billboard = SCNBillboardConstraint()
        // `.all`, not `[.X, .Y]`. Those two axes are enough to point a plane
        // at a camera that sits square on the centre line, and that is what
        // this was: the old camera had zero yaw. Giving it 13 degrees so the
        // fight reads in three dimensions left every one of these planes
        // unable to ROLL, so they came to rest tilted with the floor — the
        // CI tour photographed a health bar lying at waist height across two
        // figures like a plank. Freeing the roll costs nothing and is what
        // keeps a bar level on screen from any camera.
        billboard.freeAxes = .all
        barRoot.constraints = [billboard]
        // Clear of the head by a fixed margin rather than a fraction, so a
        // short unit's bar is not resting on its hair and a tall one's is not
        // adrift a metre above it.
        barRoot.position = SCNVector3(0, combatant.model.height + 0.34, 0)

        // Ground ring under the unit — the readable "who is this" cue.
        let ringGeometry = SCNTorus(ringRadius: modelHeight * 0.22, pipeRadius: 0.012)
        ringGeometry.firstMaterial = UnitNode.flatMaterial(tint.withAlphaComponent(0.85))
        let ring = SCNNode(geometry: ringGeometry)
        ring.position = SCNVector3(0, 0.01, 0)
        ring.opacity = 0.0

        self.combatantID = combatant.id
        self.spec = combatant.model
        self.element = combatant.element
        self.side = combatant.side
        // The clips come from the mesh on the stage: the awakened export when
        // it shipped, the base one, or the stand-in's own when the base is
        // still on the way.
        let library = ModelLibrary.shared
        if combatant.isAwakened && library.hasModel(combatant.model.awakenedAssetName) {
            self.clipAsset = combatant.model.awakenedAssetName
        } else if library.hasModel(combatant.model.assetName) {
            self.clipAsset = combatant.model.assetName
        } else {
            self.clipAsset = combatant.model.standInAsset ?? combatant.model.assetName
        }
        self.elementTint = tint
        self.modelContainer = container
        self.containerRest = container.position
        self.healthBarRoot = barRoot
        self.healthFill = fill
        self.statusRow = statuses
        self.selectionRing = ring

        super.init()

        name = "combatant_\(combatant.id.uuidString)"
        addChildNode(container)
        addChildNode(barRoot)
        addChildNode(ring)

        play(.idleCombat)
        setHealth(fraction: combatant.healthFraction, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("UnitNode is created in code") }

    /// For the island: no health bar and no selection ring, just the figure.
    func hideBattleDecorations() {
        healthBarRoot.isHidden = true
        selectionRing.isHidden = true
    }

    // MARK: - Animation

    /// Plays a clip. Falls back to a procedural motion when the export has no
    /// animation for it, so the battle never freezes waiting on missing art.
    func play(_ clip: AnimationClip, completion: (() -> Void)? = nil) {
        guard !isDefeated || clip == .death else { completion?(); return }
        // Restarting a looping clip every frame would reset its phase, so an
        // idle that is already running is left alone.
        guard clip != currentClip || !clip.loops else { completion?(); return }
        currentClip = clip
        // A clip that has not started yet and the previous clip's own ending
        // are both stale the moment a new clip begins. The ending used to be a
        // wall-clock timer with no idea what was running when it fired, so on
        // a multi-hit skill the first hit's timer landed part-way through the
        // second hit's flinch and snapped the victim to a neutral stance while
        // it was still being hit.
        removeAction(forKey: "pending_clip")
        modelContainer.removeAction(forKey: "clip_end")
        modelContainer.removeAction(forKey: "clip")

        if let shared = ModelLibrary.shared.animation(clip, for: clipAsset) {
            // The library hands out one cached animation per clip, so the copy
            // is what gets configured for this use of it.
            let animation = (shared.copy() as? CAAnimation) ?? shared
            if clip == .death {
                // A one-shot animation is removed when it ends and the model
                // snaps back to its rest pose, which for a death means the
                // corpse stands back up in an A-pose. Hold the last frame.
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards
            }

            // The library gives every clip the same long cross-fade, which was
            // aimed at the stiff cut from idle to swing. On a LOOP that is
            // right — a loop is a state, and blending both ways is how one
            // state becomes another. On a ONE-SHOT it does the opposite of
            // what was wanted: the first fifth of an attack is the wind-up,
            // the pose furthest from idle and therefore the one a linear blend
            // flattens hardest, so the swing oozed out of the idle with no
            // readable start. A one-shot is an event: it must begin on its own
            // first frame and only blend on the way out. The 0.5 s hit react
            // was losing nearly half of itself to the two fades, which is why
            // a flinch was barely visible at all.
            animation.fadeInDuration = clip.loops ? 0.25 : 0.05
            animation.fadeOutDuration = clip.loops ? 0.25 : 0.16

            var rate = playbackSpeed
            if !clip.loops, clip != .death, animation.duration > 0.05 {
                // EVERY one-shot is retimed to its contract now, not only the
                // ones that run long. The fight is timed to `fallbackDuration`
                // — `BattleSceneController` presents the damage at a fraction
                // of it, the frame the blade lands — so a 1.0 s Meshy sword
                // slash left at its authored length put its contact frame
                // 0.3 s before the damage, and the hit-stop then froze a frame
                // with the attacker already relaxed back into its idle. The
                // clamp is because past 2x a swing is a flicker and below
                // 0.6x it is a mime.
                rate *= max(0.6, min(2.0, animation.duration / clip.fallbackDuration))
            }
            if clip.loops {
                // One cached animation, copied for everybody, started in the
                // same frame for everybody: the whole field breathed on the
                // same frame at the same rate for ever. A random phase and a
                // few per cent of drift in the rate is the cheapest way to
                // make a line of figures look like separate creatures.
                animation.timeOffset = Double.random(in: 0..<max(0.05, animation.duration))
                rate *= Double.random(in: 0.94...1.06)
            }
            animation.speed = Float(max(0.05, rate))

            modelContainer.addAnimation(animation, forKey: clip.rawValue)
            if !clip.loops {
                let played = animation.duration > 0
                    ? animation.duration / Double(max(0.05, animation.speed))
                    : beat(clip.fallbackDuration)
                if clip == .death {
                    modelContainer.runAction(.sequence([.wait(duration: played), .fadeOpacity(to: 0.6, duration: 0.6)]))
                }
                scheduleClipEnd(clip, after: played, completion: completion)
            } else {
                completion?()
            }
            return
        }

        playProcedural(clip, completion: completion)
    }

    /// Hands a one-shot back to the idle when it finishes.
    ///
    /// This is a scene action rather than a `DispatchQueue.asyncAfter`, for two
    /// reasons. A hit freezes the whole scene for up to 150 ms (`Juice.impact`)
    /// and a wall-clock timer keeps counting through a freeze that the
    /// animation it is timed against does not, so a five-hit ultimate lost
    /// nearly half a second off the end of its clip and the caster was yanked
    /// to idle before its follow-through. And an action is keyed, so the next
    /// clip cancels it instead of leaving a stale ending to fire mid-swing.
    private func scheduleClipEnd(_ clip: AnimationClip, after duration: TimeInterval, completion: (() -> Void)?) {
        modelContainer.runAction(.sequence([
            .wait(duration: duration),
            SCNAction.run { [weak self] _ in
                // SceneKit runs this on its rendering thread, part-way through
                // the node's own action update, and everything below touches
                // the scene graph. Hop to main first, exactly as
                // `playProcedural` documents at the bottom of this file.
                DispatchQueue.main.async {
                    completion?()
                    guard let self, !self.isDefeated, self.currentClip == clip else { return }
                    self.play(.idleCombat)
                }
            }
        ]), forKey: "clip_end")
    }

    /// Plays a clip once the feet are down.
    ///
    /// A closing melee attack used to start its swing on the same frame as its
    /// dash, so the wind-up — the only part of an attack that carries
    /// anticipation — happened four metres away in mid-air and the figure
    /// arrived a quarter of the way through its own cut. The wait is a scene
    /// action so that it, the leap and the clip all stop together on a
    /// hit-stop.
    func play(_ clip: AnimationClip, after delay: TimeInterval) {
        guard delay > 0.01 else { play(clip); return }
        removeAction(forKey: "pending_clip")
        runAction(.sequence([
            .wait(duration: delay),
            SCNAction.run { [weak self] _ in
                DispatchQueue.main.async { self?.play(clip) }
            }
        ]), forKey: "pending_clip")
    }

    /// Drops a swing that has been scheduled but has not begun.
    ///
    /// The skip button flushes the queue and snaps the field to the end
    /// state, and a clip still waiting out its dash would otherwise land a
    /// lone attack over a battle that has already been decided.
    func cancelPendingClip() {
        removeAction(forKey: "pending_clip")
    }

    /// Stand-in motion built from SCNActions. Crude by design — it communicates
    /// timing and intent so combat pacing can be tuned before real animation.
    private func playProcedural(_ clip: AnimationClip, completion: (() -> Void)?) {
        modelContainer.removeAction(forKey: "clip")
        // This clip is about to rotate the container's pitch relatively, so it
        // takes that channel off the dash arc first. See `dashOwnsPitch`.
        if dashOwnsPitch {
            dashOwnsPitch = false
            modelContainer.eulerAngles.x = 0
        }
        // Forward, toward the enemy line. Every action below moves the model
        // container, whose parent is the unit node, and the unit node has
        // already been turned to face the enemy — `place` gives the near side
        // a half-turn because a model is authored facing +Z — so forward is
        // local +Z on BOTH sides. The `side == .player ? -1 : 1` this replaces
        // reasoned in WORLD space and then applied the answer in local space,
        // which sent every player unit's lunge and every player unit's gather
        // the wrong way: the near line wound up by stepping toward its victim
        // and then struck by retreating from it.
        let facing: Float = 1

        let action: SCNAction
        switch clip {
        case .idle, .idleCombat:
            // A `moveBy` that is interrupted half way leaves the container
            // where it stood, and over a battle of interruptions the bob
            // drifts, so the rest height is restored before it starts again.
            // The depth goes back too: the lunges below are relative and
            // `recoil` writes the same axis as an absolute value, so a unit
            // struck in the middle of its own swing ends it a few centimetres
            // off its mark. Every one-shot comes back through here, which
            // makes the idle the one place that residue can be swept up.
            modelContainer.position.y = containerRest.y
            modelContainer.position.z = containerRest.z
            // Same lockstep problem as the skeletal idle above, and worse: a
            // fixed 1.1 s bob started in the same frame for every unit on the
            // field. The period is jittered and the first idle waits a random
            // fraction of it, so nothing breathes in time with anything else.
            let period = beat(Double.random(in: 0.95...1.25))
            let up = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.012, z: 0, duration: period)
            up.timingMode = .easeInEaseOut
            let breathe = SCNAction.repeatForever(.sequence([up, up.reversed()]))
            let lead = hasIdled ? 0 : Double.random(in: 0...period)
            hasIdled = true
            action = lead > 0.01 ? SCNAction.sequence([.wait(duration: lead), breathe]) : breathe

        case .attackBasic:
            // Gather, strike, recover. The old version was a lunge and its
            // reverse with a flat wait between them, which is a slide with a
            // pause in it: there was nothing to anticipate the blow.
            let gather = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(-facing) * 0.12, duration: beat(0.14))
            gather.timingMode = .easeOut
            let lunge = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(facing) * 0.57, duration: beat(0.12))
            lunge.timingMode = .easeIn
            let recover = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(-facing) * 0.45, duration: beat(0.26))
            recover.timingMode = .easeInEaseOut
            action = .sequence([gather, lunge, .wait(duration: beat(0.10)), recover])

        case .attackHeavy, .castRelease:
            let wind = SCNAction.rotateBy(x: -0.22, y: 0, z: 0, duration: beat(0.28))
            wind.timingMode = .easeOut
            let strike = SCNAction.rotateBy(x: 0.34, y: 0, z: 0, duration: beat(0.1))
            strike.timingMode = .easeIn
            let lunge = SCNAction.moveBy(x: 0, y: 0, z: CGFloat(facing) * 0.6, duration: beat(0.12))
            lunge.timingMode = .easeIn
            action = .sequence([
                wind, .group([strike, lunge]), .wait(duration: beat(0.2)),
                .group([.rotateBy(x: -0.12, y: 0, z: 0, duration: beat(0.2)), lunge.reversed()])
            ])

        case .ultimate:
            let rise = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.35, z: 0, duration: beat(0.6))
            rise.timingMode = .easeOut
            let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: beat(0.9))
            let slam = SCNAction.moveBy(x: 0, y: CGFloat(-spec.height) * 0.35, z: 0, duration: beat(0.22))
            slam.timingMode = .easeIn
            action = .sequence([rise, spin, slam, .wait(duration: beat(0.35))])

        case .castLoop:
            action = .repeatForever(.rotateBy(x: 0, y: 0.6, z: 0, duration: beat(1.5)))

        case .hitReact:
            // The shove away from the blow is `recoil`, which every hit fires
            // whether or not a real clip exists, so this is only the flinch on
            // top of it — a twist, not a translation, so the two never fight
            // over the same axis of the same node.
            let twist = SCNAction.rotateBy(x: -0.15, y: CGFloat(facing) * 0.12, z: 0, duration: beat(0.07))
            twist.timingMode = .easeOut
            let settle = twist.reversed()
            settle.timingMode = .easeInEaseOut
            action = .sequence([twist, .wait(duration: beat(0.06)), settle])

        case .death:
            let fall = SCNAction.rotateBy(x: -.pi / 2.2, y: 0, z: 0, duration: beat(0.55))
            fall.timingMode = .easeIn
            action = .group([fall, .fadeOpacity(to: 0.15, duration: beat(0.7))])

        case .victory:
            let jump = SCNAction.moveBy(x: 0, y: CGFloat(spec.height) * 0.18, z: 0, duration: beat(0.3))
            jump.timingMode = .easeOut
            let land = jump.reversed()
            land.timingMode = .easeIn
            action = .repeat(.sequence([jump, land]), count: 3)

        case .summonReveal:
            action = .sequence([
                .fadeOpacity(to: 1, duration: beat(0.6)),
                .rotateBy(x: 0, y: .pi * 2, z: 0, duration: beat(1.6))
            ])
        }

        // SceneKit calls this on its rendering thread, part-way through the
        // node's own action update. Touching the action list from in there —
        // which `playProcedural` does immediately, via `removeAction` — mutates
        // the collection SceneKit is iterating and aborts the process. Hop to
        // main before going anywhere near the scene graph.
        modelContainer.runAction(action, forKey: "clip") { [weak self] in
            DispatchQueue.main.async {
                completion?()
                guard let self, !self.isDefeated, !clip.loops else { return }
                self.playProcedural(.idleCombat, completion: nil)
            }
        }
    }

    // MARK: - Movement

    /// Closes on a victim for a melee strike: a fast dash to a stride short of
    /// it, turning to face it on the way. The genre's melee attacks all do
    /// this — a swing from four metres away reads as mime — and the unit
    /// stays there through the hits until `returnHome`.
    func dash(toward target: UnitNode, duration: TimeInterval) {
        if homePosition == nil {
            homePosition = position
            homeYaw = eulerAngles.y
        }
        let from = position
        let to = target.position
        let dx = to.x - from.x, dz = to.z - from.z
        let distance = max(0.001, (dx * dx + dz * dz).squareRoot())
        let stride = spec.height * 0.7
        let travel = max(0, distance - stride)
        let destination = SCNVector3(from.x + dx / distance * travel, from.y, from.z + dz / distance * travel)

        // Gather, fly, land — the three beats every convincing jump has, and
        // the reason this one now reads as a figure moving itself rather than
        // one being carried. The old dash was a single eased slide with a
        // symmetric up-and-down hop laid over it: nothing coiled before it
        // went and nothing absorbed the landing, which is exactly the pair of
        // frames the eye reads as weight.
        let gather = duration * Self.dashGather
        let flight = duration * Self.dashFlight

        removeAction(forKey: "dash")
        let move = SCNAction.move(to: destination, duration: flight)
        // Out of the crouch hard and into the victim soft. An ease at both
        // ends has no push-off, and a linear move reads as cheap at any speed.
        move.timingMode = .easeOut
        // The model is authored facing +Z, so this yaw faces the victim. (A
        // CAMERA looks along its own -Z and must use `look(at:)`; a character
        // does not.)
        let turn = SCNAction.rotateTo(
            x: 0, y: CGFloat(atan2(dx, dz)), z: 0,
            duration: gather + flight * 0.5, usesShortestUnitArc: true
        )
        turn.timingMode = .easeInEaseOut
        runAction(.group([.sequence([.wait(duration: gather), move]), turn]), forKey: "dash")

        // Height and lean are driven by one curve over the whole dash rather
        // than by a stack of `moveBy`s, so every frame is an absolute value:
        // an interrupted dash can leave no residue, and the arc is a real
        // parabola — fastest through the top — instead of up-then-down.
        let rest = containerRest.y
        let apex = spec.height * 0.18
        // The coil is a token dip only. A unit's feet sit ON the platform, so
        // a crouch built out of a downward translation drives the lower legs
        // through an opaque floor: at the 0.06 of its height this started at,
        // a 1.8 m figure sank eleven centimetres into the stage and a 3.2 m
        // boss nearly twenty. What sells the anticipation is the backward
        // lean below; a crouch that reads properly has to come out of the
        // skeleton, which is not something this file can author.
        let dip = spec.height * 0.02
        let span = max(0.01, duration)
        dashOwnsPitch = true
        modelContainer.removeAction(forKey: "hop")
        let arc = SCNAction.customAction(duration: span) { [weak self] node, elapsed in
            let t = Float(min(1, max(0, Double(elapsed) / span)))
            var height: Float = 0
            var lean: Float = 0
            if t < Float(Self.dashGather) {
                // Coil: down and back, the weight loading before the push.
                let g = t / Float(Self.dashGather)
                height = -dip * sin(g * .pi * 0.5)
                lean = -0.10 * g
            } else if t < Float(Self.dashGather + Self.dashFlight) {
                let f = (t - Float(Self.dashGather)) / Float(Self.dashFlight)
                height = -dip * (1 - f) + apex * 4 * f * (1 - f)
                lean = -0.10 * (1 - f) + 0.16 * f
            } else {
                // Absorb: the knees give on landing and come back up.
                let l = (t - Float(Self.dashGather + Self.dashFlight)) / Float(Self.dashLand)
                height = -dip * 0.85 * sin(min(1, l) * .pi)
                lean = 0.16 * (1 - min(1, l))
            }
            node.position.y = rest + height
            // The height is the arc's alone; the pitch is only its while no
            // procedural clip has taken it over. See `dashOwnsPitch`.
            if self?.dashOwnsPitch == true { node.eulerAngles.x = lean }
        }
        modelContainer.runAction(.sequence([arc, SCNAction.run { [weak self] node in
            node.position.y = rest
            if self?.dashOwnsPitch == true { node.eulerAngles.x = 0 }
        }]), forKey: "hop")
    }

    /// Where the beats of a dash fall, as fractions of its duration. The clip
    /// is held until `dashGather + dashFlight` of the way through (see
    /// `BattleSceneController`), so the wind-up begins as the weight lands.
    static let dashGather = 0.22
    static let dashFlight = 0.70
    static let dashLand = 0.08

    /// Back to the spot it stood on, facing the way it did. Nothing happens
    /// for a unit that never dashed.
    func returnHome(duration: TimeInterval) {
        guard let home = homePosition else { return }
        removeAction(forKey: "dash")
        // The arc writes the container's height and lean every frame, so
        // cancelling it in mid-flight would leave the figure hanging tilted in
        // the air. Both are put back by hand.
        modelContainer.removeAction(forKey: "hop")
        modelContainer.position.y = containerRest.y
        // Only the arc's own lean is undone. A procedural clip that has taken
        // the pitch over is rotating it relatively toward its own zero, and
        // forcing it flat underneath that would leave the figure tilted for
        // the rest of the fight.
        if dashOwnsPitch { modelContainer.eulerAngles.x = 0 }
        let move = SCNAction.move(to: home, duration: duration)
        move.timingMode = .easeInEaseOut
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(homeYaw), z: 0, duration: duration, usesShortestUnitArc: true)
        runAction(.group([move, turn]), forKey: "dash")
    }

    /// The shove a blow puts through a body: the whole figure is driven
    /// backwards off its stance and springs back onto it.
    ///
    /// A hit used to be a white flash and a number over a figure that never
    /// moved, which is most of why the fight read as "numbers changing" rather
    /// than as something being struck. It is deliberately NOT part of the hit
    /// react clip: most exports do not ship one, and a shove that only some
    /// families have is worse than none. Backwards is the container's own -Z,
    /// because a unit faces the line it is fighting, so this is away from the
    /// blow for a defender at its mark and for an attacker caught by a
    /// counter mid-dash alike.
    func recoil(strength: Float) {
        guard !isDefeated else { return }
        let push = spec.height * 0.055 * min(2.4, max(0.4, strength))
        let rest = containerRest.z
        let span = beat(0.26)
        modelContainer.removeAction(forKey: "recoil")
        modelContainer.runAction(.sequence([
            SCNAction.customAction(duration: span) { node, elapsed in
                let t = Float(min(1, max(0, Double(elapsed) / span)))
                // Driven out over the first quarter and returning over the
                // rest: a symmetric there-and-back reads as a slide, a fast
                // out and a decaying return reads as a body absorbing a blow.
                let out: Float
                if t < 0.25 {
                    out = sin(t / 0.25 * .pi * 0.5)
                } else {
                    let u = (t - 0.25) / 0.75
                    out = (1 - u) * (1 - u)
                }
                node.position.z = rest - push * out
            },
            SCNAction.run { node in node.position.z = rest }
        ]), forKey: "recoil")
    }

    /// A white flash over the whole model on the frame a hit lands, fading
    /// over a fifth of a second. The emission is what the tint left there,
    /// and it is put back.
    func flashHit() {
        modelContainer.enumerateHierarchy { child, _ in
            guard let materials = child.geometry?.materials else { return }
            for material in materials {
                let previous = material.emission.contents
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0
                material.emission.contents = UIColor(white: 0.8, alpha: 1)
                SCNTransaction.commit()
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.22
                material.emission.contents = previous
                SCNTransaction.commit()
            }
        }
    }

    // MARK: - State

    func setHealth(fraction: Double, animated: Bool = true) {
        let clamped = Float(min(1, max(0, fraction)))
        let scale = SCNVector3(max(0.0001, clamped), 1, 1)
        if animated {
            let action = SCNAction.customAction(duration: 0.25) { node, elapsed in
                let t = Float(elapsed / 0.25)
                let current = node.scale.x
                node.scale = SCNVector3(current + (clamped - current) * t, 1, 1)
            }
            healthFill.runAction(action)
        } else {
            healthFill.scale = scale
        }

        // The bar shifts toward red as it empties, so a low unit is obvious
        // even in a crowded frame.
        let full = side == .player ? UIColor(hex: "#5FD98A")! : UIColor(hex: "#E8574F")!
        let danger = UIColor(hex: "#F2A03C")!
        healthFill.geometry?.firstMaterial?.diffuse.contents =
            clamped < 0.3 ? danger : full
    }

    func setHighlighted(_ highlighted: Bool) {
        selectionRing.removeAllActions()
        if highlighted {
            selectionRing.opacity = 1.0
            selectionRing.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.45, duration: 0.6),
                .fadeOpacity(to: 1.0, duration: 0.6)
            ])))
        } else {
            selectionRing.runAction(.fadeOpacity(to: 0, duration: 0.2))
        }
    }

    /// Rebuilds the little status pips above the health bar.
    /// What the unit is under right now, drawn as icons over its bar.
    private var activeStatuses: [ActiveStatus] = []

    /// The buffs and debuffs on a unit, as the genre shows them: a row of
    /// icons over the health bar, a blue tile for a buff and a red one for a
    /// debuff, the effect's glyph on it and the turns left in the corner.
    /// The coloured dots of the first build told the player nothing.
    func setStatuses(_ statuses: [ActiveStatus]) {
        activeStatuses = statuses
        statusRow.childNodes.forEach { $0.removeFromParentNode() }
        // One tile per kind, the longest-lasting of each, six at most.
        var byKind: [StatusKind: Int] = [:]
        for status in statuses { byKind[status.kind] = max(byKind[status.kind] ?? 0, status.turnsRemaining) }
        let shown = byKind.sorted { $0.key.rawValue < $1.key.rawValue }.prefix(6)
        guard !shown.isEmpty else { return }

        // Constant, for the same reason the bar is: a status tile that
        // scales with the model makes the Colossus's poison four times the
        // size of a satyr's, and the player is reading them against each
        // other. Sized to sit on a 1.15 m bar — five fit across it.
        let pip: CGFloat = 0.22
        let spacing = pip * 1.12
        let totalWidth = spacing * CGFloat(shown.count - 1)

        for (index, entry) in shown.enumerated() {
            let plane = SCNPlane(width: pip, height: pip)
            plane.firstMaterial = UnitNode.imageMaterial(StatusIconRenderer.image(kind: entry.key, turns: entry.value))
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(
                Float(-totalWidth / 2 + spacing * CGFloat(index)), Float(pip * 0.55), 0.002
            )
            statusRow.addChildNode(node)
        }
    }

    /// A status the moment it lands, so the icon shows with the hit rather
    /// than after the turn settles.
    func applyStatus(_ kind: StatusKind, turns: Int) {
        var statuses = activeStatuses.filter { $0.kind != kind }
        statuses.append(ActiveStatus(kind: kind, turnsRemaining: turns))
        setStatuses(statuses)
    }

    func removeStatus(_ kind: StatusKind) {
        setStatuses(activeStatuses.filter { $0.kind != kind })
    }

    private static func imageMaterial(_ image: UIImage?) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        return material
    }

    func markDefeated() {
        guard !isDefeated else { return }
        play(.death)
        isDefeated = true
        healthBarRoot.runAction(.fadeOut(duration: 0.4))
        selectionRing.runAction(.fadeOut(duration: 0.3))
    }

    func revive(healthFraction: Double) {
        isDefeated = false
        modelContainer.removeAllActions()
        modelContainer.removeAnimation(forKey: AnimationClip.death.rawValue)
        modelContainer.eulerAngles = SCNVector3Zero
        // A death, an interrupted leap or a recoil can all leave the container
        // off its rest transform, and a revived unit standing 20 cm to the
        // rear of its mark is the kind of thing nobody can name but everybody
        // sees.
        modelContainer.position = containerRest
        modelContainer.opacity = 1
        healthBarRoot.runAction(.fadeIn(duration: 0.3))
        setHealth(fraction: healthFraction, animated: false)
        play(.idleCombat)
    }

    /// World position for spawning a VFX or a damage number on this unit.
    func attachmentPoint(_ name: String?) -> SCNNode {
        guard let name, let found = modelContainer.childNode(withName: name, recursively: true) else {
            let fallback = SCNNode()
            fallback.position = SCNVector3(0, spec.height * 0.55, 0)
            addChildNode(fallback)
            return fallback
        }
        return found
    }

    var chestWorldPosition: SCNVector3 {
        convertPosition(SCNVector3(0, spec.height * 0.6, 0), to: nil)
    }

    var headWorldPosition: SCNVector3 {
        convertPosition(SCNVector3(0, spec.height * 1.05, 0), to: nil)
    }

    private static func flatMaterial(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        return material
    }
}

/// Draws a status tile: a rounded square in the buff or debuff colour, the
/// effect's glyph in white, the turns left in the corner. One texture per
/// kind and count, cached.
enum StatusIconRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(kind: StatusKind, turns: Int) -> UIImage? {
        let key = "\(kind.rawValue)|\(turns)"
        if let cached = cache[key] { return cached }

        let side: CGFloat = 72
        let size = CGSize(width: side, height: side)
        let fill = kind.isBuff ? UIColor(hex: "#2E8FBF") ?? .systemBlue : UIColor(hex: "#B8403A") ?? .systemRed
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            fill.setFill()
            path.fill()
            UIColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3
            path.stroke()

            let configuration = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
            if let symbol = UIImage(systemName: kind.glyph, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let box: CGFloat = 40
                let scale = min(box / max(1, symbol.size.width), box / max(1, symbol.size.height))
                let drawn = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                symbol.draw(in: CGRect(
                    x: (side - drawn.width) / 2, y: (side - drawn.height) / 2 - 3,
                    width: drawn.width, height: drawn.height
                ))
            }

            if turns > 0 {
                let label = NSAttributedString(string: "\(turns)", attributes: [
                    .font: UIFont.systemFont(ofSize: 20, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .strokeColor: UIColor.black.withAlphaComponent(0.9),
                    .strokeWidth: -3.5,
                ])
                let textSize = label.size()
                label.draw(at: CGPoint(x: side - textSize.width - 7, y: side - textSize.height - 4))
            }
        }
        if cache.count > 200 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
