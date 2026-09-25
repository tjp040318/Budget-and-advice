import XCTest
@testable import Pantheon

/// Every hit of a cast on its own contact (Docs/PLAN.md *Skills that look
/// like themselves*, 2026-09-25): the queue read ahead to the cast's own
/// hits (`CastReading`), the hold each of the cast's events is given so
/// each hit lands where its clip strikes (`CastTimeline`), the finisher of a
/// flurry landing heavy (`BattleSceneController.landsHeavy`), an
/// ultimate's signature kept to its element (`SkillFX.signature`) and the
/// sounds a cast asks for all shipping (`SkillSound`). Every
/// one is pure, so the arithmetic is pinned here on hand-built events, and
/// every expected number is a typed let (CLAUDE.md: no arithmetic inside an
/// assert's parentheses).
final class CastTimelineTests: XCTestCase {

    private let tolerance: Double = 1e-9
    private let caster = UUID()
    private let victim = UUID()

    // MARK: - Events, by hand

    private func castEvent(targets: [UUID]? = nil) -> BattleEvent {
        .skillCast(actor: caster, skillID: "test_strike", skillName: "Test Strike", targets: targets ?? [victim],
                   shot: .standard, animation: .attackBasic, vfx: "impact_generic")
    }

    private func strike(_ index: Int, of count: Int, on target: UUID? = nil, remaining: Double = 500,
                        critical: Bool = false) -> BattleEvent {
        .damage(source: caster, target: target ?? victim, amount: 100, isCritical: critical, isGlancing: false,
                matchup: .neutral, remainingHealth: remaining, hitIndex: index, hitCount: count)
    }

    private func burning(_ target: UUID? = nil) -> BattleEvent {
        .statusApplied(source: caster, target: target ?? victim, kind: .burn, turns: 2)
    }

    // MARK: - Planning

    func testEachHitLandsTheLeapPlusItsShareOfTheContract() {
        let timeline = CastTimeline.planned(walkUp: 0.3, contract: 2.0, fractions: [0.2, 0.4, 0.6], heavy: false)
        let expected: [TimeInterval] = [0.7, 1.1, 1.5]
        let recovery: TimeInterval = 0.8
        XCTAssertEqual(timeline.times.count, expected.count)
        for (index, time) in timeline.times.enumerated() {
            XCTAssertEqual(time, expected[index], accuracy: tolerance, "hit \(index)")
        }
        XCTAssertEqual(timeline.recovery, recovery, accuracy: tolerance, "the clip after its last contact")
        let past: TimeInterval = timeline.time(ofHit: 7)
        XCTAssertEqual(past, expected[2], accuracy: tolerance, "a hit past the clip's lands on its last contact")
    }

    // MARK: - The holds

    func testThreeHitsOnOneVictimLandOnTheirThreeContacts() throws {
        let timeline = CastTimeline(times: [0.6, 0.9, 1.2], recovery: 0.5)
        let events: [BattleEvent] = [castEvent(), strike(0, of: 3), strike(1, of: 3), strike(2, of: 3)]
        let toFirst: TimeInterval = try XCTUnwrap(timeline.hold(after: 0, in: events, elapsed: 0))
        let toSecond: TimeInterval = try XCTUnwrap(timeline.hold(after: 1, in: events, elapsed: 0.6))
        let toThird: TimeInterval = try XCTUnwrap(timeline.hold(after: 2, in: events, elapsed: 0.9))
        let afterLast: TimeInterval = try XCTUnwrap(timeline.hold(after: 3, in: events, elapsed: 1.2))
        let gap: TimeInterval = 0.3
        let ownHold: TimeInterval = events[3].presentationDuration
        XCTAssertEqual(toFirst, 0.6, accuracy: tolerance, "the cast holds to the first contact")
        XCTAssertEqual(toSecond, gap, accuracy: tolerance)
        XCTAssertEqual(toThird, gap, accuracy: tolerance)
        XCTAssertEqual(afterLast, ownHold, accuracy: tolerance, "an ordinary last hit keeps its own hold")
    }

