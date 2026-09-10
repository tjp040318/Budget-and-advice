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

    /// The side menu's width, and the same number the room is composed
    /// against: the painting is centred in what is left of the frame after
    /// the menu, so the altar stands in the middle of the room the player can
    /// actually see instead of 88 points to the left of it.
    private static let menuWidth: CGFloat = 176

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
                    tint: Theme.gold
                )
                BarWallet(wallet: store.player.wallet)
            } content: {
                HStack(spacing: 0) {
                    bannerMenu
                    roomControls
                }
                // The room is the content's BACKGROUND, never a sibling in the
                // stack. A fill-aspect painting reports the size it needs to
                // cover its frame, and `.clipped()` clips neither that reported
                // size nor hit-testing: as a sibling under an unbounded frame
                // it measures larger than the window and grows every ancestor,
                // which blanked a whole screen in this app. A background is
                // laid out in the content's frame and can never push on it.
                .background(room)
            }
            .fullScreenCover(isPresented: .constant(!revealResults.isEmpty)) {
                SummonRevealView(results: revealResults) {
                    revealResults = []
                }
            }
            .sheet(isPresented: $showPool) {
                RateTableView(banner: selectedBanner)
            }
        }
    }

    private var room: some View {
        SummoningCircle(
            banner: selectedBanner,
            charging: isCharging,
            leadingInset: Self.menuWidth
        )
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
    private var bannerMenu: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                menuSection("Pantheons", banners: Banner.pantheonBanners, short: false)
                menuSection("Scrolls", banners: Banner.scrollBanners, short: true)
                // The fade below is 34 points tall. This is the room a whole
                // row needs to travel out from under it, so the list can be
                // scrolled to a clean end rather than to a dissolved half-row.
                Color.clear.frame(height: 34)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .frame(width: Self.menuWidth)
        .frame(maxHeight: .infinity)
        .background(menuPlate)
        .overlay(alignment: .bottom) { menuFade }
    }

    /// A dark wash with one gold hairline down its inner edge. Decorative, so
    /// it is marked unhittable like every other painted thing in this app.
    private var menuPlate: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [Theme.ink.opacity(0.93), Theme.ink.opacity(0.74)],
                startPoint: .leading,
                endPoint: .trailing
            )
            Rectangle()
                .fill(Theme.goldDim.opacity(0.55))
                .frame(width: 1)
        }
        .allowsHitTesting(false)
    }

    /// The bottom of the list, and the answer to the half-row. A row that
    /// scrolls under this dissolves instead of being cut, and the chevron says
    /// there is more below — there always is, because ten banners at 32 points
    /// a row need 390 and a landscape phone hands this panel about 340.
    ///
    /// It is a scrim rather than a `.mask`, because a mask takes hit-testing
    /// with it and the row under the fade must still be tappable.
    private var menuFade: some View {
        LinearGradient(
            colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Theme.goldDim)
                .padding(.bottom, 2)
        }
        .allowsHitTesting(false)
    }

    private func menuSection(_ title: String, banners: [Banner], short: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(Theme.body(9).weight(.black))
                .tracking(1.0)
                .foregroundStyle(Theme.goldDim)
                .padding(.top, 6)
                .padding(.leading, 3)
            ForEach(banners) { banner in
                menuRow(banner, short: short)
            }
        }
    }

    /// One banner: its scroll's glyph in the scroll's own colour, its name, and
    /// how many of that scroll are left. A row with none left is dimmed but
    /// still selectable, because wanting to read the odds for a scroll you have
    /// run out of is normal.
    private func menuRow(_ banner: Banner, short: Bool) -> some View {
        let owned = store.player.wallet.count(of: banner.scroll)
        let isOn = banner.id == selectedBanner.id
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            selectedBanner = banner
        } label: {
            HStack(spacing: 7) {
                Image(systemName: banner.scroll.glyph)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(isOn ? Theme.ink : banner.scroll.tint)
                    .frame(width: 17)
                Text(short ? shortName(banner) : banner.title)
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(isOn ? Theme.ink : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text("\(owned)")
                    .font(Theme.numeric(11))
                    .foregroundStyle(isOn ? Theme.ink : (owned > 0 ? Theme.gold : Theme.textSecondary))
            }
            .padding(.horizontal, 8)
            .frame(height: isOn ? 30 : 28)
            .background(rowPlate(isOn: isOn))
        }
        .buttonStyle(.plain)
        .opacity(owned > 0 || isOn ? 1 : 0.55)
    }

    /// The selected row has to be unmistakable against a lit painting, so it
    /// takes all three of the app's selection signals at once: the gold plate,
    /// ink lettering on it, and a glow the unselected rows do not have.
    private func rowPlate(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isOn ? Theme.gold : Theme.surfaceRaised.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.goldDim.opacity(isOn ? 0 : 0.35), lineWidth: 0.5)
            )
            .shadow(color: isOn ? Theme.gold.opacity(0.45) : .clear, radius: 6)
    }

    /// "The Endless Scroll" is a title for a painting, not for a 176-point
    /// menu row: the scrolls are listed as Endless, Unknown, Divine, Light &
    /// Dark, Fire, Water and Wind. The pantheons keep their full names, which
    /// are what the banners are actually called.
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// What the player is standing in front of, and the two numbers he decides
    /// on: the headline odds and the pity. Each carries the little ? the owner
    /// asked for, which is where the slab's content went — a question mark and
    /// a popover cost 26 points of the frame where the slab cost 210.
    private var roomHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text(selectedBanner.title)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    InfoDot(title: "This scroll") { scrollDetail }
                }
                Text(selectedBanner.scroll.displayName.uppercased())
                    .font(Theme.body(9).weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(Theme.gold)
            }
            .shadow(color: .black.opacity(0.85), radius: 5, x: 0, y: 1)

            Spacer(minLength: 6)

            oddsChip
            if showsPity {
                pityChip
            }
        }
    }

    /// A capsule for a reading and its question mark, translucent so the
    /// temple carries on behind it.
    private var chipPlate: some View {
        Capsule()
            .fill(Theme.ink.opacity(0.72))
            .overlay(Capsule().strokeBorder(Theme.goldDim.opacity(0.45), lineWidth: 0.5))
    }

    // MARK: - Rates

    /// The one number a player actually decides on — the chance of the best
    /// grade this scroll can hand him — with the full published table behind
    /// the ?. The table used to be printed twice in one frame: as a permanent
    /// slab down the right third, and again behind the strip's Rates button.
    private var oddsChip: some View {
        let best = SummonService.oddsTable(for: selectedBanner).first
        return HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Theme.gold)
            Text(best.map { "\($0.stars)★ \(String(format: "%.1f%%", $0.chance * 100))" } ?? "—")
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.textPrimary)
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
                pityReading(label: "4★+", value: pity.sinceRare, cap: cap, tint: Theme.textSecondary)
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
    }

    private func pityReading(label: String, value: Int, cap: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Theme.body(10).weight(.black))
                .foregroundStyle(tint)
            Text("\(value)/\(cap)")
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.textPrimary)
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
                    Text("\(pity.sinceLegendary) of \(cap) since your last 5★. The \(cap)th is a 5★ whatever the dice say, and from the \(Int(Double(cap) * 0.75))th the 5★ chance climbs steeply, so it rarely comes to that.")
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
    /// takes the dark one — and it is given the wider frame of the two.
    private var summonDeck: some View {
        let scroll = selectedBanner.scroll
        let owned = store.player.wallet.count(of: scroll)
        let price = scroll.divinityPrice
        let affordable = price.map { store.player.wallet.divinity >= $0 } ?? false
        let hint = countLine(owned: owned, price: price)

        return VStack(alignment: .trailing, spacing: 5) {
            // The hint floats above the bar rather than inside it. Measured on
            // the narrowest frame this ships to — an SE in landscape leaves the
            // room 491 points, and the Buy control and the two plates want 482
            // of them — a line sharing that row would have been squeezed to a
            // truncated stub or to nothing at all.
            if !hint.isEmpty {
                Text(hint)
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.9), radius: 4, x: 0, y: 1)
            }

            // No `Spacer` at the head of this row on purpose: the bar is only
            // as wide as the three controls in it, so it hugs the trailing
            // corner — under the right thumb in landscape, and the corner the
            // owner called dead space — instead of laying half a plate of
            // empty translucency over the floor of the room. A bigger room is
            // worth more than a filled corner.
            HStack(spacing: 10) {
                if let price {
                    buyButton(price: price, affordable: affordable)
                }

                PrimaryButton(
                    title: "Summon ×1",
                    systemImage: scroll.glyph,
                    tint: Theme.textPrimary,
                    isEnabled: owned >= 1
                ) {
                    perform(count: 1)
                }
                .frame(maxWidth: 150)

                PrimaryButton(
                    title: "Summon ×10",
                    systemImage: scroll.glyph,
                    isEnabled: owned >= 10
                ) {
                    perform(count: 10)
                }
                .frame(maxWidth: 210)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(deckPlate)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Translucent, because the floor circle burns directly behind this bar and
    /// a solid plate would put the glow out.
    private var deckPlate: some View {
        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .fill(Theme.ink.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.goldDim.opacity(0.45), lineWidth: 0.5)
            )
    }

    /// A control is a rounded rectangle of `surfaceRaised` with a hairline in
    /// its own tint, everywhere in this app. This one was a bare gold caption
    /// with a 13-point tap target that stayed lit when it could not be paid.
    private func buyButton(price: Int, affordable: Bool) -> some View {
        Button {
            store.buyScroll(selectedBanner.scroll)
        } label: {
            Label("Buy — \(price)", systemImage: "sparkles")
                .font(Theme.body(12).weight(.semibold))
                .foregroundStyle(affordable ? Theme.gold : Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: Theme.controlHeight)
                .background(ScreenChrome.controlShape.fill(Theme.surfaceRaised.opacity(0.9)))
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

    /// The only thing on screen that says why a plate is grey. At zero *both*
    /// plates are grey, so "×10 needs 10 more" would read as though ×1 still
    /// worked; and the unknown scroll has no divinity price, so it has no Buy
    /// control beside this line to answer. With ten or more in hand there is
    /// nothing to explain and the line says nothing.
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
        AudioLibrary.shared.play(.summonCharge)
        Juice.haptic(.medium)
        withAnimation(.easeIn(duration: 0.2)) { isCharging = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isCharging = false
            revealResults = results
        }
    }
}

