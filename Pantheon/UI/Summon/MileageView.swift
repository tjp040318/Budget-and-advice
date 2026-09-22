import SwiftUI

// MARK: - The exchange and the gift, in the summoning hall (2026-09-22, phase B)
//
// Both screens open from the summon screen, and run 211 photographed them as
// forms: the selector's five cards in the top third of a cream void with a
// cream slab for a button (36-selector.jpg), the mileage board ten painted
// `ui_panel` frames whose acanthus corners crowded every card, two sentences
// on top and the second row guillotined by the foot with no fade
// (35-mileage.jpg). The critic's verdict: they are chips off the summon
// screen, so they are the same ROOM — `summon_hall_bg` full-bleed under the
// hall's scrims and air, the faces on dark glass, the sentences behind a
// little ?, and the one action a gold `PrimaryButton` that turns to dim glass
// (never a cream slab) while it cannot be pressed.

/// The painting both screens stand in, anchored to its floor as the summon
/// screen anchors it (`SummoningCircle` covers the frame from the bottom
/// up), so the painted circle glows under the button, not off the frame.
private let hallPainting = "summon_hall_bg"
private let hallFocus = UnitPoint(x: 0.5, y: 1.0)

/// A unit the player does not own yet, as the face every other place draws.
///
/// `UnitPortraitTile` takes a `ResolvedUnit` — a unit that exists — and
/// these two screens are about units that do not exist yet. They are drawn
/// as the thing they hand over: the blueprint at level 1 with nothing worn,
/// which is exactly what `redeemMileage` and `claimSelector` create, so the
/// "1" in the tile's corner is the truth rather than a placeholder. The
/// private `BlueprintPortrait` this replaces was a second drawing of the same
/// face with a thinner frame.
private func previewUnit(of blueprint: UnitBlueprint) -> ResolvedUnit {
    ProgressionService.resolve(Unit(blueprint: blueprint), blueprint: blueprint, equipped: [])
}

/// The name before any epithet, as `UnitCard` captions it ("Ares", not
/// "Ares, Bane of Cities"): the face carries no name, so the name under it
/// is the short one and is never cut.
private func faceName(_ name: String) -> String {
    name.split(separator: ",", maxSplits: 1).first.map { String($0) } ?? name
}

/// The mileage exchange: the banner's own pool, priced in points, and a unit
/// the player NAMES.
///
/// It lives inside the banner rather than in the bazaar because the points do:
/// they are earned on this banner and spent on this banner's pool, which is
/// Blue Archive's Recruitment Point shop and the reason that shop reads as a
/// promise rather than a second currency to manage.
///
/// Laid out as the genre's exchange (2026-09-22): the board of faces on one
/// glass plate on the left, fading at its foot where it scrolls on, and the
/// COUNTER on the right — the face picked, large, its name carved, its price,
/// and one Take. A take button on every one of 122 cards was ten price plates
/// that read the same whether the player could pay or not; one counter says
/// once, in gold or in rose, what this one costs and whether it is his.
struct MileageSheet: View {
    let banner: Banner
    /// The unit handed over, so the summon screen can play the reveal.
    var onRedeem: (SummonResult) -> Void

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    /// The face on the counter. Nil until the player taps one; the counter
    /// shows the head of the board until then — the dearest thing he can
    /// take now, or, when he can take nothing, the thing he is saving for.
    @State private var pickedID: String?

    /// `preselect` puts one offer on the counter before any tap — a
    /// blueprint id from the banner's catalogue — so the tour can photograph
    /// the counter short of points (the dim-glass "N MORE") as well as the
    /// gold TAKE the head of the board shows; the game never passes it.
    init(banner: Banner, preselect: String? = nil, onRedeem: @escaping (SummonResult) -> Void) {
        self.banner = banner
        self.onRedeem = onRedeem
        _pickedID = State(initialValue: preselect)
    }

    /// The counter's width. 176 inside its padding holds the longest roster
    /// name in two lines of display 18 ("TERRACOTTA / SOLDIER") and the
    /// widest button title ("35 MORE" with its ticket, 131 points).
    private static let counterWidth: CGFloat = 200
    /// No cell narrower than this: its name is title 13 on up to two lines,
    /// and the longest single word in the roster ("Terracotta",
    /// "Hephaestus") is 84 points of Cinzel at 13, plus the row plate's 8.
    private static let minimumCell: CGFloat = 92
    /// The face's size cap, so a wide phone gets air between faces rather
    /// than faces bigger than the counter's.
    private static let maximumFace: CGFloat = 84
    private static let gap: CGFloat = 8
    /// The board's foot fade, and the room the last row keeps under it so it
    /// can scroll clear of the fade.
    private static let fade: CGFloat = 26

