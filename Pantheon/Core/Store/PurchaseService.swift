import Foundation
import StoreKit

// MARK: - StoreKit 2, for the Treasury (2026-09-23; Docs/STORE.md)
//
// The one file that imports StoreKit. It loads the products, runs the
// purchase sheet, listens to `Transaction.updates` from launch, sweeps the
// unfinished transactions into whichever store is open, and restores. What a
// transaction PAYS is `TreasuryService`'s (StoreCatalog.swift); making it
// durable before the App Store is told is `GameStore+Store.swift`'s. The
// order, every time: verify → grant and record in one mutation → write the
// save → `finish()` (Docs/STORE.md §3.3).

/// The store's side of a purchase. `GameStore` is the only one.
@MainActor
protocol PurchaseDelivering: AnyObject {
    /// The UUID the App Store keeps on each transaction for the account that
    /// bought it (`StoreCatalog.accountToken(for:)`).
    var purchaseAccountToken: UUID { get }
    /// False once the store is retired: nothing may be delivered into it.
    var acceptsPurchases: Bool { get }
    /// Grants a verified transaction once and writes the save.
    func deliverPurchase(_ receipt: StoreReceipt) -> TreasuryDelivery
    /// Takes back what a refunded transaction paid this save.
    func revokePurchase(_ receipt: StoreReceipt)
    /// Restores the Blessing days still ahead; returns how many.
    func restoreBlessing(_ receipts: [StoreReceipt]) -> Int
}

/// Where the Treasury's prices stand.
enum StoreShelfState: Equatable, Sendable {
    /// Not asked yet.
    case idle
    /// Asked; every tile shows "—" meanwhile, never a spinner.
    case loading
    /// The App Store answered: its `displayPrice` on every tile it knows.
    case ready
    /// No answer in twelve seconds, an error, or no products at all (none
    /// created in App Store Connect yet, or no StoreKit configuration).
    case unavailable
    /// The CI tour: StoreKit is never touched and every price is "—".
    case tour
}

/// A delivery, for the Treasury's receipt.
struct TreasuryNote: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let grants: [ShopService.Grant]
}

extension StoreReceipt {
    /// The game's reading of a VERIFIED transaction.
    init(_ transaction: Transaction) {
        self.init(
            transactionID: String(transaction.id),
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            revocationDate: transaction.revocationDate,
            appAccountToken: transaction.appAccountToken,
            quantity: transaction.purchasedQuantity
        )
    }
}

@MainActor
final class PurchaseService: ObservableObject {

    static let shared = PurchaseService()

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var shelf: StoreShelfState = .idle
    /// The product id whose sheet is up, or nil.
    @Published private(set) var purchasing: String?
    @Published private(set) var restoring = false
    /// The last delivery, for the receipt; a new value each time.
    @Published private(set) var lastDelivery: TreasuryNote?
    /// A sentence for the Treasury's foot — Ask to Buy, a failure, what a
    /// restore brought back. Clears itself after five seconds.
    @Published private(set) var notice: String?

    private weak var deliverer: PurchaseDelivering?
    private var listener: Task<Void, Never>?
    private var loadTimeout: Task<Void, Never>?
    private var noticeTimer: Task<Void, Never>?

    private init() {}

