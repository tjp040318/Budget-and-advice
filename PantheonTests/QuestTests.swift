import XCTest
@testable import Pantheon

/// Missions count what the day did, pay once, and start over at midnight;
/// feats pay once ever; the login gift walks its seven days.
final class QuestTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    private func account() -> Player {
        var player = NewGame.create().player
        player.wallet.divinity = 0
        return player
    }

    func testMissionCountsClaimsOnceAndResetsNextDay() throws {
        var player = account()
        var rng = SeededRandom(seed: 1)
        let stage = StageDatabase.chapters[0].stages[0]
        for _ in 0..<3 { QuestService.record(.stageCleared(stage), player: &player, now: noon) }
        let mission = QuestService.missions.first(where: { $0.id == "clear_stages" })!
        XCTAssertTrue(QuestService.isMissionComplete(mission, player: player))

        let before = player.wallet.count(of: .unknown)
        try QuestService.claimMission(mission.id, player: &player, rng: &rng, now: noon)
        XCTAssertEqual(player.wallet.count(of: .unknown), before + 2)
        XCTAssertThrowsError(try QuestService.claimMission(mission.id, player: &player, rng: &rng, now: noon))

        // Tomorrow the counter is empty and the mission is open again.
        let tomorrow = noon.addingTimeInterval(86_400)
        QuestService.refreshDay(player: &player, now: tomorrow)
        XCTAssertEqual(QuestService.progress(of: mission, player: player), 0)
        XCTAssertFalse(QuestService.isMissionClaimed(mission.id, player: player))
    }

    func testAllMissionsBonusNeedsEveryClaim() throws {
        var player = account()
        var rng = SeededRandom(seed: 2)
        XCTAssertThrowsError(try QuestService.claimMission(QuestService.allMissionsID, player: &player, rng: &rng, now: noon))

        let stage = StageDatabase.chapters[0].stages[0]
        let floor = DungeonDatabase.halls[0].floors[0]
        for _ in 0..<3 { QuestService.record(.stageCleared(stage), player: &player, now: noon) }
        QuestService.record(.hallFloorCleared(floor), player: &player, now: noon)
        QuestService.record(.arenaBattle(won: true), player: &player, now: noon)
        QuestService.record(.summoned(count: 1, bestStars: 3), player: &player, now: noon)
        QuestService.record(.unitPoweredUp, player: &player, now: noon)
        QuestService.record(.relicUpgraded(level: 1), player: &player, now: noon)
        QuestService.record(.dailyOfferingClaimed, player: &player, now: noon)
        QuestService.record(.energySpent(30), player: &player, now: noon)
        for mission in QuestService.missions {
            try QuestService.claimMission(mission.id, player: &player, rng: &rng, now: noon)
        }
        XCTAssertTrue(QuestService.allMissionsClaimable(player))
        let scrolls = player.wallet.count(of: .pantheonic)
        try QuestService.claimMission(QuestService.allMissionsID, player: &player, rng: &rng, now: noon)
        XCTAssertEqual(player.wallet.count(of: .pantheonic), scrolls + 1)
        XCTAssertEqual(QuestService.claimableCount(player: player, now: noon), 1, "only the login gift is left")
    }

    func testFeatsPayOnce() throws {
        var player = account()
        var rng = SeededRandom(seed: 3)
        XCTAssertThrowsError(try QuestService.claimFeat("first_five_star", player: &player, rng: &rng))
        QuestService.record(.summoned(count: 1, bestStars: 5), player: &player, now: noon)
        try QuestService.claimFeat("first_five_star", player: &player, rng: &rng)
        XCTAssertEqual(player.wallet.divinity, 100)
        XCTAssertThrowsError(try QuestService.claimFeat("first_five_star", player: &player, rng: &rng))

        // A chapter feat reads the campaign progress directly.
        let chapter = StageDatabase.chapters[0]
        player.campaignProgress[chapter.id] = chapter.stages.count
        try QuestService.claimFeat("clear_\(chapter.id)", player: &player, rng: &rng)
        XCTAssertEqual(player.wallet.divinity, 200)
    }

    func testLoginGiftWalksTheWeekAndResetsOnAMiss() throws {
        var player = account()
        var rng = SeededRandom(seed: 4)
        QuestService.refreshDay(player: &player, now: noon)
        XCTAssertEqual(player.loginStreak?.day, 1)
        try QuestService.claimLoginGift(player: &player, rng: &rng, now: noon)
        XCTAssertThrowsError(try QuestService.claimLoginGift(player: &player, rng: &rng, now: noon))

        QuestService.refreshDay(player: &player, now: noon.addingTimeInterval(86_400))
        XCTAssertEqual(player.loginStreak?.day, 2)

        // Two days later without a visit: back to day one.
        QuestService.refreshDay(player: &player, now: noon.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(player.loginStreak?.day, 1)
    }

    func testOldSavesDecodeWithoutQuestFields() throws {
        var player = account()
        player.quests = nil
        player.loginStreak = nil
        player.lifetimeCounters = nil
        player.featsClaimed = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(player)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Player.self, from: data)
        XCTAssertNil(decoded.quests)
        XCTAssertEqual(QuestService.claimableCount(player: decoded, now: noon), 1)
    }
}
