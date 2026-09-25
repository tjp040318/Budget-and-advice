import Foundation
import SceneKit
import simd

// MARK: - The gaze (Docs/PLAN.md *Natural poses*, build step 6)
//
// A figure at rest on a stage looks at the one person looking at it. Its
// idle already turns its head (the survey and the glances of
// `tools/natural_idle.py`); the gaze lays a turn toward the lens OVER that,
// so the figure on the Hall of Ka's altar, the unit sheet and the
// collection's Stage — each stood in a three-quarter stance, or spun by a
// drag — keeps its face on the viewer, and a body turned away from the lens
// leads with its head. It is the craft's oldest portrait pose (the body
// angled, the face to the painter) and the genre's showcase screens' look.
//
// The pose lab settled the road (run 259's `[PoseLab]` lines, the verdict
// "SHOWS": +20.0° of +20 over the playing idle): an
// `SCNTransformConstraint` on the joint the head hangs from turns what the
// skinner is handed after the clips have written the joint, every frame. So
// the gaze is one constraint on that joint — `neck` on 106 rigs, the joint
// carrying the head's skin on the eleven that call the joint over the hips
// `neck` (the lab's finding) — laying a turn about the figure's upright and
// a nod about its side, clamped to ±25° and ±12°, eased toward the lens in
// the figure's own frame. Its block runs on SceneKit's render thread; it is
// built off the main actor and reads nothing but `GazeState`, through its
// lock. The lens is read off the presentation tree there, where the render
// thread keeps it, so a drag's spin and the reveal's push need no call.
//
// The gaze gives way to a break (a look-around is the head's own) and to an
// entrance (the life, and the gaze with it, begins after one), and lets go
// of a lens behind the figure's shoulder rather than swing across its back.
// Nothing here runs in a fight or on the island.

/// A figure's head turned toward the lens over whatever its clips hold it
/// at. Main thread only; the constraint's block reads only `state`.
final class Gaze {
    // MARK: The numbers

    /// The most the head is turned over the clip: 25° across and 12° up or
    /// down, the craft's head-look range. Past it the neck's skin, weighted
    /// to one joint on Meshy's rigs, twists visibly.
    static let maxYaw: Float = 25 * .pi / 180
    static let maxPitch: Float = 12 * .pi / 180
    /// The lens is looked at fully while it is within 80° of the figure's
    /// front, and not at all past 120° — behind a shoulder, where following
    /// it would swing the head from one side to the other as the figure is
    /// spun through its back.
    static let fullWithin: Float = 80 * .pi / 180
    static let noneBeyond: Float = 120 * .pi / 180
    /// The head follows with this time constant, in seconds: settled in
    /// about a second, a person's unhurried look rather than a turret's.
    static let followTime: Float = 0.35
    /// The gaze gives way to a break over this, and comes back over it.
    static let yieldTime: Float = 0.25
    /// Two orientations closer than this (radians, about half a degree) are
    /// one value handed back (`GazeState.turned`).
    static let sameAngle: Float = 0.01

    /// The block's state: the lens, the strength, the turn laid on.
    let state: GazeState
    /// The joint the constraint hangs on, while it does.
    private weak var joint: SCNNode?
    private let constraint: SCNTransformConstraint

    /// Finds the joint the head hangs from and hangs the gaze's constraint
    /// on it. Nil for a rig with no head over a neck. The figure must stand
    /// at rest in its model tree (a clone from `ModelLibrary.node`: a
    /// canonical rig's rest is its bind; the clips move the presentation).
    init?(figure: SCNNode, lens: SCNNode) {
        guard let head = Self.joint(named: "head", in: figure),
              let joint = head.parent, let above = joint.parent else { return nil }
        // The figure's upright and side in the frame of the turned joint's
        // parent at the bind: the axes the turn and the nod are laid about.
        let toFigure: simd_quatf = Self.rotation(of: figure.simdWorldTransform).inverse
        let aboveRest: simd_quatf = toFigure * Self.rotation(of: above.simdWorldTransform)
        let up: SIMD3<Float> = simd_normalize(aboveRest.inverse.act(SIMD3<Float>(0, 1, 0)))
        let side: SIMD3<Float> = simd_normalize(aboveRest.inverse.act(SIMD3<Float>(1, 0, 0)))
        let made = GazeState(figure: figure, lens: lens, up: up, side: side)
        state = made
        constraint = Self.headTurn(made)
        self.joint = joint
        var hung = joint.constraints ?? []
        hung.append(constraint)
        joint.constraints = hung
    }

