import SwiftUI
import UIKit

/// The gacha screen.
///
/// The two chip rows this screen used to stack under the navigation bar — the
/// pantheons, then the scrolls, every chip a capsule with its count — were the
/// exact thing the owner called ugly, and they cost about 110 points of a
/// 430-point landscape frame before the banner was drawn. They are two
/// dropdowns in the strip now, each listing its banners with how many of that
/// scroll the player holds, and the frame belongs to the painting and the two
/// summon plates: the art fills the left, the pity counters and the buttons
/// run down a column on the right.
struct SummonView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedBanner: Banner = Banner.all[0]
    @State private var revealResults: [SummonResult] = []
    @State private var showRates = false

    var body: some View {
        NavigationStack {
            GameScreen("Summon") {
                BarMenu(label: "Pantheon", value: pantheonValue) {
                    ForEach(Banner.pantheonBanners) { banner in
                        bannerMenuItem(banner)
                    }
                }
                BarMenu(label: "Scroll", value: scrollValue) {
                    ForEach(Banner.scrollBanners) { banner in
                        bannerMenuItem(banner)
                    }
                }
                BarCount(
                    value: "\(store.player.wallet.count(of: selectedBanner.scroll))",
                    systemImage: selectedBanner.scroll.glyph,
                    tint: Theme.gold
                )
                BarButton(title: "Rates", systemImage: "info.circle") {
                    showRates = true
                }
                BarWallet(wallet: store.player.wallet)
            } content: {
                HStack(alignment: .top, spacing: 10) {
                    bannerArt
                    VStack(spacing: 8) {
                        if showsPity {
                            pityPanel
                        }
                        Spacer(minLength: 0)
                        summonButtons
                    }
                    .frame(width: 320)
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
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

    /// A banner in one of the strip's dropdowns, carrying the count its chip
    /// used to carry. The chosen one wears a tick instead of its scroll glyph.
    private func bannerMenuItem(_ banner: Banner) -> some View {
        let owned = store.player.wallet.count(of: banner.scroll)
        return Button {
            selectedBanner = banner
        } label: {
            Label(
                "\(banner.title)  ×\(owned)",
                systemImage: banner.id == selectedBanner.id ? "checkmark" : banner.scroll.glyph
            )
        }
    }

    private var pantheonValue: String {
        guard Banner.pantheonBanners.contains(where: { $0.id == selectedBanner.id }) else { return "—" }
        return selectedBanner.pantheon?.displayName ?? shortName(selectedBanner)
    }

    private var scrollValue: String {
        guard Banner.scrollBanners.contains(where: { $0.id == selectedBanner.id }) else { return "—" }
        return shortName(selectedBanner)
    }

    /// "The Endless Scroll" is a title for the painting, not for a 26-point
    /// control: the strip shows "Endless".
    private func shortName(_ banner: Banner) -> String {
        banner.title
            .replacingOccurrences(of: "The ", with: "")
            .replacingOccurrences(of: " Scroll", with: "")
    }

    private var bannerArt: some View {
        ZStack(alignment: .bottomLeading) {
            if BundleImage.exists(selectedBanner.artName) {
                BundleImage(name: selectedBanner.artName)
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

            // The painting is full height now, so the name needs something to
            // sit on wherever the art happens to be bright.
            LinearGradient(
                colors: [Color.clear, Theme.ink.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(selectedBanner.title)
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.textPrimary)
                Text(selectedBanner.subtitle)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        // A painting scaled to fill is clipped on screen but not for touch:
        // the art's unclipped extent covered the banner chips above it.
        .allowsHitTesting(false)
    }

    // MARK: - Pity

    private var pity: PityState {
        store.player.summonPity[selectedBanner.id] ?? PityState()
    }

    /// A banner without counters (the Unknown Scroll has none) would otherwise
    /// draw an empty panel down the side of the frame.
    private var showsPity: Bool {
        selectedBanner.legendaryPity != nil
            || selectedBanner.rarePity != nil
            || pity.featuredGuaranteed
    }

    private var pityPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
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
        .padding(10)
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
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let price = scroll.divinityPrice {
                    Button {
                        store.buyScroll(scroll)
                    } label: {
                        Label("Buy — \(price)", systemImage: "sparkles")
                            .font(Theme.body(12).weight(.semibold))
                            .foregroundStyle(Theme.gold)
                            .lineLimit(1)
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
        .padding(10)
        .panelBackground()
    }

    private func perform(count: Int) {
        let results = store.summon(banner: selectedBanner, count: count)
        guard !results.isEmpty else { return }
        revealResults = results
    }
}

/// The published odds. Shown in full, because a rate table that hides the pool
/// is not a rate table.
struct RateTableView: View {
    let banner: Banner
    @Environment(\.dismiss) private var dismiss

    /// The pool across the width instead of one name to a row: a landscape
    /// phone fits four columns where the list showed a single name and 80% air.
    private let unitColumns = [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 6)]

    private var table: [BannerOdds] { SummonService.oddsTable(for: banner) }

    /// How many units the banner can actually give you, across every grade.
    private var poolCount: Int {
        table.reduce(0) { $0 + $1.units.count }
    }

    var body: some View {
        NavigationStack {
            GameScreen("Rates", subtitle: banner.title, dismiss: { dismiss() }) {
                BarCount(value: "\(poolCount)", systemImage: "person.3.fill")
                BarCount(value: banner.scroll.displayName, systemImage: banner.scroll.glyph, tint: Theme.gold)
            } content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(banner.scroll.description)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)

                        ForEach(table) { entry in
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
                                    LazyVGrid(columns: unitColumns, alignment: .leading, spacing: 6) {
                                        ForEach(entry.units) { unit in
                                            HStack(spacing: 8) {
                                                ElementBadge(element: unit.element, compact: true)
                                                Text(unit.name)
                                                    .font(Theme.body(13))
                                                    .foregroundStyle(Theme.textPrimary)
                                                    .lineLimit(1)
                                                if banner.featured.contains(unit.id) {
                                                    Text("FEATURED")
                                                        .font(Theme.body(8).weight(.black))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Capsule().fill(Theme.gold.opacity(0.25)))
                                                        .foregroundStyle(Theme.gold)
                                                }
                                                Spacer(minLength: 0)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .panelBackground()
                        }
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
