import XCTest
@testable import Pantheon

/// The Regalia: one named item per family, unlocked by awakening and levelled
/// I–V by duplicates fed past the skill-up cap (`Docs/PLAN.md`, *Artifacts —
/// the last item on the order*, option 3). These pin the tables — every
/// family named, every template's five numbers rising — the feed rule, the
/// unlock, and the engine's hooks, read off a real fight with and without
/// the item on the same seed. The size of each template is measured in
/// `tools/balance.py --regalia`.
final class RegaliaTests: XCTestCase {

    // MARK: - Helpers

    /// A unit resolved the player's way (`resolve(_:relics:boons:)`), which
    /// is the one path that fills the regalia.
    private func fighter(_ id: String, level: Int, stars: Int, awakened: Bool = false, regaliaLevel: Int? = nil) -> ResolvedUnit {
        let blueprint = UnitDatabase.blueprint(id)!
        var unit = Unit(blueprint: blueprint, level: level, stars: stars, awakened: awakened)
        unit.regaliaLevel = regaliaLevel
        return ProgressionService.resolve(unit, relics: [], boons: [])!
    }

    /// The same unit twice: bare, and wearing its regalia at a level — the
    /// pair every hook is read off.
    private func pair(_ id: String, level: Int, stars: Int, regaliaLevel: Int) -> (bare: ResolvedUnit, armed: ResolvedUnit) {
        let blueprint = UnitDatabase.blueprint(id)!
        var unit = Unit(blueprint: blueprint, level: level, stars: stars, awakened: true)
        unit.regaliaLevel = regaliaLevel
        let bare = ProgressionService.resolve(unit, blueprint: blueprint, equipped: [])
        let armed = ProgressionService.resolve(
            unit, blueprint: blueprint, equipped: [], regalia: RegaliaService.regalia(for: unit, blueprint: blueprint)
        )
        return (bare, armed)
    }

    /// A sturdy unit of no leader skill to stand on the far side.
    private func bag(level: Int = 60, stars: Int = 6) -> ResolvedUnit {
        let blueprint = UnitDatabase.all.first(where: { $0.leaderSkill == nil })!
        return ProgressionService.resolve(Unit(blueprint: blueprint, level: level, stars: stars), blueprint: blueprint, equipped: [])
    }

    // MARK: - The tables

    func testEveryFamilyHasANamedRegaliaWithABlurbAndATemplate() {
        let keys = RegaliaService.familyKeys
        let expected: Int = RegaliaService.handwrittenFamilies.count + UnitDatabase.familyRows.count
        XCTAssertEqual(keys.count, expected)
        XCTAssertEqual(Set(keys).count, keys.count, "a family key is spelt once")
        var names = Set<String>()
        for key in keys {
            let regalia = RegaliaService.regalia(forFamily: key, level: 1)
            XCTAssertNotNil(regalia, "\(key) has no regalia")
            guard let regalia else { continue }
            XCTAssertFalse(regalia.name.isEmpty, key)
            XCTAssertFalse(regalia.blurb.isEmpty, "\(key) has no blurb")
            XCTAssertTrue(names.insert(regalia.name).inserted, "\(regalia.name) names two families")
        }
        XCTAssertEqual(UnitDatabase.regaliaNames.count, keys.count, "a name for a family that does not exist")
        XCTAssertEqual(UnitDatabase.regaliaBlurbs.count, keys.count, "a blurb for a family that does not exist")
        for key in UnitDatabase.handwrittenRegaliaTemplates.keys {
            XCTAssertTrue(RegaliaService.handwrittenFamilies.contains(key), "\(key) is not one of the eleven")
        }
        // Every collectible unit resolves to one; an enemy or a boss to none.
        for id in UnitDatabase.collectiblePool {
            XCTAssertNotNil(RegaliaService.regalia(forBlueprint: id), id)
        }
        XCTAssertNil(RegaliaService.regalia(forBlueprint: "enemy_minotaur"))
        XCTAssertNil(RegaliaService.regalia(forBlueprint: "apep"))
        XCTAssertEqual(RegaliaService.familyKey(of: "zeus_ember"), "zeus")
        XCTAssertEqual(RegaliaService.familyKey(of: "shabti"), "shabti", "the starter is its own family")
        XCTAssertEqual(RegaliaService.familyKey(of: "terracotta_soldier_radiance"), "terracotta_soldier")
        // A table family's template is its kit's; the eleven are chosen by hand.
        XCTAssertEqual(RegaliaService.template(forFamily: "thor"), .keenEdge)
        XCTAssertEqual(RegaliaService.template(forFamily: "isis"), .wellspring)
        XCTAssertEqual(RegaliaService.template(forFamily: "odin"), .lastingWord)
        XCTAssertEqual(RegaliaService.template(forFamily: "zeus"), .keenEdge)
        XCTAssertEqual(RegaliaService.template(forFamily: "heracles"), .unbowed)
        XCTAssertEqual(RegaliaService.regalia(forFamily: "zeus", level: 1)?.name, "Thunderbolt of Olympus")
        XCTAssertEqual(RegaliaService.regalia(forFamily: "anubis", level: 1)?.name, "Scales of the Duat")
        XCTAssertEqual(RegaliaService.regalia(forFamily: "thor", level: 1)?.name, "Mjölnir")
        XCTAssertEqual(RegaliaService.regalia(forFamily: "odin", level: 1)?.name, "Gungnir")
    }