    /// True under the CI tour, which signs nothing and has no StoreKit
    /// configuration: StoreKit is never touched there.
    static var isTouring: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-tour")
        #else
        return false
        #endif
    }

    static let restrictedLine = "Purchases are turned off on this device (Screen Time)."

    // MARK: - Launch and sign-in

    /// Starts listening to `Transaction.updates`, once, at launch
    /// (`PantheonApp.init`). Apple's rule: unfinished transactions are handed
    /// to the listener once, right after launch, and a purchase a parent
    /// approves later or one made on another device arrives only here.
    func start() {
        guard listener == nil, !Self.isTouring else { return }
        listener = Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update, knownUnfinished: false)
            }
        }
        note("listening for transactions")
    }

    /// The store purchases go into, set each time one is installed
    /// (`AppSession.install`), and swept at once: a transaction left
    /// unfinished while no store was open is delivered now, a refund taken
    /// back, a Blessing bought on another phone restores its days ahead.
    func attach(_ newDeliverer: PurchaseDelivering) {
        deliverer = newDeliverer
        guard !Self.isTouring else { return }
        Task { [weak self] in
            await self?.settle()
        }
    }

    /// Delivers every unfinished transaction, takes back any refunded one
    /// this save was paid, and restores the Blessing days still ahead for
    /// this account (its `appAccountToken`, or none). Returns the Blessing
    /// days restored.
    @discardableResult
    func settle() async -> Int {
        guard !Self.isTouring, deliverer?.acceptsPurchases == true else { return 0 }
        var pending: [VerificationResult<Transaction>] = []
        for await result in Transaction.unfinished {
            pending.append(result)
        }
        for result in pending {
            await handle(result, knownUnfinished: true)
        }
        // What is STILL unfinished was not delivered (the save could not be
        // written, or no store was open): it must be delivered whole later,
        // never restored as days alone now.
        var stillWaiting: Set<UInt64> = []
        for await result in Transaction.unfinished {
            stillWaiting.insert(result.unsafePayloadValue.id)
        }
        var history: [UInt64: StoreReceipt] = [:]
        for await result in Transaction.all {
            if case .verified(let transaction) = result {
                history[transaction.id] = StoreReceipt(transaction)
            }
        }
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                history[transaction.id] = StoreReceipt(transaction)
            }
        }
        guard let target = deliverer, target.acceptsPurchases else { return 0 }
        for receipt in history.values where receipt.isRevoked {
            target.revokePurchase(receipt)
        }
        let token = target.purchaseAccountToken
        let blessings: [StoreReceipt] = history
            .filter { !stillWaiting.contains($0.key) }
            .map { $0.value }
            .filter { $0.productID == StoreCatalog.blessing.productID && !$0.isRevoked }
            .filter { $0.appAccountToken == nil || $0.appAccountToken == token }
        guard !blessings.isEmpty else { return 0 }
        let days = target.restoreBlessing(blessings)
        if days > 0 {
            note("restored \(days) Blessing day(s)")
        }
        return days
    }

    // MARK: - Prices

    /// Asks the App Store for the products, once, and again after a failure.
    /// The tiles never wait on it: they show "—" until it answers, and after
    /// twelve seconds without an answer the shelf says so.
    func prepare() async {
        if Self.isTouring {
            shelf = .tour
            return
        }
        guard shelf == .idle || shelf == .unavailable else { return }
        shelf = .loading
        startLoadTimeout()
        do {
            let loaded = try await Product.products(for: StoreCatalog.productIDs)
            var byID: [String: Product] = [:]
            for product in loaded {
                byID[product.id] = product
            }
            products = byID
            shelf = byID.isEmpty ? .unavailable : .ready
            if byID.isEmpty {
                note("the App Store knows none of the \(StoreCatalog.productIDs.count) products")
            } else if byID.count < StoreCatalog.productIDs.count {
                note("the App Store sent \(byID.count) of \(StoreCatalog.productIDs.count) products")
            }
        } catch {
            shelf = .unavailable
            note("the products could not be loaded: \(error.localizedDescription)")
        }
        loadTimeout?.cancel()
    }

    /// The header's Retry.
    func retry() {
        guard shelf == .unavailable else { return }
        Task { [weak self] in
            await self?.prepare()
        }
    }

    private func startLoadTimeout() {
        loadTimeout?.cancel()
        loadTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, let self, self.shelf == .loading else { return }
            self.shelf = .unavailable
            self.note("the App Store did not answer in twelve seconds")
        }
    }

    /// The App Store's price for a product, in the storefront's currency, or
    /// nil before it has answered.
    func price(for offer: StoreOffer) -> String? {
        products[offer.productID]?.displayPrice
    }

    /// Whether this device allows purchases at all (Screen Time, MDM).
    var paymentsAllowed: Bool {
        !Self.isTouring && AppStore.canMakePayments
    }

    // MARK: - Buying

    /// Apple's purchase sheet, then the delivery. The purchase carries this
    /// demigod's `appAccountToken`, so the App Store's record of it names
    /// the account that bought it.
    func purchase(_ offer: StoreOffer) async {
        guard purchasing == nil, !restoring else { return }
        guard let product = products[offer.productID] else {
            say("The App Store has not sent this price yet.")
            return
        }
        guard let target = deliverer, target.acceptsPurchases else { return }
        guard AppStore.canMakePayments else {
            say(Self.restrictedLine)
            return
        }
        purchasing = offer.productID
        defer { purchasing = nil }
        do {
            let result = try await product.purchase(options: [.appAccountToken(target.purchaseAccountToken)])
            switch result {
            case .success(let verification):
                await handle(verification, knownUnfinished: true)
            case .pending:
                say("Waiting for approval. It arrives the moment it is approved.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            say("The purchase did not go through.")
            note("the purchase of \(offer.productID) failed: \(error.localizedDescription)")
        }
    }

    /// Restore: Apple's sign-in sheet (`AppStore.sync()`, only ever behind
    /// this button), then the sweep a sign-in runs, then what came back.
    func restore() async {
        guard !restoring, purchasing == nil, !Self.isTouring else { return }
        restoring = true
        defer { restoring = false }
        do {
            try await AppStore.sync()
        } catch {
            if let storeError = error as? StoreKitError, case .userCancelled = storeError {
                return
            }
            say("The App Store could not be reached. Try again in a moment.")
            note("restore failed: \(error.localizedDescription)")
            return
        }
        let days = await settle()
        if days > 0 {
            say("Restored \(days) days of the Blessing.")
        } else {
            say("Everything bought with this Apple Account is already here.")
        }
    }

    // MARK: - One transaction

    /// One transaction from any source. `knownUnfinished` is true for a
    /// purchase's own result and for the unfinished sweep; for `updates` it
    /// is asked, because a transaction another phone has already finished
    /// was paid there and is never paid again — only a Blessing's days ahead
    /// follow it (Docs/STORE.md §3.3).
    private func handle(_ result: VerificationResult<Transaction>, knownUnfinished: Bool) async {
        let transaction: Transaction
        switch result {
        case .verified(let checked):
            transaction = checked
        case .unverified(let unchecked, let failure):
            let reason: String = failure.localizedDescription
            note("unverified transaction \(unchecked.id) for \(unchecked.productID) (\(reason)): not granted, not finished")
            return
        }
        let receipt = StoreReceipt(transaction)
        guard let target = deliverer, target.acceptsPurchases else {
            note("transaction \(transaction.id) waits: no demigod is signed in")
            return
        }
        if receipt.isRevoked {
            target.revokePurchase(receipt)
            await transaction.finish()
            note("the refund of \(receipt.productID) (\(receipt.transactionID)) was taken back")
            return
        }
        var unfinished = knownUnfinished
        if !unfinished {
            unfinished = await Self.isUnfinished(transaction.id)
        }
        guard unfinished else {
            let mine = receipt.appAccountToken == nil || receipt.appAccountToken == target.purchaseAccountToken
            if receipt.productID == StoreCatalog.blessing.productID, mine {
                let days = target.restoreBlessing([receipt])
                if days > 0 {
                    note("restored \(days) Blessing day(s) bought on another device")
                }
            }
            return
        }
        let delivery = target.deliverPurchase(receipt)
        if delivery.mayFinish {
            await transaction.finish()
        }
        switch delivery {
        case .granted(let grants):
            announce(grants, for: receipt)
        case .alreadyGranted:
            note("\(receipt.productID) (\(receipt.transactionID)) was already paid; finished")
        case .unknownProduct:
            note("\(receipt.productID) is not sold by this build; left unfinished")
        case .closed:
            note("\(receipt.transactionID) waits for the next demigod to sign in")
        case .notSaved:
            note("\(receipt.transactionID) could not be saved; it is delivered again at the next launch")
        }
    }

    private static func isUnfinished(_ id: UInt64) async -> Bool {
        for await result in Transaction.unfinished where result.unsafePayloadValue.id == id {
            return true
        }
        return false
    }

    // MARK: - Words

    private func announce(_ grants: [ShopService.Grant], for receipt: StoreReceipt) {
        let title = StoreCatalog.offer(receipt.productID)?.name ?? "Purchase"
        lastDelivery = TreasuryNote(id: UUID(), title: title, grants: grants)
        note("delivered \(receipt.productID) (\(receipt.transactionID))")
    }

    private func say(_ line: String) {
        notice = line
        noticeTimer?.cancel()
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    /// One line to the console and to More → Diagnostics.
    private func note(_ line: String) {
        let stamped = "[Treasury] \(line)"
        print(stamped)
        DiagnosticsLog.shared.record(stamped)
    }
}
