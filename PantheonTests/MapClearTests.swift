import XCTest
@testable import Pantheon

/// The chapter map plays the clear (Docs/FEEL.md W2.5): what one settled
/// run changed on its road (`StageClear.between`) — nothing for a repeat, a
/// loss or a floor off the road; the stage, its stars, its chests, and on a
/// road's first end the tier and the chapter it opened — and the beat's
/// order as times (`MapClearTimeline`), with the CI's holds read both ways.
/// Every figure an assert compares is hoisted into a typed `let` first
/// (CLAUDE.md).
final class MapClearTests: XCTestCase {

    private func account() -> Player {
        NewGame.create().player
    }

    /// The Duat's first road, which every account walks first.
    private var road: Chapter { StageDatabase.chapters[0] }

    /// Every stage of the road up to `cleared` at `stars`.
    private func walked(_ player: Player, to cleared: Int, stars: Int, on chapter: Chapter) -> Player {
        var copy = player
        copy.campaignProgress[chapter.id] = cleared
        var rating: [String: Int] = copy.stageStars ?? [:]
        for stage in chapter.stages.prefix(cleared) { rating[stage.id] = stars }
        copy.stageStars = rating
        return copy
    }

    // MARK: - What a run changed

    /// A first clear turns the medallion gold with the stars it earned, and
    /// the first stage opens nothing but the second.
    func testAFirstClearIsABeat() throws {
        let before: Player = account()
        let stage: Stage = road.stages[0]
        var after: Player = before
        after.campaignProgress[road.id] = 1
        after.stageStars = [stage.id: 2]
        let clear: StageClear = try XCTUnwrap(StageClear.between(before: before, after: after, stage: stage, serial: 7))
        XCTAssertEqual(clear.serial, 7)
        XCTAssertEqual(clear.stageID, stage.id)
        XCTAssertEqual(clear.chapterID, road.id)
        XCTAssertEqual(clear.stageIndex, 0)
        XCTAssertTrue(clear.firstClear)
        XCTAssertEqual(clear.starsBefore, 0)
        XCTAssertEqual(clear.starsAfter, 2)
        XCTAssertTrue(clear.chestsEarned.isEmpty)
        XCTAssertFalse(clear.conquered)
        XCTAssertNil(clear.tierOpened)
        XCTAssertNil(clear.chapterOpened)
        XCTAssertTrue(clear.hasBeat)
    }

    /// The third stage's first clear earns the road's chest.
    func testTheThirdStageEarnsTheRoadsChest() throws {
        let before: Player = walked(account(), to: 2, stars: 3, on: road)
        let stage: Stage = road.stages[2]
        var after: Player = before
        after.campaignProgress[road.id] = 3
        after.stageStars?[stage.id] = 1
        let clear: StageClear = try XCTUnwrap(StageClear.between(before: before, after: after, stage: stage, serial: 1))
        XCTAssertEqual(clear.stageIndex, 2)
        XCTAssertEqual(clear.chestsEarned, [TributeMilestone.third])
        XCTAssertFalse(clear.conquered)
    }

    /// The boss's first fall on Normal conquers the road, earns the gate's
    /// chest, opens Hard on this chapter and the next chapter's city.
    func testTheBossesFirstFallConquersTheRoad() throws {
        let last: Int = road.stages.count - 1
        let before: Player = walked(account(), to: last, stars: 1, on: road)
        let boss: Stage = road.stages[last]
        var after: Player = before
        after.campaignProgress[road.id] = road.stages.count
        after.stageStars?[boss.id] = 3
        let clear: StageClear = try XCTUnwrap(StageClear.between(before: before, after: after, stage: boss, serial: 2))
        let nextChapter: String = StageDatabase.chapters[1].id
        XCTAssertTrue(clear.conquered)
        XCTAssertEqual(clear.chestsEarned, [TributeMilestone.boss])
        XCTAssertEqual(clear.tierOpened, CampaignDifficulty.hard)
        XCTAssertEqual(clear.chapterOpened, nextChapter)
    }

    /// Hard's boss opens Hell on the chapter, and no city: the road beyond
    /// was opened on Normal.
    func testHardsEndOpensHellAndNoCity() throws {
        let hard: Chapter = road.at(.hard)
        let last: Int = hard.stages.count - 1
        let normalDone: Player = walked(account(), to: road.stages.count, stars: 3, on: road)
        let before: Player = walked(normalDone, to: last, stars: 2, on: hard)
        let boss: Stage = hard.stages[last]
        var after: Player = before
        after.campaignProgress[hard.id] = hard.stages.count
        after.stageStars?[boss.id] = 2
        let clear: StageClear = try XCTUnwrap(StageClear.between(before: before, after: after, stage: boss, serial: 3))
        XCTAssertEqual(clear.chapterID, hard.id)
        XCTAssertTrue(clear.conquered)
        XCTAssertEqual(clear.tierOpened, CampaignDifficulty.hell)
        XCTAssertNil(clear.chapterOpened)
    }

