import SwiftUI

/// The bazaar: scrolls, energy, relic packs, essences and the laurel
/// exchange, paid for in the game's own currencies, and a free offering once
/// a day. Opens from the wallet on the island and from More.
struct ShopView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var section: ShopService.Section = .daily
    @State private var receipt: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ShopService.Section.allCases) { candidate in
                                chip(candidate.rawValue, on: section == candidate) {
                                    section = candidate
                                }
                            }
                        }
                    }

                    if let receipt {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Theme.success)
                            Text(receipt)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                .fill(Theme.success.opacity(0.12))
                        )
                    }

                    if section == .daily {
                        Text("One free offering every day, whatever else you buy.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if section == .laurels {
                        Text("Laurels come from the arena. \(store.player.wallet.laurels) to spend.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(ShopService.items(in: section)) { item in
                        itemRow(item)
                    }
                }
                .padding(16)
            }
            .screen("Bazaar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    WalletBar(wallet: store.player.wallet)
                }
            }
        }
    }

    private func itemRow(_ item: ShopService.Item) -> some View {
        let available = item.isDaily
            ? ShopService.isDailyAvailable(player: store.player)
            : ShopService.canAfford(item.price, wallet: store.player.wallet)
        return HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surfaceRaised))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(Theme.body(14).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(item.subtitle)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                buy(item)
            } label: {
                priceLabel(item, available: available)
            }
            .disabled(!available)
        }
        .padding(12)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func priceLabel(_ item: ShopService.Item, available: Bool) -> some View {
        HStack(spacing: 5) {
            if item.isDaily {
                Image(systemName: available ? "gift.fill" : "checkmark")
                Text(available ? "Claim" : "Claimed")
            } else {
                Image(systemName: item.price.currency.icon)
                Text("\(item.price.amount)")
            }
        }
        .font(Theme.numeric(12).weight(.bold))
        .foregroundStyle(available ? Theme.ink : Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(available ? Theme.gold : Theme.surface))
    }

    private func buy(_ item: ShopService.Item) {
        guard let grants = store.buy(item) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.light)
        receipt = "Received " + grants.map(ShopService.describe).joined(separator: ", ") + "."
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(12).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? Theme.gold : Theme.surfaceRaised))
                .foregroundStyle(on ? Theme.ink : Theme.textSecondary)
        }
    }
}
