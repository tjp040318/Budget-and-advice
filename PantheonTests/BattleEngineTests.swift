import XCTest
@testable import Pantheon

/// The engine is the part of the game that must never drift, because a balance
/// change that silently alters an existing battle is invisible until players
/// find it. These tests pin the parts that matter: determinism, the element
/// wheel, the defence curve, turn order, and that a battle always terminates.
final class BattleEngineTests: XCTestCase {

    // MARK: - Helpers

    private func unit(
        _ blueprintID: String,
        level: Int = 30,
        stars: Int = 5,
        awakened: Bool = false
    ) -> ResolvedUnit {
        let blueprint = UnitDatabase.blueprint(blueprintID)!
        let unit = Unit(blueprint: blueprint, level: level, stars: stars, awakened: awakened)
        return ProgressionService.resolve(unit, blueprint: blueprint, equipped: [])
    }

    // MARK: - Determinism

    func testSameSeedProducesSameResult() {
        let player = [unit("anubis_umbra")]
        let enemies = [unit("ammit", level: 20, stars: 4), unit("serpopard", level: 20, stars: 3)]

        let first = BattleEngine.simulate(playerTeam: player, opponentTeam: enemies, seed: 12_345)
        let second = BattleEngine.simulate(playerTeam: player, opponentTeam: enemies, seed: 12_345)

        XCTAssertEqual(first.outcome, second.outcome)
        XCTAssertEqual(first.turnsTaken, second.turnsTaken)
        XCTAssertEqual(first.totalDamageDealt, second.totalDamageDealt, accuracy: 0.0001)
    }

    func testDifferentSeedsDiverge() {
        let player = [unit("anubis_umbra")]
        let enemies = [unit("apep", level: 30, stars: 5)]

        let results = (0..<8).map {
            BattleEngine.simulate(playerTeam: player, opponentTeam: enemies, seed: UInt64($0 + 1))
        }
        // Not every seed has to differ, but eight identical damage totals would
        // mean the RNG is not actually being consumed.
        let distinct = Set(results.map { Int($0.totalDamageDealt) })
        XCTAssertGreaterThan(distinct.count, 1)
    }

    // MARK: - Element wheel

    func testElementWheelIsACycle() {
        XCTAssertEqual(Element.ember.matchup(against: .gale), .advantage)
        XCTAssertEqual(Element.gale.matchup(against: .tide), .advantage)
        XCTAssertEqual(Element.tide.matchup(against: .ember), .advantage)

        XCTAssertEqual(Element.gale.matchup(against: .ember), .disadvantage)
        XCTAssertEqual(Element.tide.matchup(against: .gale), .disadvantage)
        XCTAssertEqual(Element.ember.matchup(against: .tide), .disadvantage)

        XCTAssertEqual(Element.radiance.matchup(against: .umbra), .advantage)
        XCTAssertEqual(Element.umbra.matchup(against: .radiance), .advantage)
        XCTAssertEqual(Element.radiance.matchup(against: .ember), .neutral)
        XCTAssertEqual(Element.ember.matchup(against: .ember), .neutral)
    }

    // MARK: - Damage

    func testDefenseReducesDamageWithDiminishingReturns() {
        let low = DamageCalculator.mitigation(defense: 200, ignore: 0)
        let mid = DamageCalculator.mitigation(defense: 800, ignore: 0)
        let high = DamageCalculator.mitigation(defense: 1_600, ignore: 0)

        XCTAssertGreaterThan(low, mid)
        XCTAssertGreaterThan(mid, high)
        // Doubling defence must not halve damage — that is the whole point of
        // the curve, and it is what keeps DEF stacking from being mandatory.
        XCTAssertGreaterThan(high, mid / 2)
    }

    func testDefenseIgnoreRaisesDamage() {
        let normal = DamageCalculator.mitigation(defense: 1_000, ignore: 0)
        let pierced = DamageCalculator.mitigation(defense: 1_000, ignore: 0.30)
        XCTAssertGreaterThan(pierced, normal)
    }

    // MARK: - Turn order

    func testFasterUnitActsFirst() {
        let fast = unit("serpopard", level: 30, stars: 4)   // base SPD 116
        let slow = unit("apep", level: 30, stars: 5) // base SPD 92
        XCTAssertGreaterThan(fast.stats.spd, slow.stats.spd)

        let engine = BattleEngine(
            playerTeam: [fast], opponentTeam: [slow], mode: .simulation, seed: 7
        )
        engine.autoBattle = true
        let events = engine.start()

        let firstTurn = events.compactMap { event -> UUID? in
            if case .turnBegan(let actor, _) = event { return actor }
            return nil
        }.first

        let fastCombatant = engine.combatants.first { $0.side == .player }
        XCTAssertEqual(firstTurn, fastCombatant?.id)
    }

    // MARK: - Termination

