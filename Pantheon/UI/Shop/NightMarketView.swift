import SwiftUI

/// The Night Market's shelf, inside the bazaar.
///
/// It is a stall of the bazaar rather than a building of its own, because the
/// owner already reaches the bazaar from the wallet on the island and from
/// More, and a sixth landmark for a shop that changes every hour would be a
/// walk for nothing.
///
/// What the genre's Magic Shop gets right and this copies: the stock is
/// ROLLED, so a player looks; the timer is visible, so waiting has a shape;
/// and a paid re-roll is there for the player who cannot wait. What it does
/// differently is on `NightMarketService` — slots are levels and never
/// purchases, no 5★ is ever on the shelf, and a sold slot stays where it was,
/// crossed out, so a player can see what tonight gave them.
///
/// Since phase B (2026-09-22) the shelf is the bazaar's own glass shelf over
/// the Forum at a deeper hour: six wares a clean 3 × 2 in fixed columns (run
/// 211 drew five cream `ui_panel` frames and a sixth alone under them, cut by
/// the foot), each ware a `BazaarWareTile` with its words behind a ?, and the
/// clock and the re-roll in the room's header — `NightMarketTitle` and
/// `NightMarketReroll` below — where Epic Seven puts its "59m left until
/// refresh" and its Refresh with the price on it.
struct NightMarketBoard: View {
    @EnvironmentObject private var store: GameStore
    /// What a purchase paid, handed to the bazaar's receipt. Only `ShopView`
    /// builds this board.
    var onReceipt: ([ShopService.Grant]) -> Void

    var body: some View {
        BazaarShelf(wares: store.nightMarketStalls) { stall in
            tile(stall)
        }
        .onAppear { store.refreshNightMarket() }
    }

    // MARK: - One ware

    private func tile(_ stall: NightMarketService.Stall) -> some View {
        BazaarWareTile(
            artKey: ItemArt.key(for: stall.grant),
            amount: BazaarWareTile.cornerAmount(for: stall.grant),
            stars: ItemArt.stars(for: stall.grant),
            portraitName: Self.portraitName(for: stall.grant),
            kind: BazaarWareTile.kind(for: stall.grant),
            name: stall.title,
            shelfName: BazaarWareTile.shelfName(stall.title, grant: stall.grant),
            detail: stall.subtitle,
            price: stall.price,
            status: status(for: stall)
        ) {
            buy(stall)
        }
    }

    /// A unit on the shelf shows its card's face: the row is only worth
    /// having because the player can see whose face is on it.
    private static func portraitName(for grant: ShopService.Grant) -> String? {
        guard case .unit(let id) = grant, let blueprint = UnitDatabase.blueprint(id) else { return nil }
        return blueprint.model.portraitName(awakened: false)
    }

    private func status(for stall: NightMarketService.Stall) -> BazaarWareStatus {
        if stall.isSoldOut { return .taken }
        return ShopService.canAfford(stall.price, wallet: store.player.wallet) ? .buy : .short
    }

    // MARK: - Doing things

    private func buy(_ stall: NightMarketService.Stall) {
        guard let grants = store.buyFromNightMarket(slot: stall.slot) else { return }
        // The price button's press ticked on touch-down; the confirm is the
        // "done".
        AudioLibrary.shared.play(.uiConfirm)
        onReceipt(grants)
    }

    /// "42:18" to the next free turn-over. The title's eyebrow and the
    /// bazaar rail's Night Market row both print it.
    static func countdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// The Night Market's carved name with its clock as the eyebrow — "NEW STOCK
/// IN 42:18" over "NIGHT MARKET" — ticking once a second. The clock was an
/// 11-point grey line above the shelf, and beside a carved title, a clock
/// bead and a 200-point re-roll would not fit one header on a 16 Pro, so the
/// clock went where the stall's description goes on every other stall.
struct NightMarketTitle: View {
    @EnvironmentObject private var store: GameStore
    let size: CGFloat

    var body: some View {
        if let refresh = store.nightMarketRefreshesAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                PlaceTitle(
                    eyebrow: "New stock in " + NightMarketBoard.countdown(to: refresh, now: context.date),
                    title: "Night Market",
                    size: size
                )
            }
        } else {
            PlaceTitle(eyebrow: "New stock on the hour", title: "Night Market", size: size)
        }
    }
}

/// The paid re-roll as a glass button with its price on it, the summon
/// screen's "Buy · 100" in the same material: the painted divinity, "RE-ROLL
/// · 30", dimmed glass when the purse is short. It was a 24-point cream
/// capsule with 10-point words, outside the chrome's one control language.
/// 204 wide: the label at "RE-ROLL · 500" (the dearest re-roll) measures 192
/// with its icon, and a narrower frame would shrink the title under the
/// floor.
struct NightMarketReroll: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let price = store.nightMarketRerollPrice
        return PrimaryButton(
            title: "Re-roll · \(price)",
            isEnabled: store.player.wallet.divinity >= price,
            itemKey: "divinity",
            style: .glass
        ) {
            store.rerollNightMarket()
        }
        .frame(width: 204)
    }
}
