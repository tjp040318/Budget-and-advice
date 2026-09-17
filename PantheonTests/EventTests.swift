import XCTest
@testable import Pantheon

/// The event calendar: a fixed weekday rota, a weekend headline that turns
/// with the ISO week, multipliers that are 1 outside an event and the
/// constant inside, a Festival gift that claims once, and a settle that pays
/// double on its day. Every date is built through `EventCalendar.calendar`,
/// so the tests hold in any time zone.
final class EventTests: XCTestCase {

    /// A date at noon in the calendar's own zone.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        EventCalendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// Monday 21 September 2026: week 142 since the epoch's Monday, a Hall
    /// week (142 % 4 = 2); the week after it is a Labyrinth and Festival week.
    private var monday: Date { date(2026, 9, 21) }
    private func weekday(_ offset: Int) -> Date { EventCalendar.day(offset, after: monday) }
    /// Midnight at the start of the offset's day: an event's own edge (a
    /// `weekday` is noon, a moment INSIDE a day; run 176 compared four
    /// edges to noons and failed them).
    private func dayStart(_ offset: Int) -> Date { EventCalendar.day(offset, after: EventCalendar.weekStart(at: monday)) }
    private let hallWeek = 142
    private let festivalWeek = 143

    private func win(turns: Int = 9) -> BattleResult {
        BattleResult(outcome: .victory, turnsTaken: turns, survivorFraction: 1, totalDamageDealt: 1, totalDamageTaken: 0, seed: 1)
    }

    // MARK: - The rota

    func testTheRotaCoversSevenDays() {
        XCTAssertEqual(EventCalendar.weekIndex(at: monday), hallWeek)
        XCTAssertEqual(EventCalendar.dayIndex(at: monday), 0)
        XCTAssertEqual(EventCalendar.dayIndex(at: weekday(6)), 6)
        XCTAssertEqual(EventCalendar.weekdayRota.count, EventCalendar.weekendStart, "the weekdays hand over to the weekend where the rota ends")

        let headline = EventCalendar.headline(week: hallWeek)
        for offset in 0..<7 {
            let kinds = EventCalendar.active(at: weekday(offset)).map(\.kind)
            XCTAssertFalse(kinds.isEmpty, "day \(offset) has no event")
            if offset < EventCalendar.weekendStart {
                XCTAssertEqual(kinds, [EventCalendar.weekdayRota[offset]], "day \(offset)")
            } else {
                XCTAssertEqual(kinds, [headline], "the weekend's headline runs Friday to Sunday")
            }
        }
        // A weekday's event is over at its midnight.
        XCTAssertFalse(EventCalendar.isActive(.doubleDrachma, at: weekday(1)))
        XCTAssertTrue(EventCalendar.isActive(.doubleDrachma, at: date(2026, 9, 21, hour: 23)))
    }

    func testTheWeekIsListedInOrderAndCovered() {
        let week = EventCalendar.events(at: weekday(3))
        XCTAssertEqual(week.count, EventCalendar.weekdayRota.count + 1, "four weekdays and the headline")
        XCTAssertEqual(week.first?.start, EventCalendar.weekStart(at: weekday(3)))
        XCTAssertEqual(week.last?.end, dayStart(7))
        for (index, event) in week.enumerated() {
            XCTAssertLessThan(event.start, event.end, event.id)
            if index > 0 { XCTAssertEqual(week[index - 1].end, event.start, "no gap before \(event.id)") }
        }
        XCTAssertEqual(EventCalendar.events(at: weekday(6)).map(\.id), week.map(\.id), "the same week from any of its days")

        // The Festival week lists the gift first, then the same shape.
        let festival = EventCalendar.events(at: weekday(7))
        XCTAssertEqual(festival.count, EventCalendar.weekdayRota.count + 2)
        XCTAssertEqual(festival.first?.kind, .loginGift)
        XCTAssertEqual(festival.first?.start, dayStart(7))
        XCTAssertEqual(festival.first?.end, dayStart(14))
        XCTAssertEqual(EventCalendar.nextFestival(after: monday).start, dayStart(7))
        XCTAssertEqual(EventCalendar.nextHeadline(after: monday).kind, EventCalendar.headline(week: festivalWeek))
        XCTAssertEqual(EventCalendar.upcoming(at: weekday(3)).count, 1, "Thursday noon: only the weekend is still to come")
    }

