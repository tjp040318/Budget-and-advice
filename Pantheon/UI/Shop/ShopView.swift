import SwiftUI

/// The bazaar: scrolls, energy, relic packs, essences and the laurel
/// exchange, paid for in the game's own currencies, a free offering once a
/// day, and the Night Market's rolled shelf. Opens from the wallet on the
/// island, from More, and from the Arena on its Laurel stall.
///
/// And, first on its rail since 2026-09-23, the TREASURY: the one stall that
/// sells for real money (`TreasuryStall`, Docs/STORE.md) — divinity, the
/// starter and the Blessing of the Gods through the App Store. It is not a
/// `ShopService.Section`, because nothing it sells is a `ShopService.Item`:
/// its products and their rules are `StoreCatalog`'s, and a section would
/// have put an empty stall into every switch over the bazaar's sections.
///
/// A PLACE since phase B (2026-09-22; PLAN.md, *Phase B of the premium
/// pass*, option B). Run 211 photographed it as a 360-point cream plate alone
/// in a cream void, SF glyphs where 48 painted items ship, "+2,0…" on a tile
/// and every stall hidden in one "Stall ▾" dropdown. It is the Forum at
/// Midnight now — a forum was Rome's market, and `forum_rome_bg` is the one
/// painting in the bundle that is one — full-bleed under dark glass, the
/// genre's shop (Epic Seven's Secret Shop is a painted room with its goods on
/// dark glass): the stalls a glass rail down the left, the summon screen's
/// shape, so the two read as one game; the stall's name carved over the
/// painting; the Daily Offering floating as the painted gift over a glass
/// deck; every other stall a shelf of glass ware tiles in fixed columns.
///
/// A bespoke day agora (`bazaar_bg`, option C) is the better result and is
/// NOT made: about 9 Meshy credits on the owner's word. The screen prefers it
/// the moment the file ships, with no code change.
struct ShopView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    /// Which stall the screen opens on. The island's wallet and More want the
    /// daily offering, the Arena the Laurel exchange, the CI tour the Night
    /// Market.
    var opening: ShopService.Section = .daily

    @State private var section: ShopService.Section
    /// True while the Treasury is the stall in view; `section` keeps the
    /// game-currency stall the rail returns to.
    @State private var inTreasury: Bool
    /// What the last purchase or claim paid, as tiles; empty when nothing is
    /// shown. `receiptID` lets a later receipt outlive an earlier one's timer.
    @State private var receipt: [ShopService.Grant] = []
    @State private var receiptID = UUID()
    /// Whether a stall stands below the rail's fold, read off the last
    /// stall's place in the rail's scroll (`stallFold`).
    @State private var stallsBelow = false

    /// `treasury: true` opens on the Treasury (the CI tour's `treasury`
    /// step); every other door opens on `opening`.
    init(opening: ShopService.Section = .daily, treasury: Bool = false) {
        self.opening = opening
        _section = State(initialValue: opening)
        _inTreasury = State(initialValue: treasury)
    }

    /// The Treasury's row on the rail, for `ScrollViewReader`.
    private static let treasuryRowID = "treasury"

    // MARK: - The room's measures

    /// The stall rail. 200 and not the proposal's 188: at 188 "Market" had
    /// 44 points beside the Night Market's clock bead and would have broken
    /// mid-word (measured with the bundled Cinzel, 2026-09-22).
    private static let railWidth: CGFloat = 200
    /// The carved stall name. 22 rather than the summon room's 30: the
    /// header, two rows of ware tiles and the foot fade have to fit the
    /// 329 points an iPhone 16 Pro gives a sheet's content in landscape.
    private static let titleSize: CGFloat = 22

    private static let forumPainting = "forum_rome_bg"
    private static let bespokePainting = "bazaar_bg"

    /// The Forum, or a bazaar of its own once one ships.
    private var backdropName: String {
        BundleImage.exists(Self.bespokePainting) ? Self.bespokePainting : Self.forumPainting
    }

    /// The Forum cropped high enough to keep the arch and the temple roofs:
    /// on this content box (750 × 329, a 2.28:1 band of a square painting)
    /// the proposal's y 0.36 cut the arch's attic off, and 0.26 frames the
    /// arch, the pediments and the braziers with the paving below. A bespoke
    /// painting is composed for the band and takes the centre.
    private var backdropFocus: UnitPoint {
        backdropName == Self.forumPainting ? UnitPoint(x: 0.5, y: 0.26) : .center
    }

    /// The Night Market is the same Forum at a deeper hour, and the day
    /// stalls the same Forum at lamp-lighting: two hours of one place. Run
    /// 216 measured the old 0.28 night wash at about five levels of the
    /// painted band's mean colour — under the header's scrims it did not
    /// read — and the day stalls sat in the same midnight. Now the night is
    /// a deep blue wash at 0.45 with a pale moon rising at the top right and
    /// cool motes; the day a warm soft-light wash (0.4 of #FFB866) with the
    /// braziers' sparks and a lamp's pool of light behind the Daily gift
    /// (`lampColour`). Run 220 still read the day stalls as the same midnight
    /// as the Night Market at 0.28 with no lamp: the gift was claimed under a
    /// grey-blue Forum. The bespoke agora (option C) replaces all of it.
    private static let nightWash = Color(hex: "#0A1430").opacity(0.45)
    private static let dayLight = Color(hex: "#FFB866").opacity(0.4)
    private static let moonLight = Color(hex: "#DDE8FF")
    private static let sparkColour = Color(hex: "#FFB866")
    private static let nightMoteColour = Color(hex: "#9FC3FF")
    /// The lamp the Daily gift stands in: warmer and deeper than the gift's
    /// own gold halo, so the pool reads as lamplight on stone rather than as
    /// the gift glowing.
    private static let lampColour = Color(hex: "#FFB35C")

    private var isNight: Bool { !inTreasury && section == .nightMarket }

    /// The stalls as the rail lists them: Testing last, so the rows a player
    /// spends in come first. `ShopService.Section`'s own order is untouched.
    private static let railOrder: [ShopService.Section] = [
        .daily, .nightMarket, .scrolls, .energy, .relics, .essences, .laurels, .testing,
    ]

    private var offers: [ShopService.Item] { Self.shelfOrder(ShopService.items(in: section)) }

    /// The Scrolls stall as its shelf lists it: the premium first, as the
    /// genre's shop does — the Light & Dark scroll was seventh of ten, below
    /// the fold with nothing to say it was there (run 216) — then the Divine,
    /// the three elements, the Pantheon, and the everyday Mystical and
    /// Unknown with their tens. `ShopService`'s own order is untouched; a
    /// ware not named here keeps its place after these.
    private static let scrollShelf = [
        "scroll_light_dark", "scroll_divine", "scroll_fire", "scroll_water", "scroll_wind",
        "scroll_pantheonic", "scroll_mystical", "scroll_mystical_10", "scroll_unknown", "scroll_unknown_10",
    ]

    private static func shelfOrder(_ items: [ShopService.Item]) -> [ShopService.Item] {
        let unranked = scrollShelf.count
        return items.enumerated()
            .sorted { lhs, rhs in
                let left = scrollShelf.firstIndex(of: lhs.element.id) ?? unranked
                let right = scrollShelf.firstIndex(of: rhs.element.id) ?? unranked
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// A stall with more wares than one screen of the shelf shows says how
    /// many it has on its rail row ("10" on Scrolls), so the chevron at the
    /// shelf's foot is never the only cue that more is there.
    private static func wareCount(_ stall: ShopService.Section) -> String? {
        let count = ShopService.items(in: stall).count
        return count > 6 ? "\(count)" : nil
    }

    // MARK: - The screen

    var body: some View {
        NavigationStack {
            GameScreen("Bazaar", dismiss: { dismiss() }) {
                BarWallet(
                    wallet: store.player.wallet,
                    shows: [.energy, .divinity, .drachma, .laurels]
                )
            } content: {
                ZStack(alignment: .topLeading) {
                    PlaceBackdrop(
                        painting: backdropName,
                        focus: backdropFocus,
                        wash: isNight ? Self.nightWash : Color.clear
                    )
                    .animation(.easeInOut(duration: 0.35), value: section)
                    hourLight
                        .animation(.easeInOut(duration: 0.35), value: section)
                    // Brazier sparks by day — the Forum's three braziers are
                    // the only light in it — and cool motes under the moon.
                    // Seed 931, since 930 is the Arena's.
                    PlaceAmbience(shafts: [], motes: 18,
                                  moteColor: isNight ? Self.nightMoteColour : Self.sparkColour, seed: 931)
                    HStack(spacing: 0) {
                        stallRail
                        room
                    }
                }
            }
        }
    }

    /// The hour's light over the painting and under the air: a warm
    /// soft-light wash for the day stalls, a pale moon glow at the top right
    /// for the Night Market (its blue wash is `PlaceBackdrop`'s). Full-bleed
    /// with the backdrop, and never takes a tap.
    @ViewBuilder
    private var hourLight: some View {
        if isNight {
            RadialGradient(
                colors: [Self.moonLight.opacity(0.34), Self.moonLight.opacity(0.10), Self.moonLight.opacity(0)],
                center: UnitPoint(x: 0.86, y: 0.0),
                startRadius: 0,
                endRadius: 320
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
            .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            .transition(.opacity)
        } else {
            Self.dayLight
                .blendMode(.softLight)
                .allowsHitTesting(false)
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
                .transition(.opacity)
        }
    }

    // MARK: - The stall rail

    /// Every stall, down the left of the Forum. The genre shows its shop's
    /// parts as a set the player sees (Summoners War's six, AFK Journey's
    /// hub of stores); the dropdown hid seven of eight and the Daily stall's
    /// free gift with them. It opens scrolled to the stall the screen opened
    /// on, so the Arena's Laurel exchange is never under the fade.
    ///
    /// Its rows rest WHOLE, as the shelf beside them does: run 234 ended the
    /// rail on "Essences" faded in the rail's foot, 77% of the row in view on
    /// an iPhone 16 Pro, so a row shows only from 85% in view and is whole
    /// from 98%, the rail's name ("STALLS") only whole, and while a stall
    /// stands below the fold the glass's chevron says the rail goes on.
    private var stallRail: some View {
        let stalls = Self.railOrder.filter { ShopService.visibleSections.contains($0) }
        return ScrollViewReader { proxy in
            PlaceRail(width: Self.railWidth) {
                PlaceRailLabel("Stalls")
                    .restingRow(goneBelow: 0.9, wholeFrom: 0.995)
                treasuryRow
                    .restingRow(goneBelow: 0.85, wholeFrom: 0.98)
                    .id(Self.treasuryRowID)
                ForEach(stalls) { stall in
                    railRow(stall)
                        .restingRow(goneBelow: 0.85, wholeFrom: 0.98)
                        .background {
                            if stall == stalls.last {
                                stallFold
                            }
                        }
                        .id(stall)
                }
            }
            // Over the rail's fade, not under its mask.
            .overlay(alignment: .bottom) {
                if stallsBelow {
                    RestingChevron(onGlass: true)
                        .padding(.bottom, 6)
                }
            }
            .onAppear {
                if inTreasury {
                    proxy.scrollTo(Self.treasuryRowID, anchor: .center)
                } else {
                    proxy.scrollTo(section, anchor: .center)
                }
            }
        }
    }

    /// The Treasury's row, first under the rail's name: the painted crystal,
    /// and the gold dot while a Blessing day waits to be claimed.
    private var treasuryRow: some View {
        PlaceRailRow(
            title: "Treasury",
            itemKey: "divinity",
            systemImage: "sparkles",
            isOn: inTreasury,
            accessory: nil,
            dot: store.treasuryHasClaim
        ) {
            withAnimation(.easeOut(duration: 0.2)) { inTreasury = true }
            receipt = []
        }
    }

    /// Reads, behind the last stall, whether it stands below the rail's
    /// fold: its foot past the rail's scroll.
    private var stallFold: some View {
        GeometryReader { box in
            let viewport: CGFloat = box.bounds(of: .scrollView)?.height ?? 0
            let below: Bool = viewport > 0 && box.frame(in: .scrollView).maxY > viewport + 1
            Color.clear
                .onAppear { stallsBelow = below }
                .onChange(of: below) { _, now in stallsBelow = now }
        }
        .allowsHitTesting(false)
    }

    /// The Night Market's row carries its clock, ticking; only that row is
    /// in a `TimelineView`, so the rail is not laid out again every second.
    @ViewBuilder
    private func railRow(_ stall: ShopService.Section) -> some View {
        if stall == .nightMarket, let refresh = store.nightMarketRefreshesAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                stallRow(stall, accessory: NightMarketBoard.countdown(to: refresh, now: context.date))
            }
        } else {
            stallRow(stall, accessory: Self.wareCount(stall))
        }
    }

    private func stallRow(_ stall: ShopService.Section, accessory: String?) -> some View {
        PlaceRailRow(
            title: Self.railTitle(stall),
            itemKey: Self.railArt(stall),
            systemImage: Self.railGlyph(stall),
            isOn: !inTreasury && stall == section,
            accessory: accessory,
            dot: stall == .daily && ShopService.isDailyAvailable(player: store.player)
        ) {
            withAnimation(.easeOut(duration: 0.2)) {
                section = stall
                inTreasury = false
            }
            receipt = []
        }
    }

    private static func railTitle(_ stall: ShopService.Section) -> String {
        switch stall {
        case .daily: return "Daily"
        case .nightMarket: return "Night Market"
        case .testing: return "Testing"
        case .scrolls: return "Scrolls"
        case .energy: return "Energy"
        case .relics: return "Relics"
        case .essences: return "Essences"
        case .laurels: return "Laurels"
        }
    }

    /// The painted item each stall's row wears; Testing keeps its glyph.
    private static func railArt(_ stall: ShopService.Section) -> String? {
        switch stall {
        case .daily: return "bundle"
        case .nightMarket: return "chest_gold"
        case .testing: return nil
        case .scrolls: return "scroll_mystical"
        case .energy: return "energy"
        case .relics: return "relic_cache"
        case .essences: return "essence_magic_mid"
        case .laurels: return "laurels"
        }
    }

    /// The glyph a row falls back to while its painting is missing.
    private static func railGlyph(_ stall: ShopService.Section) -> String {
        switch stall {
        case .daily: return "gift.fill"
        case .nightMarket: return "moon.stars.fill"
        case .testing: return "wrench.and.screwdriver.fill"
        case .scrolls: return "scroll.fill"
        case .energy: return "bolt.fill"
        case .relics: return "shield.lefthalf.filled"
        case .essences: return "drop.triangle.fill"
        case .laurels: return "laurel.leading"
        }
    }

    // MARK: - The room

    /// The stall, over the painting: its carved name and the one reading or
    /// action it has, then its goods. The receipt rises over the goods.
    private var room: some View {
        VStack(alignment: .leading, spacing: 6) {
            roomHeader
            stallBody
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            receiptOverlay
        }
    }

    private var roomHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            if inTreasury {
                TreasuryTitle(size: Self.titleSize)
            } else if section == .nightMarket {
                NightMarketTitle(size: Self.titleSize)
            } else {
                PlaceTitle(eyebrow: Self.eyebrow(section), title: Self.headline(section), size: Self.titleSize)
            }
            Spacer(minLength: 8)
            if inTreasury {
                TreasuryHeaderControls()
            } else {
                headerAccessory
            }
        }
    }

    /// What the stall is sold for, or how it runs — the line the strip's
    /// subtitle used to carry, which truncated there.
    private static func eyebrow(_ stall: ShopService.Section) -> String {
        switch stall {
        case .daily: return "Free · once a day"
        case .nightMarket: return "Rolled on the hour"
        case .testing: return "Free while testing"
        case .scrolls: return "Divinity and drachma"
        case .energy: return "For divinity"
        case .relics: return "Drachma and divinity"
        case .essences: return "Awakening materials"
        case .laurels: return "Won in the arena"
        }
    }

    private static func headline(_ stall: ShopService.Section) -> String {
        switch stall {
        case .daily: return "Daily Offering"
        case .nightMarket: return "Night Market"
        case .testing: return "Testing"
        case .scrolls: return "Scrolls"
        case .energy: return "Energy"
        case .relics: return "Relics"
        case .essences: return "Essences"
        case .laurels: return "Laurel Exchange"
        }
    }

    /// The Daily stall's clock to midnight; the Night Market's re-roll with
    /// its price (its clock is the title's eyebrow). Nothing on the rest.
    @ViewBuilder
    private var headerAccessory: some View {
        switch section {
        case .daily:
            resetClock
        case .nightMarket:
            NightMarketReroll()
        case .testing, .scrolls, .energy, .relics, .essences, .laurels:
            EmptyView()
        }
    }

    private var resetClock: some View {
        GlassCapsule {
            Image(systemName: "clock.fill")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Theme.onGlassGold)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Resets in \(Self.untilMidnight(from: context.date))")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// "07:42:10" to the next local midnight, when the offering returns.
    private static func untilMidnight(from now: Date) -> String {
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let seconds = max(0, Int(midnight.timeIntervalSince(now)))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    @ViewBuilder
    private var stallBody: some View {
        if inTreasury {
            TreasuryStall { grants in showReceipt(grants) }
        } else {
            sectionBody
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch section {
        case .daily:
            if let offering = offers.first {
                dailyOffering(offering)
            } else {
                Spacer(minLength: 0)
            }
        case .nightMarket:
            NightMarketBoard { grants in showReceipt(grants) }
        case .testing, .scrolls, .energy, .relics, .essences, .laurels:
            BazaarShelf(wares: offers) { item in
                tile(item)
            }
        }
    }

    // MARK: - The daily offering

    /// The one gift of the day, floating over the Forum as the painted gift
    /// box — run 211 drew it as an SF gift in a cream circle — with what it
    /// holds on a glass deck under it and the claim beside them. The sentence
    /// that repeated the three tiles is gone; the tiles say it.
    private func dailyOffering(_ item: ShopService.Item) -> some View {
        let available = ShopService.isDailyAvailable(player: store.player)
        // 124 + the deck (a two-line tile title makes it 109) + the gaps is
        // 251 of the 264 points under the header on an iPhone 16 Pro.
        return VStack(spacing: 6) {
            Spacer(minLength: 0)
            offeringArt(lit: available)
            Spacer(minLength: 0)
            offeringDeck(item, available: available)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The gift breathing in its own light while it waits; still and dimmed
    /// once taken. Driven by the clock rather than a repeating animation, so
    /// it breathes again every time the stall is reopened.
    ///
    /// Behind it, a lamp: a wide, low pool of warm light on the Forum's stone
    /// (an ellipse 480 × 290 at its fade, screened), so the day stall is lit
    /// like a stall at lamp-lighting and the Night Market's blue beside it
    /// reads as another hour. It stays, fainter, once the gift is taken — the
    /// hour does not change because the gift did. By the carved title above
    /// it the pool is a tenth of its strength, and its fade ends short of the
    /// stall rail on the left.
    private func offeringArt(lit: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = 1 + 0.03 * sin(t * 2 * .pi / 3.4)
            ZStack {
                RadialGradient(
                    colors: [
                        Self.lampColour.opacity(lit ? 0.55 : 0.34),
                        Self.lampColour.opacity(lit ? 0.22 : 0.14),
                        Self.lampColour.opacity(0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 170
                )
                .frame(width: 340, height: 340)
                .scaleEffect(x: 1.4, y: 0.85)
                .blendMode(.screen)
                RadialGradient(
                    colors: [Color(hex: "#FFD678").opacity(lit ? 0.5 : 0.16), Color(hex: "#FFD678").opacity(0)],
                    center: .center,
                    startRadius: 4,
                    endRadius: 100
                )
                .frame(width: 200, height: 200)
                .blendMode(.screen)
                // 86 points is the painting's own 256 pixels on a 3x
                // phone: at 100 it was upscaled and read soft (run 216).
                ItemIcon(key: "bundle", size: 86, glow: false)
                    .shadow(color: Theme.gold.opacity(lit ? 0.55 : 0.18), radius: 14)
                    .saturation(lit ? 1 : 0.55)
                    .scaleEffect(lit ? breath : 1)
            }
        }
        .frame(height: 124)
        .allowsHitTesting(false)
    }

    private func offeringDeck(_ item: ShopService.Item, available: Bool) -> some View {
        HStack(spacing: 12) {
            // Top-aligned in their own row, so a tile whose name wraps
            // ("Mystical / Scroll") does not ride higher than its
            // neighbours; the deck itself stays centred on the claim.
            HStack(alignment: .top, spacing: 12) {
                // Offsets, not the grants: two identical grants in one
                // bundle would collide on `id: \.self`.
                ForEach(Array(grantParts(item.grant).enumerated()), id: \.offset) { _, part in
                    RewardTile(grant: part, size: 56, showsTitle: true, onGlass: true)
                }
            }
            Spacer(minLength: 16)
            if available {
                // The bazaar's one gold: the shelves' BUY plate and the
                // Missions' claim, at a primary action's height, with the
                // gift on it (run 216: the painted copper slice beside the
                // drawn gold everywhere else in the group).
                BazaarClaimButton(title: "Claim", itemKey: "bundle") { buy(item, chime: false) }
                    .frame(width: 190)
            } else {
                GlassCapsule(height: 34) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Theme.onGlassSuccess)
                    Text("Claimed · back at midnight")
                        .font(Theme.body(12).weight(.semibold))
                        .foregroundStyle(Theme.onGlass)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .background(GlassPlate(radius: 14))
    }

    // MARK: - The shelf

    /// One offer as a glass ware tile: its painting (an awakening cache or a
    /// scroll by its own id where one is painted), what kind of thing it is
    /// over its name, the words behind the ?, and the price plate.
    private func tile(_ item: ShopService.Item) -> some View {
        BazaarWareTile(
            artKey: ItemArt.hasPainting(item.id) ? item.id : ItemArt.key(for: item.grant),
            amount: BazaarWareTile.cornerAmount(for: item.grant),
            stars: ItemArt.stars(for: item.grant),
            portraitName: nil,
            kind: Self.kind(for: item),
            name: item.title,
            shelfName: BazaarWareTile.shelfName(item.title, grant: item.grant),
            detail: item.subtitle,
            price: item.price,
            status: status(for: item)
        ) {
            buy(item, chime: true)
        }
    }

    /// A bundle is named by what it is for, not by the word "bundle".
    private static func kind(for item: ShopService.Item) -> String {
        if case .bundle = item.grant {
            if item.section == .testing { return "Free pack" }
            if item.id.hasPrefix("awakening_cache_") { return "Cache" }
            return "Bundle"
        }
        return BazaarWareTile.kind(for: item.grant)
    }

    private func status(for item: ShopService.Item) -> BazaarWareStatus {
        if item.price.currency == .free { return .free }
        return ShopService.canAfford(item.price, wallet: store.player.wallet) ? .buy : .short
    }

    // MARK: - Doing things

    /// A bundle spelled out one grant to a tile; anything else is one tile.
    private func grantParts(_ grant: ShopService.Grant) -> [ShopService.Grant] {
        if case .bundle(let parts) = grant { return parts }
        return [grant]
    }

    /// `chime` is false for the daily's claim, whose `BazaarClaimButton` has
    /// already played the confirm.
    private func buy(_ item: ShopService.Item, chime: Bool) {
        guard let grants = store.buy(item) else { return }
        if chime { AudioLibrary.shared.play(.uiConfirm) }
        Juice.haptic(.light)
        showReceipt(grants)
    }

    @ViewBuilder
    private var receiptOverlay: some View {
        if !receipt.isEmpty {
            GrantReceipt(title: "Received", grants: receipt, onGlass: true)
                .padding(.bottom, 10)
        }
    }

    /// What a purchase paid, as the genre's strip of tiles for 2.8 seconds —
    /// it was a sentence in a capsule ("Received Mystical Scroll ×1, Drachma
    /// +2000, …"), which a bundle of eighteen essences ran off the screen.
    private func showReceipt(_ grants: [ShopService.Grant]) {
        let id = UUID()
        withAnimation(.easeOut(duration: 0.2)) {
            receipt = grants
            receiptID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard receiptID == id else { return }
            withAnimation(.easeIn(duration: 0.25)) { receipt = [] }
        }
    }
}

// MARK: - The bazaar's parts, shared with the Night Market

/// Where a ware stands for this player: payable, not yet payable, free, or
/// already taken tonight (a Night Market slot stays on its shelf, crossed
/// out).
enum BazaarWareStatus {
    case buy, short, free, taken
}

/// The measures every bazaar shelf shares, kept out of the generic
/// `BazaarShelf` because a generic type cannot hold a stored static.
enum BazaarLayout {
    static let spacing: CGFloat = 10

    /// Three fixed columns, never adaptive: the Night Market's first shelf is
    /// six wares, and run 151's adaptive grid drew five and orphaned the
    /// sixth (frame 32 of run 211 again). Two on a room narrower than 470
    /// points (an SE-class phone), where three would cut the names.
    static func columns(for width: CGFloat) -> [GridItem] {
        let count = width >= 470 ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}

/// A shelf of ware tiles over the painting: fixed columns chosen by the
/// width it is given (a `GeometryReader`, never `ViewThatFits`), scrolling.
/// The day stalls and the Night Market are this one shelf.
///
/// It rests on WHOLE rows (`RestingList`, with the glass's chevron), as
/// Missions, the Lessons and the decor catalogue have since round 4. Run
/// 234's Scrolls stall ended on the peek run 216 asked for — a faded third
/// row of "SCROLL SCROLL SCROLL", the ? dots and the tops of three sockets,
/// no names — the one list in the game still ending on part of a row. A
/// tile shows only from 85% in view and is whole from 98%: its name and its
/// price plate stand at its foot, and the third row is 27% in view at rest
/// on an iPhone 16 Pro, over half on a Pro Max. The chevron says the stall
/// goes on; a full 3 × 2 Night Market fits and shows none.
struct BazaarShelf<Ware: Identifiable, Tile: View>: View {
    let wares: [Ware]
    @ViewBuilder let tile: (Ware) -> Tile

    var body: some View {
        GeometryReader { frame in
            RestingList(onGlass: true) {
                LazyVGrid(columns: BazaarLayout.columns(for: frame.size.width), spacing: BazaarLayout.spacing) {
                    ForEach(wares) { ware in
                        tile(ware)
                            .restingRow(goneBelow: 0.85, wholeFrom: 0.98)
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, RowRest.footFade)
            }
        }
    }
}

/// One ware on glass, Epic Seven's Secret Shop hierarchy: the painted thing
/// in a dark socket (or a unit's face), a gold kind line over the name, and
/// the price plate across the foot. The long description is behind the ?
/// in the corner — run 211's tiles cut it to "Replaces one sub stat with a
/// stat of your cho…".
///
/// Every tile is `height` tall, so a row never staggers: a 12-point name on
/// up to two lines, the 46-point art with its stars, the 32-point plate. Two
/// rows and the header fit the 329 points an iPhone 16 Pro gives the sheet's
/// content (run 216: 120-point tiles filled the box to its foot); a third
/// row is drawn only whole, and the shelf's chevron says a stall has more
/// (`BazaarShelf`, run 234).
///
/// The tile prints its `shelfName` — the name without what the socket
/// already says (the count, the grade) — and the whole `name` is the
/// popover's title behind the ?.
struct BazaarWareTile: View {
    let artKey: String
    let amount: String?
    let stars: Int?
    let portraitName: String?
    let kind: String
    let name: String
    let shelfName: String
    let detail: String
    let price: ShopService.Price
    let status: BazaarWareStatus
    let action: () -> Void

    static let height: CGFloat = 106
    private static let artSize: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                art
                VStack(alignment: .leading, spacing: 2) {
                    // The kinds are written short (STONE, CACHE, a unit's
                    // element) so the line never reaches the ? in the corner.
                    Text(kind.uppercased())
                        .font(Theme.body(11).weight(.heavy))
                        .tracking(1.0)
                        .foregroundStyle(Theme.onGlassEyebrow)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.trailing, 16)
                    // Two lines hold every shelf name at the 97 points
                    // the column has (measured in Manrope, 2026-09-23).
                    Text(Self.nameLine(shelfName, kind: kind, price: price))
                        .font(Theme.body(12).weight(.semibold))
                        .foregroundStyle(Theme.onGlass)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 3)
            BazaarPriceButton(price: price, status: status, action: action)
        }
        .padding(8)
        .frame(height: Self.height)
        .background(GlassPlate(radius: 12))
        .overlay(alignment: .topTrailing) {
            InfoDot(title: name) {
                Text(detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(1)
        }
        .opacity(status == .taken ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    /// A unit shows its face — a ware is only worth a look because the player
    /// can see whose face is on the shelf. Everything else is the game's one
    /// reward tile, on its dark glass socket.
    ///
    /// The face is `PortraitPainting`'s, never a bare fill of the card: a
    /// family whose cards are whole figures stood horns to hooves in the
    /// 46-point socket with a face of eight pixels (run 221's Minotaur), and
    /// the painting draws such a card as the bust every other card is.
    @ViewBuilder
    private var art: some View {
        if let portraitName, BundleImage.exists(portraitName) {
            VStack(spacing: 2) {
                PortraitPainting(name: portraitName, size: Self.artSize)
                    .frame(width: Self.artSize, height: Self.artSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .rarityFrame(Rarity(stars: stars ?? 3), radius: 8, painted: false)
                StarRow(stars: stars ?? 3, size: 6)
            }
        } else {
            RewardTile(key: artKey, amount: amount, stars: stars, size: Self.artSize, showsTitle: false, onGlass: true)
        }
    }

    /// The gold line over a ware's name: what kind of thing it is. A unit is
    /// "Tide unit" — its element alone read as a Tide essence (run 216).
    static func kind(for grant: ShopService.Grant) -> String {
        switch grant {
        case .scrolls: return "Scroll"
        case .energy, .energyRefill: return "Energy"
        case .drachma: return "Drachma"
        case .divinity: return "Divinity"
        case .relic: return "Relic"
        case .essences: return "Essence"
        case .stones: return "Stone"
        case .boonCache: return "Boon"
        case .unit(let id):
            guard let element = UnitDatabase.blueprint(id)?.element else { return "Unit" }
            return element.displayName + " unit"
        case .bundle: return "Bundle"
        }
    }

    /// A ware's name on the shelf, without what the socket already prints:
    /// "Energy ×50" beside a "+50" socket is "Energy", "Champion's Relic, 6★"
    /// over six stars is "Champion's Relic", the Night Market's "3★ relic"
    /// is "Relic", and "The stonecutter's crate" loses its article so it
    /// fits two lines. The whole title stays behind the ?. A name that comes
    /// out as its own kind is `nameLine`'s to replace.
    static func shelfName(_ title: String, grant: ShopService.Grant) -> String {
        var name = title
        if cornerAmount(for: grant) != nil, let cut = name.range(of: " ×", options: .backwards) {
            let tail = name[cut.upperBound...]
            if !tail.isEmpty, tail.allSatisfy(\.isNumber) { name = String(name[..<cut.lowerBound]) }
        }
        if ItemArt.stars(for: grant) != nil {
            if let cut = name.range(of: ", ", options: .backwards), name.hasSuffix("★") {
                name = String(name[..<cut.lowerBound])
            }
            if let star = name.firstIndex(of: "★"), name[..<star].allSatisfy(\.isNumber) {
                let rest: String = name[name.index(after: star)...].trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { name = capitalisedFirst(rest) }
            }
        }
        if case .bundle = grant, name.hasPrefix("The ") {
            name = capitalisedFirst(String(name.dropFirst(4)))
        }
        return name
    }

    /// The line under the kind, which never says the kind again. Stripped of
    /// what the socket prints, "Energy ×20" is "Energy" and the Night
    /// Market's "3★ relic" is "Relic": run 221's shelf read "ENERGY / Energy"
    /// three times and "RELIC / Relic" once, which is placeholder data. Such
    /// a ware says what sets it apart instead, from its own terms: a relic is
    /// rolled when it is bought, any set and any slot (broken after the comma,
    /// or the column would break it after "any"); energy for drachma is the
    /// Night Market's own trade, since the bazaar sells energy only for
    /// divinity; and the bazaar's own goes over the cap. Anything else that
    /// ever comes out as its kind says what it is paid in.
    static func nameLine(_ shelfName: String, kind: String, price: ShopService.Price) -> String {
        guard shelfName.caseInsensitiveCompare(kind) == .orderedSame else { return shelfName }
        if kind == Self.kind(for: .relic(grade: 3)) {
            return "Any set,\nany slot"
        }
        if kind == Self.kind(for: .energy(1)) {
            return price.currency == .drachma ? "For drachma" : "Over the cap"
        }
        switch price.currency {
        case .free: return "Free"
        case .divinity, .drachma, .laurels: return "For " + price.currency.displayName
        }
    }

    /// "relic" → "Relic": the first letter up, the rest as written.
    private static func capitalisedFirst(_ text: String) -> String {
        let head: String = String(text.prefix(1)).uppercased()
        let tail: String = String(text.dropFirst())
        return head + tail
    }

    /// The count on the socket's corner. None for a relic or a boon cache
    /// (the stars under the socket are its grade — run 211's relic ware said
    /// "3★" three times), a unit or a bundle.
    static func cornerAmount(for grant: ShopService.Grant) -> String? {
        switch grant {
        case .relic, .boonCache, .unit, .bundle:
            return nil
        case .scrolls, .energy, .energyRefill, .drachma, .divinity, .essences, .stones:
            return ItemArt.amount(for: grant)
        }
    }
}

/// A ware's price as one plate across its foot: the painted currency, the
/// amount, and the verb. Gold with a gloss when the wallet covers it; dark
/// glass with the amount in rose and a lock when it does not; gold "Free ·
/// TAKE" for a free pack; "TAKEN" on dark glass for a sold slot. Each look
/// is chosen with a switch, never a ternary between the gold plate (a
/// gradient) and a colour.
struct BazaarPriceButton: View {
    let price: ShopService.Price
    let status: BazaarWareStatus
    let action: () -> Void

    static let height: CGFloat = 32

    private var isLit: Bool {
        switch status {
        case .buy, .free: return true
        case .short, .taken: return false
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            Juice.haptic(.light)
            action()
        } label: {
            HStack(spacing: 5) {
                label
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(plate)
            .overlay(shape.strokeBorder(isLit ? Color(hex: "#FFE9A8").opacity(0.55) : Theme.glassRim.opacity(0.45),
                                        lineWidth: 1))
            .shadow(color: isLit ? Theme.gold.opacity(0.3) : Color.clear, radius: 5, y: 2)
            .contentShape(shape)
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(!isLit)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var label: some View {
        switch status {
        case .buy:
            ItemIcon(key: Self.currencyKey(price.currency), size: 20, glow: false)
            amountText(Theme.ink)
            Spacer(minLength: 4)
            verb("BUY", tint: Theme.ink)
        case .short:
            ItemIcon(key: Self.currencyKey(price.currency), size: 20, glow: false)
                .opacity(0.8)
            amountText(Theme.onGlassDanger)
            Spacer(minLength: 4)
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Theme.onGlassDim)
        case .free:
            Image(systemName: "gift.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Theme.ink)
            Text("Free")
                .font(Theme.numeric(13))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            verb("TAKE", tint: Theme.ink)
        case .taken:
            Spacer(minLength: 0)
            verb("TAKEN", tint: Theme.onGlassDim)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var plate: some View {
        switch status {
        case .buy, .free:
            BazaarGoldPlate(radius: 8)
        case .short, .taken:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.38))
        }
    }

    /// The whole amount, grouped: a price is read, not estimated, so the
    /// wallet's compact "45K" is wrong here.
    private func amountText(_ tint: Color) -> some View {
        Text(price.amount.formatted())
            .font(Theme.numeric(13))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    private func verb(_ word: String, tint: Color) -> some View {
        Text(word)
            .font(Theme.title(13))
            .tracking(1.2)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    private var accessibilityText: String {
        switch status {
        case .buy: return "Buy for \(price.amount) \(price.currency.displayName)"
        case .short: return "Costs \(price.amount) \(price.currency.displayName), not enough"
        case .free: return "Take, free"
        case .taken: return "Taken"
        }
    }

    /// The painted currency a price is paid in.
    static func currencyKey(_ currency: ShopService.Currency) -> String {
        switch currency {
        case .divinity: return "divinity"
        case .drachma: return "drachma"
        case .laurels: return "laurels"
        case .free: return "bundle"
        }
    }
}

/// The bazaar's one gold: `Theme.goldPlate` lit from above by a gloss over
/// its top half — the shelves' BUY, the Daily Offering's CLAIM, and the
/// same metal as the Missions' and Events' `ClaimPlate`, so a screen family
/// has one gold, not the painted copper slice beside a drawn gold (run 216).
struct BazaarGoldPlate: View {
    var radius: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(Theme.goldPlate)
            .overlay(
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                                          startPoint: .top, endPoint: .center))
            )
    }
}

/// The Daily Offering's claim: the bazaar's gold plate (`BazaarGoldPlate`,
/// the BUY plates' and the claims' metal) at a primary action's height of
/// 46, the painted gift beside CLAIM in ink. It plays the confirm and
/// the haptic itself, as `ClaimPlate` does.
struct BazaarClaimButton: View {
    let title: String
    var itemKey: String? = nil
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return Button {
            Juice.haptic(.medium)
            AudioLibrary.shared.play(.uiConfirm)
            action()
        } label: {
            HStack(spacing: 8) {
                if let itemKey, ItemArt.hasPainting(itemKey) {
                    ItemIcon(key: itemKey, size: 26, glow: false)
                }
                Text(title.uppercased())
                    .font(Theme.title(15))
                    .tracking(1.6)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: PrimaryButton.height)
            .background(BazaarGoldPlate(radius: Theme.tightCorner))
            .overlay(shape.strokeBorder(Color(hex: "#FFE9A8").opacity(0.55), lineWidth: 1))
            .shadow(color: Theme.gold.opacity(0.35), radius: 8, y: 3)
            .shadow(color: Color.black.opacity(0.45), radius: 4, y: 3)
            .contentShape(shape)
        }
        .buttonStyle(PlateButtonStyle())
        .accessibilityLabel(title)
    }
}