    func testBattleAlwaysTerminates() {
        // Two tanky, low-damage teams are the worst case for a stall.
        let a = [unit("sandstone_sentinel", level: 40, stars: 6), unit("sun_scarab", level: 40, stars: 6)]
        let b = [unit("sandstone_sentinel", level: 40, stars: 6), unit("sun_scarab", level: 40, stars: 6)]

        for seed in UInt64(1)...UInt64(10) {
            let result = BattleEngine.simulate(playerTeam: a, opponentTeam: b, seed: seed)
            XCTAssertLessThanOrEqual(result.turnsTaken, BattleEngine.maxTurns + 1)
            XCTAssertNotNil(BattleOutcome(rawValue: result.outcome.rawValue))
        }
    }

    func testDeadUnitsStopActing() {
        let strong = [unit("anubis_umbra", level: 60, stars: 6, awakened: true)]
        let weak = [unit("shabti", level: 1, stars: 1)]

        let engine = BattleEngine(playerTeam: strong, opponentTeam: weak, mode: .simulation, seed: 99)
        engine.autoBattle = true
        let events = engine.start()

        var deathIndex: Int?
        var deadID: UUID?
        for (index, event) in events.enumerated() {
            if case .defeated(let target) = event {
                deathIndex = index
                deadID = target
                break
            }
        }
        guard let deathIndex, let deadID else {
            return XCTFail("The weak unit should have died")
        }

        // Nobody dead should begin a turn afterwards.
        for event in events[deathIndex...] {
            if case .turnBegan(let actor, _) = event {
                XCTAssertNotEqual(actor, deadID)
            }
        }
    }

    // MARK: - The Anubis kit

    func testBasicAttackLandsEveryHit() {
        let anubis = unit("anubis_umbra", level: 40, stars: 6)
        let target = unit("sandstone_sentinel", level: 40, stars: 6)

        let engine = BattleEngine(playerTeam: [anubis], opponentTeam: [target], mode: .campaign, seed: 5)
        _ = engine.start()

        guard let actorID = engine.awaitingActor else {
            return XCTFail("Anubis is faster and should be awaiting input")
        }

        // The returned stream also carries the opponent's reply, so count only
        // the strikes Anubis himself landed.
        let events = engine.submit(BattleAction(actorID: actorID, skillSlot: 0, targetID: nil))
        let anubisHits = events.filter { event in
            if case .damage(let source, _, _, _, _, _, _, _, _) = event { return source == actorID }
            return false
        }
        XCTAssertEqual(anubisHits.count, 2, "Jackal's Due strikes twice")
    }

    func testUltimateGoesOnCooldown() {
        let anubis = unit("anubis_umbra", level: 40, stars: 6)
        let targets = [unit("serpopard", level: 40, stars: 6), unit("sun_scarab", level: 40, stars: 6)]

        let engine = BattleEngine(playerTeam: [anubis], opponentTeam: targets, mode: .campaign, seed: 11)
        _ = engine.start()
        guard let actorID = engine.awaitingActor else { return XCTFail("Anubis should act first or be awaited") }

        let events = engine.submit(BattleAction(actorID: actorID, skillSlot: 2, targetID: nil))
        let cooldownStarted = events.contains { event in
            if case .cooldownStarted(_, let slot, let turns) = event { return slot == 2 && turns == 5 }
            return false
        }
        XCTAssertTrue(cooldownStarted)
        XCTAssertFalse(engine.combatants[0].isSkillReady(2))
    }

    func testAwakenedPassiveIsHiddenUntilAwakened() {
        let base = unit("anubis_umbra", level: 40, stars: 6, awakened: false)
        let awakened = unit("anubis_umbra", level: 40, stars: 6, awakened: true)

        XCTAssertFalse(base.skills.contains { $0.isPassive })
        XCTAssertTrue(awakened.skills.contains { $0.id == "anubis_umbra_passive" })
        XCTAssertGreaterThan(awakened.stats.spd, base.stats.spd)
    }

    func testLeaderSkillAppliesToMatchingPantheonOnly() {
        // The Fire variant leads on ATK, which is the easiest bonus to measure.
        let leader = unit("anubis_ember", level: 40, stars: 6)
        let ally = unit("serpopard", level: 40, stars: 6)   // Egyptian, so it qualifies

        let engine = BattleEngine(
            playerTeam: [leader, ally],
            opponentTeam: [unit("sun_scarab", level: 40, stars: 6)],
            mode: .campaign,
            seed: 3
        )
        let boosted = engine.combatants.first { $0.blueprintID == "serpopard" && $0.side == .player }
        XCTAssertNotNil(boosted)
        // +33% ATK from the leader skill.
        XCTAssertEqual(boosted!.baseStats.atk, (ally.stats.atk * 1.33).rounded(), accuracy: 2.0)
    }
}
