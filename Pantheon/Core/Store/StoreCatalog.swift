import Foundation
import CryptoKit

// MARK: - The Treasury's catalog (2026-09-23; Docs/STORE.md)
//
// Real-money products and what each one pays. This file is PURE: no
// StoreKit, no clock but the one passed in, no disk. StoreKit lives in
// `PurchaseService`, the store's side in `GameStore+Store.swift`. Every
// number here is mirrored in `tools/balance.py --store` (which also reads
// `Pantheon.storekit` at the repository's root and refuses to run if its
// products drift from these) and pinned in `PantheonTests/StoreTests.swift`:
// change a number in all four.

/// What a product is, which decides how it is delivered.
enum StoreOfferKind: String, Codable, Sendable {
    /// A divinity pack: a consumable whose base is doubled on its first
    /// purchase in a save.
    case divinity
    /// The starter: a consumable the Treasury sells a save once.
    case starter
    /// The Blessing: a non-renewing subscription of thirty days.
    case blessing
}

/// One product the Treasury sells: the App Store's product id and what it
/// pays. The PRICE is never here — the App Store sets it per storefront and
/// the Treasury prints `Product.displayPrice` or "—". `referencePrice` is the
/// US tier to pick in App Store Connect, for the doc, the balance sheet and
/// the tests' per-dollar ladder.
struct StoreOffer: Identifiable, Equatable, Sendable {
    let productID: String
    let kind: StoreOfferKind
    /// The name on the tile and the display name in App Store Connect.
    let name: String
    /// A pack's base divinity; the starter's divinity; the Blessing's
    /// divinity paid at once.
    let divinity: Int
    /// A pack's bonus on every purchase after its first.
    let bonus: Int
    /// The price tier in US dollars (Docs/STORE.md §4).
    let referencePrice: Double
    /// The pile a pack's tile draws, 1 (a phial) to 6 (a hoard); 0 otherwise.
    let tier: Int

    var id: String { productID }

    /// What a repeat purchase of a pack pays: its base and its bonus.
    var regularDivinity: Int { divinity + bonus }

    /// What a pack's FIRST purchase in a save pays: its base twice, in place
    /// of its bonus (Genshin's rule, the genre's; Docs/STORE.md §1).
    var firstPurchaseDivinity: Int { divinity * 2 }

    /// The tile's name: "Chalice" for "Chalice of Divinity", "Blessing" for
    /// "Blessing of the Gods"; a name with no "of" is itself.
    var shortName: String { name.components(separatedBy: " of ").first ?? name }
}

enum StoreCatalog {

    /// The six divinity packs, cheapest first. The ladder climbs 1.24x per
    /// dollar from the Phial to the Hoard (Genshin's climbs 1.33x), and a
    /// pull costs what it costs across the genre: $2.00 at the top, $2.48
    /// at the bottom (Docs/STORE.md §3.1, option A).
    static let packs: [StoreOffer] = [
        StoreOffer(productID: "com.pantheon.game.divinity.phial", kind: .divinity, name: "Phial of Divinity",
                   divinity: 40, bonus: 0, referencePrice: 0.99, tier: 1),
        StoreOffer(productID: "com.pantheon.game.divinity.chalice", kind: .divinity, name: "Chalice of Divinity",
                   divinity: 200, bonus: 10, referencePrice: 4.99, tier: 2),
        StoreOffer(productID: "com.pantheon.game.divinity.amphora", kind: .divinity, name: "Amphora of Divinity",
                   divinity: 400, bonus: 30, referencePrice: 9.99, tier: 3),
        StoreOffer(productID: "com.pantheon.game.divinity.coffer", kind: .divinity, name: "Coffer of Divinity",
                   divinity: 800, bonus: 80, referencePrice: 19.99, tier: 4),
        StoreOffer(productID: "com.pantheon.game.divinity.chest", kind: .divinity, name: "Chest of Divinity",
                   divinity: 2_000, bonus: 300, referencePrice: 49.99, tier: 5),
        StoreOffer(productID: "com.pantheon.game.divinity.hoard", kind: .divinity, name: "Hoard of Divinity",
                   divinity: 4_000, bonus: 1_000, referencePrice: 99.99, tier: 6),
    ]

