import XCTest
@testable import Pantheon

/// The Hidden Shrines (2026-09-23; Docs/SHRINES.md): where a shrine is found,
/// what it can be, what a win pays and what the pieces buy. The tuning numbers
/// are pinned with their INTENT beside them, so a change to one here, in
/// `ShrineService` or in `tools/balance.py --shrines` fails loudly rather than
/// drifting. Arithmetic is hoisted into typed lets, never inside an assert.
final class ShrineTests: XCTestCase {

    private let labyrinthB7 = "lab_colossus_7"
    private let hallOfTidesB1 = "hall_tide_1"
    private let hallOfRadianceB3 = "hall_radiance_3"

    private func stage(_ id: String) throws -> Stage {
        try XCTUnwrap(StageDatabase.stage(id), "\(id) is a real stage")
    }

    private func win(_ stage: Stage) -> BattleResult {
        SweepService.masteredResult(for: stage, seed: 1)
    }

    private func loss() -> BattleResult {
        BattleResult(outcome: .defeat, turnsTaken: 30, survivorFraction: 0, totalDamageDealt: 0, totalDamageTaken: 0, seed: 1)
    }

    // MARK: - The numbers, pinned with their intent

    /// Summoners War's exact hour; three open at most; half a per cent for
    /// every point of energy a clear cost — about one shrine a day of normal
    /// play (`balance.py --shrines` asserts 0.6–1.2).
    func testTheRulesAreTheMeasuredOnes() {
        XCTAssertEqual(ShrineService.windowMinutes, 60)
        XCTAssertEqual(ShrineService.maxOpen, 3)
        XCTAssertEqual(ShrineService.discoveryPerEnergy, 0.005, accuracy: 1e-12)
        XCTAssertEqual(ShrineService.piecesPerRun, 3)
        XCTAssertEqual(ShrineService.bonusPieceChance, 0.5, accuracy: 1e-12)
        XCTAssertEqual(ShrineService.returnChance, 0.5, accuracy: 1e-12)
        XCTAssertEqual(ShrineService.essenceChance, 0.30, accuracy: 1e-12)
        XCTAssertEqual(ShrineService.scrollChance, 0.10, accuracy: 1e-12)
        XCTAssertEqual(ShrineService.bossMultiplier, 1.6, accuracy: 1e-12)
        let window: TimeInterval = ShrineService.window
        XCTAssertEqual(window, 3_600, accuracy: 1e-9)
    }

    /// 20 pieces for a 3★ (the fodder tier: dearer than an Unknown Scroll),
    /// 40 for a 4★ (one shrine's hour), 100 for a 5★ (more than any one
    /// hour, so a god needs his shrine to come back). The prices climb.
    func testPiecesClimbWithTheGrade() {
        XCTAssertEqual(ShrineService.piecesPerSummon, [3: 20, 4: 40, 5: 100])
        let three = ShrineService.piecesPerSummon[3] ?? 0
        let four = ShrineService.piecesPerSummon[4] ?? 0
        let five = ShrineService.piecesPerSummon[5] ?? 0
        XCTAssertLessThan(three, four)
        XCTAssertLessThan(four, five)
        // A 4★ is inside one hour of a level-30 bar at B7's seven energy a
        // win (138 + 12); a 5★ is not, even at a level-50 bar (178 + 12).
        let perWin: Double = Double(ShrineService.piecesPerRun) + ShrineService.bonusPieceChance
        let fourEnergy: Double = Double(four) / perWin * 7
        let fiveEnergy: Double = Double(five) / perWin * 8
        XCTAssertLessThanOrEqual(fourEnergy, 150, "a 4★ is one shrine's hour of normal play")
        XCTAssertGreaterThan(fiveEnergy, 190, "no 5★ is ever had from one shrine")
    }

