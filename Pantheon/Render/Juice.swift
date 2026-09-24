import Foundation
import SceneKit
import UIKit

/// How hard a hit lands, for the purpose of feedback. Decided at presentation
/// time from the event and the clip that caused it; the engine knows nothing
/// about any of this.
enum HitWeight {
    /// A glancing blow.
    case light
    /// An ordinary hit.
    case normal
    /// A heavy attack or an ultimate's hit.
    case heavy
    /// A critical.
    case critical
    /// A killing blow.
    case lethal
}

/// Impact feedback — the freeze-frame, the shake, the haptic, the number pop —
/// scaled by how hard the hit was.
///
/// This is most of what separates "watching numbers change" from "hitting
/// something". Every magnitude lives in `profile(for:)` so the feel can be
/// tuned in one place, and everything is scaled by the playback speed the
/// player picked: ×2 stays snappy rather than mushy, and ×3 keeps the feel
/// at a third of its length rather than losing it (Docs/FEEL.md W1.1). The
/// skip button is the one way to watch a turn with none of it: it flushes the
/// queue, so no hit is presented at all.
///
/// The freeze is `SCNScene.isPaused`, which stops every action and animation
/// in the scene for a few frames while the view keeps drawing the last one.
/// That is exactly the classic hit-stop and it costs nothing. The shake fires
/// on release, not on impact — a shake during a freeze is invisible. Inside
/// the freeze the VICTIM trembles (`Tremor`) while the attacker holds still,
/// which is what says "the blade met resistance" rather than "the video
/// paused" (Smash's hitlag; Docs/FEEL.md W1.3).
enum Juice {

    struct Profile {
        /// Seconds the world freezes on impact, before the blow's share of
        /// its victim's health adds to it (`freeze(for:share:early:speed:)`).
        var pause: TimeInterval
        /// Camera shake amplitude in metres, and how long it decays.
        var shake: Float
        var shakeDuration: TimeInterval
        /// Haptic, if any.
        var haptic: UIImpactFeedbackGenerator.FeedbackStyle?
        /// Size multiplier for the damage number.
        var numberScale: CGFloat
    }

    static func profile(for weight: HitWeight) -> Profile {
        switch weight {
        case .light:    return Profile(pause: 0.00, shake: 0.00, shakeDuration: 0.00, haptic: nil,     numberScale: 0.85)
        case .normal:   return Profile(pause: 0.045, shake: 0.05, shakeDuration: 0.14, haptic: .light,  numberScale: 1.00)
        case .heavy:    return Profile(pause: 0.075, shake: 0.12, shakeDuration: 0.24, haptic: .medium, numberScale: 1.15)
        case .critical: return Profile(pause: 0.090, shake: 0.16, shakeDuration: 0.28, haptic: .medium, numberScale: 1.40)
        case .lethal:   return Profile(pause: 0.150, shake: 0.22, shakeDuration: 0.40, haptic: .heavy,  numberScale: 1.60)
        }
    }

    // MARK: - Scaled by the player's speed (W1.1)
    //
    // The control stepped 1 → 2 → 4 and at 4 a skip threshold (3.5) switched
    // every freeze, shake and haptic off, so a player who tapped it twice lost
    // the fight's whole feel without knowing why. It steps 1 → 2 → 3 now and
    // nothing is switched off: ×2 is as it always was (every length halved),
    // ×3 divides the freeze by three with a 20 ms floor, halves the shake, and
    // keeps the haptic for the three blows worth a thumb — a crit, a kill and
    // an ultimate. A speed over ×3 (the stress tour's) is scaled the same way.

    /// Past this the player is watching at ×3: the shake is halved and only
    /// a crit, a kill or an ultimate buzzes.
    static let fastSpeed: Double = 2.5

    static func isFast(_ speed: Double) -> Bool { speed > fastSpeed }

    // MARK: - The freeze (W1.3)

    /// The longest a hit's freeze may be (the final blow has its own,
    /// `finalBlowFreeze`).
    static let longestFreeze: TimeInterval = 0.22
    /// What a blow adds to its weight's freeze when it takes a third of its
    /// victim's health or more — less in proportion under that — so a crit
    /// for 40 and a crit for 4,000 no longer freeze for the same 90 ms.
    static let freezeForShare: TimeInterval = 0.10
    /// A multi-hit's early hits freeze for this much of a whole hit's.
    static let earlyHitFreeze: Double = 0.6
    /// The shortest freeze worth making: a little over a frame at 60 Hz. It
    /// is the floor ×3 divides down to.
    static let shortestFreeze: TimeInterval = 0.02
    /// The blow that ends a wave or the fight (W1.7): a fifth of a second
    /// held, then the slow motion (`BattleSceneController`).
    static let finalBlowFreeze: TimeInterval = 0.2
    /// The shortest freeze the victim trembles in: under it the tremble is a
    /// frame, which reads as a glitch.
    static let tremorFloor: TimeInterval = 0.03

