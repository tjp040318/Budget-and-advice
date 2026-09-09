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
}
