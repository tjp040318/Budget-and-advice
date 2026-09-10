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

    // MARK: - Raid mechanics
    //
    // Every one of these builds the raid out of an ordinary enemy plus a
    // profile, rather than out of the shipped raid content, so a tuning change
    // to Apep or the Jötunn cannot quietly turn a mechanic's test green.

    /// The hero for a raid test: fast enough to act first, hard enough to live
    /// through the fight being measured.
    private func raidHero(level: Int = 40) -> ResolvedUnit {
        unit("anubis_umbra", level: level, stars: 6)
    }

    /// The boss: a sentinel, because it is slow (SPD 82, so the hero always
    /// acts first) and fat enough that no test accidentally kills it early.
    private func raidBoss(level: Int = 50) -> ResolvedUnit {
        unit("sandstone_sentinel", level: level, stars: 6)
    }

    private func raidEngine(
        _ profile: RaidBossProfile,
        seed: UInt64,
        heroLevel: Int = 40,
        bossLevel: Int = 50,
        mode: BattleMode = .campaign
    ) -> BattleEngine {
        BattleEngine(
            playerTeam: [raidHero(level: heroLevel)],
            opponentTeam: [raidBoss(level: bossLevel)],
            mode: mode,
            seed: seed,
            raidBosses: [0: profile]
        )
    }

    private func hasPassive(_ events: [BattleEvent], containing text: String, actor: UUID? = nil) -> Bool {
        events.contains { event in
            if case .passiveTriggered(let who, let name) = event {
                return name.contains(text) && (actor == nil || who == actor)
            }
            return false
        }
    }

    func testAFightWithNoProfileHasNoRaidInIt() {
        let engine = BattleEngine(
            playerTeam: [raidHero()], opponentTeam: [raidBoss()], mode: .simulation, seed: 4_242
        )
        engine.autoBattle = true
        let events = engine.start()

        XCTAssertTrue(engine.raidBossIDs.isEmpty)
        for combatant in engine.combatants {
            XCTAssertNil(engine.raidBarrier(for: combatant.id))
            XCTAssertNil(engine.raidWeakness(for: combatant.id))
            XCTAssertEqual(engine.raidEnrage(for: combatant.id), 1.0)
        }
        XCTAssertFalse(hasPassive(events, containing: "Barrier"))
        XCTAssertFalse(hasPassive(events, containing: "Enraged"))
        XCTAssertFalse(hasPassive(events, containing: "Weak to"))
    }

    func testBarrierSoaksEverythingUntilItBreaks() {
        // Half the boss's health in barrier: far more than one turn of damage,
        // so this measures the soak rather than the break.
        let engine = raidEngine(RaidBossProfile(barrierFraction: 0.5), seed: 5)
        _ = engine.start()
        guard let bossID = engine.raidBossIDs.first, let boss = engine.combatant(bossID) else {
            return XCTFail("The profile should have made a raid boss")
        }
        XCTAssertEqual(engine.raidBarrier(for: bossID)?.maximum ?? 0, boss.maxHealth * 0.5, accuracy: 1.0)

        guard let actor = engine.awaitingActor else { return XCTFail("The hero is faster and should be awaited") }
        let events = engine.submit(BattleAction(actorID: actor, skillSlot: 0, targetID: bossID))

        let absorbed = events.contains { event in
            if case .shieldAbsorbed(let target, let amount, _) = event { return target == bossID && amount > 0 }
            return false
        }
        XCTAssertTrue(absorbed, "The barrier should have soaked the hit")
        // Health untouched, barrier down: that is the whole point of the bar.
        XCTAssertEqual(engine.combatant(bossID)?.currentHealth, engine.combatant(bossID)?.maxHealth)
        guard let barrier = engine.raidBarrier(for: bossID) else { return XCTFail("Barrier should still be up") }
        XCTAssertLessThan(barrier.remaining, barrier.maximum)
    }

    func testBreakingTheBarrierCostsTheBossItsNextTurn() {
        // A barrier one hit wide, so the first strike takes it off.
        let engine = raidEngine(
            RaidBossProfile(barrierFraction: 0.001, barrierRegenTurns: 9, barrierStunTurns: 1),
            seed: 11
        )
        _ = engine.start()
        guard let bossID = engine.raidBossIDs.first, let actor = engine.awaitingActor else {
            return XCTFail("The hero should be awaited against a raid boss")
        }
        let events = engine.submit(BattleAction(actorID: actor, skillSlot: 0, targetID: bossID))

        XCTAssertTrue(hasPassive(events, containing: "Shattered", actor: bossID))
        let stunned = events.contains { event in
            if case .statusApplied(_, let target, let kind, _) = event { return target == bossID && kind == .stun }
            return false
        }
        XCTAssertTrue(stunned, "Breaking the barrier applies the stun straight, unrolled")
        let skipped = events.contains { event in
            if case .turnSkipped(let who, let reason) = event { return who == bossID && reason == .stun }
            return false
        }
        XCTAssertTrue(skipped, "The stun window has to actually cost the boss the turn")
        // And the overflow from the breaking hit still landed.
        XCTAssertLessThan(engine.combatant(bossID)!.currentHealth, engine.combatant(bossID)!.maxHealth)
    }

    func testBarrierComesBackAfterItsRegenTurns() {
        let engine = raidEngine(
            RaidBossProfile(barrierFraction: 0.001, barrierRegenTurns: 2, barrierStunTurns: 1),
            seed: 13
        )
        var events = engine.start()
        guard let bossID = engine.raidBossIDs.first else { return XCTFail("No raid boss") }

        // Turn count rather than a fixed number of submits: the two sides do
        // not alternate one for one, and the test is about the clock, not the
        // interleaving.
        var restored = false
        for _ in 0..<12 {
            if hasPassive(events, containing: "Restored", actor: bossID) { restored = true; break }
            guard let actor = engine.awaitingActor else { break }
            events = engine.submit(BattleAction(actorID: actor, skillSlot: 0, targetID: bossID))
        }
        XCTAssertTrue(restored, "The barrier should regenerate two boss turns after breaking")
        guard let barrier = engine.raidBarrier(for: bossID) else { return XCTFail("Barrier gone") }
        XCTAssertEqual(barrier.remaining, barrier.maximum, accuracy: 0.001)
    }

    func testTheGuardIsSummonedAndFeedsTheBoss() {
        let profile = RaidBossProfile(
            adds: [
                EnemySpawn(blueprintID: "shabti", level: 30, stars: 3),
                EnemySpawn(blueprintID: "shabti", level: 30, stars: 3)
            ],
            addInterval: 1,
            addDrain: 0.05
        )
        let engine = BattleEngine(
            playerTeam: [raidHero(level: 50)],
            opponentTeam: [raidBoss(level: 60)],
            mode: .simulation,
            seed: 4,
            raidBosses: [0: profile]
        )
        engine.autoBattle = true
        let events = engine.start()
        guard let bossID = engine.raidBossIDs.first else { return XCTFail("No raid boss") }

        var summoned: [UUID] = []
        for event in events {
            if case .waveStarted(_, _, let arrivals) = event { summoned += arrivals.map(\.id) }
        }
        XCTAssertFalse(summoned.isEmpty, "The boss should have called its guard")
        XCTAssertTrue(hasPassive(events, containing: "Calls", actor: bossID))

        let fed = events.contains { event in
            if case .healed(let source, let target, let amount, _) = event {
                return target == bossID && summoned.contains(source) && amount > 0
            }
            return false
        }
        XCTAssertTrue(fed, "A minion left alive has to be healing the boss")

        // Only ever topped back up to the guard's size, never piled higher.
        let opponentsAlive = engine.combatants.filter { $0.side == .opponent && $0.isAlive }.count
        XCTAssertLessThanOrEqual(opponentsAlive, 3)
    }

    func testKillingTheBossTakesItsGuardWithIt() {
        // No drain, so the boss dies on schedule; the guard is only there to be
        // left standing when it does.
        let profile = RaidBossProfile(
            adds: [EnemySpawn(blueprintID: "shabti", level: 1, stars: 1)],
            addInterval: 1,
            addDrain: 0
        )
        let engine = BattleEngine(
            playerTeam: [raidHero(level: 60)],
            opponentTeam: [unit("sandstone_sentinel", level: 30, stars: 4)],
            mode: .campaign,
            seed: 21,
            raidBosses: [0: profile]
        )
        var events = engine.start()
        guard let bossID = engine.raidBossIDs.first else { return XCTFail("No raid boss") }

        var summoned: Set<UUID> = []
        for _ in 0..<60 {
            for event in events {
                if case .waveStarted(_, _, let arrivals) = event { summoned.formUnion(arrivals.map(\.id)) }
            }
            guard let actor = engine.awaitingActor else { break }
            // Every hit into the boss, never into the guard: that is what
            // leaves minions standing at the moment the boss falls.
            events = engine.submit(BattleAction(actorID: actor, skillSlot: 0, targetID: bossID))
        }

        XCTAssertFalse(summoned.isEmpty, "The boss should have called a guard before it died")
        XCTAssertFalse(engine.combatant(bossID)?.isAlive ?? true, "The boss should be dead")
        for minionID in summoned {
            XCTAssertFalse(engine.combatant(minionID)?.isAlive ?? true, "A summon outlived its boss")
        }
        XCTAssertEqual(engine.result?.outcome, .victory)
    }

    func testEnrageStepsOnTheBattleClock() {
        let engine = raidEngine(
            RaidBossProfile(enrageTurn: 2, enrageMultiplier: 2.5),
            seed: 17
        )
        var events = engine.start()
        guard let bossID = engine.raidBossIDs.first else { return XCTFail("No raid boss") }
        XCTAssertEqual(engine.raidEnrage(for: bossID), 1.0, "Nothing before the threshold")

        guard let actor = engine.awaitingActor else { return XCTFail("The hero should be awaited") }
        events = engine.submit(BattleAction(actorID: actor, skillSlot: 0, targetID: bossID))

        XCTAssertTrue(hasPassive(events, containing: "Enraged", actor: bossID))
        XCTAssertEqual(engine.raidEnrage(for: bossID), 2.5, accuracy: 0.001)
    }

    func testEnrageMultipliesWhatTheBossDeals() {
        func damageToHero(enraged: Bool) -> Double {
            let profile = enraged
                ? RaidBossProfile(enrageTurn: 1, enrageMultiplier: 3.0)
                : RaidBossProfile()
            let engine = BattleEngine(
                playerTeam: [raidHero(level: 50)],
                opponentTeam: [raidBoss(level: 50)],
                mode: .simulation,
                seed: 77,
                raidBosses: [0: profile]
            )
            engine.autoBattle = true
            let events = engine.start()
            let heroID = engine.combatants.first(where: { $0.side == .player })!.id
            for event in events {
                if case .damage(_, let target, let amount, _, _, _, _, _, _) = event, target == heroID {
                    return amount
                }
            }
            return 0
        }

        let plain = damageToHero(enraged: false)
        let enraged = damageToHero(enraged: true)
        XCTAssertGreaterThan(plain, 0)
        // Same seed, and the enrage multiplier consumes no randomness of its
        // own, so the first hit of the fight is the same roll times three.
        XCTAssertEqual(enraged, plain * 3.0, accuracy: 1.0)
    }

    func testTheOpenElementHitsHarderAndReadsAsAnAdvantage() {
        func firstHit(weaknessMultiplier: Double) -> (amount: Double, matchup: Element.Matchup) {
            // Anubis is Umbra and the sentinel is Ember: neutral on the wheel,
            // so anything that changes here is the raid's doing.
            let profile = RaidBossProfile(
                weaknesses: [.umbra],
                weaknessMultiplier: weaknessMultiplier,
                offElementMultiplier: 1.0
            )
            let engine = raidEngine(profile, seed: 31)
            _ = engine.start()
            let bossID = engine.raidBossIDs.first!
            let events = engine.submit(
                BattleAction(actorID: engine.awaitingActor!, skillSlot: 0, targetID: bossID)
            )
            for event in events {
                if case .damage(_, let target, let amount, _, _, let matchup, _, _, _) = event, target == bossID {
                    return (amount, matchup)
                }
            }
            return (0, .neutral)
        }

        let neutral = firstHit(weaknessMultiplier: 1.0)
        let open = firstHit(weaknessMultiplier: 2.0)
        XCTAssertGreaterThan(neutral.amount, 0)
        XCTAssertEqual(open.amount, neutral.amount * 2.0, accuracy: 1.0)
        XCTAssertEqual(open.matchup, .advantage, "The open element has to read green")
    }

    func testTheOffElementIsPunished() {
        let profile = RaidBossProfile(
            weaknesses: [.tide],          // and the hero is Umbra
            weaknessMultiplier: 1.7,
            offElementMultiplier: 0.5
        )
        let engine = raidEngine(profile, seed: 31)
        _ = engine.start()
        let bossID = engine.raidBossIDs.first!
        let events = engine.submit(
            BattleAction(actorID: engine.awaitingActor!, skillSlot: 0, targetID: bossID)
        )
        var reduced: Double = 0
        for event in events {
            if case .damage(_, let target, let amount, _, _, _, _, _, _) = event, target == bossID {
                reduced = amount
                break
            }
        }

        let plain = raidEngine(RaidBossProfile(), seed: 31)
        _ = plain.start()
        let plainBossID = plain.raidBossIDs.first!
        let plainEvents = plain.submit(
            BattleAction(actorID: plain.awaitingActor!, skillSlot: 0, targetID: plainBossID)
        )
        var full: Double = 0
        for event in plainEvents {
            if case .damage(_, let target, let amount, _, _, _, _, _, _) = event, target == plainBossID {
                full = amount
                break
            }
        }

        XCTAssertGreaterThan(full, 0)
        XCTAssertEqual(reduced, full * 0.5, accuracy: 1.0)
    }

    func testTheWeaknessRotatesOnTheBossTurns() {
        let engine = raidEngine(
            RaidBossProfile(weaknesses: [.tide, .gale], weaknessInterval: 1),
            seed: 23
        )
        _ = engine.start()
        guard let bossID = engine.raidBossIDs.first else { return XCTFail("No raid boss") }
        XCTAssertEqual(engine.raidWeakness(for: bossID), .tide, "The opening weakness is the first in the cycle")

        var rotated = false
        for _ in 0..<6 {
            guard let actor = engine.awaitingActor else { break }
            _ = engine.submit(BattleAction(actorID: actor, skillSlot: 0, targetID: bossID))
            if engine.raidWeakness(for: bossID) == .gale { rotated = true; break }
        }
        XCTAssertTrue(rotated, "The cycle should move on as the boss takes its turns")
    }

    // MARK: - The raid content

    func testShippedRaidsAreWellFormed() {
        XCTAssertEqual(StageDatabase.raids.count, 2)
        for raid in StageDatabase.raids {
            XCTAssertEqual(raid.stage.chapterID, raid.id, "A raid's clear is recorded under its own id")
            XCTAssertNotNil(StageDatabase.stage(raid.stage.id), "A raid stage must be findable by id")
            XCTAssertTrue(raid.stage.isBoss)

            guard let profile = raid.profile else { return XCTFail("\(raid.id) has no raid profile") }
            XCTAssertGreaterThan(profile.barrierFraction, 0)
            XCTAssertGreaterThan(profile.enrageTurn, 0)
            XCTAssertGreaterThan(profile.weaknesses.count, 1, "A single weakness never rotates")
            XCTAssertEqual(Set(profile.weaknesses).count, profile.weaknesses.count, "A repeat in the cycle is a typo")
            for spawn in profile.adds {
                XCTAssertNotNil(UnitDatabase.blueprint(spawn.blueprintID), "\(raid.id) calls unknown \(spawn.blueprintID)")
            }
            // The profile has to survive a round trip: it rides on `EnemySpawn`,
            // which is Codable, and a stage is decoded from the bundle.
            let coded = try? JSONEncoder().encode(profile)
            XCTAssertNotNil(coded)
            XCTAssertEqual(try? JSONDecoder().decode(RaidBossProfile.self, from: coded ?? Data()), profile)

            // And the engine has to find the boss where the content says it is.
            let profiles = StageDatabase.raidProfiles(for: raid.stage)
            XCTAssertEqual(profiles.count, 1)
            XCTAssertNotNil(profiles[0])
        }
    }

    func testRaidsAreNotOnTheCampaignMap() {
        for chapter in StageDatabase.chapters {
            XCTAssertNil(StageDatabase.raid(chapter.id), "A raid must not be a campaign chapter")
        }
        for raid in StageDatabase.raids {
            XCTAssertTrue(StageDatabase.allStages.contains(where: { $0.id == raid.stage.id }))
        }
    }
}