    /// How long a hit holds the world: its weight's pause, plus up to
    /// `freezeForShare` as the blow's share of its victim's health rises to a
    /// third (`0.10 × min(1, 3 × damage ÷ max health)`), capped at
    /// `longestFreeze`; a multi-hit's early hit takes `earlyHitFreeze` of
    /// that; and the whole is scaled by the player's speed
    /// (`scaledFreeze`). A glancing blow does not freeze.
    static func freeze(for weight: HitWeight, share: Double, early: Bool, speed: Double) -> TimeInterval {
        let base: TimeInterval = profile(for: weight).pause
        guard base > 0 else { return 0 }
        let bite: Double = min(1, max(0, 3 * share))
        let grown: TimeInterval = min(longestFreeze, base + freezeForShare * bite)
        let hit: TimeInterval = early ? grown * earlyHitFreeze : grown
        return scaledFreeze(hit, speed: speed)
    }

    /// A freeze at the player's speed: divided by it (×2 halves it, as it
    /// always has; ×3 is a third), never under `shortestFreeze`.
    static func scaledFreeze(_ seconds: TimeInterval, speed: Double) -> TimeInterval {
        guard seconds > 0 else { return 0 }
        let divisor: Double = max(1, speed)
        return max(shortestFreeze, seconds / divisor)
    }

    /// The camera's shake for a hit at the player's speed: its length divided
    /// by the speed, as it always was, and its size halved at ×3.
    static func shake(for weight: HitWeight, speed: Double) -> (intensity: Float, duration: TimeInterval) {
        let p = profile(for: weight)
        guard p.shake > 0 else { return (0, 0) }
        let divisor: Double = max(1, speed)
        let intensity: Float = isFast(speed) ? p.shake * 0.5 : p.shake
        return (intensity, p.shakeDuration / divisor)
    }

    /// Whether a hit buzzes the thumb: every weight that has a haptic, and at
    /// ×3 only a crit, a kill or an ultimate's hit.
    static func hapticFires(for weight: HitWeight, speed: Double, ultimate: Bool) -> Bool {
        guard profile(for: weight).haptic != nil else { return false }
        guard isFast(speed) else { return true }
        return weight == .critical || weight == .lethal || ultimate
    }

    /// Only the most recent freeze may release the scene. Multi-hit skills land
    /// their hits a few frames apart, and without this the first hit's release
    /// would cut the second hit's freeze short.
    private static var pauseGeneration = 0

    /// The colour of a hit: what struck, as opposed to how hard.
    ///
    /// The tier alone made every blow the same event at five volumes. A cut,
    /// a mace and a spell are different sounds in any game that feels
    /// expensive, and the files exist for all three plus one per element, so
    /// a hit now plays its weight AND a quieter layer saying what it was.
    enum HitColour {
        case blade, blunt, magic, element(Element)

        var sound: AudioLibrary.Sound {
            switch self {
            case .blade: return .hitBlade
            case .blunt: return .hitBlunt
            case .magic: return .hitMagic
            case .element(let element):
                switch element {
                case .ember: return .impactEmber
                case .tide: return .impactTide
                case .gale: return .impactGale
                case .radiance: return .impactRadiance
                case .umbra: return .impactUmbra
                }
            }
        }
    }

