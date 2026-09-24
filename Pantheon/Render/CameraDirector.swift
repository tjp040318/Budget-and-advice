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
/// **The owner's angle (2026-09-24).** Everything above about yaw is history:
/// the camera now stands square BEHIND the team (`homeYaw` 0), 19° down
/// through a 28° lens, the team's backs a third of the frame tall across the
/// bottom and the enemy row ten metres beyond it across the middle — the two
/// Summoners War frames the owner sent ("this is the camera angle I like"),
/// measured. The solve is the same solve; its distance is now set by two feet
/// lines (`nearFeetLine`, `farFeetLine`) instead of falling out of its first
/// pass. `tools/camera_solve.py` is its Python port.
///
/// **A skill zooms; nothing turns the camera.** The owner's standing rule is
/// that the camera is fixed — a basic attack, an enemy's turn and the hits
/// never touch the frame — and since 2026-09-11 (late) the rule is exact: the
/// camera's ORIENTATION never changes in a fight. A special, an ultimate and a
/// killing blow get the genre's skill camera, which is a dolly along the home
/// line of sight toward the unit the skill belongs to, held for the clip, and
/// back (`zoom`): the same yaw, the same pitch, the same lens, the field the
/// same field only nearer, exactly as Summoners War zooms on a caster and
/// never shows its arena from another side. The hard CUTS this replaces — a
/// three-quarter medium over a player's shoulder, a face-on shot of an enemy
/// caster — were composed angles, and a composed angle is a different view of
/// the floor: the CI's arena frame of an enemy's turn showed the tiles
/// running diagonally and both rows swung round, and the owner asked how that
/// could have been sent to him as the fixed camera. **Cinematic** (More →
/// Sound & camera) keeps the authored moves, aiming with `look(at:)` every
/// frame instead of with a look-at constraint, which is what used to snap the
/// frame to nowhere when the constraint was dropped at the end of a shot.
final class CameraDirector {

    /// The player's choice, read at shot time. Off is the genre's fixed view.
    /// Reduce Motion (`MotionComfort`) holds the cuts, leans and orbits off
    /// whatever the switch says: the gentle zoom plays instead.
    static let cinematicKey = "cinematicCamera"
    static var isCinematic: Bool { UserDefaults.standard.bool(forKey: cinematicKey) && !MotionComfort.isReduced }

    // MARK: - The home solve

    /// Vertical field of view. 26° is 53° horizontal on a 2.17 landscape phone
    /// (a 36 mm lens): long enough that the outer figures of a line are not
    /// sheared outward, short enough that a four-a-side line still fits from
    /// a distance the stage can afford.
    ///
    /// 30° since the rows came back (2026-09-11 evening): a row six metres
    /// behind another needs height in the frame more than it needs reach,
    /// and the wider lens brings the camera four metres closer for the
    /// same rows, which is what makes the near figures a quarter of the
    /// frame tall instead of a fifth.
    ///
    /// 28° since 2026-09-24: the owner's Summoners War arena frame, whose
    /// gold ring and pillars fit a 24–30° vertical lens (the pillar lean
    /// gives 28.8°, the walkway's rails 24°).
    private static let lensFieldOfView: CGFloat = 28

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
    /// 26° since the rows came back (2026-09-11 evening). A far row has to
    /// stand clear above a near row, and at this pitch six metres of depth
    /// is a tenth of the frame between the team's heads and the enemies'
    /// feet; the far edge of the ground lands about 27% down, with the
    /// painting above it. Lower — the 20° the wings had — foreshortens the
    /// floor into something the owner read as a ramp: "the ground continues
    /// to look weird and angled".
    /// 36° since 2026-09-15: the owner's Summoners War frame, measured. Their
    /// camera stands high enough that the floor's pattern reads and the two
    /// rows lie on a diagonal — the team at the lower left, the enemies at
    /// the upper right — which is the yaw below; at 26° the floor was a
    /// strip and the rows two flat lines. Solved in the Python port before
    /// it was tried: at −32°/36° a three-a-side puts the team's feet 75%
    /// down the frame across its left third, the enemies' 45% down across
    /// its right third, both about a sixth of the frame tall, the far rim
    /// 23% down.
    ///
    /// 19° since 2026-09-24, and straight behind the team (`homeYaw` 0): the
    /// owner sent two Summoners War battle frames — "this is the camera angle
    /// I like" — and the arena's gold ring, fitted as an ellipse (2269 × 763
    /// px, level to 0.0°), solves to 19.0° for any lens from 15° to 35°; the
    /// units' shadow ovals, 3.3–3.6 times wider than tall, say 16–18°. The
    /// 20° of 2026-09-11 was called a ramp and the 26° after it no better,
    /// and both had the two rows six metres apart with the figures a sixth
    /// of the frame tall: what makes 19° read in the genre's frame is that
    /// its rows stand TEN metres apart and its team is a third of the frame
    /// tall, which is what `farFeetLine` and `BattleSceneController`'s marks
    /// now give (the team's feet 84% down, the enemies' 37%, the team 0.30
    /// of the frame tall and the enemies 0.18 — the arena frame's own
    /// numbers, solved in the Python port before it was tried).
    private static let homePitch: Float = 19 * .pi / 180

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
    /// −15° since 2026-09-11 evening: BEHIND the team and a little to the
    /// right, which is the genre's shot and the owner's words for it
    /// ("Summoners War has it from the back but slightly off to the right").
    /// The 58° before it turned the whole world to make two rows read as
    /// columns and the owner called the ground slanted; the 0° after it
    /// laid the teams out as wings at the sides and he could not find an
    /// enemy to tap. From behind, the team's row runs across the bottom
    /// with its backs to the camera, the enemy row runs across the middle
    /// facing it, and the fifteen degrees to the right is what keeps an
    /// enemy from standing straight behind the player in front of it.
    /// −32° since 2026-09-15 (see `homePitch`): the genre's three-quarter,
    /// read off the owner's own screenshot. −15° was "behind the team and
    /// a little to the right", his words for an earlier frame; the frame
    /// he sent after it shows the rows on a diagonal, which takes twice
    /// the yaw and a higher pitch, and is not the 58° that turned the
    /// whole world and was called slanted.
    /// 0° since 2026-09-24: the owner's own reference frames are square to
    /// the field, the rows level across the screen within 2–4°, the ring's
    /// centre at 0.497 of the width. Nobody hides behind anybody at 0° now
    /// for a reason the −15° never had: the enemy row stands so far back
    /// (`BattleSceneController.position`) that its feet are above the
    /// team's heads on screen, and its marks are 1.3 times as wide apart,
    /// so only a centre mark ever lines up with one of the team's.
    static let homeYaw: Float = 0

