import SwiftUI

// MARK: - The Treasury: the bazaar's real-money stall (2026-09-23; Docs/STORE.md §5)
//
// The first stall on the bazaar's rail, in the house's glass over the Forum.
// One row of offers — the Blessing of the Gods across two columns and the
// starter in the third — then the six divinity packs in two rows of three,
// then a footnote. Every row is the bazaar's 106-point ware height, so the
// header and two rows rest whole in the 264 points an iPhone 16 Pro gives
// the room, and the rest waits below the glass's chevron as every shelf's
// does (`RestingList`).
//
// The App Store's price is the only price printed. Until it answers — and
// always under `-tour` and in CI, which sign nothing and have no StoreKit
// configuration — every tile shows what it holds with "—" and a dark,
// disabled BUY: never an empty stall, never a spinner that waits for ever.

/// The measures the Treasury's rows share.
enum TreasuryLayout {
    /// A row's height: the bazaar's ware tile's.
    static let rowHeight: CGFloat = BazaarWareTile.height
    /// The Blessing card's column of controls.
    static let actionWidth: CGFloat = 128
    /// The Blessing's medallion.
    static let medallion: CGFloat = 56
}

struct TreasuryStall: View {
    @EnvironmentObject private var store: GameStore
    @ObservedObject private var purchases = PurchaseService.shared
    /// What a purchase or a claim paid, handed to the bazaar's receipt.
    var onReceipt: ([ShopService.Grant]) -> Void

    var body: some View {
        GeometryReader { frame in
            RestingList(onGlass: true) {
                VStack(alignment: .leading, spacing: BazaarLayout.spacing) {
                    offerRow(width: frame.size.width)
                        .restingRow(goneBelow: 0.85, wholeFrom: 0.98)
                    LazyVGrid(columns: BazaarLayout.columns(for: frame.size.width), spacing: BazaarLayout.spacing) {
                        ForEach(StoreCatalog.packs) { offer in
                            packTile(offer)
                                .restingRow(goneBelow: 0.85, wholeFrom: 0.98)
                        }
                    }
                    footnote
                        .restingRow(goneBelow: 0.5, wholeFrom: 0.95)
                }
                .padding(.top, 2)
                .padding(.bottom, RowRest.footFade)
            }
        }
        .overlay(alignment: .bottom) {
            noticeBead
        }
        .task {
            await purchases.prepare()
        }
        .onChange(of: purchases.lastDelivery) { _, delivered in
            if let delivered {
                onReceipt(delivered.grants)
            }
        }
    }

    // MARK: - The first row

    /// The Blessing across every column but the last, the starter in the
    /// last: the two best values in the Treasury, first, as the genre's shop
    /// leads with its packages. On a room too narrow for three columns (an
    /// SE-class phone) the Blessing's card needs the whole width for its
    /// seal, its words and its plates, so the two stand one above the other.
    @ViewBuilder
    private func offerRow(width: CGFloat) -> some View {
        let columns: Int = BazaarLayout.columns(for: width).count
        if columns >= 3 {
            let spacing: CGFloat = BazaarLayout.spacing
            let gaps: CGFloat = spacing * CGFloat(columns - 1)
            let unit: CGFloat = max(0, (width - gaps) / CGFloat(columns))
            let wide: CGFloat = unit * CGFloat(columns - 1) + spacing * CGFloat(columns - 2)
            HStack(alignment: .top, spacing: spacing) {
                blessingCard
                    .frame(width: wide)
                starterCard
                    .frame(width: unit)
            }
        } else {
            VStack(alignment: .leading, spacing: BazaarLayout.spacing) {
                blessingCard
                starterCard
            }
        }
    }

    // MARK: - The Blessing

