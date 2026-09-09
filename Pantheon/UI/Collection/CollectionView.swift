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
    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 124), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    filterBar

                    if units.isEmpty {
                        EmptyState(
                            icon: "person.3",
                            title: "Nothing here",
                            message: "Summon at the circle, or clear a stage and come back."
                        )
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(units) { unit in
                                Button {
                                    selected = unit
                                } label: {
                                    UnitCard(unit: unit, size: 100)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .screen("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTraining = true
                    } label: {
                        Label("Train", systemImage: "arrow.up.circle.fill")
                            .font(Theme.body(13).weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Text("\(store.player.units.count) units")
                            .font(Theme.numeric(12))
                            .foregroundStyle(Theme.textSecondary)
                        Button {
                            showRelics = true
                        } label: {
                            Label("Relics", systemImage: "shield.lefthalf.filled")
                                .font(Theme.body(13).weight(.semibold))
                                .foregroundStyle(Theme.gold)
                        }
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

    private var filterBar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    filterChip(title: "All", isOn: elementFilter == nil, tint: Theme.gold) {
                        elementFilter = nil
                    }
                    ForEach(Element.allCases) { element in
                        filterChip(
                            title: element.displayName,
                            isOn: elementFilter == element,
                            tint: element.color
                        ) {
                            elementFilter = elementFilter == element ? nil : element
                        }
                    }
                }
            }

            HStack {
                Text("Sort")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                Picker("Sort", selection: $sort) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func filterChip(title: String, isOn: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(12).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? tint : Theme.surfaceRaised))
                .foregroundStyle(isOn ? Theme.ink : Theme.textSecondary)
        }
    }
}
