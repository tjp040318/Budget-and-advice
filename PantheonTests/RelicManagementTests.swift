import XCTest
@testable import Pantheon

/// Selling, reappraisal, locking and the efficiency read-out.
final class RelicManagementTests: XCTestCase {

    private func account() -> (Player, SeededRandom) {
        var rng = SeededRandom(seed: 11)
        var player = NewGame.create().player
        player.wallet.drachma = 1_000_000
        for grade in [3, 4, 5, 6] {
            player.relics.append(RelicService.generate(grade: grade, rng: &rng))
        }
        return (player, rng)
    }

    func testSellingPaysAndRemovesAndUnequips() throws {
        var (player, _) = account()
        let starter = player.units[0]
        let equipped = try XCTUnwrap(starter.equippedRelics[1].flatMap { player.relic($0) })
        let loose = try XCTUnwrap(player.relics.last)
        let before = player.wallet.drachma
        let expected = RelicService.sellValue(equipped) + RelicService.sellValue(loose)

        let paid = try RelicService.sell(relicIDs: [equipped.id, loose.id], player: &player)
        XCTAssertEqual(paid, expected)
        XCTAssertEqual(player.wallet.drachma, before + expected)
        XCTAssertNil(player.relic(equipped.id))
        XCTAssertNil(player.relic(loose.id))
        XCTAssertNil(player.units[0].equippedRelics[1], "selling an equipped relic must empty the slot")
    }

    func testLockedRelicsCannotBeSold() throws {
        var (player, _) = account()
        let index = player.relics.count - 1
        player.relics[index].isLocked = true
        let id = player.relics[index].id
        let count = player.relics.count
        XCTAssertThrowsError(try RelicService.sell(relicIDs: [id], player: &player))
        XCTAssertEqual(player.relics.count, count)
    }

    func testSellValueGrowsWithGradeAndInvestment() {
        var rng = SeededRandom(seed: 12)
        let low = RelicService.generate(grade: 3, rng: &rng)
        let high = RelicService.generate(grade: 6, rng: &rng)
        XCTAssertGreaterThan(RelicService.sellValue(high), RelicService.sellValue(low))

        var upgraded = high
        for _ in 0..<12 { RelicService.upgradeOnce(&upgraded, rng: &rng) }
        XCTAssertGreaterThan(RelicService.sellValue(upgraded), RelicService.sellValue(high))
        // Never more than what the upgrades cost, or selling would print drachma.
        let invested = (0..<12).reduce(0) { $0 + RelicService.upgradeCost(grade: 6, level: $1) }
        XCTAssertLessThan(RelicService.sellValue(upgraded) - RelicService.sellValue(high), invested)
    }

    func testReappraisalKeepsMainStatLevelAndSet() throws {
        var (player, rng) = account()
        var relic = try XCTUnwrap(player.relics.last)
        for _ in 0..<9 { RelicService.upgradeOnce(&relic, rng: &rng) }
        let before = relic
        var wallet = player.wallet
        try RelicService.reappraise(&relic, wallet: &wallet, rng: &rng)
        XCTAssertEqual(relic.mainStat, before.mainStat)
        XCTAssertEqual(relic.level, before.level)
        XCTAssertEqual(relic.set, before.set)
        XCTAssertEqual(relic.slot, before.slot)
        XCTAssertEqual(relic.subStats.count, before.subStats.count)
        XCTAssertEqual(wallet.drachma, player.wallet.drachma - RelicService.reappraisalCost(before))
        XCTAssertFalse(relic.subStats.contains(where: { $0.kind == relic.mainStat.kind }))
        player.wallet = wallet
    }

    func testReappraisalNeedsPlusNine() {
        var (player, rng) = account()
        var relic = player.relics.last!
        var wallet = player.wallet
        XCTAssertThrowsError(try RelicService.reappraise(&relic, wallet: &wallet, rng: &rng))
        XCTAssertEqual(wallet.drachma, player.wallet.drachma)
        player.wallet = wallet
    }