    /// How much of the half-frame the outermost figure may reach, and the
    /// metres of air left beside it. A figure is about 0.9 m across, so 0.9 m
    /// of shoulder room leaves half a figure of air outside the outer unit.
    private static let widthMargin: Float = 0.98
    private static let shoulderRoom: Float = 0.9

    /// How much of the half-frame the TEAM's row may reach, shoulder room
    /// included, in an ordinary fight (2026-09-24). The team's feet stand
    /// 82–86% down, in the band the HUD's bottom corners take: the three
    /// skill squares from 0.67 to 0.935 of the width and the three controls
    /// out to 0.18, both rising to about 80–85% down. The owner's Summoners
    /// War arena frame keeps a four-a-side between 0.23 and 0.77, and at the
    /// frame-wide `widthMargin` our five-a-side's outer figures stood at
    /// 0.15 and 0.85 — the right one under the skill squares. 0.64 of the
    /// half-frame at the shoulder is a figure's feet within 0.24–0.76; the
    /// camera steps back when a row needs more (a four-a-side by a percent,
    /// a five by a tenth, whose marks are also closer —
    /// `BattleSceneController.position`). It does NOT keep the team clear
    /// of the skill squares, and was never going to (2026-09-24, review):
    /// on an 852 × 393 phone the row runs 0.67–0.93 of the width from 78%
    /// down, so on the player's turn the right-hand figure's shins and feet
    /// stand behind the first square — a three-a-side's at 0.68, a four's
    /// or five's at 0.76, reaching the second square's edge — and a
    /// four-a-side's left feet touch the top of the controls. That is the
    /// owner's frame kept (his four-a-side reaches 0.77 under Summoners
    /// War's own squares); what the margin buys is the outer figures off
    /// the frame's edges and out from under the squares' middle. Holding
    /// the whole figure clear would be an asymmetric margin (the right
    /// shoulder at 0.28 of the half-frame) with the team centred in the
    /// free span 0.26–0.67 — a different frame, judged on CI frames first.
    /// A boss fight does not take it:
    /// backing off with the feet held low drops the boss's head down the
    /// frame (to 25–37% for a four- or five-a-side in the Python port), and
    /// the boss is what that shot is for.
    private static let teamWidthMargin: Float = 0.64

    /// Where the near column's front feet sit, as a fraction of the half-frame
    /// below centre: 0.68 is 84% of the frame height, which clears the actor
    /// plate along the bottom edge. The genre puts the cast across the lower
    /// two thirds and gives the top of the frame to the environment.
    ///
    /// 0.69 since the unit plates went under the feet (2026-09-11, night):
    /// at 0.74 the team's health and attack bars, drawn 10 pt below the
    /// projected feet, ran into the actor plate and the resolving panel
    /// along the bottom of the HUD. Five percent of the frame is room for
    /// a plate and a hairline of floor under it.
    /// 0.65 after the next run: at 0.69 the resolving panel still crossed
    /// the two left units' bars.
    /// 0.82 since the plates moved over the heads (2026-09-15): nothing
    /// hangs under the feet any more, so the team stands low in the frame
    /// with the bottom-left controls beside it, the genre's way.
    /// 0.72 since 2026-09-24 (86% down the frame, the arena frame's 0.84–0.87):
    /// the controls and the skill squares stand beside the feet at the
    /// bottom, as the genre's do.
    private static let nearFeetLine: Float = 0.72