    /// A repeat that changed nothing plays nothing — the map never replays a
    /// clear it has shown.
    func testARepeatIsNoBeat() {
        let before: Player = walked(account(), to: road.stages.count, stars: 3, on: road)
        let stage: Stage = road.stages[1]
        let clear: StageClear? = StageClear.between(before: before, after: before, stage: stage, serial: 4)
        XCTAssertNil(clear)
    }

    /// A repeat that bettered its stars stamps them and turns nothing.
    func testNewStarsOnARepeatStampOnly() throws {
        let before: Player = walked(account(), to: road.stages.count, stars: 1, on: road)
        let stage: Stage = road.stages[1]
        var after: Player = before
        after.stageStars?[stage.id] = 3
        let clear: StageClear = try XCTUnwrap(StageClear.between(before: before, after: after, stage: stage, serial: 5))
        XCTAssertFalse(clear.firstClear)
        XCTAssertEqual(clear.starsBefore, 1)
        XCTAssertEqual(clear.starsAfter, 3)
        XCTAssertFalse(clear.conquered)
        XCTAssertTrue(clear.chestsEarned.isEmpty)
    }

    /// A floor of the Labyrinth is not on any road.
    func testAFloorOffTheRoadIsNoBeat() throws {
        let floor: Stage = try XCTUnwrap(StageDatabase.stage("lab_colossus_1"))
        let before: Player = account()
        var after: Player = before
        after.campaignProgress[floor.chapterID] = 1
        let clear: StageClear? = StageClear.between(before: before, after: after, stage: floor, serial: 6)
        XCTAssertNil(clear)
    }

    /// An auto-repeat that cleared a stage and then bettered its stars plays
    /// once: the first run's before, the last run's after, both chests.
    func testAnAutoRepeatPlaysOnce() {
        let first = StageClear(serial: 1, stageID: "duat_1_3", chapterID: "duat_1", stageIndex: 2,
                               firstClear: true, starsBefore: 0, starsAfter: 1, chestsEarned: [.third],
                               conquered: false, tierOpened: nil, chapterOpened: nil)
        let better = StageClear(serial: 2, stageID: "duat_1_3", chapterID: "duat_1", stageIndex: 2,
                                firstClear: false, starsBefore: 1, starsAfter: 3, chestsEarned: [.flawless],
                                conquered: false, tierOpened: nil, chapterOpened: nil)
        let merged: StageClear = first.merged(with: better)
        let chests: [TributeMilestone] = [.third, .flawless]
        XCTAssertEqual(merged.serial, 2)
        XCTAssertTrue(merged.firstClear)
        XCTAssertEqual(merged.starsBefore, 0)
        XCTAssertEqual(merged.starsAfter, 3)
        XCTAssertEqual(merged.chestsEarned, chests)
    }

    // MARK: - The beat's order

    /// The genre's order: the medallion turns, then its stars stamp, then
    /// the leader walks on and the next lock breaks, then the chest jumps;
    /// at the end every part stands finished.
    func testTheBeatPlaysInOrder() throws {
        let clear = StageClear(serial: 1, stageID: road.stages[2].id, chapterID: road.id, stageIndex: 2,
                               firstClear: true, starsBefore: 0, starsAfter: 2, chestsEarned: [.third],
                               conquered: false, tierOpened: nil, chapterOpened: nil)
        let timeline = MapClearTimeline(clear: clear, hasNext: true)
        let turned: TimeInterval = timeline.flipStart + timeline.flipLength
        let firstStar: TimeInterval = try XCTUnwrap(timeline.starStarts.first)
        let lastStar: TimeInterval = try XCTUnwrap(timeline.starStarts.last)
        let walk: TimeInterval = try XCTUnwrap(timeline.hopStart)
        let lock: TimeInterval = try XCTUnwrap(timeline.unlockStart)
        let chest: TimeInterval = try XCTUnwrap(timeline.chestStarts[.third])
        XCTAssertEqual(timeline.starStarts.count, 2)
        XCTAssertGreaterThanOrEqual(firstStar, turned)
        XCTAssertGreaterThan(walk, lastStar)
        XCTAssertGreaterThan(lock, walk)
        XCTAssertGreaterThan(chest, lock)
        XCTAssertGreaterThan(timeline.end, chest)
        XCTAssertNil(timeline.ribbonStart)

        let opening: MapClearFrame = timeline.frame(at: 0)
        let closing: MapClearFrame = timeline.frame(at: timeline.end)
        let stamped: [Double] = [1, 1]
        let jumped: Double = closing.chests[.third] ?? 0
        XCTAssertEqual(opening.flip, 0, accuracy: 1e-9)
        XCTAssertFalse(opening.finished)
        XCTAssertEqual(closing.flip, 1, accuracy: 1e-9)
        XCTAssertEqual(closing.stamps, stamped)
        XCTAssertEqual(closing.hop, 1, accuracy: 1e-9)
        XCTAssertEqual(closing.shards, 1, accuracy: 1e-9)
        XCTAssertEqual(jumped, 1, accuracy: 1e-9)
        XCTAssertTrue(closing.finished)
    }

