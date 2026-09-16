import XCTest
@testable import Pantheon

/// Pantheon resonance: what a lineup lights by who is in it. These pin the
/// reading of a lineup, the numbers a rank II lineup carries into battle
/// (and that a campaign wave never does), and every hook — read off the
/// events a real fight produces. The size of each rank is measured in
/// `tools/balance.py --resonance`.
final class ResonanceTests: XCTestCase {

    // MARK: - Helpers

    /// `count` units of a pantheon, led by one with no leader skill so a
    /// mode's leader-skill rule cannot masquerade as a resonance.
    private func team(_ pantheon: Pantheon, count: Int, level: Int, stars: Int) -> [ResolvedUnit] {
        let pool = UnitDatabase.all.filter { $0.pantheon == pantheon }
        let leader = pool.first(where: { $0.leaderSkill == nil }) ?? pool[0]
        var picked = [leader]
        for blueprint in pool where blueprint.id != leader.id && picked.count < count {
            picked.append(blueprint)
        }
        return picked.map { blueprint in
            ProgressionService.resolve(Unit(blueprint: blueprint, level: level, stars: stars), blueprint: blueprint, equipped: [])
        }
    }

    private func fighter(_ id: String, level: Int, stars: Int) -> ResolvedUnit {
        let blueprint = UnitDatabase.blueprint(id)!
        return ProgressionService.resolve(Unit(blueprint: blueprint, level: level, stars: stars), blueprint: blueprint, equipped: [])
    }

    /// A sturdy unit of no leader skill and no pantheon of interest, to
    /// stand on the far side of a fight.
    private func bag(excluding pantheon: Pantheon, level: Int = 60, stars: Int = 6) -> ResolvedUnit {
        let blueprint = UnitDatabase.all.first(where: { $0.leaderSkill == nil && $0.pantheon != pantheon })!
        return ProgressionService.resolve(Unit(blueprint: blueprint, level: level, stars: stars), blueprint: blueprint, equipped: [])
    }

    /// The serpent at the raid's own strength — 6★, level 60, twice its
    /// stats, built the way a stage builds it — for the tests that need a
    /// team of three to FALL. A plain `fighter("apep", level: 60, stars: 5)`
    /// is a level over a 5★'s cap and half the raid's serpent; against
    /// three level-30 5★s with a healer among them it killed nobody in a
    /// whole fight (run 162), and a resonance that answers a fall cannot be
    /// seen in a fight with none.
    private func titan() -> ResolvedUnit {
        let spawn = EnemySpawn(blueprintID: "apep", level: 60, stars: 6, statMultiplier: 2.0)
        return StageDatabase.buildEnemies(spawns: [spawn]).first!
    }

    private func fight(player: [ResolvedUnit], opponent: [ResolvedUnit], seed: UInt64) -> (events: [BattleEvent], engine: BattleEngine) {
        let engine = BattleEngine(playerTeam: player, opponentTeam: opponent, mode: .campaign, seed: seed)
        engine.autoBattle = true
        return (engine.start(), engine)
    }

    private func announcements(_ events: [BattleEvent], named name: String) -> Int {
        events.filter {
            if case .passiveTriggered(_, let announced) = $0 { return announced == name }
            return false
        }.count
    }

    // MARK: - Reading a lineup

