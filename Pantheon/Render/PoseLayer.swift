import Foundation
import SceneKit

// MARK: - A figure's life at rest (Docs/PLAN.md *Natural poses*, steps 5 and 7)
//
// The owner, 2026-09-24: "can we make the 3D characters have more of a fluid
// design and poses, instead of all the same static, frozen style poses?"
// Steps 1-3 gave every family a standing idle of its own, built from its own
// rig in its archetype's contrapposto (`tools/natural_idle.py`). An idle is
// still ONE loop, and a loop, however well posed, repeats. The craft's idle is
// a pose AND a life: a weight that moves every few seconds and a gesture that
// surprises — the genre's showcase screens (Genshin's and Star Rail's idle
// animations after a character has stood still; Summoners War's and Raid's
// per-champion idles) sell a character on exactly that.
//
// This layer gives any figure node that life, on the stages that hold one —
// the reveal's hold, the Hall of Ka's altar (and the unit sheet's, the same
// view), the collection's Stage and the island. The stage views hold a plain
// node from `ModelLibrary.node`, not a `UnitNode`, so the layer works on the
// node the clips are added to; the island's `UnitNode` owns one of its own
// (`UnitNode.takeStageLife`). Two pieces, both built from animation players
// SceneKit already blends:
//
// - THE WEIGHT SHIFT (build step 5). Where the family ships a second variant
//   of its idle (`<asset>_idle_alt.usdz`: the same figure on the other leg,
//   on the same foot spots), both loops play, the variant ON TOP, on the
//   idle's own beat, and its `blendFactor` — "when set to less than 1, the
//   animation value is blent with the current presentation value", which is
//   the idle's — is eased 0↔1 over 1.2 s at random intervals of 8-20 s. Two
//   clocks that never meet, so the shift never repeats. The variant is parsed
//   OFF the main thread a moment after the figure stands (a rail flicked
//   through never parses one) and seated at the share of the cycle the idle
//   has reached by then; the first shift is 8 s away at the soonest.
// - THE BREAK (build step 7). A one-shot laid over the running idle and
//   blended in over 0.4 s and out over 0.5 s — the reveal entrance's pattern
//   (run 251), which blends the victory over the idle and back — after 12-18 s
//   untouched on a stage, and on the island for most of its stirs. The clip
//   is the family's own `<asset>_break.usdz` (two breaks in three when it has
//   both) or its VICTORY, played through the window the reveal measured for
//   each preset (`RevealEntrance.cut`: the part that faces the lens).
//
// A family with neither file simply stands on its one idle, and breaks with
// its victory: since phase 2 of 2026-09-25, 60 families ship `_idle_alt`
// (the other 57's shift was refused: the feet left their spots mid-blend, or
// it tore more) and 114 ship `_break` (Nephthys's is held, Odin and the Nymph
// have none that passes); a victory is there for every family of the serious
// roster. The battle never makes one — a fight keeps its one stance, never
// blending, never fidgeting.
//
// The rules the stages learned are kept. The idle starts through
// `SCNNode.startLoop`, the figure already in its scene (a clip added to a
// detached node carried into a live scene never starts, 2026-09-17). Every
// clock of the life is a main-run-loop `Timer` through a weak target
// (`WeakTickTarget`, the ease a `FrameTicker`); only the CI's held break
// (`-tour-fidget`) waits on the scene's clock, through an action whose block
// does nothing but hop to the main queue, as the reveal's entrance does.
// Nothing here touches the scene graph off the main thread: the one parse
// off it hands its clip back to the main queue. The layer holds its figure
// weakly and the stage holds the layer, so its timers stop the first time
// they find the figure gone, and every stage's `dismantleUIView` stops them
// first.

/// One figure's life at rest: its idle, the idle's second variant eased
/// under it, and its breaks. Main thread only.
final class PoseLayer {
    // MARK: The numbers

    /// The keys the layer's players go under on the figure.
    static let idleKey = "idle"
    static let alternateKey = AnimationClip.idleAlt.rawValue
    static let breakKeyStem = "pose_break"

