import SceneKit
import SwiftUI

/// The roster: everything you own, with filters and sorting — and, since
/// 2026-09-11, a unit chosen without leaving the screen.
///
/// The owner, with the grid on his phone: "can we do it more like Summoners
/// War where either we can see the icon list and then when you click on it
/// on the right side the info pops up on the top right with the rune
/// selection/collection underneath? (can you do it where its similar but not
/// exactly the same?) ... I also want a view that the other choice is to see
/// a list along the bottom, the actual character (able to spin with my
/// finger) on the right, and the info/rune selector on the left." So the
/// screen has two layouts, switched in the strip and remembered
/// (`collectionLayout`), and a tap on a card now PICKS rather than opens:
///
/// - **Cards**: the grid on the left, 55% of the width, and a plate on the
///   right for the unit picked — portrait, name, grade, level, power, the
///   four combat stats with what the relics add, then the six relics as the
///   unit sheet's own rosette with the sets they complete beside it, and
///   Full sheet / Train at the foot. The genre's side panel in the
///   game's own marble and bronze rather than a copy of anyone's: this is
///   the DATA layout, and it stays cream.
/// - **Stage**: the roster as a rail of faces along the bottom, the
///   picked unit's real model standing on a rune ring in the right half of
///   the summoning hall's painting (`CollectionStageView`, the Hall of Ka's
///   trick), turned by a drag across that half, and the same words and slots
///   in a plate over the left half — "maybe we do that stuff on the left
///   side, not to copy Summoners War". This is the PLACE layout, so since
///   phase B (2026-09-22) the plate and the rail are dark glass.
///
/// Both share the selection and the sheets. The six slots are the unit
/// sheet's rosette round the Boon (`RelicRosette`, 2026-09-24) and follow its
/// rule: a worn socket opens that relic's card, an empty one opens Manage on
/// that slot (it opened the picker either way, the audit's #25). The
/// portrait, the Full-sheet door and, on the Stage, the carved name and the
/// door in the plate's corner open the unit sheet, paging through this list;
/// Train opens the Hall of Ka on the unit.
struct CollectionView: View {
    @EnvironmentObject private var store: GameStore
    @AppStorage("collectionLayout") private var layout: CollectionLayout = .cards
    @State private var elementFilter: Element?
    @State private var gradeFilter: Int?
    @State private var sort: SortOrder = .power
    /// The unit whose words and slots are shown. Nil until the first pass
    /// picks the top of the list; a unit the filters hide stays picked, and
    /// the list's first stands in for it until the filter comes off.
    @State private var selectedID: UUID?
    @State private var fullSheet: UnitPick?
    @State private var pickingSlot: SlotPick?
    /// A worn relic opened from its socket: the relic's card.
    @State private var openedRelic: CollectionRelicPick?
    @State private var showTraining = false
    @State private var showRelics = false
    /// The Codex, the collection book (`CodexView`, Docs/CODEX.md).
    @State private var showCodex = false
    /// The stage figure's turn, in points of drag: what earlier drags left
    /// it at, and the drag in progress. Both go to zero with a new unit.
    @State private var spinBase: CGFloat = 0
    @State private var spinDrag: CGFloat = 0