    func testEveryTemplateHasFiveMagnitudesThatRiseFromIToV() {
        XCTAssertEqual(RegaliaTemplate.magnitudes.count, RegaliaTemplate.allCases.count)
        XCTAssertEqual(RegaliaTemplate.levels, 5)
        for template in RegaliaTemplate.allCases {
            let table = RegaliaTemplate.magnitudes[template] ?? []
            XCTAssertEqual(table.count, RegaliaTemplate.levels, "\(template.rawValue) has five levels")
            for (lower, higher) in zip(table, table.dropFirst()) {
                XCTAssertLessThan(lower, higher, "\(template.rawValue) rises every level")
            }
            let first: Double = table.first ?? -1
            let last: Double = table.last ?? -1
            let atOne: Double = template.magnitude(at: 1)
            let atFive: Double = template.magnitude(at: 5)
            let above: Double = template.magnitude(at: 9)
            let below: Double = template.magnitude(at: 0)
            XCTAssertGreaterThan(first, 0)
            XCTAssertEqual(atOne, first, accuracy: 1e-12)
            XCTAssertEqual(atFive, last, accuracy: 1e-12)
            XCTAssertEqual(above, last, accuracy: 1e-12, "clamped above V")
            XCTAssertEqual(below, first, accuracy: 1e-12, "clamped below I")
            XCTAssertFalse(template.displayName.isEmpty)
            XCTAssertFalse(template.glyph.isEmpty)
        }
        // The words print the numbers the engine uses.
        let keen = RegaliaService.regalia(forFamily: "thor", level: 5)
        XCTAssertEqual(keen?.line, "+12% crit rate")
        XCTAssertEqual(keen?.shortLine, "+12% crit")
        XCTAssertEqual(keen?.levelLabel, "V")
        XCTAssertEqual(keen?.isMaxLevel, true)
        let word = RegaliaService.regalia(forFamily: "odin", level: 2)
        XCTAssertEqual(word?.extendsDebuffs, false, "a Lasting Word holds the debuffs from III")
        let held = RegaliaService.regalia(forFamily: "odin", level: 3)
        XCTAssertEqual(held?.extendsDebuffs, true)
        XCTAssertEqual(held?.line.contains("a turn longer"), true)
        XCTAssertEqual(RegaliaService.regalia(forFamily: "odin", level: 7)?.level, 5, "a level past V is V")
    }

    // MARK: - Feeding

    func testFeedingADuplicateRaisesTheLevelOnlyWhenSkillsAreCappedAndNeverPastV() throws {
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint("zeus_ember"))
        var zeus = Unit(blueprint: blueprint, level: 1)
        let twin = Unit(blueprint: blueprint, level: 1)
        let cousin = Unit(blueprint: try XCTUnwrap(UnitDatabase.blueprint("zeus_tide")), level: 1)
        let stranger = Unit(blueprint: try XCTUnwrap(UnitDatabase.blueprint("thor_ember")), level: 1)
        XCTAssertEqual(RegaliaService.level(of: zeus), 1)
        XCTAssertNil(zeus.regaliaLevel, "nil in the save is level I")
        XCTAssertTrue(RegaliaService.isSameFamily(cousin, as: zeus))
        XCTAssertFalse(RegaliaService.isSameFamily(stranger, as: zeus))
        XCTAssertFalse(RegaliaService.isSameFamily(zeus, as: zeus), "a unit is not its own duplicate")

