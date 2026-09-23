import XCTest
@testable import Pantheon

/// The Treasury (Docs/STORE.md): the catalog's numbers, the ladder's shape,
/// and the ledger's promise — every transaction pays a save exactly once,
/// a Blessing's days are never lost and never more than were bought, a
/// refund takes back what it paid and no more, and a restore brings back
/// days ahead and never divinity. No StoreKit here: `StoreReceipt` is what
/// `PurchaseService` makes of a verified transaction, and it is made by
/// hand. The numbers are mirrored in `tools/balance.py --store` and in
/// `Pantheon.storekit`; change one in all of them.
final class StoreTests: XCTestCase {

    // MARK: - Helpers

    private func player() -> Player {
        var subject = NewGame.create().player
        subject.wallet.divinity = 0
        subject.wallet.drachma = 0
        return subject
    }

    /// Noon, `days` from today in the test machine's own calendar: far from
    /// midnight, so a day's arithmetic never lands on a DST edge.
    private func noon(_ days: Int = 0) throws -> Date {
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()))
        return try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: today))
    }

    private func receipt(_ id: String, _ offer: StoreOffer, at date: Date, token: UUID? = nil) -> StoreReceipt {
        StoreReceipt(transactionID: id, productID: offer.productID, purchaseDate: date, appAccountToken: token)
    }

    private func deliver(_ receipt: StoreReceipt, to subject: inout Player, now: Date) -> TreasuryDelivery {
        var rng = SeededRandom(seed: 17)
        return TreasuryService.deliver(receipt, player: &subject, rng: &rng, now: now)
    }

    private func claim(_ subject: inout Player, now: Date) throws -> [ShopService.Grant] {
        var rng = SeededRandom(seed: 29)
        return try TreasuryService.claimBlessing(player: &subject, rng: &rng, now: now)
    }

    // MARK: - The catalog

    /// The ladder Docs/STORE.md §4.1 publishes: what each pack pays, the tier
    /// it is priced at, and its first-purchase double.
    func testTheCatalogIsTheOneTheDocPublishes() {
        let totals: [Int] = StoreCatalog.packs.map { $0.regularDivinity }
        let prices: [Double] = StoreCatalog.packs.map { $0.referencePrice }
        let firsts: [Int] = StoreCatalog.packs.map { $0.firstPurchaseDivinity }
        XCTAssertEqual(totals, [40, 210, 430, 880, 2_300, 5_000])
        XCTAssertEqual(prices, [0.99, 4.99, 9.99, 19.99, 49.99, 99.99])
        XCTAssertEqual(firsts, [80, 400, 800, 1_600, 4_000, 8_000])
        XCTAssertEqual(StoreCatalog.blessing.divinity, 300)
        XCTAssertEqual(StoreCatalog.blessingDaily, 50)
        XCTAssertEqual(StoreCatalog.blessingDays, 30)
        XCTAssertEqual(StoreCatalog.blessingMostDaysAhead, 180)
        XCTAssertEqual(StoreCatalog.starter.divinity, 500)
        XCTAssertEqual(StoreCatalog.starter.referencePrice, 4.99)
        XCTAssertEqual(StoreCatalog.blessing.referencePrice, 4.99)
    }

    /// The genre's shape: every pack pays more per dollar than the one below
    /// it (the intent — the numbers above may move, the shape may not).
    func testEveryPackIsBetterPerDollarThanTheOneBelowIt() {
        let rates: [Double] = StoreCatalog.packs.map { Double($0.regularDivinity) / $0.referencePrice }
        for index in 1..<rates.count {
            let below: Double = rates[index - 1]
            let this: Double = rates[index]
            XCTAssertGreaterThan(this, below, StoreCatalog.packs[index].name)
        }
    }

    /// A first purchase is exactly twice the base, in place of the bonus.
    func testAFirstPurchaseIsTwiceTheBase() {
        for pack in StoreCatalog.packs {
            let doubled: Int = pack.divinity * 2
            XCTAssertEqual(pack.firstPurchaseDivinity, doubled, pack.name)
            XCTAssertGreaterThan(pack.firstPurchaseDivinity, pack.regularDivinity, pack.name)
        }
    }

    /// The Blessing and the starter are the Treasury's best values, as the
    /// genre's monthly pass and starter are: each at least five times the
    /// best pack's rate per dollar.
    func testTheBlessingAndTheStarterOutValueTheBestPack() throws {
        let hoard = try XCTUnwrap(StoreCatalog.packs.last)
        let best: Double = Double(hoard.regularDivinity) / hoard.referencePrice
        let blessingTotal: Int = StoreCatalog.blessing.divinity + StoreCatalog.blessingDays * StoreCatalog.blessingDaily
        let blessingRate: Double = Double(blessingTotal) / StoreCatalog.blessing.referencePrice
        // The starter's worth in divinity, a term at a time: 500 divinity, five
        // Pantheon Scrolls at 100, the Divine Scroll at 600, and 100,000 drachma
        // at 300 to one (a literal sum of mixed types took the type checker
        // ten seconds and then failed, run 238).
        let starterDivinity: Double = 500
        let starterScrolls: Double = 5.0 * 100.0
        let starterDivine: Double = 600
        let starterDrachma: Double = 100_000.0 / 300.0
        let starterWorth: Double = starterDivinity + starterScrolls + starterDivine + starterDrachma
        let starterRate: Double = starterWorth / StoreCatalog.starter.referencePrice
        let floor: Double = best * 5
        XCTAssertEqual(blessingTotal, 1_800)
        XCTAssertGreaterThan(blessingRate, floor)
        XCTAssertGreaterThan(starterRate, floor)
    }

    /// Product ids are the App Store Connect ids, one each, under the
    /// bundle's own prefix, and every one is found back by its id.
    func testProductIDsAreUniqueAndFindable() {
        let ids: [String] = StoreCatalog.productIDs
        XCTAssertEqual(ids.count, 8)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertTrue(id.hasPrefix("com.pantheon.game."), id)
            XCTAssertEqual(StoreCatalog.offer(id)?.productID, id)
        }
        XCTAssertNil(StoreCatalog.offer("com.pantheon.game.nothing"))
    }

    /// The token is the account's, on every phone, and a proper UUID.
    func testTheAccountTokenIsStablePerAccount() {
        let first = StoreCatalog.accountToken(for: "000123.abc")
        let again = StoreCatalog.accountToken(for: "000123.abc")
        let other = StoreCatalog.accountToken(for: "guest-1")
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, other)
        let text: String = first.uuidString
        let version: String = String(text.dropFirst(14).prefix(1))
        XCTAssertEqual(version, "5")
    }

    // MARK: - Exactly once

    func testATransactionPaysExactlyOnce() throws {
        var subject = player()
        let now = try noon()
        let chalice = StoreCatalog.packs[1]
        let bought = receipt("1001", chalice, at: now)
        XCTAssertEqual(deliver(bought, to: &subject, now: now), .granted([.divinity(chalice.firstPurchaseDivinity)]))
        let afterFirst: Int = subject.wallet.divinity
        XCTAssertEqual(deliver(bought, to: &subject, now: now), .alreadyGranted)
        XCTAssertEqual(subject.wallet.divinity, afterFirst)
        XCTAssertEqual(subject.treasury?.entries.count, 1)
        XCTAssertTrue(TreasuryDelivery.alreadyGranted.mayFinish)
        XCTAssertFalse(TreasuryDelivery.notSaved.mayFinish)
    }

    /// The double is once per pack and per save: a second Chalice pays its
    /// base and its bonus, and a Phial still has its own double.
    func testTheDoubleIsOncePerPack() throws {
        var subject = player()
        let now = try noon()
        let chalice = StoreCatalog.packs[1]
        let phial = StoreCatalog.packs[0]
        XCTAssertTrue(TreasuryService.isFirstPurchase(chalice, player: subject))
        _ = deliver(receipt("2001", chalice, at: now), to: &subject, now: now)
        XCTAssertFalse(TreasuryService.isFirstPurchase(chalice, player: subject))
        XCTAssertTrue(TreasuryService.isFirstPurchase(phial, player: subject))
        _ = deliver(receipt("2002", chalice, at: now), to: &subject, now: now)
        let expected: Int = chalice.firstPurchaseDivinity + chalice.regularDivinity
        XCTAssertEqual(subject.wallet.divinity, expected)
    }

    /// A product this build does not sell is never paid and never finished.
    func testAnUnknownProductIsNeverPaid() throws {
        var subject = player()
        let now = try noon()
        let stranger = StoreReceipt(transactionID: "3001", productID: "com.pantheon.game.future", purchaseDate: now)
        let delivery = deliver(stranger, to: &subject, now: now)
        XCTAssertEqual(delivery, .unknownProduct)
        XCTAssertFalse(delivery.mayFinish)
        XCTAssertEqual(subject.wallet.divinity, 0)
        XCTAssertNil(subject.treasury)
    }

    func testTheStarterPaysItsContentsAndIsOwned() throws {
        var subject = player()
        let now = try noon()
        let pantheonBefore: Int = subject.wallet.count(of: .pantheonic)
        let divineBefore: Int = subject.wallet.count(of: .divine)
        XCTAssertFalse(TreasuryService.ownsStarter(player: subject))
        _ = deliver(receipt("4001", StoreCatalog.starter, at: now), to: &subject, now: now)
        XCTAssertTrue(TreasuryService.ownsStarter(player: subject))
        let pantheonAfter: Int = pantheonBefore + 5
        let divineAfter: Int = divineBefore + 1
        XCTAssertEqual(subject.wallet.divinity, 500)
        XCTAssertEqual(subject.wallet.drachma, 100_000)
        XCTAssertEqual(subject.wallet.count(of: .pantheonic), pantheonAfter)
        XCTAssertEqual(subject.wallet.count(of: .divine), divineAfter)
    }

    // MARK: - The Blessing

    /// 300 at once and the first day's 50 waiting on the day it is bought;
    /// thirty days later it has paid 1,800 and nothing more is owed.
    func testTheBlessingPaysAtOnceThenDaily() throws {
        var subject = player()
        let bought = try noon()
        _ = deliver(receipt("5001", StoreCatalog.blessing, at: bought), to: &subject, now: bought)
        XCTAssertEqual(subject.wallet.divinity, 300)
        let dayOne = try XCTUnwrap(TreasuryService.blessingStatus(player: subject, now: bought))
        XCTAssertEqual(dayOne.day, 1)
        XCTAssertEqual(dayOne.daysLeft, 30)
        XCTAssertEqual(dayOne.waiting, 1)
        _ = try claim(&subject, now: bought)
        XCTAssertEqual(subject.wallet.divinity, 350)
        XCTAssertThrowsError(try claim(&subject, now: bought))
        for day in 1..<30 {
            _ = try claim(&subject, now: try noon(day))
        }
        XCTAssertEqual(subject.wallet.divinity, 1_800)
        XCTAssertNil(TreasuryService.blessingStatus(player: subject, now: try noon(30)))
    }

    /// A missed day waits for the next claim; nothing is forfeited, and no
    /// clock can make it pay more than its thirty days.
    func testMissedDaysWaitAndTheTotalNeverPassesThirty() throws {
        var subject = player()
        let bought = try noon()
        _ = deliver(receipt("5101", StoreCatalog.blessing, at: bought), to: &subject, now: bought)
        let later = try XCTUnwrap(TreasuryService.blessingStatus(player: subject, now: try noon(4)))
        XCTAssertEqual(later.waiting, 5)
        _ = try claim(&subject, now: try noon(4))
        XCTAssertEqual(subject.wallet.divinity, 550)
        _ = try claim(&subject, now: try noon(400))
        XCTAssertEqual(subject.wallet.divinity, 1_800)
        XCTAssertThrowsError(try claim(&subject, now: try noon(401)))
    }

    /// Bought again while it runs, it runs thirty days longer, and the
    /// Treasury stops selling once 180 days would wait ahead.
    func testBuyingWhileItRunsAddsThirtyDaysUpToTheCap() throws {
        var subject = player()
        let bought = try noon()
        _ = deliver(receipt("5201", StoreCatalog.blessing, at: bought), to: &subject, now: bought)
        _ = deliver(receipt("5202", StoreCatalog.blessing, at: try noon(10)), to: &subject, now: try noon(10))
        let running = try XCTUnwrap(TreasuryService.blessingStatus(player: subject, now: try noon(10)))
        XCTAssertEqual(running.days, 60)
        XCTAssertEqual(running.daysLeft, 50)
        XCTAssertEqual(subject.wallet.divinity, 600)
        XCTAssertTrue(TreasuryService.canExtendBlessing(player: subject, now: try noon(10)))
        for index in 0..<4 {
            _ = deliver(receipt("53\(index)", StoreCatalog.blessing, at: try noon(10)), to: &subject, now: try noon(10))
        }
        XCTAssertFalse(TreasuryService.canExtendBlessing(player: subject, now: try noon(10)))
    }

    /// Bought after it ended, the old one's waiting days are paid at once and
    /// a new thirty begins today.
    func testBuyingAfterItEndedPaysWhatWasWaiting() throws {
        var subject = player()
        let bought = try noon()
        _ = deliver(receipt("5401", StoreCatalog.blessing, at: bought), to: &subject, now: bought)
        _ = try claim(&subject, now: try noon(26))
        let paidSoFar: Int = subject.wallet.divinity
        let upFrontAndTwentySevenDays: Int = 300 + 27 * 50
        XCTAssertEqual(paidSoFar, upFrontAndTwentySevenDays)
        _ = deliver(receipt("5402", StoreCatalog.blessing, at: try noon(40)), to: &subject, now: try noon(40))
        let expected: Int = paidSoFar + 300 + 3 * 50
        XCTAssertEqual(subject.wallet.divinity, expected)
        let fresh = try XCTUnwrap(TreasuryService.blessingStatus(player: subject, now: try noon(40)))
        XCTAssertEqual(fresh.day, 1)
        XCTAssertEqual(fresh.daysLeft, 30)
    }

    // MARK: - Refunds

    /// A refund takes back what the transaction paid, once, never below
    /// zero; a refund of something this save was never paid changes nothing.
    func testARefundTakesBackWhatItPaidOnce() throws {
        var subject = player()
        let now = try noon()
        let hoard = StoreCatalog.packs[5]
        var bought = receipt("6001", hoard, at: now)
        _ = deliver(bought, to: &subject, now: now)
        subject.wallet.divinity -= 5_000
        bought.revocationDate = now
        XCTAssertTrue(TreasuryService.revoke(bought, player: &subject))
        XCTAssertEqual(subject.wallet.divinity, 0)
        subject.wallet.divinity = 100
        XCTAssertFalse(TreasuryService.revoke(bought, player: &subject))
        XCTAssertEqual(subject.wallet.divinity, 100)
        let stranger = StoreReceipt(transactionID: "6099", productID: hoard.productID, purchaseDate: now, revocationDate: now)
        XCTAssertFalse(TreasuryService.revoke(stranger, player: &subject))
        XCTAssertEqual(subject.wallet.divinity, 100)
        XCTAssertFalse(TreasuryService.isFirstPurchase(hoard, player: subject))
    }

    /// A refunded Blessing loses its days not yet paid.
    func testARefundedBlessingLosesItsUnpaidDays() throws {
        var subject = player()
        let bought = try noon()
        var blessing = receipt("6101", StoreCatalog.blessing, at: bought)
        _ = deliver(blessing, to: &subject, now: bought)
        _ = try claim(&subject, now: try noon(4))
        blessing.revocationDate = try noon(4)
        TreasuryService.revoke(blessing, player: &subject)
        XCTAssertNil(TreasuryService.blessingStatus(player: subject, now: try noon(5)))
        XCTAssertEqual(subject.wallet.divinity, 250)
    }

    // MARK: - Restoring

    /// A Blessing this save was never paid restores its days AHEAD — ten of
    /// thirty on its twentieth day — and never its divinity.
    func testRestoringGivesOnlyTheDaysAhead() throws {
        var subject = player()
        let elsewhere = receipt("7001", StoreCatalog.blessing, at: try noon(-20))
        let days = TreasuryService.restoreBlessing([elsewhere], player: &subject, now: try noon())
        XCTAssertEqual(days, 10)
        XCTAssertEqual(subject.wallet.divinity, 0)
        let restored = try XCTUnwrap(TreasuryService.blessingStatus(player: subject, now: try noon()))
        XCTAssertEqual(restored.daysLeft, 10)
        XCTAssertEqual(restored.waiting, 1)
        XCTAssertEqual(TreasuryService.restoreBlessing([elsewhere], player: &subject, now: try noon()), 0)
    }

    /// What the save already knows, what was refunded and what has run out
    /// restore nothing; two stacked purchases restore as they stacked.
    func testRestoreSkipsTheKnownTheRefundedAndTheSpent() throws {
        var subject = player()
        let now = try noon()
        _ = deliver(receipt("7101", StoreCatalog.blessing, at: now), to: &subject, now: now)
        let known = receipt("7101", StoreCatalog.blessing, at: now)
        var refunded = receipt("7102", StoreCatalog.blessing, at: try noon(-5))
        refunded.revocationDate = now
        let spent = receipt("7103", StoreCatalog.blessing, at: try noon(-90))
        XCTAssertEqual(TreasuryService.restoreBlessing([known, refunded, spent], player: &subject, now: now), 0)

        var fresh = player()
        let first = receipt("7201", StoreCatalog.blessing, at: try noon(-10))
        let second = receipt("7202", StoreCatalog.blessing, at: try noon(-5))
        let stacked = TreasuryService.restoreBlessing([second, first], player: &fresh, now: now)
        XCTAssertEqual(stacked, 50)
    }

    // MARK: - The save

    /// `Player.treasury` round-trips, and a save written before it opens.
    func testTheLedgerRoundTripsAndAnOldSaveStillOpens() throws {
        var subject = player()
        let now = try noon()
        _ = deliver(receipt("8001", StoreCatalog.blessing, at: now), to: &subject, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(subject)
        let back = try decoder.decode(Player.self, from: data)
        XCTAssertEqual(back.treasury, subject.treasury)

        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["treasury"] = nil
        let old = try decoder.decode(Player.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.treasury)
        XCTAssertTrue(TreasuryService.isFirstPurchase(StoreCatalog.packs[0], player: old))
        XCTAssertNil(TreasuryService.blessingStatus(player: old, now: now))
    }
}
