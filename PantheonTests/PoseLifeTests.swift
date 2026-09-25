import XCTest
import simd
@testable import Pantheon

/// The natural poses' pure parts (Docs/PLAN.md *Natural poses*, build steps
/// 6 and 8): the gaze's reach and aim, the victories the reveal and the
/// breaks find by their length, and the triumph's hold. Every figure an
/// assert compares is hoisted into a typed `let` first (CLAUDE.md: an
/// assert's parentheses stay free of arithmetic).
final class PoseLifeTests: XCTestCase {

    // MARK: - The gaze (build step 6)

    /// The lens is looked at fully within 80° of the figure's front, not at
    /// all past 120°, and less the further round between.
    func testTheGazeLetsGoOfALensBehindTheShoulder() {
        let degree: Float = .pi / 180
        let ahead: Float = Gaze.reach(0)
        let edge: Float = Gaze.reach(80 * degree)
        let between: Float = Gaze.reach(100 * degree)
        let later: Float = Gaze.reach(110 * degree)
        let behind: Float = Gaze.reach(120 * degree)
        let back: Float = Gaze.reach(180 * degree)
        let otherSide: Float = Gaze.reach(-100 * degree)
        XCTAssertEqual(ahead, 1, accuracy: 1e-6)
        XCTAssertEqual(edge, 1, accuracy: 1e-6)
        XCTAssertGreaterThan(between, 0)
        XCTAssertLessThan(between, 1)
        XCTAssertLessThan(later, between)
        XCTAssertEqual(behind, 0, accuracy: 1e-6)
        XCTAssertEqual(back, 0, accuracy: 1e-6)
        XCTAssertEqual(otherSide, between, accuracy: 1e-6)
    }