        let owed = RegaliaService.skillUpsRemaining(zeus, blueprint: blueprint)
        XCTAssertGreaterThan(owed, 0, "a fresh unit has skill-ups to take")
        XCTAssertFalse(RegaliaService.skillsAreCapped(zeus, blueprint: blueprint))
        XCTAssertEqual(RegaliaService.feed(duplicate: twin, into: &zeus), .skillsNotCapped(remaining: owed))
        XCTAssertNil(zeus.regaliaLevel, "nothing banked while a skill-up is owed")
        XCTAssertEqual(RegaliaService.feed(duplicate: stranger, into: &zeus), .notSameFamily)

        // Every skill at its cap, the way `applySkillUp` would leave it.
        zeus.skillLevels = blueprint.skills.map(\.maxSkillLevel)
        XCTAssertTrue(RegaliaService.skillsAreCapped(zeus, blueprint: blueprint))
        XCTAssertEqual(RegaliaService.skillUpsRemaining(zeus, blueprint: blueprint), 0)
        XCTAssertEqual(RegaliaService.feed(duplicate: twin, into: &zeus), .raised(to: 2))
        XCTAssertEqual(RegaliaService.feed(duplicate: cousin, into: &zeus), .raised(to: 3), "a copy of the family in another colour counts")
        XCTAssertEqual(RegaliaService.feed(duplicate: twin, into: &zeus), .raised(to: 4))
        XCTAssertEqual(RegaliaService.feed(duplicate: twin, into: &zeus), .raised(to: 5))
        XCTAssertEqual(RegaliaService.feed(duplicate: twin, into: &zeus), .alreadyMax)
        XCTAssertEqual(zeus.regaliaLevel, 5)
        XCTAssertEqual(RegaliaService.level(of: zeus), 5)
        XCTAssertEqual(RegaliaService.feed(duplicate: stranger, into: &zeus), .notSameFamily)

        // The level banks on a unit that has not awakened yet: the fifth
        // copy fed before the awakening is not fed for nothing.
        XCTAssertFalse(zeus.isAwakened)
        XCTAssertNil(RegaliaService.regalia(for: zeus, blueprint: blueprint), "banked, not lit")