    /// Where the far row's feet stand, as a fraction of the half-frame ABOVE
    /// centre: 0.26 is 37% down the frame, the arena frame's 0.36–0.38.
    /// With the near feet on `nearFeetLine` this is the second of the two
    /// lines that fix the camera's height and distance (2026-09-24). Before
    /// it, the distance fell out of the solve's first pass — the near feet
    /// held to their line while the aim was still the field's centre — and
    /// nothing said how far above the team the enemies should stand; at 19°
    /// that put the camera 21 m out and the team a fifth of the frame tall.
    /// The width and the heads still step the camera back when they need
    /// to (a five-a-side, a giant in the far row); this only brings it IN
    /// to the genre's framing when nothing forbids it.
    private static let farFeetLine: Float = 0.26

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
    /// 0.98 since 2026-09-15: the head runs to the frame's top edge under
    /// the full-width boss bar, the genre's boss shot.
    /// 0.88 since 2026-09-24: with the team at z +7 the boss stands fifteen
    /// metres beyond it, and at 0.98 Apep's head ran behind the boss bar
    /// (5% down); at 0.88 it lands 9–17% down, under the bar.
    /// With the far edge at −11 (`StageBuilder.battleFloorFarEdge`, the same
    /// day) every boss from 6 to 8 m, behind a team of three to five, lands
    /// 7–17% down: the Hydra and Apep highest (7–11%), the Colossus lowest
    /// (13–17%). The boss bar's own channel sits about 9–14% down, so the
    /// top of the Hydra's and Apep's heads meet its lower half — lower this
    /// line if a frame shows a face behind it.
    private static let bossTopLine: Float = 0.88

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
    /// −8° and 8° since 2026-09-15, from the owner's Summoners War boss
    /// frame: the camera LOW, nearly level, close behind the team, so the
    /// boss fills the upper half of the frame and the team stands large at
    /// the bottom. Solved in the Python port: Apep on the rim (−8.4, sunk
    /// 32%) at 8° with the feet at 0.94 and the head at 0.98 puts the
    /// camera 13 m out and 3.4 m up, the boss 46% of the frame tall with
    /// its head a tenth down, the team 39% tall. At 20° from 18 m the boss
    /// was 30% and the team 23%, and the owner could not see the boss.
    /// 0° and 9° since 2026-09-24: square to the field like the home
    /// camera, so a boss arriving with the third wave changes the pitch and
    /// the distance and never turns the floor's lines (the rule since
    /// 2026-09-11: a frame whose floor runs another way is a bug). Solved in
    /// the Python port on the new marks: Apep (7.2 m, sunk 32% on the rim)
    /// with the head 9% down, the team 0.39 of the frame tall at the bottom;
    /// the Colossus (8 m) with the head 17% down and the team 0.28.
    /// On the rim at −11 instead of −8.4: Apep's head 7% down behind a
    /// three-a-side (0.43 tall) to 11% behind a five (0.38), the Colossus's
    /// 13–17% (the team 0.31–0.28). A four- or five-a-side spreads 0.12–0.89
    /// of the width in this shot, the outer figures' legs behind the bottom
    /// corners' controls; `teamWidthMargin` says why it is not held in.
    static let bossYaw: Float = 0
    private static let bossPitch: Float = 9 * .pi / 180
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
    ///
    /// 0.92 since the unit plates went under the feet: with the ankles
    /// behind the bottom bar the team's bars were below the frame, and a
    /// boss fight is where the attack bars matter most. The camera steps
    /// back a little for it and the boss loses a few percent of the frame.
    ///
    /// 0.82 after the run that followed: at 0.92 the team's plates sat on
    /// the frame's bottom edge and under the actor plate in every boss
    /// fight. Nine percent of the frame under the feet is a plate and a
    /// hairline of floor, the same room an ordinary fight has.
    /// 0.94 since the plates moved over the heads: the feet may stand at
    /// the frame's bottom edge, the genre's boss shot.
    /// 0.92 since 2026-09-24 (the feet 96% down), with the pitch at 9°.
    private static let bossFeetLine: Float = 0.92

    /// The painting is hung between the two yaws (`StageBuilder`), 17° off
    /// either camera, which a painting seventy metres out does not show: a
    /// boss can arrive with a later wave, after the set is built, and the
    /// camera swings to meet it.
    /// Both are 0 since 2026-09-24, so the painting hangs square to the field.
    static var backdropYaw: Float { (homeYaw + bossYaw) / 2 }


