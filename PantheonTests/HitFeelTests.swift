import XCTest
@testable import Pantheon

/// The numbers behind a hit's feel (Docs/FEEL.md W1.1, W1.2, W1.3, W1.7): the
/// freeze by the blow's weight, by its share of the victim's health and by the
/// player's speed; ×3 scaled rather than switched off; a multi-hit's early
/// hits drawn fainter and its run closed by a TOTAL; the final blow; and the
/// slow motion that follows it. Every one is a pure function, so the feel is
/// pinned here and in `Juice`/`BattleSceneController` together.
final class HitFeelTests: XCTestCase {

    private let tolerance: Double = 1e-9

    // MARK: - The freeze

    func testTheFreezeStartsAtTheWeightsOwnPause() {
        let normal: TimeInterval = Juice.freeze(for: .normal, share: 0, early: false, speed: 1)
        let heavy: TimeInterval = Juice.freeze(for: .heavy, share: 0, early: false, speed: 1)
        let critical: TimeInterval = Juice.freeze(for: .critical, share: 0, early: false, speed: 1)
        let lethal: TimeInterval = Juice.freeze(for: .lethal, share: 0, early: false, speed: 1)
        let glance: TimeInterval = Juice.freeze(for: .light, share: 1, early: false, speed: 1)
        XCTAssertEqual(normal, 0.045, accuracy: tolerance)
        XCTAssertEqual(heavy, 0.075, accuracy: tolerance)
        XCTAssertEqual(critical, 0.090, accuracy: tolerance)
        XCTAssertEqual(lethal, 0.150, accuracy: tolerance)
        XCTAssertEqual(glance, 0, "a glancing blow never freezes, however much it took")
    }

    func testTheFreezeGrowsWithTheShareOfHealthTakenUpToAThird() {
        // 0.10 s more at a third of the victim's health; less in proportion
        // under it; no more past it.
        let tenth: TimeInterval = Juice.freeze(for: .normal, share: 0.1, early: false, speed: 1)
        let third: TimeInterval = Juice.freeze(for: .normal, share: 1.0 / 3.0, early: false, speed: 1)
        let whole: TimeInterval = Juice.freeze(for: .normal, share: 1, early: false, speed: 1)
        let tenthExpected: TimeInterval = 0.045 + 0.10 * 0.3
        let thirdExpected: TimeInterval = 0.045 + 0.10
        XCTAssertEqual(tenth, tenthExpected, accuracy: tolerance)
        XCTAssertEqual(third, thirdExpected, accuracy: tolerance)
        XCTAssertEqual(whole, third, accuracy: tolerance, "a third of the health or more adds the whole 0.10 s")
    }

    func testTheFreezeIsCappedAtTwentyTwoHundredths() {
        let lethal: TimeInterval = Juice.freeze(for: .lethal, share: 1, early: false, speed: 1)
        let critical: TimeInterval = Juice.freeze(for: .critical, share: 1, early: false, speed: 1)
        let criticalExpected: TimeInterval = 0.09 + 0.10
        XCTAssertEqual(lethal, Juice.longestFreeze, accuracy: tolerance, "a killing blow's 0.25 is held to the cap")
        XCTAssertEqual(critical, criticalExpected, accuracy: tolerance)
        XCTAssertLessThanOrEqual(critical, Juice.longestFreeze)
    }

    func testAMultiHitsEarlyHitsFreezeForSixtyPercent() {
        let early: TimeInterval = Juice.freeze(for: .heavy, share: 0, early: true, speed: 1)
        let whole: TimeInterval = Juice.freeze(for: .heavy, share: 0, early: false, speed: 1)
        let expected: TimeInterval = whole * 0.6
        XCTAssertEqual(early, expected, accuracy: tolerance)
    }

    // MARK: - ×2 and ×3 (W1.1)

    func testDoubleSpeedHalvesTheFreezeAsItAlwaysHas() {
        let single: TimeInterval = Juice.freeze(for: .critical, share: 0.2, early: false, speed: 1)
        let double: TimeInterval = Juice.freeze(for: .critical, share: 0.2, early: false, speed: 2)
        let expected: TimeInterval = single / 2
        XCTAssertEqual(double, expected, accuracy: tolerance)
    }