        // The save's path: by id, inside the player.
        var player = Player()
        var other = Unit(blueprint: blueprint, level: 1)
        other.skillLevels = blueprint.skills.map(\.maxSkillLevel)
        player.units = [other]
        XCTAssertEqual(RegaliaService.feed(duplicate: twin, into: other.id, player: &player), .raised(to: 2))
        XCTAssertEqual(player.units[0].regaliaLevel, 2)
        XCTAssertEqual(RegaliaService.feed(duplicate: twin, into: UUID(), player: &player), .noSuchUnit)
    }

    // MARK: - Unlocking

    func testALockedUnitResolvesNoRegaliaAndAnUnlockedOneItsFamilys() throws {
        let sleeping = fighter("zeus_ember", level: 30, stars: 5)
        XCTAssertNil(sleeping.regalia, "unawakened: locked")
        let awake = fighter("zeus_ember", level: 30, stars: 5, awakened: true)
        XCTAssertEqual(awake.regalia?.name, "Thunderbolt of Olympus")
        XCTAssertEqual(awake.regalia?.level, 1)
        XCTAssertEqual(awake.regalia?.template, .keenEdge)
        let honed = fighter("zeus_ember", level: 30, stars: 5, awakened: true, regaliaLevel: 3)
        XCTAssertEqual(honed.regalia?.level, 3)
        XCTAssertEqual(honed.regalia?.levelLabel, "III")
        // The regalia changes no stat on the sheet; the engine adds it.
        XCTAssertEqual(honed.stats.critRate, awake.stats.critRate, accuracy: 1e-9)
        XCTAssertEqual(honed.stats.atk, awake.stats.atk, accuracy: 1e-9)
        XCTAssertEqual(honed.power, awake.power)

        // A family with no awakened form unlocks at 6★ instead.
        let common = try XCTUnwrap(UnitDatabase.blueprint("hoplite_tide"))
        XCTAssertNil(common.awakening)
        XCTAssertEqual(RegaliaService.unlockLine(for: common), "Evolve to 6★ to unlock")
        XCTAssertNil(fighter("hoplite_tide", level: 55, stars: 5).regalia)
        XCTAssertEqual(fighter("hoplite_tide", level: 1, stars: 6).regalia?.name, "Hoplon of the Line")
        XCTAssertEqual(RegaliaService.unlockLine(for: awake.blueprint), "Awaken to unlock")

        // A campaign wave's unit is resolved by the overload with none.
        let spawn = EnemySpawn(blueprintID: "zeus_ember", level: 60, stars: 6, statMultiplier: 1.0)
        let enemy = try XCTUnwrap(StageDatabase.buildEnemies(spawns: [spawn]).first)
        XCTAssertNil(enemy.regalia, "a wave's Zeus carries no Thunderbolt")
    }

    func testASaveWrittenBeforeTheRegaliaStillDecodesAndALevelRoundTrips() throws {
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint("zeus_ember"))
        let unit = Unit(blueprint: blueprint, level: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(unit)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.isEmpty)
        XCTAssertFalse(json.contains("\"regaliaLevel\""), "a unit with no regalia level must not write the key")
        let restored = try decoder.decode(Unit.self, from: data)
        XCTAssertNil(restored.regaliaLevel)
        XCTAssertEqual(RegaliaService.level(of: restored), 1)

        var honed = unit
        honed.regaliaLevel = 4
        let back = try decoder.decode(Unit.self, from: try encoder.encode(honed))
        XCTAssertEqual(back.regaliaLevel, 4)
        XCTAssertEqual(RegaliaService.level(of: back), 4)
    }

    // MARK: - Into the battle

    func testAStrikersRegaliaAtVRaisesItsCritRateByTheTableAndADuelistsItsCritDamage() {
        let foe = [bag()]
        // Thor, a striker: Keen Edge is crit rate. The differences are
        // hoisted into typed lets: arithmetic inside an assert's autoclosure
        // is what the type checker spends seconds on.
        let thor = pair("thor_ember", level: 40, stars: 5, regaliaLevel: 5)
        XCTAssertNil(thor.bare.regalia)
        XCTAssertEqual(thor.armed.regalia?.level, 5)
        let lit = BattleEngine(playerTeam: [thor.armed], opponentTeam: foe, mode: .campaign, seed: 1)
        let dark = BattleEngine(playerTeam: [thor.bare], opponentTeam: foe, mode: .campaign, seed: 1)
        let critLift: Double = lit.team(.player)[0].baseStats.critRate - dark.team(.player)[0].baseStats.critRate
        let critDue: Double = RegaliaTemplate.keenEdge.magnitude(at: 5)
        XCTAssertEqual(critLift, critDue, accuracy: 1e-9)
        XCTAssertEqual(critDue, 0.12, accuracy: 1e-12, "the table's V")
        XCTAssertEqual(lit.team(.player)[0].baseStats.atk, dark.team(.player)[0].baseStats.atk, accuracy: 1e-9, "a Keen Edge touches the crit rate and nothing else")
        XCTAssertEqual(lit.team(.player)[0].baseStats.critDamage, dark.team(.player)[0].baseStats.critDamage, accuracy: 1e-9)
        XCTAssertEqual(lit.team(.player)[0].regalia?.name, "Mjölnir")
        XCTAssertNil(dark.team(.player)[0].regalia)

        // Level I is the table's first number.
        let fresh = pair("thor_ember", level: 40, stars: 5, regaliaLevel: 1)
        let litFresh = BattleEngine(playerTeam: [fresh.armed], opponentTeam: foe, mode: .campaign, seed: 1)
        let freshLift: Double = litFresh.team(.player)[0].baseStats.critRate - dark.team(.player)[0].baseStats.critRate
        let freshDue: Double = RegaliaTemplate.keenEdge.magnitude(at: 1)
        XCTAssertEqual(freshLift, freshDue, accuracy: 1e-9)

        // Horus, a duelist: Heavy Hand is crit damage.
        let horus = pair("horus_ember", level: 40, stars: 5, regaliaLevel: 5)
        let litHorus = BattleEngine(playerTeam: [horus.armed], opponentTeam: foe, mode: .campaign, seed: 1)
        let darkHorus = BattleEngine(playerTeam: [horus.bare], opponentTeam: foe, mode: .campaign, seed: 1)
        let damageLift: Double = litHorus.team(.player)[0].baseStats.critDamage - darkHorus.team(.player)[0].baseStats.critDamage
        let damageDue: Double = RegaliaTemplate.heavyHand.magnitude(at: 5)
        XCTAssertEqual(damageLift, damageDue, accuracy: 1e-9)
        XCTAssertEqual(litHorus.team(.player)[0].baseStats.critRate, darkHorus.team(.player)[0].baseStats.critRate, accuracy: 1e-9)
    }

    func testFirstOffTheMarkFillsTheBarUnderTheItemsNameWhenTheBattleBegins() throws {
        // Artemis, a marksman. Her awakened passive fills the bar too, but
        // the regalia fires before any passive, so the first bar change on
        // her is the item's, exactly the table's V.
        let artemis = pair("artemis_ember", level: 40, stars: 5, regaliaLevel: 5)
        let engine = BattleEngine(playerTeam: [artemis.armed], opponentTeam: [bag()], mode: .campaign, seed: 2)
        engine.autoBattle = true
        let huntress = engine.team(.player)[0].id
        let events = engine.start()
        let due: Double = RegaliaTemplate.firstOffTheMark.magnitude(at: 5)
        let announced = events.contains {
            if case .passiveTriggered(let actor, let name) = $0 { return actor == huntress && name == "Silver Bow of Artemis" }
            return false
        }
        XCTAssertTrue(announced, "the item is announced under its own name")
        let opening = try XCTUnwrap(events.firstIndex(where: {
            if case .attackBarChanged(let target, _, _) = $0 { return target == huntress }
            return false
        }))
        guard case .attackBarChanged(_, let delta, _) = events[opening] else { return XCTFail("not a bar change") }
        XCTAssertEqual(delta, due, accuracy: 1e-9)

        // Without the item, nothing is announced.
        let bareEngine = BattleEngine(playerTeam: [artemis.bare], opponentTeam: [bag()], mode: .campaign, seed: 2)
        bareEngine.autoBattle = true
        let silent = bareEngine.start().contains {
            if case .passiveTriggered(_, let name) = $0 { return name == "Silver Bow of Artemis" }
            return false
        }
        XCTAssertFalse(silent)
    }

    func testALastingWordHoldsTheFirstDebuffATurnLongerAndNeverAStun() throws {
        // Anubis, whose Scales are a Lasting Word: the same fight on the same
        // seed with and without the item, and the first debuff he lands is
        // the same debuff a turn longer. Two fights on one seed are identical
        // up to the first thing the item changes, and this is it.
        let anubis = pair("anubis_umbra", level: 50, stars: 6, regaliaLevel: 3)
        XCTAssertEqual(anubis.armed.regalia?.template, .lastingWord)
        XCTAssertEqual(anubis.armed.regalia?.extendsDebuffs, true)
        func firstDebuff(_ resolved: ResolvedUnit) -> (kind: StatusKind, turns: Int)? {
            let engine = BattleEngine(playerTeam: [resolved], opponentTeam: [bag()], mode: .campaign, seed: 3)
            engine.autoBattle = true
            let jackal = engine.team(.player)[0].id
            for event in engine.start() {
                if case .statusApplied(let source, _, let kind, let turns) = event, source == jackal, kind.isDebuff, !kind.isHardCC {
                    return (kind, turns)
                }
            }
            return nil
        }
        let plain = try XCTUnwrap(firstDebuff(anubis.bare), "Anubis should land a debuff")
        let held = try XCTUnwrap(firstDebuff(anubis.armed))
        XCTAssertEqual(held.kind, plain.kind, "the same debuff")
        let longer: Int = plain.turns + 1
        XCTAssertEqual(held.turns, longer, "a turn longer")
        // A hard control is never held: the engine's rule, not the sim's.
        let engine = BattleEngine(playerTeam: [anubis.armed], opponentTeam: [bag()], mode: .campaign, seed: 3)
        engine.autoBattle = true
        let jackal = engine.team(.player)[0].id
        for event in engine.start() {
            if case .statusApplied(let source, _, let kind, let turns) = event, source == jackal, kind.isHardCC {
                XCTAssertLessThanOrEqual(turns, kind.defaultDuration, "\(kind.rawValue) held longer than its own duration")
            }
        }
    }
}
