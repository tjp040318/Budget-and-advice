import Foundation
import SceneKit
import UIKit

/// Solves the battle camera's home framing, and cuts away from it for a skill.
///
/// Two things here are structural, and both were re-decided after the third
/// playtest in a row called the battle camera bad.
///
/// **The home framing is solved, not written down.** `BattleSceneController`
/// puts the camera node in the scene; this class then measures the `UnitNode`s
/// actually standing on the stage — how wide the two lines are, how deep, and
/// how tall the tallest thing in the fight is — and solves the position and
/// the aim that put THAT field in the frame. A hard-coded camera can only ever
/// be right for the formation it was solved against: the old (0, 7.2, 11) was
/// solved for two ranks of two, and a 4.5 m Colossus walked through the top of
/// it. Solving instead means a 1v1 arena bout, a five-a-side and a boss twice
/// the height of a man each get a frame that fits, and a change to the
/// formation on the other side of `BattleSceneController` needs no change here.
///
/// **The lens is long, and the camera is off the axis.** 26° vertical on a
/// 2.17 frame is 53° horizontal — a 36 mm lens where the old 34°/67° was a
/// 27 mm one that splayed the outer figures and stretched the props at the
/// frame edges. The long lens is paid for by standing further back, which is
/// what compresses the two lines together and makes the figures read as solid
/// rather than as a diorama. 13° of yaw takes the camera off the centre line,
/// so the two lines recede diagonally instead of ruling two horizontal stripes
/// across the screen; 21° of pitch is the shallowest that still separates the
/// near line's heads from the far line's feet, and leaves the top third of the
/// frame to the environment painting rather than to bare floor.
///
/// Solved for a four-a-side line thirteen metres across, the camera lands at
/// (−4.7, 9.0, 20.4) aiming at (0, 0.95, 0): the player line runs 49%–83% of
/// the frame height, the enemy line 28%–51%, the top 28% is environment, and
/// no figure overlaps another — checked pairwise, every near box against every
/// far box, for four-a-side, five-a-side and a boss. Given instead the tight
/// two-rank block the stage used to place, the same solve comes in to
/// (−3.9, 7.5, 15.9) and stands the figures a quarter of the screen tall.
/// That is the whole argument for solving rather than writing a camera down:
/// one set of rules, and the frame follows the fight it is given.
///
/// **A skill cuts; nothing else moves the camera.** The owner's standing rule
/// is that the camera is fixed — a basic attack, an enemy's turn and the hits
/// never touch the frame. But a fixed camera that ALSO discards the four
/// authored shot types leaves a twenty-turn fight with one frame in it, which
/// is the other half of "too basic, not fluid". So a special, an ultimate and
/// a killing blow get a real shot change: a hard CUT to a composed angle, held
/// for the clip, and a cut back. A cut reads instantly and cannot leave the
/// camera half way anywhere; the slow push it replaces did neither. Every cut
/// is taken from the same side of the field as the home framing — the 180°
/// line — so screen direction never flips, and every cut stands on the camera
/// side of its subject, which for a player is over the shoulder and for an
/// enemy is face on. **Cinematic** (More → Sound & camera) still moves the
/// camera between the cuts; it now aims with `look(at:)` every frame instead
/// of with a look-at constraint, which is what used to snap the frame to
/// nowhere when the constraint was dropped at the end of a shot.
final class CameraDirector {

    /// The player's choice, read at shot time. Off is the genre's fixed view.
    static let cinematicKey = "cinematicCamera"
    static var isCinematic: Bool { UserDefaults.standard.bool(forKey: cinematicKey) }

    // MARK: - The home solve

    /// Vertical field of view. 26° is 53° horizontal on a 2.17 landscape phone
    /// (a 36 mm lens): long enough that the outer figures of a line are not
    /// sheared outward, short enough that a four-a-side line still fits from
    /// a distance the stage can afford.
    private static let lensFieldOfView: CGFloat = 26