    private var blessingCard: some View {
        let current = store.blessingStatus
        return HStack(alignment: .center, spacing: 10) {
            BlessingMedallion(daysLeft: current?.daysLeft, days: current?.days ?? StoreCatalog.blessingDays,
                              size: TreasuryLayout.medallion)
            VStack(alignment: .leading, spacing: 3) {
                // The ? beside the eyebrow, not in the card's corner, where
                // it would stand on the claim plate's gold.
                HStack(spacing: 2) {
                    eyebrow("30-day pass")
                    InfoDot(title: StoreCatalog.blessing.name) {
                        Text(Self.blessingDetail)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 20, height: 16)
                }
                Text(StoreCatalog.blessing.name)
                    .font(Theme.body(13).weight(.semibold))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(Self.blessingFirstLine(current))
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.onGlassGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(Self.blessingSecondLine(current))
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                blessingClaim(current)
                TreasuryBuyButton(
                    price: purchases.price(for: StoreCatalog.blessing),
                    state: blessingBuyState,
                    verb: current?.isRunning == true ? "+30 days" : "Buy"
                ) {
                    buy(StoreCatalog.blessing)
                }
            }
            .frame(width: TreasuryLayout.actionWidth)
        }
        .padding(10)
        .frame(height: TreasuryLayout.rowHeight)
        .background(GlassPlate(radius: 12))
    }

    /// The claim above the price: gold while a day waits, a quiet plate once
    /// today's is taken, nothing before the first Blessing.
    @ViewBuilder
    private func blessingClaim(_ current: BlessingStatus?) -> some View {
        if let current, current.waiting > 0 {
            ClaimPlate(status: .ready, title: "Claim \(current.divinityWaiting)", onGlass: true) {
                claimBlessing()
            }
        } else if let current, current.isRunning {
            ClaimPlate(status: .waiting, title: "Tomorrow", onGlass: true) {}
        }
    }

    private var blessingBuyState: TreasuryBuyState {
        store.canExtendBlessing ? buyState(for: StoreCatalog.blessing) : .full
    }

    /// "300 now, 50 a day" before the first; "Day 12 of 30" while it runs;
    /// "Ended" with days waiting.
    static func blessingFirstLine(_ current: BlessingStatus?) -> String {
        guard let current else {
            return "\(StoreCatalog.blessing.divinity) now, \(StoreCatalog.blessingDaily) a day"
        }
        return current.isRunning ? "Day \(current.day) of \(current.days)" : "Ended"
    }

    static func blessingSecondLine(_ current: BlessingStatus?) -> String {
        guard let current else { return "for \(StoreCatalog.blessingDays) days" }
        if current.waiting > 1 { return "\(current.waiting) days waiting" }
        if current.waiting == 1 { return "Today's is waiting" }
        return "Today's is claimed"
    }

    /// Everything the Blessing pays, in all.
    static let blessingTotal: Int = StoreCatalog.blessing.divinity + StoreCatalog.blessingDays * StoreCatalog.blessingDaily

    /// What the card's ? says: the terms before the purchase, as Guideline
    /// 3.1.2(c) asks of anything time-limited.
    static let blessingDetail: String = [
        "\(StoreCatalog.blessing.divinity) divinity at once, then \(StoreCatalog.blessingDaily) every day for \(StoreCatalog.blessingDays) days,",
        "\(blessingTotal) in all.",
        "A day you miss is never lost: it waits for your next claim.",
        "Buying it again while it runs adds \(StoreCatalog.blessingDays) days to its end, up to \(StoreCatalog.blessingMostDaysAhead) waiting.",
        "It never renews by itself.",
    ].joined(separator: " ")

    // MARK: - The starter

