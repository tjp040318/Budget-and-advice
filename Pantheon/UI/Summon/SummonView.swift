import SwiftUI

/// The gacha screen: a summoning room you are standing in, not a picture of one.
///
/// The owner played the previous build and said he "was picturing more the
/// summons live on the island with a menu to the side thats scrolable, with
/// little ? to view other details. Like summoners war". What the screenshot
/// showed instead was three separate faults. The temple was a small BOXED
/// painting in the middle of the frame, with a rounded border and a gap all
/// round it, so it read as a picture of a room. The scroll rail down the left
/// was clipped mid-row by the bottom of the screen — "Wind Scroll 60" was cut
/// in half — with nothing to say there was more below it. And the right third
/// of the frame was a permanent rates slab (a pity box and the 1.5 / 10.0 /
/// 88.5 table) that repeated what the strip's Rates button already opened,
/// with dead space under it.
///
/// So the room is the screen now: `SummoningCircle` is the content's
/// `.background`, edge to edge, and everything else is overlaid ON it — the
/// banners as one translucent menu down the left, the two summon plates low
/// and right where the thumb is in landscape, and everything the slab used to
/// say behind the three circled question marks the owner asked for.
struct SummonView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedBanner: Banner = Banner.all[0]
    @State private var revealResults: [SummonResult] = []
    /// The full published table — every grade's odds and every name in the
    /// pool. It is `RateTableView`, the screen the strip's Rates button used
    /// to open; the button is gone and the rates ? is the one way in.
    @State private var showPool = false
    /// True for the moment between the button and the reveal, so the circle
    /// can wind up before the unit arrives.
    @State private var isCharging = false
    /// The banner's mileage exchange, and the opening selector.
    @State private var showMileage = false
    @State private var showSelector = false

    /// The side menu's width, and the same number the room is composed
    /// against: the painting is centred in what is left of the frame after
    /// the menu, so the altar stands in the middle of the room the player can
    /// actually see instead of 88 points to the left of it.
    private static let menuWidth: CGFloat = 204

    /// The band the scroll over the ring hangs in, in the room's own points:
    /// below the header (8 points of padding, the eyebrow and the 30-point
    /// name, whose ink ends near 50) and above the deck (10 points of padding
    /// and the 46-point plates). Run 217 hung the scroll off the ring alone
    /// and its top ran under the "5★ 3.0%" chip and against the name's ?.
    private static let headerFoot: CGFloat = 58
    private static let deckHead: CGFloat = 60

    var body: some View {
        NavigationStack {
            GameScreen("Summon") {
                // The two banner dropdowns that used to live here did the same
                // job as the menu on the left, and the Rates button opened the
                // same table as the slab beside it. One control per thing: the
                // strip is left with what nothing else on the screen says.
                BarCount(
                    value: "\(store.player.wallet.count(of: selectedBanner.scroll))",
                    systemImage: selectedBanner.scroll.glyph,
                    tint: Theme.gold,
                    itemKey: ItemArt.key(scroll: selectedBanner.scroll)
                )
                BarWallet(wallet: store.player.wallet)
            } content: {
                // The hall is the screen (2026-09-22): the painting under
                // everything, the rail and the words floating over it on
                // dark glass, light shafts and motes over the painting.
                ZStack(alignment: .topLeading) {
                    room
                    PlaceAmbience()
                    HStack(spacing: 0) {
                        bannerRail
                        roomControls
                    }
                }
            }
            .fullScreenCover(isPresented: .constant(!revealResults.isEmpty)) {
                SummonRevealView(results: revealResults, scroll: selectedBanner.scroll) {
                    revealResults = []
                }
            }
            .sheet(isPresented: $showPool) {
                RateTableView(banner: selectedBanner)
            }
            .sheet(isPresented: $showMileage) {
                MileageSheet(banner: selectedBanner) { result in
                    warmFirstFigure([result])
                    revealResults = [result]
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showSelector) {
                SelectorSheet { result in
                    warmFirstFigure([result])
                    revealResults = [result]
                }
                .environmentObject(store)
            }
            // The gift opens itself the first time the summoner walks into the
            // circle. Epic Seven puts its Selective Summon at account creation
            // for the same reason: a selector a player has to go looking for
            // is a selector most players never find.
            .onAppear {
                if SelectorService.isOwed(store.player) { showSelector = true }
                // The charge's rune rings are keyed off the main thread
                // before the first summon needs them.
                RuneLinesArt.prepare()
            }
        }
    }

    /// Out to the glass on both sides, as every other place's painting is
    /// (`PlaceBackdrop` bleeds by default): run 217 still photographed this
    /// hall in cream columns 60 points wide, because the room is its own
    /// view and the shared bleed never reached it. The circle's geometry
    /// reads the wider frame, so the rings stay on the painted floor; the
    /// expansion never changes the size the ZStack is told, and the room's
    /// `.clipped()` bounds it. The rail and the words stay in the safe area.
    private var room: some View {
        SummoningCircle(
            banner: selectedBanner,
            charging: isCharging,
            leadingInset: Self.menuWidth,
            headerClearance: Self.headerFoot,
            deckClearance: Self.deckHead
        )
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
    }

    // MARK: - The banner menu

    /// Every banner the player can spend on, down the left of the room and on
    /// top of it: the genre's rule is that the thing you are about to spend is
    /// a list you look at, not a value hidden inside a dropdown.
    ///
    /// It is a panel over the painting rather than a column beside it, so the
    /// temple runs on behind it, and it ends in a fade instead of the screen
    /// edge. The rail it replaces was pinned to the bottom of the frame, so
    /// the last row was guillotined halfway through — the owner's screenshot
    /// caught the Wind Scroll cut through its own count.
    // MARK: - The banner rail (2026-09-22)
    //
    // Cards on dark glass down the left, over the painting: the scroll's
    // painting large, the banner's name in carved capitals, the count in a
    // gold bead; the chosen one on a gold plate with a glow. The cream list
    // with 24-point icons it replaces read as a settings table.

    private var bannerRail: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                railSection("Pantheons", banners: Banner.pantheonBanners, short: false)
                railSection("Scrolls", banners: Banner.scrollBanners, short: true)
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
        }
        .frame(width: Self.menuWidth)
        .frame(maxHeight: .infinity)
        .mask(
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        )
        // The shared rail glass (this screen's own plate, made shared in
        // phase B), which runs out under the leading inset now that the
        // hall does: the rows stay in the safe area, the glass meets the
        // glass of the phone.
        .background(GlassRailPlate())
    }

    private func railSection(_ title: String, banners: [Banner], short: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(Theme.title(10))
                .tracking(2.0)
                .carved(glow: false)
                .padding(.top, 8)
                .padding(.leading, 4)
            ForEach(banners) { banner in
                railRow(banner, short: short)
            }
        }
    }

    private func railRow(_ banner: Banner, short: Bool) -> some View {
        let owned = store.player.wallet.count(of: banner.scroll)
        let isOn = banner.id == selectedBanner.id
        let key = ItemArt.key(scroll: banner.scroll)
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            selectedBanner = banner
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.35))
                    if ItemArt.hasPainting(key) {
                        ItemIcon(key: key, size: 32, glow: false)
                    } else {
                        Image(systemName: banner.scroll.glyph)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(banner.scroll.tint)
                    }
                }
                .frame(width: 36, height: 36)
                Text(short ? shortName(banner) : banner.title)
                    .font(Theme.title(11))
                    .foregroundStyle(isOn ? Color(hex: "#FFF1C2") : Theme.onGlass)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 2)
                Text("\(owned)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(owned > 0 ? Color(hex: "#FFE29A") : Theme.onGlassDim)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .overlay(Capsule().strokeBorder(Theme.goldDim.opacity(0.7), lineWidth: 0.6))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(railRowPlate(isOn: isOn))
        }
        .buttonStyle(.plain)
        .opacity(owned > 0 || isOn ? 1 : 0.6)
    }

    private func railRowPlate(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isOn
                  ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#6A5020"), Color(hex: "#2E2210")], startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(Color.white.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? Theme.gold.opacity(0.95) : Color.white.opacity(0.12), lineWidth: isOn ? 1.2 : 0.8)
            )
            .shadow(color: isOn ? Theme.gold.opacity(0.45) : .clear, radius: 8)
    }

    private func shortName(_ banner: Banner) -> String {
        banner.title
            .replacingOccurrences(of: "The ", with: "")
            .replacingOccurrences(of: " Scroll", with: "")
    }

    // MARK: - What sits on the room

    private var roomControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            roomHeader
            Spacer(minLength: 8)
            summonDeck
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // The banner's name carved in gold at 30 points over the dark top of
    // the painting, the scroll's kind as an eyebrow above it, the odds, the
    // pity and the mileage as glass beads at the right (2026-09-22).
    private var roomHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedBanner.scroll.displayName.uppercased())
                    .font(Theme.title(10))
                    .tracking(2.4)
                    .foregroundStyle(Color(hex: "#E0C275"))
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(selectedBanner.title)
                        .font(Theme.display(30))
                        .carved()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    InfoDot(title: "This scroll") { scrollDetail }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 6) {
                    oddsChip
                    if showsPity {
                        pityChip
                    }
                }
                mileageChip
            }
        }
    }


    /// The banner's mileage, said as what it is and what it is for (run
    /// 221: a ticket and a bare "118" said neither): the word, and the
    /// points against the price of the dearest unit the exchange sells —
    /// the thing a player is saving for, the first row of its catalogue.
    private var mileageChip: some View {
        let points = MileageService.points(on: selectedBanner, player: store.player)
        let best = MileageService.catalogue(for: selectedBanner).first
        let reading: String = best.map { "\(points)/\($0.price)" } ?? "\(points)"
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            showMileage = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.gold)
                Text("Mileage")
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(Theme.onGlassDim)
                Text(reading)
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.onGlass)
                if let best, points >= best.price {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.success)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(chipPlate)
        }
        .buttonStyle(.plain)
    }

    /// A capsule for a reading and its question mark, translucent so the
    /// temple carries on behind it.
    private var chipPlate: some View {
        Capsule()
            .fill(Theme.glass)
            .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 0.8))
    }


    private var oddsChip: some View {
        let best = SummonService.oddsTable(for: selectedBanner).first
        return HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Theme.gold)
            Text(best.map { "\($0.stars)★ \(String(format: "%.1f%%", $0.chance * 100))" } ?? "—")
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
            // This ? opens the full table rather than a paragraph: every
            // grade's odds AND every name in the pool are already a screen
            // (`RateTableView`), and two summaries of one table is the fault
            // being fixed here, not a pattern to repeat.
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showPool = true
            } label: {
                InfoGlyph()
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 9)
        .padding(.trailing, 1)
        .frame(height: 28)
        .background(chipPlate)
    }

    // MARK: - Pity

    private var pity: PityState {
        store.player.summonPity[selectedBanner.id] ?? PityState()
    }

    /// A banner without counters (the Unknown Scroll has none) would otherwise
    /// draw an empty capsule into the header.
    private var showsPity: Bool {
        selectedBanner.legendaryPity != nil
            || selectedBanner.rarePity != nil
            || pity.featuredGuaranteed
    }

    private var pityChip: some View {
        HStack(spacing: 7) {
            if let cap = selectedBanner.legendaryPity {
                pityReading(label: "5★", value: pity.sinceLegendary, cap: cap, tint: Theme.gold)
            }
            if let cap = selectedBanner.rarePity {
                pityReading(label: "4★+", value: pity.sinceRare, cap: cap, tint: Theme.onGlassDim)
            }
            if pity.featuredGuaranteed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.success)
            }
            InfoDot(title: "Guaranteed summons") { pityDetail }
        }
        .padding(.leading, 9)
        .padding(.trailing, 1)
        .frame(height: 28)
        .background(chipPlate)
        // Its own width, whole (run 207: "5★ in… ··· in…"); the banner's
        // name on the left shrinks instead.
        .fixedSize()
    }

    /// The reading counts DOWN, not up.
    ///
    /// "5★ 12/90" is a fact about the past; "5★ in 78" is the thing the player
    /// is actually deciding on, and it is how every published pity tracker in
    /// the genre words it. The counter is bumped before it is tested, so the
    /// number of summons still to make is `cap - value`.
    private func pityReading(label: String, value: Int, cap: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Theme.body(10).weight(.black))
                .foregroundStyle(tint)
            // On the glass chip: ink here was invisible on run 204 ("5★ …").
            Text("in \(max(1, cap - value))")
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.onGlass)
        }
    }

    /// What "4★+ 2/20" means, which is the thing the slab never actually said.
    /// The wording is read off `SummonService.single`: the counter is bumped
    /// before it is tested, so the cap-th summon SINCE the last hit is the
    /// guaranteed one, and soft pity opens at three quarters of the legendary
    /// cap and adds six points of 5★ chance per summon after it.
    private var pityDetail: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let cap = selectedBanner.legendaryPity {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Guaranteed 5★ in \(max(1, cap - pity.sinceLegendary)) more summons — \(pity.sinceLegendary) of \(cap) are behind you. From the \(Int(Double(cap) * 0.75))th the 5★ chance climbs steeply, so it rarely comes to the guarantee.")
                    StatBar(
                        value: Double(pity.sinceLegendary),
                        maximum: Double(cap),
                        tint: Theme.gold,
                        height: 5
                    )
                }
            }
            if let cap = selectedBanner.rarePity {
                Text("\(pity.sinceRare) of \(cap) since your last 4★ or better. The \(cap)th summon on this banner cannot be a 3★.")
            }
            if pity.featuredGuaranteed {
                Label("Your last 5★ lost the coin toss, so your next one is guaranteed to be the featured unit.",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.success)
            }
            Text("Each banner keeps its own counters, and changing scroll does not reset them.")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(Theme.body(11))
        .foregroundStyle(Theme.textPrimary)
    }

    // MARK: - The scroll in hand

    /// What this scroll is and what it draws from. The slab could only print
    /// this on the one banner with room for it — the Unknown Scroll, whose
    /// single 3★ row left its column black — and said nothing on the other
    /// nine. Behind the ?, every banner can say it.
    private var scrollDetail: some View {
        let scroll = selectedBanner.scroll
        let pool = SummonService.eligible(for: selectedBanner)
        return VStack(alignment: .leading, spacing: 9) {
            Text(selectedBanner.subtitle)
            Text(scroll.description)
                .foregroundStyle(Theme.textSecondary)
            detailRow(label: "Souls in the pool", value: "\(pool.count)")
            detailRow(label: "Scrolls held", value: "\(store.player.wallet.count(of: scroll))")
            detailRow(
                label: "Price",
                value: scroll.divinityPrice.map { "\($0) divinity" } ?? "Drachma, in the bazaar"
            )
        }
        .font(Theme.body(11))
        .foregroundStyle(Theme.textPrimary)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 6)
            Text(value)
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
        }
    }

    // MARK: - The plates

    /// The buttons stay where the hand is: one bar across the foot of the
    /// room, the plates at its trailing end, which in landscape is under the
    /// right thumb and is also the corner the owner called dead space. The
    /// ×10 is the emphasised one — it wears the painted gold plate while ×1
    /// takes a cream plate with a gold edge — and it is given the wider frame
    /// of the two.
    private var summonDeck: some View {
        let scroll = selectedBanner.scroll
        let owned = store.player.wallet.count(of: scroll)
        let price = scroll.divinityPrice
        let affordable = price.map { store.player.wallet.divinity >= $0 } ?? false
        let hint = countLine(owned: owned, price: price)

        // The deck floats on the dark foot of the painting (2026-09-22): the
        // ×10 on the painted gold plate with its gloss, the ×1 and Buy on
        // dark glass, 46 points tall, no cream tray under them.
        return VStack(alignment: .trailing, spacing: 6) {
            if !hint.isEmpty {
                Text(hint)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Color(hex: "#E0C275"))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(chipPlate)
            }

            HStack(spacing: 12) {
                if let price {
                    buyButton(price: price, affordable: affordable)
                }

                PrimaryButton(
                    title: "Summon ×1",
                    systemImage: scroll.glyph,
                    tint: Theme.surfaceHigh,
                    isEnabled: owned >= 1,
                    itemKey: ItemArt.key(scroll: scroll),
                    style: .glass
                ) {
                    perform(count: 1)
                }
                .frame(maxWidth: 190)

                PrimaryButton(
                    title: "Summon ×10",
                    systemImage: scroll.glyph,
                    isEnabled: owned >= 10,
                    itemKey: ItemArt.key(scroll: scroll)
                ) {
                    perform(count: 10)
                }
                .frame(maxWidth: 250)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func buyButton(price: Int, affordable: Bool) -> some View {
        Button {
            store.buyScroll(selectedBanner.scroll)
        } label: {
            HStack(spacing: 6) {
                ItemIcon(key: "divinity", size: 20, glow: false)
                Text("Buy · \(price)")
                    .font(Theme.title(12))
                    .tracking(0.6)
            }
            .foregroundStyle(affordable ? Color(hex: "#FFE9A8") : Theme.onGlassDim)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(GlassPlate(radius: Theme.tightCorner))
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
    }

    private func countLine(owned: Int, price: Int?) -> String {
        if owned == 0 {
            return price == nil ? "None held — the bazaar sells them for drachma" : "None held"
        }
        if owned < 10 { return "×10 needs \(10 - owned) more" }
        return ""
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
        warmFirstFigure(results)
        AudioLibrary.shared.play(.summonCharge)
        Juice.haptic(.medium)
        withAnimation(.easeIn(duration: 0.2)) { isCharging = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isCharging = false
            revealResults = results
        }
    }

    /// The first figure the reveal will stand on its beam starts parsing
    /// the moment the summon returns (2026-09-23, run 221): the wind-up and
    /// the cover's presentation are most of a second, and the reveal's
    /// stage then clones it from the cache instead of parsing it on the
    /// main thread (1.2 s of it on the CI's simulator). The FIRST only: the
    /// warm pass parses its list in no set order, and a ten-pull's second
    /// figure would contend with its first for the importer. The reveal
    /// warms each next pull while the one before is on the beam.
    private func warmFirstFigure(_ results: [SummonResult]) {
        guard let first = results.first else { return }
        ModelLibrary.shared.warm([first.blueprint.model])
    }
}

// The little ? (`InfoGlyph`, `InfoDot`) moved to Glass.swift in phase B
// (2026-09-22), shared by every place screen.

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
                BarCount(value: banner.scroll.displayName, systemImage: banner.scroll.glyph, tint: Theme.gold,
                         itemKey: ItemArt.key(scroll: banner.scroll))
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
            // The Light and Dark discount, said out loud. It is the one rate
            // on this screen a player cannot work out from the pool in front
            // of him, because it is not a grade rate — it is a weighting
            // inside the grade.
            if let line = entry.lightDarkLine {
                Text(line)
                    .font(Theme.numeric(11))
                    .foregroundStyle(ScrollType.lightDark.tint)
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

}

// MARK: - The room

/// The summoning room: the thing the player is actually looking at while he
/// decides to spend a scroll, and since this pass the whole screen.
///
/// The owner asked for the genre's summoning room — "a summon circle (we need
/// to pick something else) and then you select scrolls on one side and an
/// animation plays and the mon spawns". Ours is not a pentagram: it is the
/// **Ring of Names**, the rune ring already painted for the 3D summoning stage
/// (`rune_ring`, Pantheon/Resources/Stage), turning slowly over the temple's
/// own painted floor circle with the scroll's element burning in the middle.
///
/// It is drawn in SwiftUI rather than SceneKit on purpose. This screen is
/// entered dozens of times a session and a live 3D view would cost a scene
/// build every time; the reveal that follows is the 3D moment and it earns it.
/// What this has to do is breathe, and wind up when a summon is coming.
struct SummoningCircle: View {
    let banner: Banner
    /// Set for the moment between the button and the reveal.
    var charging: Bool
    /// How much of the frame's leading edge the banner menu covers. The
    /// painting is centred in what is left over rather than in the whole
    /// frame, so the altar stands in the middle of the room the player can
    /// see; on a 734-point frame with a 176-point menu that also hides the
    /// letterbox under the menu instead of leaving it beside the art. Since
    /// 2026-09-23 the frame is the whole glass (the room bleeds under both
    /// side insets), which grows it the same on both sides, so the ring
    /// stands where it stood.
    var leadingInset: CGFloat = 0
    /// How far down the frame the words laid over the room reach (the
    /// banner's name and the rates chips), and how far up from its foot the
    /// summon plates stand: the scroll over the ring hangs in the band
    /// between, whatever the painting's scale does to the ring.
    var headerClearance: CGFloat = 0
    var deckClearance: CGFloat = 0

    @State private var spin: Double = 0
    @State private var pulse: CGFloat = 1

    private var tint: Color { banner.scroll.tint }

    /// Where the painted floor ring sits in `summon_hall_bg`, in fractions of
    /// the painting. Measured off the art, like every other anchor here.
    private static let floorCentre = CGPoint(x: 0.50, y: 0.82)
    private static let floorRadius: CGFloat = 0.21

    var body: some View {
        GeometryReader { frame in
            // The hall is drawn to FIT, not to fill: the floor ring has to land
            // where the painter put it, and a fill crop moves it. Everything
            // below is measured off the fitted art rect, so the glow and the
            // rune rings stay on the painted meander whatever the frame does.
            // The painting COVERS the frame (2026-09-22), anchored to its
            // floor so the summoning circle stays in view: the hall is the
            // screen, the rail and the words float over it.
            let scale = max(frame.size.width / 16.0, frame.size.height / 9.0)
            let artWidth = scale * 16
            let artHeight = scale * 9
            let originX = (frame.size.width - artWidth) / 2
            // Hung three quarters of the way from its top edge to its foot
            // (2026-09-23), not by the foot alone: run 221's crop cut the
            // right-hand brazier at the strip, a bare dark tripod with its
            // fire above the frame. Only as far down as keeps the painted
            // floor ring's centre above the summon plates — on the phone
            // that is 26 points lower, the brazier's bowl and the foot of
            // its fire in view.
            let footAnchored = frame.size.height - artHeight
            let ringAbovePlates = frame.size.height - deckClearance - Self.floorCentre.y * artHeight
            let originY = min(footAnchored * 0.75, max(footAnchored, ringAbovePlates))
            // The ring stands in the room to the right of the rail.
            let centre = CGPoint(
                x: originX + Self.floorCentre.x * artWidth + leadingInset * 0.42,
                y: originY + Self.floorCentre.y * artHeight
            )
            let ringSize = Self.floorRadius * 2 * artWidth

            ZStack {
                // Dark beyond the painting's edge (2026-09-22): the cover
                // crop leaves none in view, and a cream bar would be the
                // cheap copy back.
                Color(hex: "#0E0B08")
                hall(width: artWidth, height: artHeight)
                    .position(x: originX + artWidth / 2, y: originY + artHeight / 2)

                // The light standing in the floor ring.
                RadialGradient(
                    colors: [tint.opacity(charging ? 0.85 : 0.5), tint.opacity(0.12), .clear],
                    center: .center, startRadius: 2, endRadius: ringSize * 0.62
                )
                .frame(width: ringSize * 1.5, height: ringSize * 1.5)
                .blendMode(.screen)
                .position(centre)

                // Two rings of runes over the painted meander, turning opposite
                // ways so it reads as machinery rather than a spinning picture.
                ring(size: ringSize * 0.94, opacity: 0.85, angle: spin)
                    .position(centre)
                ring(size: ringSize * 0.62, opacity: 0.55, angle: -spin * 1.6)
                    .position(centre)

                // The scroll itself, standing over the ring where the unit
                // will step out of it: the painted scroll the menu row and
                // the plates carry, not a mark (2026-09-17, evening; the
                // owner: "use that artwork IN the summoning circle"). At
                // rest it hangs above the ring, tilted, and breathes; when
                // the summon is coming it drops toward the ring's centre,
                // swells and flares, and the reveal takes over.
                scrollOverTheRing(centre: centre, ringSize: ringSize, height: frame.size.height)

                // The banner's name used to hang above the altar here, on a
                // marble plaque. It is in the header now: this whole view is a
                // background and a background cannot be tapped, so the little ?
                // that explains the scroll had to stand beside a name that
                // lives in the control layer.
                //
                // The washes go last, over everything, so the controls that sit
                // on the room have something to be read against.
                scrims
            }
        }
        // Safe on both counts of the rule this app learned the hard way: the
        // GeometryReader's own size is the size it was proposed, so nothing
        // here can grow an ancestor, and the whole room is unhittable below.
        .clipped()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                spin = 360
            }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = 1.06
            }
        }
        .animation(.easeOut(duration: 0.35), value: charging)
    }

    /// The scroll over the ring (see `body`): a disc of its own light behind
    /// it so it reads against the painted floor and the marble alike, a slow
    /// breath (`pulse`) as a bob and a swell. The glyph remains the fallback
    /// for a scroll whose painting has not shipped.
    ///
    /// It hangs in the band between the header and the deck
    /// (`headerClearance`, `deckClearance`), at four fifths of the band or
    /// two fifths of the ring, whichever is smaller, and swells a quarter
    /// and drops a third of the way to the ring's centre when charging. Run
    /// 217 hung it at 0.44 of the ring above the centre and two fifths of
    /// the ring tall, which put its top under the "5★ 3.0%" chip.
    private func scrollOverTheRing(centre: CGPoint, ringSize: CGFloat, height: CGFloat) -> some View {
        let key = ItemArt.key(scroll: banner.scroll)
        let top = headerClearance
        let foot = max(top + 40, height - deckClearance)
        let rest = min(ringSize * 0.40, (foot - top) * 0.80)
        let size = charging ? rest * 1.25 : rest
        let restY = (top + foot) / 2
        let y = charging ? restY + (centre.y - restY) * 0.35 : restY
        return ZStack {
            RadialGradient(
                colors: [tint.opacity(charging ? 0.9 : 0.5), tint.opacity(0)],
                center: .center, startRadius: 0, endRadius: size * 0.72
            )
            .frame(width: size * 1.6, height: size * 1.6)
            .blendMode(.screen)
            if ItemArt.hasPainting(key) {
                ItemIcon(key: key, size: size, glow: false)
                    // Seven of the eight painted scrolls carry their sheet's
                    // dark ground as a ragged glow round the roll (only the
                    // black was keyed), and on the marble hall it read as a
                    // black smudge behind the scroll (run 217). Every roll
                    // lies corner to corner, lower left to upper right, so a
                    // feathered capsule along that diagonal keeps the roll,
                    // its knobs, its seal and its ribbon and lets the ground
                    // go. Before the tilt, so it is the painting's diagonal.
                    .mask {
                        Capsule()
                            .frame(width: size * 1.34, height: size * 0.44)
                            .rotationEffect(.degrees(-45))
                            .blur(radius: size * 0.025)
                    }
                    .rotationEffect(.degrees(charging ? 0 : -12))
                    // The element's light round the roll, and no dark drop
                    // shadow under it: a scroll hanging in light casts none.
                    .shadow(color: tint.opacity(0.85), radius: charging ? size * 0.22 : size * 0.10)
            } else {
                Image(systemName: banner.scroll.glyph)
                    .font(.system(size: size * 0.4, weight: .black))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.9), radius: charging ? 24 : 12)
            }
        }
        .scaleEffect(pulse)
        .offset(y: (1 - pulse) * 90)
        .position(x: centre.x, y: y)
    }

    /// Something for the overlaid controls to sit on. The lettering over the
    /// room is ink on cream plates, so both washes LIGHTEN: the top of the
    /// room under the banner's name and the foot of it under the summon
    /// plates go toward cream, the way the island's edges do. The bottom wash
    /// is the lighter of the two because the floor circle burns inside it.
    /// The top one was an ink wash left from the days of white lettering, and
    /// it stood the ink title on a black vault.
    private var scrims: some View {
        // Dark, since 2026-09-22: a cream veil over a painting is what read
        // as a cheap copy; a dark one is a cinema's, and gold words sit on it.
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 110)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
        }
        .allowsHitTesting(false)
    }

    private func hall(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if BundleImage.exists("summon_hall_bg") {
                BundleImage(name: "summon_hall_bg")
                    .aspectRatio(contentMode: .fill)
            } else if BundleImage.exists(banner.artName) {
                BundleImage(name: banner.artName)
                    .aspectRatio(contentMode: .fill)
                    .overlay(Theme.plate.opacity(0.3))
            } else {
                RadialGradient(
                    colors: [tint.opacity(0.30), Theme.surface],
                    center: .center, startRadius: 8, endRadius: 320
                )
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(edgeFade)
        .allowsHitTesting(false)
    }

    /// The painting is 16:9 and a landscape phone's content area is about
    /// 2.2:1, so fitting it leaves the cream ground beside it. A hard vertical
    /// seam between painted marble and flat cream is exactly the boxed-picture
    /// look this pass exists to kill, so the art is feathered into the ground
    /// over 44 points at its sides and 30 at its top and bottom, and the seam
    /// disappears whether the letterbox is 20 points wide or the art runs off
    /// the screen. The transparent stops are the plate's own colour at zero:
    /// a fade to transparent INK passes through a grey band on the way.
    private var edgeFade: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.45)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 60)
        }
        .allowsHitTesting(false)
    }

    private func ring(size: CGFloat, opacity: Double, angle: Double) -> some View {
        Group {
            if BundleImage.exists("rune_ring") {
                BundleImage(name: "rune_ring")
                    .aspectRatio(contentMode: .fit)
                    .colorMultiply(tint)
                    .blendMode(.screen)
            } else {
                Circle()
                    .strokeBorder(tint.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 10]))
            }
        }
        .opacity(opacity)
        .frame(width: size, height: size)
        .scaleEffect(charging ? 1.06 : 1.0)
        .rotationEffect(.degrees(angle))
        .allowsHitTesting(false)
    }
}

// The hall's air is `PlaceAmbience` (Glass.swift) since phase B
// (2026-09-22): its defaults are this hall's shafts and motes.