    func testEfficiencyIsBetweenZeroAndOneAndRewardsTheRightStats() {
        var rng = SeededRandom(seed: 13)
        var attackerRelic = RelicService.generate(grade: 6, slot: 2, set: .fury, rng: &rng)
        attackerRelic.mainStat = StatModifier(.atkPercent, RelicService.mainStatValue(kind: .atkPercent, grade: 6))
        attackerRelic.subStats = [
            StatModifier(.critRate, 0.08), StatModifier(.critDamage, 0.1), StatModifier(.spd, 8), StatModifier(.atkFlat, 20)
        ]
        var tankRelic = attackerRelic
        tankRelic.mainStat = StatModifier(.defPercent, RelicService.mainStatValue(kind: .defPercent, grade: 6))
        tankRelic.subStats = [StatModifier(.hpPercent, 0.08), StatModifier(.defFlat, 20), StatModifier(.accuracy, 0.05), StatModifier(.resistance, 0.05)]

        for relic in [attackerRelic, tankRelic] {
            for role in [CombatRole.attacker, .defender, .support] {
                let value = RelicService.efficiency(relic, for: role)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
            }
        }
        XCTAssertGreaterThan(
            RelicService.efficiency(attackerRelic, for: .attacker),
            RelicService.efficiency(tankRelic, for: .attacker)
        )
        XCTAssertGreaterThan(
            RelicService.efficiency(tankRelic, for: .defender),
            RelicService.efficiency(attackerRelic, for: .defender)
        )
    }

    // MARK: - Power-up, the genre's way

    func testPowerUpIsSureToPlusThreeThenFalls() {
        XCTAssertEqual(RelicService.successChance(toLevel: 1), 1.0)
        XCTAssertEqual(RelicService.successChance(toLevel: 3), 1.0)
        XCTAssertLessThan(RelicService.successChance(toLevel: 4), 1.0)
        for level in 4...15 {
            XCTAssertLessThan(RelicService.successChance(toLevel: level), RelicService.successChance(toLevel: level - 1) + 0.0001, "+\(level)")
        }
        XCTAssertGreaterThanOrEqual(RelicService.successChance(toLevel: 15), 0.3, "the top must stay reachable")
    }

    func testAFailedAttemptSpendsTheDrachmaAndKeepsTheLevel() throws {
        var rng = SeededRandom(seed: 21)
        var relic = RelicService.generate(grade: 6, slot: 2, set: .fury, rng: &rng)
        for _ in 0..<12 { RelicService.upgradeOnce(&relic, rng: &rng) }
        XCTAssertEqual(relic.level, 12)

        var failures = 0
        var successes = 0
        for seed in 0..<40 {
            var trial = relic
            var wallet = Wallet()
            wallet.drachma = 1_000_000
            var attemptRNG = SeededRandom(seed: UInt64(seed))
            let outcome = try RelicService.upgrade(&trial, wallet: &wallet, rng: &attemptRNG)
            XCTAssertEqual(outcome.cost, RelicService.upgradeCost(grade: 6, level: 12))
            XCTAssertEqual(wallet.drachma, 1_000_000 - outcome.cost, "the drachma goes either way")
            if outcome.succeeded {
                successes += 1
                XCTAssertEqual(trial.level, 13)
                XCTAssertEqual(outcome.level, 13)
            } else {
                failures += 1
                XCTAssertEqual(trial.level, 12)
                XCTAssertEqual(outcome.level, 12)
                XCTAssertNil(outcome.subStatChange)
            }
        }
        XCTAssertGreaterThan(failures, 0, "+13 at 50% never failed in forty tries")
        XCTAssertGreaterThan(successes, 0)
    }

