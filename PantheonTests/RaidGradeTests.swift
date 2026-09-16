import XCTest
@testable import Pantheon

/// The raid grade is the first thing in the game a fight can be got better
/// at, so the ladder's SHAPE is what these pin, not its numbers: a faster
/// kill never grades lower, a kill always outranks a non-kill, the aether
/// climbs with the grade and the pure kind needs a kill. The numbers
/// themselves are mirrored in `tools/balance.py --grades`.
final class RaidGradeTests: XCTestCase {

    /// A profile with the serpent's clock and none of its other mechanics,
    /// so a tuning change to Apep cannot turn a ladder test green or red.
    private var profile: RaidBossProfile { RaidBossProfile(enrageTurn: 60, enrageMultiplier: 1.8) }

    private func result(_ outcome: BattleOutcome, turns: Int, share: Double?) -> BattleResult {
        BattleResult(
            outcome: outcome, turnsTaken: turns, survivorFraction: 1,
            totalDamageDealt: 0, totalDamageTaken: 0, seed: 1, raidShare: share
        )
    }

    private func grade(_ result: BattleResult) -> RaidGrade {
        RaidGradeService.grade(result: result, profile: profile)
    }

    // MARK: - The ladder

    func testAKillIsGradedOnItsPaceAndIsNeverBelowB() {
        // The bars are fractions of the enrage turn — 60 here, so SSS by 42,
        // SS by 51, S by 60, A by 78 — and the card prints the same numbers.
        XCTAssertEqual(RaidGradeService.turnsAllowed(for: .sss, profile: profile), 42)
        XCTAssertEqual(RaidGradeService.turnsAllowed(for: .ss, profile: profile), 51)
        XCTAssertEqual(RaidGradeService.turnsAllowed(for: .s, profile: profile), 60)
        XCTAssertEqual(RaidGradeService.turnsAllowed(for: .a, profile: profile), 78)
        XCTAssertEqual(grade(result(.victory, turns: 42, share: 1)), .sss)
        XCTAssertEqual(grade(result(.victory, turns: 43, share: 1)), .ss)
        XCTAssertEqual(grade(result(.victory, turns: 51, share: 1)), .ss)
        XCTAssertEqual(grade(result(.victory, turns: 52, share: 1)), .s)
        XCTAssertEqual(grade(result(.victory, turns: 60, share: 1)), .s, "a kill before it enrages is an S")
        XCTAssertEqual(grade(result(.victory, turns: 61, share: 1)), .a)
        XCTAssertEqual(grade(result(.victory, turns: 78, share: 1)), .a)
        XCTAssertEqual(grade(result(.victory, turns: 79, share: 1)), .b)
        XCTAssertEqual(grade(result(.victory, turns: 150, share: 1)), .b)

        // Monotone: a faster kill never grades lower, and every kill is a kill.
        var last = RaidGrade.sss
        for turns in 1...150 {
            let earned = grade(result(.victory, turns: turns, share: 1))
            XCTAssertLessThanOrEqual(earned, last, "turn \(turns) graded above turn \(turns - 1)")
            XCTAssertTrue(earned.isKill, "turn \(turns)")
            last = earned
        }
    }

    func testAnythingShortOfAKillIsGradedOnTheShareAndNeverReachesB() {
        for outcome in [BattleOutcome.defeat, .draw] {
            XCTAssertEqual(grade(result(outcome, turns: 40, share: 1.0)), .c, "\(outcome)")
            XCTAssertEqual(grade(result(outcome, turns: 40, share: 0.65)), .c, "\(outcome)")
            XCTAssertEqual(grade(result(outcome, turns: 40, share: 0.30)), .d, "\(outcome)")
            XCTAssertEqual(grade(result(outcome, turns: 40, share: 0.10)), .f, "\(outcome)")
            XCTAssertEqual(grade(result(outcome, turns: 40, share: nil)), .f, "no share at all is an F")
            // However fast it went, a fight the boss survived stays under B.
            for turns in [1, 20, 150] {
                for share in stride(from: 0.0, through: 1.0, by: 0.05) {
                    let earned = grade(result(outcome, turns: turns, share: share))
                    XCTAssertFalse(earned.isKill)
                    XCTAssertLessThan(earned, .b)
                }
            }
        }
    }

    func testTheLadderReadsInOrder() {
        XCTAssertEqual(RaidGrade.allCases.map(\.label), ["F", "D", "C", "B", "A", "S", "SS", "SSS"])
        XCTAssertLessThan(RaidGrade.c, .b)
        XCTAssertLessThan(RaidGrade.s, .sss)
        XCTAssertEqual(RaidGrade.allCases.filter(\.isKill).count, 5, "B, A, S, SS and SSS are kills")
    }