    func testTheWeekendHeadlineChangesWithTheISOWeek() {
        let cycle = EventCalendar.labyrinthEvery
        var halls: Set<Element> = []
        var labyrinths: Set<String> = []
        var previous: EventKind?
        for week in hallWeek..<(hallWeek + 5 * cycle) {
            let headline = EventCalendar.headline(week: week)
            XCTAssertEqual(headline, EventCalendar.headline(week: week), "the same week reads the same twice")
            XCTAssertNotEqual(headline, previous, "week \(week) repeats the weekend before it")
            previous = headline
            switch headline {
            case .doubleEssence(let element):
                XCTAssertFalse(EventCalendar.isLabyrinthWeek(week))
                halls.insert(element)
            case .doubleRelics(let labyrinth):
                XCTAssertTrue(EventCalendar.isLabyrinthWeek(week), "week \(week)")
                XCTAssertNotNil(DungeonDatabase.labyrinth(labyrinth))
                labyrinths.insert(labyrinth)
            default:
                XCTFail("a weekend headline is a Hall or a Labyrinth, not \(headline.key)")
            }
        }
        XCTAssertEqual(halls, Set(Element.allCases), "every Hall gets its weekend")
        XCTAssertEqual(labyrinths, Set(DungeonDatabase.labyrinths.map(\.id)), "every Labyrinth gets its weekend")

        // The week index turns at Monday midnight, not before.
        XCTAssertEqual(EventCalendar.weekIndex(at: date(2026, 9, 27, hour: 23)), hallWeek)
        XCTAssertEqual(EventCalendar.weekIndex(at: date(2026, 9, 28, hour: 0)), festivalWeek)
        XCTAssertNotEqual(EventCalendar.headline(week: hallWeek), EventCalendar.headline(week: festivalWeek))
        // And the cycle is continuous through a year's end: the Hall before
        // and after the boundary are neighbours on the wheel, not the same.
        let lastOf2026 = EventCalendar.weekIndex(at: date(2026, 12, 28))
        XCTAssertNotEqual(EventCalendar.headline(week: lastOf2026), EventCalendar.headline(week: lastOf2026 + 1))
    }

    // MARK: - Multipliers

    func testMultipliersAreOneOutsideAnEventAndTheConstantInside() {
        let tuesday = weekday(1)
        let wednesday = weekday(2)
        let thursday = weekday(3)
        let saturday = weekday(5)

        XCTAssertEqual(EventCalendar.multiplier(for: .doubleDrachma, at: monday), EventTuning.drachma)
        XCTAssertEqual(EventCalendar.multiplier(for: .doubleDrachma, at: tuesday), 1)
        XCTAssertEqual(EventCalendar.multiplier(for: .doubleExperience, at: tuesday), EventTuning.experience)
        XCTAssertEqual(EventCalendar.multiplier(for: .doubleExperience, at: monday), 1)
        XCTAssertEqual(EventCalendar.multiplier(for: .halfEnergyCampaign, at: wednesday), EventTuning.energy)
        XCTAssertEqual(EventCalendar.multiplier(for: .halfEnergyCampaign, at: thursday), 1)
        XCTAssertEqual(EventCalendar.multiplier(for: .arenaLaurelsBoost, at: thursday), EventTuning.laurels)
        XCTAssertEqual(EventCalendar.multiplier(for: .arenaLaurelsBoost, at: saturday), 1)

        let headline = EventCalendar.headline(week: hallWeek)
        let essence = Double(EventTuning.essence)
        XCTAssertEqual(EventCalendar.multiplier(for: headline, at: saturday), essence)
        XCTAssertEqual(EventCalendar.multiplier(for: headline, at: thursday), 1)
        // The other Halls are not doubled on this Hall's weekend.
        for element in Element.allCases where headline != .doubleEssence(element) {
            XCTAssertEqual(EventCalendar.multiplier(for: .doubleEssence(element), at: saturday), 1, element.rawValue)
        }
        XCTAssertEqual(EventCalendar.multiplier(for: .loginGift, at: weekday(7)), 1, "a gift is not a multiplier")
    }