    func testAPairLightsRankOneThreeLightRankTwoAndFourPantheonsTheConcord() {
        let egypt = UnitDatabase.all.filter { $0.pantheon == .egyptian }
        let greece = UnitDatabase.all.filter { $0.pantheon == .greek }
        let norse = UnitDatabase.all.filter { $0.pantheon == .norse }
        let rome = UnitDatabase.all.filter { $0.pantheon == .roman }

        XCTAssertTrue(ResonanceService.active(for: [egypt[0], greece[0]]).isEmpty, "one of each lights nothing")
        let pair = ResonanceService.active(for: [egypt[0], egypt[1], greece[0]])
        XCTAssertEqual(pair.map(\.kind), [.weighingOfHearts])
        XCTAssertEqual(pair.first?.rank, .one)
        XCTAssertEqual(pair.first?.members, 2)
        let trio = ResonanceService.active(for: [egypt[0], egypt[1], egypt[2], greece[0], greece[1]])
        XCTAssertEqual(trio.map(\.kind), [.weighingOfHearts, .olympianHubris], "the stronger first")
        XCTAssertEqual(trio.map(\.rank), [.two, .one], "a five can carry a II and a I at once")
        XCTAssertEqual(ResonanceService.active(for: [egypt[0], egypt[1], egypt[2], egypt[3], egypt[4]]).first?.rank, .two, "no rank III")
        let concord = ResonanceService.active(for: [egypt[0], greece[0], norse[0], rome[0]])
        XCTAssertEqual(concord.map(\.kind), [.concord])
        XCTAssertEqual(concord.first?.members, 4)
        XCTAssertTrue(ResonanceService.active(for: [egypt[0], greece[0], norse[0]]).isEmpty, "three pantheons is not yet a Concord")
        XCTAssertEqual(ResonanceKind.allCases.count, 6)
        for pantheon in Pantheon.live {
            XCTAssertNotNil(ResonanceKind.kind(for: pantheon), "\(pantheon.rawValue) resonates")
        }
        XCTAssertNil(ResonanceKind.kind(for: .aztec), "a pantheon without content has no resonance yet")
    }

    func testTheHintNamesWhatOneMoreUnitWouldLight() {
        let egypt = UnitDatabase.all.filter { $0.pantheon == .egyptian }
        let greece = UnitDatabase.all.filter { $0.pantheon == .greek }
        let norse = UnitDatabase.all.filter { $0.pantheon == .norse }
        XCTAssertEqual(
            ResonanceService.hint(for: [egypt[0], greece[0]], maxSize: 5),
            "One more Egyptian ally lights The Weighing of Hearts I.",
            "a tie goes to the first pantheon by name"
        )
        XCTAssertEqual(
            ResonanceService.hint(for: [egypt[0], egypt[1], greece[0]], maxSize: 5),
            "One more Egyptian ally lights The Weighing of Hearts II."
        )
        XCTAssertEqual(
            ResonanceService.hint(for: [egypt[0], greece[0], norse[0]], maxSize: 5),
            "A unit of a fourth pantheon lights the Concord of the Gods."
        )
        XCTAssertNil(ResonanceService.hint(for: [egypt[0], egypt[1], egypt[2], egypt[3]], maxSize: 4), "a full lineup has no room")
        XCTAssertNil(ResonanceService.hint(for: [egypt[0], egypt[1], egypt[2]], maxSize: 5), "a rank II has nowhere higher to go")
    }

    func testTheWordsPrintTheNumbersTheEngineUses() {
        XCTAssertEqual(ResonanceKind.valhalla.line(rank: .one), "Norse allies +5% attack")
        XCTAssertTrue(ResonanceKind.theLegion.line(rank: .two).contains("shield of 20% of max health"))
        XCTAssertTrue(ResonanceKind.weighingOfHearts.line(rank: .one).hasPrefix("Egyptian allies deal +8% damage against a debuffed enemy"))
        XCTAssertTrue(ResonanceKind.concord.line(rank: .one).hasPrefix("Every ally +6% attack, health and defence"))
        XCTAssertEqual(ActiveResonance(kind: .olympianHubris, rank: .two, members: 3).displayName, "Olympian Hubris II")
    }

    // MARK: - Into the battle