    /// Plays the impact for a hit. Returns how long the world froze, so the
    /// caller can extend its hold by that much and keep the event cadence.
    ///
    /// `share` is the blow's damage over its victim's maximum health, `early`
    /// marks a multi-hit's hit before its last, `ultimate` an ultimate's hit
    /// (it keeps its haptic at ×3). `freezeFor` replaces the computed freeze
    /// (the final blow's), and `shakes` false keeps the camera still (the
    /// final blow's camera is the slow motion's). `victim` trembles inside
    /// the freeze — never under Reduce Motion.
    @discardableResult
    static func impact(
        _ weight: HitWeight,
        colour: HitColour? = nil,
        share: Double = 0,
        early: Bool = false,
        ultimate: Bool = false,
        freezeFor fixed: TimeInterval? = nil,
        shakes: Bool = true,
        victim: UnitNode? = nil,
        scene: SCNScene,
        director: CameraDirector?,
        speed: Double
    ) -> TimeInterval {
        let p = profile(for: weight)

        // The haptic and the sound go with the freeze, not the release: the
        // thumb and the ear should get the hit at the instant the eye sees the
        // world stop.
        if hapticFires(for: weight, speed: speed, ultimate: ultimate), let style = p.haptic { haptic(style) }
        AudioLibrary.shared.play(sound(for: weight))
        // The colour sits under the weight, quieter and a touch later, so the
        // two read as one hit rather than two sounds.
        if let colour {
            AudioLibrary.shared.play(colour.sound, volume: 0.55, delay: 0.02)
        }

        let kick = shake(for: weight, speed: speed)
        let shakesCamera: Bool = shakes && kick.intensity > 0
        let pause: TimeInterval = fixed ?? freeze(for: weight, share: share, early: early, speed: speed)
        guard pause > 0 else {
            if shakesCamera { director?.shake(intensity: kick.intensity, duration: kick.duration) }
            return 0
        }

        pauseGeneration += 1
        let generation = pauseGeneration
        scene.isPaused = true
        // The victim trembles through the freeze while everything else, the
        // attacker included, holds still.
        stopTremor()
        if let victim, pause >= tremorFloor, !MotionComfort.isReduced {
            let tremor = Tremor(
                body: victim.tremorBody,
                amplitude: tremorAmplitude(forHeight: victim.spec.height),
                duration: pause
            )
            Juice.tremor = tremor
            tremor.start()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
            guard generation == pauseGeneration else { return }
            // Back on its rest position BEFORE the world moves again, so the
            // recoil and the clip take the body up from where they left it.
            stopTremor()
            scene.isPaused = false
            if shakesCamera {
                director?.shake(intensity: kick.intensity, duration: kick.duration)
            }
        }
        return pause
    }

    static func sound(for weight: HitWeight) -> AudioLibrary.Sound {
        switch weight {
        case .light: return .hitLight
        case .normal: return .hitNormal
        case .heavy: return .hitHeavy
        case .critical: return .hitCrit
        case .lethal: return .hitLethal
        }
    }

    /// Belt and braces: anything that tears the scene down while a freeze is
    /// pending must not leave it paused, nor a body off its mark.
    static func release(_ scene: SCNScene) {
        pauseGeneration += 1
        stopTremor()
        scene.isPaused = false
    }

    // MARK: - The tremble inside the freeze (W1.3)

    /// The tremble's rate: about two frames a swing at 60 Hz, the rate a
    /// fighting game shakes a body inside its hitlag.
    static let tremorHertz: Double = 30

    /// How far the body shakes, in metres: 2.5 cm on a 1.9 m figure, in
    /// proportion to height, held inside 2–10 cm so a giant's tremble is
    /// still seen and a small one's is not a wobble.
    static func tremorAmplitude(forHeight height: Float) -> Float {
        let scaled: Float = height * 0.013
        return min(0.10, max(0.02, scaled))
    }

    /// The body's offset `t` seconds into a tremble that lasts `duration`:
    /// across the line of the blow and a little along it, at `tremorHertz`,
    /// dying away to nothing by the release. Metres, in the body's parent's
    /// frame, whose −Z is away from the blow (`UnitNode.recoil`).
    static func tremorOffset(at t: TimeInterval, of duration: TimeInterval, amplitude: Float) -> (across: Float, along: Float) {
        let life: Double = max(0.001, duration)
        let left: Double = max(0, 1 - t / life)
        let decay = Float(left)
        let phase: Double = 2 * Double.pi * tremorHertz * t
        let across: Float = amplitude * decay * Float(sin(phase))
        let along: Float = amplitude * 0.6 * decay * Float(sin(phase * 1.37 + 1.1))
        return (across, along)
    }

    /// The tremble in progress, if any: one at a time, the newest freeze's.
    private static var tremor: Tremor?

    /// Ends the tremble in progress, with its body back on its rest position.
    static func stopTremor() {
        tremor?.settle()
        tremor = nil
    }