    /// A road's end: no walk (nothing beyond it on the road), and the
    /// ribbon crosses the map after the gate's chest has jumped.
    func testARoadsEndEndsOnTheRibbon() throws {
        let last: Int = road.stages.count - 1
        let clear = StageClear(serial: 1, stageID: road.stages[last].id, chapterID: road.id, stageIndex: last,
                               firstClear: true, starsBefore: 0, starsAfter: 3, chestsEarned: [.boss],
                               conquered: true, tierOpened: .hard, chapterOpened: StageDatabase.chapters[1].id)
        let timeline = MapClearTimeline(clear: clear, hasNext: false)
        let chest: TimeInterval = try XCTUnwrap(timeline.chestStarts[.boss])
        let ribbon: TimeInterval = try XCTUnwrap(timeline.ribbonStart)
        let ribbonEnds: TimeInterval = ribbon + MapClearTimeline.ribbon
        XCTAssertNil(timeline.hopStart)
        XCTAssertNil(timeline.unlockStart)
        XCTAssertGreaterThan(ribbon, chest)
        XCTAssertGreaterThanOrEqual(timeline.end, ribbonEnds)
        let closing: MapClearFrame = timeline.frame(at: timeline.end)
        let ran: Double = closing.ribbon ?? 0
        XCTAssertEqual(ran, 1, accuracy: 1e-9)
    }

    /// New stars on a repeat: the medallion is gold already and nobody
    /// walks; only the stars stamp.
    func testNewStarsTurnNothing() {
        let clear = StageClear(serial: 1, stageID: road.stages[1].id, chapterID: road.id, stageIndex: 1,
                               firstClear: false, starsBefore: 1, starsAfter: 3, chestsEarned: [],
                               conquered: false, tierOpened: nil, chapterOpened: nil)
        let timeline = MapClearTimeline(clear: clear, hasNext: true)
        let opening: MapClearFrame = timeline.frame(at: 0)
        XCTAssertEqual(opening.flip, 1, accuracy: 1e-9, "already gold")
        XCTAssertEqual(timeline.starStarts.count, 2)
        XCTAssertNil(timeline.hopStart)
        XCTAssertNil(timeline.unlockStart)
        XCTAssertNil(timeline.ribbonStart)
    }

    // MARK: - The CI's holds

    /// A hold stands the beat still for its seconds at its beat time; the
    /// wall time of a beat time counts every hold that began before it, so
    /// the two readings are each other's inverse.
    func testAHoldStandsTheBeatStill() {
        let flip = MapClearHold(at: 0.36, seconds: 8, cue: "map-flip")
        let ribbon = MapClearHold(at: 3.0, seconds: 10, cue: "map-conquered")
        let holds: [MapClearHold] = [flip, ribbon]
        let early: TimeInterval = MapClearTimeline.beatTime(elapsed: 0.2, holds: holds)
        let held: TimeInterval = MapClearTimeline.beatTime(elapsed: 5, holds: holds)
        let resumed: TimeInterval = MapClearTimeline.beatTime(elapsed: 9.36, holds: holds)
        XCTAssertEqual(early, 0.2, accuracy: 1e-9)
        XCTAssertEqual(held, 0.36, accuracy: 1e-9)
        XCTAssertEqual(resumed, 1.36, accuracy: 1e-9)
        let beats: [TimeInterval] = [0.2, 0.36, 1.0, 3.0, 4.0]
        for beat in beats {
            let wall: TimeInterval = MapClearTimeline.wallTime(atBeat: beat, holds: holds)
            let back: TimeInterval = MapClearTimeline.beatTime(elapsed: wall, holds: holds)
            XCTAssertEqual(back, beat, accuracy: 1e-9, "beat \(beat)")
        }
        let holdBegins: TimeInterval = MapClearTimeline.wallTime(atBeat: 3.0, holds: holds)
        XCTAssertEqual(holdBegins, 11.0, accuracy: 1e-9, "the ribbon's hold begins after the flip's eight seconds")
    }
}
