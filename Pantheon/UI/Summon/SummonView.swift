import SwiftUI

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
    /// True for the moment between the button and the reveal, so the circle
    /// can wind up before the unit arrives.
    @State private var isCharging = false

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
                // The genre's summoning room: the scrolls you own down one
                // side, the circle in the middle, and the summon under it.
                HStack(alignment: .top, spacing: 10) {
                    scrollRail
                    VStack(spacing: 8) {
                        SummoningCircle(banner: selectedBanner, charging: isCharging)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        summonButtons
                    }
                    VStack(spacing: 8) {
                        if showsPity {
                            pityPanel
                        }
                        ratesPanel
                        Spacer(minLength: 0)
                    }
                    .frame(width: 210)
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
        guard Banner.pantheonBanners.contains(where: { $0.id == selectedBanner.id }) else { return "Choose" }
        return selectedBanner.pantheon?.displayName ?? shortName(selectedBanner)
    }

    private var scrollValue: String {
        guard Banner.scrollBanners.contains(where: { $0.id == selectedBanner.id }) else { return "Choose" }
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

    // MARK: - Rates

    /// The published odds, on the screen rather than behind the strip's Rates
    /// button. The column between the pity counters and the summon plates was
    /// black — and on the Unknown Scroll, which has no counters at all, the
    /// whole column above the buttons was. A row per grade fills it with the
    /// one thing a player wants before spending: the chance, and how many
    /// souls each grade can hand them — and, on the one banner whose single
    /// row leaves the column empty, what the scroll is. The full pool is still
    /// one tap away behind the strip's Rates button.
    private var ratesPanel: some View {
        SectionPanel(title: "Rates", accessory: selectedBanner.scroll.displayName) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(spacing: 4) {
                    ForEach(SummonService.oddsTable(for: selectedBanner)) { entry in
                        rateRow(entry)
                    }
                }
                // The Unknown Scroll is the one banner with no pity counters
                // and a single 3★ row, so its column was black from the strip
                // to the plates. It is also the one with room for the sentence
                // that says what the scroll is; every other banner shows its
                // counters there instead.
                if !showsPity {
                    Text(selectedBanner.scroll.description)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One grade: the stars, the published chance, and how many souls of that
    /// grade the banner can actually hand you.
    private func rateRow(_ entry: BannerOdds) -> some View {
        HStack(spacing: 6) {
            StarRow(stars: entry.stars, size: 9)
            Spacer(minLength: 4)
            Text(String(format: "%.1f%%", entry.chance * 100))
                .font(Theme.numeric(11))
                .foregroundStyle(entry.stars >= 5 ? Theme.gold : Theme.textSecondary)
                .frame(width: 44, alignment: .trailing)
            HStack(spacing: 2) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 8, weight: .black))
                Text("\(entry.units.count)")
                    .font(Theme.numeric(10))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - Buttons

    private var summonButtons: some View {
        let scroll = selectedBanner.scroll
        let owned = store.player.wallet.count(of: scroll)
        let price = scroll.divinityPrice
        let affordable = price.map { store.player.wallet.divinity >= $0 } ?? false

        return VStack(spacing: 10) {
            HStack {
                // The count was printed three times in one frame — the strip
                // carries it, so does every dropdown row. This line spends
                // itself on the thing nothing else says: why a plate is grey.
                Text(countLine(owned: owned, price: price))
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(owned >= 10 ? Theme.textSecondary : Theme.gold)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let price {
                    Button {
                        store.buyScroll(scroll)
                    } label: {
                        // A control is a rounded rectangle of surfaceRaised
                        // with a hairline in its own tint, everywhere in this
                        // app. This one was a bare gold caption with a 13-point
                        // tap target that stayed lit when it could not be paid.
                        Label("Buy — \(price)", systemImage: "sparkles")
                            .font(Theme.body(12).weight(.semibold))
                            .foregroundStyle(affordable ? Theme.gold : Theme.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: Theme.controlHeight)
                            .background(ScreenChrome.controlShape.fill(Theme.surfaceRaised))
                            .overlay(
                                ScreenChrome.controlShape
                                    .strokeBorder(
                                        (affordable ? Theme.goldDim : Theme.stroke).opacity(0.6),
                                        lineWidth: 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!affordable)
                }
            }

            HStack(spacing: 10) {
                // `tint` is the label colour on the dark painted plate, not the
                // plate's colour (Components.swift, `labelColor`): surfaceRaised
                // drew SUMMON ×1 in #1F1D3D on a #1F1D3D plate. Both plates wear
                // the glyph of the scroll they spend.
                PrimaryButton(
                    title: "Summon ×1",
                    systemImage: scroll.glyph,
                    tint: Theme.textPrimary,
                    isEnabled: owned >= 1
                ) {
                    perform(count: 1)
                }

                PrimaryButton(
                    title: "Summon ×10",
                    systemImage: scroll.glyph,
                    isEnabled: owned >= 10
                ) {
                    perform(count: 10)
                }
            }
        }
        .padding(10)
        .panelBackground()
    }

    /// The one line under the plates, and the only thing on screen that says
    /// why a plate is grey. At zero *both* plates are grey, so "×10 needs 10
    /// more" would read as though ×1 still worked; and the unknown scroll has
    /// no divinity price, so it has no Buy control beside this line to answer.
    private func countLine(owned: Int, price: Int?) -> String {
        if owned == 0 {
            return price == nil ? "None held — the bazaar sells them for drachma" : "None held"
        }
        if owned < 10 { return "\(owned) held — ×10 needs \(10 - owned) more" }
        return "\(owned) held"
    }

    /// The circle winds up, then the reveal takes over.
    ///
    /// The summon itself is resolved first and only the presentation waits:
    /// if the wallet says no, nothing lights up and nothing is spent. The
    /// 0.45 s is the charge — long enough to read as a wind-up, short enough
    /// that a player pulling ten times in a row does not feel taxed for it.
    private func perform(count: Int) {
        let results = store.summon(banner: selectedBanner, count: count)
        guard !results.isEmpty else { return }
        AudioLibrary.shared.play(.summonCharge)
        Juice.haptic(.medium)
        withAnimation(.easeIn(duration: 0.2)) { isCharging = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isCharging = false
            revealResults = results
        }
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
                            oddsPanel(entry)
                        }
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    /// One grade: the odds, and every unit that grade can hand you. Lifted out
    /// of `body` because the screen had become a single expression six closures
    /// deep, and the type checker is the one reviewer this project cannot run.
    private func oddsPanel(_ entry: BannerOdds) -> some View {
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
                        unitChip(unit)
                    }
                }
            }
        }
        .padding(12)
        .panelBackground()
    }

    /// A name in the pool: its element, its name, and a chip when the banner
    /// rates it up.
    private func unitChip(_ unit: UnitBlueprint) -> some View {
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
    // MARK: - The scroll rail

    /// Every scroll the player can spend, down the left of the screen, the way
    /// the genre lays out its summoning room: the thing you are spending is a
    /// list you look at, not a value hidden inside a dropdown. A row shows the
    /// scroll's glyph, what it summons and how many are left; the one in hand
    /// is lit, and one with none left is dimmed but still selectable, because
    /// wanting to read the odds for a scroll you have run out of is normal.
    private var scrollRail: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 4) {
                railSection("Pantheons", banners: Banner.pantheonBanners)
                railSection("Scrolls", banners: Banner.scrollBanners)
            }
        }
        .frame(width: 178)
    }

    private func railSection(_ title: String, banners: [Banner]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(Theme.body(9).weight(.black))
                .tracking(1.0)
                .foregroundStyle(Theme.goldDim)
                .padding(.top, 4)
            ForEach(banners) { banner in
                railRow(banner)
            }
        }
    }

    private func railRow(_ banner: Banner) -> some View {
        let owned = store.player.wallet.count(of: banner.scroll)
        let isOn = banner.id == selectedBanner.id
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            selectedBanner = banner
        } label: {
            HStack(spacing: 6) {
                Image(systemName: banner.scroll.glyph)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(isOn ? Theme.ink : Theme.gold)
                    .frame(width: 18)
                Text(banner.name)
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(isOn ? Theme.ink : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(owned)")
                    .font(Theme.numeric(11))
                    .foregroundStyle(isOn ? Theme.ink : (owned > 0 ? Theme.gold : Theme.textSecondary))
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? Theme.gold : Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.goldDim.opacity(isOn ? 0 : 0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(owned > 0 || isOn ? 1 : 0.55)
    }

}

// MARK: - The circle

/// The summoning circle: the thing the player is actually looking at while he
/// decides to spend a scroll.
///
/// The owner asked for the genre's summoning room — "a summon circle (we need
/// to pick something else) and then you select scrolls on one side and an
/// animation plays and the mon spawns". Ours is not a pentagram: it is the
/// **Ring of Names**, the rune ring already painted for the 3D summoning stage
/// (`rune_ring`, Pantheon/Resources/Stage), turning slowly over the banner's
/// own art with the scroll's element burning in the middle of it.
///
/// It is drawn in SwiftUI rather than SceneKit on purpose. This screen is
/// entered dozens of times a session and a live 3D view would cost a scene
/// build every time; the reveal that follows is the 3D moment and it earns it.
/// What this has to do is breathe, and wind up when a summon is coming.
struct SummoningCircle: View {
    let banner: Banner
    /// Set for the moment between the button and the reveal.
    var charging: Bool

    @State private var spin: Double = 0
    @State private var pulse: CGFloat = 1

    private var tint: Color { banner.scroll.tint }

    var body: some View {
        ZStack {
            // The banner's painting, behind everything, dimmed so the ring
            // reads over it. It is decoration: it must never take a tap.
            if BundleImage.exists(banner.artName) {
                BundleImage(name: banner.artName)
                    .aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(0.35))
                    .allowsHitTesting(false)
            } else {
                RadialGradient(
                    colors: [tint.opacity(0.30), Theme.ink],
                    center: .center, startRadius: 8, endRadius: 320
                )
                .allowsHitTesting(false)
            }

            // The floor glow the ring stands in.
            RadialGradient(
                colors: [tint.opacity(charging ? 0.75 : 0.45), .clear],
                center: .center, startRadius: 2, endRadius: 190
            )
            .blendMode(.screen)
            .allowsHitTesting(false)

            // The ring itself, turning. Two copies at different speeds and
            // opposite directions read as machinery rather than as a spinning
            // picture.
            ring(scale: 1.00, opacity: 0.85, angle: spin)
            ring(scale: 0.74, opacity: 0.55, angle: -spin * 1.6)

            // The scroll's own mark at the centre, breathing.
            Image(systemName: banner.scroll.glyph)
                .font(.system(size: charging ? 46 : 38, weight: .black))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.9), radius: charging ? 22 : 12)
                .scaleEffect(pulse)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.goldPlate, lineWidth: 1)
        )
        // .clipShape does not clip hit testing, and the painting inside is
        // scaled to fill: without this the circle would swallow taps well
        // outside its frame, including the summon buttons under it.
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                spin = 360
            }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = 1.12
            }
        }
        .animation(.easeOut(duration: 0.35), value: charging)
    }

    private func ring(scale: CGFloat, opacity: Double, angle: Double) -> some View {
        Group {
            if BundleImage.exists("rune_ring") {
                BundleImage(name: "rune_ring")
                    .aspectRatio(contentMode: .fit)
                    .colorMultiply(tint)
                    .blendMode(.screen)
            } else {
                // The texture has not shipped: draw the ring.
                Circle()
                    .strokeBorder(tint.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 10]))
            }
        }
        .opacity(opacity)
        .scaleEffect(scale * (charging ? 1.06 : 1.0))
        .rotationEffect(.degrees(angle))
        .frame(maxWidth: 260, maxHeight: 260)
        .allowsHitTesting(false)
    }
}