    func testARankTwoLineupCarriesItsBonusAndACampaignWaveNever() {
        let greeks = team(.greek, count: 3, level: 40, stars: 5)
        let other = [bag(excluding: .greek)]
        let lit = BattleEngine(playerTeam: greeks, opponentTeam: other, mode: .campaign, seed: 1)
        let wave = BattleEngine(playerTeam: other, opponentTeam: greeks, mode: .campaign, seed: 1)
        let arena = BattleEngine(playerTeam: other, opponentTeam: greeks, mode: .arenaOffense, seed: 1)

        XCTAssertEqual(lit.activeResonances(.player).map(\.kind), [.olympianHubris])
        XCTAssertEqual(lit.activeResonances(.player).first?.rank, .two)
        XCTAssertTrue(wave.activeResonances(.opponent).isEmpty, "a campaign wave never resonates")
        XCTAssertEqual(arena.activeResonances(.opponent).first?.kind, .olympianHubris, "an arena's defending team does")

        // The differences are hoisted into typed lets: arithmetic inside an
        // assert's autoclosure is what the type checker spends seconds on.
        for (mine, theirs) in zip(lit.team(.player), wave.team(.opponent)) {
            let lift: Double = mine.baseStats.critDamage - theirs.baseStats.critDamage
            XCTAssertEqual(lift, 0.20, accuracy: 1e-9)
            XCTAssertEqual(mine.baseStats.atk, theirs.baseStats.atk, accuracy: 1e-6, "Hubris touches crit damage and nothing else")
        }
        for (mine, theirs) in zip(arena.team(.opponent), wave.team(.opponent)) {
            let lift: Double = mine.baseStats.critDamage - theirs.baseStats.critDamage
            XCTAssertEqual(lift, 0.20, accuracy: 1e-9)
        }

        // Rank I is the smaller number, on the pantheon's own alone.
        let mixed = team(.greek, count: 2, level: 40, stars: 5) + team(.norse, count: 1, level: 40, stars: 5)
        let pairLit = BattleEngine(playerTeam: mixed, opponentTeam: other, mode: .campaign, seed: 1)
        let pairWave = BattleEngine(playerTeam: other, opponentTeam: mixed, mode: .campaign, seed: 1)
        XCTAssertEqual(pairLit.activeResonances(.player).first?.rank, .one)
        let greekLift = pairLit.team(.player)[0].baseStats.critDamage - pairWave.team(.opponent)[0].baseStats.critDamage
        let norseLift = pairLit.team(.player)[2].baseStats.critDamage - pairWave.team(.opponent)[2].baseStats.critDamage
        XCTAssertEqual(greekLift, 0.10, accuracy: 1e-9)
        XCTAssertEqual(norseLift, 0, accuracy: 1e-9, "the Norse ally is not Greek")
    }

    func testTheConcordReachesEveryone() {
        let four = team(.egyptian, count: 1, level: 40, stars: 5) + team(.greek, count: 1, level: 40, stars: 5)
            + team(.norse, count: 1, level: 40, stars: 5) + team(.roman, count: 1, level: 40, stars: 5)
        let other = [bag(excluding: .egyptian)]
        let lit = BattleEngine(playerTeam: four, opponentTeam: other, mode: .campaign, seed: 2)
        let wave = BattleEngine(playerTeam: other, opponentTeam: four, mode: .campaign, seed: 2)
        XCTAssertEqual(lit.activeResonances(.player).map(\.kind), [.concord])
        for (mine, theirs, resolved) in zip3(lit.team(.player), wave.team(.opponent), four) {
            let atkLift: Double = mine.baseStats.atk - theirs.baseStats.atk
            let atkDue: Double = resolved.stats.atk * 0.06
            let hpLift: Double = mine.baseStats.hp - theirs.baseStats.hp
            let hpDue: Double = resolved.stats.hp * 0.06
            let accuracyLift: Double = mine.baseStats.accuracy - theirs.baseStats.accuracy
            // A combatant's HP, ATK, DEF and SPD are whole points
            // (`Stats.clamped()` rounds them), so the lift the engine keeps
            // is 6% rounded — 20 for 19.98 on run 162 — and can sit up to a
            // point from the exact product. The rate stats are not rounded.
            XCTAssertEqual(atkLift, atkDue, accuracy: 1.0)
            XCTAssertEqual(hpLift, hpDue, accuracy: 1.0)
            XCTAssertGreaterThan(atkLift, 0)
            XCTAssertGreaterThan(hpLift, 0)
            XCTAssertEqual(accuracyLift, 0.05, accuracy: 1e-9)
        }
    }

