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

    // MARK: - The premium (2026-09-17)
    //
    // The owner, with the Fuse board offering a 5★ light Ares and a 5★ dark
    // Horus: "we should NEVER offer a 5 star Light or dark mon like this. it
    // should ONLY be availble at like a 1% or less rate through the LD
    // scrolls (like summoners war). They are PREMIUM PREMIUM mons that need
    // to be better than the rest". Every path that hands a unit over is
    // measured here against that sentence.

    func testOnlyTheLightAndDarkScrollDrawsRadianceOrUmbra() {
        for banner in Banner.all where banner.id != Banner.lightAndDark.id {
            let leaked = SummonService.eligible(for: banner).filter { $0.element.isLightOrDark }
            XCTAssertEqual(leaked.map(\.id), [], "\(banner.id) can draw a Radiance or Umbra unit")
            let featuredLightDark = banner.featured.filter { UnitDatabase.blueprint($0)?.element.isLightOrDark ?? false }
            XCTAssertEqual(featuredLightDark, [], "\(banner.id) features a light or dark form")
        }
        let premium = SummonService.eligible(for: .lightAndDark)
        XCTAssertFalse(premium.isEmpty, "the premium scroll has nothing to give")
        XCTAssertTrue(premium.allSatisfy { $0.element.isLightOrDark })
        // And every light and dark unit with cards is on it: the scroll is
        // THE road, not one road among several.
        let everyLightDark = UnitDatabase.summonPool.filter { UnitDatabase.blueprint($0)?.element.isLightOrDark ?? false }
        XCTAssertEqual(Set(premium.map(\.id)), Set(everyLightDark))
        // A banner built with an empty pool means "everything summonable",
        // and the rule holds there too — the draw filters, not only the pools.
        XCTAssertTrue(Banner.standard.pool.isEmpty)
        let standardLeak = SummonService.eligible(for: .standard).filter { $0.element.isLightOrDark }
        XCTAssertEqual(standardLeak.map(\.id), [])
    }

    func testTheLightAndDarkScrollIsUnderOnePercentWithNoGuarantee() throws {
        let fiveStar: Double = ScrollType.lightDark.odds[5] ?? 0
        XCTAssertGreaterThan(fiveStar, 0)
        XCTAssertLessThanOrEqual(fiveStar, 0.01, "the owner: 1% or less")
        XCTAssertNil(Banner.lightAndDark.legendaryPity, "no hard pity — and so no soft pity, which keys off the same number")
        XCTAssertNotNil(Banner.lightAndDark.rarePity, "the 4★ guarantee stays")
        XCTAssertTrue(Banner.scrollBanners.contains { $0.id == Banner.lightAndDark.id }, "the premium scroll is on the summon screen")

        // A long run: no 5★ ever comes from a guarantee, and the counter is
        // free to run past any cap it used to have.
        var subject = player()
        subject.wallet.add(.lightDark, 400)
        var rng = SeededRandom(seed: 17)
        let pulls = try SummonService.summon(banner: .lightAndDark, count: 400, player: &subject, rng: &rng)
        for pull in pulls where pull.stars >= 5 {
            XCTAssertFalse(pull.fromPity, "\(pull.blueprint.id) came from a guarantee the scroll does not have")
        }
        let fours = pulls.filter { $0.stars == 4 }.count
        XCTAssertGreaterThan(fours, 0, "the 4★ guarantee should have fired at least once in 400")
    }

    func testTheSelectorAndTheNightMarketNeverOfferLightOrDark() {
        for candidate in SelectorService.candidates() {
            XCTAssertFalse(candidate.element.isLightOrDark, "the day-one selector offers \(candidate.id)")
        }
        for stars in [3, 4] {
            for id in NightMarketService.marketUnits(stars: stars) {
                XCTAssertFalse(UnitDatabase.blueprint(id)?.element.isLightOrDark ?? false, "the night market shelves \(id)")
            }
        }
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