    /// The weight shift: 1.2 s from one leg to the other, every 8-20 s.
    static let shiftDuration: TimeInterval = 1.2
    static let shiftEvery: ClosedRange<TimeInterval> = 8...20
    /// A break after this long untouched on a stage.
    static let fidgetAfter: ClosedRange<TimeInterval> = 12...18
    /// A break comes in over 0.4 s and goes over 0.5 s (the entrance's
    /// pattern), and one cut short by a clip of the stage's own goes in 0.2.
    static let breakBlendIn: TimeInterval = 0.4
    static let breakBlendOut: TimeInterval = 0.5
    static let interruptBlendOut: TimeInterval = 0.2
    /// The idle's second variant leaves over this when the figure leaves
    /// its idle (the island's stroll): `UnitNode.loopBlendOut`'s 0.25 s.
    static let alternateBlendOut: CGFloat = 0.25
    /// Of every three breaks where a family has its own and a victory, two
    /// are its own: the victory is the louder gesture.
    static let ownBreakShare: Double = 2.0 / 3.0
    /// Seconds the figure must have stood before its second variant is
    /// parsed, and before its break clips are: a thumb running down the
    /// Hall of Ka's rail places a figure a beat and leaves it, and a parse
    /// for each would hold the importer the rail's own warm-ahead is using.
    static let alternateLoadDelay: TimeInterval = 0.6
    static let warmBreaksAfter: TimeInterval = 3

    // MARK: State

    /// The stage's name in the tour's console (`[Pose]` lines): the one its
    /// `StageDoctor` prints.
    let label: String
    /// The asset whose clips the figure plays (`ModelLibrary.clipAsset`).
    let clips: String
    /// The node the clips play on. Weak: the scene owns the figure, and a
    /// layer that finds it gone stops.
    private weak var figure: SCNNode?
    /// Whether the layer times its own breaks (the figure stages) or is told
    /// when to break (the island, whose stirs keep their own clock).
    private let fidgetsBySelf: Bool

    /// Out of sight (the stage stopped: a sheet over the unit sheet's altar,
    /// the island off screen): no shift is begun and no break is fired; the
    /// clocks keep turning and try again.
    var isHeld = false

    /// The life's clocks run (`beginLife`) — the reveal's wait for its
    /// entrance — and the layer has been stopped for good (`stop`).
    private var living = false
    private var stopped = false

    /// Where the idle stands in its cycle: set each time it is (re)started,
    /// nil while the figure is out of it (the island's stroll). The second
    /// variant is seated on this beat, however late its clip arrives.
    private var idleBeat: IdleBeat?
    private var alternate: SCNAnimationPlayer?
    private var loadingAlternate = false
    /// The family ships a variant the importer could not read: asked once.
    private var alternateFailed = false
    /// The variant's blend now, and the one it is easing toward.
    private var blend: CGFloat = 0
    private var blendTarget: CGFloat = 0
    private var easeFrom: CGFloat = 0
    private var easeBegan: CFTimeInterval = 0
    private var ease: FrameTicker?

    private var loadTimer: Timer?
    private var warmTimer: Timer?
    private var shiftTimer: Timer?
    private var fidgetTimer: Timer?
    private var breakTimer: Timer?
    private var gazeTimer: Timer?
    /// The break playing now, under its own key (a serial in it, so a break
    /// cut short and still blending out is never taken for the next one).
    private var breakPlayer: SCNAnimationPlayer?
    private var breakKey: String?
    private var breakSerial = 0
    private var lastBreak: String?
    /// What this family can break with, found at the first break.
    private var choices: [PoseBreak]?
    /// The head's turn toward the lens (`Gaze`, build step 6), hung once the
    /// life has begun and the stage has named its lens.
    private var gaze: Gaze?
    /// The stage's camera, which the gaze looks toward: set by the figure
    /// stages once their camera exists, never by the island.
    weak var lens: SCNNode? {
        didSet { startGaze() }
    }
    /// Whether the family ships the idle's second variant at all: a bundle
    /// lookup, once. Without one the shift's clock never starts.
    private lazy var shipsAlternate: Bool = ModelLibrary.shared.hasClipFile(.idleAlt, for: clips)