    func testSubStatsRollAtThreeSixNineAndTwelveOnly() {
        var rng = SeededRandom(seed: 5)
        var relic = RelicService.generate(grade: 3, slot: 4, set: .thunder, quality: .magic, rng: &rng)
        relic.subStats = [relic.subStats[0]]
        var rolledAt: [Int] = []
        for _ in 0..<15 {
            if let change = RelicService.upgradeOnce(&relic, rng: &rng) {
                rolledAt.append(relic.level)
                XCTAssertGreaterThan(change.after, change.before)
            }
        }
        XCTAssertEqual(rolledAt, [3, 6, 9, 12])
        XCTAssertEqual(relic.level, 15)
        XCTAssertEqual(relic.subStats.count, 4, "three new subs, then the fourth roll grows one")
        XCTAssertNil(RelicService.upgradeOnce(&relic, rng: &rng), "nothing past +15")
    }

    func testPlusFifteenLiftsTheMainStat() {
        var rng = SeededRandom(seed: 8)
        var relic = RelicService.generate(grade: 5, slot: 1, set: .aegis, rng: &rng)
        let atZero = relic.effectiveMainStat.value
        for _ in 0..<14 { RelicService.upgradeOnce(&relic, rng: &rng) }
        let atFourteen = relic.effectiveMainStat.value
        XCTAssertEqual(relic.nextMainStat?.kind, relic.mainStat.kind)
        RelicService.upgradeOnce(&relic, rng: &rng)
        let atFifteen = relic.effectiveMainStat.value
        XCTAssertNil(relic.nextMainStat)
        XCTAssertGreaterThan(atFifteen / atFourteen, 1.08, "the last level is a jump")
        XCTAssertEqual(atFifteen / atZero, 3.0, accuracy: 0.01)
    }
}

// MARK: - Quality, whetstones and gems

/// The genre's rune rarity and its grindstones and gems, as this game has
/// them: the quality is the sub count at the drop, rolled by grade and never
/// below a floor; a whetstone hones one sub stat and keeps the better bonus;
/// a gem replaces one sub stat, one per relic.
final class RelicQualityTests: XCTestCase {

    func testQualityIsTheSubCountAtTheDrop() {
        var rng = SeededRandom(seed: 31)
        for quality in RelicQuality.allCases {
            let relic = RelicService.generate(grade: 6, quality: quality, rng: &rng)
            XCTAssertEqual(relic.quality, quality)
            XCTAssertEqual(relic.subStats.count, quality.subStatCount)
            XCTAssertEqual(relic.resolvedQuality, quality)
        }
    }

    func testQualityOddsFollowTheGradeAndTheFloor() {
        var rng = SeededRandom(seed: 32)
        var legendsAtSix = 0
        var normalsAtSix = 0
        for _ in 0..<600 {
            let relic = RelicService.generate(grade: 6, rng: &rng)
            if relic.resolvedQuality == .legend { legendsAtSix += 1 }
            if relic.resolvedQuality == .normal { normalsAtSix += 1 }
        }
        // 12% and 6% in the table; loose bounds so a seed cannot fail this.
        XCTAssertGreaterThan(legendsAtSix, 30)
        XCTAssertLessThan(legendsAtSix, 130)
        XCTAssertGreaterThan(normalsAtSix, 8)

        for _ in 0..<200 {
            XCTAssertEqual(RelicService.generate(grade: 2, rng: &rng).resolvedQuality < .legend, true, "a 2★ never drops a Legend")
            XCTAssertGreaterThanOrEqual(RelicService.generate(grade: 3, qualityFloor: .rare, rng: &rng).resolvedQuality, .rare)
        }
        XCTAssertEqual(RelicQuality.weights(forGrade: 6).reduce(0, +), 100)
        XCTAssertEqual(RelicQuality.weights(forGrade: 1).reduce(0, +), 100)
    }

