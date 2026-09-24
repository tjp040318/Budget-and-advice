import Foundation
import SceneKit

/// The battle camera's shake (Docs/FEEL.md W2.18), after Squirrel Eiserloh's
/// "Math for Game Programmers: Juicing Your Cameras With Math" (GDC 2016):
/// every hit adds TRAUMA, 0…1, which falls away at `decay` a second, and the
/// shake is trauma SQUARED — a graze barely stirs the frame, a killing blow
/// or a boss's roar rocks it, and a flurry of hits climbs instead of
/// restarting the same wobble. Each channel — roll, yaw, pitch and the two
/// shifts across the lens — rides its own smooth noise, so the camera shakes
/// like a held camera and never like a sine wave.
///
/// It replaces a sine wobble along WORLD x (`CameraDirector.shake`, an
/// action on the camera node) that pulled the camera back to a stale point
/// in the middle of a dolly — the skill zoom's position was the shake's
/// "origin" — and partly toward the lens once the camera had any yaw. The
/// camera now hangs under a rig: the director's moves (the home framing,
/// the zoom, the final blow's ease, the triumph's frame) move the RIG, and
/// this moves only the lens, in the rig's own frame, so the two never fight.
///
/// Written on the render thread in `renderer(_:updateAtTime:)`
/// (`BattleSceneController.renderUpdate`), where SceneKit applies a change
/// directly: the plates' `projectPoint` in `willRenderScene` reads the
/// shaken camera, so the bars shake with the world they hang over. The main
/// thread only adds trauma, a kick or a rumble, under the lock.
///
/// THE ROLL IS SMALL ON PURPOSE. The owner has twice turned down a camera
/// that read as slanted (the 58° yaw and the 20° "ramp"); 2.2° at full
/// trauma is a jolt that is gone in a few frames, never a tilt, and a hit
/// under full trauma is rare — a boss's roar, a stack of crits.
final class CameraShake {

    // MARK: The numbers

    /// Trauma lost a second at ×1: a normal hit's 0.18 is gone in a tenth
    /// of a second, a roar's 0.8 in under half.
    static let decay: Float = 1.8
    /// At full trauma: the roll, the yaw and the pitch (radians), and the
    /// shift along the lens's own x and y (metres).
    static let maxRoll: Float = 2.2 * .pi / 180
    static let maxYaw: Float = 0.6 * .pi / 180
    static let maxPitch: Float = 0.6 * .pi / 180
    static let maxShift: Float = 0.03
    /// How fast the noise runs, in lattice cells a second: a shake about
    /// fourteen swings a second, a hand's tremble rather than a wobble.
    static let noiseRate: Double = 14
    /// The kick along the hit (4–6 cm): out in `kickOut`, back by
    /// `kickLength`, easing home.
    static let kickOut: Double = 0.035
    static let kickLength: Double = 0.2

    // MARK: State (under `lock`; the render thread reads, the main thread adds)

    private let lock = NSLock()
    private var trauma: Float = 0
    /// Trauma lost a second, the player's speed through it (`add`).
    private var decayRate: Float = CameraShake.decay
    /// A floor trauma cannot fall under until `floorUntil` — a boss
    /// climbing the rim rumbles the whole climb (`rumble`).
    private var floorLevel: Float = 0
    private var floorUntil: CFTimeInterval = 0
    /// Seconds of unpaused frames: the noise's clock, which a hit-stop holds.
    private var clock: Double = 0
    private var lastTime: TimeInterval?
    /// The kick: its offset along the lens's x and y (metres) and its age.
    private var kickX: Float = 0
    private var kickY: Float = 0
    private var kickAge: Double = .infinity
    /// The render thread's: the lens was last written at rest.
    private var atRest = true
    #if DEBUG
    /// Under `-tour-shake`, the lens stands at the shake's peak until then.
    private var peakUntil: CFTimeInterval = 0
    #endif

    // MARK: The main thread's side

    /// A hit's trauma, at the player's speed (`Juice.trauma(for:speed:)`
    /// already carries ×3's share): it adds to what is there, capped at 1,
    /// and falls `decay` times the speed a second, so ×2 shakes as hard for
    /// half as long, as the sine did. Nothing under Reduce Motion.
    func add(_ amount: Float, speed: Double) {
        guard amount > 0, !MotionComfort.isReduced else { return }
        lock.lock()
        trauma = min(1, trauma + amount)
        decayRate = Self.decayRate(speed: speed)
        lock.unlock()
    }

    /// Trauma lost a second at the player's speed: ×2 halves a shake's
    /// length and ×3 takes a third of it, as the sine's lengths were.
    static func decayRate(speed: Double) -> Float {
        decay * Float(max(1, speed))
    }

    /// A jolt `metres` along the hit's direction on the screen (`right` and
    /// `up` in the lens's own axes, any length; normalised here): out and
    /// back inside a fifth of a second.
    func kick(right: Float, up: Float, metres: Float) {
        guard metres > 0, !MotionComfort.isReduced else { return }
        let length: Float = (right * right + up * up).squareRoot()
        guard length > 0.0001 else { return }
        lock.lock()
        kickX = right / length * metres
        kickY = up / length * metres
        kickAge = 0
        lock.unlock()
    }