    /// 21° down. Steeper is a diorama seen from above and fills the bottom of
    /// the frame with floor; shallower stops separating the near line's heads
    /// from the far line's feet (the separation needs a camera height of about
    /// `figureHeight × farDistance / lineGap`, which at 21° and the solved
    /// distance is 9.0 m against the 7.0 m needed).
    private static let homePitch: Float = 21 * .pi / 180

    /// 13° of yaw, camera to the left of the centre line looking right. Zero
    /// yaw is a frontal elevation: every rank is a row exactly parallel to the
    /// screen and the only depth cue left is scale. This is the three-quarter
    /// the doc comment always claimed and the code never had.
    private static let homeYaw: Float = 13 * .pi / 180

    /// How much of the half-frame the outermost figure may reach, and the
    /// metres of air left beside it. A figure is about 0.9 m across, so 0.9 m
    /// of shoulder room leaves half a figure of air outside the outer unit.
    private static let widthMargin: Float = 0.98
    private static let shoulderRoom: Float = 0.9

    /// Where the near line's feet sit, as a fraction of the half-frame below
    /// centre: 0.68 is 84% of the frame height, which clears the command
    /// panel's 50 pt actor plate along the bottom edge. The genre puts the
    /// lines across the lower-middle third and gives the top of the frame to
    /// the environment; the old solve centred the cast and spent 23% of the
    /// frame on bare floor in front of them.
    private static let nearFeetLine: Float = 0.68

    /// And the ceiling: nothing in the fight may go above 10% of the frame
    /// height. This is what steps the camera back for a giant — `boss_colossus`
    /// is 4.5 m, the Jötunn 4.5, the Hydra 4.2, and all three were beheaded by
    /// the old fixed framing, which could show nothing above 4.15 m.
    private static let fieldTopLine: Float = 0.80

    /// A 1v1 is not framed as a close-up: the stage is still a stage, so the
    /// solve always frames at least this much width.
    private static let minHalfWidth: Float = 5.0

    /// Distance bounds. The far end is generous because a 4.5 m boss on a
    /// narrow iPad frame needs it; the scene's fog does not begin until 55 m,
    /// so nothing in the fight hazes over at any distance in this range.
    private static let minDistance: Float = 12
    private static let maxDistance: Float = 32

    /// Two cuts in quick succession read as a mistake rather than as cutting,
    /// so a shot may not start within this of the last one. One turn casts one
    /// skill, so in practice this only catches auto-battle at speed.
    private static let cutCooldown: TimeInterval = 0.8

    /// The extent of what has to be in frame. Held as a high-water mark for
    /// the length of a battle: a wave arriving with a giant in it widens the
    /// framing, and nothing narrows it, so the camera cannot creep inward as
    /// units fall.
    private struct FieldBounds {
        var halfWidth: Float
        var nearZ: Float
        var farZ: Float
        var topY: Float

        /// The four-a-side line, used for the one frame between building the
        /// camera and the units being placed.
        static let standard = FieldBounds(halfWidth: 6.5, nearZ: 3.4, farZ: -3.4, topY: 2.0)

        func union(_ other: FieldBounds) -> FieldBounds {
            FieldBounds(
                halfWidth: max(halfWidth, other.halfWidth),
                nearZ: max(nearZ, other.nearZ),
                farZ: min(farZ, other.farZ),
                topY: max(topY, other.topY)
            )
        }
    }

    private let cameraNode: SCNNode
    private var field: FieldBounds?
    private var homePosition = SCNVector3(0, 9, 20)
    private var homeAim = SCNVector3(0, 1, 0)
    /// True while a shot has the camera anywhere but the home framing.
    private var isOffHome = false
    /// Bumped by every shot and every return home. A main-queue hop scheduled
    /// by a shot that has since been cancelled compares its captured value and
    /// steps aside, rather than cutting home in the middle of the next shot.
    private var shotGeneration = 0
    private var lastCutAt: TimeInterval = -100

