import SwiftUI

/// The bazaar: scrolls, energy, relic packs, essences and the laurel
/// exchange, paid for in the game's own currencies, and a free offering once
/// a day. Opens from the wallet on the island and from More.
///
/// The six categories used to be six capsule pills under a navigation bar,
/// above a single stretched column of rows — the worst offender in the game
/// for the owner's "big top bar and pills as options" complaint. They are now
/// one dropdown in the 34-point strip, and the offers are a grid of tiles that
/// fills the frame: four across a landscape phone instead of one.
struct ShopView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var section: ShopService.Section = .daily
    @State private var receipt: String?

    /// As many 208-point tiles as the width holds: four across a landscape
    /// phone, three on a short one, rather than one column down the middle.
    private let columns = [GridItem(.adaptive(minimum: 208, maximum: 320), spacing: 8)]

    private var offers: [ShopService.Item] { ShopService.items(in: section) }

    /// The two sentences the old layout spent a content row on each fit the
    /// strip's subtitle instead.
    private var subtitle: String {
        switch section {
        case .daily: return "Free, once a day"
        case .laurels: return "Won in the arena"
        default: return "\(offers.count) offers"
        }
    }

    var body: some View {
        NavigationStack {
            GameScreen("Bazaar", subtitle: subtitle, dismiss: { dismiss() }) {
                BarMenu(label: "Stall", value: section.rawValue) {
                    ForEach(ShopService.Section.allCases) { candidate in
                        Button {
                            section = candidate
                            receipt = nil
                        } label: {
                            Label(candidate.rawValue, systemImage: glyph(for: candidate))
                        }
                    }
                }
                BarWallet(
                    wallet: store.player.wallet,
                    shows: [.energy, .divinity, .drachma, .laurels]
                )
            } content: {
                ZStack(alignment: .bottom) {
                    if section == .daily, let offering = offers.first {
                        hero(offering)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(offers) { item in
                                    tile(item)
                                }
                            }
                            .padding(.horizontal, ScreenChrome.contentPadding)
                            .padding(.vertical, 8)
                        }
                    }

                    if let receipt {
                        receiptToast(receipt)
                    }
                }
            }
        }
    }

    // MARK: - The grid

    /// One offer, as a shop tile: what it is, what it costs, and whether the
    /// wallet covers it, all readable without a tap.
    private func tile(_ item: ShopService.Item) -> some View {
        let available = isAvailable(item)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.goldDim.opacity(0.45), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            Button {
                buy(item)
            } label: {
                priceLabel(item, available: available)
            }
            .buttonStyle(.plain)
            .disabled(!available)
        }
        .padding(9)
        .frame(height: 104)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// The daily offering is one item, and a lone tile in the corner of an
    /// empty frame is the blank space the owner objects to. It gets the middle
    /// of the screen and its contents spelled out instead.
    private func hero(_ item: ShopService.Item) -> some View {
        let available = isAvailable(item)
        return VStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: 82, height: 82)
                .background(Circle().fill(Theme.surfaceRaised))
                .overlay(Circle().strokeBorder(Theme.goldDim.opacity(0.6), lineWidth: 1))
                .shadow(color: Theme.gold.opacity(available ? 0.35 : 0), radius: 12)

            VStack(spacing: 4) {
                Text(item.title.uppercased())
                    .font(Theme.title(17))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textPrimary)
                Text(item.subtitle)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                // Offsets, not the strings themselves: two identical grants in
                // one bundle would collide on `id: \.self`.
                ForEach(Array(grantParts(item.grant).enumerated()), id: \.offset) { _, part in
                    Text(part)
                        .font(Theme.body(10).weight(.bold))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Theme.surfaceRaised))
                        .overlay(Capsule().strokeBorder(Theme.goldDim.opacity(0.4), lineWidth: 0.5))
                }
            }

            Button {
                buy(item)
            } label: {
                priceLabel(item, available: available)
            }
            .buttonStyle(.plain)
            .disabled(!available)
            .frame(width: 190)
        }
        .padding(18)
        .frame(width: 360)
        .panelBackground(radius: Theme.cornerRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The price plate: currency, amount, and the verb that says whether the
    /// wallet covers it. Gold when it does, dark when it does not.
    private func priceLabel(_ item: ShopService.Item, available: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: leadingGlyph(item, available: available))
                .font(.system(size: 10, weight: .black))
            Text(leadingText(item, available: available))
                .font(Theme.numeric(11))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verb(item, available: available))
                .font(Theme.body(9).weight(.black))
                .tracking(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(available ? Theme.ink : Theme.textSecondary)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 26)
        .background(
            Group {
                if available {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.goldPlate)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.surface)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(available ? Color.clear : Theme.stroke, lineWidth: 0.5)
        )
    }

    private func receiptToast(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.success)
            Text(text)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(Theme.surface.opacity(0.95)))
        .overlay(Capsule().strokeBorder(Theme.success.opacity(0.5), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 3)
        .padding(.bottom, 10)
        // A toast that swallowed taps would make the bottom row of tiles dead.
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Reading an offer

    private func isAvailable(_ item: ShopService.Item) -> Bool {
        item.isDaily
            ? ShopService.isDailyAvailable(player: store.player)
            : ShopService.canAfford(item.price, wallet: store.player.wallet)
    }

    private func leadingGlyph(_ item: ShopService.Item, available: Bool) -> String {
        if item.isDaily { return available ? "gift.fill" : "checkmark" }
        return item.price.currency.icon
    }

    private func leadingText(_ item: ShopService.Item, available: Bool) -> String {
        if item.isDaily { return available ? "Free" : "Claimed" }
        return grouped(item.price.amount)
    }

    private func verb(_ item: ShopService.Item, available: Bool) -> String {
        if item.isDaily { return available ? "CLAIM" : "TOMORROW" }
        return available ? "BUY" : "NEED MORE"
    }

    /// A bundle spelled out one grant to a chip; anything else is one chip.
    private func grantParts(_ grant: ShopService.Grant) -> [String] {
        if case .bundle(let parts) = grant {
            return parts.map(ShopService.describe)
        }
        return [ShopService.describe(grant)]
    }

    /// 45000 → "45,000". A price is read, not estimated, so the wallet's
    /// compact "45K" is wrong here.
    private func grouped(_ amount: Int) -> String {
        let digits = Array(String(amount))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }

    private func glyph(for candidate: ShopService.Section) -> String {
        switch candidate {
        case .daily: return "gift.fill"
        case .scrolls: return "scroll.fill"
        case .energy: return "bolt.fill"
        case .relics: return "shield.lefthalf.filled"
        case .essences: return "drop.triangle.fill"
        case .laurels: return "laurel.leading"
        }
    }

    private func buy(_ item: ShopService.Item) {
        guard let grants = store.buy(item) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.light)
        withAnimation(.easeOut(duration: 0.2)) {
            receipt = "Received " + grants.map(ShopService.describe).joined(separator: ", ") + "."
        }
    }
}
