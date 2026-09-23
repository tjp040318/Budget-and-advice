import Foundation

// MARK: - The Treasury's hold on the save (2026-09-23; Docs/STORE.md)
//
// `PurchaseService` hands a verified transaction to the store that is open;
// this file pays it into the save through `update`, the store's mutation
// path, and WRITES THE SAVE before it answers, because the answer is what
// lets the App Store be told the transaction is finished. What a transaction
// pays, and the Blessing's days, are `TreasuryService`'s rules.
//
// The order (Docs/STORE.md §3.3): grant and record in one `update` → a
// synchronous `SaveStore.save` → only then `.granted`/`.alreadyGranted`. A
// crash before the write leaves the transaction unfinished and the ledger on
// disk without it, so the next launch delivers it again; a crash after the
// write leaves it unfinished with the ledger knowing it, so the next launch
// only finishes it. Either way it pays exactly once.

extension GameStore: PurchaseDelivering {

    /// The UUID every purchase carries for this account.
    var purchaseAccountToken: UUID { StoreCatalog.accountToken(for: account.id) }

    /// A retired store (a sign-out, a reset, a deletion in progress) takes
    /// nothing: the transaction waits for the next store.
    var acceptsPurchases: Bool { !retired }

    func deliverPurchase(_ receipt: StoreReceipt) -> TreasuryDelivery {
        guard !retired else { return .closed }
        var rng = makeRandom()
        let now = Date()
        var delivery = TreasuryDelivery.alreadyGranted
        update { player in
            delivery = TreasuryService.deliver(receipt, player: &player, rng: &rng, now: now)
        }
        guard delivery.mayFinish else { return delivery }
        // Durable before the App Store is told. `update` has already
        // scheduled the ordinary save and the cloud copy; this write is the
        // one the answer waits for.
        do {
            try SaveStore.save(SaveGame(player: player, rngSeed: nextSeed()), key: account.storageKey)
        } catch {
            lastError = "The purchase is safe with the App Store and arrives when the game can save: \(error.localizedDescription)"
            return .notSaved
        }
        return delivery
    }

    func revokePurchase(_ receipt: StoreReceipt) {
        guard !retired, player.treasury?.entry(receipt.transactionID) != nil else { return }
        update { player in
            _ = TreasuryService.revoke(receipt, player: &player)
        }
    }

    func restoreBlessing(_ receipts: [StoreReceipt]) -> Int {
        guard !retired else { return 0 }
        var trial = player
        let days = TreasuryService.restoreBlessing(receipts, player: &trial, now: Date())
        guard days > 0 else { return 0 }
        update { player in
            player = trial
        }
        return days
    }

    // MARK: - What the Treasury reads

    /// The Blessing for its card: nil when there is none running and none
    /// waiting.
    var blessingStatus: BlessingStatus? { TreasuryService.blessingStatus(player: player, now: Date()) }

    /// A Blessing day is waiting: the gold dot on the Treasury's rail row.
    var treasuryHasClaim: Bool { (blessingStatus?.waiting ?? 0) > 0 }

    /// True until this save has bought the pack once: its "×2".
    func isFirstPurchase(_ offer: StoreOffer) -> Bool {
        TreasuryService.isFirstPurchase(offer, player: player)
    }

    var ownsStarter: Bool { TreasuryService.ownsStarter(player: player) }

    /// Another thirty days may be bought: fewer than 180 would be waiting.
    var canExtendBlessing: Bool { TreasuryService.canExtendBlessing(player: player, now: Date()) }

    /// Claims every Blessing day waiting. Nil, with the reason shown, when
    /// nothing is.
    @discardableResult
    func claimBlessing() -> [ShopService.Grant]? {
        var rng = makeRandom()
        let now = Date()
        return attempt { player in
            try TreasuryService.claimBlessing(player: &player, rng: &rng, now: now)
        }
    }

    #if DEBUG
    /// The tour's Treasury: the Chalice bought once (its "×2" gone, the
    /// other five still showing theirs) and the Blessing on day 12 of 30
    /// with today's 50 waiting. The starter is left unbought. Idempotent:
    /// every launch sets the same ledger.
    func seedTourTreasury(now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -11, to: today) ?? today
        let chalice = StoreCatalog.packs[1]
        update { player in
            var ledger = TreasuryLedger()
            ledger.entries = [
                TreasuryEntry(transactionID: "tour-chalice", productID: chalice.productID,
                              purchasedAt: firstDay.addingTimeInterval(-86_400),
                              divinity: chalice.firstPurchaseDivinity, days: 0, restored: false),
                TreasuryEntry(transactionID: "tour-blessing", productID: StoreCatalog.blessing.productID,
                              purchasedAt: firstDay, divinity: StoreCatalog.blessing.divinity,
                              days: StoreCatalog.blessingDays, restored: false),
            ]
            ledger.blessing = TreasuryPass(firstDay: firstDay, days: StoreCatalog.blessingDays, daysPaid: 11)
            player.treasury = ledger
        }
    }
    #endif
}
