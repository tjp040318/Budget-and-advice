import XCTest
@testable import Pantheon

/// The Draft Arena (Docs/DRAFT.md): the genre's order, a rival that counters,
/// answers a need and strikes the biggest threat, a strike that is sealed
/// before the player's, the Elo ladder with its floors and its Olympiad, the
/// day's paid bouts, the week's chest — and a purse that stays under the
/// arena's. Every number DRAFT.md prints is pinned here with its intent
/// beside it; `tools/balance.py` does not mirror them yet. Dates are built
/// through `EventCalendar.calendar`, so the tests hold in any zone.
final class DraftTests: XCTestCase {

    // MARK: - Fixtures

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        EventCalendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// Monday 21 September 2026: week 142, the third week of Olympiad 35
    /// (weeks 140–143), and a day that leaves laurels alone (Thursday
    /// doubles them).
    private var monday: Date { date(2026, 9, 21) }
    private func day(_ offset: Int) -> Date { EventCalendar.day(offset, after: monday) }

    /// A player with `families` different monsters at `level`, no light or
    /// dark among them.
    private func player(families: Int = 8, level: Int = 30) -> Player {
        var subject = Player()
        let blueprints = UnitDatabase.summonPool
            .compactMap { UnitDatabase.blueprint($0) }
            .filter { !$0.element.isLightOrDark }
            .prefix(families)
        for blueprint in blueprints {
            subject.units.append(Unit(blueprint: blueprint, level: level))
        }
        return subject
    }

    private func resolved(_ blueprint: UnitBlueprint, level: Int = 30) -> ResolvedUnit {
        ProgressionService.resolve(Unit(blueprint: blueprint, level: level), blueprint: blueprint, equipped: [])
    }