    func testTripleSpeedKeepsAThirdOfTheFreezeOverATwentyMillisecondFloor() {
        let lethal: TimeInterval = Juice.freeze(for: .lethal, share: 0, early: false, speed: 3)
        let lethalExpected: TimeInterval = 0.15 / 3
        let normal: TimeInterval = Juice.freeze(for: .normal, share: 0, early: false, speed: 3)
        let earlyNormal: TimeInterval = Juice.freeze(for: .normal, share: 0, early: true, speed: 3)
        XCTAssertEqual(lethal, lethalExpected, accuracy: tolerance, "×3 is a third of the freeze, not none")
        XCTAssertEqual(normal, Juice.shortestFreeze, accuracy: tolerance, "a third of 45 ms is held at the 20 ms floor")
        XCTAssertEqual(earlyNormal, Juice.shortestFreeze, accuracy: tolerance)
        XCTAssertGreaterThan(normal, 0, "×3 never switches the freeze off")
    }

    func testTripleSpeedHalvesTheShake() {
        // The shake is trauma SQUARED (Docs/FEEL.md W2.18): ×2 adds the same
        // trauma, which the shaker lets fall twice as fast; ×3 adds √½ of it,
        // so its shake is half ×1's, and its kick is half as far.
        let single: Float = Juice.trauma(for: .heavy, speed: 1)
        let double: Float = Juice.trauma(for: .heavy, speed: 2)
        let triple: Float = Juice.trauma(for: .heavy, speed: 3)
        let singleShake: Float = single * single
        let tripleShake: Float = triple * triple
        let halved: Float = singleShake * 0.5
        XCTAssertEqual(double, single, "×2 shakes as hard as ×1, for half as long")
        XCTAssertEqual(tripleShake, halved, accuracy: 1e-6, "×3 shakes half as hard")
        let singleFall: Float = CameraShake.decayRate(speed: 1)
        let doubleFall: Float = CameraShake.decayRate(speed: 2)
        let twiceAsFast: Float = singleFall * 2
        XCTAssertEqual(doubleFall, twiceAsFast, accuracy: 1e-6, "×2's trauma falls twice as fast")
        let kickSingle: Float = Juice.kick(for: .heavy, speed: 1)
        let kickTriple: Float = Juice.kick(for: .heavy, speed: 3)
        let kickHalved: Float = kickSingle * 0.5
        XCTAssertEqual(kickTriple, kickHalved, accuracy: 1e-6)
        XCTAssertEqual(Juice.trauma(for: .light, speed: 1), 0, "a glance never shakes the camera")
    }

    func testTripleSpeedBuzzesOnlyForACritAKillOrAnUltimate() {
        XCTAssertTrue(Juice.hapticFires(for: .normal, speed: 1, ultimate: false))
        XCTAssertTrue(Juice.hapticFires(for: .heavy, speed: 2, ultimate: false))
        XCTAssertFalse(Juice.hapticFires(for: .light, speed: 1, ultimate: false), "a glance never buzzes")
        XCTAssertFalse(Juice.hapticFires(for: .normal, speed: 3, ultimate: false))
        XCTAssertFalse(Juice.hapticFires(for: .heavy, speed: 3, ultimate: false))
        XCTAssertTrue(Juice.hapticFires(for: .heavy, speed: 3, ultimate: true), "an ultimate's hit keeps its haptic")
        XCTAssertTrue(Juice.hapticFires(for: .critical, speed: 3, ultimate: false))
        XCTAssertTrue(Juice.hapticFires(for: .lethal, speed: 3, ultimate: false))
    }

    func testTheFinalBlowsFreezeIsScaledByTheSpeedToo() {
        let single: TimeInterval = Juice.scaledFreeze(Juice.finalBlowFreeze, speed: 1)
        let triple: TimeInterval = Juice.scaledFreeze(Juice.finalBlowFreeze, speed: 3)
        let tripleExpected: TimeInterval = 0.2 / 3
        XCTAssertEqual(single, 0.2, accuracy: tolerance)
        XCTAssertEqual(triple, tripleExpected, accuracy: tolerance)
    }

    // MARK: - The tremble inside the freeze

    func testTheTrembleIsAFewCentimetresAndDiesByTheRelease() {
        let hero: Float = Juice.tremorAmplitude(forHeight: 1.9)
        let giant: Float = Juice.tremorAmplitude(forHeight: 8)
        let child: Float = Juice.tremorAmplitude(forHeight: 0.5)
        XCTAssertGreaterThanOrEqual(hero, 0.02)
        XCTAssertLessThanOrEqual(hero, 0.03, "2–3 cm on a figure of ordinary height")
        XCTAssertLessThanOrEqual(giant, 0.10)
        XCTAssertEqual(child, 0.02, accuracy: 1e-6)
        let atRelease = Juice.tremorOffset(at: 0.12, of: 0.12, amplitude: hero)
        XCTAssertEqual(atRelease.across, 0, accuracy: 1e-6, "the body is still at the release")
        XCTAssertEqual(atRelease.along, 0, accuracy: 1e-6)
        for step in 0..<12 {
            let t: TimeInterval = Double(step) * 0.01
            let offset = Juice.tremorOffset(at: t, of: 0.12, amplitude: hero)
            let across: Float = abs(offset.across)
            let along: Float = abs(offset.along)
            XCTAssertLessThanOrEqual(across, hero)
            XCTAssertLessThanOrEqual(along, hero)
        }
    }