    /// Straight ahead turns nothing; a lens off to one side is turned to,
    /// never past 25° across or 12° up; the figure's left is +X.
    func testTheGazeAimsTowardTheLensWithinItsRange() {
        let degree: Float = .pi / 180
        let straight = Gaze.aim(toward: SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(straight.yaw, 0, accuracy: 1e-6)
        XCTAssertEqual(straight.pitch, 0, accuracy: 1e-6)

        let slightLeft = Gaze.aim(toward: SIMD3<Float>(sin(10 * degree), 0, cos(10 * degree)))
        let tenDegrees: Float = 10 * degree
        XCTAssertEqual(slightLeft.yaw, tenDegrees, accuracy: 1e-4)

        let farRight = Gaze.aim(toward: SIMD3<Float>(sin(-60 * degree), 0, cos(-60 * degree)))
        let capAcross: Float = -Gaze.maxYaw
        XCTAssertEqual(farRight.yaw, capAcross, accuracy: 1e-5)

        let above = Gaze.aim(toward: SIMD3<Float>(0, sin(40 * degree), cos(40 * degree)))
        let capUp: Float = Gaze.maxPitch
        XCTAssertEqual(above.pitch, capUp, accuracy: 1e-5)
        XCTAssertEqual(above.yaw, 0, accuracy: 1e-6)

        let behind = Gaze.aim(toward: SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(behind.yaw, 0, accuracy: 1e-6)
        XCTAssertEqual(behind.pitch, 0, accuracy: 1e-6)
    }

    /// The gaze's range is the craft's: a head turned more than 25° across
    /// or 12° up twists the neck's skin on Meshy's one-joint necks.
    func testTheGazeRangeIsTheCraftsRange() {
        let degrees: Float = 180 / .pi
        let across: Float = Gaze.maxYaw * degrees
        let up: Float = Gaze.maxPitch * degrees
        XCTAssertEqual(across, 25, accuracy: 1e-4)
        XCTAssertEqual(up, 12, accuracy: 1e-4)
    }

    /// A hand-back is told from a slow frame of the clip: the angle reads a
    /// fifth of a degree as a fifth of a degree, and only a turn under
    /// `sameAngle` is taken for the block's own answer handed back.
    func testTheGazeTellsAHandBackFromASlowClip() {
        let degree: Float = .pi / 180
        let rest = simd_quatf(angle: 0.3, axis: simd_normalize(SIMD3<Float>(0.2, 1, 0.1)))
        let nudge = simd_quatf(angle: 0.2 * degree, axis: SIMD3<Float>(0, 1, 0))
        let moved: simd_quatf = nudge * rest
        let slow: Float = Gaze.angle(between: moved, rest)
        let fifth: Float = 0.2 * degree
        XCTAssertEqual(slow, fifth, accuracy: 1e-5)
        XCTAssertGreaterThan(slow, Gaze.sameAngle)
        let same: Float = Gaze.angle(between: rest, rest)
        XCTAssertLessThan(same, Gaze.sameAngle)
        let flipped = simd_quatf(vector: -rest.vector)
        let sign: Float = Gaze.angle(between: flipped, rest)
        XCTAssertLessThan(sign, Gaze.sameAngle)
    }

    // MARK: - The victories (build step 8.4)

    /// The four victories dealt from the bought presets are found by their
    /// length, beside the three the motion palette dealt before them.
    func testTheBoughtVictoriesAreFoundByTheirLength() {
        let cheer: RevealEntranceCut = RevealEntrance.cut(forClipLength: 1.6667)
        let pump: RevealEntranceCut = RevealEntrance.cut(forClipLength: 1.5333)
        let stomp: RevealEntranceCut = RevealEntrance.cut(forClipLength: 1.4)
        let bow: RevealEntranceCut = RevealEntrance.cut(forClipLength: 3.6)
        XCTAssertEqual(cheer, RevealEntrance.cheerOneHand)
        XCTAssertEqual(pump, RevealEntrance.fistPump)
        XCTAssertEqual(stomp, RevealEntrance.stomp)
        XCTAssertEqual(bow, RevealEntrance.bow)
        let oldCheer: RevealEntranceCut = RevealEntrance.cut(forClipLength: 1.90)
        XCTAssertEqual(oldCheer, RevealEntrance.cheer)
    }

    /// No two presets are closer in length than the tolerance that tells
    /// them apart.
    func testNoTwoPresetsShareALength() {
        let lengths: [TimeInterval] = RevealEntrance.presets.map(\.length).sorted()
        for (shorter, longer) in zip(lengths, lengths.dropFirst()) {
            let gap: TimeInterval = longer - shorter
            let twice: TimeInterval = 2 * RevealEntrance.lengthTolerance
            XCTAssertGreaterThan(gap, twice, "\(shorter) s and \(longer) s")
        }
    }

    /// A bow greets; it is never an idle break. Every other victory is one.
    func testTheBowIsNeverABreak() {
        XCTAssertFalse(RevealEntrance.breaks(RevealEntrance.bow))
        for preset in RevealEntrance.presets where preset.cut != RevealEntrance.bow {
            XCTAssertTrue(RevealEntrance.breaks(preset.cut), preset.cut.preset)
        }
    }

    /// The triumph waits its 2.4 s for a short victory, long enough for the
    /// bow to finish and settle, and never past 3.6 s.
    func testTheTriumphHoldsForTheLongestVictory() {
        let none: TimeInterval = BattleSceneController.triumphHold(forVictory: 0)
        let pump: TimeInterval = BattleSceneController.triumphHold(forVictory: 1.08)
        let bowWindow: TimeInterval = RevealEntrance.bow.end - RevealEntrance.bow.start
        let bow: TimeInterval = BattleSceneController.triumphHold(forVictory: bowWindow)
        let endless: TimeInterval = BattleSceneController.triumphHold(forVictory: 10)
        let bowDone: TimeInterval = bowWindow + BattleSceneController.triumphSettle
        let bowNeeds: TimeInterval = min(bowDone, BattleSceneController.triumphLongest)
        XCTAssertEqual(none, BattleSceneController.triumphDuration, accuracy: 1e-9)
        XCTAssertEqual(pump, BattleSceneController.triumphDuration, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(bow, bowNeeds)
        XCTAssertEqual(endless, BattleSceneController.triumphLongest, accuracy: 1e-9)
    }
}