    /// Toward 3★ and 4★ at every depth, the 5★ rare and rarer the shallower
    /// the clear, and every table a whole.
    func testGradeWeightsLeanLowAndSumToOne() {
        XCTAssertEqual(Set(ShrineService.gradeWeights.keys), [3, 4, 5, 6], "a table for every relic grade a source pays")
        var lastFive = 0.0
        for depth in ShrineService.gradeWeights.keys.sorted() {
            let weights = ShrineService.gradeWeights[depth] ?? [:]
            let total: Double = weights.values.reduce(0, +)
            let five: Double = weights[5] ?? 0
            let common: Double = (weights[3] ?? 0) + (weights[4] ?? 0)
            XCTAssertEqual(total, 1, accuracy: 1e-9, "depth \(depth) sums to one")
            XCTAssertLessThanOrEqual(five, 0.05, "depth \(depth): a 5★ shrine is rare")
            XCTAssertGreaterThanOrEqual(common, 0.95, "depth \(depth): toward 3★ and 4★")
            XCTAssertGreaterThanOrEqual(five, lastFive, "a deeper clear never finds a 5★ less often")
            lastFive = five
        }
        let deepFive: Double = ShrineService.gradeWeights[5]?[5] ?? 0
        let bottomFive: Double = ShrineService.gradeWeights[6]?[5] ?? 0
        XCTAssertEqual(deepFive, 0.04, accuracy: 1e-12, "B7 finds a 5★ one shrine in twenty-five")
        XCTAssertEqual(bottomFive, 0.05, accuracy: 1e-12, "B10 one in twenty")
    }

    // MARK: - What a shrine can be

    /// Never Radiance or Umbra — the Light & Dark scroll is their only road —
    /// never a fusion prize, and only what the summon pool holds.
    func testThePoolHoldsNoPremiumAndNoFusionPrize() {
        let pool = ShrineService.pool
        XCTAssertFalse(pool.isEmpty)
        for blueprint in pool {
            XCTAssertFalse(blueprint.element.isLightOrDark, "\(blueprint.id) is a Radiance or Umbra form")
            XCTAssertFalse(FusionService.isFusionOnly(blueprint.id), "\(blueprint.id) is a fusion prize")
            XCTAssertTrue(UnitDatabase.summonPool.contains(blueprint.id), "\(blueprint.id) is not summonable")
            XCTAssertNotNil(ShrineService.piecesPerSummon[blueprint.naturalStars], "\(blueprint.id) has a price")
        }
        for grade in [3, 4, 5] {
            let count = pool.filter { $0.naturalStars == grade }.count
            XCTAssertGreaterThan(count, 0, "a \(grade)★ shrine has forms to be")
        }
        XCTAssertFalse(ShrineService.isShrineForm("anubis_radiance"))
        XCTAssertFalse(ShrineService.isShrineForm("anubis_umbra"))
        XCTAssertTrue(ShrineService.isShrineForm("anubis_tide"))
    }

    /// The Hall of Tides finds water; the Labyrinth and the Hall of Radiance
    /// find fire, water and wind — never the premium, whatever the seed.
    func testAFormIsTheRoomsElementAndNeverThePremium() throws {
        let player = NewGame.create().player
        let tides = try stage(hallOfTidesB1)
        let radiance = try stage(hallOfRadianceB3)
        let vault = try stage(labyrinthB7)
        XCTAssertEqual(ShrineService.elements(foundOn: tides), [.tide])
        XCTAssertEqual(ShrineService.elements(foundOn: radiance), [.ember, .tide, .gale])
        XCTAssertEqual(ShrineService.elements(foundOn: vault), [.ember, .tide, .gale])
        for seed in 1...300 {
            var rng = SeededRandom(seed: UInt64(seed))
            let fromTides = ShrineService.rollForm(foundOn: tides, player: player, rng: &rng)
            let fromRadiance = ShrineService.rollForm(foundOn: radiance, player: player, rng: &rng)
            let fromTheVault = ShrineService.rollForm(foundOn: vault, player: player, rng: &rng)
            let water = try XCTUnwrap(fromTides)
            XCTAssertEqual(water.element, .tide, "the Hall of Tides found \(water.id)")
            let bright = try XCTUnwrap(fromRadiance)
            XCTAssertFalse(bright.element.isLightOrDark, "the Hall of Radiance found \(bright.id)")
            let deep = try XCTUnwrap(fromTheVault)
            XCTAssertFalse(deep.element.isLightOrDark, "the Vault found \(deep.id)")
        }
    }

