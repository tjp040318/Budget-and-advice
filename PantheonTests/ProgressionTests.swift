import XCTest
@testable import Pantheon

/// Progression and economy rules. These are the numbers a player will notice
/// changing, so they are pinned rather than left to drift.
final class ProgressionTests: XCTestCase {

    func testStarGradeScalesStatsButNotSpeed() {
        let blueprint = UnitDatabase.starter
        let low = ProgressionService.baseStats(
            for: Unit(blueprint: blueprint, level: 1, stars: 3), blueprint: blueprint
        )
        let high = ProgressionService.baseStats(
            for: Unit(blueprint: blueprint, level: 1, stars: 6), blueprint: blueprint
        )

        XCTAssertGreaterThan(high.hp, low.hp)
        XCTAssertGreaterThan(high.atk, low.atk)
        // Speed is flat by design: it is what lets a low-grade support stay
        // relevant next to a maxed god.
        XCTAssertEqual(high.spd, low.spd)
    }

    func testMaxLevelFollowsGrade() {
        XCTAssertEqual(ProgressionService.maxLevel(stars: 1), 15)
        XCTAssertEqual(ProgressionService.maxLevel(stars: 6), 65)
    }

    func testExperienceCannotPushPastGradeCap() {
        var unit = Unit(blueprint: UnitDatabase.starter, level: 1, stars: 3)
        ProgressionService.grantExperience(10_000_000, to: &unit)
        XCTAssertEqual(unit.level, ProgressionService.maxLevel(stars: 3))
        XCTAssertEqual(unit.experience, 0)
    }

    func testEvolutionRequiresMaxLevelAndFodder() {
        var unit = Unit(blueprint: UnitDatabase.starter, level: 1, stars: 5)
        var wallet = Wallet()
        XCTAssertThrowsError(try ProgressionService.evolve(&unit, fodder: [], wallet: &wallet))

        unit.level = ProgressionService.maxLevel(stars: 5)
        XCTAssertThrowsError(try ProgressionService.evolve(&unit, fodder: [], wallet: &wallet))

        let fodder = (0..<5).map { _ in Unit(blueprint: UnitDatabase.starter, level: 1, stars: 5) }
        XCTAssertNoThrow(try ProgressionService.evolve(&unit, fodder: fodder, wallet: &wallet))
        XCTAssertEqual(unit.stars, 6)
        XCTAssertEqual(unit.level, 1)
    }

    func testRelicPercentagesApplyToBaseNotToFlats() {
        let blueprint = UnitDatabase.starter
        let unit = Unit(blueprint: blueprint, level: 40, stars: 6)
        let base = ProgressionService.baseStats(for: unit, blueprint: blueprint)

        let flatOnly = Relic(
            set: .fury, slot: 1, grade: 6,
            mainStat: StatModifier(.atkFlat, 500), subStats: []
        )
        // Deliberately a different set from the flat piece, so that no set
        // bonus completes and the test measures only the two main stats.
        let percentOnly = Relic(
            set: .zephyr, slot: 2, grade: 6,
            mainStat: StatModifier(.atkPercent, 0.50), subStats: []
        )

        let both = ProgressionService.resolve(unit, blueprint: blueprint, equipped: [flatOnly, percentOnly])
        // 50% of base ATK, plus the flat 500 (at +0 the main stat multiplier is 1x).
        let expected = base.atk + base.atk * 0.50 + 500
        XCTAssertEqual(both.stats.atk, expected.rounded(), accuracy: 2.0)
    }

    func testCompletedSetGrantsItsBonusOnce() {
        let blueprint = UnitDatabase.starter
        let unit = Unit(blueprint: blueprint, level: 40, stars: 6)
        let base = ProgressionService.baseStats(for: unit, blueprint: blueprint)

        // Two Fury pieces complete the set; a third does not double it.
        let pieces = (1...3).map { slot in
            Relic(
                set: .fury, slot: slot, grade: 6,
                mainStat: StatModifier(Relic.fixedMainStat(forSlot: slot) ?? .atkPercent, 0),
                subStats: []
            )
        }
        let resolved = ProgressionService.resolve(unit, blueprint: blueprint, equipped: pieces)
        XCTAssertEqual(resolved.stats.atk, (base.atk * 1.35).rounded(), accuracy: 2.0)
    }

    func testAwakeningConsumesEssenceExactlyOnce() {
        var unit = Unit(blueprint: UnitDatabase.starter, level: 1, stars: 5)
        var essences = UnitDatabase.starter.awakening!.essenceCost

        XCTAssertNoThrow(try ProgressionService.awaken(&unit, essences: &essences))
        XCTAssertTrue(unit.isAwakened)
        XCTAssertTrue(essences.values.allSatisfy { $0 == 0 })
        XCTAssertThrowsError(try ProgressionService.awaken(&unit, essences: &essences))
    }
}
