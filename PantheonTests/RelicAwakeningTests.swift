import XCTest
@testable import Pantheon

/// Awakening is a FLAG on a 6★, not a grade above it, and these pin what
/// the flag does and what it costs: a fifth sub stat through the same
/// choice of two every roll uses, the +15 main stat at 3.6×, the aether by
/// colour, and a save that decodes without it. The value of an awakening
/// against an ordinary 6★ is measured in `tools/balance.py --awakening`.
final class RelicAwakeningTests: XCTestCase {

    /// A 6★ Legend of an ember set taken to +15: four sub stats, ready.
    private func maxedRelic(set: RelicSet = .fury, seed: UInt64 = 11) -> Relic {
        var rng = SeededRandom(seed: seed)
        var relic = RelicService.generate(grade: 6, slot: 4, set: set, quality: .legend, rng: &rng)
        for _ in 0..<15 { RelicService.upgradeOnce(&relic, rng: &rng) }
        return relic
    }

    private func player(holding relic: Relic, ember: Int = 60, tide: Int = 0, pure: Int = 15) -> Player {
        var player = Player()
        player.relics = [relic]
        Aether.add(Aether.id(for: .ember), ember, player: &player)
        Aether.add(Aether.id(for: .tide), tide, player: &player)
        Aether.add(Aether.pure, pure, player: &player)
        return player
    }

    // MARK: - Who may awaken

    func testOnlyASixStarAtFifteenAwakens() {
        let ready = maxedRelic()
        XCTAssertEqual(ready.grade, 6)
        XCTAssertTrue(ready.isMaxLevel)
        XCTAssertEqual(ready.subStats.count, 4, "a +15 always has its four")
        let held = player(holding: ready)
        XCTAssertNil(RelicService.awakeningError(ready, paying: .ember, player: held))

        var rng = SeededRandom(seed: 3)
        var fiveStar = RelicService.generate(grade: 5, slot: 4, set: .fury, quality: .legend, rng: &rng)
        for _ in 0..<15 { RelicService.upgradeOnce(&fiveStar, rng: &rng) }
        XCTAssertEqual(RelicService.awakeningError(fiveStar, paying: .ember, player: held), .notSixStar)

        var fourteen = ready
        fourteen.level = 14
        XCTAssertEqual(RelicService.awakeningError(fourteen, paying: .ember, player: held), .notMaxLevel)

        var done = ready
        done.awakened = true
        XCTAssertEqual(RelicService.awakeningError(done, paying: .ember, player: held), .alreadyAwakened)

        var waiting = ready
        waiting.pendingRoll = 9
        XCTAssertEqual(RelicService.awakeningError(waiting, paying: .ember, player: held), .choiceWaiting)

        let poor = player(holding: ready, ember: 59)
        XCTAssertEqual(
            RelicService.awakeningError(ready, paying: .ember, player: poor),
            .notEnoughAether(id: "aether_ember", needed: 60, held: 59)
        )
        let noPure = player(holding: ready, pure: 14)
        XCTAssertEqual(
            RelicService.awakeningError(ready, paying: .ember, player: noPure),
            .notEnoughAether(id: Aether.pure, needed: 15, held: 14)
        )
    }

    func testTheCostFollowsTheSetsColour() {
        let fury = maxedRelic(set: .fury)
        XCTAssertEqual(RelicSet.fury.aetherElement, .ember)
        XCTAssertEqual(RelicService.awakeningCost(for: fury, paying: .ember).elemental, RelicService.awakeningMatching)
        XCTAssertEqual(RelicService.awakeningCost(for: fury, paying: .tide).elemental, RelicService.awakeningOffColour)
        XCTAssertEqual(RelicService.awakeningCost(for: fury, paying: .tide).pure, RelicService.awakeningPure)
        XCTAssertLessThan(RelicService.awakeningMatching, RelicService.awakeningOffColour, "the set's own colour goes further")
        // Every set names a colour, so every set can be awakened.
        for set in RelicSet.allCases {
            XCTAssertTrue(Element.allCases.contains(set.aetherElement), set.rawValue)
        }
    }

    // MARK: - The awakening