    func testAProfileWithNoEnrageStillGradesOnAPace() {
        let never = RaidBossProfile()
        XCTAssertEqual(never.enrageTurn, 0)
        XCTAssertEqual(RaidGradeService.enrageBar(never), RaidGradeService.defaultEnrageTurn)
        XCTAssertEqual(RaidGradeService.grade(result: result(.victory, turns: 30, share: 1), profile: never), .sss)
        XCTAssertEqual(RaidGradeService.turnsAllowed(for: .s, profile: never), RaidGradeService.defaultEnrageTurn)
        // The serpent's own bars, the ones its card prints.
        if let apep = StageDatabase.raid("raid_apep")?.profile {
            XCTAssertEqual(apep.enrageTurn, 65)
            XCTAssertEqual(RaidGradeService.turnsAllowed(for: .sss, profile: apep), 45)
            XCTAssertEqual(RaidGradeService.turnsAllowed(for: .ss, profile: apep), 55)
            XCTAssertEqual(RaidGradeService.turnsAllowed(for: .s, profile: apep), 65)
            XCTAssertEqual(RaidGradeService.turnsAllowed(for: .a, profile: apep), 84)
        } else {
            XCTFail("The serpent's raid should ship with a profile")
        }
        XCTAssertNil(RaidGradeService.turnsAllowed(for: .b, profile: never), "any kill is a B; there is no bar")
    }

    // MARK: - What a grade pays

    func testAetherClimbsTheLadderAndPureAetherNeedsAKill() {
        var lastElemental = -1
        var lastPure = -1
        for grade in RaidGrade.allCases {
            let pay = RaidGradeService.aether(for: grade)
            XCTAssertGreaterThanOrEqual(pay.elemental, lastElemental, "\(grade.label)")
            XCTAssertGreaterThanOrEqual(pay.pure, lastPure, "\(grade.label)")
            XCTAssertEqual(pay.pure > 0, grade.isKill, "\(grade.label): pure aether comes from a kill and only a kill")
            lastElemental = pay.elemental
            lastPure = pay.pure
        }
        XCTAssertEqual(RaidGradeService.aether(for: .f).elemental, 0, "an F pays nothing, so a forfeit farms nothing")
        XCTAssertGreaterThan(RaidGradeService.aether(for: .d).elemental, 0, "a D pays something, so a lost raid is still worth entering")
    }

    func testTheQualityFloorLiftsOnlyAtTheTop() {
        XCTAssertNil(RaidGradeService.qualityFloor(for: .b))
        XCTAssertNil(RaidGradeService.qualityFloor(for: .a))
        XCTAssertEqual(RaidGradeService.qualityFloor(for: .s), .hero)
        XCTAssertEqual(RaidGradeService.qualityFloor(for: .ss), .hero)
        XCTAssertEqual(RaidGradeService.qualityFloor(for: .sss), .legend)
    }

    func testEveryShippedRaidHasAnElementAndAClock() {
        for raid in StageDatabase.raids {
            guard let profile = raid.profile else { return XCTFail("\(raid.id) has no profile") }
            XCTAssertGreaterThan(profile.enrageTurn, 0, "\(raid.id): the pace is measured against the enrage")
            let bossElement = raid.stage.enemies.first(where: { $0.raid != nil })
                .flatMap { UnitDatabase.blueprint($0.blueprintID)?.element }
            XCTAssertEqual(RaidGradeService.element(of: raid), bossElement, "\(raid.id): the aether is the boss's own element")
        }
    }

    // MARK: - Settling a run