    func testAHeavyFinisherKeepsTheHeavyDwell() throws {
        let timeline = CastTimeline(times: [0.6, 0.9, 1.2], recovery: 0.5, heavy: true)
        let events: [BattleEvent] = [castEvent(), strike(0, of: 3), strike(1, of: 3), strike(2, of: 3)]
        let middle: TimeInterval = try XCTUnwrap(timeline.hold(after: 1, in: events, elapsed: 0.6))
        let afterLast: TimeInterval = try XCTUnwrap(timeline.hold(after: 3, in: events, elapsed: 1.2))
        let gap: TimeInterval = 0.3
        XCTAssertEqual(middle, gap, accuracy: tolerance, "only the last hit dwells")
        XCTAssertEqual(afterLast, CastTimeline.heavyDwell, accuracy: tolerance)
    }

    func testOneHitOnFourRunsDownTheLineFortyMillisecondsApart() throws {
        let line = [UUID(), UUID(), UUID(), UUID()]
        let timeline = CastTimeline(times: [0.8], recovery: 0.6)
        let events: [BattleEvent] = [castEvent(targets: line)] + line.map { strike(0, of: 1, on: $0) }
        let toFirst: TimeInterval = try XCTUnwrap(timeline.hold(after: 0, in: events, elapsed: 0))
        XCTAssertEqual(toFirst, 0.8, accuracy: tolerance)
        for index in 1...3 {
            let elapsed: TimeInterval = 0.8 + CastTimeline.victimStep * TimeInterval(index - 1)
            let step: TimeInterval = try XCTUnwrap(timeline.hold(after: index, in: events, elapsed: elapsed))
            XCTAssertEqual(step, CastTimeline.victimStep, accuracy: tolerance, "victim \(index) to the next")
        }
        let afterLast: TimeInterval = try XCTUnwrap(timeline.hold(after: 4, in: events, elapsed: 0.92))
        let ownHold: TimeInterval = events[4].presentationDuration
        XCTAssertEqual(afterLast, ownHold, accuracy: tolerance)
    }

    func testPerHitStatusesShareTheGapBetweenTwoHits() throws {
        let timeline = CastTimeline(times: [0.5, 0.8, 1.1], recovery: 0.4)
        let events: [BattleEvent] = [
            castEvent(),
            strike(0, of: 3), burning(),
            strike(1, of: 3), burning(),
            strike(2, of: 3), burning(),
        ]
        let due = timeline.dues(in: events)
        let expected: [TimeInterval?] = [0, 0.5, 0.65, 0.8, 0.95, 1.1, nil]
        XCTAssertEqual(due.count, expected.count)
        for (index, wanted) in expected.enumerated() {
            if let wanted {
                let found: TimeInterval = try XCTUnwrap(due[index], "event \(index)")
                XCTAssertEqual(found, wanted, accuracy: tolerance, "event \(index)")
            } else {
                XCTAssertNil(due[index], "event \(index) comes after the last hit and keeps its own hold")
            }
        }
        let half: TimeInterval = 0.15
        let afterHit: TimeInterval = try XCTUnwrap(timeline.hold(after: 1, in: events, elapsed: 0.5))
        let afterStatus: TimeInterval = try XCTUnwrap(timeline.hold(after: 2, in: events, elapsed: 0.65))
        XCTAssertEqual(afterHit, half, accuracy: tolerance)
        XCTAssertEqual(afterStatus, half, accuracy: tolerance)
        XCTAssertNil(timeline.hold(after: 6, in: events, elapsed: 1.4), "the last hit's status keeps its own hold")
    }

    func testALethalLastHitKeepsTheKillingDwell() throws {
        let timeline = CastTimeline(times: [0.5, 0.8, 1.1], recovery: 0.4)
        let events: [BattleEvent] = [
            castEvent(), strike(0, of: 3), strike(1, of: 3), strike(2, of: 3, remaining: 0), .defeated(target: victim),
        ]
        let afterKill: TimeInterval = try XCTUnwrap(timeline.hold(after: 3, in: events, elapsed: 1.1))
        XCTAssertEqual(afterKill, CastTimeline.lethalDwell, accuracy: tolerance)
        XCTAssertNil(timeline.hold(after: 4, in: events, elapsed: 1.65), "the fall keeps its own hold")
    }