    // MARK: - The numbers (W1.2)

    func testAMultiHitsEarlyHitsAreDrawnFainter() {
        XCTAssertTrue(BattleSceneController.isEarlyHit(hitIndex: 0, hitCount: 3))
        XCTAssertTrue(BattleSceneController.isEarlyHit(hitIndex: 1, hitCount: 3))
        XCTAssertFalse(BattleSceneController.isEarlyHit(hitIndex: 2, hitCount: 3), "the last hit is drawn whole")
        XCTAssertFalse(BattleSceneController.isEarlyHit(hitIndex: 0, hitCount: 1), "a lone hit is drawn whole")
        let early = BattleSceneController.multiHitLook(early: true)
        let whole = BattleSceneController.multiHitLook(early: false)
        XCTAssertEqual(early.scale, 0.85, accuracy: 1e-9)
        XCTAssertEqual(early.opacity, 0.8, accuracy: 1e-9)
        XCTAssertEqual(whole.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(whole.opacity, 1, accuracy: 1e-9)
    }

    func testAMultiHitEndsOnAGoldTotalAfterItsLastHit() {
        var ledger = MultiHitLedger()
        let caster = UUID()
        let victim = UUID()
        let first: Double? = ledger.record(source: caster, target: victim, amount: 120, hitIndex: 0, hitCount: 3, lethal: false)
        let second: Double? = ledger.record(source: caster, target: victim, amount: 130, hitIndex: 1, hitCount: 3, lethal: false)
        let third: Double? = ledger.record(source: caster, target: victim, amount: 150, hitIndex: 2, hitCount: 3, lethal: false)
        let sum: Double = 120 + 130 + 150
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(third, sum, "the TOTAL follows the hit whose index is hitCount - 1")
        XCTAssertEqual(ledger.openRuns, 0)
    }

    func testASingleHitAndARunCutToOneEarnNoTotal() {
        var ledger = MultiHitLedger()
        let caster = UUID()
        let victim = UUID()
        let lone: Double? = ledger.record(source: caster, target: victim, amount: 500, hitIndex: 0, hitCount: 1, lethal: false)
        XCTAssertNil(lone, "a skill of one hit has no total")
        let killedAtOnce: Double? = ledger.record(source: caster, target: victim, amount: 900, hitIndex: 0, hitCount: 4, lethal: true)
        XCTAssertNil(killedAtOnce, "a kill on the first of four hits is a run of one")
        XCTAssertEqual(ledger.openRuns, 0)
    }

    func testAKillClosesTheRunEarlyWithItsTotal() {
        var ledger = MultiHitLedger()
        let caster = UUID()
        let victim = UUID()
        _ = ledger.record(source: caster, target: victim, amount: 200, hitIndex: 0, hitCount: 4, lethal: false)
        let killing: Double? = ledger.record(source: caster, target: victim, amount: 250, hitIndex: 1, hitCount: 4, lethal: true)
        let sum: Double = 200 + 250
        XCTAssertEqual(killing, sum)
        XCTAssertEqual(ledger.openRuns, 0)
    }

    func testEachSourceAndTargetIsARunOfItsOwn() {
        var ledger = MultiHitLedger()
        let caster = UUID()
        let counter = UUID()
        let first = UUID()
        let second = UUID()
        // A row of two, three hits each, interleaved as the engine lands them.
        for index in 0..<3 {
            let onFirst: Double? = ledger.record(source: caster, target: first, amount: 10, hitIndex: index, hitCount: 3, lethal: false)
            // A counter landed in the middle of the run is its own.
            if index == 1 {
                let riposte: Double? = ledger.record(source: counter, target: caster, amount: 40, hitIndex: 0, hitCount: 1, lethal: false)
                XCTAssertNil(riposte)
            }
            let onSecond: Double? = ledger.record(source: caster, target: second, amount: 20, hitIndex: index, hitCount: 3, lethal: false)
            if index < 2 {
                XCTAssertNil(onFirst)
                XCTAssertNil(onSecond)
            } else {
                let firstSum: Double = 30
                let secondSum: Double = 60
                XCTAssertEqual(onFirst, firstSum)
                XCTAssertEqual(onSecond, secondSum)
            }
        }
    }

    func testARunMissedOnItsLastHitIsPaidAtTheTurnsEnd() {
        var ledger = MultiHitLedger()
        let caster = UUID()
        let missed = UUID()
        let once = UUID()
        _ = ledger.record(source: caster, target: missed, amount: 70, hitIndex: 0, hitCount: 3, lethal: false)
        _ = ledger.record(source: caster, target: missed, amount: 80, hitIndex: 1, hitCount: 3, lethal: false)
        _ = ledger.record(source: caster, target: once, amount: 90, hitIndex: 1, hitCount: 3, lethal: false)
        let owed = ledger.closeAll()
        let sum: Double = 150
        XCTAssertEqual(owed.count, 1, "a run of one owes nothing")
        XCTAssertEqual(owed.first?.target, missed)
        XCTAssertEqual(owed.first?.total, sum)
        XCTAssertEqual(ledger.openRuns, 0)
    }

    // MARK: - The final blow and its slow motion (W1.7)

    func testTheFinalBlowIsTheKillThatLeavesItsSideEmpty() {
        XCTAssertTrue(BattleSceneController.endsItsSide(lethal: true, othersStanding: 0))
        XCTAssertFalse(BattleSceneController.endsItsSide(lethal: true, othersStanding: 1))
        XCTAssertFalse(BattleSceneController.endsItsSide(lethal: false, othersStanding: 0))
    }

    func testAnEarlierCritOrKillLeavesTheImpactFrameToAFinalBlowLaterInTheCast() {
        // An area ultimate on a wave of three: its first kill leaves two
        // standing, both of whom die later in the cast — the third kill ends
        // the side and takes the cast's one impact frame.
        XCTAssertTrue(BattleSceneController.finalBlowFollows(standingAfter: 2, killedLater: 2))
        // A crit on the last enemy of a three-hit skill whose last hit kills.
        XCTAssertTrue(BattleSceneController.finalBlowFollows(standingAfter: 1, killedLater: 1))
        // A kill that leaves someone standing through the cast punches now.
        XCTAssertFalse(BattleSceneController.finalBlowFollows(standingAfter: 2, killedLater: 1))
        XCTAssertFalse(BattleSceneController.finalBlowFollows(standingAfter: 1, killedLater: 0))
        XCTAssertFalse(BattleSceneController.finalBlowFollows(standingAfter: 0, killedLater: 0),
                       "the final blow itself is `endsItsSide`, not a blow still to come")
    }

    func testTheSlowMotionDipsToThreeTenthsAndComesBackToThePlayersSpeed() {
        let before: Double = BattleSceneController.slowMotionShare(at: -0.1, speed: 1)
        let heldAt: TimeInterval = BattleSceneController.slowIn + BattleSceneController.slowHold / 2
        let held: Double = BattleSceneController.slowMotionShare(at: heldAt, speed: 1)
        let span: TimeInterval = BattleSceneController.slowMotionSpan(speed: 1)
        let after: Double = BattleSceneController.slowMotionShare(at: span + 0.01, speed: 1)
        let spanExpected: TimeInterval = 0.06 + 0.6 + 0.25
        XCTAssertEqual(before, 1, accuracy: tolerance, "nothing slows during the freeze")
        XCTAssertEqual(held, 0.3, accuracy: tolerance)
        XCTAssertEqual(after, 1, accuracy: tolerance)
        XCTAssertEqual(span, spanExpected, accuracy: tolerance, "0.6 s held at 0.3, with a short way in and out")
        var last: Double = 0.3
        var step: TimeInterval = heldAt
        while step < span {
            let share: Double = BattleSceneController.slowMotionShare(at: step, speed: 1)
            let floor: Double = last - tolerance
            XCTAssertGreaterThanOrEqual(share, floor, "time only speeds up on the way back")
            last = share
            step += 0.01
        }
    }

    func testTheSlowMotionIsShorterAtTripleSpeed() {
        let single: TimeInterval = BattleSceneController.slowMotionSpan(speed: 1)
        let triple: TimeInterval = BattleSceneController.slowMotionSpan(speed: 3)
        let expected: TimeInterval = single / 3
        XCTAssertEqual(triple, expected, accuracy: tolerance)
        let heldAt: TimeInterval = (BattleSceneController.slowIn + BattleSceneController.slowHold / 2) / 3
        let held: Double = BattleSceneController.slowMotionShare(at: heldAt, speed: 3)
        XCTAssertEqual(held, 0.3, accuracy: tolerance, "as deep at ×3, for a third as long")
    }
}