    /// Trauma held at `level` or over for `seconds` (a boss climbing over
    /// the rim, sinking back under it).
    func rumble(_ level: Float, for seconds: TimeInterval) {
        guard level > 0, seconds > 0, !MotionComfort.isReduced else { return }
        lock.lock()
        floorLevel = min(1, level)
        floorUntil = CACurrentMediaTime() + seconds
        trauma = max(trauma, floorLevel)
        lock.unlock()
    }

    #if DEBUG
    /// The CI tour's `-tour-shake`: the lens stands at the shake's peak — the
    /// most roll, yaw, pitch and shift full trauma reaches, all at once —
    /// for `seconds`, the frame the roll is judged on.
    func pinPeak(for seconds: TimeInterval) {
        lock.lock()
        peakUntil = CACurrentMediaTime() + seconds
        lock.unlock()
    }
    #endif

    /// Everything stops at once: a skip, a forfeit, a new run.
    func stop() {
        lock.lock()
        trauma = 0
        floorLevel = 0
        floorUntil = 0
        kickAge = .infinity
        lock.unlock()
    }

    // MARK: The render thread's side

    /// Advances the shake to `time` (the renderer's clock) and writes it on
    /// `lens`, the camera node hanging at rest under its rig. `paused` is
    /// the scene's hit-stop: the shake holds where it is through a freeze,
    /// as the world does. At rest the lens is written back to the identity
    /// once and then left alone.
    func apply(to lens: SCNNode, at time: TimeInterval, paused: Bool) {
        lock.lock()
        let step: Double = lastTime.map { max(0, min(0.1, time - $0)) } ?? 0
        lastTime = time
        if !paused {
            clock += step
            trauma = max(0, trauma - decayRate * Float(step))
            if kickAge < Self.kickLength { kickAge += step }
        }
        let now = CACurrentMediaTime()
        let level: Float = max(trauma, now < floorUntil ? floorLevel : 0)
        let kick: Float = Self.kickEnvelope(kickAge)
        let kickRight: Float = kickX * kick
        let kickUp: Float = kickY * kick
        let noiseClock: Double = clock * Self.noiseRate
        var pinned = false
        #if DEBUG
        pinned = now < peakUntil
        #endif
        lock.unlock()
        if pinned {
            atRest = false
            lens.position = SCNVector3(Self.maxShift, Self.maxShift, 0)
            lens.eulerAngles = SCNVector3(Self.maxPitch, Self.maxYaw, Self.maxRoll)
            return
        }

        let offsets = Self.offsets(trauma: level, at: noiseClock)
        let moving = offsets.shake > 0 || kick > 0
        guard moving else {
            if !atRest {
                lens.position = SCNVector3(0, 0, 0)
                lens.eulerAngles = SCNVector3(0, 0, 0)
                atRest = true
            }
            return
        }
        atRest = false
        lens.position = SCNVector3(offsets.right + kickRight, offsets.up + kickUp, 0)
        lens.eulerAngles = SCNVector3(offsets.pitch, offsets.yaw, offsets.roll)
    }

    // MARK: The sums (pure, pinned in BattleFeelTests)

    /// The shake at `trauma`, `noiseClock` cells into the noise: each channel
    /// its own stretch of the one noise, scaled by trauma squared.
    static func offsets(trauma: Float, at noiseClock: Double)
        -> (shake: Float, roll: Float, yaw: Float, pitch: Float, right: Float, up: Float) {
        let level: Float = min(1, max(0, trauma))
        let shake: Float = level * level
        guard shake > 0 else { return (0, 0, 0, 0, 0, 0) }
        let roll: Float = maxRoll * shake * Float(noise(noiseClock))
        let yaw: Float = maxYaw * shake * Float(noise(noiseClock + 37.3))
        let pitch: Float = maxPitch * shake * Float(noise(noiseClock + 71.9))
        let right: Float = maxShift * shake * Float(noise(noiseClock + 113.7))
        let up: Float = maxShift * shake * Float(noise(noiseClock + 151.1))
        return (shake, roll, yaw, pitch, right, up)
    }

    /// How far out the kick stands `age` seconds after it: straight out in
    /// `kickOut`, eased home by `kickLength`; 0 before and after.
    static func kickEnvelope(_ age: Double) -> Float {
        guard age >= 0, age < kickLength else { return 0 }
        if age < kickOut { return Float(age / kickOut) }
        let back: Double = (age - kickOut) / (kickLength - kickOut)
        let left: Double = 1 - back
        return Float(left * left)
    }

    /// Smooth gradient noise in −1…1 (Perlin's, in one dimension): a
    /// gradient at every whole number from a hash, the two either side of
    /// `x` blended with the quintic fade, so the value and its slope are
    /// continuous and the shake has no corners.
    static func noise(_ x: Double) -> Double {
        let cell: Double = x.rounded(.down)
        let t: Double = x - cell
        let index = Int(cell)
        let left: Double = gradient(index) * t
        let right: Double = gradient(index &+ 1) * (t - 1)
        let fade: Double = t * t * t * (t * (t * 6 - 15) + 10)
        let value: Double = (left + (right - left) * fade) * 2
        return min(1, max(-1, value))
    }

    /// A gradient in −1…1 for a lattice point, from an integer hash.
    private static func gradient(_ index: Int) -> Double {
        var hash = UInt32(truncatingIfNeeded: index &* 374_761_393)
        hash = (hash ^ (hash >> 13)) &* 1_274_126_177
        hash ^= hash >> 16
        let unit: Double = Double(hash & 0xFFFF) / 65_535
        return unit * 2 - 1
    }
}