    /// Half the time a new shrine is a form whose pieces are held: over three
    /// hundred Hall of Tides B1 rolls, the one held 3★ water form comes up in
    /// far more of the 3★ shrines than its one-in-thirty-odd uniform share.
    func testAHeldFormComesBack() throws {
        var player = NewGame.create().player
        let tides = try stage(hallOfTidesB1)
        let held = try XCTUnwrap(ShrineService.pool.first { $0.naturalStars == 3 && $0.element == .tide })
        player.shrinePieces = [held.id: 12]
        var threes = 0
        var returns = 0
        for seed in 1...300 {
            var rng = SeededRandom(seed: UInt64(seed))
            let rolled = ShrineService.rollForm(foundOn: tides, player: player, rng: &rng)
            let form = try XCTUnwrap(rolled)
            guard form.naturalStars == 3 else { continue }
            threes += 1
            if form.id == held.id { returns += 1 }
        }
        XCTAssertGreaterThan(threes, 100)
        let share: Double = Double(returns) / Double(max(1, threes))
        XCTAssertGreaterThan(share, 0.35, "the stock rule brings a held form back about half the time")
        XCTAssertLessThan(share, 0.70, "and a random form the rest")
    }

    // MARK: - Where one is found

    /// A Labyrinth or Hall win's chance is its energy times the rate; no
    /// other stage finds one, and a shrine's own win never does.
    func testTheChanceFollowsTheEnergy() throws {
        let vault = try stage(labyrinthB7)
        let tides = try stage(hallOfTidesB1)
        let vaultChance: Double = Double(vault.energyCost) * ShrineService.discoveryPerEnergy
        let tidesChance: Double = Double(tides.energyCost) * ShrineService.discoveryPerEnergy
        XCTAssertEqual(ShrineService.discoveryChance(for: vault), vaultChance, accuracy: 1e-12)
        XCTAssertEqual(ShrineService.discoveryChance(for: tides), tidesChance, accuracy: 1e-12)
        XCTAssertEqual(ShrineService.depth(of: vault), 5, "B7 pays a 5★ relic")
        XCTAssertEqual(ShrineService.depth(of: tides), 3, "Hall B1 pays a 3★ relic")

        let campaign = try XCTUnwrap(StageDatabase.chapters.first?.stages.first)
        XCTAssertEqual(ShrineService.discoveryChance(for: campaign), 0, "a campaign stage finds none")
        let shrine = try XCTUnwrap(ShrineService.stage(formID: "anubis_tide", foundOn: labyrinthB7))
        XCTAssertEqual(ShrineService.discoveryChance(for: shrine), 0, "a shrine's win finds none")
    }

    /// A found shrine is open an hour, keyed to the stage it was found on;
    /// three at most are open; an expired one is pruned.
    func testDiscoveryOpensAnHourAndNeverAFourth() throws {
        let vault = try stage(labyrinthB7)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var found: HiddenShrine?
        var player = NewGame.create().player
        for seed in 1...3_000 where found == nil {
            var rng = SeededRandom(seed: UInt64(seed))
            found = ShrineService.discover(after: vault, player: &player, rng: &rng, now: now)
        }
        let shrine = try XCTUnwrap(found, "B7's 3.5% lands inside three thousand seeds")
        let open: TimeInterval = shrine.expiresAt.timeIntervalSince(shrine.openedAt)
        XCTAssertEqual(open, 3_600, accuracy: 1e-6)
        XCTAssertEqual(shrine.foundOn, labyrinthB7)
        XCTAssertTrue(ShrineService.isShrineForm(shrine.blueprintID))
        XCTAssertEqual(player.shrines?.count, 1)

        // Three open: no clear finds a fourth.
        var full = NewGame.create().player
        full.shrines = ["anubis_tide", "anubis_ember", "anubis_gale"].map { id in
            HiddenShrine(blueprintID: id, foundOn: labyrinthB7, openedAt: now, expiresAt: now.addingTimeInterval(600))
        }
        for seed in 1...500 {
            var rng = SeededRandom(seed: UInt64(seed))
            ShrineService.discover(after: vault, player: &full, rng: &rng, now: now)
        }
        XCTAssertEqual(full.shrines?.count, ShrineService.maxOpen, "a shrine is never taken away to make room")

        // An hour later every one of them is gone.
        let later = now.addingTimeInterval(601)
        XCTAssertTrue(ShrineService.openShrines(player: full, at: later).isEmpty)
        ShrineService.prune(player: &full, at: later)
        XCTAssertNil(full.shrines, "an empty list is no key at all")
    }