    // MARK: - Haptics

    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static let notifier = UINotificationFeedbackGenerator()

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator: UIImpactFeedbackGenerator
        if let existing = impactGenerators[style] {
            generator = existing
        } else {
            generator = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = generator
        }
        generator.impactOccurred()
    }

    /// Warms the Taptic Engine so the first hit of a cast is not late.
    static func prepareHaptics() {
        for style in [UIImpactFeedbackGenerator.FeedbackStyle.light, .medium, .heavy] {
            if impactGenerators[style] == nil {
                impactGenerators[style] = UIImpactFeedbackGenerator(style: style)
            }
            impactGenerators[style]?.prepare()
        }
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notifier.notificationOccurred(type)
    }

    // MARK: - Number pop

    /// The entrance for a floating number: snaps in oversized, settles, then
    /// the caller's rise-and-fade takes over. A number that simply appears at
    /// full size reads as a label; one that pops reads as a consequence.
    static func popAction(scale: CGFloat) -> SCNAction {
        let overshoot = SCNAction.scale(to: scale * 1.12, duration: 0.07)
        overshoot.timingMode = .easeOut
        let settle = SCNAction.scale(to: scale, duration: 0.06)
        settle.timingMode = .easeInEaseOut
        return .sequence([overshoot, settle])
    }
}

/// A victim shaking inside its hit's freeze (Docs/FEEL.md W1.3): a
/// main-thread tick (`FrameTicker`) writes the body's position while the
/// scene is paused — the pause stops every action and clip, and the view
/// keeps drawing, so the body alone moves — and `settle` puts it back on its
/// rest position exactly before the world moves again. It touches nothing
/// inside an `SCNAction` block, and it offsets only across and along the
/// ground, so the leap's height, written by an action, is never fought over.
///
/// A tick RETAINS its target, so the target holds this weakly: a tremble
/// whose body has gone stops itself on its next tick, and
/// `Juice.stopTremor` (every release, every flush, every new run) stops it
/// at once.
final class Tremor {
    private weak var body: SCNNode?
    private let rest: SCNVector3
    private let amplitude: Float
    private let duration: CFTimeInterval
    private let began: CFTimeInterval
    private var ticker: FrameTicker?

    init(body: SCNNode, amplitude: Float, duration: CFTimeInterval) {
        self.body = body
        self.rest = body.position
        self.amplitude = amplitude
        self.duration = max(0.01, duration)
        self.began = CACurrentMediaTime()
    }

    func start() {
        ticker = FrameTicker { [weak self] in
            self?.step() ?? false
        }
        _ = step()
    }

    /// One frame of the tremble; false once it is over, which stops the tick.
    private func step() -> Bool {
        guard let body else { return false }
        let elapsed: CFTimeInterval = CACurrentMediaTime() - began
        guard elapsed < duration else {
            settle()
            return false
        }
        let offset = Juice.tremorOffset(at: elapsed, of: duration, amplitude: amplitude)
        body.position = SCNVector3(rest.x + offset.across, rest.y, rest.z + offset.along)
        return true
    }

    /// The tick stopped and the body on its rest position.
    func settle() {
        ticker?.stop()
        ticker = nil
        body?.position = rest
    }
}

/// A main-thread tick for motion written frame by frame from the main
/// thread — the tremble inside a freeze (`Tremor`) and the final blow's slow
/// motion (`BattleSceneController`) — at 120 a second, at or past the
/// display's own rate, in the run loop's common modes so a touch never holds
/// it. Each tick asks `step`, which reads the clock itself, so the rate only
/// sets how smooth it is; `step` answering false ends it.
///
/// A timer RETAINS its target, so a timer aimed straight at a controller
/// would keep the whole fight alive after its cover closed (the owner's
/// crashes were memory). Its target is a `WeakTickTarget` holding only the
/// step, which captures its owner weakly: the tick stops itself the first
/// time its owner has gone. (A display link would serve as well and is the
/// same shape; the checker's list of the frameworks' names does not carry
/// its name, so a timer on the main run loop it is.)
final class FrameTicker {
    private var timer: Timer?

    init(_ step: @escaping () -> Bool) {
        let target = WeakTickTarget(step)
        let timer = Timer(timeInterval: 1.0 / 120.0, target: target,
                          selector: #selector(WeakTickTarget.tick(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the tick. Main thread, where it runs.
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// The target a `FrameTicker`'s timer holds: the step alone, and the timer
/// stopped the first tick the step answers false.
final class WeakTickTarget: NSObject {
    private let step: () -> Bool

    init(_ step: @escaping () -> Bool) {
        self.step = step
        super.init()
    }

    @objc func tick(_ timer: Timer) {
        if !step() { timer.invalidate() }
    }
}