    private func zip3<A, B, C>(_ a: [A], _ b: [B], _ c: [C]) -> [(A, B, C)] {
        zip(zip(a, b), c).map { ($0.0, $0.1, $1) }
    }

    func testTheWeighingMultipliesAnEgyptiansBlowOnAJudgedEnemy() throws {
        // Three Egyptians with a burn between them, on the far side of a
        // fight in two modes: as a campaign wave they resonate with nothing,
        // as an arena's defenders they light the Weighing II. The same seed
        // deals the same blows until the first one lands on a debuffed
        // target, and that one is bigger by exactly the line.
        let pool = UnitDatabase.all.filter { $0.pantheon == .egyptian }
        let leader = try XCTUnwrap(pool.first(where: { $0.leaderSkill == nil && !$0.id.hasPrefix("sekhmet") }))
        let egyptians = [leader.id, "sekhmet_umbra", "anubis_umbra"].map { fighter($0, level: 50, stars: 6) }
        let target = [bag(excluding: .egyptian, level: 60, stars: 6)]
        func hits(mode: BattleMode) -> [Double] {
            let engine = BattleEngine(playerTeam: target, opponentTeam: egyptians, mode: mode, seed: 7)
            engine.autoBattle = true
            let egyptianIDs = Set(engine.team(.opponent).map(\.id))
            let targetID = engine.team(.player).first!.id
            var amounts: [Double] = []
            for event in engine.start() {
                if case .damage(let source, let victim, let amount, _, _, _, _, _, _) = event,
                   egyptianIDs.contains(source), victim == targetID {
                    amounts.append(amount)
                }
            }
            return amounts
        }
        let plain = hits(mode: .campaign)
        let judged = hits(mode: .arenaOffense)
        let ratios: [Double] = zip(judged, plain).map { $0 / $1 }
        let first = try XCTUnwrap(ratios.firstIndex(where: { abs($0 - 1) > 1e-9 }), "a burn should land and be judged")
        let line: Double = 1 + ResonanceService.weighingDamage(rank: .two)
        XCTAssertEqual(ratios[first], line, accuracy: 1e-6)
        for index in 0..<first {
            XCTAssertEqual(ratios[index], 1.0, accuracy: 1e-9, "unjudged blows are the same blows")
        }
    }

    func testValhallaGivesTheOthersAttackUpWhenANorseAllyFalls() throws {
        let norse = team(.norse, count: 3, level: 30, stars: 5)
        let serpent = [titan()]
        let (events, engine) = fight(player: norse, opponent: serpent, seed: 3)
        let norseIDs = Set(engine.team(.player).map(\.id))
        let firstFall = try XCTUnwrap(events.firstIndex(where: {
            if case .defeated(let target) = $0 { return norseIDs.contains(target) }
            return false
        }), "the serpent should bring one down")
        let fury = events[firstFall...].contains {
            if case .statusApplied(_, let target, let kind, let turns) = $0 {
                return norseIDs.contains(target) && kind == .attackUp && turns == ResonanceService.valhallaTurns
            }
            return false
        }
        XCTAssertTrue(fury, "the others take up the fury")
        XCTAssertGreaterThan(announcements(events, named: "Valhalla II"), 0)
    }