    private var starterCard: some View {
        let owned = store.ownsStarter
        return VStack(alignment: .leading, spacing: 3) {
            eyebrow(owned ? "Welcomed" : "Once only")
                .padding(.trailing, 22)
            Text(StoreCatalog.starter.name)
                .font(Theme.body(12).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 7) {
                starterPart(key: "divinity", amount: "\(StoreCatalog.starter.divinity)")
                starterPart(key: ItemArt.key(scroll: .pantheonic), amount: "×5")
                starterPart(key: ItemArt.key(scroll: .divine), amount: "×1")
            }
            Spacer(minLength: 2)
            TreasuryBuyButton(
                price: purchases.price(for: StoreCatalog.starter),
                state: owned ? .owned : buyState(for: StoreCatalog.starter)
            ) {
                buy(StoreCatalog.starter)
            }
        }
        .padding(8)
        .frame(height: TreasuryLayout.rowHeight)
        .background(GlassPlate(radius: 12))
        .overlay(alignment: .topTrailing) {
            InfoDot(title: StoreCatalog.starter.name) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.starterDetail)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach([ScrollType.pantheonic, ScrollType.divine], id: \.self) { scroll in
                        Text("\(scroll.displayName): \(TreasuryOddsSheet.oddsLine(scroll))")
                            .font(Theme.numeric(12))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(1)
        }
        .opacity(owned ? 0.72 : 1)
    }

