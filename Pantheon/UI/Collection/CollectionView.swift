import SwiftUI

/// The roster: everything you own, with filters and sorting.
struct CollectionView: View {
    @EnvironmentObject private var store: GameStore
    @State private var elementFilter: Element?
    @State private var gradeFilter: Int?
    @State private var sort: SortOrder = .power
    @State private var selected: ResolvedUnit?
    @State private var showTraining = false
    @State private var showRelics = false

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
        // empty check and the grid all want the same answer: work it out once
        // per pass rather than three times.
        let list = units

        NavigationStack {
            GameScreen("Collection", subtitle: subtitle(showing: list.count)) {
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
                BarButton(title: "Train", systemImage: "arrow.up.circle.fill") {
                    showTraining = true
                }
                BarButton(title: "Relics", systemImage: "shield.lefthalf.filled") {
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
                    grid(list)
                }
            }
            .sheet(item: $selected) { unit in
                UnitDetailView(unitID: unit.id)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showRelics) {
                RelicInventoryView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showTraining) {
                TrainingView()
                    .environmentObject(store)
            }
        }
    }

    private func subtitle(showing count: Int) -> String {
        let total = store.player.units.count
        return count == total ? "\(count) units" : "\(count) of \(total)"
    }

    // MARK: - The grid

    private let gap: CGFloat = 6
    private let gridPadding: CGFloat = 6
    /// The smallest card worth drawing: under this the name stops reading even
    /// at `minimumScaleFactor`. Both the column count and the card width are
    /// held to it.
    private let minimumCard: CGFloat = 56
    /// What `UnitCard` draws under the tile: the name over the level line.
    /// Held here only to size the grid — if the card's footer changes height,
    /// change this with it.
    private let cardFooter: CGFloat = 28

    /// The grid owns the whole frame now that the filters live in the strip,
    /// and the cards are cut to the column rather than floating in it: what
    /// the width does not spend on a card is spent on another card, not left
    /// as gutter. The column count is read off the height so three rows of
    /// them stand in a landscape frame — thirty units at a glance, where the
    /// old adaptive grid showed sixteen with a dead band down each side.
    private func grid(_ list: [ResolvedUnit]) -> some View {
        GeometryReader { geo in
            let count = columnCount(in: geo.size)
            let card = cardWidth(in: geo.size, columns: count)
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(card), spacing: gap), count: count),
                    spacing: gap
                ) {
                    ForEach(list) { unit in
                        Button {
                            Juice.haptic(.light)
                            selected = unit
                        } label: {
                            UnitCard(unit: unit, size: card)
                        }
                        .buttonStyle(PlateButtonStyle())
                    }
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, gridPadding)
            }
        }
    }

    /// The width the cards have to share: the frame less the padding the strip
    /// above already uses. A non-finite proposal is treated as nothing, because
    /// the column count is an `Int(_:)` of this and `Int(nan)` traps rather
    /// than returning zero.
    private func gridSpan(in size: CGSize) -> CGFloat {
        let width = size.width.isFinite ? size.width : 0
        return max(80, width - ScreenChrome.contentPadding * 2)
    }

    private func columnCount(in size: CGSize) -> Int {
        let span = gridSpan(in: size)
        let height = size.height.isFinite ? size.height : 0
        let usable = max(80, height - gridPadding * 2)
        // The widest card that still leaves three rows in the frame, the
        // card's own footer counted in.
        let byHeight = (usable - gap * 2) / 3 - cardFooter
        let target = min(max(byHeight, minimumCard), 96)
        // Rounded up, so the card the width divides into is no taller than
        // the height allows: too wide a card costs a whole row.
        let wanted = max(4, Int(((span + gap) / (target + gap)).rounded(.up)))
        // ...but never more columns than the width holds at the smallest card.
        // These are `.fixed` columns: one too many and the row lays out wider
        // than the frame rather than wrapping, which is what the first pass —
        // proposed a zero size before the frame is known — would draw.
        let fits = max(1, Int((span + gap) / (minimumCard + gap)))
        return min(wanted, fits)
    }

    private func cardWidth(in size: CGSize, columns: Int) -> CGFloat {
        let width = (gridSpan(in: size) - gap * CGFloat(columns - 1)) / CGFloat(columns)
        return max(minimumCard, width.rounded(.down))
    }
}