    func testTheLineDwellsForItsHardestBlow() throws {
        // A crit on the first of two victims, an ordinary blow on the last:
        // the line's dwell is the crit's.
        let pair = [UUID(), UUID()]
        let timeline = CastTimeline(times: [0.7], recovery: 0.5)
        let events: [BattleEvent] = [
            castEvent(targets: pair), strike(0, of: 1, on: pair[0], critical: true), strike(0, of: 1, on: pair[1]),
        ]
        let afterLine: TimeInterval = try XCTUnwrap(timeline.hold(after: 2, in: events, elapsed: 0.74))
        XCTAssertEqual(afterLine, CastTimeline.criticalDwell, accuracy: tolerance)
    }

    func testALateHoldIsMadeUpByTheNext() throws {
        let timeline = CastTimeline(times: [0.6, 0.9, 1.2], recovery: 0.5)
        let events: [BattleEvent] = [castEvent(), strike(0, of: 3), strike(1, of: 3), strike(2, of: 3)]
        // The second hit was presented 0.1 s late: the third still lands on
        // its contact, and a hold already overdue is the shortest step.
        let caughtUp: TimeInterval = try XCTUnwrap(timeline.hold(after: 2, in: events, elapsed: 1.0))
        let overdue: TimeInterval = try XCTUnwrap(timeline.hold(after: 2, in: events, elapsed: 1.5))
        let remaining: TimeInterval = 0.2
        XCTAssertEqual(caughtUp, remaining, accuracy: tolerance)
        XCTAssertEqual(overdue, CastTimeline.shortestStep, accuracy: tolerance)
    }

    func testWhatLandsBeforeTheFirstHitIsPressedAgainstIt() throws {
        // A shield soaks the first hit before its damage is told: the soak is
        // shown on the blow, not half way through the wind-up.
        let timeline = CastTimeline(times: [0.6], recovery: 0.6)
        let events: [BattleEvent] = [
            castEvent(), .shieldAbsorbed(target: victim, amount: 50, shieldRemaining: 0), strike(0, of: 1),
        ]
        let castHold: TimeInterval = try XCTUnwrap(timeline.hold(after: 0, in: events, elapsed: 0))
        let soakHold: TimeInterval = try XCTUnwrap(timeline.hold(after: 1, in: events, elapsed: 0.58))
        let pressed: TimeInterval = 0.6 - CastTimeline.leadStep
        XCTAssertEqual(castHold, pressed, accuracy: tolerance)
        XCTAssertEqual(soakHold, CastTimeline.leadStep, accuracy: tolerance)
    }

    func testARiteHoldsToItsRelease() throws {
        let ally = UUID()
        let timeline = CastTimeline(times: [0.9], recovery: 0.8)
        let events: [BattleEvent] = [
            castEvent(targets: [ally]), .healed(source: caster, target: ally, amount: 120, remainingHealth: 900),
        ]
        let castHold: TimeInterval = try XCTUnwrap(timeline.hold(after: 0, in: events, elapsed: 0))
        XCTAssertEqual(castHold, 0.9, accuracy: tolerance, "the heal lands on the release")
        XCTAssertNil(timeline.hold(after: 1, in: events, elapsed: 0.9), "the heal keeps its own hold")
    }

    func testASliceThatDoesNotOpenOnACastIsNotTimed() {
        let timeline = CastTimeline(times: [0.6], recovery: 0.6)
        let events: [BattleEvent] = [strike(0, of: 1), strike(0, of: 1)]
        XCTAssertNil(timeline.hold(after: 0, in: events, elapsed: 0))
    }

    // MARK: - Reading ahead

    func testTheReadAheadGroupsTheHitsAndStopsAtACounter() {
        let queue: [BattleEvent] = [
            strike(0, of: 3), burning(),
            strike(1, of: 3),
            .counterattack(actor: victim, target: caster),
            .skillCast(actor: victim, skillID: "counter", skillName: "Counter", targets: [caster], shot: .standard,
                       animation: .attackBasic, vfx: "impact_generic"),
            strike(2, of: 3),
        ]
        let reading = CastReading.ahead(in: queue, caster: caster)
        let eventsRead: Int = reading.events.count
        let hitsRead: Int = reading.hits.count
        XCTAssertEqual(eventsRead, 3, "up to the counter, which is a beat of its own")
        XCTAssertEqual(hitsRead, 2)
        XCTAssertEqual(reading.hitCount, 3, "the skill strikes three times whatever the counter cut off")
        XCTAssertEqual(reading.hits.first?.hit, 0)
        XCTAssertEqual(reading.hits.last?.hit, 1)
    }