    func testHalfEnergyHalvesCampaignStagesOnlyAndRoundsUp() throws {
        let wednesday = weekday(2)
        XCTAssertEqual(EventCalendar.energyCost(base: 4, at: wednesday), 2)
        XCTAssertEqual(EventCalendar.energyCost(base: 3, at: wednesday), 2, "half of three rounds up")
        XCTAssertEqual(EventCalendar.energyCost(base: 6, at: wednesday), 3)
        XCTAssertEqual(EventCalendar.energyCost(base: 1, at: wednesday), 1, "never free")
        XCTAssertEqual(EventCalendar.energyCost(base: 4, at: monday), 4)

        let stage = try XCTUnwrap(StageDatabase.stage("duat_1_1"))
        let hard = try XCTUnwrap(StageDatabase.stage("duat_1_1@hard"))
        let hall = try XCTUnwrap(DungeonDatabase.hall("hall_ember")).floors[0]
        let level = try XCTUnwrap(DungeonDatabase.labyrinth("lab_hydra")).levels[0]
        let halved = EventCalendar.energyCost(base: stage.energyCost, at: wednesday)
        let hardHalved = EventCalendar.energyCost(base: hard.energyCost, at: wednesday)
        XCTAssertEqual(EventCalendar.energyCost(for: stage, at: wednesday), halved)
        XCTAssertEqual(EventCalendar.energyCost(for: hard, at: wednesday), hardHalved, "a tier is still the campaign")
        XCTAssertLessThan(halved, stage.energyCost)
        XCTAssertEqual(EventCalendar.energyCost(for: hall, at: wednesday), hall.energyCost, "a Hall keeps its price")
        XCTAssertEqual(EventCalendar.energyCost(for: level, at: wednesday), level.energyCost, "a Labyrinth keeps its price")
        XCTAssertEqual(EventCalendar.energyCost(for: DungeonDatabase.towerFloor(3), at: wednesday), DungeonDatabase.towerFloor(3).energyCost)

        // The charge, the refund and the sweep's count all read the same price.
        var player = NewGame.create().player
        let full = player.wallet.energy
        _ = try CampaignService.startBattle(stage: stage, player: &player, seed: 1, now: wednesday)
        let charged = full - player.wallet.energy
        XCTAssertEqual(charged, halved)
        CampaignService.refund(stage: stage, player: &player, now: wednesday)
        XCTAssertEqual(player.wallet.energy, full)
        let swept = try CampaignService.spendSweptRun(stage: stage, player: &player, now: wednesday)
        XCTAssertEqual(swept, halved)
        player.wallet.energy = 20
        let runsOnWednesday = SweepService.affordableRuns(stage, player: player, now: wednesday)
        let runsOnMonday = SweepService.affordableRuns(stage, player: player, now: monday)
        let expectedWednesday = 20 / halved
        let expectedMonday = 20 / stage.energyCost
        XCTAssertEqual(runsOnWednesday, expectedWednesday)
        XCTAssertEqual(runsOnMonday, expectedMonday)
        XCTAssertGreaterThan(runsOnWednesday, runsOnMonday)
    }

    // MARK: - What the game pays

    func testSettlePaysDoubleDrachmaOnTheDrachmaDay() {
        let stage = StageDatabase.chapters[0].stages[0]
        let base = NewGame.create().player
        var plain = base
        var boosted = base
        var plainRNG = SeededRandom(seed: 5)
        var boostedRNG = SeededRandom(seed: 5)

        let onTuesday = CampaignService.settle(stage: stage, result: win(), player: &plain, rng: &plainRNG, now: weekday(1))
        let onMonday = CampaignService.settle(stage: stage, result: win(), player: &boosted, rng: &boostedRNG, now: monday)
        let single = onTuesday.drachma
        let doubled = onMonday.drachma
        let expected = Int(Double(single) * EventTuning.drachma)
        XCTAssertGreaterThan(single, 0)
        XCTAssertEqual(doubled, expected)
        let paidPlain = plain.wallet.drachma - base.wallet.drachma
        let paidBoosted = boosted.wallet.drachma - base.wallet.drachma
        XCTAssertEqual(paidPlain, single, "the receipt is what the wallet got")
        XCTAssertEqual(paidBoosted, doubled)
        XCTAssertEqual(onMonday.eventBoosts.drachma, EventTuning.drachma)
        XCTAssertEqual(onTuesday.eventBoosts.drachma, 1)
        // Monday is not experience day: the same clear's experience is flat.
        let tuesdayXP = onTuesday.unitExperience
        let mondayXP = onMonday.unitExperience
        let expectedTuesdayXP = Int(Double(mondayXP) * EventTuning.experience)
        XCTAssertEqual(tuesdayXP, expectedTuesdayXP, "Tuesday doubles the experience Monday leaves flat")
        XCTAssertEqual(onMonday.eventBoosts.experience, 1)
        // `applyRewards` on its own never reads the calendar.
        var pure = base
        var pureRNG = SeededRandom(seed: 5)
        let untouched = CampaignService.applyRewards(stage: stage, result: win(), player: &pure, rng: &pureRNG)
        XCTAssertEqual(untouched.drachma, single)
        XCTAssertEqual(untouched.eventBoosts, EventBoosts.flat)
    }