    init(figure: SCNNode, clips: String, label: String, fidgetsBySelf: Bool) {
        self.figure = figure
        self.clips = clips
        self.label = label
        self.fidgetsBySelf = fidgetsBySelf
    }

    deinit {
        // Held by a stage's coordinator or a `UnitNode`, both let go of on
        // the main thread; the hop is for a node SceneKit frees elsewhere.
        // Each clock also stops itself the first time it finds this gone.
        let timers: [Timer] = [loadTimer, warmTimer, shiftTimer, fidgetTimer, breakTimer, gazeTimer].compactMap { $0 }
        let ticker: FrameTicker? = ease
        if Thread.isMainThread {
            for timer in timers { timer.invalidate() }
            ticker?.stop()
        } else {
            DispatchQueue.main.async {
                for timer in timers { timer.invalidate() }
                ticker?.stop()
            }
        }
    }

    // MARK: Starting

    /// Plays the figure's idle — its standing `idle`, else its combat idle —
    /// through `SCNNode.startLoop`, seats its second variant on top when the
    /// family ships one, and then, `lively`, begins the life (`beginLife`).
    /// The figure must already be in its scene. The reveal starts the idle
    /// at its build and the life after the entrance (`lively: false`).
    @discardableResult
    static func startIdle(on figure: SCNNode, clips assetName: String, label: String, lively: Bool = true) -> PoseLayer {
        let layer = PoseLayer(figure: figure, clips: assetName, label: label, fidgetsBySelf: true)
        layer.playIdle()
        if lively { layer.beginLife() }
        return layer
    }

    /// The idle, and the variant on its beat.
    private func playIdle() {
        guard let figure else { return }
        let library = ModelLibrary.shared
        let phase: Double = Double.random(in: 0..<1)
        var cycle: TimeInterval = 0
        if let idle = library.animation(.idle, for: clips) ?? library.animation(.idleCombat, for: clips) {
            let player = figure.startLoop(idle, key: Self.idleKey, phase: phase)
            cycle = player.animation.duration
        }
        report("idle started")
        idleStarted(phase: phase, speed: 1, cycle: cycle)
    }

    /// The idle has just been (re)started on the figure, at `phase` of its
    /// `cycle` and at `speed`: the variant is seated again ON TOP of it, on
    /// the same beat, at the blend it had. A player added later is applied
    /// later, so an idle re-added after a one-shot (the island's) would
    /// otherwise cover the variant whole. A variant not yet parsed is parsed
    /// off the main thread and seated when it arrives (`loadAlternate`).
    /// Nothing when the family ships none.
    func idleStarted(phase: Double, speed: CGFloat, cycle: TimeInterval) {
        guard let figure, !stopped else { return }
        figure.removeAnimation(forKey: Self.alternateKey)
        alternate = nil
        idleBeat = IdleBeat(began: CACurrentMediaTime(), phase: phase, speed: speed, cycle: cycle)
        guard shipsAlternate, !alternateFailed else { return }
        if let clip = ModelLibrary.shared.cachedAnimation(.idleAlt, for: clips) {
            seatAlternate(clip)
        } else {
            armAlternateLoad()
        }
    }

    /// The variant parsed a moment after the figure stands, once its life has
    /// begun: the reveal starts its idle at its build and its life after the
    /// entrance, and a parse during the charge would hold the importer's lock
    /// the summon board's warm-ahead and a lifted card's build wait on (the
    /// review of 2026-09-25, live since the alts shipped).
    private func armAlternateLoad() {
        guard living, loadTimer == nil, !loadingAlternate, alternate == nil else { return }
        loadTimer = after(Self.alternateLoadDelay) { layer in
            layer.loadTimer = nil
            layer.loadAlternate()
        }
    }