    /// Takes the constraint off the joint: the head is the clip's again.
    func stop() {
        guard let joint else { return }
        let mine: SCNTransformConstraint = constraint
        joint.constraints = (joint.constraints ?? []).filter { $0 !== mine }
        self.joint = nil
    }

    /// The constraint, built here, off the main actor: SceneKit calls the
    /// block on its render thread in the middle of the frame, and a closure
    /// formed in a main-actor context carries a check that traps there
    /// under Swift 6 (the pose lab's `headTurn`).
    nonisolated static func headTurn(_ state: GazeState) -> SCNTransformConstraint {
        SCNTransformConstraint.orientationConstraint(inWorldSpace: false) { joint, orientation in
            state.turned(joint, orientation)
        }
    }

    /// How much of the turn toward a lens `across` radians off the figure's
    /// front is laid on: all of it within `fullWithin`, none past
    /// `noneBeyond`, eased between.
    static func reach(_ across: Float) -> Float {
        let off: Float = abs(across)
        if off <= fullWithin { return 1 }
        if off >= noneBeyond { return 0 }
        let x: Float = (noneBeyond - off) / (noneBeyond - fullWithin)
        return x * x * (3 - 2 * x)
    }

    /// The turn toward a direction in the figure's frame (+Z its front, +X
    /// its left, +Y up): radians across (toward its left) and up, clamped,
    /// and scaled by `reach`.
    static func aim(toward direction: SIMD3<Float>) -> (yaw: Float, pitch: Float) {
        let across: Float = atan2(direction.x, direction.z)
        let flat: Float = (direction.x * direction.x + direction.z * direction.z).squareRoot()
        let rise: Float = atan2(direction.y, flat)
        let share: Float = reach(across)
        let yaw: Float = min(maxYaw, max(-maxYaw, across)) * share
        let pitch: Float = min(maxPitch, max(-maxPitch, rise)) * share
        return (yaw, pitch)
    }

    /// The angle between two orientations, in radians.
    static func angle(between a: simd_quatf, _ b: simd_quatf) -> Float {
        let dot: Float = abs(simd_dot(a.vector, b.vector))
        return 2 * acos(min(1, dot))
    }

    /// The rotation of a world transform, its scale stripped (Meshy's
    /// joints carry the armature's scale).
    static func rotation(of m: simd_float4x4) -> simd_quatf {
        let c0: SIMD3<Float> = simd_normalize(SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z))
        let c1: SIMD3<Float> = simd_normalize(SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z))
        let c2: SIMD3<Float> = simd_normalize(SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        return simd_normalize(simd_quatf(simd_float3x3(columns: (c0, c1, c2))))
    }

    /// A joint by its lowercased name: every shipped rig has a `Head`.
    private static func joint(named key: String, in model: SCNNode) -> SCNNode? {
        let matches = model.childNodes { node, stop in
            if node.name?.lowercased() == key {
                stop.pointee = true
                return true
            }
            return false
        }
        return matches.first
    }
}

/// What the gaze's block reads and keeps, under a lock: the block runs on
/// SceneKit's render thread, and the strength and the tour's direction are
/// set on the main one (`ClipPace`'s pattern).
final class GazeState {
    private let lock = NSLock()
    private weak var figure: SCNNode?
    private weak var lens: SCNNode?
    /// The figure's upright and side in the turned joint's parent frame.
    private let up: SIMD3<Float>
    private let side: SIMD3<Float>
    /// 1 while the gaze leads the head, 0 while a break has it.
    private var strengthTarget: Float = 1
    /// Under the tour's `-tour-gaze left`: a direction in the figure's frame
    /// looked along instead of the lens.
    private var fixedDirection: SIMD3<Float>?

