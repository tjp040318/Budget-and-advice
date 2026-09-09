import XCTest
@testable import Pantheon

/// The bazaar: every price is paid in the game's own currencies, the daily
/// offering is once a day, and a purchase that cannot be paid for changes
/// nothing.
final class ShopTests: XCTestCase {

    private func player() -> Player {
        var player = NewGame.create().player
        player.wallet.divinity = 1_000
        player.wallet.drachma = 100_000
        player.wallet.laurels = 500
        return player
    }

    func testBuyingScrollsDeductsDivinity() throws {
        var subject = player()
        var rng = SeededRandom(seed: 1)
        let item = try XCTUnwrap(ShopService.item("scroll_mystical_10"))
        let before = subject.wallet.count(of: .mystical)
        try ShopService.buy(item, player: &subject, rng: &rng)
        XCTAssertEqual(subject.wallet.divinity, 1_000 - item.price.amount)
        XCTAssertEqual(subject.wallet.count(of: .mystical), before + 10)
    }

    func testCannotAffordChangesNothing() {
        var subject = player()
        subject.wallet.divinity = 10
        var rng = SeededRandom(seed: 2)
        let item = ShopService.item("relic_pack_5")!
        let relicsBefore = subject.relics.count
        XCTAssertThrowsError(try ShopService.buy(item, player: &subject, rng: &rng))
        XCTAssertEqual(subject.wallet.divinity, 10)
        XCTAssertEqual(subject.relics.count, relicsBefore)
    }

    func testRelicPacksRollTheGradeOnTheLabel() throws {
        var subject = player()
        var rng = SeededRandom(seed: 3)
        let pack = try XCTUnwrap(ShopService.item("relic_laurels_6"))
        let before = subject.relics.count
        try ShopService.buy(pack, player: &subject, rng: &rng)
        XCTAssertEqual(subject.relics.count, before + 1)
        XCTAssertEqual(subject.relics.last?.grade, 6)
        XCTAssertEqual(subject.wallet.laurels, 500 - pack.price.amount)
    }

    func testDailyOfferingIsOncePerDay() throws {
        var subject = player()
        var rng = SeededRandom(seed: 4)
        let daily = try XCTUnwrap(ShopService.items(in: .daily).first)
        let noon = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(ShopService.isDailyAvailable(player: subject, now: noon))

        let energyBefore = subject.wallet.energy
        let scrollsBefore = subject.wallet.count(of: .mystical)
        try ShopService.buy(daily, player: &subject, rng: &rng, now: noon)
        XCTAssertEqual(subject.wallet.energy, energyBefore + 10)
        XCTAssertEqual(subject.wallet.count(of: .mystical), scrollsBefore + 1)
        XCTAssertFalse(ShopService.isDailyAvailable(player: subject, now: noon.addingTimeInterval(3_600)))
        XCTAssertThrowsError(try ShopService.buy(daily, player: &subject, rng: &rng, now: noon.addingTimeInterval(3_600)))

        // Tomorrow it is back.
        XCTAssertTrue(ShopService.isDailyAvailable(player: subject, now: noon.addingTimeInterval(36 * 3_600)))
    }

    func testEnergyRefillGoesToTheCapAndNoFurther() throws {
        var subject = player()
        var rng = SeededRandom(seed: 5)
        subject.wallet.energy = 3
        try ShopService.buy(try XCTUnwrap(ShopService.item("energy_refill")), player: &subject, rng: &rng)
        XCTAssertEqual(subject.wallet.energy, subject.wallet.maxEnergy)

        subject.wallet.energy = subject.wallet.maxEnergy + 20
        try ShopService.buy(try XCTUnwrap(ShopService.item("energy_refill")), player: &subject, rng: &rng)
        XCTAssertEqual(subject.wallet.energy, subject.wallet.maxEnergy + 20)
    }

    func testOldSavesDecodeWithoutTheShopFields() throws {
        // A save written before the shop existed has no daily-claim key. It
        // must still load, or the update would wipe accounts.
        var subject = player()
        subject.lastDailyPackClaim = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(subject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Player.self, from: data)
        XCTAssertNil(decoded.lastDailyPackClaim)
        XCTAssertEqual(decoded.wallet.divinity, subject.wallet.divinity)
    }
}