    private var points: Int { MileageService.points(on: banner, player: store.player) }
    /// The whole board, dearest first — the catalogue's own order, and what
    /// the header's target is read off.
    private var offers: [MileageService.Offer] { MileageService.catalogue(for: banner) }

    /// What the grid actually draws: **what you can take, first.**
    ///
    /// Run 153's frame is why. The catalogue is sorted dearest-first so the
    /// thing a player is saving for is the headline — and with 122 units in
    /// the Duat's pool that filled the entire first screen with 5★s at 153
    /// points and "35 MORE" under every one of them. A shop whose first
    /// screenful is nothing you can buy reads as a wall, not an offer. The
    /// affordable band comes first now, dearest within it, and the
    /// aspirational tail follows in the catalogue's own order underneath.
    private func sorted(_ all: [MileageService.Offer]) -> [MileageService.Offer] {
        let held = points
        return all.filter { held >= $0.price } + all.filter { held < $0.price }
    }

    var body: some View {
        // Read once per pass: the catalogue walks the banner's whole pool.
        let all = offers
        let board = sorted(all)
        let picked = board.first { $0.id == pickedID } ?? board.first

        NavigationStack {
            GameScreen(
                "Mileage",
                subtitle: banner.title,
                dismiss: { dismiss() }
            ) {
                BarCount(value: "\(points)", systemImage: "ticket.fill", tint: Theme.gold)
                BarCount(value: "\(all.count)", systemImage: "person.3.fill")
            } content: {
                ZStack {
                    PlaceBackdrop(painting: hallPainting, focus: hallFocus)
                    PlaceAmbience(motes: 18, seed: 921)
                    if board.isEmpty {
                        EmptyState(
                            icon: "ticket",
                            title: "Nothing to exchange",
                            message: "No unit of this banner's pool has its card yet.",
                            onGlass: true
                        )
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            grid(board, litID: picked?.id)
                            counter(picked, all: all)
                                .frame(width: Self.counterWidth)
                        }
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: - The board

    /// Every offer as a face on one glass plate, as many columns as the
    /// width holds at `minimumCell` — five on an iPhone 16 Pro, four on an
    /// iPhone 16, three on an SE — measured with a `GeometryReader`, never
    /// `ViewThatFits`. The
    /// plate scrolls and fades at its foot, so a row is never guillotined
    /// with nothing to say there is more (the frame of run 211).
    private func grid(_ board: [MileageService.Offer], litID: String?) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width.isFinite ? geometry.size.width : 0
            let inner = max(Self.minimumCell, width - 20)
            let columns = max(1, Int((inner + Self.gap) / (Self.minimumCell + Self.gap)))
            let cell = ((inner - Self.gap * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
            let face = min(Self.maximumFace, cell - 8)
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cell), spacing: Self.gap), count: columns),
                    alignment: .leading,
                    spacing: Self.gap
                ) {
                    ForEach(board) { offer in
                        tile(offer, face: face, cell: cell, isOn: offer.id == litID)
                    }
                }
                .padding(10)
                .padding(.bottom, Self.fade)
            }
            .mask(
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                }
            )
        }
        .background(GlassPlate(radius: 14, opacity: 0.62))
    }

    /// One offer: the face, the short name under it on up to two lines,
    /// and the price in a glass bead — gold when the points are there, rose
    /// when they are not, the genre's read of a price. A tap puts it on the
    /// counter; it never takes by itself.
    private func tile(_ offer: MileageService.Offer, face: CGFloat, cell: CGFloat, isOn: Bool) -> some View {
        let affordable = points >= offer.price
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            pickedID = offer.id
        } label: {
            VStack(spacing: 4) {
                UnitPortraitTile(unit: previewUnit(of: offer.blueprint), size: face)
                Text(faceName(offer.blueprint.name))
                    .font(Theme.title(13))
                    .foregroundStyle(isOn ? Color(hex: "#FFF1C2") : Theme.onGlass)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                GlassBead(
                    text: "\(offer.price)",
                    systemImage: "ticket.fill",
                    tint: affordable ? Theme.onGlassGold : Theme.onGlassDanger,
                    height: 22
                )
            }
            .padding(4)
            .frame(width: cell)
            .background(GlassRowPlate(isOn: isOn))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(offer.blueprint.name), \(offer.price) points")
    }

    // MARK: - The counter

    /// The face picked, what it is, what it costs, and the one button: gold
    /// TAKE when the points are there, the shortfall on dim glass when they
    /// are not — readable either way, never the cream disabled slab.
    ///
    /// Heights on a sheet (329 points under the strip, 309 inside the 10 of
    /// padding): 12 + 26 header + 80 face + 17 line + 48 two-line name + 26
    /// price + 46 button + 12, with the spacing, is 301 at its tallest.
    private func counter(_ offer: MileageService.Offer?, all: [MileageService.Offer]) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                GlassSectionHeader(title: "Your pick")
                InfoDot(title: "Mileage") { rules(all) }
            }
            if let offer {
                let affordable = points >= offer.price
                let blueprint = offer.blueprint
                UnitPortraitTile(unit: previewUnit(of: blueprint), size: 80)
                VStack(spacing: 2) {
                    Text("\(blueprint.naturalStars)★ · \(blueprint.element.displayName) · \(blueprint.role.displayName)")
                        .font(Theme.body(11).weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.onGlassEyebrow)
                        .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                        .lineLimit(1)
                        .fixedSize()
                    Text(faceName(blueprint.name).uppercased())
                        .font(Theme.display(18))
                        .carved()
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GlassBead(
                    text: "\(offer.price)",
                    systemImage: "ticket.fill",
                    tint: affordable ? Theme.onGlassGold : Theme.onGlassDanger
                )
                Spacer(minLength: 0)
                PrimaryButton(
                    title: affordable ? "Take" : "\(offer.price - points) more",
                    systemImage: affordable ? "hand.tap.fill" : "ticket.fill",
                    isEnabled: affordable,
                    style: affordable ? .painted : .glass
                ) {
                    redeem(offer)
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassPlate(radius: 14, opacity: 0.78))
    }

    /// The two sentences that sat over the board, behind the counter's ?:
    /// how points are earned and kept, and how far off the dearest face is.
    /// A points system whose rate is not printed is a points system the
    /// player does not believe in — so it is printed, one tap away.
    private func rules(_ all: [MileageService.Offer]) -> some View {
        let held = points
        let within = all.filter { held >= $0.price }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text("One point for every summon on this banner. Points are never lost and never expire, and they are spent only here, on this banner's own pool.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let target = all.first {
                // Hoisted into a typed String: a ternary of two interpolated
                // literals with arithmetic inside `Text(...)` is solved against
                // every Text and numeric overload at once.
                let short: Int = max(0, target.price - held)
                let name: String = faceName(target.blueprint.name)
                let line: String = within > 0
                    ? "\(within) within reach, shown first. \(short) more for \(name)."
                    : "\(short) more for \(name)."
                Text(line)
                    .font(Theme.numeric(12))
                    .foregroundStyle(held >= target.price ? Theme.success : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func redeem(_ offer: MileageService.Offer) {
        guard let result = store.redeemMileage(offer, on: banner) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.medium)
        dismiss()
        onRedeem(result)
    }
}

/// The opening selector: five faces, one choice, before the dice get a vote.
///
/// Epic Seven's Selective Summon is credited as one of its biggest free-to-play
/// improvements, and the point of it is not the unit — it is that the first
/// thing a player does in a gacha is a CHOICE, so the first real face in his
/// collection is one he wanted rather than one he was dealt.
///
/// So it is a ceremony in the summoning hall, not a form (2026-09-22): the
/// hall full-bleed, a carved title, the five faces large on one glass plate
/// with their role under each, the sentence behind the ?, and PICK ONE on
/// dim glass until a face is lit, when it turns to the gold TAKE.
struct SelectorSheet: View {
    var onChoose: (SummonResult) -> Void

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var picked: String?

    /// `preselect` lights one face before any tap — a blueprint id from
    /// `SelectorService.candidates()` — so the tour can photograph the gold
    /// TAKE as well as the dim PICK ONE; the game never passes it.
    init(preselect: String? = nil, onChoose: @escaping (SummonResult) -> Void) {
        self.onChoose = onChoose
        _picked = State(initialValue: preselect)
    }

    /// The largest face; a narrow phone gets less (`faceSize(for:count:)`).
    private static let maximumFace: CGFloat = 100
    private static let gap: CGFloat = 12

    private var candidates: [UnitBlueprint] { SelectorService.candidates() }
    private var chosen: UnitBlueprint? { candidates.first { $0.id == picked } }

    var body: some View {
        let five = candidates
        NavigationStack {
            GameScreen(
                "Opening Gift",
                subtitle: "Once, before the dice",
                dismiss: { dismiss() }
            ) {
                BarCount(value: "\(five.count)", systemImage: "person.3.fill", tint: Theme.gold)
            } content: {
                ZStack {
                    PlaceBackdrop(painting: hallPainting, focus: hallFocus)
                    PlaceAmbience(seed: 923)
                    // Heights on a sheet (329 under the strip): 8 + 49 title
                    // + 10 + a plate of 24 + 12 row padding + 100 face + 20
                    // name + 15 role + 8 between, then at least 8 of spacer,
                    // the 46 button and 10 under it — 310, and the spacer
                    // takes the rest. No spacing on the stack itself: a
                    // stack's spacing is paid on both sides of a Spacer even
                    // at zero height, which put the first draft 7 over.
                    GeometryReader { geometry in
                        let face = faceSize(for: geometry.size.width, count: five.count)
                        VStack(spacing: 0) {
                            HStack(alignment: .center, spacing: 4) {
                                PlaceTitle(eyebrow: "One 4★ of the Duat, yours to name", title: "Choose your first", size: 24)
                                InfoDot(title: "The opening gift") {
                                    Text("The circle owes every demigod one soul it did not choose for him. Pick the one you want; the rest of the roster is still out there, and this gift comes once.")
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            HStack(alignment: .top, spacing: Self.gap) {
                                ForEach(five) { blueprint in
                                    candidate(blueprint, face: face)
                                }
                            }
                            .padding(12)
                            .background(GlassPlate(radius: 14, opacity: 0.72))
                            .padding(.top, 10)
                            Spacer(minLength: 8)
                            PrimaryButton(
                                title: chosen.map { "Take \(faceName($0.name))" } ?? "Pick one",
                                systemImage: chosen == nil ? "hand.tap.fill" : "checkmark.seal.fill",
                                isEnabled: chosen != nil,
                                style: chosen == nil ? .glass : .painted
                            ) {
                                take()
                            }
                            .frame(width: 300)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                }
            }
        }
    }

    /// The face that lets five of them, their row plates and the glass plate
    /// round them stand in the width: 100 on an iPhone 16 Pro (726 points
    /// inside the padding) and on an SE (643).
    private func faceSize(for width: CGFloat, count: Int) -> CGFloat {
        let span = width.isFinite ? width : 0
        let columns = CGFloat(max(1, count))
        // The glass plate's 12 a side, the gaps, and each row plate's 6 a side.
        let room = (span - 24 - Self.gap * (columns - 1)) / columns - 12
        return max(64, min(Self.maximumFace, room.rounded(.down)))
    }

    /// One candidate: the face, the name in Cinzel on up to two lines, and
    /// the role under it, which is what a first choice is made on (the
    /// element is the badge on the face). The picked one stands on the gold
    /// row plate; the others on a breath of glass.
    private func candidate(_ blueprint: UnitBlueprint, face: CGFloat) -> some View {
        let isPicked = picked == blueprint.id
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            picked = blueprint.id
        } label: {
            VStack(spacing: 4) {
                UnitPortraitTile(unit: previewUnit(of: blueprint), size: face)
                Text(faceName(blueprint.name))
                    .font(Theme.title(15))
                    .foregroundStyle(isPicked ? Color(hex: "#FFF1C2") : Theme.onGlass)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(blueprint.role.displayName)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(6)
            .frame(width: face + 12)
            .background(GlassRowPlate(isOn: isPicked))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(blueprint.name), \(blueprint.role.displayName)")
    }

    private func take() {
        guard let chosen, let result = store.claimSelector(chosen) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.medium)
        dismiss()
        onChoose(result)
    }
}