    func testTheWeekendDoublesTheHallsEssenceAndTheLabyrinthsRelics() throws {
        // This week's Hall, whichever the wheel gives it.
        guard case .doubleEssence(let element) = EventCalendar.headline(week: hallWeek) else {
            return XCTFail("week \(hallWeek) should headline a Hall")
        }
        let hall = try XCTUnwrap(DungeonDatabase.halls.first(where: { $0.element == element }))
        let floor = try XCTUnwrap(hall.floors.last)
        let base = NewGame.create().player
        var plain = base
        var boosted = base
        var plainRNG = SeededRandom(seed: 9)
        var boostedRNG = SeededRandom(seed: 9)
        let onThursday = CampaignService.settle(stage: floor, result: win(turns: 20), player: &plain, rng: &plainRNG, now: weekday(3))
        let onSaturday = CampaignService.settle(stage: floor, result: win(turns: 20), player: &boosted, rng: &boostedRNG, now: weekday(5))
        let plainEssence = onThursday.essencesEarned.values.reduce(0, +)
        let boostedEssence = onSaturday.essencesEarned.values.reduce(0, +)
        let expectedEssence = plainEssence * EventTuning.essence
        XCTAssertGreaterThan(plainEssence, 0, "B5 drops its Mid essence every run")
        XCTAssertEqual(boostedEssence, expectedEssence, "the same rolls, twice the amount")
        XCTAssertEqual(onSaturday.eventBoosts.essence, EventTuning.essence)
        XCTAssertEqual(onSaturday.relicsEarned.count, onThursday.relicsEarned.count, "a Hall's relics are not the weekend's")
        // Another Hall on the same Saturday is flat.
        let other = try XCTUnwrap(DungeonDatabase.halls.first(where: { $0.element != element }))
        var elsewhere = base
        var elsewhereRNG = SeededRandom(seed: 9)
        let flat = CampaignService.settle(stage: other.floors[4], result: win(turns: 20), player: &elsewhere, rng: &elsewhereRNG, now: weekday(5))
        XCTAssertEqual(flat.eventBoosts.essence, 1)

        // Next week's Labyrinth: two relics a run instead of one.
        guard case .doubleRelics(let id) = EventCalendar.headline(week: festivalWeek) else {
            return XCTFail("week \(festivalWeek) should headline a Labyrinth")
        }
        let labyrinth = try XCTUnwrap(DungeonDatabase.labyrinth(id))
        var runner = base
        var runnerRNG = SeededRandom(seed: 3)
        let ordinary = CampaignService.settle(stage: labyrinth.levels[0], result: win(turns: 20), player: &runner, rng: &runnerRNG, now: weekday(5))
        let doubled = CampaignService.settle(stage: labyrinth.levels[0], result: win(turns: 20), player: &runner, rng: &runnerRNG, now: weekday(12))
        XCTAssertEqual(ordinary.relicsEarned.count, 1)
        XCTAssertEqual(doubled.relicsEarned.count, EventTuning.relicRolls)
        XCTAssertEqual(doubled.eventBoosts.relicRolls, EventTuning.relicRolls)
        for relic in doubled.relicsEarned {
            XCTAssertTrue(labyrinth.sets.contains(relic.set), "\(relic.set) is not one of the dungeon's sets")
        }
        let held = runner.relics.filter { relic in doubled.relicsEarned.contains(where: { $0.id == relic.id }) }.count
        XCTAssertEqual(held, EventTuning.relicRolls, "both relics reach the save")
    }

