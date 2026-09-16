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
struct NightMarketBoard: View {
    @EnvironmentObject private var store: GameStore
    var onReceipt: (String) -> Void

    /// Six across a landscape phone, because six is the shelf a new player
    /// gets: at a 132-point minimum the grid fitted five and drew the sixth
    /// alone on a second row beside a hole (run 151's frames). At 116 the
    /// starting shelf is one clean row, and the ten a level-40 summoner has
    /// are two.
    ///
    /// STATIC on purpose: a private STORED property drags the memberwise
    /// initialiser down to private with it, and `ShopView` builds this from
    /// another file. `ShopView`'s own `columns` gets away with being stored
    /// because nothing ever passes it an argument.
    private static let columns = [GridItem(.adaptive(minimum: 116, maximum: 170), spacing: 8)]

    var body: some View {
        VStack(spacing: 6) {
            clockRow
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(store.nightMarketStalls) { stall in
                        tile(stall)
                    }
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.bottom, 8)
            }
        }
        .onAppear { store.refreshNightMarket() }
    }

    // MARK: - The clock and the re-roll

    /// The countdown, ticking, and the price of not waiting for it. A market
    /// whose timer is hidden is a market a player has no reason to come back
    /// to at any particular time.
    private var clockRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.gold)
            if let refresh = store.nightMarketRefreshesAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("New stock in \(countdown(to: refresh, now: context.date))")
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Button { reroll() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .black))
                    Text("Re-roll")
                        .font(Theme.body(10).weight(.black))
                        .tracking(0.6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .black))
                    Text("\(store.nightMarketRerollPrice)")
                        .font(Theme.numeric(11))
                }
                .foregroundStyle(canReroll ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    // A ternary cannot pick between `Theme.goldPlate`, which
                    // is a LinearGradient, and `Theme.surface`, which is a
                    // Color. ShopView's price plate uses a Group for the same
                    // reason; copying its shape without this cost a CI run.
                    Group {
                        if canReroll {
                            Capsule().fill(Theme.goldPlate)
                        } else {
                            Capsule().fill(Theme.surface)
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(canReroll ? Color.clear : Theme.stroke, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canReroll)
        }
        .padding(.horizontal, ScreenChrome.contentPadding)
        .padding(.top, 6)
    }

    private var canReroll: Bool {
        store.player.wallet.divinity >= store.nightMarketRerollPrice
    }

    private func countdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - One ware

    private func tile(_ stall: NightMarketService.Stall) -> some View {
        let affordable = ShopService.canAfford(stall.price, wallet: store.player.wallet)
        let available = !stall.isSoldOut && affordable
        return VStack(spacing: 5) {
            ZStack {
                ware(stall.grant)
                    .frame(height: 62)
                if stall.isSoldOut {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.plate.opacity(0.75))
                        .overlay(
                            Text("TAKEN")
                                .font(Theme.title(12))
                                .tracking(1.2)
                                .foregroundStyle(Theme.goldDeep)
                        )
                }
            }
            .frame(maxWidth: .infinity)

            Text(stall.title)
                .font(Theme.body(11).weight(.bold))
                .foregroundStyle(stall.isSoldOut ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
            Text(stall.subtitle)
                .font(Theme.body(9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button { buy(stall) } label: {
                HStack(spacing: 5) {
                    Image(systemName: stall.price.currency.icon)
                        .font(.system(size: 10, weight: .black))
                    Text(grouped(stall.price.amount))
                        .font(Theme.numeric(11))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(stall.isSoldOut ? "GONE" : (affordable ? "BUY" : "NEED MORE"))
                        .font(Theme.body(9).weight(.black))
                        .tracking(0.7)
                        .lineLimit(1)
                }
                .foregroundStyle(available ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(
                    Group {
                        if available {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.goldPlate)
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surface)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(available ? Color.clear : Theme.stroke, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(!available)
        }
        .padding(8)
        .frame(height: 158)
        .panelBackground(radius: Theme.tightCorner)
        .opacity(stall.isSoldOut ? 0.72 : 1)
    }

    /// A unit shows its PORTRAIT — the row is only worth having because the
    /// player can see whose face is on the shelf. Everything else is the
    /// game's one reward tile.
    @ViewBuilder
    private func ware(_ grant: ShopService.Grant) -> some View {
        if case .unit(let id) = grant, let blueprint = UnitDatabase.blueprint(id) {
            VStack(spacing: 2) {
                BundleImage(name: blueprint.model.portraitName(awakened: false), renderedAt: 52)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                Rarity(stars: blueprint.naturalStars).frame,
                                lineWidth: Rarity(stars: blueprint.naturalStars).frameWidth
                            )
                    )
                StarRow(stars: blueprint.naturalStars, size: 7)
            }
        } else {
            RewardTile(grant: grant, size: 52, showsTitle: false)
        }
    }

    // MARK: - Doing things

    private func buy(_ stall: NightMarketService.Stall) {
        guard let grants = store.buyFromNightMarket(slot: stall.slot) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.light)
        onReceipt("Received " + grants.map(ShopService.describe).joined(separator: ", ") + ".")
    }

    private func reroll() {
        store.rerollNightMarket()
        AudioLibrary.shared.play(.uiTap)
        Juice.haptic(.light)
    }

    /// 45000 → "45,000". A price is read, not estimated.
    private func grouped(_ amount: Int) -> String {
        let digits = Array(String(amount))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }
}