    /// Which layout the screen opens in. Every caller wants what the player
    /// last chose (`collectionLayout`, Cards until they switch); the CI tour
    /// wants the Stage without a tap. The value given here is the DEFAULT
    /// under the stored one, not an override of it — a choice the player has
    /// made still wins — which is what the tour needs, since nothing on the
    /// runner ever touches the switch, and what keeps this initialiser free
    /// of side effects on a view SwiftUI builds many times a second.
    init(initialLayout: CollectionLayout? = nil) {
        _layout = AppStorage(wrappedValue: initialLayout ?? .cards, "collectionLayout")
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case power, level, stars, recent, name
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .power: return "Power"
            case .level: return "Level"
            case .stars: return "Grade"
            case .recent: return "Newest"
            case .name: return "Name"
            }
        }
    }

    /// A unit that can drive the full-sheet presentation.
    struct UnitPick: Identifiable {
        let id: UUID
    }

    /// An empty slot on a unit, for Manage on that slot: the slot is the
    /// identity, the unit is who would wear it.
    struct SlotPick: Identifiable {
        let id: Int
        let unitID: UUID
    }

    /// A worn relic, for its card.
    struct CollectionRelicPick: Identifiable {
        let id: UUID
    }

    private var units: [ResolvedUnit] {
        var list = store.resolvedUnits
        if let elementFilter {
            list = list.filter { $0.element == elementFilter }
        }
        if let gradeFilter {
            list = list.filter { $0.stars >= gradeFilter }
        }
        switch sort {
        case .power: list.sort { $0.power > $1.power }
        case .level: list.sort { $0.level > $1.level }
        case .stars: list.sort { ($0.stars, $0.level) > ($1.stars, $1.level) }
        case .recent: list.sort { $0.unit.acquiredAt > $1.unit.acquiredAt }
        case .name: list.sort { $0.name < $1.name }
        }
        return list
    }

    /// Names whatever the strip is filtering by, so the "no matches" copy can
    /// say which filter emptied the grid rather than "you own nothing".
    private var filterDescription: String {
        var parts: [String] = []
        if let gradeFilter { parts.append("\(gradeFilter)★+") }
        if let elementFilter { parts.append(elementFilter.displayName) }
        return parts.isEmpty ? "matching" : parts.joined(separator: " ")
    }

    var body: some View {
        // Resolving and sorting sixty units is not free, and the strip, the
        // empty check and both layouts all want the same answer: work it out
        // once per pass rather than three times.
        let list = units

        NavigationStack {
            GameScreen("Collection", subtitle: subtitle(showing: list.count)) {
                // One glyph that toggles, showing the layout a tap would
                // give: the two-word segments were 106 points of a strip
                // that had none left for its own title (run 210: "COLLECT…"
                // at half size). The genre's grid/figure switch is a glyph.
                BarButton(
                    title: layout == .cards ? "Stage" : "Cards",
                    systemImage: layout == .cards ? "figure.stand" : "square.grid.3x3.fill",
                    showsTitle: false
                ) {
                    layout = layout == .cards ? .stage : .cards
                }
                ElementFilterTiles(selection: $elementFilter)
                BarMenu(label: "Grade", value: gradeFilter.map { "\($0)★+" } ?? "All") {
                    Button("All grades") { gradeFilter = nil }
                    ForEach([3, 4, 5, 6], id: \.self) { stars in
                        Button("\(stars)★ and up") { gradeFilter = stars }
                    }
                }
                BarMenu(label: "Sort", value: sort.displayName) {
                    ForEach(SortOrder.allCases) { order in
                        Button {
                            sort = order
                        } label: {
                            // An open menu covers the value in the strip, so
                            // the live sort has to be marked in the menu too.
                            if sort == order {
                                Label(order.displayName, systemImage: "checkmark")
                            } else {
                                Text(order.displayName)
                            }
                        }
                    }
                }
                // Glyphs only, as the unit sheet's Lore and Lock are. The
                // strip was 656 points of controls against the 756 an iPhone
                // 16 Pro has between its safe areas; the layout switch is
                // another 106, and the two words here were the 64 that no
                // longer fit. Train is also spelled out on the Cards plate.
                BarButton(title: "Train", systemImage: "arrow.up.circle.fill", showsTitle: false) {
                    showTraining = true
                }
                BarButton(title: "Relics", systemImage: "shield.lefthalf.filled", showsTitle: false) {
                    showRelics = true
                }
                // The Codex (2026-09-23): every form of every family, the
                // roster's book. A glyph, as its two neighbours are — the
                // strip has 44 points left for one more — and the book's gold
                // mark on the well's shoulder while a page or a tier waits to
                // be claimed. The closed book is the More screen's codex
                // count's glyph too.
                BarButton(title: "Codex", systemImage: "book.closed.fill", showsTitle: false) {
                    showCodex = true
                }
                .overlay(alignment: .topTrailing) {
                    if store.codexRewardsWaiting > 0 {
                        CodexMark(size: 11)
                            .offset(x: 3, y: 6)
                    }
                }
            } content: {
                if store.player.units.isEmpty {
                    EmptyState(
                        icon: "person.3",
                        title: "Nothing here",
                        message: "Summon at the circle, or clear a stage and come back."
                    )
                } else if list.isEmpty {
                    EmptyState(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "No matches",
                        message: "No \(filterDescription) units in the roster. Clear the filters in the bar to see the rest."
                    )
                } else {
                    let selected = list.first(where: { $0.id == selectedID }) ?? list[0]
                    switch layout {
                    case .cards:
                        cardsLayout(list, selected: selected)
                    case .stage:
                        stageLayout(list, selected: selected)
                    }
                }
            }
            .onAppear {
                if selectedID == nil { selectedID = list.first?.id }
                if layout == .stage { warmStage(list) }
            }
            .onChange(of: layout) { _, now in
                if now == .stage { warmStage(list) }
            }
            // The unit sheet pages through this screen's own list, in its
            // order, filters and all.
            .sheet(item: $fullSheet) { pick in
                UnitDetailView(unitID: pick.id, roster: list.map(\.id))
                    .environmentObject(store)
            }
            .sheet(item: $pickingSlot) { pick in
                RelicsScreen(unitID: pick.unitID, opening: .slot(pick.id))
                    .environmentObject(store)
            }
            .sheet(item: $openedRelic) { pick in
                RelicCard(relicID: pick.id)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showRelics) {
                RelicsScreen()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showTraining) {
                TrainingView(selectedUnitID: selectedID)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCodex) {
                CodexView()
                    .environmentObject(store)
            }
        }
    }

    private func subtitle(showing count: Int) -> String {
        let total = store.player.units.count
        return count == total ? "\(count) units" : "\(count) of \(total)"
    }

    /// The stage loads a unit's model the moment it is picked; the top of the
    /// rail is warmed off the main thread so the first few taps do not stall
    /// on parsing. The Hall of Ka does the same for its rail.
    private func warmStage(_ list: [ResolvedUnit]) {
        ModelLibrary.shared.warm(forms: list.prefix(6).map { (spec: $0.blueprint.model, awakened: $0.unit.isAwakened) }, crowded: false, clips: false)
    }

    // MARK: - Cards: the grid and the plate beside it

    private let gap: CGFloat = 6
    private let gridPadding: CGFloat = 6
    /// How much of the width the grid keeps; the plate takes the rest. A
    /// little over half, because the grid is the list and the plate is one
    /// unit's worth of words: at 55% of an iPhone 16 Pro's frame the grid is
    /// six columns of 60-point cards, two and a half rows of them in view
    /// under the tab bar, and the plate keeps the 300 points its words, its
    /// stats row and its slots with the Train button beside them need.
    private let gridShare: CGFloat = 0.55
    private let columnGap: CGFloat = 8
    /// The smallest card worth drawing: under this the name stops reading even
    /// at `minimumScaleFactor`. Both the column count and the card width are
    /// held to it.
    private let minimumCard: CGFloat = 56
    /// What `UnitCard` draws under the tile: the name over the level line.
    /// Held here only to size the grid — if the card's footer changes height,
    /// change this with it. 41 since the type floor of 2026-09-22 (body 11
    /// and numeric 11.5 under 3 and 4 of padding; measured off run 211's
    /// unit sheet, a 100-point card 141 tall); it was 28.
    private let cardFooter: CGFloat = 41

    private func cardsLayout(_ list: [ResolvedUnit], selected: ResolvedUnit) -> some View {
        GeometryReader { geo in
            let width = geo.size.width.isFinite ? geo.size.width : 0
            let inner = max(160, width - ScreenChrome.contentPadding * 2)
            HStack(alignment: .top, spacing: columnGap) {
                grid(list, selected: selected)
                    .frame(width: ((inner - columnGap) * gridShare).rounded(.down))
                detailPlate(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, gridPadding)
        }
    }

    /// The grid owns its column, and the cards are cut to it rather than
    /// floating in it: what the width does not spend on a card is spent on
    /// another card, not left as gutter. The column count is read off the
    /// height so three rows of them stand in a landscape frame.
    private func grid(_ list: [ResolvedUnit], selected: ResolvedUnit) -> some View {
        GeometryReader { geo in
            let count = columnCount(in: geo.size)
            let card = cardWidth(in: geo.size, columns: count)
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(card), spacing: gap), count: count),
                    spacing: gap
                ) {
                    ForEach(list) { unit in
                        Button {
                            Juice.haptic(.light)
                            selectedID = unit.id
                        } label: {
                            // `UnitCard` fills its square with a portrait that
                            // may be taller than it is wide, and `clipShape`
                            // does not clip hit-testing: the tap belongs to
                            // the card's own rectangle, not to the art.
                            UnitCard(unit: unit, isSelected: unit.id == selected.id, size: card)
                                .contentShape(Rectangle())
                        }
                        // A card of a scrolling grid: quiet, the tick kept
                        // in the action (2026-09-24).
                        .buttonStyle(GamePressStyle(.quiet))
                    }
                    // The grid is filled out to whole rows, and to at least
                    // the three the frame holds. A new save has nine units in
                    // a grid sized for thirty, and the tour photographed the
                    // result: one row of cards and four fifths of the screen
                    // bare black. The genre never shows a void — it shows the
                    // shape of what you have not got yet, which is a goal
                    // rather than a gap, and it is what makes a young
                    // collection look like a collection.
                    ForEach(0..<emptySlots(for: list.count, columns: count), id: \.self) { _ in
                        EmptyCollectionSlot(size: card)
                    }
                }
                // Room for the last row to scroll clear of the fade.
                .padding(.bottom, Self.gridFade)
            }
            // The foot fades, as the mileage board's does: a card cut by the
            // frame's edge read as the tab bar's doing in run 216's frame 1.
            // Two rows and part of a third stand in the frame at rest, so the
            // third row's head under the fade says the grid goes on.
            .mask(
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.gridFade)
                }
            )
        }
    }

    /// The Cards grid's foot fade, and the room under its last row.
    private static let gridFade: CGFloat = 20

    /// The width the cards have to share: the column's own frame, since the
    /// layout around it carries the screen padding now. A non-finite proposal
    /// is treated as nothing, because the column count is an `Int(_:)` of
    /// this and `Int(nan)` traps rather than returning zero.
    private func gridSpan(in size: CGSize) -> CGFloat {
        let width = size.width.isFinite ? size.width : 0
        return max(80, width)
    }

    private func columnCount(in size: CGSize) -> Int {
        let span = gridSpan(in: size)
        let height = size.height.isFinite ? size.height : 0
        let usable = max(80, height - gridPadding)
        // The widest card that still leaves three rows in the frame, the
        // card's own footer counted in.
        let byHeight = (usable - gap * 2) / 3 - cardFooter
        let target = min(max(byHeight, minimumCard), 96)
        // Rounded up, so the card the width divides into is no taller than
        // the height allows: too wide a card costs a whole row.
        let wanted = max(3, Int(((span + gap) / (target + gap)).rounded(.up)))
        // ...but never more columns than the width holds at the smallest card.
        // These are `.fixed` columns: one too many and the row lays out wider
        // than the frame rather than wrapping, which is what the first pass —
        // proposed a zero size before the frame is known — would draw.
        let fits = max(1, Int((span + gap) / (minimumCard + gap)))
        return min(wanted, fits)
    }

    /// How many wells to draw after the last card: enough to finish the row,
    /// and enough to reach three rows while the roster is small. It stops
    /// entirely once the player has more than three rows of units, so a full
    /// collection is cards and nothing else.
    private func emptySlots(for owned: Int, columns: Int) -> Int {
        guard columns > 0 else { return 0 }
        let wholeRows = ((owned + columns - 1) / columns) * columns
        return max(0, max(columns * 3, wholeRows) - owned)
    }

    private func cardWidth(in size: CGSize, columns: Int) -> CGFloat {
        let width = (gridSpan(in: size) - gap * CGFloat(columns - 1)) / CGFloat(columns)
        return max(minimumCard, width.rounded(.down))
    }

    // MARK: - The plate: one unit's words and slots

    /// The card's art beside the words on the Cards plate: 84, the words'
    /// own height, so the block is no taller than its text.
    private static let portraitSize: CGFloat = 84
    /// The six relics in both layouts: the unit sheet's rosette at R 19 with
    /// a 2-point gap, 102.7 × 98.4 (2026-09-24) — 41 points narrower than the
    /// 3×2 of 44-point tiles it replaced and four taller, which is what a
    /// plate that shares its frame with a grid or a stage, UNDER the tab
    /// bar, can spend on them.
    private static let rosetteRadius: CGFloat = 19
    private static let rosetteGap: CGFloat = 2
    /// What the painted panel's last row has to clear at the bottom: its
    /// corner ornament reaches 16.9 points up and 18.6 in, against the band's
    /// 8 — 71 and 78 px of the 512 px @3x `ui_panel` at `Chrome.shrink`,
    /// measured for the cream unit sheet's panels before it became a place.
    private static let plateBottomInset: CGFloat = 18

    /// The Cards layout's right side: the portrait and the words, the four
    /// stats across, then the slots with the sets they complete beside them
    /// and the two doors at the foot — the unit sheet (a glyph, whole) and
    /// Train (the gold `PrimaryButton`).
    ///
    /// One frame, no scroll, so the heights are written down. The
    /// collection is a TAB, so its content is measured under the 58-point
    /// `GameTabBar` (2026-09-22, phase B: the tour had photographed it
    /// without the bar, 58 points taller than the phone): an iPhone 16 Pro
    /// in landscape gives it 271, an iPhone 16 262. Less the layout's 12 of
    /// padding and the panel's 26 of inset, 233 and 224 inside. The words
    /// beside the 84 portrait are 86 (name 20, epithet 15, element and
    /// power 18, the level line 16 and its meter, at the fonts' own line
    /// heights), the stats row 34, the slots 96, with 4 between: 224. The
    /// block it replaces was 300 tall — the type floor had grown the words
    /// from 128 to 175 — and fitted only because the tour's frame had no
    /// tab bar. The rosette (2026-09-24) is 98.4 where the tiles and their
    /// badges' 2 points were 96: the iPhone 16's plate runs 2.4 points into
    /// its 18 of bottom clearance, where the rosette's lower corners are
    /// empty (pointed hexagons) and TRAIN's rounded corner is inside the
    /// ornament's 17 by a point — nothing meets the carving.
    ///
    /// Train was a teal plate, a third button material beside gold and
    /// glass, and "Full sheet" was cut to "Full…" (run 211, frame 1); the
    /// critic's two faults, both gone.
    private func detailPlate(_ unit: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                portrait(unit)
                header(unit, ink: .cream)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            statsRow(unit, ink: .cream)
            HStack(alignment: .top, spacing: 7) {
                // Basalt sockets on the cream plate, on purpose: a relic
                // always lies on dark, where its colour reads.
                relicRosette(unit)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SETS · \(unit.relics.count)/6 WORN")
                        .font(Theme.body(11).weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(Theme.goldDim)
                        .lineLimit(1)
                        .fixedSize()
                    setSummary(unit, ink: .cream)
                    Spacer(minLength: 0)
                    // 149 points on an iPhone 16 Pro, 141 on an iPhone 16:
                    // the 46 door, 5, and 98 or 90 for TRAIN, whose label is
                    // 59 of Cinzel at 15 plus the button's 28 of padding. No
                    // glyph on it: with one it is 110 and the button would
                    // shrink its title under the floor.
                    HStack(spacing: 5) {
                        fullSheetDoor(unit)
                        PrimaryButton(title: "Train") {
                            showTraining = true
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelPadding)
        .padding(.bottom, Self.plateBottomInset)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// The door to the unit sheet, as a glyph the height of the button
    /// beside it: a cream plate in a gold rim, the sheet's own figure on it.
    /// Its two words were cut to "Full…" in a plate that had 60 points for
    /// them; a glyph cannot be cut, and the portrait above opens the same
    /// sheet for a thumb that goes to the face.
    private func fullSheetDoor(_ unit: ResolvedUnit) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return Button {
            fullSheet = UnitPick(id: unit.id)
        } label: {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.goldDim)
                .frame(width: PrimaryButton.height, height: PrimaryButton.height)
                .background(
                    shape.fill(LinearGradient(colors: [Theme.surfaceHigh, Theme.surface],
                                              startPoint: .top, endPoint: .bottom))
                )
                .overlay(shape.strokeBorder(Theme.goldPlate, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .contentShape(shape)
        }
        // Answers on touch-down (2026-09-24), so the action plays nothing.
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("Full sheet")
    }

    /// The card's art in its grade's metal, without the card's caption: the
    /// words stand beside it here. A tap opens the unit sheet.
    private func portrait(_ unit: ResolvedUnit) -> some View {
        let rarity = Rarity(stars: unit.stars)
        let art = unit.blueprint.model.portraitName(awakened: unit.unit.isAwakened)
        return ZStack {
            if BundleImage.exists(art) {
                // Decoded at the drawn size, as every card in a list is.
                BundleImage(name: art, renderedAt: Self.portraitSize)
                    .aspectRatio(contentMode: .fill)
            } else {
                // Pre-art: the element's tint and the initial, as `UnitCard`.
                RadialGradient(
                    colors: [unit.element.color.opacity(0.75), unit.element.color.opacity(0.25), Theme.surface],
                    center: .init(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: Self.portraitSize * 0.85
                )
                Text(String(unit.name.prefix(1)))
                    .font(Theme.display(Self.portraitSize * 0.46))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(width: Self.portraitSize, height: Self.portraitSize)
        .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
        .overlay(paintedFrame(rarity))
        // The lock on its dark disc, as the cards wear it (`CardMark`, run
        // 221: an ink glyph vanished on a dark painting), and over the
        // carved frame rather than under its corner scroll.
        .overlay(alignment: .topTrailing) {
            if unit.unit.isLocked {
                CardMark(systemName: "lock.fill", size: 18, gold: false)
                    .padding(6)
            }
        }
        .rarityFrame(rarity, radius: Theme.tightCorner)
        // A painting scaled to fill overhangs its frame, and `clipShape` does
        // not clip hit-testing: without this it takes the taps meant for the
        // words beside it. The tap is a clear plate of exactly the frame.
        .allowsHitTesting(false)
        .overlay {
            Button {
                fullSheet = UnitPick(id: unit.id)
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            // The press's tick and tap on touch-down (2026-09-24); the clear
            // plate has nothing to sink.
            .buttonStyle(GamePressStyle(.plate))
            .accessibilityLabel("\(unit.name), full sheet")
        }
    }

    /// The carved frame for the grade, over the art, as `UnitCard` draws it.
    /// Nothing when the texture has not shipped; `rarityFrame` strokes then.
    @ViewBuilder
    private func paintedFrame(_ rarity: Rarity) -> some View {
        if let frame = Chrome.image(rarity.frameImageName) {
            Image(uiImage: frame)
                .resizable()
        }
    }

    /// Name, epithet, element, grade and power, and the level with its
    /// meter — 85 points, the same block in both layouts, in cream ink on
    /// the Cards plate and in the on-glass colours on the Stage's glass
    /// (96 there, the name carved at 22).
    ///
    /// The name is Cinzel at 15 and shrinks to the title floor (13) before
    /// anything else gives; the widest in the roster ("Perseus Gorgon-Bane",
    /// 180 points at 15) fits the 189 the Stage leaves it. The power moved
    /// off the name's line onto the element's, so a long name has the width.
    private func header(_ unit: ResolvedUnit, ink: PlateInk) -> some View {
        // `grantExperience` zeroes the stored experience at the cap, so a
        // maxed unit's bar would read "0 / 1400" under a full level — the
        // unit sheet's fix: fill it and say MAX.
        let toNextLevel = Double(ProgressionService.experienceForNextLevel(
            level: unit.level, stars: unit.stars
        ))
        let experience = unit.unit.isMaxLevel ? toNextLevel : Double(unit.unit.experience)
        let meterTint = unit.unit.isMaxLevel ? Theme.gold : Theme.info
        return VStack(alignment: .leading, spacing: 3) {
            // On the Stage's glass the name is CARVED at a display size, as
            // the Hall of Ka carves it on its plate (run 216: a 15-point name
            // on a place screen read as a data box beside the Hall's 26). It
            // shrinks to the title floor before anything gives: "Perseus
            // Gorgon-Bane" is 264 points at 22 in the 182 it has on an
            // iPhone 16 beside the rosette and the door, 0.69. There it is
            // also a door to the unit sheet (2026-09-24, the audit's #23:
            // the Stage had none).
            Group {
                if ink.isGlass {
                    Button {
                        fullSheet = UnitPick(id: unit.id)
                    } label: {
                        Text(unit.nameWithoutEpithet)
                            .font(Theme.display(22))
                            .carved(glow: false)
                            .minimumScaleFactor(Theme.titleFloor / 22)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GamePressStyle(.plate))
                    .accessibilityLabel("\(unit.name), full sheet")
                } else {
                    Text(unit.nameWithoutEpithet)
                        .font(Theme.title(15))
                        .foregroundStyle(ink.primary)
                        .minimumScaleFactor(Theme.titleFloor / 15)
                }
            }
            .lineLimit(1)
            Text(unit.epithetUnderName)
                .font(Theme.body(11))
                .foregroundStyle(ink.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ElementBadge(element: unit.element, compact: true)
                // Bright on glass, as the Hall's nameplate draws them: the
                // natural stars' dim bronze could not be counted on the dark
                // plate (run 217). The cream plate keeps the two tones.
                StarRow(stars: unit.stars, natural: ink.isGlass ? nil : unit.blueprint.naturalStars, size: 10)
                Spacer(minLength: 4)
                Text("\(unit.power)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(ink.accent)
                    .lineLimit(1)
                    .fixedSize()
                Text("POWER")
                    .font(Theme.body(11).weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(spacing: 4) {
                Text(unit.unit.isMaxLevel
                     ? "Lv.\(unit.level) · MAX"
                     : "Lv.\(unit.level) / \(unit.unit.maxLevel)")
                    .font(Theme.body(11))
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                Text("\(Int(experience)) / \(Int(toNextLevel))")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(ink.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            // A cream channel on marble, a dark one on glass: `StatBar`'s
            // recessed cream track is a pale stripe on a dark plate.
            Group {
                if ink.isGlass {
                    GlassMeter(value: experience, maximum: toNextLevel, tint: meterTint, height: 5)
                } else {
                    StatBar(value: experience, maximum: toNextLevel, tint: meterTint, height: 5)
                }
            }
        }
    }

    /// HP, ATK, DEF and SPD across the plate, each the total beside its name
    /// with the relics' share under it. Base is grade, level and awakening;
    /// the difference to the final number is the six slots, shown the way
    /// the genre shows it so equipping a relic is visible here and not only
    /// in battle. One row of four rather than two of two: 33 points instead
    /// of 65, which is what let the plate fit under the tab bar.
    private func statsRow(_ unit: ResolvedUnit, ink: PlateInk) -> some View {
        let base = ProgressionService.baseStats(for: unit.unit, blueprint: unit.blueprint)
        return HStack(alignment: .top, spacing: 6) {
            statCell("HP", base.hp, unit.stats.hp, ink: ink)
            statCell("ATK", base.atk, unit.stats.atk, ink: ink)
            statCell("DEF", base.def, unit.stats.def, ink: ink)
            statCell("SPD", base.spd, unit.stats.spd, ink: ink)
        }
    }

    /// One stat: "HP 5,270" over "+2,573", grouped as every other number on
    /// the plate is (`UnitDetailView.statText`; run 221 printed "HP 7301"
    /// beside "2,983 POWER"). Every figure is at its own width (`fixedSize`)
    /// and at or over its floor — a 70-point cell holds "HP 12,345" (64) and
    /// "+10,234" (46), so nothing is shrunk or cut.
    private func statCell(_ label: String, _ base: Double, _ total: Double, ink: PlateInk) -> some View {
        let bonus = total - base
        // A blank line when the relics add nothing, so the four cells keep
        // one height and one baseline. Hoisted out of the builder so the
        // type checker is handed a String, not a ternary inside `Text(...)`.
        let sign = bonus > 0 ? "+" : "−"
        let bonusText: String = abs(bonus) >= 0.5 ? sign + UnitDetailView.statText(abs(bonus), percent: false) : " "
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(label)
                    .font(Theme.body(11).weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Text(UnitDetailView.statText(total, percent: false))
                    .font(Theme.numeric(13))
                    .foregroundStyle(ink.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(bonusText)
                .font(Theme.numeric(11.5))
                .foregroundStyle(bonus > 0 ? ink.good : ink.bad)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The six relics as the unit sheet draws them: the rosette of basalt
    /// sockets round the Boon, slot 1 at eleven o'clock and clockwise, a
    /// complete set's sockets ringed in gold — the same object on the Cards
    /// plate's cream and the Stage's glass, since a relic always lies on
    /// dark. The centre shows the Boon and is not a door here (the unit
    /// sheet's is).
    private func relicRosette(_ unit: ResolvedUnit) -> some View {
        RelicRosette(
            slots: wornRelics(unit),
            activeSets: Set(unit.activeRelicSets.map { $0.set }),
            boon: unit.boon,
            radius: Self.rosetteRadius,
            gap: Self.rosetteGap,
            onSlot: { slot in
                openSlot(slot, of: unit)
            }
        )
    }

    /// The worn relics by the slot they are worn in.
    private func wornRelics(_ unit: ResolvedUnit) -> [Int: Relic] {
        var slots: [Int: Relic] = [:]
        for (slot, relicID) in unit.unit.equippedRelics {
            if let relic = store.player.relic(relicID) {
                slots[slot] = relic
            }
        }
        return slots
    }

    /// The unit sheet's rule: a worn socket opens the relic's card, an empty
    /// one opens Manage on that slot, where the grid is that slot's relics
    /// by fit and NOW → THEN says what a pick would change.
    private func openSlot(_ slot: Int, of unit: ResolvedUnit) {
        if let relicID = unit.unit.equippedRelics[slot], store.player.relic(relicID) != nil {
            openedRelic = CollectionRelicPick(id: relicID)
        } else {
            pickingSlot = SlotPick(id: slot, unitID: unit.id)
        }
    }

    /// The sets the worn relics complete, in a line: "Fury ×2 · Guard".
    private func setSummary(_ unit: ResolvedUnit, ink: PlateInk) -> some View {
        let sets = unit.activeRelicSets
        return Group {
            if sets.isEmpty {
                Text(unit.relics.isEmpty ? "Nothing worn" : "No set bonus")
                    .font(Theme.body(11))
                    .foregroundStyle(ink.secondary)
            } else {
                Text(sets.map { entry in
                    entry.completions > 1
                        ? "\(entry.set.displayName) ×\(entry.completions)"
                        : entry.set.displayName
                }.joined(separator: " · "))
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(ink.accent)
            }
        }
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stage: the rail, the figure and the plate

    /// The faces on the rail, and the room above and below them: the tile,
    /// its row plate's 4 a side, and 7 over and under — 80 points.
    private static let railFace: CGFloat = 58
    private static let railPadding: CGFloat = 7
    private static var railHeight: CGFloat { railFace + 8 + railPadding * 2 }

    /// The summoning hall under everything, the figure on its ring in the
    /// right half, the glass plate over the left, the drag over the right,
    /// and the rail of faces along the bottom on dark glass.
    ///
    /// It is a PLACE (2026-09-22, phase B): the critic's clearest miss after
    /// the Hall of Ka was this screen's translucent CREAM plate over the
    /// painting and its rail on a cream band with the names cut ("Anubis,
    /// Kee…", frame 21). The plate is glass with the on-glass words now, the
    /// rail a glass rail of faces (`UnitPortraitTile`, no name to cut), and
    /// the hall has the summon screen's scrims and air. The Cards layout is
    /// its DATA twin and stays cream.
    ///
    /// The heights, since nothing here scrolls but the rail: the collection
    /// is a tab, so an iPhone 16 Pro gives the content 271 over the
    /// `GameTabBar`. Less the rail's 80 and the stage's 16 of padding, the
    /// plate has 175; it is 156 (the words beside the slots, 96 with the
    /// name carved at 22, then 6 and the stats row, 34, and its 20 of
    /// padding). An iPhone 16 gives it 166. The set line the plate carried
    /// under the words went for the carved name (run 216's judge: the Cards
    /// plate says it, and the stones on the slots wear their sets' colours).
    /// The rosette (2026-09-24) is 98.4 against the tiles' 96, so the plate
    /// is 158.4 of its 175.
    private func stageLayout(_ list: [ResolvedUnit], selected: ResolvedUnit) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let width = geo.size.width.isFinite ? geo.size.width : 0
                ZStack(alignment: .topLeading) {
                    CollectionStageView(unit: selected, spin: Float((spinBase + spinDrag) * CollectionStageView.spinPerPoint))
                        .allowsHitTesting(false)
                    HStack(alignment: .top, spacing: 0) {
                        stagePlate(selected)
                            .frame(width: width * 0.5, alignment: .topLeading)
                        // The right half is the figure's: a drag across it
                        // turns the figure about its own axis, left for
                        // left, and it stays where the finger left it until
                        // the next drag or the next unit.
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 4)
                                    .onChanged { value in
                                        spinDrag = value.translation.width
                                    }
                                    .onEnded { value in
                                        spinBase += value.translation.width
                                        spinDrag = 0
                                    }
                            )
                            // The hint on a small dark glass capsule, the
                            // rule for words over a painting: bare pale caps
                            // on the painted floor had the meander and the
                            // laurel running through the letters (run 217).
                            .overlay(alignment: .bottom) {
                                GlassCapsule(height: 22) {
                                    Image(systemName: "arrow.left.and.right")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(Theme.onGlassEyebrow)
                                    Text("DRAG TO TURN")
                                        .font(Theme.body(11).weight(.black))
                                        .tracking(1.2)
                                        .foregroundStyle(Theme.onGlass)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                .padding(.bottom, 2)
                                .allowsHitTesting(false)
                            }
                    }
                }
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
            stageRail(list, selected: selected)
        }
        .background(stageGround)
        .onChange(of: selected.id) { _, _ in
            // A new figure is met face on.
            spinBase = 0
            spinDrag = 0
        }
    }

    /// The words and the relics over the left half, on dark glass with the
    /// on-glass colours — the rule for words over a painting — and in the
    /// plate's top-trailing corner the door to the unit sheet (2026-09-24,
    /// the audit's #23: the Stage had none). The door stands beside the
    /// rosette rather than on it, so no socket is covered.
    private func stagePlate(_ unit: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                header(unit, ink: .glass)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                relicRosette(unit)
                stageSheetDoor(unit)
            }
            statsRow(unit, ink: .glass)
        }
        .padding(10)
        .background(GlassPlate(radius: 12, opacity: 0.72))
    }

    /// The Stage plate's door to the unit sheet: the strip's own dark well,
    /// a 34-point circle, with the sheet's figure on it in pale gold.
    private func stageSheetDoor(_ unit: ResolvedUnit) -> some View {
        Button {
            fullSheet = UnitPick(id: unit.id)
        } label: {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Theme.onGlassGold)
                .frame(width: ScreenChrome.control, height: ScreenChrome.control)
                .background(ScreenChrome.well)
                .contentShape(Circle())
        }
        // Answers on touch-down, so the action plays nothing.
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("\(unit.name), full sheet")
    }

    /// The roster as a rail of faces along the bottom, the picked one on the
    /// gold row plate and kept in view, the rail ending in a fade at its
    /// right where it scrolls on.
    private func stageRail(_ list: [ResolvedUnit], selected: ResolvedUnit) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(list) { unit in
                        Button {
                            Juice.haptic(.light)
                            AudioLibrary.shared.play(.uiTap)
                            selectedID = unit.id
                        } label: {
                            UnitPortraitTile(unit: unit, size: Self.railFace)
                                .padding(4)
                                .background(GlassRowPlate(isOn: unit.id == selected.id))
                                // The face and its plate's rim are the tap.
                                .contentShape(Rectangle())
                        }
                        // A face of a scrolling rail: quiet, the tick and
                        // tap kept in the action (2026-09-24).
                        .buttonStyle(GamePressStyle(.quiet))
                        .id(unit.id)
                    }
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, Self.railPadding)
            }
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92),
                                       .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .onAppear {
                proxy.scrollTo(selected.id, anchor: .center)
            }
            .onChange(of: selected.id) { _, id in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: Self.railHeight)
        // The rail's glass runs out to both edges with the painting under it
        // (the backdrop bleeds since run 216); the faces stay inside the
        // safe area.
        .background(railPlate.ignoresSafeArea(.container, edges: .horizontal))
    }

    /// The summon screen's `GlassRailPlate`, laid along the bottom instead of
    /// down the left: turned a quarter anticlockwise, so its dark edge is the
    /// screen's foot and its gold hairline runs along the top, over the
    /// stage. The one drawing of a rail's glass, whichever edge it is on.
    private var railPlate: some View {
        GeometryReader { geometry in
            GlassRailPlate()
                .frame(width: geometry.size.height, height: geometry.size.width)
                .rotationEffect(.degrees(-90))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    /// The summoning hall behind the stage, with the summon screen's scrims
    /// (lighter at the top, where the glass plate sits and the figure's head
    /// stands) and its motes, under the figure.
    ///
    /// Anchored to the painting's FLOOR (`focus` y 1): cropped at its centre
    /// it showed the columns and the altar in the right half and no floor at
    /// all above the rail, so the figure hovered on its ring in front of a
    /// fluted column (run 216, frame 21). Measured off the painting with a
    /// grid: its floor medallion is centred at (0.50, 0.82) and 0.60 of the
    /// width across; over the 874 × 271 of an iPhone 16 Pro's tab this crop
    /// shows the painting from 0.45 of its height down, the marble floor
    /// from about 0.33 of the frame, and the figure's feet (the stage's
    /// `across` 0.66, `down` 0.78) land at (0.63, 0.74) of the painting — on
    /// the medallion's laurel ring, on the painted floor.
    ///
    /// A `.background`, never a sibling: `PlaceBackdrop` is a `PaintingFill`,
    /// which reports exactly the size it is given, and it takes no taps —
    /// the mistake that emptied the dungeon screen's frames cannot recur.
    private var stageGround: some View {
        ZStack {
            PlaceBackdrop(painting: "summon_hall_bg", focus: UnitPoint(x: 0.5, y: 1.0), topScrim: 0.35, footScrim: 0.55)
            PlaceAmbience(motes: 16, seed: 961)
        }
        .allowsHitTesting(false)
    }
}

/// The colours of one unit's words: cream ink on the Cards plate (DATA,
/// marble), the on-glass set on the Stage's glass (a PLACE). One block of
/// words is drawn for both layouts, so the two cannot drift apart; only the
/// ink changes (2026-09-22, phase B).
private struct PlateInk {
    let isGlass: Bool
    let primary: Color
    let secondary: Color
    let accent: Color
    let good: Color
    let bad: Color

    static let cream = PlateInk(
        isGlass: false,
        primary: Theme.textPrimary,
        secondary: Theme.textSecondary,
        accent: Theme.gold,
        good: Theme.success,
        bad: Theme.danger
    )

    static let glass = PlateInk(
        isGlass: true,
        primary: Theme.onGlass,
        secondary: Theme.onGlassDim,
        accent: Theme.onGlassGold,
        good: Theme.onGlassSuccess,
        bad: Theme.onGlassDanger
    )
}

/// Which of the two shapes the collection takes. Stored by its name under
/// `collectionLayout`, so a save that predates the switch reads as Cards.
enum CollectionLayout: String, CaseIterable {
    case cards, stage

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .stage: return "Stage"
        }
    }
}

// MARK: - The stage

/// The picked unit standing in the summoning hall, turned by a finger.
///
/// The Hall of Ka's altar (`AltarStageView`) without the rites: a transparent
/// SceneKit view the size of the stage, the unit's real model on a rune ring
/// with a contact shadow, lit as that painting is, and a camera shifted — not
/// turned — so the figure stands in the right half of the frame with the
/// plate's words beside it. The one thing the altar has not got is a yaw the
/// screen sets from the drag across that half. The figure is rebuilt when the
/// unit or its form changes, and the screen zeroes the spin with it.
///
/// It was also the unit sheet's figure for a day (FEEL.md, W1.10), in a dark
/// glass well in the sheet's left column; since the relic redesign of the
/// same day the sheet is a place of its own and stands its figure on the Hall
/// of Ka's painted dais (`AltarStageView`), turned at this stage's rate
/// (`spinPerPoint`). `Framing` keeps its measures general for a stage that
/// wants its figure somewhere else.
struct CollectionStageView: UIViewRepresentable {
    let unit: ResolvedUnit?
    /// The turn about Y, in radians, on top of the stance.
    let spin: Float
    /// Where the figure stands in this stage's frame: the collection's by
    /// default.
    var framing: Framing = .collection
    /// Whether the stage runs. False while it is out of sight, so a view
    /// nobody can see stops drawing sixty frames a second; the figure holds
    /// its pose and takes it up again as it comes back into view.
    var playing: Bool = true

    /// Radians of turn per point of drag: one full turn across a landscape
    /// phone's width, which is what a finger expects of a turntable. The
    /// unit sheet's altar turns its figure at the same rate — one gesture,
    /// one feel.
    static let spinPerPoint: CGFloat = .pi * 2 / 800

    /// Where the figure stands in the stage's frame, in shares of it: its
    /// centre line `across` of the way across, its feet `down` of the way
    /// down, and `fill` of the height tall.
    ///
    /// `stance` is the turn about Y before any drag, in radians. A figure is
    /// authored facing +Z, toward the camera, and a POSITIVE turn brings its
    /// front round to the frame's RIGHT (`UnitNode` faces a victim with
    /// `atan2(dx, dz)`). So the collection's 0.3 turns its figure toward the
    /// right, away from the plate on the left — run 241's frame 21 has
    /// Thoth's beak pointing right — though the note this replaces said it
    /// turned toward the words; the number is kept, since it is the frame
    /// the owner has judged.
    ///
    /// `ringRoom`, when set, is the most of the frame's width, measured from
    /// the centre line to the nearer edge, the rune ring may take; a ring
    /// built wider is scaled down to it. A narrow frame is narrower than a
    /// figure's ring is wide — `max(1.2, 0.7 h)` of radius is 1.4 times the
    /// figure's height across — and shrinking the RING keeps the figure at
    /// its `fill`, where shrinking the figure to fit the ring would leave a
    /// tall well's upper third empty. Nil, the collection's, leaves the ring
    /// as it was built.
    ///
    /// `fillByWidth`, when set, caps `fill` at that share of the frame's
    /// WIDTH (the figure's height at most `fillByWidth` times the width): a
    /// well taller than the one it was drawn for — a family with no
    /// awakening has 36 points more, a Pro Max 28 — keeps its figure at the
    /// size the width sets, with the room over its head, where 78% of the
    /// height made a figure wide enough to stand under the card's thumbnail.
    /// Nil, the collection's, is `fill` alone.
    ///
    /// `firstAspect` is the frame's shape (width over height) the camera is
    /// solved for before the view's first layout, when its bounds are still
    /// zero: the collection's is a notched phone's stage in landscape, and a
    /// well framed on that until the next update would stand its figure a
    /// fifth of a metre off its centre line with its ring uncut.
    ///
    /// `name` is the stage's name in the tour's console (`StageDoctor`).
    struct Framing: Equatable {
        var across: Float
        var down: Float
        var fill: Float
        var stance: Float
        var ringRoom: Float?
        var fillByWidth: Float?
        var firstAspect: Float
        var name: String

        /// The collection's Stage: the centre line 66% of the way across the
        /// frame, the feet 78% of the way down, 70% of the height tall. The
        /// left half is the plate's; the figure has the right, with room
        /// over its head for the tallest family and under its feet for the
        /// ring. 0.66 rather than 0.72 since run 216, so the feet stand on
        /// the hall's painted floor medallion (`CollectionView.stageGround`)
        /// rather than on bare marble beside a column; the ring's left edge
        /// still clears the plate by 30 points.
        static let collection = Framing(across: 0.66, down: 0.78, fill: 0.70, stance: 0.3, ringRoom: nil,
                                        fillByWidth: nil, firstAspect: 736 / 204, name: "collection")
    }

    private static let lens: Float = 30

    final class Coordinator {
        var scene: SCNScene?
        var figure: SCNNode?
        var figureKey = ""
        var figureHeight: Float = 1.9
        var ring: SCNNode?
        /// The ring's radius as built, before `Framing.ringRoom` scales it.
        var ringRadius: Float = 0
        var shadow: SCNNode?
        var cameraNode: SCNNode?
        var framedFor: Float = 0
        /// The framing the camera was last solved for.
        var framing: Framing?
        /// Replaced in `makeUIView` by one named for the framing.
        var doctor = StageDoctor(label: "collection")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        // Transparent: the painting behind this view is the hall. Everything
        // added here either blends with a real alpha channel or adds light
        // and writes no alpha (the summon stage's rule).
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isPlaying = true
        // The drag is a SwiftUI gesture over the view, not the view's own.
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        // The console says which screen's stage it is watching: the unit
        // sheet's and the collection's are the same view (2026-09-24).
        coordinator.doctor = StageDoctor(label: framing.name)
        view.delegate = coordinator.doctor
        coordinator.doctor.view = view
        coordinator.scene = scene

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.lens)
        camera.projectionDirection = .vertical
        camera.zNear = 0.5
        camera.zFar = 100
        camera.wantsHDR = true
        // THE SHOULDER (2026-09-17, evening): `whitePoint` at SceneKit's
        // default 1.0 clips every lit surface at or over 1.0 flat to paper —
        // the battle learned it on 2026-09-15 (BattleSceneController) and
        // this camera never got it, which is half of why the owner's awakened
        // Ares photographed as a pale smear on the reveal. Same number as the
        // battle's so the figure looks the same on every stage.
        camera.whitePoint = 1.85
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.3
        camera.bloomThreshold = 0.93
        camera.bloomBlurRadius = 12
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        coordinator.cameraNode = cameraNode

        // Lit as the hall is: a warm key from the oculus above and in front,
        // a cool fill from the marble, a gold rim from behind, and an ambient
        // floor so the shadow side keeps its costume — the altar's rig.
        // The rig's numbers, the studio environment and the figure's shadow are
        // `FigureStageLighting`, shared with the reveal (2026-09-18).
        let key = SCNLight()
        key.type = .directional
        key.intensity = FigureStageLighting.keyIntensity
        key.color = UIColor(hex: "#FFE8C2") ?? .white
        FigureStageLighting.castShadows(from: key)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-1.0, -0.3, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = FigureStageLighting.fillIntensity
        fill.color = UIColor(hex: "#7C93D6") ?? .white
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.4, 0.9, 0)
        scene.rootNode.addChildNode(fillNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = FigureStageLighting.rimIntensity
        rim.color = UIColor(hex: "#FFD36A") ?? .yellow
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.5, 2.7, 0)
        scene.rootNode.addChildNode(rimNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = FigureStageLighting.ambientIntensity
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        FigureStageLighting.applyEnvironment(to: scene)

        place(unit, in: coordinator)
        frameCamera(view, coordinator)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        place(unit, in: coordinator)
        frameCamera(view, coordinator)
        // The drag, applied every pass: it is one float and the figure is
        // one node, so there is nothing to be saved by checking first.
        coordinator.figure?.eulerAngles.y = framing.stance + spin
        // Out of sight, the stage stops: no scene time, no frames. Only a
        // change is written, so the collection's stage, which always plays,
        // is never touched here.
        if view.isPlaying != playing {
            view.isPlaying = playing
            view.rendersContinuously = playing
        }
    }

    /// The stage lets go of its scene the moment it leaves the screen
    /// (2026-09-24).
    ///
    /// The model cache is bounded since 1b1bf74, but it never drops a file a
    /// live figure was cloned from, and until now this stage kept its figure
    /// for as long as SceneKit kept the view — the scene held by the view and
    /// by this coordinator both — so every unit sheet opened could leave a
    /// family pinned in the cache after its sheet had gone (run 242's summon
    /// stress climbed 30 MB a reveal and never came down; a stage that
    /// outlives its screen is one way to draw that curve, and this one no
    /// longer can). Stopped first, so no frame is drawn
    /// half-empty, then the scene is dropped from the view and the
    /// coordinator; the figure, its ring and its aura go with the whole
    /// scene, as a torn-down battle's do — `VFXLibrary.dismiss` is for a node
    /// leaving a scene that goes on rendering, which this one does not.
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.rendersContinuously = false
        view.delegate = nil
        view.scene = nil
        coordinator.scene = nil
        coordinator.figure = nil
        coordinator.ring = nil
        coordinator.shadow = nil
        coordinator.cameraNode = nil
        coordinator.figureKey = ""
        coordinator.doctor.figure = nil
    }

    /// The figure for the unit, rebuilt only when the unit or its form changes.
    private func place(_ unit: ResolvedUnit?, in coordinator: Coordinator) {
        guard let scene = coordinator.scene else { return }
        let key = unit.map { "\($0.blueprint.id)|\($0.unit.isAwakened)" } ?? ""
        guard key != coordinator.figureKey else { return }
        coordinator.figureKey = key
        // An awakened figure carries a live aura: it leaves the way every
        // particle carrier does (`VFXLibrary.dismiss`: systems off, hidden
        // now, removed half a second of frames later), never freed with its
        // motes alive (2026-09-24).
        if let old = coordinator.figure { VFXLibrary.dismiss(old, reportsLive: false) }
        coordinator.ring?.removeFromParentNode()
        coordinator.shadow?.removeFromParentNode()
        coordinator.figure = nil
        guard let unit else { return }
        let blueprint = unit.blueprint
        let height = blueprint.model.height
        let tint = UIColor(hex: blueprint.element.accentHex) ?? .white

        let node = ModelLibrary.shared.node(
            for: blueprint.model,
            archetype: blueprint.archetype,
            element: blueprint.element,
            awakened: unit.unit.isAwakened
        )
        if unit.unit.isAwakened {
            node.addParticleSystem(VFXLibrary.aura(tint: tint, scale: height / 1.9))
        }
        node.eulerAngles.y = framing.stance + spin
        node.opacity = 0
        scene.rootNode.addChildNode(node)
        // The idle AFTER the figure is in the scene, through a player told
        // to play (`SCNNode.startLoop`): the first unit, placed before the
        // view's first frame, animated either way; a unit picked from the
        // rail afterwards is placed into a live scene, the case that froze
        // the Hall of Ka's figure (2026-09-17).
        // The clips of the mesh on the stage (`ModelLibrary.clipAsset`): an
        // awakened figure plays its own rig's idle, never the base rig's.
        let assetName = ModelLibrary.shared.clipAsset(for: blueprint.model, awakened: unit.unit.isAwakened)
        if let idle = ModelLibrary.shared.animation(.idle, for: assetName)
            ?? ModelLibrary.shared.animation(.idleCombat, for: assetName) {
            node.startLoop(idle, key: "idle")
        }
        node.runAction(.fadeIn(duration: 0.35))
        // The figure is the scene's one shadow caster; the ring, the shadow
        // patch and the set never cast (2026-09-18).
        FigureStageLighting.restrictShadows(in: scene, to: node)
        coordinator.figure = node
        coordinator.doctor.figure = node
        coordinator.figureHeight = height

        let ringRadius = max(1.2, height * 0.7)
        let ring = StageBuilder.runeRing(radius: CGFloat(ringRadius), tint: tint)
        scene.rootNode.addChildNode(ring)
        coordinator.ring = ring
        coordinator.ringRadius = ringRadius

        let size = CGFloat(height) * 0.75
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = SummonStageView.contactShadowImage
        material.writesToDepthBuffer = false
        plane.firstMaterial = material
        let shadow = SCNNode(geometry: plane)
        shadow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, 0.012, 0)
        shadow.renderingOrder = 5
        shadow.opacity = 0.75
        scene.rootNode.addChildNode(shadow)
        coordinator.shadow = shadow
        // A new height is a new framing.
        coordinator.framedFor = 0
    }

    /// Places the camera so the figure stands where the framing says — the
    /// right half of the collection's frame.
    ///
    /// The vertical lens makes the frame's height a known quantity: the
    /// figure is `fill` of it, the feet sit `down` of the way down, and the
    /// camera is shifted — not turned — so the figure's centre line stands
    /// `across` of the way across, the reveal's rising front. Solved again
    /// only when the viewport's shape, the figure or the framing changes.
    private func frameCamera(_ view: SCNView, _ coordinator: Coordinator) {
        guard let cameraNode = coordinator.cameraNode else { return }
        let bounds = view.bounds
        // The framing's own shape stands in until the first real layout —
        // for the collection, the stage of a notched phone in landscape.
        let aspect = bounds.height > 0 ? Float(bounds.width / bounds.height) : framing.firstAspect
        let framedFor = aspect * 1000 + coordinator.figureHeight
        guard abs(framedFor - coordinator.framedFor) > 0.01 || coordinator.framing != framing else { return }
        coordinator.framedFor = framedFor
        coordinator.framing = framing

        var fill = framing.fill
        if let byWidth = framing.fillByWidth {
            fill = min(fill, byWidth * aspect)
        }
        let visible = coordinator.figureHeight / fill
        let distance = visible / (2 * tan(Self.lens * .pi / 360))
        // The frame's centre is `down - 0.5` of a frame above the feet.
        let aimY = visible * (framing.down - 0.5)
        let halfWidth = visible * aspect / 2
        let x = halfWidth * (1 - 2 * framing.across)
        // A little above the aim and looking down at it, the way the hall's
        // painting looks down at its floor.
        cameraNode.position = SCNVector3(x, aimY + visible * 0.08, distance)
        cameraNode.look(at: SCNVector3(x, aimY, 0))

        // The ring on the feet's plane, which is the plane the frame is
        // solved on, so a metre there is `visible` over the frame's height:
        // the room is the distance from the centre line to the nearer edge,
        // `ringRoom` of it.
        if let room = framing.ringRoom, let ring = coordinator.ring, coordinator.ringRadius > 0 {
            let reach = min(framing.across, 1 - framing.across) * 2 * halfWidth * room
            let scale = min(1, max(0.1, reach / coordinator.ringRadius))
            ring.scale = SCNVector3(scale, scale, scale)
        }
    }
}

// MARK: - A unit's name, as the plates print it

extension ResolvedUnit {
    /// The name without its epithet ("Ares", not "Ares, Bane of Cities"), so
    /// a plate's or a strip's title is never cut: `UnitCard`'s rule. The
    /// collection's plates and the unit sheet's strip read it.
    var nameWithoutEpithet: String {
        name.split(separator: ",", maxSplits: 1).first.map { String($0) } ?? name
    }

    /// The ONE line under the name: an awakened name's own epithet when it
    /// has one ("Keeper of the Ash Road"), the family's otherwise ("of the
    /// Burning Sands"). The unit sheet's strip printed the awakened name
    /// whole over the family's epithet — two epithets stacked (run 216).
    var epithetUnderName: String {
        let parts = name.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return blueprint.epithet }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }
}