    func testAwakeningSpendsTheAetherAndOpensAFifthSubStat() throws {
        let relic = maxedRelic()
        var held = player(holding: relic, ember: 70, pure: 20)
        var rng = SeededRandom(seed: 5)
        let outcome = try RelicService.awaken(relicID: relic.id, paying: .ember, player: &held, rng: &rng)
        XCTAssertEqual(outcome.spent["aether_ember"], 60)
        XCTAssertEqual(outcome.spent[Aether.pure], 15)
        XCTAssertEqual(Aether.count("aether_ember", player: held), 10)
        XCTAssertEqual(Aether.count(Aether.pure, player: held), 5)

        let awakened = try XCTUnwrap(held.relics.first)
        XCTAssertTrue(awakened.isAwakened)
        XCTAssertEqual(awakened.subStatCap, 5)
        XCTAssertTrue(awakened.hasPendingRoll, "the fifth sub stat is a choice of two, like every roll")
        XCTAssertEqual(awakened.subStats.count, 4, "nothing is added until the player chooses")

        // Both offers are NEW kinds the relic does not have, and taking one
        // makes five.
        let offers = RelicService.candidates(for: awakened)
        XCTAssertEqual(offers.count, 2)
        for offer in offers {
            XCTAssertTrue(offer.change.isNew)
            XCTAssertNil(offer.growsIndex)
            XCTAssertFalse(awakened.subStats.contains(where: { $0.kind == offer.change.kind }))
            XCTAssertNotEqual(offer.change.kind, awakened.mainStat.kind)
        }
        var chosen = awakened
        XCTAssertNotNil(RelicService.takeRoll(&chosen, candidate: 1))
        XCTAssertEqual(chosen.subStats.count, 5)
        XCTAssertFalse(chosen.hasPendingRoll)
        XCTAssertEqual(Set(chosen.subStats.map(\.kind)).count, 5, "five different kinds")

        // And it cannot be awakened twice.
        XCTAssertThrowsError(try RelicService.awaken(relicID: relic.id, paying: .ember, player: &held, rng: &rng))
    }

    func testTheMainStatPeaksAtThreePointSixOnceAwakened() {
        let relic = maxedRelic()
        let ordinary = relic.projectedMainStat(atLevel: 15).value
        XCTAssertEqual(ordinary, relic.mainStat.value * Relic.peak, accuracy: 0.0001)
        var awakened = relic
        awakened.awakened = true
        XCTAssertEqual(awakened.projectedMainStat(atLevel: 15).value, relic.mainStat.value * Relic.awakenedPeak, accuracy: 0.0001)
        XCTAssertEqual(awakened.effectiveMainStat.value, relic.mainStat.value * 3.6, accuracy: 0.0001)
        // Below +15 the road is the same road.
        XCTAssertEqual(awakened.projectedMainStat(atLevel: 14).value, relic.projectedMainStat(atLevel: 14).value, accuracy: 0.0001)
        XCTAssertEqual(awakened.projectedMainStat(atLevel: 0).value, relic.mainStat.value, accuracy: 0.0001)
    }

    func testAnAwakenedRelicKeepsFiveThroughAReappraisal() throws {
        var rng = SeededRandom(seed: 8)
        var relic = maxedRelic(seed: 8)
        relic.awakened = true
        relic.subStats.append(StatModifier(.resistance, 3))
        XCTAssertEqual(relic.subStats.count, 5)
        var wallet = Wallet()
        wallet.drachma = 1_000_000
        try RelicService.reappraise(&relic, wallet: &wallet, rng: &rng)
        XCTAssertTrue(relic.isAwakened, "a reappraisal rolls the subs, not the awakening")
        XCTAssertEqual(relic.subStats.count, 5, "a Legend's four plus the awakening's one, then four grows")
        XCTAssertEqual(Set(relic.subStats.map(\.kind)).count, 5)
    }