    func testTheWeighingLeavesItsKaOnceWhenTheFirstEgyptianFalls() throws {
        let egyptians = team(.egyptian, count: 3, level: 30, stars: 5)
        let serpent = [titan()]
        let (events, engine) = fight(player: egyptians, opponent: serpent, seed: 4)
        let ids = Set(engine.team(.player).map(\.id))
        // Where each Egyptian fell. A unit's own heals before its death do
        // not count; a heal SOURCED by a unit after its death can only be
        // the Ka.
        var fallenAt: [UUID: Int] = [:]
        for (index, event) in events.enumerated() {
            if case .defeated(let target) = event, ids.contains(target), fallenAt[target] == nil {
                fallenAt[target] = index
            }
        }
        XCTAssertGreaterThanOrEqual(fallenAt.count, 2, "the whole line should fall to a serpent this size")
        let first = try XCTUnwrap(fallenAt.min(by: { $0.value < $1.value })).key
        let firstAt = fallenAt[first] ?? 0
        let kaHeals = events.enumerated().filter { index, event in
            if case .healed(let source, let target, _, _) = event {
                return index > firstAt && source == first && ids.contains(target)
            }
            return false
        }
        XCTAssertFalse(kaHeals.isEmpty, "the first to fall leaves its Ka")
        XCTAssertEqual(announcements(events, named: "The Weighing of Hearts II"), 1, "once a side")
        for (later, at) in fallenAt where later != first {
            XCTAssertFalse(events[(at + 1)...].contains {
                if case .healed(let source, _, _, _) = $0 { return source == later }
                return false
            }, "a second fall leaves nothing")
        }
    }

    func testHubrisFeedsTheBarOnAGreekKill() throws {
        let greeks = team(.greek, count: 3, level: 60, stars: 6)
        let mobs = (0..<3).map { _ in fighter("shabti", level: 1, stars: 1) }
        let (events, engine) = fight(player: greeks, opponent: mobs, seed: 5)
        let greekIDs = Set(engine.team(.player).map(\.id))
        XCTAssertGreaterThan(announcements(events, named: "Olympian Hubris II"), 0)
        let kill = try XCTUnwrap(events.firstIndex(where: {
            if case .defeated = $0 { return true }
            return false
        }))
        let most: Double = ResonanceService.hubrisBar + 1e-9
        let fed = events[kill...].prefix(8).contains {
            if case .attackBarChanged(let target, let delta, _) = $0 {
                return greekIDs.contains(target) && delta > 0 && delta <= most
            }
            return false
        }
        XCTAssertTrue(fed, "the killer's bar moves right after the kill")
    }

    func testTheMandateAndTheLegionAnswerTheFirstToFallUnderHalfOnceABattle() {
        let serpent = [fighter("apep", level: 60, stars: 5)]
        let jade = team(.chinese, count: 3, level: 30, stars: 5)
        let (jadeEvents, jadeEngine) = fight(player: jade, opponent: serpent, seed: 6)
        let jadeIDs = Set(jadeEngine.team(.player).map(\.id))
        XCTAssertEqual(announcements(jadeEvents, named: "The Mandate of Heaven II"), 1)
        XCTAssertTrue(jadeEvents.contains {
            if case .statusApplied(_, let target, let kind, let turns) = $0 {
                return jadeIDs.contains(target) && kind == .recovery && turns == ResonanceService.mandateTurns
            }
            return false
        })

        let romans = team(.roman, count: 3, level: 30, stars: 5)
        let (romanEvents, romanEngine) = fight(player: romans, opponent: serpent, seed: 6)
        let romanIDs = Set(romanEngine.team(.player).map(\.id))
        XCTAssertEqual(announcements(romanEvents, named: "The Legion II"), 1)
        XCTAssertTrue(romanEvents.contains {
            if case .statusApplied(_, let target, let kind, _) = $0 { return romanIDs.contains(target) && kind == .shield }
            return false
        })
        // Given when one is worn down, never at the battle's start.
        let firstTurn = romanEvents.firstIndex(where: {
            if case .turnBegan = $0 { return true }
            return false
        }) ?? 0
        let wallClosed = romanEvents.firstIndex(where: {
            if case .passiveTriggered(_, let name) = $0 { return name == "The Legion II" }
            return false
        }) ?? -1
        XCTAssertGreaterThan(wallClosed, firstTurn, "the wall closes over the wounded, not the whole")
    }
}