    init(cameraNode: SCNNode) {
        self.cameraNode = cameraNode
        // The lens and the framing are one solve, so this class owns both
        // rather than reading a field of view off the node and hoping the two
        // agree. The projection direction is stated rather than assumed:
        // `fieldOfView` is a VERTICAL angle only while `projectionDirection`
        // is `.vertical` (the two cases are `.vertical` and `.horizontal`,
        // and vertical is the default), and every line of `solve(for:)`
        // divides by a vertical half-angle and multiplies the horizontal one
        // out by the aspect ratio itself. Setting it here is what keeps the
        // solve right if the scene's camera is ever built with the other.
        cameraNode.camera?.fieldOfView = Self.lensFieldOfView
        cameraNode.camera?.projectionDirection = .vertical
        applySolve(for: FieldBounds.standard)
        // `buildCamera()` runs before `place(combatants:)`, so there is not a
        // single unit in the scene yet and there is nothing to measure. Both
        // are called from one synchronous `build(...)` on the main queue, so a
        // hop to the back of that queue lands after the units are standing and
        // before the first frame the player sees.
        DispatchQueue.main.async { [weak self] in
            self?.frameField()
        }
    }

    /// Re-measures the stage and re-solves the home framing. Called once the
    /// units are placed, and again whenever playback drains — which is how a
    /// later wave's giant widens the frame.
    func frameField() {
        guard let measured = measureField() else { return }
        let merged = field.map { $0.union(measured) } ?? measured
        field = merged
        let solved = solve(for: merged)
        homePosition = solved.position
        homeAim = solved.aim
        // While a shot has the camera the new framing is only recorded — the
        // shot cuts back to it when it ends. With the camera at home it is
        // applied at once, and since the solve only changes when the field
        // does, that is a wave walking on with something bigger in it: a
        // moment the fight has already announced, not a drift out of nowhere.
        if !isOffHome { applyHome() }
    }

    /// The stage as it stands: how wide the lines are, how deep, how tall.
    ///
    /// A unit's HEIGHT counts wherever it happens to be standing, so a giant
    /// arriving with a later wave widens the frame the moment it is on the
    /// field. Its POSITION is read only while it is standing on its mark. An
    /// action running on the `UnitNode` itself says it is not: it is walking
    /// on from three metres behind the far line
    /// (`place(combatants:entering:)`), dashing at a victim, or fading out
    /// with a cleared wave. The field is a high-water mark that never comes
    /// back down, so measuring one of those transients steps the camera back
    /// for the rest of the fight — the walk-on stands a unit at −6.8 m, which
    /// the clamp below only trims to −6.5, and `playNext()` drains and calls
    /// `returnHome()` in the same frame the wave is placed, so the walk WAS
    /// being measured; in the Labyrinth, where every level is three waves,
    /// the camera stepped back at each one and never came in again. The idle
    /// and the clips play on the model container rather than on this node, so
    /// a unit at rest has no action here to read.
    private func measureField() -> FieldBounds? {
        guard let stage = cameraNode.parent else { return nil }
        var halfWidth: Float = 0
        var nearZ: Float?
        var farZ: Float?
        var topY: Float = 1.6
        var found = false
        for node in stage.childNodes {
            guard let unit = node as? UnitNode else { continue }
            found = true
            topY = max(topY, unit.spec.height)
            guard !unit.hasActions else { continue }
            let x = min(8, abs(unit.position.x))
            let z = min(6.5, max(-6.5, unit.position.z))
            halfWidth = max(halfWidth, x + Self.shoulderRoom)
            nearZ = max(nearZ ?? z, z)
            farZ = min(farZ ?? z, z)
        }
        guard found else { return nil }
        // With nobody standing still the heights still count and the depth of
        // the field is handed back unchanged, which the union in
        // `frameField()` then leaves exactly as it was.
        let held = field ?? FieldBounds.standard
        return FieldBounds(
            halfWidth: halfWidth,
            nearZ: nearZ ?? held.nearZ,
            farZ: farZ ?? held.farZ,
            topY: topY
        )
    }

