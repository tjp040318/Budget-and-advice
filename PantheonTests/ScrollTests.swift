import XCTest
@testable import Pantheon

/// The scroll banners give what they say on the label: an element scroll
/// only its element, the light & dark scroll only the sun's and the night's,
/// the unknown scroll only commons, the divine scroll nothing under a 4★.
final class ScrollTests: XCTestCase {

    private func player() -> Player {
        var player = NewGame.create().player
        for scroll in ScrollType.allCases { player.wallet.add(scroll, 60) }
        return player
    }

    func testEveryScrollHasOddsThatSumToOne() {
        for scroll in ScrollType.allCases {
            XCTAssertEqual(scroll.odds.values.reduce(0, +), 1.0, accuracy: 1e-9, scroll.rawValue)
        }
    }

    func testElementScrollsGiveOnlyTheirElement() throws {
        for (banner, element) in [(Banner.emberScroll, Element.ember), (Banner.tideScroll, .tide), (Banner.galeScroll, .gale)] {
            var subject = player()
            var rng = SeededRandom(seed: 5)
            let pulls = try SummonService.summon(banner: banner, count: 40, player: &subject, rng: &rng)
            XCTAssertEqual(pulls.count, 40)
            for pull in pulls {
                XCTAssertEqual(pull.blueprint.element, element, "\(banner.id) gave \(pull.blueprint.id)")
            }
        }
    }

    func testLightAndDarkGivesOnlyRadianceAndUmbra() throws {
        var subject = player()
        var rng = SeededRandom(seed: 6)
        let pulls = try SummonService.summon(banner: .lightAndDark, count: 40, player: &subject, rng: &rng)
        for pull in pulls {
            XCTAssertTrue([Element.radiance, .umbra].contains(pull.blueprint.element), pull.blueprint.id)
        }
    }

    func testUnknownScrollGivesCommonsAndDivineGivesNoneUnderFour() throws {
        var subject = player()
        var rng = SeededRandom(seed: 7)
        for pull in try SummonService.summon(banner: .unknownScroll, count: 30, player: &subject, rng: &rng) {
            XCTAssertEqual(pull.blueprint.naturalStars, 3, pull.blueprint.id)
        }
        for pull in try SummonService.summon(banner: .divineScroll, count: 30, player: &subject, rng: &rng) {
            XCTAssertGreaterThanOrEqual(pull.blueprint.naturalStars, 4, pull.blueprint.id)
        }
    }

    func testScrollBannersSpendTheirOwnScroll() throws {
        var subject = player()
        var rng = SeededRandom(seed: 8)
        let before = subject.wallet.count(of: .ember)
        let mystical = subject.wallet.count(of: .mystical)
        _ = try SummonService.summon(banner: .emberScroll, count: 3, player: &subject, rng: &rng)
        XCTAssertEqual(subject.wallet.count(of: .ember), before - 3)
        XCTAssertEqual(subject.wallet.count(of: .mystical), mystical, "the mystical scrolls are untouched")
    }

    func testTheBazaarSellsEveryScrollPackItPromises() throws {
        var subject = player()
        subject.wallet.divinity = 10_000
        subject.wallet.drachma = 1_000_000
        subject.wallet.laurels = 1_000
        var rng = SeededRandom(seed: 9)
        for item in ShopService.items(in: .scrolls) + ShopService.items(in: .laurels) {
            guard case .scrolls(let scroll, let count) = item.grant else { continue }
            let before = subject.wallet.count(of: scroll)
            try ShopService.buy(item, player: &subject, rng: &rng)
            XCTAssertEqual(subject.wallet.count(of: scroll), before + count, item.id)
        }
    }
}