    func testTheArenaPaysDoubleLaurelsOnItsDay() {
        let opponent = ArenaService.pool(for: ArenaRecord(), day: 1)[0]
        var plain = Player()
        var boosted = Player()
        let result = BattleResult(outcome: .victory, turnsTaken: 10, survivorFraction: 1, totalDamageDealt: 1, totalDamageTaken: 0, seed: 1)
        let onMonday = ArenaService.applyResult(result, against: opponent, player: &plain, now: monday)
        let onThursday = ArenaService.applyResult(result, against: opponent, player: &boosted, now: weekday(3))
        let expected = Int(Double(onMonday.laurels) * EventTuning.laurels)
        XCTAssertEqual(onMonday.laurels, ArenaService.laurelsForWin(tier: .initiate))
        XCTAssertEqual(onThursday.laurels, expected)
        XCTAssertEqual(boosted.wallet.laurels, expected)
        XCTAssertEqual(onThursday.pointsDelta, onMonday.pointsDelta, "the day moves laurels, never rank")
    }

    // MARK: - The Festival's gift

    func testAGiftClaimsOnce() throws {
        var player = NewGame.create().player
        var rng = SeededRandom(seed: 1)
        let festivalMonday = weekday(7)
        let festivalTuesday = weekday(8)

        XCTAssertNil(EventCalendar.gift(at: monday), "no gift outside the Festival")
        XCTAssertThrowsError(try EventCalendar.claimGift(player: &player, rng: &rng, at: monday))
        XCTAssertEqual(EventCalendar.claimableCount(player: player, at: monday), 0)

        XCTAssertEqual(EventCalendar.gift(at: festivalMonday), EventCalendar.festivalGifts[0])
        XCTAssertEqual(EventCalendar.claimableCount(player: player, at: festivalMonday), 1)
        let before = player.wallet.drachma
        let paid = try EventCalendar.claimGift(player: &player, rng: &rng, at: festivalMonday)
        XCTAssertEqual(paid, [EventCalendar.festivalGifts[0]])
        let expectedDrachma = before + 15_000
        XCTAssertEqual(player.wallet.drachma, expectedDrachma)
        XCTAssertTrue(EventCalendar.isGiftClaimed(player: player, at: festivalMonday))
        XCTAssertEqual(player.eventGiftsClaimed, [EventCalendar.giftID(for: festivalMonday)])
        XCTAssertEqual(EventCalendar.claimableCount(player: player, at: festivalMonday), 0)
        XCTAssertThrowsError(try EventCalendar.claimGift(player: &player, rng: &rng, at: festivalMonday))
        // Later the same day is the same gift.
        XCTAssertThrowsError(try EventCalendar.claimGift(player: &player, rng: &rng, at: date(2026, 9, 28, hour: 23)))

        // Tomorrow is a new gift under a new id.
        XCTAssertNotEqual(EventCalendar.giftID(for: festivalMonday), EventCalendar.giftID(for: festivalTuesday))
        XCTAssertFalse(EventCalendar.isGiftClaimed(player: player, at: festivalTuesday))
        let scrolls = player.wallet.count(of: .mystical)
        try EventCalendar.claimGift(player: &player, rng: &rng, at: festivalTuesday)
        let expectedScrolls = scrolls + 2
        XCTAssertEqual(player.wallet.count(of: .mystical), expectedScrolls)
        XCTAssertEqual(player.eventGiftsClaimed?.count, 2)
        // Sunday's is the big one, and the seventh is the last.
        XCTAssertEqual(EventCalendar.gift(at: weekday(13)), EventCalendar.festivalGifts[6])
        XCTAssertNil(EventCalendar.gift(at: weekday(14)), "the Festival ends at Monday midnight")
    }

    func testTheGiftFieldIsOptionalSoAnOldSaveStillDecodes() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let fresh = SaveGame(player: Player(), rngSeed: 1)
        let json = String(data: try encoder.encode(fresh), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"eventGiftsClaimed\""))
        let restored = try decoder.decode(SaveGame.self, from: try encoder.encode(fresh))
        XCTAssertNil(restored.player.eventGiftsClaimed)
        XCTAssertEqual(EventCalendar.claimableCount(player: restored.player, at: weekday(7)), 1)

        var player = Player()
        player.eventGiftsClaimed = ["gift_2026-09-28"]
        let back = try decoder.decode(SaveGame.self, from: try encoder.encode(SaveGame(player: player, rngSeed: 2)))
        XCTAssertEqual(back.player.eventGiftsClaimed, ["gift_2026-09-28"])
        XCTAssertTrue(EventCalendar.isGiftClaimed(player: back.player, at: weekday(7)))
    }
}