    func testAnOldRelicReadsItsQualityOffItsSubsAndLevel() {
        var rng = SeededRandom(seed: 33)
        var relic = RelicService.generate(grade: 6, quality: .hero, rng: &rng)
        relic.quality = nil
        XCTAssertEqual(relic.resolvedQuality, .legend, "the old generator's floor for a 6★ was four subs")
        var three = RelicService.generate(grade: 3, quality: .magic, rng: &rng)
        three.quality = nil
        for _ in 0..<6 { RelicService.upgradeOnce(&three, rng: &rng) }
        XCTAssertEqual(three.subStats.count, 3)
        XCTAssertEqual(three.resolvedQuality, .magic, "three subs less two rolls is one")
    }

    func testReappraisalKeepsTheQualityAndClearsTheStones() throws {
        var rng = SeededRandom(seed: 34)
        var player = NewGame.create().player
        player.wallet.drachma = 1_000_000
        var relic = RelicService.generate(grade: 6, quality: .rare, rng: &rng)
        for _ in 0..<9 { RelicService.upgradeOnce(&relic, rng: &rng) }
        relic.honed = [0: 3]
        relic.gemmed = 1
        var wallet = player.wallet
        try RelicService.reappraise(&relic, wallet: &wallet, rng: &rng)
        XCTAssertEqual(relic.quality, .rare)
        XCTAssertEqual(relic.subStats.count, 4, "two at the drop, then three rolls: two new and one grown")
        XCTAssertNil(relic.honed)
        XCTAssertNil(relic.gemmed)
        player.wallet = wallet
    }

    func testAWhetstoneHonesAndKeepsTheBetterBonus() throws {
        var rng = SeededRandom(seed: 35)
        var player = NewGame.create().player
        player.wallet.drachma = 100_000
        var relic = RelicService.generate(grade: 6, slot: 2, set: .fury, quality: .legend, rng: &rng)
        relic.subStats[0] = StatModifier(.spd, 6)
        player.relics.append(relic)
        let stone = RelicStone(kind: .whetstone, tier: .legend)
        XCTAssertThrowsError(try RelicService.hone(relicID: relic.id, subStat: 0, tier: .legend, player: &player, rng: &rng), "no stone yet")

        RelicService.addStones(stone.id, 2, player: &player)
        let first = try RelicService.hone(relicID: relic.id, subStat: 0, tier: .legend, player: &player, rng: &rng)
        let span = RelicService.stoneSpan(stone, kind: .spd)
        XCTAssertEqual(first.kind, .spd)
        XCTAssertEqual(first.before, 0)
        XCTAssertGreaterThanOrEqual(first.after, span.lowerBound)
        XCTAssertLessThanOrEqual(first.after, span.upperBound)
        XCTAssertEqual(player.wallet.drachma, 100_000 - stone.cost)
        XCTAssertEqual(RelicService.stoneCount(stone, player: player), 1)
        let honed = try XCTUnwrap(player.relic(relic.id))
        XCTAssertEqual(honed.subStats[0].value, 6, "the roll itself is untouched")
        XCTAssertEqual(honed.effectiveSubStats[0].value, 6 + first.after, accuracy: 0.001)
        XCTAssertEqual(honed.allStats.count, 5)

        let second = try RelicService.hone(relicID: relic.id, subStat: 0, tier: .legend, player: &player, rng: &rng)
        XCTAssertEqual(second.before, first.after)
        XCTAssertGreaterThanOrEqual(second.after, first.after, "honing again never lowers the bonus")
        XCTAssertEqual(RelicService.stoneCount(stone, player: player), 0)
        XCTAssertNil(player.relicStones?[stone.id])
    }