    private func starterPart(key: String, amount: String) -> some View {
        HStack(spacing: 2) {
            ItemIcon(key: key, size: 18, glow: false)
            Text(amount)
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// Every part of the starter, and the odds its scrolls summon at: the
    /// disclosure Guideline 3.1.1 asks for before anything random is bought.
    static let starterDetail: String = [
        "\(StoreCatalog.starter.divinity) divinity, 5 Pantheon Scrolls, 1 Divine Scroll and 100,000 drachma.",
        "Sold once to each demigod.",
        "The scrolls summon at the published odds:",
    ].joined(separator: " ")

    // MARK: - The packs

    /// A pack: its pile of crystal, its name, what it pays now, and the
    /// "×2" of a first purchase or the bonus of every later one.
    private func packTile(_ offer: StoreOffer) -> some View {
        let first = store.isFirstPurchase(offer)
        let amount = first ? offer.firstPurchaseDivinity : offer.regularDivinity
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                DivinityPile(tier: offer.tier, size: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text(offer.shortName)
                        .font(Theme.body(12).weight(.semibold))
                        .foregroundStyle(Theme.onGlass)
                        .lineLimit(1)
                    Text(amount.formatted())
                        .font(Theme.numeric(17))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(1)
                        .fixedSize()
                    Text(Self.bonusLine(offer, first: first))
                        .font(Theme.body(11).weight(.heavy))
                        .tracking(0.4)
                        .foregroundStyle(first ? Theme.onGlassEyebrow : Theme.onGlassDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 3)
            TreasuryBuyButton(price: purchases.price(for: offer), state: buyState(for: offer)) {
                buy(offer)
            }
        }
        .padding(8)
        .frame(height: TreasuryLayout.rowHeight)
        .background(GlassPlate(radius: 12))
        .overlay(alignment: .topTrailing) {
            if first {
                FirstPurchaseMark()
                    .padding(5)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "FIRST BUY ×2" while the double stands; "+30 BONUS" after; nothing
    /// for a pack with no bonus.
    static func bonusLine(_ offer: StoreOffer, first: Bool) -> String {
        if first { return "FIRST BUY ×2" }
        return offer.bonus > 0 ? "+\(offer.bonus.formatted()) BONUS" : " "
    }

    // MARK: - The foot

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Prices are the App Store's, in your currency. Divinity bought here never expires.")
            if store.account.isGuest {
                Text("Playing as a guest, purchases stay with this demigod's save. Sign in with Apple to keep them on a new phone.")
            }
        }
        .font(Theme.body(11))
        .foregroundStyle(Theme.onGlassDim)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var noticeBead: some View {
        if let notice = purchases.notice {
            GlassCapsule(height: 30) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.onGlassGold)
                Text(notice)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
            }
            .padding(.bottom, 10)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func eyebrow(_ word: String) -> some View {
        Text(word.uppercased())
            .font(Theme.body(11).weight(.heavy))
            .tracking(1.0)
            .foregroundStyle(Theme.onGlassEyebrow)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    // MARK: - Doing things

    /// Where a product's BUY stands: in flight, payable, or not yet (no
    /// price from the App Store, purchases off on the device, another
    /// purchase or a restore in flight).
    private func buyState(for offer: StoreOffer) -> TreasuryBuyState {
        if purchases.purchasing == offer.productID { return .busy }
        let priced = purchases.price(for: offer) != nil
        let idle = purchases.purchasing == nil && !purchases.restoring
        return priced && idle && purchases.paymentsAllowed ? .ready : .unavailable
    }

    private func buy(_ offer: StoreOffer) {
        AudioLibrary.shared.play(.uiConfirm)
        Task {
            await purchases.purchase(offer)
        }
    }

    private func claimBlessing() {
        guard let grants = store.claimBlessing() else { return }
        onReceipt(grants)
    }
}

// MARK: - The header's parts

/// The stall's carved name, its eyebrow saying where the prices stand.
struct TreasuryTitle: View {
    @ObservedObject private var purchases = PurchaseService.shared
    let size: CGFloat

    var body: some View {
        PlaceTitle(eyebrow: Self.eyebrow(purchases.shelf, allowed: purchases.paymentsAllowed), title: "Treasury", size: size)
    }

    static func eyebrow(_ shelf: StoreShelfState, allowed: Bool) -> String {
        switch shelf {
        case .loading: return "Asking the App Store"
        case .unavailable: return "The App Store did not answer"
        case .ready: return allowed ? "Real money · App Store" : "Purchases are off here"
        case .idle, .tour: return "Real money · App Store"
        }
    }
}

/// Odds and Restore, always in the header, where a reviewer and a player
/// both look first; Retry beside them while the App Store has not answered.
struct TreasuryHeaderControls: View {
    @ObservedObject private var purchases = PurchaseService.shared
    @State private var showsOdds = false

    var body: some View {
        HStack(spacing: 6) {
            if purchases.shelf == .unavailable {
                GlassBead(text: "Retry", systemImage: "arrow.clockwise", tint: Theme.onGlassWarning) {
                    purchases.retry()
                }
            }
            GlassBead(text: "Odds", systemImage: "dice.fill") {
                showsOdds = true
            }
            GlassBead(text: purchases.restoring ? "Restoring" : "Restore", systemImage: "arrow.counterclockwise") {
                Task {
                    await purchases.restore()
                }
            }
        }
        .sheet(isPresented: $showsOdds) {
            TreasuryOddsSheet()
        }
    }
}

// MARK: - The buy plate

/// Where a BUY stands.
enum TreasuryBuyState: Equatable {
    /// Priced and payable: gold.
    case ready
    /// Its purchase sheet is up.
    case busy
    /// No price from the App Store yet, purchases off, or another purchase
    /// in flight: dark, "—" where no price came, never pressable.
    case unavailable
    /// The starter, once bought.
    case owned
    /// The Blessing with 180 days waiting.
    case full
}

/// A price as the App Store gives it, and the verb: the bazaar's gold plate
/// (`BazaarGoldPlate`) when it can be bought, dark glass when it cannot.
/// Each look is chosen with a switch, never a ternary between the gold (a
/// gradient) and a colour.
struct TreasuryBuyButton: View {
    let price: String?
    let state: TreasuryBuyState
    var verb: String = "Buy"
    let action: () -> Void

    static let height: CGFloat = 32

    private var isLit: Bool { state == .ready }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
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
        // Gold when it can buy: the primary press, its tick and tap on
        // touch-down (2026-09-24).
        .buttonStyle(GamePressStyle(.primary))
        .disabled(!isLit)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var label: some View {
        switch state {
        case .ready:
            priceText(Theme.ink)
            Spacer(minLength: 4)
            verbText(verb, tint: Theme.ink)
        case .busy:
            Spacer(minLength: 0)
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Theme.ink.opacity(0.8))
            verbText("Buying", tint: Theme.ink.opacity(0.8))
            Spacer(minLength: 0)
        case .unavailable:
            priceText(Theme.onGlassDim)
            Spacer(minLength: 4)
            verbText(verb, tint: Theme.onGlassDim.opacity(0.7))
        case .owned:
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.onGlassSuccess)
            verbText("Owned", tint: Theme.onGlassDim)
            Spacer(minLength: 0)
        case .full:
            Spacer(minLength: 0)
            verbText("Full", tint: Theme.onGlassDim)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var plate: some View {
        switch state {
        case .ready, .busy:
            BazaarGoldPlate(radius: 8)
        case .unavailable, .owned, .full:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.38))
        }
    }

    /// The App Store's price, whole, or "—" before it has answered.
    private func priceText(_ tint: Color) -> some View {
        Text(price ?? "—")
            .font(Theme.numeric(13))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    private func verbText(_ word: String, tint: Color) -> some View {
        Text(word.uppercased())
            .font(Theme.title(13))
            .tracking(1.2)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    private var accessibilityText: String {
        switch state {
        case .ready: return "\(verb) for \(price ?? "")"
        case .busy: return "Buying"
        case .unavailable: return "Not available yet"
        case .owned: return "Owned"
        case .full: return "The most days are already waiting"
        }
    }
}

// MARK: - The art

/// A pack's pile of the painted crystal, growing with its tier: one crystal
/// for the Phial to four for the Coffer, and the gold chest behind the
/// Chest's and the Hoard's. The genre's piles are painted per tier; six
/// paintings are Docs/STORE.md §7's, on the owner's word.
struct DivinityPile: View {
    let tier: Int
    var size: CGFloat = 46

    /// Each crystal's offset (a share of the pile's size) and scale, back to
    /// front.
    private static func crystals(_ tier: Int) -> [(x: CGFloat, y: CGFloat, scale: CGFloat)] {
        switch tier {
        case ...1:
            return [(0, 0, 0.9)]
        case 2:
            return [(-0.16, 0.06, 0.72), (0.16, -0.04, 0.8)]
        case 3:
            return [(-0.2, 0.1, 0.62), (0.2, 0.1, 0.62), (0, -0.08, 0.76)]
        case 4:
            return [(-0.24, 0.12, 0.56), (0.24, 0.12, 0.56), (-0.1, -0.1, 0.62), (0.13, -0.12, 0.66)]
        case 5:
            return [(-0.17, -0.14, 0.56), (0.18, -0.16, 0.6)]
        default:
            return [(-0.24, -0.1, 0.52), (0.24, -0.1, 0.52), (0, -0.22, 0.62)]
        }
    }

    var body: some View {
        ZStack {
            if tier >= 5 {
                ItemIcon(key: "chest_gold", size: size * 0.8, glow: false)
                    .offset(y: size * 0.14)
            }
            ForEach(Array(Self.crystals(tier).enumerated()), id: \.offset) { _, crystal in
                ItemIcon(key: "divinity", size: size * crystal.scale, glow: false)
                    .offset(x: size * crystal.x, y: size * crystal.y)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: "#C9A7FF").opacity(0.12 + 0.06 * Double(min(6, max(1, tier)))),
                radius: 2 + CGFloat(min(6, max(1, tier))) * 1.5)
        .accessibilityHidden(true)
    }
}

/// The Blessing's seal: a dark disc with a gold ring that empties as the
/// days run, and the days left in it — or "30 DAYS" before the first.
struct BlessingMedallion: View {
    let daysLeft: Int?
    let days: Int
    var size: CGFloat = 56

    private var fraction: CGFloat {
        guard let daysLeft else { return 1 }
        let share: CGFloat = CGFloat(daysLeft) / CGFloat(max(1, days))
        return min(1, max(0, share))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#4A3A1C"), Color(hex: "#15100A")],
                                     center: .center, startRadius: 2, endRadius: size * 0.55))
            ItemIcon(key: "divinity", size: size * 0.62, glow: false)
                .opacity(0.28)
            Circle()
                .stroke(Theme.glassRim.opacity(0.45), lineWidth: 3)
                .padding(2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.goldPlate, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
            VStack(spacing: -1) {
                Text("\(daysLeft ?? days)")
                    .font(Theme.numeric(19))
                    .foregroundStyle(Theme.onGlassGold)
                    .lineLimit(1)
                    .fixedSize()
                Text(daysLeft == nil ? "DAYS" : "LEFT")
                    .font(Theme.body(11).weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(daysLeft.map { "\($0) days left" } ?? "\(days) days")
    }
}

/// A pack's first-purchase double, on its corner.
struct FirstPurchaseMark: View {
    var body: some View {
        Text("×2")
            .font(Theme.numeric(12))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(Theme.goldPlate))
            .overlay(Capsule().strokeBorder(Color(hex: "#FFE9A8").opacity(0.6), lineWidth: 0.8))
            .shadow(color: Theme.gold.opacity(0.45), radius: 4)
            .accessibilityLabel("First purchase doubled")
    }
}

// MARK: - The odds

/// Every scroll divinity buys, with the odds of each grade — the disclosure
/// Guideline 3.1.1 asks for before anything random is bought — and each
/// scroll's full published table (`RateTableView`), pool and pity.
struct TreasuryOddsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var table: Banner?

    private static let scrolls: [ScrollType] = [.pantheonic, .mystical, .divine, .lightDark, .ember, .tide, .gale, .unknown]

    var body: some View {
        NavigationStack {
            GameScreen("Odds", subtitle: "What divinity summons", dismiss: { dismiss() }) {
                EmptyView()
            } content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Self.preface)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Self.scrolls, id: \.self) { scroll in
                            row(scroll)
                        }
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(item: $table) { banner in
            RateTableView(banner: banner)
        }
    }

    static let preface: String = [
        "Divinity from the Treasury buys summons, and every summon is drawn at the odds below,",
        "the same for everyone and published before anything is bought.",
        "A banner's full table lists every unit it can give and its guarantee.",
    ].joined(separator: " ")

    private func row(_ scroll: ScrollType) -> some View {
        HStack(spacing: 10) {
            ItemIcon(key: ItemArt.key(scroll: scroll), size: 30, glow: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(scroll.displayName)
                    .font(Theme.body(13).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(Self.oddsLine(scroll))
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            Text(scroll.divinityPrice.map { "\($0) divinity" } ?? "drachma only")
                .font(Theme.numeric(12))
                .foregroundStyle(Theme.goldDim)
                .lineLimit(1)
                .fixedSize()
            if let banner = Self.banner(for: scroll) {
                Button {
                    table = banner
                } label: {
                    Text("FULL TABLE")
                        .font(Theme.title(12))
                        .tracking(1.0)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.goldPlate))
                }
                // A small action at the row's end: the full press.
                .buttonStyle(GamePressStyle(.plate))
            }
        }
        .padding(10)
        .panelBackground()
    }

    /// "5★ 3.0% · 4★ 18.0% · 3★ 79.0%", best grade first.
    static func oddsLine(_ scroll: ScrollType) -> String {
        scroll.odds
            .sorted { $0.key > $1.key }
            .map { "\($0.key)★ \(String(format: "%.1f", $0.value * 100))%" }
            .joined(separator: " · ")
    }

    /// The banner whose table a scroll's row opens: the first banner that
    /// spends it.
    static func banner(for scroll: ScrollType) -> Banner? {
        Banner.all.first { $0.scroll == scroll }
    }
}