    func testAnAwakenedDropCarriesOneMoreSubStatThanItsQuality() {
        var rng = SeededRandom(seed: 21)
        let rare = RelicService.generate(grade: 6, quality: .rare, awakened: true, rng: &rng)
        XCTAssertTrue(rare.isAwakened)
        XCTAssertEqual(rare.subStats.count, RelicQuality.rare.subStatCount + 1)
        let legend = RelicService.generate(grade: 6, quality: .legend, awakened: true, rng: &rng)
        XCTAssertEqual(legend.subStats.count, 5, "a Legend awakened drop has all five")
        let plain = RelicService.generate(grade: 6, quality: .legend, rng: &rng)
        XCTAssertFalse(plain.isAwakened)
        XCTAssertNil(plain.awakened, "an ordinary relic writes no key")
        XCTAssertEqual(plain.subStats.count, 4)

        // Powered up, an awakened Normal reaches its five the way an
        // ordinary one reaches four: every milestone adds until the cap.
        var normal = RelicService.generate(grade: 6, quality: .normal, awakened: true, rng: &rng)
        XCTAssertEqual(normal.subStats.count, 1)
        for _ in 0..<15 { RelicService.upgradeOnce(&normal, rng: &rng) }
        XCTAssertEqual(normal.subStats.count, 5)
        XCTAssertEqual(Set(normal.subStats.map(\.kind)).count, 5)
    }

    // MARK: - The dream: awakened drops

    func testAwakenedDropsComeFromTheTopOfTheRaidLadderOnly() {
        XCTAssertEqual(RaidGradeService.awakenedChance(for: .s), 0)
        XCTAssertGreaterThan(RaidGradeService.awakenedChance(for: .ss), 0)
        XCTAssertGreaterThan(RaidGradeService.awakenedChance(for: .sss), RaidGradeService.awakenedChance(for: .ss))
        XCTAssertLessThan(RaidGradeService.awakenedChance(for: .sss), 0.5, "a dream, not a routine")
    }

    func testTheHardestContentCanDropAwakenedAndNothingElseCan() throws {
        let vault = try XCTUnwrap(DungeonDatabase.labyrinth("lab_colossus"))
        XCTAssertNil(vault.levels[0].rewards.awakenedChance)
        XCTAssertNil(vault.levels[8].rewards.awakenedChance)
        XCTAssertEqual(vault.levels[9].rewards.awakenedChance, DungeonDatabase.labyrinthAwakenedChance)

        XCTAssertNil(DungeonDatabase.towerFloor(85).rewards.awakenedChance)
        XCTAssertEqual(DungeonDatabase.towerFloor(95).rewards.awakenedChance, DungeonDatabase.towerAwakenedChance)

        for hall in DungeonDatabase.halls {
            for floor in hall.floors { XCTAssertNil(floor.rewards.awakenedChance, "\(floor.id): the essence farm never drops one") }
        }

        // The campaign: only Hell where Hell pays a 6★.
        let early = try XCTUnwrap(StageDatabase.chapters.first)
        XCTAssertNil(early.at(.hell).stages.last?.rewards.awakenedChance, "chapter 1 on Hell pays a 4★; nothing awakened")
        XCTAssertNil(early.at(.hard).stages.last?.rewards.awakenedChance)
        let late = try XCTUnwrap(StageDatabase.chapters.first(where: { StageDatabase.chapterOrder(of: $0.id) >= 7 }))
        XCTAssertEqual(late.at(.hell).stages.last?.rewards.awakenedChance, CampaignDifficulty.hellAwakenedChance)
        XCTAssertNil(late.at(.hard).stages.last?.rewards.awakenedChance, "Hard never does")
    }

    // MARK: - The save

    func testTheFlagIsOptionalSoAnOldSaveDecodes() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        // An ordinary relic writes no key, exactly as a relic saved before
        // awakening existed has none, and reads back as ordinary.
        let ordinary = maxedRelic()
        let data = try encoder.encode(ordinary)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"awakened\""))
        let relic = try decoder.decode(Relic.self, from: data)
        XCTAssertNil(relic.awakened)
        XCTAssertFalse(relic.isAwakened)
        XCTAssertEqual(relic.subStatCap, 4)

        var awakened = ordinary
        awakened.awakened = true
        let back = try decoder.decode(Relic.self, from: try encoder.encode(awakened))
        XCTAssertTrue(back.isAwakened)
        XCTAssertEqual(back.subStatCap, 5)
    }
}
