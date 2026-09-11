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
/// **The lens is long, and the camera is round to the side.** 26° vertical
/// on a 2.17 frame is 53° horizontal — a 36 mm lens where the old 34°/67° was
/// a 27 mm one that splayed the outer figures and stretched the props at the
/// frame edges. The long lens is paid for by standing further back, which is
/// what compresses the field and makes the figures read as solid rather than
/// as a diorama. 58° of yaw puts the camera well round to the right of the
/// field, so the two lines-abreast the stage places read as the genre's two
/// COLUMNS — the player's at the lower left stepping back and left, the
/// enemy's on the right stepping back toward the top, an open middle
/// between them — and 22° of pitch keeps the floor from filling the frame:
/// the far rim sits a third of the way down and the painting takes the rest.
///
/// Solved for a four-a-side, the camera stands about 20 m from the aim, the
/// front figure a quarter of the frame tall and the farthest a sixth. A boss
/// standing over the far rim is framed by its head (`bossTopLine`), not by
/// its box, so a giant does not step the camera back for everyone else.
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

    /// 16° down. The genre's battle camera is LOW: you look across the
    /// field at the figures, not down onto a table of them. The old 21° was
    /// chosen to separate a near ROW's heads from a far ROW's feet, and with
    /// the two sides standing as columns beside each other (see `homeYaw`)
    /// there is no row behind a row to separate, so the pitch can come down
    /// to where the floor stops filling the frame and the painting behind
    /// the far rim takes the top half instead.
    ///
    /// 22°, up from a first 16°: at 16° each step along a column rose only
    /// half a metre up the frame, and the photographed three-a-side stood
    /// as a row with shoulders overlapping. At 22° a step is 0.7 m up and
    /// 1.2 m across — a clean diagonal — and the far rim still sits a third
    /// of the way down the frame with the painting above it.
    /// 20° since 2026-09-11, with the field re-laid as two wings (see
    /// `BattleSceneController.position(for:teamSize:)`): each rank of a wing
    /// steps 1.3 m outward as well as 1.9 m deeper, so the pitch no longer
    /// has to separate ranks by itself, and the lower it is the more of the
    /// painting stands above the far edge — about a third of the frame at
    /// 20°, the genre's share.
    private static let homePitch: Float = 20 * .pi / 180

    /// 58° of yaw, camera on the right, well round toward the side of the
    /// field. This is the composition, and it is the third attempt at it.
    ///
    /// At 0° the two lines were rows parallel to the screen. At 27° they
    /// receded a little and the owner, with a screenshot, called the angle
    /// ugly: the floor's tiles ran diagonally across a small tilted disc, the
    /// figures were a sixth of the frame tall and half the picture was the
    /// void beyond the rim. At 58° the world's two lines-abreast become what
    /// the genre shows: the player's team a COLUMN at the lower left, its
    /// front unit nearest the camera at the bottom of the frame and the rest
    /// stepping back and left; the enemy column across from it on the right,
    /// stepping back toward the top; an open middle between them where the
    /// attacks cross; and a boss standing over the far rim at the upper
    /// right. Nobody hides behind anybody, because each step along a line is
    /// 1.3 m across the screen as well as back into it.
    ///
    /// Shared with `StageBuilder`, which turns the far painting to face the
    /// camera: at this much yaw a painting hung square to the world ended a
    /// third of the way across the frame.
    ///
    /// ZERO since 2026-09-11. The 58° was a trick — two lines-abreast in the
    /// world made to read as columns by turning the whole world — and the
    /// owner saw the trick, not the columns: the floor's grid ran diagonally,
    /// the far rim crossed the frame as a slant, every pillar and statue
    /// stood askew, and the ground looked "slanted". "Take a look at
    /// Summoners War. DO THAT." The genre's camera looks straight up the
    /// field: the world's axes are square to the screen, the far edge of
    /// the ground runs level across the upper third, and the two teams are
    /// two WINGS laid out on the floor itself — the player's on the left,
    /// the enemy's on the right, each stepping outward and deeper from a
    /// front unit near the centre — which is what puts them at the lower
    /// left and the right with an open middle between them. The composition
    /// is in the marks now, not in the yaw.
    static let homeYaw: Float = 0

    /// How much of the half-frame the outermost figure may reach, and the
    /// metres of air left beside it. A figure is about 0.9 m across, so 0.9 m
    /// of shoulder room leaves half a figure of air outside the outer unit.
    private static let widthMargin: Float = 0.98
    private static let shoulderRoom: Float = 0.9

    /// Where the near column's front feet sit, as a fraction of the half-frame
    /// below centre: 0.68 is 84% of the frame height, which clears the actor
    /// plate along the bottom edge. The genre puts the cast across the lower
    /// two thirds and gives the top of the frame to the environment.
    private static let nearFeetLine: Float = 0.68

    /// The ceiling for an ordinary unit: nothing goes above 10% of the frame
    /// height. A BOSS gets a ceiling of its own, `bossTopLine`: its head may
    /// run right up to the frame's edge, because a boss that has to fit under
    /// the ordinary ceiling steps the whole camera back and shrinks the cast
    /// — which is what the old solve did for the Colossus, and why every boss
    /// fight was photographed from twice as far away as every other fight.
    private static let fieldTopLine: Float = 0.80
    /// 0.55 of the half-frame above the aim: the head lands 22% down the
    /// frame, under the boss bar rather than behind it (at 0.90 it was 5%
    /// down, behind the wave chip).
    private static let bossTopLine: Float = 0.90

    /// A boss fight is framed from BEHIND the player's team: 12° of yaw
    /// instead of 58°, 19° down, and further back, so the whole of a boss
    /// over the far rim — head included — is in the frame with the team's
    /// backs in a row across the bottom of it, the genre's boss-dungeon
    /// shot. The owner, with the Coils of Apep on his phone: "zoom back and
    /// a little more to behind the characters FOR BOSSES ONLY." From the
    /// side the hood ran off the top of the frame; at 24° the first frames
    /// had the Colossus top-right, with the team's column pulling the aim
    /// left — so the aim now centres on the boss's head (`FramePoint.isBoss`)
    /// and the yaw is nearly straight up the field, where the team's row is
    /// symmetrical about it and costs the boss no size.
    static let bossYaw: Float = -12 * .pi / 180
    private static let bossPitch: Float = 20 * .pi / 180
    /// The near feet a little higher up the frame in a boss fight, so the
    /// boss has the frame and the team is the foreground.
    /// Solved, not dialled: a Python port of `solve` swept pitch, feet line
    /// and top line over the real field. The owner's second look: "a little
    /// too far back and a little higher (angled downward but physically up
    /// higher)". Twenty degrees, the near feet allowed just below the bottom
    /// edge (1.05 — the team's ankles are behind the bottom bar, the genre's
    /// boss-dungeon shot) and the head allowed to 0.90 put the camera about
    /// 25 m out, the head 22% down just under the boss bar, a unit a fifth of
    /// the frame tall, the far rim past mid-frame with the boss over it.
    private static let bossFeetLine: Float = 1.05

    /// The painting is hung between the two yaws (`StageBuilder`), 17° off
    /// either camera, which a painting seventy metres out does not show: a
    /// boss can arrive with a later wave, after the set is built, and the
    /// camera swings to meet it.
    static var backdropYaw: Float { (homeYaw + bossYaw) / 2 }

    /// The cut shots' offsets are written for a camera on the −x side of
    /// the field, which is where the first solve stood; the home framing is
    /// on the +x side now, and a cut must stay on the camera's side of the
    /// 180° line or screen direction flips.
    private static var cutSide: Float { homeYaw < 0 ? -1 : 1 }

    /// Distance bounds. The far end is generous because a 4.5 m boss on a
    /// narrow iPad frame needs it; the scene's fog does not begin until 55 m,
    /// so nothing in the fight hazes over at any distance in this range.
    private static let minDistance: Float = 12
    private static let maxDistance: Float = 40

    /// Two cuts in quick succession read as a mistake rather than as cutting,
    /// so a shot may not start within this of the last one. One turn casts one
    /// skill, so in practice this only catches auto-battle at speed.
    private static let cutCooldown: TimeInterval = 0.8

    /// One point the frame has to hold, and how far up the frame it may sit
    /// (a fraction of the half-frame above centre).
    private struct FramePoint {
        var position: SCNVector3
        var topLine: Float
        /// The boss's head: a boss fight is centred on it, not on the field.
        var isBoss: Bool = false
    }

    /// What has to be in frame: the feet and heads of everyone standing on a
    /// mark, with shoulder room. Held as a high-water mark for the length of
    /// a battle — a wave arriving with a giant in it widens the framing, and
    /// nothing narrows it, so the camera cannot creep inward as units fall.
    ///
    /// POINTS, not a box. The first solve framed a box (half-width, near and
    /// far z, top), which is exact for a camera near the axis and wrong for
    /// one 55° round to the side: the box's near-right corner is then five
    /// metres nearer the lens than any figure and, being empty, cost half
    /// the frame to keep in it. Framing the figures themselves costs
    /// nothing that is not on the stage.
    private struct FieldBounds {
        var points: [FramePoint]
        /// A boss is on the field: the framing is the boss fight's.
        var hasBoss = false

        /// The four-a-side line-up, used for the one frame between building
        /// the camera and the units being placed, and always folded in so a
        /// 1v1 is framed as a stage rather than as a close-up.
        static let standard: FieldBounds = {
            var points: [FramePoint] = []
            // A three-a-side pair of wings: fronts at ±3 across and 2.2
            // deep, backs at ±5.6 and −1.6.
            for x in [Float(-5.6), 5.6] {
                for z in [Float(-1.6), 2.2] {
                    points.append(FramePoint(position: SCNVector3(x, 0, z), topLine: CameraDirector.fieldTopLine))
                    points.append(FramePoint(position: SCNVector3(x, 1.9, z), topLine: CameraDirector.fieldTopLine))
                }
            }
            return FieldBounds(points: points)
        }()

        /// The union keeps every point either side has, less exact repeats:
        /// the field is re-measured every time playback drains, and a
        /// hundred-turn fight would otherwise carry a hundred copies of each
        /// figure's feet into every solve.
        func union(_ other: FieldBounds) -> FieldBounds {
            var seen = Set(points.map(Self.key))
            var merged = points
            for point in other.points where !seen.contains(Self.key(point)) {
                seen.insert(Self.key(point))
                merged.append(point)
            }
            return FieldBounds(points: merged, hasBoss: hasBoss || other.hasBoss)
        }

        /// The nearest mark anyone stands on: what the cut shots dolly clear of.
        var nearZ: Float { points.map { $0.position.z }.max() ?? 3.4 }

        private static func key(_ point: FramePoint) -> String {
            let p = point.position
            return "\(Int((p.x * 10).rounded())),\(Int((p.y * 10).rounded())),\(Int((p.z * 10).rounded())),\(Int(point.topLine * 100))"
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
        let merged = (field ?? FieldBounds.standard).union(measured)
        if merged.hasBoss, !(field?.hasBoss ?? false) {
            print("[Camera] a boss is on the field: \(merged.points.count) points, re-framing from behind the team")
        }
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
        var points: [FramePoint] = []
        var found = false
        var hasBoss = false
        for node in stage.childNodes {
            guard let unit = node as? UnitNode else { continue }
            found = true
            if unit.isBoss { hasBoss = true }
            // A unit in motion is skipped — its mark is where it will stand
            // — except a boss, which never leaves its mark: it rises onto it
            // over a second when its wave arrives, and the first boss frames
            // were solved in that second with no boss point at all, which
            // put the Colossus wherever the team's column left the aim.
            guard !unit.hasActions || unit.isBoss else { continue }
            let x = max(-9, min(9, unit.position.x))
            let z = max(-11, min(7, unit.position.z))
            // A boss stands sunk below the platform's rim, so what has to be
            // framed is the rim at its feet and the head above it — its
            // full box would be half hidden rock — at its resting height,
            // not wherever the rise has it this frame. Its head sits under
            // the boss bar (`bossTopLine`).
            let top = unit.isBoss
                ? unit.spec.height * (1 - BattleSceneController.bossSink)
                : unit.spec.height
            let line = unit.isBoss ? Self.bossTopLine : Self.fieldTopLine
            for dx in [-Self.shoulderRoom, Self.shoulderRoom] {
                points.append(FramePoint(position: SCNVector3(x + dx, 0, z), topLine: Self.fieldTopLine))
            }
            points.append(FramePoint(position: SCNVector3(x, max(1.6, top), z), topLine: line, isBoss: unit.isBoss))
            if unit.isBoss {
                print("[Camera] measured boss \(unit.spec.assetName) at (\(unit.position.x), \(unit.position.y), \(unit.position.z)) head \(max(1.6, top)) actions \(unit.hasActions)")
            }
        }
        guard found else { return nil }
        // With nobody standing still there is nothing new to frame, and the
        // union in `frameField()` leaves the field exactly as it was.
        return FieldBounds(points: points, hasBoss: hasBoss)
    }

    /// Solves the camera position and aim that frame `field`.
    ///
    /// The direction is fixed (pitch and yaw are the look of the game), so the
    /// unknowns are where the camera stands: how far back, and where the
    /// frame's centre — the aim — sits across and up. Written in the camera's
    /// own basis, all of it is cheap: a point's offsets across and up the
    /// frame do not depend on the distance at all, and its depth is
    /// `distance + a constant`. So the distance each point demands is exact
    /// arithmetic and the largest of them is the answer; then the aim is slid
    /// across the frame until the field is centred and up it until the near
    /// feet rest on `nearFeetLine`, which changes the offsets, so the steps
    /// alternate. Three passes converge; eight are run because they are free.
    private func solve(for field: FieldBounds) -> (position: SCNVector3, aim: SCNVector3) {
        let pitch = field.hasBoss ? Self.bossPitch : Self.homePitch
        let yaw = field.hasBoss ? Self.bossYaw : Self.homeYaw
        let feetLine = field.hasBoss ? Self.bossFeetLine : Self.nearFeetLine
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
        let points = field.points.isEmpty ? FieldBounds.standard.points : field.points

        // Start on the field's centre, a metre up.
        var aim = SCNVector3(0, 1, 0)
        for point in points {
            aim.x += point.position.x / Float(points.count)
            aim.z += point.position.z / Float(points.count)
        }
        var distance = Float(16)
        for _ in 0..<8 {
            var required = Self.minDistance
            for point in points {
                let p = point.position
                let offset = SCNVector3(p.x - aim.x, p.y - aim.y, p.z - aim.z)
                let across = dot(offset, right)
                let vertical = dot(offset, up)
                let depth = dot(offset, forward)
                required = max(required, abs(across) / (Self.widthMargin * tanH) - depth)
                if vertical > 0 {
                    required = max(required, vertical / (point.topLine * tanV) - depth)
                } else {
                    required = max(required, -vertical / (feetLine * tanV) - depth)
                }
            }
            distance = min(Self.maxDistance, required)
            // Where the field lands in the frame at this distance, in
            // half-frames from the centre.
            var leftmost: Float = 1, rightmost: Float = -1, lowest: Float = 1
            var bossAcross: Float?
            for point in points {
                let p = point.position
                let offset = SCNVector3(p.x - aim.x, p.y - aim.y, p.z - aim.z)
                let d = dot(offset, forward) + distance
                let across = dot(offset, right) / (d * tanH)
                leftmost = min(leftmost, across)
                rightmost = max(rightmost, across)
                lowest = min(lowest, dot(offset, up) / (d * tanV))
                if point.isBoss { bossAcross = across }
            }
            // `distance * tanH` is a half-frame in metres at the aim, across;
            // `distance * tanV` the same up. Sliding the aim slides the whole
            // frame with it, so the field is centred by moving the aim to
            // the middle of its extremes, and the near feet are rested on
            // their line by moving the aim down by however far they are
            // below it.
            // A boss fight is centred on the boss; the distance step above
            // has already backed off far enough to keep the team in frame.
            let acrossShift = (bossAcross ?? (leftmost + rightmost) / 2) * distance * tanH
            let upShift = (lowest + feetLine) * distance * tanV
            aim = SCNVector3(
                aim.x + right.x * acrossShift + up.x * upShift,
                aim.y + right.y * acrossShift + up.y * upShift,
                aim.z + right.z * acrossShift + up.z * upShift
            )
        }

        let position = SCNVector3(
            aim.x - forward.x * distance,
            aim.y - forward.y * distance,
            aim.z - forward.z * distance
        )
        if field.hasBoss {
            // Where the boss's head lands, in half-frames from the centre,
            // read off the tour's console: the first boss frames at 12° had
            // it right of centre with no obvious reason in the numbers here.
            var report = "no boss point"
            if let boss = points.first(where: { $0.isBoss }) {
                let offset = SCNVector3(boss.position.x - aim.x, boss.position.y - aim.y, boss.position.z - aim.z)
                let d = dot(offset, forward) + distance
                report = "head (\(boss.position.x), \(boss.position.y), \(boss.position.z)) across \(dot(offset, right) / (d * tanH)) up \(dot(offset, up) / (d * tanV))"
            }
            print("[Camera] boss solve: \(points.count) points, \(report), aim (\(aim.x), \(aim.y), \(aim.z)), distance \(distance), yaw \(yaw * 180 / .pi)")
        }
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
            offset = SCNVector3(-2.6 * reach * Self.cutSide, height * 0.95 + 0.6, 3.8 * reach)
            aimHeight = height * 0.55
            fov = 30
            hold = 0.75
        case .impactClose:
            // Tight on the victim as the blow lands: 4.8 m out at 27°, so the
            // figure stands 83% of the frame height and the attacker arrives
            // over the camera's shoulder as a foreground mass on the right.
            offset = SCNVector3(-2.4 * reach * Self.cutSide, height * 0.85 + 0.5, 4.0 * reach)
            aimHeight = height * 0.60
            fov = 27
            hold = 0.55
        case .heroLowAngle:
            // Three-quarters of a metre off the floor, looking 20° up at the
            // head. A wide lens from below is what makes a god look like one,
            // and it is the one shot here worth the haze it stands in.
            offset = SCNVector3(-2.0 * reach * Self.cutSide, 0.75, 3.2 * reach)
            aimHeight = height * 0.92
            fov = 36
            hold = 1.0
        default:
            // An ultimate: further out, higher and wider than the rest,
            // because the effect needs the room. The figure is half the frame.
            offset = SCNVector3(-3.0 * reach * Self.cutSide, height * 1.15 + 0.8, 4.6 * reach)
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