    /// The figure has left its idle for another loop (the island's walk):
    /// the variant goes with it and any break is cut short. `idleStarted`
    /// seats it again when the idle comes back.
    func idleLeft() {
        interruptBreak()
        idleBeat = nil
        if ease != nil {
            // A shift cut off half way: the clock of shifts goes on, and
            // tries again once the idle is back.
            ease?.stop()
            ease = nil
            armShift()
        }
        guard let figure, alternate != nil else { return }
        figure.removeAnimation(forKey: Self.alternateKey, blendOutDuration: Self.alternateBlendOut)
        alternate = nil
    }

    /// Parses the variant on a background queue (the importer's own lock
    /// keeps it to one parse at a time) and seats it on the main queue.
    private func loadAlternate() {
        guard !stopped, !loadingAlternate, figure != nil else { return }
        loadingAlternate = true
        let asset = clips
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let clip: CAAnimation? = ModelLibrary.shared.animation(.idleAlt, for: asset)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingAlternate = false
                guard let clip else {
                    self.alternateFailed = true
                    self.report("\(asset)_idle_alt is in the bundle but did not load: the figure stands on its one idle")
                    return
                }
                self.seatAlternate(clip)
            }
        }
    }

    /// The variant on the idle's beat — at the share of the cycle the idle
    /// has reached now — over it, at the blend it is easing between (or the
    /// tour's pinned one). Not while the figure is out of its idle; the
    /// next `idleStarted` finds the clip in the cache.
    private func seatAlternate(_ clip: CAAnimation) {
        guard let figure, let beat = idleBeat, !stopped else { return }
        figure.removeAnimation(forKey: Self.alternateKey)
        let held: CGFloat = Self.pinnedBlend ?? blend
        let player = figure.startLoop(clip, key: Self.alternateKey, phase: beat.share(at: CACurrentMediaTime()), blend: held)
        player.speed = beat.speed
        alternate = player
        blend = held
        report(String(format: "idle_alt seated at %.2f", held))
    }

    /// Begins the life: the shift's clock, and on a figure stage the break's.
    /// Under `-tour-fidget` a break fires as soon as the stage has drawn for
    /// a moment (`fidgetForTour`).
    func beginLife() {
        guard !living, !stopped, figure != nil else { return }
        living = true
        if idleBeat != nil, shipsAlternate, !alternateFailed { armAlternateLoad() }
        if Self.fidgetsAtOnce {
            warmBreaks()
        } else {
            warmTimer = after(Self.warmBreaksAfter) { layer in
                layer.warmTimer = nil
                layer.warmBreaks()
            }
        }
        if let pinned = Self.pinnedBlend {
            report(!shipsAlternate
                   ? String(format: "blend pinned at %.2f, but %@ ships no idle_alt: nothing to blend", pinned, clips)
                   : String(format: "blend pinned at %.2f", pinned))
        } else {
            armShift()
        }
        startGaze()
        // The island times its own breaks (its stirs), under the tour too.
        guard fidgetsBySelf else { return }
        if Self.fidgetsAtOnce {
            fidgetForTour()
        } else {
            armFidget()
        }
    }

    /// Stops every clock, for good: the figure is leaving its stage. The
    /// players stay on the figure: the stage that owns it takes them off
    /// (`dismantleUIView`) or drops the whole scene.
    func stop() {
        living = false
        stopped = true
        for timer in [loadTimer, warmTimer, shiftTimer, fidgetTimer, breakTimer, gazeTimer] { timer?.invalidate() }
        loadTimer = nil
        warmTimer = nil
        shiftTimer = nil
        fidgetTimer = nil
        breakTimer = nil
        gazeTimer = nil
        ease?.stop()
        ease = nil
        gaze?.stop()
        gaze = nil
    }

    /// A touch on the stage (a drag turning the figure, a rite on the
    /// altar): the untouched clock starts again.
    func touch() {
        guard living else { return }
        armFidget()
    }

    // MARK: The weight shift

    private func armShift() {
        shiftTimer?.invalidate()
        shiftTimer = nil
        guard living, Self.pinnedBlend == nil, shipsAlternate, !alternateFailed else { return }
        shiftTimer = after(TimeInterval.random(in: Self.shiftEvery)) { layer in
            layer.shiftTimer = nil
            layer.shift()
        }
    }

    /// From one leg to the other: the variant's blend eased to the other end
    /// over `shiftDuration`, smoothstepped, a number written each tick.
    private func shift() {
        guard figure != nil else { stop(); return }
        guard alternate != nil, !isHeld else { armShift(); return }
        blendTarget = blendTarget > 0.5 ? 0 : 1
        easeFrom = blend
        easeBegan = CACurrentMediaTime()
        ease?.stop()
        ease = FrameTicker { [weak self] in self?.easeStep() ?? false }
        report(String(format: "weight shift %.2f to %.2f over %.1f s", easeFrom, blendTarget, Self.shiftDuration))
    }

    private func easeStep() -> Bool {
        guard figure != nil, let alternate else {
            ease = nil
            if figure != nil { armShift() }
            return false
        }
        let t: Double = min(1, max(0, (CACurrentMediaTime() - easeBegan) / Self.shiftDuration))
        let eased: CGFloat = CGFloat(t * t * (3 - 2 * t))
        blend = easeFrom + (blendTarget - easeFrom) * eased
        alternate.blendFactor = blend
        guard t < 1 else {
            ease = nil
            armShift()
            return false
        }
        return true
    }

    // MARK: Breaks

    /// The untouched clock: a break when it runs out. Never under
    /// `-tour-fidget`, whose one break is held for good.
    private func armFidget() {
        fidgetTimer?.invalidate()
        fidgetTimer = nil
        guard living, fidgetsBySelf, !Self.fidgetsAtOnce else { return }
        fidgetTimer = after(TimeInterval.random(in: Self.fidgetAfter)) { layer in
            layer.fidgetTimer = nil
            guard layer.figure != nil else { layer.stop(); return }
            if layer.isHeld || layer.breakPlayer != nil {
                layer.armFidget()
            } else if !layer.fidget() {
                // Nothing to break with: the clock stops for good.
                layer.report("no break and no victory: the figure stands on its idle")
            }
        }
    }

    /// Plays one break over the running idle: blended in over 0.4 s, let go
    /// at the end of its window, blended out over 0.5 s and taken off. False
    /// when one is already playing, the stage is out of sight or the family
    /// has nothing to break with. The island calls it for a stir.
    @discardableResult
    func fidget() -> Bool {
        guard let figure, !stopped, breakPlayer == nil, !isHeld, let choice = nextBreak() else { return false }
        let copy: CAAnimation = (choice.clip.copy() as? CAAnimation) ?? choice.clip
        let animation = SCNAnimation(caAnimation: copy)
        animation.usesSceneTimeBase = false
        animation.repeatCount = 1
        animation.isRemovedOnCompletion = false
        // Holds its last frame should the blend run past the clip's end.
        animation.fillsForward = true
        animation.blendInDuration = Self.breakBlendIn
        animation.blendOutDuration = Self.breakBlendOut
        animation.timeOffset = choice.start
        let player = SCNAnimationPlayer(animation: animation)
        breakSerial += 1
        let key = "\(Self.breakKeyStem)_\(breakSerial)"
        // Into the live scene's figure first, then the player, then play():
        // the one order SceneKit starts a clip in (`SCNNode.startLoop`).
        figure.addAnimationPlayer(player, forKey: key)
        player.play()
        breakPlayer = player
        breakKey = key
        lastBreak = choice.name
        // A look-around is the head's own: the gaze gives way to it.
        gaze?.state.setStrength(0)
        let window: TimeInterval = max(Self.breakBlendIn + 0.1, choice.end - choice.start)
        report(String(format: "break: %@ (%@, %.2f-%.2f s of a %.2f s clip)",
                      choice.name, choice.preset, choice.start, choice.end, choice.clip.duration))
        if Self.fidgetsAtOnce, fidgetsBySelf {
            // The CI's frame of a break (`-tour-fidget`): it stops on its
            // high point, fully blended in, and stays, so a screenshot that
            // lands seconds late still shows it. Timed on the SCENE's clock
            // (the entrance's pattern: an action that only hops to main), so
            // a first Metal compile that holds the stage's first frames for
            // seconds holds the wait with them.
            let apexIn: TimeInterval = max(Self.breakBlendIn + 0.1, min(window, choice.apex - choice.start))
            figure.runAction(.sequence([
                .wait(duration: apexIn),
                .run { [weak self] _ in
                    DispatchQueue.main.async { self?.holdBreakForTour() }
                },
            ]), forKey: Self.tourKey)
            return true
        }
        breakTimer = after(window) { layer in
            layer.breakTimer = nil
            layer.letGoOfBreak(over: Self.breakBlendOut)
        }
        return true
    }

    /// Cuts a break short (the island's tap, its walk, a rite on the
    /// altar): out over 0.2 s, under the clip that replaces it.
    func interruptBreak() {
        guard breakPlayer != nil else { return }
        breakTimer?.invalidate()
        breakTimer = nil
        letGoOfBreak(over: Self.interruptBlendOut)
    }

    /// The break blends out and, once it has, comes off the figure. The
    /// removal is a timer of its own, kept by nobody: it takes off exactly
    /// the key it was given, so a break begun inside those half a second
    /// (the island's next stir) is never touched, and it does nothing once
    /// the layer has gone.
    private func letGoOfBreak(over seconds: TimeInterval) {
        guard let player = breakPlayer, let key = breakKey else { return }
        player.stop(withBlendOutDuration: seconds)
        breakPlayer = nil
        breakKey = nil
        gaze?.state.setStrength(1)
        _ = after(seconds + 0.05) { layer in
            layer.figure?.removeAnimation(forKey: key)
            layer.armFidget()
        }
    }

    /// The next break: the family's own two times in three when it has a
    /// victory too, never the victory twice running; whichever it has when
    /// it has one; nil when it has neither.
    private func nextBreak() -> PoseBreak? {
        let all: [PoseBreak] = breakChoices()
        guard let first = all.first else { return nil }
        guard all.count > 1 else { return first }
        let own: PoseBreak? = all.first { $0.name == PoseBreak.own }
        let victory: PoseBreak? = all.first { $0.name == PoseBreak.victory }
        if lastBreak == PoseBreak.victory { return own ?? first }
        return Double.random(in: 0..<1) < Self.ownBreakShare ? (own ?? first) : (victory ?? first)
    }

    /// What the family can break with, found once, on the main thread (a
    /// bundle lookup each; the clips themselves are in the model cache by
    /// then, from `warmBreaks` or, on the reveal, the entrance).
    private func breakChoices() -> [PoseBreak] {
        if let choices { return choices }
        var found: [PoseBreak] = []
        let library = ModelLibrary.shared
        if library.hasClipFile(.idleBreak, for: clips), let clip = library.animation(.idleBreak, for: clips) {
            let length: TimeInterval = clip.duration
            let end: TimeInterval = max(Self.breakBlendIn + 0.1, length - Self.breakBlendOut)
            found.append(PoseBreak(name: PoseBreak.own, clip: clip, start: 0, end: end,
                                   apex: length * 0.5, preset: "its own"))
        }
        if library.hasClipFile(.victory, for: clips), let clip = library.animation(.victory, for: clips) {
            // The window the reveal measured for the preset: the part of the
            // victory that faces the lens (412 turns its back after 1.6 s).
            // A bow is a greeting, never a fidget: a figure that bowed to
            // no one every half minute would read as broken (the mystics'
            // and graces' victory since 2026-09-25, `RevealEntrance.bow`).
            let cut: RevealEntranceCut = RevealEntrance.cut(forClipLength: clip.duration)
            if RevealEntrance.breaks(cut) {
                found.append(PoseBreak(name: PoseBreak.victory, clip: clip, start: cut.start, end: cut.end,
                                       apex: cut.apex, preset: cut.preset))
            }
        }
        choices = found
        return found
    }

    /// The break clips parsed off the main thread, a few seconds after the
    /// life begins (at once under `-tour-fidget`), so the first break reads
    /// them from the model cache.
    private func warmBreaks() {
        guard !stopped else { return }
        let asset = clips
        let library = ModelLibrary.shared
        let own = library.hasClipFile(.idleBreak, for: asset)
        let victory = library.hasClipFile(.victory, for: asset)
        guard own || victory else { return }
        DispatchQueue.global(qos: .utility).async {
            if own { _ = library.animation(.idleBreak, for: asset) }
            if victory { _ = library.animation(.victory, for: asset) }
        }
    }

    // MARK: Clocks

    /// A one-shot main-run-loop timer whose target holds this layer weakly
    /// (`WeakTickTarget`): the action is handed the layer, so it captures
    /// nothing, and the timer does nothing once the layer has gone.
    private func after(_ delay: TimeInterval, _ action: @escaping (PoseLayer) -> Void) -> Timer {
        let target = WeakTickTarget { [weak self] in
            if let self { action(self) }
            return false
        }
        let timer = Timer(timeInterval: max(0.01, delay), target: target,
                          selector: #selector(WeakTickTarget.tick(_:)), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: The gaze (build step 6)

    /// Hangs the gaze on the figure once its life has begun and its stage
    /// has named a lens (`lens`): the reveal's after its entrance, the
    /// altar's and the collection's at once. Never on the island, which
    /// names none, and never in a fight, which makes no layer.
    private func startGaze() {
        guard living, !stopped, gaze == nil, Self.gazes, let figure, let lens else { return }
        guard let made = Gaze(figure: figure, lens: lens) else {
            report("no gaze: \(clips) has no head over a neck")
            return
        }
        if let direction = Self.tourGazeDirection {
            made.state.setFixedDirection(direction)
        }
        gaze = made
        report(Self.tourGazeDirection == nil ? "the gaze toward the lens" : "the gaze held off the figure's front (-tour-gaze)")
        #if DEBUG
        if PoseTour.touring {
            gazeTimer = after(Self.gazeReportAfter) { layer in
                layer.gazeTimer = nil
                layer.reportGaze()
            }
        }
        #endif
    }

    /// Whether the figure stages hang a gaze: not under the pose lab, which
    /// turns the same joint and measures the clip's head without it.
    static var gazes: Bool {
        #if DEBUG
        return PoseLab.mode == nil
        #else
        return true
        #endif
    }

    /// `-tour-gaze left|right`: a direction in the figure's frame the gaze
    /// holds to instead of the lens. Nil outside the tour.
    static var tourGazeDirection: SIMD3<Float>? {
        #if DEBUG
        return PoseTour.gazeDirection
        #else
        return nil
        #endif
    }

    /// Seconds after the gaze is hung that the tour's `[Gaze]` line reads
    /// it: long enough to have settled (`Gaze.followTime` 0.35 s).
    static let gazeReportAfter: TimeInterval = 3

    /// `[Gaze]`: the turn the block lays on and where the lens stands,
    /// under the tour.
    private func reportGaze() {
        #if DEBUG
        guard let gaze else { return }
        let seen = gaze.state.reading()
        // Where the face points, measured, beside where the lens stands: the
        // two share a sign when the gaze turns the head toward the lens.
        let face: Float = gaze.faceAcross() ?? .nan
        print(String(format: "[Gaze] %@ %@: the head turned %+.1f° across and %+.1f° up over its clip, the lens %+.1f° off its front, the face %+.1f°, strength %.2f, %d frames",
                     label, clips, seen.yaw, seen.pitch, seen.across, face, seen.strength, seen.frames))
        #endif
    }

    // MARK: The tour

    /// The key of the tour's scene-clock actions on the figure.
    static let tourKey = "pose_tour"
    /// Seconds of the stage's own time before `-tour-fidget`'s break: the
    /// stage is drawing by then, so the break starts in a live scene.
    static let tourFidgetLead: TimeInterval = 0.8

    /// `-tour-fidget`: a break once the stage has drawn for a moment, on the
    /// scene's clock, then held on its high point (`fidget`).
    private func fidgetForTour() {
        guard let figure else { return }
        report(String(format: "-tour-fidget: a break in %.1f s of the stage's time", Self.tourFidgetLead))
        figure.runAction(.sequence([
            .wait(duration: Self.tourFidgetLead),
            .run { [weak self] _ in
                DispatchQueue.main.async { self?.fidgetNowForTour() }
            },
        ]), forKey: Self.tourKey)
    }

    private func fidgetNowForTour() {
        guard living, !fidget() else { return }
        report(isHeld
               ? "-tour-fidget: the stage is out of sight, so no break"
               : "-tour-fidget: \(clips) has no break and no victory to break with")
    }

    /// The tour's break stops on its high point and stays.
    private func holdBreakForTour() {
        guard living, let player = breakPlayer else { return }
        player.paused = true
        report("-tour-fidget: the break held on its high point")
        #if DEBUG
        print("[TourCue] fidget-held")
        #endif
    }

    /// `-tour-pose-blend X` (TourView's `PoseTour`): the variant held at X,
    /// no shifts. Nil outside the tour.
    static var pinnedBlend: CGFloat? {
        #if DEBUG
        return PoseTour.pinnedBlend
        #else
        return nil
        #endif
    }

    /// `-tour-fidget`: a break as the life begins (after `tourFidgetLead`),
    /// held on its high point.
    static var fidgetsAtOnce: Bool {
        #if DEBUG
        return PoseTour.fidgetAtOnce
        #else
        return false
        #endif
    }

    /// `[Pose]` lines under the tour: what happened and every player on the
    /// figure with its blend, read on the main thread at the moment of the
    /// event (never on a timer through a beat), the first eighty a launch.
    private func report(_ what: String) {
        #if DEBUG
        guard PoseTour.touring, Self.reported < 80 else { return }
        Self.reported += 1
        var players: [String] = []
        if let figure {
            for key in figure.animationKeys.sorted() {
                guard let player = figure.animationPlayer(forKey: key) else { continue }
                players.append(String(format: "%@ %.2f%@", key, player.blendFactor, player.paused ? " held" : ""))
            }
        }
        print("[Pose] \(label) \(clips): \(what); players [\(players.joined(separator: ", "))]")
        #endif
    }

    #if DEBUG
    private static var reported = 0
    #endif
}

/// Where a figure's idle stands in its cycle: started at `phase` (a share)
/// at `began` (the media clock), running at `speed` over `cycle` seconds.
/// The idle plays on the system time base (`startLoop`, `UnitNode.play`), so
/// the media clock is its clock.
struct IdleBeat {
    let began: CFTimeInterval
    let phase: Double
    let speed: CGFloat
    let cycle: TimeInterval

    /// The share of the cycle the idle has reached at `now`, in 0..<1.
    func share(at now: CFTimeInterval) -> Double {
        guard cycle > 0.05 else { return phase }
        let reached: Double = phase + max(0, now - began) * Double(speed) / cycle
        return reached - reached.rounded(.down)
    }
}

/// A break a family can play: which clip, and the window of it.
struct PoseBreak {
    static let own = "break"
    static let victory = "victory"

    /// `own` (the family's `_break`) or `victory`.
    let name: String
    let clip: CAAnimation
    /// Seconds into the clip the break starts from, lets go at (the blend
    /// out begins), and reaches its high point at.
    let start: TimeInterval
    let end: TimeInterval
    let apex: TimeInterval
    /// For the console: the victory's preset, or "its own".
    let preset: String
}