// MARK: - The little ?

/// The circled question mark itself, in one place so the three of them are the
/// same object. It is drawn at 14 points inside a 26-point tap area: the glyph
/// has to be small enough to read as an aside rather than as a control, and the
/// target has to be big enough to hit with a thumb over a moving painting.
///
/// It is the OUTLINE `questionmark.circle`, not the filled one, because the
/// filled one is already the Unknown Scroll's own glyph (`ScrollType.glyph`)
/// and appears on that scroll's menu row, in the strip, and on both summon
/// plates whenever it is the scroll in hand.
private struct InfoGlyph: View {
    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(Theme.goldDim)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
    }
}

/// A little ? that opens one short answer beside the thing it explains.
///
/// This is what the owner asked for in place of the slabs — "with little ? to
/// view other details" — and it is a popover rather than a sheet on purpose:
/// `.presentationCompactAdaptation(.popover)` keeps it a popover on a phone,
/// so the answer appears next to the question with the room still behind it,
/// where a sheet would cover the room to answer a question about it.
private struct InfoDot<Detail: View>: View {
    let title: String
    @ViewBuilder var detail: () -> Detail
    @State private var isOpen = false

    var body: some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            isOpen = true
        } label: {
            InfoGlyph()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(Theme.body(10).weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(Theme.goldDim)
                detail()
            }
            .padding(14)
            .frame(width: 272)
            .background(Theme.surface)
            .presentationCompactAdaptation(.popover)
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
    /// letterbox under the menu instead of leaving it beside the art.
    var leadingInset: CGFloat = 0

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
            let scale = min(frame.size.width / 16.0, frame.size.height / 9.0)
            let artWidth = scale * 16
            let artHeight = scale * 9
            let originX = leadingInset + (frame.size.width - leadingInset - artWidth) / 2
            let originY = (frame.size.height - artHeight) / 2
            let centre = CGPoint(
                x: originX + Self.floorCentre.x * artWidth,
                y: originY + Self.floorCentre.y * artHeight
            )
            let ringSize = Self.floorRadius * 2 * artWidth

            ZStack {
                Theme.ink
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

                // The scroll's mark, hanging over the ring where the unit will
                // step out of it.
                Image(systemName: banner.scroll.glyph)
                    .font(.system(size: charging ? 44 : 34, weight: .black))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.9), radius: charging ? 24 : 12)
                    .scaleEffect(pulse)
                    .position(x: centre.x, y: centre.y - ringSize * 0.42)

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
                pulse = 1.12
            }
        }
        .animation(.easeOut(duration: 0.35), value: charging)
    }

    /// Something for the overlaid controls to sit on. The temple is a sunlit
    /// painting and 22-point white lettering on lit marble is unreadable, so
    /// the top of the room is washed down for the banner's name and the foot
    /// of it for the summon plates. The bottom wash is the lighter of the two
    /// because the floor circle burns inside it.
    private var scrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Theme.ink.opacity(0.8), Theme.ink.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 92)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 92)
        }
        .allowsHitTesting(false)
    }

    /// The hall itself: a Greek temple with the light falling through the
    /// oculus onto the altar, which is what the owner asked for — "can the
    /// summoning room be like a Greek temple, like the temple of Hephaestus or
    /// the temple of Poseidon". The floor carries a meander band and a laurel
    /// ring with bare marble in the middle, deliberately not a star or a
    /// pentagram.
    private func hall(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if BundleImage.exists("summon_hall_bg") {
                BundleImage(name: "summon_hall_bg")
                    .aspectRatio(contentMode: .fill)
            } else if BundleImage.exists(banner.artName) {
                BundleImage(name: banner.artName)
                    .aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(0.35))
            } else {
                RadialGradient(
                    colors: [tint.opacity(0.30), Theme.ink],
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
    /// 2.2:1, so fitting it leaves ink beside it. A hard vertical seam between
    /// painted marble and flat ink is exactly the boxed-picture look this pass
    /// exists to kill, so the art is feathered into the ink over 44 points at
    /// its sides and 30 at its top and bottom, and the seam disappears whether
    /// the letterbox is 20 points wide or the art runs off the screen.
    private var edgeFade: some View {
        ZStack {
            HStack(spacing: 0) {
                LinearGradient(colors: [Theme.ink, Theme.ink.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 44)
                Spacer(minLength: 0)
                LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 44)
            }
            VStack(spacing: 0) {
                LinearGradient(colors: [Theme.ink.opacity(0.55), Theme.ink.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 30)
                Spacer(minLength: 0)
                LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 30)
            }
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