    /// A defeat finds nothing and pays nothing.
    func testADefeatDoesNothing() throws {
        let vault = try stage(labyrinthB7)
        let shrine = try XCTUnwrap(ShrineService.stage(formID: "anubis_tide", foundOn: labyrinthB7))
        var player = NewGame.create().player
        for seed in 1...300 {
            var rng = SeededRandom(seed: UInt64(seed))
            let fromTheVault = ShrineService.noteClear(stage: vault, result: loss(), player: &player, rng: &rng)
            let fromTheShrine = ShrineService.noteClear(stage: shrine, result: loss(), player: &player, rng: &rng)
            XCTAssertNil(fromTheVault)
            XCTAssertNil(fromTheShrine)
        }
        XCTAssertNil(player.shrines)
        XCTAssertNil(player.shrinePieces)
    }

    // MARK: - A win in one

    /// Three pieces a win and a fourth half the time, into the form's stock,
    /// counted on the shrine while it stands.
    func testAWinPaysThreeOrFourPieces() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var player = NewGame.create().player
        player.shrines = [HiddenShrine(blueprintID: "anubis_tide", foundOn: labyrinthB7, openedAt: now,
                                       expiresAt: now.addingTimeInterval(ShrineService.window))]
        let shrine = try XCTUnwrap(ShrineService.stage(formID: "anubis_tide", foundOn: labyrinthB7))
        var total = 0
        var fours = 0
        for seed in 1...200 {
            var rng = SeededRandom(seed: UInt64(seed))
            let news = ShrineService.noteClear(stage: shrine, result: win(shrine), player: &player, rng: &rng, now: now)
            guard case .pieces(let form, let count)? = news else { return XCTFail("a win pays pieces") }
            XCTAssertEqual(form, "anubis_tide")
            let inRange: Bool = (3...4).contains(count)
            XCTAssertTrue(inRange, "a win pays \(count)")
            total += count
            if count == 4 { fours += 1 }
        }
        XCTAssertEqual(ShrineService.pieces(of: "anubis_tide", player: player), total)
        XCTAssertEqual(player.shrines?.first?.wins, 200)
        XCTAssertGreaterThan(fours, 60, "a fourth piece about one win in two")
        XCTAssertLessThan(fours, 140)
    }

    // MARK: - The pieces buy the form

    /// 40 pieces of a 4★ summon it: the unit is the player's, the codex has
    /// it, and the stock is spent to the piece; 45 leave 5; 39 are one short.
    func testPiecesSummonTheForm() throws {
        let form = try XCTUnwrap(UnitDatabase.blueprint("anubis_tide"))
        XCTAssertEqual(form.naturalStars, 4)
        var player = NewGame.create().player
        let before = player.units.count
        player.shrinePieces = ["anubis_tide": 40]
        var rng = SeededRandom(seed: 7)
        let result = try ShrineService.summon("anubis_tide", player: &player, rng: &rng)
        let after = player.units.count
        let expected = before + 1
        XCTAssertEqual(after, expected)
        XCTAssertEqual(result.blueprint.id, "anubis_tide")
        XCTAssertEqual(result.stars, 4)
        XCTAssertFalse(result.fromPity)
        XCTAssertEqual(player.units.last?.acquiredFrom, "shrine")
        XCTAssertTrue(player.codex.contains("anubis_tide"))
        XCTAssertNil(player.shrinePieces, "forty spent to the piece leaves no stock")

        player.shrinePieces = ["anubis_tide": 45]
        _ = try ShrineService.summon("anubis_tide", player: &player, rng: &rng)
        XCTAssertEqual(ShrineService.pieces(of: "anubis_tide", player: player), 5)

        player.shrinePieces = ["anubis_tide": 39]
        do {
            _ = try ShrineService.summon("anubis_tide", player: &player, rng: &rng)
            XCTFail("39 pieces must not summon a 4★")
        } catch ShrineService.ShrineError.notEnoughPieces(let needed) {
            XCTAssertEqual(needed, 1)
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertEqual(ShrineService.pieces(of: "anubis_tide", player: player), 39, "a refused summon spends nothing")
    }

    /// No stock of pieces ever buys the premium.
    func testPiecesNeverBuyRadianceOrUmbra() {
        var player = NewGame.create().player
        player.shrinePieces = ["anubis_radiance": 500, "anubis_umbra": 500]
        var rng = SeededRandom(seed: 3)
        for premium in ["anubis_radiance", "anubis_umbra"] {
            do {
                _ = try ShrineService.summon(premium, player: &player, rng: &rng)
                XCTFail("\(premium) came from pieces")
            } catch ShrineService.ShrineError.unknownForm {
                // The one refusal it may give.
            } catch {
                XCTFail("\(error)")
            }
        }
        XCTAssertFalse(player.codex.contains("anubis_radiance"))
        XCTAssertEqual(ShrineService.pieces(of: "anubis_umbra", player: player), 500, "nothing was spent")
        XCTAssertNil(ShrineService.stage(formID: "anubis_umbra", foundOn: labyrinthB7), "no shrine of the premium")
    }

    /// A duplicate is a skill-up on the one already owned, as a scroll's is.
    func testADuplicateIsASkillUp() throws {
        let form = try XCTUnwrap(UnitDatabase.blueprint("anubis_tide"))
        var player = NewGame.create().player
        player.units.append(Unit(blueprint: form))
        player.codex.insert(form.id)
        let owned = try XCTUnwrap(player.units.last?.id)
        let levelsBefore = player.units.first { $0.id == owned }?.skillLevels.reduce(0, +) ?? 0
        let canRise = form.skills.contains { $0.maxSkillLevel > 1 }
        player.shrinePieces = [form.id: 40]
        var rng = SeededRandom(seed: 11)
        let result = try ShrineService.summon(form.id, player: &player, rng: &rng)
        XCTAssertFalse(result.isNew)
        let levelsAfter = player.units.first { $0.id == owned }?.skillLevels.reduce(0, +) ?? 0
        let risen = levelsBefore + 1
        if canRise {
            XCTAssertEqual(levelsAfter, risen, "the owned unit took a skill-up")
        }
    }

    /// The stocks list ready forms first, then the nearest to whole.
    func testStocksListReadyFirst() {
        var player = NewGame.create().player
        player.shrinePieces = ["sekhmet_gale": 45, "shabti_gale": 20, "anubis_tide": 26, "anubis_ember": 0]
        let order = ShrineService.stocks(player: player).map { $0.id }
        XCTAssertEqual(order, ["shabti_gale", "anubis_tide", "sekhmet_gale"], "ready, then 65%, then 45%; an empty stock is not listed")
    }

    // MARK: - The battle

    /// Summoners War's waves of one monster at the found floor's depth: three
    /// waves of the form, the boss last at ×1.6 and at least its own grade,
    /// the floor's energy and power, no relic, and a stage the campaign's
    /// plumbing opens.
    func testAShrineIsThreeWavesOfItsFormAtTheFoundDepth() throws {
        let found = try stage(labyrinthB7)
        let shrine = try XCTUnwrap(ShrineService.stage(formID: "anubis_tide", foundOn: labyrinthB7))
        XCTAssertEqual(shrine.id, "shrine_anubis_tide")
        XCTAssertEqual(shrine.chapterID, ShrineService.chapterID)
        XCTAssertEqual(ShrineService.formID(of: shrine), "anubis_tide")
        XCTAssertTrue(ShrineService.isShrineStage(shrine))
        XCTAssertFalse(ShrineService.isSource(shrine))
        XCTAssertEqual(shrine.energyCost, found.energyCost)
        XCTAssertEqual(shrine.recommendedPower, found.recommendedPower)
        XCTAssertEqual(shrine.laterWaves.count, 2, "three waves")
        XCTAssertEqual(shrine.environment, .hallOfTwoTruths, "an Egyptian form's shrine stands in the Hall of Two Truths")

        let every: [EnemySpawn] = shrine.enemies + shrine.laterWaves.flatMap { $0 }
        let allTheForm: Bool = every.allSatisfy { $0.blueprintID == "anubis_tide" }
        XCTAssertEqual(every.count, 9)
        XCTAssertTrue(allTheForm, "every foe is the form")
        let template = try XCTUnwrap(found.enemies.first)
        let boss = try XCTUnwrap(shrine.laterWaves.last?.first)
        let bossMultiplier: Double = template.statMultiplier * ShrineService.bossMultiplier
        XCTAssertEqual(boss.statMultiplier, bossMultiplier, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(boss.stars, 4, "the boss keeps its own grade")
        XCTAssertEqual(boss.level, template.level)

        XCTAssertEqual(shrine.rewards.relicChance, 0, "a shrine pays no relic: its energy has a price")
        XCTAssertEqual(shrine.rewards.drachma, found.rewards.drachma)
        let essence: Double = shrine.rewards.essenceChances["essence_tide_mid"] ?? 0
        let scroll: Double = shrine.rewards.scrollChances[ScrollType.unknown.rawValue] ?? 0
        XCTAssertEqual(essence, ShrineService.essenceChance, accuracy: 1e-12, "the form's element's Mid")
        XCTAssertEqual(scroll, ShrineService.scrollChance, accuracy: 1e-12, "an Unknown Scroll now and then")
        XCTAssertEqual(shrine.rewards.firstClearDivinity, 0)

        let player = NewGame.create().player
        XCTAssertTrue(CampaignService.isUnlocked(shrine, player: player), "the campaign's plumbing opens it")
        XCTAssertEqual(StageDatabase.buildEnemies(for: shrine).count, 3)
        for wave in shrine.laterWaves {
            XCTAssertEqual(StageDatabase.buildEnemies(spawns: wave).count, 3)
        }
    }

    func testEachPantheonHasAShrinePlace() {
        XCTAssertEqual(ShrineService.home(of: .egyptian), .hallOfTwoTruths)
        XCTAssertEqual(ShrineService.home(of: .greek), .olympusGate)
        XCTAssertEqual(ShrineService.home(of: .norse), .yggdrasilRoots)
        XCTAssertEqual(ShrineService.home(of: .roman), .forumRome)
        XCTAssertEqual(ShrineService.home(of: .chinese), .peachGarden)
    }

    func testTheClockReadsMinutesAndSeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ShrineService.countdown(to: now.addingTimeInterval(3_600), now: now), "60:00")
        XCTAssertEqual(ShrineService.countdown(to: now.addingTimeInterval(2_538), now: now), "42:18")
        XCTAssertEqual(ShrineService.countdown(to: now.addingTimeInterval(-5), now: now), "00:00")
    }

    // MARK: - The save

    /// Both fields are Optional: a save without them writes no key and
    /// decodes as it always did; a save with them round-trips.
    func testShrinesAndPiecesRoundTripAndTolerateAbsence() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let plain = NewGame.create()
        let json = String(data: try encoder.encode(plain), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"shrines\""))
        XCTAssertFalse(json.contains("\"shrinePieces\""))
        let restoredPlain = try decoder.decode(SaveGame.self, from: try encoder.encode(plain))
        XCTAssertNil(restoredPlain.player.shrines)
        XCTAssertNil(restoredPlain.player.shrinePieces)

        var save = NewGame.create()
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        save.player.shrines = [HiddenShrine(blueprintID: "anubis_tide", foundOn: labyrinthB7, openedAt: opened,
                                            expiresAt: opened.addingTimeInterval(ShrineService.window), wins: 2)]
        save.player.shrinePieces = ["anubis_tide": 26, "sekhmet_gale": 45]
        let restored = try decoder.decode(SaveGame.self, from: try encoder.encode(save))
        XCTAssertEqual(restored.player.shrines?.first?.blueprintID, "anubis_tide")
        XCTAssertEqual(restored.player.shrines?.first?.foundOn, labyrinthB7)
        XCTAssertEqual(restored.player.shrines?.first?.wins, 2)
        XCTAssertEqual(restored.player.shrinePieces, ["anubis_tide": 26, "sekhmet_gale": 45])
    }
}