    private func resolved(_ id: String, level: Int = 30) throws -> ResolvedUnit {
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint(id), id)
        return resolved(blueprint, level: level)
    }

    private func result(_ outcome: BattleOutcome) -> BattleResult {
        BattleResult(outcome: outcome, turnsTaken: 12, survivorFraction: outcome == .victory ? 1 : 0,
                     totalDamageDealt: 1, totalDamageTaken: 1, seed: 1)
    }

    private func bout(rivalRating: Int) -> DraftBout {
        DraftBout(id: "test", rivalName: "Theron", rivalRating: rivalRating, playerTeam: [], rivalTeam: [],
                  playerBanned: nil, rivalBanned: nil)
    }

    /// A draft between two hand-made boxes, the picks open.
    private func session(mine: [ResolvedUnit], theirs: [ResolvedUnit], first: DraftSide = .player) -> DraftSession {
        let rival = DraftRival(name: "Theron", rating: 1_000, strength: 0.5, box: theirs)
        var draft = DraftSession(seed: 1, firstPicker: first, playerBox: mine, rival: rival)
        draft.beginPicking()
        return draft
    }

    /// A draft played through to the bans by the heuristic on both sides.
    private func playedToTheBans(_ subject: Player, seed: UInt64) throws -> DraftSession {
        var draft = try XCTUnwrap(DraftService.makeSession(player: subject, seed: seed, firstPicker: .player))
        draft.beginPicking()
        while let side = draft.sideToPick {
            let made = try XCTUnwrap(DraftService.choice(for: side, in: draft))
            let taken = draft.pick(made.unitID, reason: made.reason)
            XCTAssertTrue(taken)
            if !taken { break }
        }
        return draft
    }

    // MARK: - The draft's shape

    /// Summoners War's World Arena and Epic Seven's both: one pick, then two
    /// each way, then one — five a side — and four fight, the arena's team.
    func testThePicksFallOneTwoTwoTwoTwoOne() {
        let order = DraftService.pickOrder(first: .player)
        let expected: [DraftSide] = [.player, .rival, .rival, .player, .player, .rival, .rival, .player, .player, .rival]
        XCTAssertEqual(order, expected)
        let flipped: [DraftSide] = expected.map { $0.other }
        XCTAssertEqual(DraftService.pickOrder(first: .rival), flipped)
        let mine = order.filter { $0 == .player }.count
        XCTAssertEqual(mine, DraftService.picksPerSide)
        XCTAssertEqual(DraftService.fightSize, ArenaService.teamSize, "four fight, as in the arena")
    }

    func testFiveDifferentMonstersToDraft() throws {
        let four = player(families: 4)
        XCTAssertFalse(DraftService.canDraft(four))
        XCTAssertNil(DraftService.makeSession(player: four, seed: 1))
        var twins = player(families: 4)
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint(twins.units[0].blueprintID))
        twins.units.append(Unit(blueprint: blueprint, level: 10))
        XCTAssertFalse(DraftService.canDraft(twins), "two of one monster count once")
        XCTAssertTrue(DraftService.canDraft(player(families: 5)))
    }

    func testOneMonsterOncePerFive() throws {
        var subject = player(families: 6)
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint(subject.units[0].blueprintID))
        subject.units.append(Unit(blueprint: blueprint, level: 10))
        var draft = try XCTUnwrap(DraftService.makeSession(player: subject, seed: 3, firstPicker: .player))
        draft.beginPicking()
        let copies = draft.playerBox.filter { $0.blueprint.id == blueprint.id }
        XCTAssertEqual(copies.count, 2)
        let first = draft.pick(copies[0].id)
        XCTAssertTrue(first)
        XCTAssertFalse(draft.canPick(copies[1].id, for: .player), "a second of the same monster")
    }

    // MARK: - The rival's mind

    /// The player opens on a wind unit; the rival holds one monster in water
    /// and in fire, the water first in its box, and takes the fire, which
    /// beats wind — and says so.
    func testTheRivalCountersByElement() throws {
        let perseus = try resolved("perseus_gale")
        let filler = try resolved("thoth_tide")
        let water = try resolved("anubis_tide")
        let fire = try resolved("anubis_ember")
        var draft = session(mine: [perseus, filler], theirs: [water, fire])
        let opened = draft.pick(perseus.id)
        XCTAssertTrue(opened)
        let made = try XCTUnwrap(draft.rivalPicks())
        XCTAssertEqual(made.unitID, fire.id)
        let expected = DraftReason.counters([DraftService.captionName(perseus)])
        XCTAssertEqual(made.reason, expected)
    }

    /// A side with no healer values one by exactly `healerNeed` more than a
    /// side that has one. The other terms are held equal: the sides differ by
    /// one unit, an attacker against a healer, both of another pantheon and
    /// both reached (or not) by the candidate's leader skill alike, and one
    /// support on the covered side is under the crowd's two.
    func testASideWithoutAHealerValuesOne() throws {
        let pool = UnitDatabase.summonPool.compactMap { UnitDatabase.blueprint($0) }
        let healerBlueprint = try XCTUnwrap(pool.first { blueprint in
            DraftService.heals(blueprint.skills) && blueprint.role == .support && !blueprint.element.isLightOrDark
        }, "the pool holds a healer")
        let skill = healerBlueprint.leaderSkill
        let strangers = pool.filter { $0.pantheon != healerBlueprint.pantheon && !$0.element.isLightOrDark }
        let otherHealer = try XCTUnwrap(strangers.first { DraftService.heals($0.skills) && $0.role == .support })
        let coveredReach = skill?.applies(to: otherHealer) ?? false
        let attackers = strangers.filter { $0.role == .attacker && !DraftService.heals($0.skills) }
        let alike = attackers.filter { (skill?.applies(to: $0) ?? false) == coveredReach }
        let firstBlueprint = try XCTUnwrap(attackers.first, "an attacker of another pantheon")
        let secondBlueprint = try XCTUnwrap(alike.first, "an attacker the leader skill reaches as it reaches the healer")
        let healer = resolved(healerBlueprint)
        let first = resolved(firstBlueprint)
        let second = resolved(secondBlueprint)
        let covering = resolved(otherHealer)
        let lone = DraftService.pickScore(healer, mine: [first, second], theirs: [], strongest: healer.power)
        let covered = DraftService.pickScore(healer, mine: [first, covering], theirs: [], strongest: healer.power)
        let lift: Double = lone.score - covered.score
        XCTAssertEqual(lift, DraftService.healerNeed, accuracy: 1e-9)
        XCTAssertEqual(lone.reason, .healer)
    }

    /// The rival's strike is sealed the moment the tenth pick lands, is the
    /// player's biggest threat by the heuristic, and does not move whichever
    /// of the rival's five the player strikes; then both fours are whole and
    /// the crowned unit leads.
    func testTheRivalsStrikeIsSealedBeforeThePlayers() throws {
        let draft = try playedToTheBans(player(families: 10), seed: 42)
        XCTAssertEqual(draft.phase, .banning)
        let sealed = try XCTUnwrap(draft.rivalBan)
        XCTAssertTrue(draft.picked(.player).contains { $0.id == sealed })
        let threat = DraftService.banChoice(against: .player, in: draft)?.unitID
        XCTAssertEqual(sealed, threat)
        for target in draft.picked(.rival) {
            var copy = draft
            let struck = copy.ban(target.id)
            XCTAssertTrue(struck)
            XCTAssertEqual(copy.rivalBan, sealed)
            XCTAssertEqual(copy.survivors(.player).count, DraftService.fightSize)
            XCTAssertEqual(copy.survivors(.rival).count, DraftService.fightSize)
            XCTAssertTrue(copy.isReady)
            XCTAssertEqual(copy.lineup(.player).first?.id, copy.playerLeader, "the crowned leads")
            XCTAssertEqual(copy.lineup(.rival).first?.id, copy.rivalLeader)
        }
    }

    /// A finished draft is a four-against-four in the arena's mode, carried
    /// by `BattleContext.draft` on the Arena of Souls.
    func testADraftEndsInAFightOfFourAgainstFour() throws {
        var draft = try playedToTheBans(player(families: 10), seed: 7)
        let strike = try XCTUnwrap(DraftService.banChoice(against: .rival, in: draft))
        let struck = draft.ban(strike.unitID)
        XCTAssertTrue(struck)
        let bout = try XCTUnwrap(DraftService.bout(from: draft))
        XCTAssertEqual(bout.playerTeam.count, DraftService.fightSize)
        XCTAssertEqual(bout.rivalTeam.count, DraftService.fightSize)
        XCTAssertFalse(bout.rivalTeam.contains { $0.id == strike.unitID }, "the struck unit sits out")
        let engine = BattleEngine(playerTeam: bout.playerTeam, opponentTeam: bout.rivalTeam, mode: .arenaOffense, seed: 7)
        let fighters: Int = engine.combatants.count
        XCTAssertEqual(fighters, 8)
        let context = BattleContext.draft(bout)
        XCTAssertEqual(context.environment, .arenaOfSouls)
        let title: String = "vs " + bout.rivalName
        XCTAssertEqual(context.title, title)
        XCTAssertTrue(context.id.hasPrefix("draft_"))
    }

    /// The rival's box is fourteen different monsters, no boss and at most
    /// two light or dark, built at the player's strength and leaned on by
    /// his crown: an Olympic crown meets a stronger box than a Nemean one.
    func testTheRivalsBoxLeansWithTheCrown() throws {
        var subject = player(families: 8)
        let early = try XCTUnwrap(DraftService.makeSession(player: subject, seed: 9))
        var record = DraftRecord()
        record.rating = DraftTier.olympic.threshold
        subject.draft = record
        let late = try XCTUnwrap(DraftService.makeSession(player: subject, seed: 9))
        let earlyPower: Double = DraftService.topFivePower(early.rival.box)
        let latePower: Double = DraftService.topFivePower(late.rival.box)
        XCTAssertGreaterThan(latePower, earlyPower)
        XCTAssertGreaterThanOrEqual(late.rival.strength, early.rival.strength)
        XCTAssertEqual(early.rival.box.count, DraftService.boxSize)
        let distinct = Set(early.rival.box.map { $0.blueprint.id }).count
        XCTAssertEqual(distinct, DraftService.boxSize, "one of each monster")
        let lightDark = early.rival.box.filter { $0.element.isLightOrDark }.count
        XCTAssertLessThanOrEqual(lightDark, DraftService.lightDarkCap)
        let bosses = early.rival.box.filter { $0.blueprint.archetype == .primordial || $0.blueprint.model.height >= 3 }.count
        XCTAssertEqual(bosses, 0)
    }

    /// Leaving the board and coming back finds the same coin and the same
    /// box; a fought bout calls the next rival.
    func testTheRivalWaitsUntilABoutIsFought() {
        var subject = player()
        let seed: UInt64 = DraftService.sessionSeed(player: subject, now: monday)
        let later: UInt64 = DraftService.sessionSeed(player: subject, now: day(2))
        XCTAssertEqual(seed, later, "the same week and the same bouts: the same rival")
        DraftService.applyResult(result(.victory), bout: bout(rivalRating: 1_000), player: &subject, now: monday)
        let after: UInt64 = DraftService.sessionSeed(player: subject, now: monday)
        XCTAssertNotEqual(seed, after)
    }

    func testTheToursBoardStopsWhereItIsAsked() throws {
        let subject = player(families: 10)
        let early = try XCTUnwrap(DraftService.scriptedSession(player: subject, stage: .picks))
        XCTAssertEqual(early.picks.count, 4, "two picks each")
        XCTAssertEqual(early.sideToPick, .player)
        let striking = try XCTUnwrap(DraftService.scriptedSession(player: subject, stage: .bans))
        XCTAssertEqual(striking.phase, .banning)
        let crowning = try XCTUnwrap(DraftService.scriptedSession(player: subject, stage: .leaders))
        XCTAssertTrue(crowning.isReady)
    }

    // MARK: - The ladder

    func testTheCrownsAndTheirFloors() {
        let floors: [Int] = DraftTier.allCases.map(\.threshold)
        XCTAssertEqual(floors, [0, 1_100, 1_250, 1_450, 1_700])
        XCTAssertEqual(DraftService.startingRating, 1_000, "Summoners War's 1,000 victory points")
        XCTAssertEqual(DraftTier.tier(forRating: DraftService.startingRating), .nemean)
        XCTAssertEqual(DraftTier.tier(forRating: 1_249), .isthmian)
        XCTAssertEqual(DraftTier.tier(forRating: 1_250), .pythian)
        XCTAssertEqual(DraftTier.tier(forRating: 9_999), .periodonikes)
        let names: [String] = DraftTier.allCases.map { $0.displayName.lowercased() }
        XCTAssertFalse(names.contains("demigod"), "the demigod is the player, never a rank")
        let leans: [Double] = [0.8, 0.9, 1.0, 1.1, 1.2]
        for (tier, lean) in zip(DraftTier.allCases, leans) {
            let strength: Double = tier.rivalStrength
            XCTAssertEqual(strength, lean, accuracy: 1e-9, "the rival's box against the player's best five")
        }
    }

    func testEloSwings() {
        let even: Int = DraftService.ratingDelta(score: 1, rating: 1_200, rivalRating: 1_200, k: DraftService.standardK)
        XCTAssertEqual(even, 16)
        let evenLoss: Int = DraftService.ratingDelta(score: 0, rating: 1_200, rivalRating: 1_200, k: DraftService.standardK)
        XCTAssertEqual(evenLoss, -16)
        let placement: Int = DraftService.ratingDelta(score: 1, rating: 1_000, rivalRating: 1_000, k: DraftService.placementK)
        XCTAssertEqual(placement, 24)
        let upset: Int = DraftService.ratingDelta(score: 1, rating: 1_000, rivalRating: 1_400, k: DraftService.standardK)
        XCTAssertGreaterThan(upset, even, "beating a stronger rival is worth more")
        let stomp: Int = DraftService.ratingDelta(score: 1, rating: 1_600, rivalRating: 1_000, k: DraftService.standardK)
        XCTAssertGreaterThanOrEqual(stomp, 1, "a win is never worth nothing")
        XCTAssertEqual(DraftService.placementBouts, 10)
    }

    func testAWinMovesTheRatingAndPaysAPaidBout() throws {
        var subject = Player()
        subject.wallet.laurels = 0
        let settled = DraftService.applyResult(result(.victory), bout: bout(rivalRating: 1_000), player: &subject, now: monday)
        XCTAssertEqual(settled.ratingDelta, 24, "the first ten bouts swing at the placement's 48")
        let record = try XCTUnwrap(subject.draft)
        XCTAssertEqual(record.rating, 1_024)
        XCTAssertEqual(record.wins, 1)
        XCTAssertEqual(record.bouts, 1)
        XCTAssertEqual(settled.laurels, DraftTier.nemean.laurelsForWin)
        XCTAssertEqual(subject.wallet.laurels, DraftTier.nemean.laurelsForWin)
    }

    func testALossNeverDropsBelowTheCrownsFloor() {
        var subject = Player()
        var record = DraftRecord()
        record.rating = DraftTier.pythian.threshold
        record.bouts = 40
        subject.draft = record
        for _ in 0..<5 {
            DraftService.applyResult(result(.defeat), bout: bout(rivalRating: 1_250), player: &subject, now: monday)
        }
        let rating: Int = subject.draft?.rating ?? 0
        XCTAssertEqual(rating, DraftTier.pythian.threshold)
        let losses: Int = subject.draft?.losses ?? 0
        XCTAssertEqual(losses, 5)
    }

    /// Four weeks make an Olympiad; its turn pulls the rating halfway back to
    /// the start, and the best rating stays a lifetime's. A week's turn
    /// inside an Olympiad pulls nothing.
    func testTheOlympiadPullsTheRatingHalfwayBack() {
        var record = DraftRecord()
        record.rating = 1_700
        record.highestRating = 1_700
        record.bouts = 50
        record.week = 143
        XCTAssertEqual(DraftService.seasonWeeks, 4)
        let turn = date(2026, 10, 5)
        let week: Int = EventCalendar.weekIndex(at: turn)
        XCTAssertEqual(week, 144)
        var rolled = record
        DraftService.rollOver(&rolled, now: turn)
        XCTAssertEqual(rolled.rating, 1_350)
        XCTAssertEqual(rolled.highestRating, 1_700)
        var inside = record
        inside.week = 142
        DraftService.rollOver(&inside, now: day(7))
        XCTAssertEqual(inside.rating, 1_700)
    }

    func testTheRecordRidesTheSave() throws {
        var subject = Player()
        XCTAssertNil(subject.draft, "nil until the board first opens")
        var record = DraftRecord()
        record.rating = 1_333
        record.chestTier = DraftTier.pythian.rawValue
        record.week = 142
        subject.draft = record
        let data = try JSONEncoder().encode(subject)
        let decoded = try JSONDecoder().decode(Player.self, from: data)
        XCTAssertEqual(decoded.draft, record)
    }

    // MARK: - The purse

    func testTheRewardTable() {
        let wins: [Int] = DraftTier.allCases.map(\.laurelsForWin)
        XCTAssertEqual(wins, [15, 20, 25, 30, 35])
        XCTAssertEqual(DraftService.laurelsForLoss, 5)
        XCTAssertEqual(DraftService.paidBoutsPerDay, 5)
        XCTAssertEqual(DraftService.chestMinimumBouts, 3)
        let chests: [Int] = DraftTier.allCases.map { $0.chest.laurels }
        XCTAssertEqual(chests, [60, 100, 150, 220, 300])
        let first: [DraftScroll] = DraftTier.nemean.chest.scrolls
        XCTAssertEqual(first, [DraftScroll(scroll: .mystical, count: 1)])
        let last: [DraftScroll] = DraftTier.periodonikes.chest.scrolls
        XCTAssertEqual(last, [DraftScroll(scroll: .pantheonic, count: 1), DraftScroll(scroll: .lightDark, count: 1)])
    }

    func testFiveBoutsADayPay() {
        var subject = Player()
        var paid: [Int] = []
        for _ in 0..<6 {
            let settled = DraftService.applyResult(result(.victory), bout: bout(rivalRating: 1_000), player: &subject, now: monday)
            paid.append(settled.laurels)
        }
        let paying = paid.filter { $0 > 0 }.count
        XCTAssertEqual(paying, DraftService.paidBoutsPerDay)
        XCTAssertEqual(paid.last, 0, "the sixth bout of a day moves the rating and pays nothing")
        let tomorrow = DraftService.applyResult(result(.defeat), bout: bout(rivalRating: 1_000), player: &subject, now: day(1))
        XCTAssertEqual(tomorrow.laurels, DraftService.laurelsForLoss, "midnight refills the paid bouts")
    }

    func testThursdaysDoubleLaurelsReachTheDraft() {
        var plain = Player()
        var boosted = Player()
        let onMonday = DraftService.applyResult(result(.victory), bout: bout(rivalRating: 1_000), player: &plain, now: monday)
        let onThursday = DraftService.applyResult(result(.victory), bout: bout(rivalRating: 1_000), player: &boosted, now: day(3))
        let doubled = Int(Double(onMonday.laurels) * EventTuning.laurels)
        XCTAssertEqual(onThursday.laurels, doubled)
        XCTAssertEqual(onThursday.ratingDelta, onMonday.ratingDelta, "the day moves laurels, never the rating")
    }

    func testAWeekOfThreeBoutsLeavesAChestThatPaysOnce() throws {
        var subject = Player()
        var record = DraftRecord()
        record.rating = 1_300
        record.bouts = 40
        subject.draft = record
        for offset in 0..<3 {
            DraftService.applyResult(result(.defeat), bout: bout(rivalRating: 1_300), player: &subject, now: day(offset))
        }
        let laurels = subject.wallet.laurels
        let pantheon = subject.wallet.count(of: .pantheonic)
        let mystical = subject.wallet.count(of: .mystical)
        let nextMonday = day(7)
        let chest = try XCTUnwrap(DraftService.claimChest(player: &subject, now: nextMonday))
        XCTAssertEqual(chest, DraftTier.pythian.chest, "the crown the week closed on")
        let laurelsAfter: Int = laurels + 150
        let pantheonAfter: Int = pantheon + 1
        let mysticalAfter: Int = mystical + 1
        XCTAssertEqual(subject.wallet.laurels, laurelsAfter)
        XCTAssertEqual(subject.wallet.count(of: .pantheonic), pantheonAfter)
        XCTAssertEqual(subject.wallet.count(of: .mystical), mysticalAfter)
        let again = DraftService.claimChest(player: &subject, now: nextMonday)
        XCTAssertNil(again, "a chest pays once")
    }

    func testTwoBoutsLeaveNoChest() {
        var subject = Player()
        for offset in 0..<2 {
            DraftService.applyResult(result(.victory), bout: bout(rivalRating: 1_000), player: &subject, now: day(offset))
        }
        let chest = DraftService.claimChest(player: &subject, now: day(7))
        XCTAssertNil(chest, "a week needs three bouts for its chest")
    }

    /// The purse against the arena (DRAFT.md, *The purse*): at every crown a
    /// week of paid draft bouts at a 60% win rate, the chest included, pays
    /// under 80% of a week of ten arena attacks a day at the peer arena tier
    /// at the same rate — and no more than that week with the chest's scrolls
    /// priced at the laurel exchange. The draft is a mode of skill, not the
    /// laurel farm; the arena stays that.
    func testTheDraftPaysLessThanTheArena() {
        for tier in DraftTier.allCases {
            let draft: Int = DraftService.weeklyLaurels(tier: tier, winRate: 0.6)
            let value: Int = DraftService.weeklyValue(tier: tier, winRate: 0.6)
            let arena: Int = DraftService.arenaWeeklyLaurels(tier: tier.arenaPeer, winRate: 0.6, attacksPerDay: 10)
            let ceiling: Int = arena * 8 / 10
            XCTAssertLessThan(draft, ceiling, tier.displayName)
            XCTAssertLessThanOrEqual(value, arena, tier.displayName)
        }
        let printed: [Int] = DraftTier.allCases.map { DraftService.weeklyLaurels(tier: $0, winRate: 0.6) }
        XCTAssertEqual(printed, [445, 590, 745, 920, 1_105])
        let arenaPrinted: [Int] = DraftTier.allCases.map {
            DraftService.arenaWeeklyLaurels(tier: $0.arenaPeer, winRate: 0.6, attacksPerDay: 10)
        }
        XCTAssertEqual(arenaPrinted, [588, 840, 1_092, 1_344, 1_596])
    }

    func testScrollsArePricedAtTheExchange() {
        XCTAssertEqual(DraftService.laurelValue(of: .pantheonic), 150)
        XCTAssertEqual(DraftService.laurelValue(of: .lightDark), 250)
        XCTAssertEqual(DraftService.laurelValue(of: .mystical), 112, "75 divinity at the exchange's 150 laurels for 100")
    }

    /// The arena's pay for a lost attack is a literal in `ArenaService
    /// .applyResult`; the purse's arithmetic mirrors it, and this is where
    /// the two are held together.
    func testTheArenasLossPayIsMirrored() {
        let opponent = ArenaService.pool(for: ArenaRecord(), day: 1)[0]
        var subject = Player()
        let lost = ArenaService.applyResult(result(.defeat), against: opponent, player: &subject, now: monday)
        XCTAssertEqual(lost.laurels, DraftService.arenaLaurelsForLoss)
    }
}
