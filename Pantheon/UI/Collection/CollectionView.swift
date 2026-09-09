import SwiftUI

/// The roster: everything you own, with filters and sorting.
struct CollectionView: View {
    @EnvironmentObject private var store: GameStore
    @State private var elementFilter: Element?
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
        switch sort {
        case .power: list.sort { $0.power > $1.power }
        case .level: list.sort { $0.level > $1.level }
        case .stars: list.sort { ($0.stars, $0.level) > ($1.stars, $1.level) }
        case .recent: list.sort { $0.unit.acquiredAt > $1.unit.acquiredAt }
        case .name: list.sort { $0.name < $1.name }
        }
        return list
    }

    /// As many 100-point cards as the width holds: six across a landscape
    /// phone, more on an iPad, rather than three stretched columns.
    private let columns = [GridItem(.adaptive(minimum: 76, maximum: 88), spacing: 8)]

    var body: some View {
        NavigationStack {
            GameScreen("Collection", subtitle: "\(store.player.units.count) units") {
                ElementFilterTiles(selection: $elementFilter)
                BarMenu(label: "Sort", value: sort.displayName) {
                    ForEach(SortOrder.allCases) { order in
                        Button(order.displayName) { sort = order }
                    }
                }
                BarButton(title: "Train", systemImage: "arrow.up.circle.fill") {
                    showTraining = true
                }
                BarButton(title: "Relics", systemImage: "shield.lefthalf.filled") {
                    showRelics = true
                }
            } content: {
                if units.isEmpty {
                    EmptyState(
                        icon: "person.3",
                        title: "Nothing here",
                        message: "Summon at the circle, or clear a stage and come back."
                    )
                } else {
                    // The grid owns the whole frame now that the filters live
                    // in the strip: three rows of ten on a landscape phone,
                    // where the old layout showed one row of eight.
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(units) { unit in
                                Button {
                                    Juice.haptic(.light)
                                    selected = unit
                                } label: {
                                    UnitCard(unit: unit, size: 76)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 8)
                    }
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

}