    // The render thread's, under the lock.
    /// Eased from 0: a figure's gaze comes to the lens as its life begins.
    private var strength: Float = 0
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var lastTime: CFTimeInterval = 0
    private var lastOut: simd_quatf?
    private var lastBase: simd_quatf?
    /// The lens's direction off the figure's front at the last frame, in
    /// radians: for the tour's lines.
    private var across: Float = 0
    private var frames = 0

    init(figure: SCNNode, lens: SCNNode, up: SIMD3<Float>, side: SIMD3<Float>) {
        self.figure = figure
        self.lens = lens
        self.up = up
        self.side = side
    }

    /// Main thread: 1 lets the gaze lead the head, 0 gives the head to the
    /// clips (a break).
    func setStrength(_ value: Float) {
        lock.lock()
        strengthTarget = min(1, max(0, value))
        lock.unlock()
    }

    /// Main thread: a direction in the figure's frame to look along instead
    /// of the lens (the tour's), or nil for the lens.
    func setFixedDirection(_ direction: SIMD3<Float>?) {
        lock.lock()
        fixedDirection = direction
        lock.unlock()
    }

    /// For the tour's `[Gaze]` lines: the turn laid on and the lens's place,
    /// in degrees, the strength, and the frames the block has run.
    func reading() -> (yaw: Float, pitch: Float, across: Float, strength: Float, frames: Int) {
        lock.lock()
        defer { lock.unlock() }
        let degrees: Float = 180 / .pi
        return (yaw * degrees, pitch * degrees, across * degrees, strength, frames)
    }

    /// The block's work, on the render thread: the joint's local orientation
    /// (in its parent's frame, as the constraint hands it over) turned
    /// toward the lens by the eased, clamped turn.
    func turned(_ joint: SCNNode, _ orientation: SCNVector4) -> SCNVector4 {
        let local = simd_quatf(ix: Float(orientation.x), iy: Float(orientation.y), iz: Float(orientation.z),
                               r: Float(orientation.w))
        lock.lock()
        defer { lock.unlock() }
        // The clip rewrites the joint every frame it plays it. Handed back its
        // own last answer, it did not, and turning that again would compound:
        // the turn is laid on the base it was laid on before.
        var base: simd_quatf = local
        if let lastOut, let lastBase, Gaze.angle(between: local, lastOut) < Gaze.sameAngle {
            base = lastBase
        }
        let now: CFTimeInterval = CACurrentMediaTime()
        let step: Float = lastTime == 0 ? 0 : Float(min(0.1, max(0, now - lastTime)))
        lastTime = now
        frames += 1
        var want: (yaw: Float, pitch: Float) = (0, 0)
        if let figure {
            var direction: SIMD3<Float>? = fixedDirection
            if direction == nil, let lens {
                let toLens: SIMD3<Float> = lens.presentation.simdWorldPosition - joint.presentation.simdWorldPosition
                let toFigure: simd_float4x4 = figure.presentation.simdWorldTransform.inverse
                let inFigure: SIMD4<Float> = toFigure * SIMD4<Float>(toLens.x, toLens.y, toLens.z, 0)
                direction = SIMD3<Float>(inFigure.x, inFigure.y, inFigure.z)
            }
            if let direction, simd_length(direction) > 1e-5 {
                across = atan2(direction.x, direction.z)
                want = Gaze.aim(toward: direction)
            }
        }
        let follow: Float = step > 0 ? 1 - exp(-step / Gaze.followTime) : 0
        let yielding: Float = step > 0 ? 1 - exp(-step / Gaze.yieldTime) : 0
        strength += (strengthTarget - strength) * yielding
        yaw += (want.yaw * strength - yaw) * follow
        pitch += (want.pitch * strength - pitch) * follow
        // Across about the upright, then up about the side: a nod up turns
        // the face from +Z toward +Y, which is a NEGATIVE turn about +X.
        let turn: simd_quatf = simd_quatf(angle: yaw, axis: up) * simd_quatf(angle: -pitch, axis: side)
        let out: simd_quatf = simd_normalize(turn * base)
        lastBase = base
        lastOut = out
        return SCNVector4(x: out.imag.x, y: out.imag.y, z: out.imag.z, w: out.real)
    }
}