    /// "A Demigod's Welcome": sold once to a save (a consumable, so it is
    /// never RESTORED into a second account on the phone and paid again —
    /// Docs/STORE.md §3.2). Its divinity is `divinity`; the rest is
    /// `starterGrants`.
    static let starter = StoreOffer(productID: "com.pantheon.game.starter.welcome", kind: .starter,
                                    name: "A Demigod's Welcome", divinity: 500, bonus: 0,
                                    referencePrice: 4.99, tier: 0)

    /// "Blessing of the Gods": a non-renewing subscription. `divinity` is
    /// paid at once, then `blessingDaily` for each of `blessingDays` days.
    static let blessing = StoreOffer(productID: "com.pantheon.game.blessing30", kind: .blessing,
                                     name: "Blessing of the Gods", divinity: 300, bonus: 0,
                                     referencePrice: 4.99, tier: 0)

    /// The Blessing's length, its day's divinity, and how many days may wait
    /// ahead before the Treasury stops selling another thirty (the Welkin
    /// Moon's 180).
    static let blessingDays = 30
    static let blessingDaily = 50
    static let blessingMostDaysAhead = 180

    /// The starter's whole contents, its divinity first: about 1,930
    /// divinity-equivalent, 7.7x the Hoard's rate per dollar. The Divine
    /// Scroll and the Pantheon Scrolls summon at their published odds.
    static let starterGrants: [ShopService.Grant] = [
        .divinity(500),
        .scrolls(.pantheonic, 5),
        .scrolls(.divine, 1),
        .drachma(100_000),
    ]

    /// Everything, in the order the Treasury lists it.
    static var all: [StoreOffer] { [blessing, starter] + packs }

    /// What `Product.products(for:)` asks the App Store for.
    static var productIDs: [String] { all.map(\.productID) }

    static func offer(_ productID: String) -> StoreOffer? {
        all.first { $0.productID == productID }
    }