    func testAGemReplacesOneSubStatAndOnlyOnePerRelic() throws {
        var rng = SeededRandom(seed: 36)
        var player = NewGame.create().player
        player.wallet.drachma = 100_000
        var relic = RelicService.generate(grade: 6, slot: 4, set: .thunder, quality: .hero, rng: &rng)
        relic.honed = [0: 2]
        player.relics.append(relic)
        RelicService.addStones("gem_hero", 3, player: &player)

        let kinds = RelicService.gemKinds(for: relic, replacing: 0)
        XCTAssertFalse(kinds.contains(relic.mainStat.kind))
        XCTAssertFalse(kinds.contains(relic.subStats[1].kind))
        let newKind = try XCTUnwrap(kinds.first(where: { $0 != relic.subStats[0].kind }))

        let outcome = try RelicService.engrave(relicID: relic.id, subStat: 0, with: newKind, tier: .hero, player: &player, rng: &rng)
        XCTAssertEqual(outcome.after.kind, newKind)
        let span = RelicService.stoneSpan(RelicStone(kind: .gem, tier: .hero), kind: newKind)
        XCTAssertGreaterThanOrEqual(outcome.after.value, span.lowerBound)
        XCTAssertLessThanOrEqual(outcome.after.value, span.upperBound)
        let gemmed = try XCTUnwrap(player.relic(relic.id))
        XCTAssertEqual(gemmed.gemmed, 0)
        XCTAssertEqual(gemmed.subStats[0].kind, newKind)
        XCTAssertNil(gemmed.honed, "the gem clears that sub's honing")
        XCTAssertEqual(gemmed.subStats.count, 3)

        XCTAssertThrowsError(
            try RelicService.engrave(relicID: relic.id, subStat: 1, with: newKind, tier: .hero, player: &player, rng: &rng),
            "a second sub cannot be gemmed"
        )
        XCTAssertThrowsError(
            try RelicService.engrave(relicID: relic.id, subStat: 0, with: relic.mainStat.kind, tier: .hero, player: &player, rng: &rng),
            "never the main stat"
        )
        let again = RelicService.gemKinds(for: gemmed, replacing: 0)
        let other = try XCTUnwrap(again.first)
        XCTAssertNoThrow(try RelicService.engrave(relicID: relic.id, subStat: 0, with: other, tier: .hero, player: &player, rng: &rng), "the same sub may be gemmed again")
        XCTAssertEqual(RelicService.stoneCount(RelicStone(kind: .gem, tier: .hero), player: player), 1)
    }

    func testStoneRangesMatchTheGenresNumbers() {
        // A Legend whetstone is the genre's SPD +4–5, a Legend gem its 8–10.
        let hone = RelicService.stoneSpan(RelicStone(kind: .whetstone, tier: .legend), kind: .spd)
        XCTAssertEqual(hone.lowerBound, 4, accuracy: 0.5)
        XCTAssertEqual(hone.upperBound, 6, accuracy: 0.5)
        let gem = RelicService.stoneSpan(RelicStone(kind: .gem, tier: .legend), kind: .spd)
        XCTAssertEqual(gem.lowerBound, 8, accuracy: 0.5)
        XCTAssertEqual(gem.upperBound, 9.5, accuracy: 0.5)
        for stone in RelicStone.all {
            XCTAssertEqual(RelicStone.from(id: stone.id), stone)
            XCTAssertGreaterThan(stone.cost, 0)
        }
    }

    func testSellValueRisesWithQuality() {
        var rng = SeededRandom(seed: 37)
        let normal = RelicService.generate(grade: 6, quality: .normal, rng: &rng)
        let legend = RelicService.generate(grade: 6, quality: .legend, rng: &rng)
        XCTAssertGreaterThan(RelicService.sellValue(legend), RelicService.sellValue(normal))
    }

    func testUnequipAllEmptiesEverySlot() {
        var player = NewGame.create().player
        let starter = player.units[0]
        XCTAssertFalse(starter.equippedRelics.isEmpty)
        RelicService.unequipAll(unitID: starter.id, player: &player)
        XCTAssertTrue(player.units[0].equippedRelics.isEmpty)
        XCTAssertTrue(player.relics.allSatisfy { $0.equippedBy == nil })
    }
}