    /// Solves the camera position and aim that frame `field`.
    ///
    /// The direction is fixed (pitch and yaw are the look of the game), so the
    /// only unknowns are how far back the camera stands and how high it aims.
    /// Written in the camera's own basis, both are cheap: a point's offsets
    /// across and up the frame do not depend on the distance at all, and its
    /// depth is `distance + a constant`. So the distance each corner of the
    /// field demands is exact arithmetic, and the largest of them is the
    /// answer. The aim height is then nudged until the near line's feet land
    /// on `nearFeetLine`, which changes the corners' offsets, so the two steps
    /// alternate. Three passes converge; six are run because they are free.
    private func solve(for field: FieldBounds) -> (position: SCNVector3, aim: SCNVector3) {
        let halfWidth = max(field.halfWidth, Self.minHalfWidth)
        let pitch = Self.homePitch
        let yaw = Self.homeYaw
        // The camera looks along its own −Z; this is that direction written
        // out, with the right and up axes of the frame beside it. `look(at:)`
        // turns the node to match at the end, so no angle is ever handed to
        // `atan2` — the mistake that showed the empty side of the stage.
        let forward = SCNVector3(sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
        let right = SCNVector3(cos(yaw), 0, sin(yaw))
        let up = SCNVector3(
            right.y * forward.z - right.z * forward.y,
            right.z * forward.x - right.x * forward.z,
            right.x * forward.y - right.y * forward.x
        )
        let tanV = tan(Float(Self.lensFieldOfView) * .pi / 360)
        let tanH = tanV * Self.aspect
        let midZ = (field.nearZ + field.farZ) / 2

        var corners: [SCNVector3] = []
        for x in [-halfWidth, halfWidth] {
            for z in [field.nearZ, field.farZ] {
                corners.append(SCNVector3(x, 0, z))
                corners.append(SCNVector3(x, field.topY, z))
            }
        }

        var aimY = field.topY * 0.5
        var distance = Float(16)
        for _ in 0..<6 {
            let aim = SCNVector3(0, aimY, midZ)
            var required = Self.minDistance
            for corner in corners {
                let offset = SCNVector3(corner.x - aim.x, corner.y - aim.y, corner.z - aim.z)
                let across = dot(offset, right)
                let vertical = dot(offset, up)
                let depth = dot(offset, forward)
                required = max(required, abs(across) / (Self.widthMargin * tanH) - depth)
                if vertical > 0 {
                    required = max(required, vertical / (Self.fieldTopLine * tanV) - depth)
                } else {
                    required = max(required, -vertical / (Self.nearFeetLine * tanV) - depth)
                }
            }
            distance = min(Self.maxDistance, required)
            // Where the lowest corner of the field actually lands, as a
            // fraction of the half-frame.
            var lowest: Float = 1
            for corner in corners {
                let offset = SCNVector3(corner.x - aim.x, corner.y - aim.y, corner.z - aim.z)
                lowest = min(lowest, dot(offset, up) / ((dot(offset, forward) + distance) * tanV))
            }
            // Raising the aim raises the camera with it and slides the whole
            // frame down; `distance * tanV` is a half-frame in metres at the
            // aim, and dividing by cos(pitch) turns a vertical metre into a
            // metre measured up the frame.
            aimY += (lowest + Self.nearFeetLine) * distance * tanV / cos(pitch)
            aimY = max(0.2, min(field.topY * 1.8, aimY))
        }

        let aim = SCNVector3(0, aimY, midZ)
        let position = SCNVector3(
            aim.x - forward.x * distance,
            aim.y - forward.y * distance,
            aim.z - forward.z * distance
        )
        return (position, aim)
    }

    /// The viewport's aspect ratio. The app is landscape-only and full screen
    /// on both families, so the screen's long side over its short side is the
    /// scene view's shape whatever the device has been rotated to. Clamped
    /// because the solve should degrade, not invert, if it is ever read on a
    /// window shape nobody planned for.
    private static var aspect: Float {
        let bounds = UIScreen.main.bounds
        let long = Float(max(bounds.width, bounds.height))
        let short = Float(min(bounds.width, bounds.height))
        guard short > 0 else { return 2.17 }
        return min(2.4, max(1.2, long / short))
    }

    private func applySolve(for field: FieldBounds) {
        let solved = solve(for: field)
        homePosition = solved.position
        homeAim = solved.aim
        applyHome()
    }

    // MARK: - Home

    /// Frames the whole battlefield. The default state between actions.
    ///
    /// In the fixed camera this is a cut, because the shot it is returning
    /// from was a cut; in cinematic it is an eased move. Either way it clears
    /// everything a shot might have left running, which is why the camera can
    /// no longer end a turn somewhere unexpected.
    func returnHome(duration: TimeInterval = 0.5) {
        shotGeneration += 1
        cameraNode.removeAllActions()
        // Nothing sets a constraint on this node any more — shots aim with
        // `look(at:)` frame by frame — but an old one left in place used to
        // turn the home framing into a stare at the last victim's chest, so
        // the clear stays as a guard.
        cameraNode.constraints = []
        let wasOffHome = isOffHome
        // Re-solve before returning, so a wave that has just walked on is in
        // the frame the camera comes back to.
        frameField()
        guard Self.isCinematic, wasOffHome, duration > 0 else {
            applyHome()
            return
        }
        let aim = homeAim
        travel(
            to: homePosition,
            aiming: { aim },
            over: duration,
            hold: 0,
            fov: Self.lensFieldOfView,
            completion: nil
        )
        isOffHome = false
    }

    /// Puts the camera on the home framing this instant, lens and all.
    private func applyHome() {
        cameraNode.removeAction(forKey: "shake")
        cameraNode.removeAction(forKey: "fov")
        cameraNode.position = homePosition
        cameraNode.look(at: homeAim)
        cameraNode.camera?.fieldOfView = Self.lensFieldOfView
        isOffHome = false
    }

    // MARK: - Shots

    /// Plays a shot on a caster, optionally aimed at a victim.
    func perform(
        _ shot: CameraShot,
        on caster: UnitNode,
        target: UnitNode?,
        completion: (() -> Void)? = nil
    ) {
        guard Self.isCinematic else {
            cut(shot, on: caster, target: target, completion: completion)
            return
        }

        shotGeneration += 1
        cameraNode.removeAllActions()
        cameraNode.constraints = []
        isOffHome = true

        let casterPosition = caster.chestWorldPosition
        let duration = shot.duration

        switch shot {
        case .standard:
            // Not a cut, but not dead either: a lean of a tenth of the way
            // toward the action and a touch of zoom, held through the hits and
            // released when the queue drains.
            let focus = target.map { lerp(casterPosition, $0.chestWorldPosition, 0.5) } ?? casterPosition
            let toward = lerp(homePosition, focus, 0.10)
            let aim = homeAim
            travel(
                to: toward,
                aiming: { aim },
                over: 0.35,
                hold: 0,
                fov: Self.lensFieldOfView * 0.94,
                completion: completion
            )

        case .pushIn:
            let toward = lerp(homePosition, casterPosition, 0.25)
            travel(
                to: SCNVector3(toward.x, toward.y + 0.5, toward.z),
                aiming: { caster.chestWorldPosition },
                over: duration * 0.4,
                hold: duration * 0.3,
                fov: 30,
                completion: completion
            )

        case .impactClose:
            let focus = target ?? caster
            let position = focus.chestWorldPosition
            travel(
                to: SCNVector3(position.x + 2.0, position.y + 0.9, position.z + 2.4),
                aiming: { focus.chestWorldPosition },
                over: duration * 0.35,
                hold: duration * 0.4,
                fov: 28,
                completion: completion
            )

        case .heroLowAngle:
            travel(
                to: SCNVector3(casterPosition.x + 1.2, 0.7, casterPosition.z + 2.6),
                aiming: { caster.chestWorldPosition },
                over: duration * 0.35,
                hold: duration * 0.5,
                fov: 36,
                completion: completion
            )

        case .cinematicOrbit:
            // Start wide and behind, sweep around the caster, land facing them.
            let radius: Float = 4.2
            let start = SCNVector3(casterPosition.x - radius, casterPosition.y + 1.6, casterPosition.z + radius)
            cameraNode.position = start
            let generation = shotGeneration
            let orbit = SCNAction.customAction(duration: duration * 0.8) { node, elapsed in
                let t = Float(elapsed / CGFloat(duration * 0.8))
                let angle = Float.pi * 0.55 * t - Float.pi * 0.25
                node.position = SCNVector3(
                    casterPosition.x + sin(angle) * radius,
                    casterPosition.y + 1.6 - t * 0.5,
                    casterPosition.z + cos(angle) * radius
                )
                // The camera looks along its own −Z, so `look(at:)` is the
                // orientation; the hand-rolled yaw this replaced was a half
                // turn off and showed the empty side of the stage.
                node.look(at: casterPosition)
            }
            animateFOV(to: 42, duration: 0.25)
            cameraNode.runAction(.sequence([orbit, .wait(duration: duration * 0.2)]), forKey: "shot") { [weak self] in
                self?.afterShot(generation, completion)
            }
        }
    }

    /// The fixed camera's one move: a hard cut to a composed angle on the unit
    /// the skill belongs to, held for the clip, and a cut back home.
    ///
    /// Every shot is built the same way, which is what makes the fight legible
    /// rather than merely busy: the camera stands on the +Z side of its
    /// subject — the side the home framing is on — and a stride to the left,
    /// the same side the home framing leans from. So a player's skill is seen
    /// over their shoulder with the enemy line beyond, an enemy's is seen face
    /// on with the enemy coming at the camera, and the screen direction of the
    /// fight never flips between one shot and the next.
    private func cut(
        _ shot: CameraShot,
        on caster: UnitNode,
        target: UnitNode?,
        completion: (() -> Void)?
    ) {
        // A basic attack never moves the camera. That is the owner's rule and
        // it is also the genre's: the frame is worth changing for a special,
        // an ultimate and a killing blow, and for nothing else.
        guard shot != .standard else {
            completion?()
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastCutAt > Self.cutCooldown else {
            completion?()
            return
        }
        lastCutAt = now

        let subject = shot == .impactClose ? (target ?? caster) : caster
        let height = subject.spec.height
        let base = subject.position
        // Every offset below is written for a 1.9 m figure and stood off by
        // this much for anything bigger, so a 4.5 m Colossus is framed the
        // same fraction of the screen as a hoplite instead of bursting out of
        // a shot solved for a man.
        let reach = max(1, height / 1.9)

        let offset: SCNVector3
        let aimHeight: Float
        let fov: CGFloat
        let hold: TimeInterval
        switch shot {
        case .pushIn:
            // A three-quarter medium from just above head height, 4.6 m out:
            // the figure fills 74% of the frame with the victim beyond it.
            // Above the figure rather than level with it, because the mist
            // planes that ring the platform stand up to 2.6 m and a camera
            // set down among them washes the shot with additive haze.
            offset = SCNVector3(-2.6 * reach, height * 0.95 + 0.6, 3.8 * reach)
            aimHeight = height * 0.55
            fov = 30
            hold = 0.75
        case .impactClose:
            // Tight on the victim as the blow lands: 4.8 m out at 27°, so the
            // figure stands 83% of the frame height and the attacker arrives
            // over the camera's shoulder as a foreground mass on the right.
            offset = SCNVector3(-2.4 * reach, height * 0.85 + 0.5, 4.0 * reach)
            aimHeight = height * 0.60
            fov = 27
            hold = 0.55
        case .heroLowAngle:
            // Three-quarters of a metre off the floor, looking 20° up at the
            // head. A wide lens from below is what makes a god look like one,
            // and it is the one shot here worth the haze it stands in.
            offset = SCNVector3(-2.0 * reach, 0.75, 3.2 * reach)
            aimHeight = height * 0.92
            fov = 36
            hold = 1.0
        default:
            // An ultimate: further out, higher and wider than the rest,
            // because the effect needs the room. The figure is half the frame.
            offset = SCNVector3(-3.0 * reach, height * 1.15 + 0.8, 4.6 * reach)
            aimHeight = height * 0.62
            fov = 34
            hold = 1.2
        }

        var aim = SCNVector3(base.x, base.y + aimHeight, base.z)
        if shot != .impactClose, let target, target.position.z < base.z - 0.5 {
            // Lean the aim a third of the way toward the victim, but only when
            // the victim stands BEYOND the caster: leaning toward one that is
            // between the camera and the caster would swing the shot round to
            // face the camera's own side of the field.
            let victim = SCNVector3(target.position.x, target.position.y + target.spec.height * 0.6, target.position.z)
            aim = lerp(aim, victim, 0.3)
        }

        // Every offset above is written from the subject, and a subject deep
        // in the field puts the camera among the units rather than in front
        // of them: an enemy's shot, and an impact shot — which is composed on
        // the VICTIM — both land it inside the player's front rank. Measured
        // against the stage's own marks the nearest figure that was not the
        // subject stood 1.2 m from the lens, which fills the frame with a
        // back and is near enough for the 0.1 m near plane to slice a body
        // open across it. So the whole offset is dollied out along its own
        // line until the camera stands 2.4 m clear of the near rank: the same
        // angle, the same side of the 180°, only further off and therefore a
        // smaller subject (a far enemy's ultimate goes from 50% of the frame
        // height to 30%, and the worst clearance from 1.2 m to 2.5 m). A shot
        // already outside the field — a near-line caster's own, which is most
        // of them — comes through at 1× and is untouched.
        let nearRank = field?.nearZ ?? FieldBounds.standard.nearZ
        let dolly: Float = offset.z > 0.01
            ? min(2.5, max(1, (nearRank + 2.4 - base.z) / offset.z))
            : 1

        shotGeneration += 1
        let generation = shotGeneration
        cameraNode.removeAllActions()
        cameraNode.constraints = []
        // The cut itself: position and orientation in one assignment, no
        // action, no interpolation. This is the whole point — the eye re-reads
        // a cut frame at once, and a cut cannot be interrupted half way.
        cameraNode.position = SCNVector3(
            base.x + offset.x * dolly,
            base.y + offset.y * dolly,
            base.z + offset.z * dolly
        )
        cameraNode.look(at: aim)
        cameraNode.camera?.fieldOfView = fov
        isOffHome = true

        // A locked-off shot with a 3% creep in over the hold. It moves nothing
        // — the camera position is untouched, so a hit shake still shakes
        // around the cut — but it keeps the frame from reading as a still.
        let creep = SCNAction.customAction(duration: hold) { node, elapsed in
            guard let camera = node.camera else { return }
            let t = CGFloat(min(1, elapsed / CGFloat(hold)))
            camera.fieldOfView = fov - t * fov * 0.03
        }
        cameraNode.runAction(creep, forKey: "shot") { [weak self] in
            self?.afterShot(generation, completion)
        }
    }

    /// A short shake, used on critical hits and on the ultimate's landing frame.
    func shake(intensity: Float = 0.12, duration: TimeInterval = 0.3) {
        let origin = cameraNode.position
        let shake = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = Float(elapsed / CGFloat(duration))
            let decay = (1 - t)
            // Deterministic wobble rather than random, so it reads as impact
            // rather than as noise.
            let phase = Float(elapsed) * 60
            node.position = SCNVector3(
                origin.x + sin(phase) * intensity * decay,
                origin.y + cos(phase * 1.4) * intensity * decay * 0.6,
                origin.z
            )
        }
        // Eased back over a tenth of a second rather than snapped in a frame:
        // the camera settles out of every move it makes.
        let recover = SCNAction.move(to: origin, duration: 0.12)
        recover.timingMode = .easeOut
        cameraNode.runAction(.sequence([shake, recover]), forKey: "shake")
    }

    // MARK: - Helpers

    /// Moves the camera to `destination` over `duration`, aiming at whatever
    /// `aim` returns on the frame it is asked — so a shot follows a unit that
    /// is dashing — holds it, then reports back.
    ///
    /// There is no `SCNLookAtConstraint` anywhere in this file on purpose. One
    /// with `influenceFactor` below 1 aims only part of the way at its subject,
    /// which is how a tight shot ended up looking past the unit it was framing;
    /// and dropping the constraint at the end of a shot snapped the orientation
    /// back to the home angles while the camera was still parked over someone's
    /// shoulder, pointing at nothing. Aiming frame by frame has neither
    /// failure, and leaves nothing behind to clear.
    private func travel(
        to destination: SCNVector3,
        aiming aim: @escaping () -> SCNVector3,
        over duration: TimeInterval,
        hold: TimeInterval,
        fov: CGFloat,
        completion: (() -> Void)?
    ) {
        shotGeneration += 1
        let generation = shotGeneration
        let start = cameraNode.position
        let move = SCNAction.customAction(duration: duration) { node, elapsed in
            let raw: Float = duration <= 0 ? 1 : Float(min(1, elapsed / CGFloat(duration)))
            // Smoothstep: the move eases out of rest and settles into its end
            // rather than stopping dead, which is the difference between a
            // camera that is being operated and one that is being teleported.
            let t = raw * raw * (3 - 2 * raw)
            node.position = SCNVector3(
                start.x + (destination.x - start.x) * t,
                start.y + (destination.y - start.y) * t,
                start.z + (destination.z - start.z) * t
            )
            node.look(at: aim())
        }
        let settle = SCNAction.customAction(duration: max(0, hold)) { node, _ in
            node.look(at: aim())
        }
        animateFOV(to: fov, duration: max(0.12, duration))
        cameraNode.runAction(.sequence([move, settle]), forKey: "shot") { [weak self] in
            self?.afterShot(generation, completion)
        }
    }

    /// The tail of every shot: hop to the main queue, check the shot is still
    /// the current one, cut home and report.
    ///
    /// A cancelled action never calls its completion handler, so a shot that
    /// was replaced mid-flight cannot cut home over the top of the shot that
    /// replaced it; the generation is checked as well because the hop to the
    /// main queue can outlive the frame that scheduled it.
    private func afterShot(_ generation: Int, _ completion: (() -> Void)?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shotGeneration == generation else { return }
            if !Self.isCinematic { self.applyHome() }
            completion?()
        }
    }

    private func animateFOV(to value: CGFloat, duration: TimeInterval) {
        guard let camera = cameraNode.camera else { return }
        let start = camera.fieldOfView
        let action = SCNAction.customAction(duration: duration) { _, elapsed in
            let t = CGFloat(elapsed) / CGFloat(duration)
            camera.fieldOfView = start + (value - start) * min(1, t)
        }
        cameraNode.runAction(action, forKey: "fov")
    }

    private func lerp(_ a: SCNVector3, _ b: SCNVector3, _ t: Float) -> SCNVector3 {
        SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }

    private func dot(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
}
