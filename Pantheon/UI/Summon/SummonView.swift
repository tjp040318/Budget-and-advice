import SwiftUI
import UIKit

/// The gacha screen.
struct SummonView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedBanner: Banner = Banner.all[0]
    @State private var revealResults: [SummonResult] = []
    @State private var showRates = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    bannerPicker
                    bannerArt
                    pityPanel
                    summonButtons
                    ratesLink
                }
                .padding(16)
            }
            .screen("Summon")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WalletBar(wallet: store.player.wallet)
                }
            }
            .fullScreenCover(isPresented: .constant(!revealResults.isEmpty)) {
                SummonRevealView(results: revealResults) {
                    revealResults = []
                }
            }
            .sheet(isPresented: $showRates) {
                RateTableView(banner: selectedBanner)
            }
        }
    }

    // MARK: - Banner

    private var bannerPicker: some View {
        HStack(spacing: 8) {
            ForEach(Banner.all) { banner in
                Button {
                    selectedBanner = banner
                } label: {
                    Text(banner.title)
                        .font(Theme.body(12).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                selectedBanner.id == banner.id ? Theme.gold : Theme.surfaceRaised
                            )
                        )
                        .foregroundStyle(
                            selectedBanner.id == banner.id ? Theme.ink : Theme.textSecondary
                        )
                }
            }
            Spacer()
        }
    }

    private var bannerArt: some View {
        ZStack(alignment: .bottomLeading) {
            if UIImage(named: selectedBanner.artName) != nil {
                Image(selectedBanner.artName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [
                        (selectedBanner.pantheon?.color ?? Theme.gold).opacity(0.55),
                        Theme.ink
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 90, weight: .black))
                        .foregroundStyle(.white.opacity(0.08))
                        .offset(x: 70, y: -10)
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(selectedBanner.title)
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.textPrimary)
                Text(selectedBanner.subtitle)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    // MARK: - Pity

    private var pityPanel: some View {
        let pity = store.player.summonPity[selectedBanner.id] ?? PityState()

        return VStack(alignment: .leading, spacing: 9) {
            if let cap = selectedBanner.legendaryPity {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Guaranteed 5★")
                            .font(Theme.body(12).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(pity.sinceLegendary) / \(cap)")
                            .font(Theme.numeric(12))
                            .foregroundStyle(Theme.gold)
                    }
                    StatBar(
                        value: Double(pity.sinceLegendary),
                        maximum: Double(cap),
                        tint: Theme.gold,
                        height: 5
                    )
                    Text("The 5★ rate climbs sharply after \(Int(Double(cap) * 0.75)) summons.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if pity.featuredGuaranteed {
                Label("Your next 5★ is guaranteed to be the featured unit.",
                      systemImage: "checkmark.seal.fill")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.success)
            }

            if let cap = selectedBanner.rarePity {
                HStack {
                    Text("Guaranteed 4★+")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(pity.sinceRare) / \(cap)")
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(14)
        .panelBackground()
    }

    // MARK: - Buttons

    private var summonButtons: some View {
        let scroll = selectedBanner.scroll
        let owned = store.player.wallet.count(of: scroll)

        return VStack(spacing: 10) {
            HStack {
                Label("\(owned) \(scroll.displayName)\(owned == 1 ? "" : "s")", systemImage: scroll.glyph)
                    .font(Theme.body(13).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let price = scroll.divinityPrice {
                    Button {
                        store.buyScroll(scroll)
                    } label: {
                        Label("Buy — \(price)", systemImage: "sparkles")
                            .font(Theme.body(12).weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }

            HStack(spacing: 10) {
                PrimaryButton(
                    title: "Summon ×1",
                    systemImage: "sparkle",
                    tint: Theme.surfaceRaised,
                    isEnabled: owned >= 1
                ) {
                    perform(count: 1)
                }
                .foregroundStyle(Theme.textPrimary)

                PrimaryButton(
                    title: "Summon ×10",
                    systemImage: "sparkles",
                    isEnabled: owned >= 10
                ) {
                    perform(count: 10)
                }
            }
        }
        .padding(14)
        .panelBackground()
    }

    private func perform(count: Int) {
        let results = store.summon(banner: selectedBanner, count: count)
        guard !results.isEmpty else { return }
        revealResults = results
    }

    private var ratesLink: some View {
        Button {
            showRates = true
        } label: {
            Label("Full rates and pool", systemImage: "info.circle")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// The published odds. Shown in full, because a rate table that hides the pool
/// is not a rate table.
struct RateTableView: View {
    let banner: Banner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(banner.scroll.description)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(SummonService.oddsTable(for: banner)) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                StarRow(stars: entry.stars, size: 13)
                                Spacer()
                                Text("\(String(format: "%.2f", entry.chance * 100))%")
                                    .font(Theme.numeric(14))
                                    .foregroundStyle(Theme.gold)
                            }
                            if entry.units.isEmpty {
                                Text("Nothing at this grade yet.")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                ForEach(entry.units) { unit in
                                    HStack(spacing: 8) {
                                        ElementBadge(element: unit.element, compact: true)
                                        Text(unit.name)
                                            .font(Theme.body(13))
                                            .foregroundStyle(Theme.textPrimary)
                                        if banner.featured.contains(unit.id) {
                                            Text("FEATURED")
                                                .font(Theme.body(8).weight(.black))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Theme.gold.opacity(0.25)))
                                                .foregroundStyle(Theme.gold)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .panelBackground()
                    }
                }
                .padding(16)
            }
            .screen("Rates")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