    func testARandomVolleyReadsItsVictimsOffItsHits() throws {
        let other = UUID()
        let queue: [BattleEvent] = [
            strike(0, of: 2, on: victim), strike(0, of: 2, on: other),
            strike(1, of: 2, on: other), strike(1, of: 2, on: other),
            .turnBegan(actor: other, turnNumber: 4),
            strike(0, of: 1),
        ]
        let reading = CastReading.ahead(in: queue, caster: caster)
        XCTAssertEqual(reading.hits.count, 2)
        let first: [UUID] = try XCTUnwrap(reading.hits.first?.victims)
        let second: [UUID] = try XCTUnwrap(reading.hits.last?.victims)
        XCTAssertEqual(first, [victim, other])
        XCTAssertEqual(second, [other, other], "a victim struck twice is named twice")
    }

    func testARiteReadsNoHits() {
        let ally = UUID()
        let queue: [BattleEvent] = [
            .healed(source: caster, target: ally, amount: 90, remainingHealth: 700),
            .statusApplied(source: caster, target: ally, kind: .shield, turns: 2),
            .turnBegan(actor: ally, turnNumber: 2),
        ]
        let reading = CastReading.ahead(in: queue, caster: caster)
        XCTAssertEqual(reading.hitCount, 0)
        XCTAssertTrue(reading.hits.isEmpty)
        XCTAssertEqual(reading.events.count, 2)
    }

    // MARK: - The weight of a blow, and a signature's element

    func testAFlurrysFinisherLandsHeavyAndItsStrikesDoNot() {
        XCTAssertFalse(BattleSceneController.landsHeavy(.skillX3, hitIndex: 0, hitCount: 3))
        XCTAssertFalse(BattleSceneController.landsHeavy(.skillX3, hitIndex: 1, hitCount: 3))
        XCTAssertTrue(BattleSceneController.landsHeavy(.skillX3, hitIndex: 2, hitCount: 3), "the finisher")
        XCTAssertTrue(BattleSceneController.landsHeavy(.skillArea, hitIndex: 0, hitCount: 1))
        XCTAssertTrue(BattleSceneController.landsHeavy(.ultimate, hitIndex: 0, hitCount: 3))
        XCTAssertFalse(BattleSceneController.landsHeavy(.attackBasic, hitIndex: 1, hitCount: 2), "a duelist's second cut")
    }

    func testASignatureWithAnElementIsPlayedOnlyByThatElement() {
        XCTAssertEqual(SkillFX.signature(for: "surtr", element: .ember), .meteor)
        XCTAssertEqual(SkillFX.signature(for: "surtr", element: .tide), .eruption, "a tide Surtr is never a fire meteor")
        XCTAssertEqual(SkillFX.signature(for: "zeus", element: .tide), .lightning, "a neutral look is every form's")
        XCTAssertEqual(SkillFX.signature(for: "nobody_at_all", element: .gale), .eruption)
    }

    // MARK: - The sounds a cast asks for

    /// Every sound `SkillFX` asks for by what it is (`SkillSound`) ships as
    /// its own file, and so does the sound it falls back to when a build has
    /// none, which is never played louder than the cast asked. A missing
    /// file is silent rather than a crash (`AudioLibrary`), so without this
    /// a cast that lost its sound would pass every other check.
    func testEverySkillSoundShipsAndSoDoesItsFallback() {
        var sounds: [SkillSound] = [.swing(heavy: false), .swing(heavy: true), .charge, .loose, .arrowHit, .rite]
        for element in Element.allCases {
            sounds += [.hit(element), .cast(element), .boom(element)]
        }
        for sound in sounds {
            for file in [sound.file, sound.fallback] {
                let url: URL? = Bundle.main.url(forResource: file.rawValue, withExtension: "wav", subdirectory: "Audio")
                    ?? Bundle.main.url(forResource: file.rawValue, withExtension: "wav")
                XCTAssertNotNil(url, "\(file.rawValue).wav: python3 tools/sfx.py elements skills")
            }
            let gain: Float = sound.fallbackGain
            XCTAssertGreaterThan(gain, 0, "\(sound)")
            XCTAssertLessThanOrEqual(gain, 1, "\(sound): a fallback is never louder than the cast asked")
        }
    }
}