    func testARaidPaysItsAetherKillOrNotAndKeepsTheBestGrade() throws {
        let raid = try XCTUnwrap(StageDatabase.raid("raid_apep"))
        let element = Aether.id(for: RaidGradeService.element(of: raid))
        var player = Player()
        var rng = SeededRandom(seed: 7)

        // A wipe at half health: a D, the elemental aether and nothing else.
        let loss = CampaignService.applyRewards(
            stage: raid.stage, result: result(.defeat, turns: 30, share: 0.5), player: &player, rng: &rng
        )
        XCTAssertEqual(loss.raidGrade, .d)
        XCTAssertEqual(loss.aetherEarned[element], RaidGradeService.aether(for: .d).elemental)
        XCTAssertNil(loss.aetherEarned[Aether.pure])
        XCTAssertTrue(loss.relicsEarned.isEmpty)
        XCTAssertEqual(loss.drachma, 0)
        XCTAssertEqual(Aether.count(element, player: player), RaidGradeService.aether(for: .d).elemental)
        XCTAssertEqual(RaidGradeService.bestGrade(for: raid, player: player), .d)

        // A kill on turn 30, well inside the serpent's clock: an SSS, both
        // kinds of aether, and the raid's relic lifted to Legend.
        let heldBefore = Aether.count(element, player: player)
        let win = CampaignService.applyRewards(
            stage: raid.stage, result: result(.victory, turns: 30, share: 1), player: &player, rng: &rng
        )
        XCTAssertEqual(win.raidGrade, .sss)
        XCTAssertEqual(win.aetherEarned[element], RaidGradeService.aether(for: .sss).elemental)
        XCTAssertEqual(win.aetherEarned[Aether.pure], RaidGradeService.aether(for: .sss).pure)
        XCTAssertEqual(win.relicsEarned.count, 1)
        XCTAssertEqual(win.relicsEarned.first?.resolvedQuality, .legend, "an SSS lifts the raid's relic to Legend")
        XCTAssertEqual(Aether.count(element, player: player), heldBefore + RaidGradeService.aether(for: .sss).elemental)
        XCTAssertEqual(Aether.count(Aether.pure, player: player), RaidGradeService.aether(for: .sss).pure)
        XCTAssertEqual(RaidGradeService.bestGrade(for: raid, player: player), .sss)

        // A later, slower kill pays its own grade and does not lower the mark.
        let slow = CampaignService.applyRewards(
            stage: raid.stage, result: result(.victory, turns: 140, share: 1), player: &player, rng: &rng
        )
        XCTAssertEqual(slow.raidGrade, .b)
        XCTAssertEqual(RaidGradeService.bestGrade(for: raid, player: player), .sss)
    }

    func testAnOrdinaryStageHasNoGradeAndPaysNoAether() throws {
        let stage = try XCTUnwrap(StageDatabase.stage("duat_1_1"))
        var player = Player()
        var rng = SeededRandom(seed: 1)
        let outcome = CampaignService.applyRewards(
            stage: stage, result: result(.victory, turns: 10, share: nil), player: &player, rng: &rng
        )
        XCTAssertNil(outcome.raidGrade)
        XCTAssertTrue(outcome.aetherEarned.isEmpty)
        XCTAssertNil(player.aether)
        XCTAssertNil(player.raidGrades)
    }

    // MARK: - The save

    func testTheNewFieldsAreOptionalSoAnOldSaveStillDecodes() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // A fresh save writes no key for either, exactly as an old save has none.
        let fresh = SaveGame(player: Player(), rngSeed: 1)
        let json = String(data: try encoder.encode(fresh), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"aether\""))
        XCTAssertFalse(json.contains("\"raidGrades\""))
        let restored = try decoder.decode(SaveGame.self, from: try encoder.encode(fresh))
        XCTAssertNil(restored.player.aether)
        XCTAssertNil(restored.player.raidGrades)

        // And a save that has them keeps them.
        var player = Player()
        Aether.add("aether_gale", 9, player: &player)
        Aether.add(Aether.pure, 2, player: &player)
        player.raidGrades = ["raid_jotunn": RaidGrade.ss.rawValue]
        let back = try decoder.decode(SaveGame.self, from: try encoder.encode(SaveGame(player: player, rngSeed: 2)))
        XCTAssertEqual(back.player.aether?["aether_gale"], 9)
        XCTAssertEqual(back.player.aether?[Aether.pure], 2)
        XCTAssertEqual(back.player.raidGrades?["raid_jotunn"], "ss")

        // A result written before the share existed decodes with none.
        let old = #"{"outcome":"victory","turnsTaken":12,"survivorFraction":1,"totalDamageDealt":100,"totalDamageTaken":50,"seed":9}"#
        let result = try decoder.decode(BattleResult.self, from: Data(old.utf8))
        XCTAssertNil(result.raidShare)
    }

    func testAetherNamesAndIds() {
        XCTAssertEqual(Aether.id(for: .ember), "aether_ember")
        XCTAssertEqual(Aether.element(of: "aether_tide"), .tide)
        XCTAssertNil(Aether.element(of: Aether.pure))
        XCTAssertNil(Aether.element(of: "essence_ember_mid"))
        XCTAssertEqual(Aether.name(for: "aether_umbra"), "Umbra Aether")
        XCTAssertEqual(Aether.name(for: Aether.pure), "Pure Aether")
        XCTAssertTrue(Aether.isAether(Aether.pure))
        XCTAssertFalse(Aether.isAether("drachma"))
    }
}
