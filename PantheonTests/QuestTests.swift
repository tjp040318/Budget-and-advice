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

    // MARK: - Claim All (Docs/FEEL.md W2.12)

    /// Every one of the day's eight missions done.
    private func recordAFullDay(_ player: inout Player) {
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
    }

    /// CLAIM ALL is the existing claims in the list's order: it pays exactly
    /// what claiming the eight one at a time and then the Daily Tribute they
    /// open pays — the same save, the same grants in the same order — and a
    /// second press finds nothing.
    func testClaimAllPaysWhatClaimingOneByOnePays() throws {
        var player = account()
        recordAFullDay(&player)
        var byOne: Player = player
        var byAll: Player = player
        var rngOne = SeededRandom(seed: 11)
        var rngAll = SeededRandom(seed: 11)
        var paidOne: [ShopService.Grant] = []
        for mission in QuestService.missions {
            paidOne += try QuestService.claimMission(mission.id, player: &byOne, rng: &rngOne, now: noon)
        }
        paidOne += try QuestService.claimMission(QuestService.allMissionsID, player: &byOne, rng: &rngOne, now: noon)
        let paidAll: [ShopService.Grant] = QuestService.claimAllMissions(player: &byAll, rng: &rngAll, now: noon)
        let tributeTaken: Bool = QuestService.isMissionClaimed(QuestService.allMissionsID, player: byAll)
        XCTAssertEqual(paidAll, paidOne)
        XCTAssertEqual(byAll.wallet, byOne.wallet)
        XCTAssertEqual(byAll.quests, byOne.quests)
        XCTAssertEqual(byAll, byOne)
        XCTAssertTrue(tributeTaken, "the tribute the eighth claim opened is taken in the same press")
        let again: [ShopService.Grant] = QuestService.claimAllMissions(player: &byAll, rng: &rngAll, now: noon)
        XCTAssertTrue(again.isEmpty)
    }

    /// Two missions done: CLAIM ALL takes those two and nothing else, and
    /// the tribute waits for the other six.
    func testClaimAllTakesOnlyWhatIsReady() {
        var player = account()
        QuestService.record(.summoned(count: 1, bestStars: 3), player: &player, now: noon)
        QuestService.record(.unitPoweredUp, player: &player, now: noon)
        var rng = SeededRandom(seed: 12)
        let paid: [ShopService.Grant] = QuestService.claimAllMissions(player: &player, rng: &rng, now: noon)
        let claimed: Set<String> = player.quests?.claimed ?? []
        let expected: Set<String> = ["summon", "power_up"]
        XCTAssertEqual(claimed, expected)
        XCTAssertEqual(paid.count, 2)
        XCTAssertFalse(QuestService.allMissionsClaimable(player))
    }

    /// The Feats' CLAIM ALL pays what claiming each finished feat in the
    /// table's order pays.
    func testClaimAllFeatsPaysWhatClaimingOneByOnePays() throws {
        var player = account()
        QuestService.record(.summoned(count: 1, bestStars: 5), player: &player, now: noon)
        let chapter = StageDatabase.chapters[0]
        player.campaignProgress[chapter.id] = chapter.stages.count
        let ready: [String] = QuestService.feats
            .filter { QuestService.isFeatComplete($0, player: player) && !QuestService.isFeatClaimed($0.id, player: player) }
            .map(\.id)
        XCTAssertGreaterThanOrEqual(ready.count, 2)
        var byOne: Player = player
        var byAll: Player = player
        var rngOne = SeededRandom(seed: 13)
        var rngAll = SeededRandom(seed: 13)
        var paidOne: [ShopService.Grant] = []
        for id in ready {
            paidOne += try QuestService.claimFeat(id, player: &byOne, rng: &rngOne)
        }
        let paidAll: [ShopService.Grant] = QuestService.claimAllFeats(player: &byAll, rng: &rngAll)
        XCTAssertEqual(paidAll, paidOne)
        XCTAssertEqual(byAll.wallet, byOne.wallet)
        XCTAssertEqual(byAll.featsClaimed, byOne.featsClaimed)
    }

    /// The Counsel's CLAIM ALL pays what claiming each finished step of the
    /// current tier in Athena's order pays, and leaves the tier's prize for
    /// the steps still open.
    func testClaimAllCounselPaysWhatClaimingOneByOnePays() throws {
        var player = account()
        player.campaignProgress["duat_1"] = 1
        var counters: [String: Int] = player.lifetimeCounters ?? [:]
        counters["summons"] = 1
        counters["power_ups"] = 1
        player.lifetimeCounters = counters
        let tier: CounselService.Tier = CounselService.currentTier(for: player)
        let ready: [String] = CounselService.steps(in: tier)
            .filter { CounselService.isComplete($0, player: player) && !CounselService.isClaimed($0.id, player: player) }
            .map(\.id)
        XCTAssertEqual(tier, CounselService.Tier.initiate)
        XCTAssertGreaterThanOrEqual(ready.count, 3)
        var byOne: Player = player
        var byAll: Player = player
        var rngOne = SeededRandom(seed: 14)
        var rngAll = SeededRandom(seed: 14)
        var paidOne: [ShopService.Grant] = []
        for id in ready {
            paidOne += try CounselService.claim(id, player: &byOne, rng: &rngOne)
        }
        let paidAll: [ShopService.Grant] = QuestService.claimAllCounsel(player: &byAll, rng: &rngAll)
        let prizeTaken: Bool = CounselService.isClaimed(tier.prizeID, player: byAll)
        XCTAssertEqual(paidAll, paidOne)
        XCTAssertEqual(byAll.wallet, byOne.wallet)
        XCTAssertEqual(byAll.counselClaimed, byOne.counselClaimed)
        XCTAssertFalse(prizeTaken, "the prize waits for every step")
    }

    /// The last steps of a tier open its prize, and the same press takes it
    /// — and stops there: the next tier's steps are rows the list has not
    /// shown yet.
    func testClaimAllCounselTakesTheTiersPrizeAndStops() {
        var player = account()
        player.campaignProgress["duat_1"] = 1
        var counters: [String: Int] = player.lifetimeCounters ?? [:]
        counters["summons"] = 1
        player.lifetimeCounters = counters
        let waiting: Set<String> = ["counsel_first_stage", "counsel_first_summon"]
        let initiate: Set<String> = Set(CounselService.steps(in: .initiate).map(\.id))
        player.counselClaimed = initiate.subtracting(waiting)
        var rng = SeededRandom(seed: 15)
        _ = QuestService.claimAllCounsel(player: &player, rng: &rng)
        let claimed: Set<String> = player.counselClaimed ?? []
        let stepsTaken: Bool = claimed.isSuperset(of: waiting)
        let prizeTaken: Bool = claimed.contains(CounselService.Tier.initiate.prizeID)
        let adeptTaken: Int = CounselService.steps(in: .adept).filter { claimed.contains($0.id) }.count
        XCTAssertTrue(stepsTaken)
        XCTAssertTrue(prizeTaken, "the last steps open the tier's prize, and the same press takes it")
        XCTAssertEqual(adeptTaken, 0, "the next tier's steps wait for the next press")
    }
}
