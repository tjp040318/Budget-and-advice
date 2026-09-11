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
///   four combat stats with what the relics add, then the six relic slots as
///   a 3×2 of the unit sheet's own tiles with the sets they complete beside
///   them, and Full sheet / Train at the foot. The genre's side panel in the
///   game's own marble and bronze rather than a copy of anyone's.
/// - **Stage**: the roster as a rail of small cards along the bottom, the
///   picked unit's real model standing on a rune ring in the right half of
///   the summoning hall's painting (`CollectionStageView`, the Hall of Ka's
///   trick), turned by a drag across that half, and the same words and slots
///   in a plate over the left half — "maybe we do that stuff on the left
///   side, not to copy Summoners War".
///
/// Both share the selection and the sheets: a slot opens the relic picker for
/// that slot, Full sheet opens the unit sheet as a tap used to, and Train
/// opens the Hall of Ka on the unit.
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
    @State private var showTraining = false
    @State private var showRelics = false
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

    /// A slot on a unit, for the picker sheet: the slot is the identity, the
    /// unit is who wears it.
    struct SlotPick: Identifiable {
        let id: Int
        let unitID: UUID
    }

    /// The layout switch as the strip's segments.
    private var layouts: [(value: CollectionLayout, title: String)] {
        CollectionLayout.allCases.map { (value: $0, title: $0.title) }
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
                BarSegments(options: layouts, selection: $layout)
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
            .sheet(item: $fullSheet) { pick in
                UnitDetailView(unitID: pick.id)
                    .environmentObject(store)
            }
            .sheet(item: $pickingSlot) { pick in
                RelicPickerView(unitID: pick.unitID, slot: pick.id)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showRelics) {
                RelicInventoryView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showTraining) {
                TrainingView(selectedUnitID: selectedID)
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
        ModelLibrary.shared.warm(list.prefix(6).map(\.blueprint.model), crowded: false, clips: false)
    }

    // MARK: - Cards: the grid and the plate beside it

    private let gap: CGFloat = 6
    private let gridPadding: CGFloat = 6
    /// How much of the width the grid keeps; the plate takes the rest. A
    /// little over half, because the grid is the list and the plate is one
    /// unit's worth of words: at 55% of an iPhone 16 Pro's frame the grid is
    /// six columns of 69-point cards, three rows of them in view.
    private let gridShare: CGFloat = 0.55
    private let columnGap: CGFloat = 8
    /// The smallest card worth drawing: under this the name stops reading even
    /// at `minimumScaleFactor`. Both the column count and the card width are
    /// held to it.
    private let minimumCard: CGFloat = 56
    /// What `UnitCard` draws under the tile: the name over the level line.
    /// Held here only to size the grid — if the card's footer changes height,
    /// change this with it.
    private let cardFooter: CGFloat = 28

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
                        .buttonStyle(PlateButtonStyle())
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
                .padding(.bottom, gridPadding)
            }
        }
    }

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

    private static let portraitSize: CGFloat = 110
    /// The relic tiles, in both layouts. Smaller than the sheet's 60 because
    /// a plate that shares a frame with a grid or a stage has 118 points for
    /// two rows of them, not a column of its own.
    private static let slotSize: CGFloat = 52
    private static let slotGap: CGFloat = 6
    /// What the painted panel's last row has to clear at the bottom: its
    /// corner ornament reaches 17 points up, against the band's 8 (the unit
    /// sheet's `panelBottomInset`, measured there).
    private static let plateBottomInset: CGFloat = 18

    /// The Cards layout's right side: the portrait and the words over the
    /// slots, the sets they complete beside them, the two actions at the foot.
    ///
    /// One frame, no scroll, so the heights are written down. A tabbed
    /// iPhone 16 Pro in landscape gives the content 315 points; less the
    /// layout's 12 of padding and the panel's 26 of inset, 277 inside. The
    /// top block is 128 (the words, beside a 110 portrait), the divider row
    /// 17, the slot rows 110: 255, with the bottom row stretching to put the
    /// buttons on the panel's foot whatever is left.
    private func detailPlate(_ unit: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                portrait(unit)
                words(unit)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider().overlay(Theme.stroke)
            HStack(alignment: .top, spacing: 10) {
                slotGrid(unit)
                VStack(alignment: .leading, spacing: 5) {
                    Text("RELIC SETS · \(unit.relics.count)/6 WORN")
                        .font(Theme.body(8).weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(Theme.goldDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    setSummary(unit)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        footButton("Full sheet", "rectangle.expand.vertical", tint: Theme.gold) {
                            fullSheet = UnitPick(id: unit.id)
                        }
                        footButton("Train", "arrow.up.circle.fill", tint: Theme.info) {
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

    /// The card's art in its grade's metal, without the card's caption: the
    /// words stand beside it here.
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
        .overlay(alignment: .topTrailing) {
            if unit.unit.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .shadow(color: .black, radius: 2)
                    .padding(6)
            }
        }
        .overlay(paintedFrame(rarity))
        .rarityFrame(rarity, radius: Theme.tightCorner)
        // A painting scaled to fill overhangs its frame, and `clipShape` does
        // not clip hit-testing: without this it takes the taps meant for the
        // words beside it.
        .allowsHitTesting(false)
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

    /// Name and power, epithet, element and grade, the level bar, and the
    /// four combat stats in two columns. The same block in both layouts.
    private func words(_ unit: ResolvedUnit) -> some View {
        // `grantExperience` zeroes the stored experience at the cap, so a
        // maxed unit's bar would read "0 / 1400" under a full level — the
        // unit sheet's fix: fill it and say MAX.
        let toNextLevel = Double(ProgressionService.experienceForNextLevel(
            level: unit.level, stars: unit.stars
        ))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(unit.name)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                Text("\(unit.power)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.gold)
                Text("POWER")
                    .font(Theme.body(7).weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(unit.blueprint.epithet)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(spacing: 6) {
                ElementBadge(element: unit.element)
                StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars, size: 10)
                Spacer(minLength: 0)
            }
            StatBar(
                value: unit.unit.isMaxLevel ? toNextLevel : Double(unit.unit.experience),
                maximum: toNextLevel,
                tint: unit.unit.isMaxLevel ? Theme.gold : Theme.info,
                height: 5,
                label: unit.unit.isMaxLevel
                    ? "Lv.\(unit.level) · MAX"
                    : "Lv.\(unit.level) / \(unit.unit.maxLevel)"
            )
            coreStats(unit)
        }
    }

    /// HP, ATK, DEF and SPD, each the total over its name with the relics'
    /// share beside it. Base is grade, level and awakening; the difference to
    /// the final number is the six slots, shown the way the genre shows it so
    /// equipping a relic is visible here and not only in battle.
    private func coreStats(_ unit: ResolvedUnit) -> some View {
        let base = ProgressionService.baseStats(for: unit.unit, blueprint: unit.blueprint)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                statCell("HP", base.hp, unit.stats.hp)
                statCell("DEF", base.def, unit.stats.def)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                statCell("ATK", base.atk, unit.stats.atk)
                statCell("SPD", base.spd, unit.stats.spd)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statCell(_ label: String, _ base: Double, _ total: Double) -> some View {
        let bonus = total - base
        return VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(Theme.body(8).weight(.black))
                .tracking(0.5)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(UnitDetailView.statText(total, percent: false))
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if abs(bonus) >= 0.5 {
                    Text((bonus > 0 ? "+" : "−") + UnitDetailView.statText(abs(bonus), percent: false))
                        .font(Theme.numeric(9))
                        .foregroundStyle(bonus > 0 ? Theme.success : Theme.danger)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The six slots as two rows of three, 1–3 over 4–6, in the unit sheet's
    /// own tiles. A tap opens the picker for that slot, worn or empty: the
    /// picker shows the relic there now beside the one picked, so it is the
    /// right screen for a change as well as for a first fit.
    private func slotGrid(_ unit: ResolvedUnit) -> some View {
        VStack(spacing: Self.slotGap) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: Self.slotGap) {
                    ForEach(1...3, id: \.self) { column in
                        let slot = row * 3 + column
                        RelicSlotTile(
                            slot: slot,
                            relic: unit.unit.equippedRelics[slot].flatMap { store.player.relic($0) },
                            size: Self.slotSize
                        ) {
                            Juice.haptic(.light)
                            pickingSlot = SlotPick(id: slot, unitID: unit.id)
                        }
                    }
                }
            }
        }
        // The slot badge hangs four points up and left of each tile; the
        // plate's inset is what it hangs over.
        .padding(.top, 2)
    }

    /// The sets the worn relics complete, in a line: "Fury ×2 · Guard".
    private func setSummary(_ unit: ResolvedUnit) -> some View {
        let sets = unit.activeRelicSets
        return Group {
            if sets.isEmpty {
                Text(unit.relics.isEmpty
                     ? "Nothing worn · tap a slot to fit a relic"
                     : "No set complete · 2 pieces for a stat, 4 for an effect")
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(sets.map { entry in
                    entry.completions > 1
                        ? "\(entry.set.displayName) ×\(entry.completions)"
                        : entry.set.displayName
                }.joined(separator: " · "))
                    .font(Theme.body(9).weight(.bold))
                    .foregroundStyle(Theme.gold)
            }
        }
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A small plate of a button: a glyph and a word on the tint, control
    /// height, the pair dividing their row.
    private func footButton(
        _ title: String, _ symbol: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .black))
                Text(title)
                    .font(Theme.body(10).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(tint)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlateButtonStyle())
    }

    // MARK: - Stage: the rail, the figure and the plate

    private static let railCard: CGFloat = 60
    private static let railPadding: CGFloat = 3
    /// The rail is one card and its caption tall, plus its plate's padding:
    /// 93 points at a 60-point card.
    private static var railHeight: CGFloat { Theme.cardHeight(for: railCard) + railPadding * 2 }
    /// Radians of turn per point of drag: one full turn across a landscape
    /// phone's width, which is what a finger expects of a turntable.
    private static let spinPerPoint: CGFloat = .pi * 2 / 800

    /// The stage under everything, the plate over its left half, the drag
    /// over its right, and the rail along the bottom.
    ///
    /// The heights, since nothing here scrolls but the rail: a tabbed iPhone
    /// 16 Pro in landscape gives the content 315 points; less 12 of padding,
    /// the rail's 93 and the 6 between, the stage is 204 tall. The plate is
    /// the words beside the slots rather than over them — 149 — because the
    /// two stacked would be 281 and would run under the rail.
    private func stageLayout(_ list: [ResolvedUnit], selected: ResolvedUnit) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    CollectionStageView(unit: selected, spin: Float((spinBase + spinDrag) * Self.spinPerPoint))
                        .allowsHitTesting(false)
                    HStack(alignment: .top, spacing: 0) {
                        stagePlate(selected)
                            .frame(width: (geo.size.width.isFinite ? geo.size.width : 0) * 0.5, alignment: .topLeading)
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
                            .overlay(alignment: .bottom) {
                                Text("DRAG TO TURN")
                                    .font(Theme.body(8).weight(.black))
                                    .tracking(1.2)
                                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                    .padding(.bottom, 4)
                                    .allowsHitTesting(false)
                            }
                    }
                }
            }
            stageRail(list, selected: selected)
        }
        .padding(.horizontal, ScreenChrome.contentPadding)
        .padding(.vertical, 6)
        .background(stagePainting)
        .onChange(of: selected.id) { _, _ in
            // A new figure is met face on.
            spinBase = 0
            spinDrag = 0
        }
    }

    /// The words and the slots over the left half, on a translucent plate so
    /// the hall shows through, as the Hall of Ka's own plate does.
    private func stagePlate(_ unit: ResolvedUnit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            words(unit)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 5) {
                slotGrid(unit)
                setSummary(unit)
                    .frame(width: Self.slotSize * 3 + Self.slotGap * 2)
            }
        }
        .padding(10)
        // Cream, as every plate over a painting is since the palette turned:
        // the words are ink, and ink on a dark plate is what the black UI
        // was. Opaque enough for the numbers to read over the hall's floor.
        .background(
            Theme.plate.opacity(0.84),
            in: RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        )
    }

    /// The roster as a rail of small cards along the bottom, the picked one
    /// lit and kept in view.
    private func stageRail(_ list: [ResolvedUnit], selected: ResolvedUnit) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(list) { unit in
                        Button {
                            Juice.haptic(.light)
                            selectedID = unit.id
                        } label: {
                            // As in the grid: the portrait overhangs the card,
                            // so the tap belongs to the card's rectangle.
                            UnitCard(unit: unit, isSelected: unit.id == selected.id, size: Self.railCard)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(unit.id)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, Self.railPadding)
            }
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
        .background(
            Theme.plate.opacity(0.5),
            in: RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        )
    }

    /// The summoning hall behind the stage, the size of the frame and never
    /// larger.
    ///
    /// A `.background`, never a sibling: a fill-aspect painting under an
    /// unbounded frame reports its own size and grows every ancestor with it
    /// — the mistake that emptied the dungeon screen's frames. Off a
    /// GeometryReader with a fixed frame it can measure nothing, and it
    /// takes no taps, because `.clipped()` does not clip hit-testing.
    private var stagePainting: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.surface
                if BundleImage.exists("summon_hall_bg") {
                    BundleImage(name: "summon_hall_bg")
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                // Softer under the plate, so its words read, and the
                // painting's own vignette carried to the edges.
                LinearGradient(colors: [Theme.plate.opacity(0.35), .clear, .clear],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .allowsHitTesting(false)
    }
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
struct CollectionStageView: UIViewRepresentable {
    let unit: ResolvedUnit?
    /// The turn about Y, in radians, on top of the stance.
    let spin: Float

    /// Where the figure stands: its centre line 72% of the way across the
    /// frame, its feet 78% of the way down, and 70% of the height tall. The
    /// left half is the plate's; the figure has the right, with room over its
    /// head for the tallest family and under its feet for the ring.
    private static let across: Float = 0.72
    private static let down: Float = 0.78
    private static let fill: Float = 0.70
    private static let lens: Float = 30
    /// The stance before any drag: a three-quarter turn toward the words on
    /// the left — the altar's `-0.3` mirrored, its panel being on the right.
    private static let stance: Float = 0.3

    final class Coordinator {
        var scene: SCNScene?
        var figure: SCNNode?
        var figureKey = ""
        var figureHeight: Float = 1.9
        var ring: SCNNode?
        var shadow: SCNNode?
        var cameraNode: SCNNode?
        var framedFor: Float = 0
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
        // The drag is a SwiftUI gesture over the view, not the view's own.
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        coordinator.scene = scene

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.lens)
        camera.projectionDirection = .vertical
        camera.zNear = 0.5
        camera.zFar = 100
        camera.wantsHDR = true
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
        let key = SCNLight()
        key.type = .directional
        key.intensity = 820
        key.color = UIColor(hex: "#FFE8C2") ?? .white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-1.0, -0.3, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 280
        fill.color = UIColor(hex: "#7C93D6") ?? .white
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.4, 0.9, 0)
        scene.rootNode.addChildNode(fillNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 480
        rim.color = UIColor(hex: "#FFD36A") ?? .yellow
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.5, 2.7, 0)
        scene.rootNode.addChildNode(rimNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 190
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

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
        coordinator.figure?.eulerAngles.y = Self.stance + spin
    }

    /// The figure for the unit, rebuilt only when the unit or its form changes.
    private func place(_ unit: ResolvedUnit?, in coordinator: Coordinator) {
        guard let scene = coordinator.scene else { return }
        let key = unit.map { "\($0.blueprint.id)|\($0.unit.isAwakened)" } ?? ""
        guard key != coordinator.figureKey else { return }
        coordinator.figureKey = key
        coordinator.figure?.removeFromParentNode()
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
        let assetName = blueprint.model.assetName
        if let idle = ModelLibrary.shared.animation(.idle, for: assetName)
            ?? ModelLibrary.shared.animation(.idleCombat, for: assetName) {
            node.addAnimation(idle, forKey: "idle")
        }
        node.eulerAngles.y = Self.stance + spin
        node.opacity = 0
        scene.rootNode.addChildNode(node)
        node.runAction(.fadeIn(duration: 0.35))
        coordinator.figure = node
        coordinator.figureHeight = height

        let ring = StageBuilder.runeRing(radius: CGFloat(max(1.2, height * 0.7)), tint: tint)
        scene.rootNode.addChildNode(ring)
        coordinator.ring = ring

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

    /// Places the camera so the figure stands in the right half of the frame.
    ///
    /// The vertical lens makes the frame's height a known quantity: the
    /// figure is `fill` of it, the feet sit `down` of the way down, and the
    /// camera is shifted — not turned — so the figure's centre line stands
    /// `across` of the way across, the reveal's rising front. Solved again
    /// only when the viewport's shape or the figure changes.
    private func frameCamera(_ view: SCNView, _ coordinator: Coordinator) {
        guard let cameraNode = coordinator.cameraNode else { return }
        let bounds = view.bounds
        // The stage of a notched phone in landscape stands in until the
        // first real layout.
        let phoneAspect: Float = 736 / 204
        let aspect = bounds.height > 0 ? Float(bounds.width / bounds.height) : phoneAspect
        let framedFor = aspect * 1000 + coordinator.figureHeight
        guard abs(framedFor - coordinator.framedFor) > 0.01 else { return }
        coordinator.framedFor = framedFor

        let visible = coordinator.figureHeight / Self.fill
        let distance = visible / (2 * tan(Self.lens * .pi / 360))
        // The frame's centre is `down - 0.5` of a frame above the feet.
        let aimY = visible * (Self.down - 0.5)
        let halfWidth = visible * aspect / 2
        let x = halfWidth * (1 - 2 * Self.across)
        // A little above the aim and looking down at it, the way the hall's
        // painting looks down at its floor.
        cameraNode.position = SCNVector3(x, aimY + visible * 0.08, distance)
        cameraNode.look(at: SCNVector3(x, aimY, 0))
    }
}
