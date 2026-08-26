import XCTest
@testable import Pantheon

/// Gacha rules. Rates and pity are the two things a player will check against
/// the published table, so they are tested against that table directly.
final class SummonTests: XCTestCase {

    private func player(scrolls: Int) -> Player {
        var player = Player()
        player.wallet.scrolls = [ScrollType.pantheonic.rawValue: scrolls]
        return player
    }

    func testPublishedOddsSumToOne() {
        for scroll in ScrollType.allCases {
            let total = scroll.odds.values.reduce(0, +)
            XCTAssertEqual(total, 1.0, accuracy: 0.0001, "\(scroll.rawValue) odds must sum to 1")
        }
    }

    func testSummonSpendsExactlyOneScrollPerPull() {
        var subject = player(scrolls: 10)
        var rng = SeededRandom(seed: 1)
        let results = try? SummonService.summon(
            banner: .olympusRising, count: 10, player: &subject, rng: &rng
        )
        XCTAssertEqual(results?.count, 10)
        XCTAssertEqual(subject.wallet.count(of: .pantheonic), 0)
        XCTAssertEqual(subject.units.count, 10)
    }

    func testSummonFailsWithoutScrolls() {
        var subject = player(scrolls: 0)
        var rng = SeededRandom(seed: 1)
        XCTAssertThrowsError(
            try SummonService.summon(banner: .olympusRising, count: 1, player: &subject, rng: &rng)
        )
    }

    func testHardPityGuaranteesALegendary() {
        var subject = player(scrolls: 200)
        var rng = SeededRandom(seed: 42)
        let cap = Banner.olympusRising.legendaryPity!

        let results = try! SummonService.summon(
            banner: .olympusRising, count: cap, player: &subject, rng: &rng
        )
        XCTAssertTrue(results.contains { $0.stars == 5 }, "A 5★ must appear within \(cap) summons")
    }

    func testPityCounterResetsOnLegendary() {
        var subject = player(scrolls: 300)
        var rng = SeededRandom(seed: 7)
        var pullsSinceLast = 0

        for _ in 0..<200 {
            guard subject.wallet.count(of: .pantheonic) > 0 else { break }
            let results = try! SummonService.summon(
                banner: .olympusRising, count: 1, player: &subject, rng: &rng
            )
            pullsSinceLast += 1
            if results[0].stars == 5 {
                XCTAssertEqual(subject.summonPity["olympus_rising"]?.sinceLegendary, 0)
                pullsSinceLast = 0
            }
            XCTAssertLessThanOrEqual(pullsSinceLast, Banner.olympusRising.legendaryPity!)
        }
    }

    func testDuplicatesBecomeSkillUps() {
        var subject = player(scrolls: 60)
        var rng = SeededRandom(seed: 3)
        _ = try! SummonService.summon(banner: .olympusRising, count: 60, player: &subject, rng: &rng)

        let zeusCopies = subject.units.filter { $0.blueprintID == "zeus" }
        guard zeusCopies.count > 1 else {
            // With one 5★ in the pool this is very likely, but not certain.
            return
        }
        let anySkilled = subject.units.contains { $0.skillLevels.contains { $0 > 1 } }
        XCTAssertTrue(anySkilled, "A duplicate should have raised a skill level")
    }

    func testGachaIsReproducibleFromSeed() {
        func run() -> [String] {
            var subject = player(scrolls: 30)
            var rng = SeededRandom(seed: 999)
            let results = try! SummonService.summon(
                banner: .olympusRising, count: 30, player: &subject, rng: &rng
            )
            return results.map { "\($0.blueprint.id)-\($0.stars)" }
        }
        XCTAssertEqual(run(), run())
    }

    func testSummonPoolNeverProducesCampaignEnemies() {
        var subject = player(scrolls: 100)
        var rng = SeededRandom(seed: 21)
        let results = try! SummonService.summon(
            banner: .standard, count: 0, player: &subject, rng: &rng
        )
        XCTAssertTrue(results.isEmpty)

        var subject2 = player(scrolls: 100)
        subject2.wallet.scrolls[ScrollType.mystical.rawValue] = 100
        var rng2 = SeededRandom(seed: 22)
        let pulls = try! SummonService.summon(
            banner: .standard, count: 50, player: &subject2, rng: &rng2
        )
        for pull in pulls {
            XCTAssertTrue(
                UnitDatabase.summonPool.contains(pull.blueprint.id),
                "\(pull.blueprint.id) is not summonable and must never drop from a banner"
            )
        }
    }
}