    /// The UUID a purchase carries as its `appAccountToken`, so the App
    /// Store's record of a transaction names the demigod who bought it: the
    /// first sixteen bytes of SHA-256 of the account's id, laid out as a
    /// version-5 UUID. Stable per account on every phone (an Apple account's
    /// id is Apple's), different for every account, and never the id itself.
    static func accountToken(for accountID: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(("pantheon.treasury." + accountID).utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - A transaction, as the game reads it

/// What the game needs from an App Store transaction, and nothing of
/// StoreKit: `PurchaseService` makes one from each verified `Transaction`,
/// and the tests make them by hand.
struct StoreReceipt: Equatable, Sendable {
    /// The App Store's transaction id, as a string (it is a UInt64; a string
    /// survives every JSON reader the save's cloud copy meets).
    let transactionID: String
    let productID: String
    let purchaseDate: Date
    /// Set when the App Store refunded or revoked it.
    var revocationDate: Date? = nil
    var appAccountToken: UUID? = nil
    var quantity: Int = 1

    var isRevoked: Bool { revocationDate != nil }
}

// MARK: - The ledger, in the save

/// Every App Store transaction this save has been paid for, and the
/// Blessing's days. In the SAVE and not a file of its own: the grant and the
/// record of it are one mutation of `Player` and one atomic write, so there
/// is no moment in which either exists without the other (Docs/STORE.md
/// §3.3). `Player.treasury`, Optional like every save field since the first.
struct TreasuryLedger: Codable, Equatable, Sendable {
    var entries: [TreasuryEntry] = []
    var blessing: TreasuryPass? = nil

    func entry(_ transactionID: String) -> TreasuryEntry? {
        entries.first { $0.transactionID == transactionID }
    }

    func knows(_ transactionID: String) -> Bool { entry(transactionID) != nil }

    /// Purchases of a product this save has been paid for, refunded ones
    /// included — a refund does not hand a pack its first-purchase double
    /// back, and a refunded starter is not sold again.
    func count(of productID: String) -> Int {
        entries.filter { $0.productID == productID }.count
    }
}

/// One transaction paid into this save.
struct TreasuryEntry: Codable, Equatable, Sendable {
    var transactionID: String
    var productID: String
    var purchasedAt: Date
    /// The divinity this transaction put in the wallet, which a refund takes
    /// back.
    var divinity: Int
    /// The Blessing days it added.
    var days: Int
    /// True for a Blessing restored from the App Store's history into a save
    /// that was never paid it: its days ahead, never its divinity.
    var restored: Bool
    /// True once a refund has taken it back.
    var revoked: Bool? = nil
}

/// The Blessing as it stands: from the start of the local day it began, for
/// `days` days, of which `daysPaid` have been claimed.
struct TreasuryPass: Codable, Equatable, Sendable {
    var firstDay: Date
    var days: Int
    var daysPaid: Int
}

/// The Blessing on a given day, for the card.
struct BlessingStatus: Equatable, Sendable {
    /// Today's day of it, 1-based, never past its last.
    let day: Int
    let days: Int
    /// Days left including today; 0 once it has ended.
    let daysLeft: Int
    /// Days it has run that are not yet paid.
    let waiting: Int

    var isRunning: Bool { daysLeft > 0 }
    var divinityWaiting: Int { waiting * StoreCatalog.blessingDaily }
}

/// What delivering a transaction came to. Only `.granted` and
/// `.alreadyGranted` let the App Store be told it is finished.
enum TreasuryDelivery: Equatable, Sendable {
    /// Paid now; the grants, flattened, for the receipt.
    case granted([ShopService.Grant])
    /// This save was already paid it.
    case alreadyGranted
    /// A product this build does not sell (a newer build's): left unfinished
    /// for the build that does.
    case unknownProduct
    /// The store is retired (a sign-out or a deletion in progress): left
    /// unfinished for the next store.
    case closed
    /// Granted in memory but the save could not be written: left unfinished,
    /// so a relaunch delivers it again against the save on disk.
    case notSaved

    var mayFinish: Bool {
        switch self {
        case .granted, .alreadyGranted: return true
        case .unknownProduct, .closed, .notSaved: return false
        }
    }
}

enum TreasuryError: Error, LocalizedError {
    case noBlessing
    case nothingWaiting

    var errorDescription: String? {
        switch self {
        case .noBlessing: return "There is no Blessing to claim from."
        case .nothingWaiting: return "Today's Blessing is claimed. The next day's comes at midnight."
        }
    }
}

// MARK: - The rules

/// Delivery, the Blessing's days, refunds and restores, on a `Player`. Pure:
/// the clock is a parameter and nothing here touches StoreKit or the disk.
enum TreasuryService {

    // MARK: Delivering a purchase

    /// Pays a verified transaction into the save, once. A transaction the
    /// ledger knows pays nothing (`.alreadyGranted`); a product this build
    /// does not sell pays nothing (`.unknownProduct`). Otherwise the grant
    /// and its ledger entry are made together, in this one mutation.
    static func deliver(_ receipt: StoreReceipt, player: inout Player, rng: inout SeededRandom,
                        now: Date = Date()) -> TreasuryDelivery {
        var ledger = player.treasury ?? TreasuryLedger()
        guard !ledger.knows(receipt.transactionID) else { return .alreadyGranted }
        guard let offer = StoreCatalog.offer(receipt.productID) else { return .unknownProduct }
        let quantity = max(1, receipt.quantity)
        var grants: [ShopService.Grant] = []
        var divinity = 0
        var days = 0
        switch offer.kind {
        case .divinity:
            let first = ledger.count(of: offer.productID) == 0
            let opening = first ? offer.firstPurchaseDivinity : offer.regularDivinity
            divinity = opening + (quantity - 1) * offer.regularDivinity
            grants = [.divinity(divinity)]
        case .starter:
            for _ in 0..<quantity {
                grants += StoreCatalog.starterGrants
            }
            divinity = offer.divinity * quantity
        case .blessing:
            days = StoreCatalog.blessingDays * quantity
            divinity = offer.divinity * quantity
            let waitingPay = extendBlessing(&ledger, by: days, now: now)
            grants = [.divinity(divinity + waitingPay)]
        }
        ledger.entries.append(TreasuryEntry(
            transactionID: receipt.transactionID,
            productID: offer.productID,
            purchasedAt: receipt.purchaseDate,
            divinity: divinity,
            days: days,
            restored: false
        ))
        player.treasury = ledger
        var paid: [ShopService.Grant] = []
        for grant in grants {
            paid += ShopService.grant(grant, to: &player, rng: &rng)
        }
        return .granted(paid)
    }

    // MARK: The Blessing

    /// Whole local days from the Blessing's first day to `now`'s; negative
    /// if the clock stands before it.
    static func dayIndex(of pass: TreasuryPass, on now: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: pass.firstDay)
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: today).day ?? 0
    }

    /// The Blessing on `now`'s day. Every day it has run is owed, the first
    /// on the day it was bought; a day not claimed WAITS — it is never
    /// forfeited (Docs/STORE.md §3.2) — so the total can never pass
    /// `days × blessingDaily`, whatever the clock says.
    static func standing(of pass: TreasuryPass, on now: Date) -> BlessingStatus {
        let index = max(0, dayIndex(of: pass, on: now))
        let owed = min(index + 1, pass.days)
        return BlessingStatus(
            day: min(index + 1, pass.days),
            days: pass.days,
            daysLeft: max(0, pass.days - index),
            waiting: max(0, owed - pass.daysPaid)
        )
    }

    /// The Blessing for the card: nil when there is none, or when it has
    /// ended with nothing waiting.
    static func blessingStatus(player: Player, now: Date = Date()) -> BlessingStatus? {
        guard let pass = player.treasury?.blessing else { return nil }
        let today = standing(of: pass, on: now)
        return today.isRunning || today.waiting > 0 ? today : nil
    }

    /// Adds `days` to the Blessing: onto its end while it runs, or as a new
    /// one from today once it has ended — returning, then, the divinity of
    /// the old one's days still waiting, which the caller pays at once.
    static func extendBlessing(_ ledger: inout TreasuryLedger, by days: Int, now: Date) -> Int {
        let today = Calendar.current.startOfDay(for: now)
        guard let pass = ledger.blessing else {
            ledger.blessing = TreasuryPass(firstDay: today, days: days, daysPaid: 0)
            return 0
        }
        let before = standing(of: pass, on: now)
        if before.isRunning {
            var longer = pass
            longer.days += days
            ledger.blessing = longer
            return 0
        }
        ledger.blessing = TreasuryPass(firstDay: today, days: days, daysPaid: 0)
        return before.divinityWaiting
    }

    /// Claims every Blessing day waiting, today's included.
    static func claimBlessing(player: inout Player, rng: inout SeededRandom,
                              now: Date = Date()) throws -> [ShopService.Grant] {
        guard let saved = player.treasury, let pass = saved.blessing else { throw TreasuryError.noBlessing }
        let today = standing(of: pass, on: now)
        guard today.waiting > 0 else { throw TreasuryError.nothingWaiting }
        var ledger = saved
        var paidUp = pass
        paidUp.daysPaid += today.waiting
        ledger.blessing = paidUp
        player.treasury = ledger
        return ShopService.grant(.divinity(today.divinityWaiting), to: &player, rng: &rng)
    }

    /// Whether the Treasury sells another thirty days now: while fewer than
    /// `blessingMostDaysAhead` would be waiting ahead after it.
    static func canExtendBlessing(player: Player, now: Date = Date()) -> Bool {
        guard let today = blessingStatus(player: player, now: now), today.isRunning else { return true }
        let ahead = today.daysLeft + StoreCatalog.blessingDays
        return ahead <= StoreCatalog.blessingMostDaysAhead
    }

    // MARK: What the Treasury shows

    /// True until the save has been paid a pack once: the tile's "×2".
    static func isFirstPurchase(_ offer: StoreOffer, player: Player) -> Bool {
        guard offer.kind == .divinity else { return false }
        let bought = player.treasury?.count(of: offer.productID) ?? 0
        return bought == 0
    }

    static func ownsStarter(player: Player) -> Bool {
        let bought = player.treasury?.count(of: StoreCatalog.starter.productID) ?? 0
        return bought > 0
    }

    // MARK: Refunds

    /// Takes back what a refunded transaction paid this save, once: its
    /// divinity, a starter's scrolls and drachma as far as the wallet still
    /// holds them, and a Blessing's days not yet paid — never below zero.
    /// A transaction this save was never paid changes nothing (a restore
    /// skips refunded transactions itself). True when something was taken.
    @discardableResult
    static func revoke(_ receipt: StoreReceipt, player: inout Player) -> Bool {
        guard var ledger = player.treasury,
              let index = ledger.entries.firstIndex(where: { $0.transactionID == receipt.transactionID }),
              ledger.entries[index].revoked != true else { return false }
        let entry = ledger.entries[index]
        ledger.entries[index].revoked = true
        if entry.days > 0, let pass = ledger.blessing {
            var shorter = pass
            let unpaid = max(0, shorter.days - shorter.daysPaid)
            shorter.days -= min(entry.days, unpaid)
            ledger.blessing = shorter
        }
        player.treasury = ledger
        player.wallet.divinity = max(0, player.wallet.divinity - entry.divinity)
        if entry.productID == StoreCatalog.starter.productID {
            for grant in StoreCatalog.starterGrants {
                takeBack(grant, from: &player)
            }
        }
        return true
    }

    /// A starter's non-divinity grant taken back as far as it is still held.
    /// Its divinity is the entry's, taken above.
    private static func takeBack(_ grant: ShopService.Grant, from player: inout Player) {
        switch grant {
        case .scrolls(let scroll, let count):
            let held = player.wallet.count(of: scroll)
            player.wallet.consume(scroll, min(count, held))
        case .drachma(let amount):
            player.wallet.drachma = max(0, player.wallet.drachma - amount)
        default:
            break
        }
    }

    // MARK: Restoring the Blessing

    /// The Blessing's days still AHEAD for transactions this save was never
    /// paid — a Blessing bought on another phone whose save did not come
    /// along, or kept through a reset — never the days behind and never the
    /// divinity paid at once (Docs/STORE.md §4.4). The windows stack in
    /// purchase order exactly as live purchases do. Refunded ones are
    /// skipped. Returns the days restored.
    @discardableResult
    static func restoreBlessing(_ receipts: [StoreReceipt], player: inout Player, now: Date = Date()) -> Int {
        let passes = receipts
            .filter { $0.productID == StoreCatalog.blessing.productID && !$0.isRevoked }
            .sorted { $0.purchaseDate < $1.purchaseDate }
        guard !passes.isEmpty else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var ledger = player.treasury ?? TreasuryLedger()
        var stackedEnd: Date? = nil
        var restoredDays = 0
        for receipt in passes {
            let bought = calendar.startOfDay(for: receipt.purchaseDate)
            let start = max(stackedEnd ?? bought, bought)
            let length = StoreCatalog.blessingDays * max(1, receipt.quantity)
            let stop = calendar.date(byAdding: .day, value: length, to: start) ?? start
            stackedEnd = stop
            guard !ledger.knows(receipt.transactionID) else { continue }
            let from = max(start, today)
            guard from < stop else { continue }
            let ahead = calendar.dateComponents([.day], from: from, to: stop).day ?? 0
            guard ahead > 0 else { continue }
            restoredDays += ahead
            ledger.entries.append(TreasuryEntry(
                transactionID: receipt.transactionID,
                productID: receipt.productID,
                purchasedAt: receipt.purchaseDate,
                divinity: 0,
                days: ahead,
                restored: true
            ))
        }
        guard restoredDays > 0 else { return 0 }
        let waitingPay = extendBlessing(&ledger, by: restoredDays, now: now)
        player.treasury = ledger
        player.wallet.divinity += waitingPay
        return restoredDays
    }
}