    /// Distance bounds. The far end is generous because a 4.5 m boss on a
    /// narrow iPad frame needs it; the scene's fog does not begin until 60 m,
    /// so nothing in the fight hazes over at any distance in this range.
    /// 8 since 2026-09-24: the two feet lines put an ordinary fight's aim
    /// 16–18 m out and a boss's 14–20 m, so the floor is only a guard now.
    private static let minDistance: Float = 8
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
            // A three-a-side pair of rows on the marks of 2026-09-24
            // (`BattleSceneController.position`): each `arenaRowDepth` from
            // the arena's centre — the team's at z +7.0, the enemy's at −3.4.
            let centre = StageBuilder.arenaCentre.z
            let depth = StageBuilder.arenaRowDepth
            for x in [Float(-3.0), 3.0] {
                for z in [centre - depth, centre + depth] {
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

    /// The RIG the director moves (Docs/FEEL.md W2.18): the home framing,
    /// the skill zoom, the final blow's ease and the triumph's frame are all
    /// written here, and the lens hangs under it at rest.
    private let rig: SCNNode
    /// The node that carries the camera — the grade, the lens's angle — and
    /// takes the shake: `shaker`, written on it by the controller on the
    /// render thread, in the rig's own frame, so the dolly and the shake
    /// never fight over one node.
    private let lens: SCNNode
    /// The shake (`CameraShake`): hits, roars and rumbles add to it here
    /// (`addTrauma`, `rumble`), the controller writes it on `lens` every
    /// frame, and a skip or a forfeit stops it.
    let shaker = CameraShake()
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

    /// The realm's grade on the camera, read when this director was made.
    private let restSaturation: CGFloat
    private let restContrast: CGFloat
    private let restExposure: CGFloat
    /// Set once the field's colour is draining: nothing puts the grade back
    /// over it (a new run builds a new camera).
    private var draining = false

    init(rig: SCNNode, lens: SCNNode) {
        self.rig = rig
        self.lens = lens
        // The realm's grade as `BattleSceneController.buildCamera` set it
        // from `StageBuilder.grade(for:)`: what the impact frame punches and
        // puts back exactly, and what a lost field drains from.
        restSaturation = lens.camera?.saturation ?? 1
        restContrast = lens.camera?.contrast ?? 0
        restExposure = lens.camera?.exposureOffset ?? 0
        // The lens and the framing are one solve, so this class owns both
        // rather than reading a field of view off the node and hoping the two
        // agree. The projection direction is stated rather than assumed:
        // `fieldOfView` is a VERTICAL angle only while `projectionDirection`
        // is `.vertical` (the two cases are `.vertical` and `.horizontal`,
        // and vertical is the default), and every line of `solve(for:)`
        // divides by a vertical half-angle and multiplies the horizontal one
        // out by the aspect ratio itself. Setting it here is what keeps the
        // solve right if the scene's camera is ever built with the other.
        lens.camera?.fieldOfView = Self.lensFieldOfView
        lens.camera?.projectionDirection = .vertical
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
    /// on from behind the far line (three metres then, two since 2026-09-24,
    /// `place(combatants:entering:)`), dashing at a victim, or fading out
    /// with a cleared wave. The field is a high-water mark that never comes
    /// back down, so measuring one of those transients steps the camera back
    /// for the rest of the fight — the walk-on stands a unit at −6.8 m, which
    /// the clamp below only trims to −6.5 (then; since 2026-09-24 it starts
    /// at −5.4 or −6.4, well inside the −15…+9 clamp, so skipping the walk
    /// is the only guard), and `playNext()` drains and calls
    /// `returnHome()` in the same frame the wave is placed, so the walk WAS
    /// being measured; in the Labyrinth, where every level is three waves,
    /// the camera stepped back at each one and never came in again. The idle
    /// and the clips play on the model container rather than on this node, so
    /// a unit at rest has no action here to read.
    private func measureField() -> FieldBounds? {
        guard let stage = rig.parent else { return nil }
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
            // The team's row stands at +7.0 to +7.5 since 2026-09-24 and a
            // boss on the far rim wherever the floor's edge is.
            let z = max(-15, min(9, unit.position.z))
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
        // THE TWO FEET LINES (2026-09-24). An ordinary fight is framed the
        // genre's way: the near row's feet on `nearFeetLine` below centre,
        // the far row's on `farFeetLine` above it. At a fixed pitch and lens
        // those two lines fix where the camera stands relative to the rows —
        // its height H and its distance Z behind the near feet from
        // H = tan(e1)·Z = tan(e2)·(Z + gap), e1 and e2 the angles below the
        // horizon at which the two lines leave the lens — and so the depth
        // at which the near feet stand in front of it, `gapDepth`. A boss
        // fight keeps its own rules below.
        var gapDepth: Float?
        var nearFootZ: Float = 0
        if !field.hasBoss {
            let feetZ = points.filter { $0.position.y < 0.01 }.map { $0.position.z }
            // The far row: the feet on the enemy's own marks, `arenaRowDepth`
            // beyond the arena's centre and the staggered back line behind
            // it — never a foot merely beyond the centre (2026-09-24). The
            // field is a union that never shrinks, and a melee player unit
            // measured where its dash landed (about z −2, in front of the
            // enemy row, with its return not yet started) would join the
            // MEAN below for good, walking the camera in a few percent at
            // every drain and cutting the frame between turns.
            let farRow = StageBuilder.arenaCentre.z - StageBuilder.arenaRowDepth + 0.01
            let farZ = feetZ.filter { $0 <= farRow }
            if let near = feetZ.max(), !farZ.isEmpty {
                let far = farZ.reduce(0, +) / Float(farZ.count)
                let gap = near - far
                let below = atan(feetLine * tanV)
                let above = atan(Self.farFeetLine * tanV)
                let e1 = pitch + below
                let e2 = pitch - above
                if gap > 0, e2 > 0, tan(e1) > tan(e2) {
                    let behind = tan(e2) * gap / (tan(e1) - tan(e2))
                    gapDepth = behind / cos(e1) * cos(below)
                    nearFootZ = near
                }
            }
        }

        // Start on the field's centre, a metre up.
        var aim = SCNVector3(0, 1, 0)
        for point in points {
            aim.x += point.position.x / Float(points.count)
            aim.z += point.position.z / Float(points.count)
        }
        var distance = Float(16)
        for _ in 0..<8 {
            var required = Self.minDistance
            if let gapDepth {
                // The aim only ever slides across and up the frame, never
                // along the line of sight, so the near feet's depth in front
                // of the lens is the distance plus a constant: this is the
                // distance that stands them `gapDepth` from it.
                let nearFoot = SCNVector3(0, 0, nearFootZ)
                let offset = SCNVector3(nearFoot.x - aim.x, nearFoot.y - aim.y, nearFoot.z - aim.z)
                required = max(required, gapDepth - dot(offset, forward))
            }
            for point in points {
                let p = point.position
                let offset = SCNVector3(p.x - aim.x, p.y - aim.y, p.z - aim.z)
                let across = dot(offset, right)
                let vertical = dot(offset, up)
                let depth = dot(offset, forward)
                required = max(required, abs(across) / (Self.widthMargin * tanH) - depth)
                // The team's feet — the near side of the arena's centre —
                // clear of the HUD's bottom corners (`teamWidthMargin`).
                if !field.hasBoss, p.y < 0.01, p.z > StageBuilder.arenaCentre.z {
                    required = max(required, abs(across) / (Self.teamWidthMargin * tanH) - depth)
                }
                if vertical > 0 {
                    required = max(required, vertical / (point.topLine * tanV) - depth)
                } else if gapDepth == nil {
                    // The near feet are rested on their line by the aim's
                    // slide below whatever the distance, so with the two feet
                    // lines in charge this is no limit; a boss fight keeps it
                    // as it was tuned.
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
        stopMoves()
        // Nothing sets a constraint on this node any more — shots aim with
        // `look(at:)` frame by frame — but an old one left in place used to
        // turn the home framing into a stare at the last victim's chest, so
        // the clear stays as a guard.
        rig.constraints = []
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
        rig.removeAction(forKey: "fov")
        rig.position = homePosition
        rig.look(at: homeAim)
        lens.camera?.fieldOfView = Self.lensFieldOfView
        isOffHome = false
    }

    // MARK: - Shots

    /// Plays a shot on a caster, optionally aimed at a victim.
    ///
    /// `focus` is where the caster will be STANDING when the shot lands, when
    /// that is not where it stands now: a melee unit leaps at its victim in
    /// the same beat the shot is asked for, and a push-in aimed at its mark
    /// zoomed onto the empty floor it had just left while it fought four
    /// metres away (the owner, 2026-09-15, with Sekhmet's Seven Arrows:
    /// "the camera zooms really close to nothing").
    func perform(
        _ shot: CameraShot,
        on caster: UnitNode,
        target: UnitNode?,
        focus: SCNVector3? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard Self.isCinematic else {
            zoom(shot, on: caster, target: target, focus: focus, completion: completion)
            return
        }

        shotGeneration += 1
        stopMoves()
        rig.constraints = []
        isOffHome = true

        let casterPosition = focus.map { SCNVector3($0.x, $0.y + caster.spec.height * 0.6, $0.z) }
            ?? caster.chestWorldPosition
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
            rig.position = start
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
            rig.runAction(.sequence([orbit, .wait(duration: duration * 0.2)]), forKey: "shot") { [weak self] in
                self?.afterShot(generation, completion)
            }
        }
    }

    /// The fixed camera's one move: a dolly along its own line of sight toward
    /// the unit the skill belongs to, held for the clip, and back.
    ///
    /// The orientation is never touched — not the yaw, not the pitch, not the
    /// lens — so the floor never swings and the field stays the field the
    /// player has been reading all fight, nearer. The camera slides PARALLEL
    /// to itself: it moves to the point on the subject's own line of sight
    /// that stands `distance` back, which recentres the subject without a
    /// pan, and `distance` is what makes the figure the wanted fraction of
    /// the frame at the home lens. A subject deeper in the field than that
    /// distance allows is simply not zoomed on as far (the move never dollies
    /// OUT past home, so a boss framed from 25 m is left where it is), and
    /// the move is eased in over 0.22 s and out over 0.30 s rather than cut,
    /// because there is nothing a parallel move can leave half way — every
    /// frame of it is the home framing at a different distance.
    private func zoom(
        _ shot: CameraShot,
        on caster: UnitNode,
        target: UnitNode?,
        focus: SCNVector3?,
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
        // How much of the frame's height the figure stands, and how long the
        // shot holds: tighter for a blow landing, looser for an ultimate,
        // whose effect needs the room around the figure.
        let fraction: Float
        let hold: TimeInterval
        switch shot {
        case .impactClose:
            fraction = 0.60
            hold = 0.55
        case .pushIn:
            fraction = 0.52
            hold = 0.75
        case .heroLowAngle:
            fraction = 0.48
            hold = 1.0
        default:
            fraction = 0.44
            hold = 1.2
        }

        // The home line of sight, kept exactly.
        let sight = SCNVector3(homeAim.x - homePosition.x, homeAim.y - homePosition.y, homeAim.z - homePosition.z)
        let length = max(0.001, (sight.x * sight.x + sight.y * sight.y + sight.z * sight.z).squareRoot())
        let dir = SCNVector3(sight.x / length, sight.y / length, sight.z / length)
        // The figure `fraction` of the frame tall at the home lens: the frame
        // is 2·d·tan(fov/2) tall at distance d, so d = (height / fraction) /
        // (2·tan(fov/2)). A 1.9 m figure at 52% and 30° is 6.8 m.
        let halfLens = Float(Self.lensFieldOfView) / 2 * .pi / 180
        let wanted = (height / fraction) / (2 * tan(halfLens))
        // The subject's chest, and how far along the line of sight it stands
        // from home; the move never goes past home, so `distance` is capped at
        // 85% of that depth, which for a boss 25 m out means a modest step.
        // The caster's landing spot when it is about to leap; otherwise
        // where the subject stands now.
        let standing = (subject === caster ? focus : nil) ?? subject.position
        let chest = SCNVector3(standing.x, standing.y + height * 0.55, standing.z)
        let depth = dot(SCNVector3(chest.x - homePosition.x, chest.y - homePosition.y, chest.z - homePosition.z), dir)
        guard depth > 3 else {
            completion?()
            return
        }
        let distance = min(wanted, depth * 0.85)
        let full = SCNVector3(chest.x - dir.x * distance, chest.y - dir.y * distance, chest.z - dir.z * distance)
        // Reduce Motion (`MotionComfort`, Docs/SETTINGS.md §2): the same
        // dolly, a share of the way and a gentler ease — the push still
        // says whose skill it is, without the rush.
        let gentle = MotionComfort.isReduced
        let destination = gentle ? lerp(homePosition, full, MotionComfort.zoomReach) : full
        let easeIn: TimeInterval = gentle ? 0.22 * MotionComfort.zoomEase : 0.22
        let easeOut: TimeInterval = gentle ? 0.30 * MotionComfort.zoomEase : 0.30

        shotGeneration += 1
        let generation = shotGeneration
        stopMoves()
        rig.constraints = []
        // Orientation set once, from home, and never again during the shot:
        // the move below changes the position only.
        rig.position = homePosition
        rig.look(at: homeAim)
        lens.camera?.fieldOfView = Self.lensFieldOfView
        isOffHome = true

        let home = homePosition
        let dollyIn = SCNAction.customAction(duration: easeIn) { node, elapsed in
            let raw = Float(min(1, elapsed / CGFloat(easeIn)))
            let t = raw * raw * (3 - 2 * raw)
            node.position = SCNVector3(
                home.x + (destination.x - home.x) * t,
                home.y + (destination.y - home.y) * t,
                home.z + (destination.z - home.z) * t
            )
        }
        let settle = SCNAction.wait(duration: hold)
        let dollyOut = SCNAction.customAction(duration: easeOut) { node, elapsed in
            let raw = Float(min(1, elapsed / CGFloat(easeOut)))
            let t = raw * raw * (3 - 2 * raw)
            node.position = SCNVector3(
                destination.x + (home.x - destination.x) * t,
                destination.y + (home.y - destination.y) * t,
                destination.z + (home.z - destination.z) * t
            )
        }
        rig.runAction(.sequence([dollyIn, settle, dollyOut]), forKey: "shot") { [weak self] in
            self?.afterShot(generation, completion)
        }
    }

    // MARK: - The shake (Docs/FEEL.md W2.18)

    /// A hit's trauma at the player's speed (`Juice.trauma(for:speed:)`), and
    /// its kick: `metres` along the line from `striker` to `victim` as the
    /// screen sees it — the lens's own right and up, read off the rig, so a
    /// blow into the frame jolts it up and one out of it jolts it down, and
    /// a blow across it across. The shake itself is `CameraShake`, written
    /// on the lens by the controller on the render thread; nothing here
    /// moves a node. Never under Reduce Motion (the shaker's own guard): the
    /// hit's flash and sound carry it.
    func addTrauma(_ amount: Float, speed: Double, from striker: SCNVector3? = nil, to victim: SCNVector3? = nil,
                   kick metres: Float = 0) {
        shaker.add(amount, speed: speed)
        guard metres > 0, let striker, let victim else { return }
        let line = SCNVector3(victim.x - striker.x, victim.y - striker.y, victim.z - striker.z)
        let right: Float = dot(line, rig.worldRight)
        let up: Float = dot(line, rig.worldUp)
        shaker.kick(right: right, up: up, metres: metres)
    }

    /// Trauma held at `level` or over for `seconds`: a boss climbing over the
    /// rim or sinking back under it rumbles the whole way.
    func rumble(_ level: Float, for seconds: TimeInterval) {
        shaker.rumble(level, for: seconds)
    }

    /// Stops whatever is moving the rig — a shot, a lens change — and
    /// nothing else: the grade's own action (`drainColour`) is not a move,
    /// and a return home must not undo a field's colour draining. The shake
    /// is the lens's and runs on through a return home (W2.18): a blow that
    /// ends a shot still lands.
    private func stopMoves() {
        for key in ["shot", "fov"] {
            rig.removeAction(forKey: key)
        }
    }

    // MARK: - The impact frame (Docs/FEEL.md W1.3)

    /// The saturation, and what the contrast and the exposure gain, for the
    /// two frames of a crit's or a kill's impact frame: the anime cut of a
    /// big hit, the colour knocked out of the world and the light pushed,
    /// before everything snaps back.
    static let impactSaturation: CGFloat = 0.25
    static let impactContrast: CGFloat = 0.35
    static let impactExposure: CGFloat = 0.3

    /// Main thread: the impact frame as two changes to the camera, the punch
    /// and the restore that puts the grade back exactly as
    /// `StageBuilder.grade(for:)` set it (read when this director was made).
    /// The controller runs BOTH on the renderer's thread, in
    /// `renderer(_:updateAtTime:)`, where SceneKit applies a change directly,
    /// and counts the drawn frames between them
    /// (`BattleSceneController.impactFrames`). The punch used to be written
    /// here, into the main thread's implicit transaction, and the restore
    /// queued on the main queue two sixtieths of a second on: a busy main
    /// thread held the world grey (run 245's 8-b), and a restore written on
    /// the render thread could have landed before a punch still waiting for
    /// its transaction to commit, and left it grey for good (review,
    /// 2026-09-24). Not through an action: it lands at the start of the
    /// hit's freeze, when every action in the scene is paused and the view
    /// is still drawing. Never under Reduce Motion, and not over a field
    /// whose colour is draining; nil when there is nothing to punch.
    func impactFrame() -> (punch: () -> Void, restore: () -> Void)? {
        guard !MotionComfort.isReduced, !draining, let camera = lens.camera else { return nil }
        let punchSaturation: CGFloat = Self.impactSaturation
        let punchContrast: CGFloat = restContrast + Self.impactContrast
        let punchExposure: CGFloat = restExposure + Self.impactExposure
        let saturation = restSaturation
        let contrast = restContrast
        let exposure = restExposure
        let punch: () -> Void = { [weak camera] in
            guard let camera else { return }
            camera.saturation = punchSaturation
            camera.contrast = punchContrast
            camera.exposureOffset = punchExposure
        }
        let restore: () -> Void = { [weak camera] in
            guard let camera else { return }
            camera.saturation = saturation
            camera.contrast = contrast
            camera.exposureOffset = exposure
        }
        return (punch: punch, restore: restore)
    }

    /// How far the splash's end pushes the exposure, in stops (Docs/FEEL.md
    /// W2.9): the ultimate's light arriving.
    static let splashExposure: CGFloat = 1.1

    /// Main thread: the end of an ultimate's splash as two changes to the
    /// camera, run by the controller on the renderer's thread two drawn
    /// frames apart exactly as `impactFrame`'s are — the exposure pushed
    /// `splashExposure` stops, then the realm's own. It replaces the white
    /// full-screen flash the cut-in used to fire, which read as a UI flash
    /// over the fight; this is the fight's own light, through the bloom and
    /// the white point. Never under Reduce Motion, never over a draining
    /// field; nil when there is nothing to punch.
    func exposurePunch() -> (punch: () -> Void, restore: () -> Void)? {
        guard !MotionComfort.isReduced, !draining, let camera = lens.camera else { return nil }
        let pushed: CGFloat = restExposure + Self.splashExposure
        let exposure = restExposure
        let saturation = restSaturation
        let contrast = restContrast
        let punch: () -> Void = { [weak camera] in
            camera?.exposureOffset = pushed
        }
        // The whole grade back, not the exposure alone: this pair takes an
        // impact frame's place in the controller's queue, and a crit's punch
        // whose restore it replaced must not be left on the camera.
        let restore: () -> Void = { [weak camera] in
            guard let camera else { return }
            camera.saturation = saturation
            camera.contrast = contrast
            camera.exposureOffset = exposure
        }
        return (punch: punch, restore: restore)
    }

    /// The realm's grade, exactly.
    private func restoreGrade() {
        guard let camera = lens.camera else { return }
        camera.saturation = restSaturation
        camera.contrast = restContrast
        camera.exposureOffset = restExposure
    }

    // MARK: - The end of the fight (Docs/FEEL.md W1.7)

    /// Main thread, on a loss: the colour eases out of the field to
    /// `saturation` over `duration`, from the realm's grade, and stays out
    /// until a new run builds a new camera. An action on the camera under
    /// its own key (`stopMoves` leaves it), easing by smoothstep.
    func drainColour(to saturation: CGFloat, over duration: TimeInterval) {
        guard let camera = lens.camera else { return }
        draining = true
        restoreGrade()
        let from = restSaturation
        let span: TimeInterval = max(0.01, duration)
        rig.removeAction(forKey: "grade")
        let drain = SCNAction.customAction(duration: span) { _, elapsed in
            let raw = min(1, CGFloat(elapsed) / CGFloat(span))
            let eased = raw * raw * (3 - 2 * raw)
            camera.saturation = from + (saturation - from) * eased
        }
        rig.runAction(drain, forKey: "grade")
    }

    /// The final blow's camera (W1.7): from wherever the camera is — a
    /// skill's zoom may hold it — it eases along the home line of sight
    /// toward the victim over `easeIn`, the victim 42% of the frame tall at
    /// most, and back home over `back`. The same yaw, pitch and lens as
    /// every frame of the fight: the floor never turns. Its actions run in
    /// scene time, so they wait out the blow's freeze with everything else.
    func easeToward(_ victim: UnitNode, over easeIn: TimeInterval, back easeOut: TimeInterval) {
        let sight = SCNVector3(homeAim.x - homePosition.x, homeAim.y - homePosition.y, homeAim.z - homePosition.z)
        let length = max(0.001, (sight.x * sight.x + sight.y * sight.y + sight.z * sight.z).squareRoot())
        let dir = SCNVector3(sight.x / length, sight.y / length, sight.z / length)
        let height = victim.spec.height
        let halfLens = Float(Self.lensFieldOfView) / 2 * .pi / 180
        let wanted = (height / Self.finalBlowFraction) / (2 * tan(halfLens))
        let standing = victim.position
        let chest = SCNVector3(standing.x, standing.y + height * 0.55, standing.z)
        let depth = dot(SCNVector3(chest.x - homePosition.x, chest.y - homePosition.y, chest.z - homePosition.z), dir)
        guard depth > 3 else { return }
        let distance = min(wanted, depth * 0.85)
        let destination = SCNVector3(chest.x - dir.x * distance, chest.y - dir.y * distance, chest.z - dir.z * distance)
        let start = rig.position
        let home = homePosition
        shotGeneration += 1
        let generation = shotGeneration
        stopMoves()
        rig.constraints = []
        lens.camera?.fieldOfView = Self.lensFieldOfView
        isOffHome = true
        let inSpan: TimeInterval = max(0.01, easeIn)
        let outSpan: TimeInterval = max(0.01, easeOut)
        let dollyIn = SCNAction.customAction(duration: inSpan) { node, elapsed in
            let raw = Float(min(1, elapsed / CGFloat(inSpan)))
            let t = raw * raw * (3 - 2 * raw)
            node.position = SCNVector3(
                start.x + (destination.x - start.x) * t,
                start.y + (destination.y - start.y) * t,
                start.z + (destination.z - start.z) * t
            )
        }
        let dollyOut = SCNAction.customAction(duration: outSpan) { node, elapsed in
            let raw = Float(min(1, elapsed / CGFloat(outSpan)))
            let t = raw * raw * (3 - 2 * raw)
            node.position = SCNVector3(
                destination.x + (home.x - destination.x) * t,
                destination.y + (home.y - destination.y) * t,
                destination.z + (home.z - destination.z) * t
            )
        }
        rig.runAction(.sequence([dollyIn, dollyOut]), forKey: "shot") { [weak self] in
            self?.afterShot(generation, nil)
        }
    }

    /// How much of the frame's height the final blow's victim may stand.
    private static let finalBlowFraction: Float = 0.42

    /// The triumph's framing (W1.7): the camera comes in along the home line
    /// of sight on the survivors — `team`, each at the mark it is walking
    /// onto, with its height — until they stand `teamFraction` of the frame
    /// tall, no nearer than keeps every one of them and a shoulder's room
    /// inside `teamSpread` of the half-width, and holds there. The team's
    /// chests sit well under the frame's centre (`teamLowering`), leaving the
    /// upper frame to the VICTORY stamp. The same yaw, pitch and lens: the floor
    /// never turns. Reduce Motion goes `MotionComfort.zoomReach` of the way.
    /// Returns where the camera ends, so each figure can turn to face it.
    @discardableResult
    func frameTeam(_ team: [(position: SCNVector3, height: Float)], over duration: TimeInterval) -> SCNVector3 {
        guard !team.isEmpty else { return rig.position }
        let sight = SCNVector3(homeAim.x - homePosition.x, homeAim.y - homePosition.y, homeAim.z - homePosition.z)
        let length = max(0.001, (sight.x * sight.x + sight.y * sight.y + sight.z * sight.z).squareRoot())
        let dir = SCNVector3(sight.x / length, sight.y / length, sight.z / length)
        // The frame's right and up, from the home camera: level, and square
        // to the line of sight.
        let flat = max(0.001, (dir.x * dir.x + dir.z * dir.z).squareRoot())
        let right = SCNVector3(-dir.z / flat, 0, dir.x / flat)
        let up = SCNVector3(
            right.y * dir.z - right.z * dir.y,
            right.z * dir.x - right.x * dir.z,
            right.x * dir.y - right.y * dir.x
        )
        var centreX: Float = 0
        var centreZ: Float = 0
        var tallest: Float = 0
        for member in team {
            centreX += member.position.x / Float(team.count)
            centreZ += member.position.z / Float(team.count)
            tallest = max(tallest, member.height)
        }
        let chest = SCNVector3(centreX, tallest * 0.55, centreZ)
        let tanV = tan(Float(Self.lensFieldOfView) * .pi / 360)
        let tanH = tanV * Self.aspect
        let forHeight = (tallest / Self.teamFraction) / (2 * tanV)
        var reach: Float = 0
        for member in team {
            let offset = SCNVector3(member.position.x - chest.x, 0, member.position.z - chest.z)
            reach = max(reach, abs(dot(offset, right)) + Self.shoulderRoom)
        }
        let forWidth = reach / (Self.teamSpread * tanH)
        let depth = dot(SCNVector3(chest.x - homePosition.x, chest.y - homePosition.y, chest.z - homePosition.z), dir)
        guard depth > 3 else { return rig.position }
        let distance = min(max(forHeight, forWidth), depth * 0.85)
        // The team well under the centre: the frame's centre is set on a
        // point above the chest.
        let lift = distance * tanV * Self.teamLowering
        let focus = SCNVector3(chest.x + up.x * lift, chest.y + up.y * lift, chest.z + up.z * lift)
        let full = SCNVector3(focus.x - dir.x * distance, focus.y - dir.y * distance, focus.z - dir.z * distance)
        let destination = MotionComfort.isReduced ? lerp(homePosition, full, MotionComfort.zoomReach) : full
        let start = rig.position
        shotGeneration += 1
        stopMoves()
        rig.constraints = []
        lens.camera?.fieldOfView = Self.lensFieldOfView
        isOffHome = true
        let span: TimeInterval = max(0.01, duration)
        let dolly = SCNAction.customAction(duration: span) { node, elapsed in
            let raw = Float(min(1, elapsed / CGFloat(span)))
            let t = raw * raw * (3 - 2 * raw)
            node.position = SCNVector3(
                start.x + (destination.x - start.x) * t,
                start.y + (destination.y - start.y) * t,
                start.z + (destination.z - start.z) * t
            )
        }
        // Held: no way back is queued. A new run builds a new camera.
        rig.runAction(dolly, forKey: "shot")
        return destination
    }

    /// The team's share of the frame's height in the triumph, how much of
    /// the half-width its outermost shoulders may reach, and how far under
    /// the centre (as a share of the half-frame) its chests stand.
    ///
    /// 0.42 under, not 0.22 (review, 2026-09-24): the VICTORY stamp takes
    /// the frame's top 136 points (`VictoryStamp`: its stars, then its
    /// 84-point band), and at 0.22 the team's heads stood 150–190 points
    /// down, which put every plate's LEVEL UP (its words stand 72 points
    /// over the head: `UnitPlate.riseAboveHead`, the track, a gap and the
    /// words) under the band and the tallest badge on its rule. At 0.42 —
    /// solved in a port of this and of the home camera for one to five
    /// survivors of 1.9–2.2 m on an 852 × 393 frame — the words' letters
    /// stand 139 points down or lower and the feet 375 or higher; a 2.6-m
    /// giant's words touch the band's foot and its feet reach 390. The
    /// camera still comes in to `teamFraction` (or as far as the width
    /// allows), and never less than 15% of its depth: a push onto a team
    /// that keeps the lower half of the frame while the stamp has the upper.
    private static let teamFraction: Float = 0.40
    private static let teamSpread: Float = 0.8
    private static let teamLowering: Float = 0.42

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
        let start = rig.position
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
        rig.runAction(.sequence([move, settle]), forKey: "shot") { [weak self] in
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
        guard let camera = lens.camera else { return }
        let start = camera.fieldOfView
        let action = SCNAction.customAction(duration: duration) { _, elapsed in
            let t = CGFloat(elapsed) / CGFloat(duration)
            camera.fieldOfView = start + (value - start) * min(1, t)
        }
        rig.runAction(action, forKey: "fov")
    }

    private func lerp(_ a: SCNVector3, _ b: SCNVector3, _ t: Float) -> SCNVector3 {
        SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }

    private func dot(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
}
