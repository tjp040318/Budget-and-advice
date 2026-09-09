import SwiftUI

/// Every relic the account owns, with the tools the grind needs: filter by
/// slot and set, sort by what a role wants, sell the chaff in bulk, lock the
/// keepers, and open one to upgrade, reappraise or see who wears it.
struct RelicInventoryView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var slotFilter: Int?
    @State private var setFilter: RelicSet?
    @State private var role: CombatRole = .attacker
    @State private var sort: Sort = .efficiency
    @State private var hideEquipped = false
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var showSellConfirm = false
    @State private var opened: Relic?

    enum Sort: String, CaseIterable, Identifiable {
        case efficiency, grade, level, newest
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .efficiency: return "Efficiency"
            case .grade: return "Grade"
            case .level: return "Level"
            case .newest: return "Newest"
            }
        }
    }

    private let roles: [CombatRole] = [.attacker, .defender, .support, .controller, .hpTank]

    private var relics: [Relic] {
        var list = store.player.relics
        if let slotFilter { list = list.filter { $0.slot == slotFilter } }
        if let setFilter { list = list.filter { $0.set == setFilter } }
        if hideEquipped { list = list.filter { $0.equippedBy == nil } }
        switch sort {
        case .efficiency:
            list.sort { RelicService.efficiency($0, for: role) > RelicService.efficiency($1, for: role) }
        case .grade:
            list.sort { ($0.grade, $0.level) > ($1.grade, $1.level) }
        case .level:
            list.sort { ($0.level, $0.grade) > ($1.level, $1.grade) }
        case .newest:
            list.reverse()
        }
        return list
    }

    private var sellTotal: Int {
        selection.compactMap { store.player.relic($0) }.reduce(0) { $0 + RelicService.sellValue($1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    setSummary
                    filters
                    if relics.isEmpty {
                        EmptyState(
                            icon: "shield.slash",
                            title: "No relics here",
                            message: "Clear a stage or a hall floor; relics drop from both."
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(relics) { relic in
                                RelicRow(
                                    relic: relic,
                                    role: role,
                                    ownerName: ownerName(relic),
                                    isSelected: selection.contains(relic.id),
                                    selecting: selecting
                                ) {
                                    tap(relic)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .screen("Relics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        if !selecting { selection.removeAll() }
                    }
                    .font(Theme.body(13).weight(.semibold))
                    .foregroundStyle(Theme.gold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack(spacing: 12) {
                        Text("\(selection.count) selected")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        PrimaryButton(
                            title: "Sell for \(sellTotal)",
                            systemImage: "circle.hexagongrid.fill",
                            tint: Theme.danger,
                            isEnabled: !selection.isEmpty
                        ) {
                            showSellConfirm = true
                        }
                    }
                    .padding(12)
                    .background(Theme.ink)
                }
            }
            .confirmationDialog(
                "Sell \(selection.count) relics for \(sellTotal) drachma?",
                isPresented: $showSellConfirm,
                titleVisibility: .visible
            ) {
                Button("Sell", role: .destructive) {
                    if store.sellRelics(Array(selection)) != nil {
                        AudioLibrary.shared.play(.uiConfirm)
                    }
                    selection.removeAll()
                }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("Equipped relics come off their units first. Locked relics are never sold.")
            }
            .sheet(item: $opened) { relic in
                RelicDetailView(relicID: relic.id, role: role)
                    .environmentObject(store)
            }
        }
    }

    private func tap(_ relic: Relic) {
        if selecting {
            guard !relic.isLocked else {
                Juice.notify(.warning)
                return
            }
            if selection.contains(relic.id) {
                selection.remove(relic.id)
            } else {
                selection.insert(relic.id)
            }
        } else {
            opened = relic
        }
    }

    private func ownerName(_ relic: Relic) -> String? {
        relic.equippedBy.flatMap { store.resolved($0)?.name }
    }

    // MARK: - Sets

    /// How many pieces of each set the account holds, against what a set
    /// needs; a chip is a filter as well.
    private var setSummary: some View {
        let tally = Dictionary(grouping: store.player.relics, by: \.set).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sets", accessory: "\(store.player.relics.count) relics")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RelicSet.allCases) { set in
                        let count = tally[set] ?? 0
                        let complete = count >= set.piecesRequired
                        Button {
                            setFilter = setFilter == set ? nil : set
                        } label: {
                            HStack(spacing: 4) {
                                Text(set.displayName)
                                    .font(Theme.body(11).weight(.semibold))
                                Text("\(count)/\(set.piecesRequired)")
                                    .font(Theme.numeric(10))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(setFilter == set ? Theme.gold : (complete ? Theme.surfaceHigh : Theme.surface))
                            )
                            .foregroundStyle(setFilter == set ? Theme.ink : (complete ? Theme.textPrimary : Theme.textSecondary))
                        }
                    }
                }
            }
            if let setFilter {
                Text(setFilter.effectDescription)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .panelBackground()
    }

    // MARK: - Filters

    private var filters: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", on: slotFilter == nil) { slotFilter = nil }
                    ForEach(1...6, id: \.self) { slot in
                        chip("Slot \(slot)", on: slotFilter == slot) {
                            slotFilter = slotFilter == slot ? nil : slot
                        }
                    }
                    chip("Unequipped", on: hideEquipped) { hideEquipped.toggle() }
                }
            }
            HStack(spacing: 10) {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Role", selection: $role) {
                    ForEach(roles, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.gold)
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(12).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? Theme.gold : Theme.surfaceRaised))
                .foregroundStyle(on ? Theme.ink : Theme.textSecondary)
        }
    }
}

/// One relic in a list: grade, set, slot, level, the main stat, the subs,
/// who wears it, and how good it is for the role being sorted by.
struct RelicRow: View {
    let relic: Relic
    let role: CombatRole
    var ownerName: String? = nil
    var isSelected: Bool = false
    var selecting: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : (relic.isLocked ? "lock.fill" : "circle"))
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Theme.gold : Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        StarRow(stars: relic.grade, size: 9)
                        Text("\(relic.set.displayName) · Slot \(relic.slot)")
                            .font(Theme.body(12).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        if relic.level > 0 {
                            Text("+\(relic.level)")
                                .font(Theme.numeric(11))
                                .foregroundStyle(Theme.gold)
                        }
                        if relic.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text(relic.effectiveMainStat.displayText)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.gold)
                    Text(relic.subStats.map(\.displayText).joined(separator: "  ·  "))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    if let ownerName {
                        Text("Worn by \(ownerName)")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.info)
                    }
                }
                Spacer(minLength: 6)
                EfficiencyDial(value: RelicService.efficiency(relic, for: role))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(isSelected ? Theme.surfaceHigh : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(isSelected ? Theme.gold : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A ring that fills with the relic's efficiency, green past 70%.
struct EfficiencyDial: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.stroke, lineWidth: 3)
            Circle()
                .trim(from: 0, to: value)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))%")
                .font(Theme.numeric(9))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 40, height: 40)
    }

    private var tint: Color {
        value >= 0.7 ? Theme.success : (value >= 0.45 ? Theme.gold : Theme.textSecondary)
    }
}

/// One relic: its numbers, its wearer, and the four things you can do to it.
struct RelicDetailView: View {
    let relicID: UUID
    var role: CombatRole = .attacker

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var showSellConfirm = false
    @State private var showReappraiseConfirm = false

    private var relic: Relic? { store.player.relic(relicID) }

    var body: some View {
        NavigationStack {
            Group {
                if let relic {
                    ScrollView {
                        VStack(spacing: 14) {
                            header(relic)
                            stats(relic)
                            actions(relic)
                        }
                        .padding(16)
                    }
                    .screen("\(relic.set.displayName) Relic")
                } else {
                    EmptyState(icon: "shield.slash", title: "Sold", message: "This relic is gone.")
                        .onAppear { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                "Sell this relic for \(relic.map { RelicService.sellValue($0) } ?? 0) drachma?",
                isPresented: $showSellConfirm,
                titleVisibility: .visible
            ) {
                Button("Sell", role: .destructive) {
                    if store.sellRelics([relicID]) != nil {
                        AudioLibrary.shared.play(.uiConfirm)
                        dismiss()
                    }
                }
                Button("Keep it", role: .cancel) {}
            }
            .confirmationDialog(
                "Reappraise for \(relic.map { RelicService.reappraisalCost($0) } ?? 0) drachma?",
                isPresented: $showReappraiseConfirm,
                titleVisibility: .visible
            ) {
                Button("Reroll the sub stats") {
                    store.reappraiseRelic(relicID)
                    AudioLibrary.shared.play(.uiConfirm)
                }
                Button("Leave it", role: .cancel) {}
            } message: {
                Text("Every sub stat is rolled again from scratch. The main stat, the level, the set and the slot stay. There is no undo.")
            }
        }
    }

    private func header(_ relic: Relic) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                StarRow(stars: relic.grade, size: 12)
                Text("\(relic.set.displayName) · Slot \(relic.slot) · +\(relic.level)")
                    .font(Theme.title(17))
                    .foregroundStyle(Theme.textPrimary)
                Text(relic.set.effectDescription)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let wearer = relic.equippedBy.flatMap({ store.resolved($0)?.name }) {
                    Label("Worn by \(wearer)", systemImage: "person.fill")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.info)
                }
            }
            Spacer()
            VStack(spacing: 3) {
                EfficiencyDial(value: RelicService.efficiency(relic, for: role))
                Text(role.displayName)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .panelBackground()
    }

    private func stats(_ relic: Relic) -> some View {
        let stats = relic.allStats
        return VStack(spacing: 7) {
            SectionHeader(title: "Stats", accessory: relic.isMaxLevel ? "Max" : "\(relic.maxLevel - relic.level) levels to go")
            ForEach(stats.indices, id: \.self) { index in
                let modifier = stats[index]
                HStack {
                    Text(modifier.kind.displayName)
                        .font(Theme.body(12))
                        .foregroundStyle(index == 0 ? Theme.gold : Theme.textSecondary)
                    Spacer()
                    Text("+\(modifier.kind.format(modifier.value))")
                        .font(Theme.numeric(12))
                        .foregroundStyle(index == 0 ? Theme.gold : Theme.textPrimary)
                }
            }
        }
        .padding(12)
        .panelBackground()
    }

    private func actions(_ relic: Relic) -> some View {
        let upgradeCost = RelicService.upgradeCost(grade: relic.grade, level: relic.level)
        let canUpgrade = !relic.isMaxLevel && store.player.wallet.drachma >= upgradeCost
        let canReappraise = relic.level >= RelicService.reappraisalMinimumLevel
            && store.player.wallet.drachma >= RelicService.reappraisalCost(relic)
        return VStack(spacing: 10) {
            PrimaryButton(
                title: relic.isMaxLevel ? "Upgrade — max" : "Upgrade — \(upgradeCost) drachma",
                systemImage: "arrow.up.circle.fill",
                isEnabled: canUpgrade
            ) {
                store.upgradeRelic(relicID)
                AudioLibrary.shared.play(.uiTap)
            }
            PrimaryButton(
                title: relic.level >= RelicService.reappraisalMinimumLevel
                    ? "Reappraise — \(RelicService.reappraisalCost(relic)) drachma"
                    : "Reappraise — from +\(RelicService.reappraisalMinimumLevel)",
                systemImage: "arrow.triangle.2.circlepath",
                tint: Theme.info,
                isEnabled: canReappraise
            ) {
                showReappraiseConfirm = true
            }
            HStack(spacing: 10) {
                Button {
                    store.toggleRelicLock(relicID)
                    AudioLibrary.shared.play(.uiTap)
                } label: {
                    Label(relic.isLocked ? "Unlock" : "Lock", systemImage: relic.isLocked ? "lock.open.fill" : "lock.fill")
                        .font(Theme.body(13).weight(.semibold))
                        .foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.panel(Theme.tightCorner))
                }
                if let wearer = relic.equippedBy {
                    Button {
                        store.unequip(slot: relic.slot, from: wearer)
                    } label: {
                        Label("Unequip", systemImage: "minus.circle")
                            .font(Theme.body(13).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.panel(Theme.tightCorner))
                    }
                }
                Button {
                    showSellConfirm = true
                } label: {
                    Label("Sell \(RelicService.sellValue(relic))", systemImage: "circle.hexagongrid.fill")
                        .font(Theme.body(13).weight(.semibold))
                        .foregroundStyle(relic.isLocked ? Theme.textSecondary : Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.panel(Theme.tightCorner))
                }
                .disabled(relic.isLocked)
            }
        }
    }
}

/// Picks a relic for one of a unit's slots: everything that fits the slot,
/// best for the unit's role first, with who is wearing it now.
struct RelicPickerView: View {
    let unitID: UUID
    let slot: Int

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    private var role: CombatRole { store.resolved(unitID)?.role ?? .attacker }

    private var candidates: [Relic] {
        let role = self.role
        return store.player.relics
            .filter { $0.slot == slot && $0.equippedBy != unitID }
            .sorted { RelicService.score($0, for: role) > RelicService.score($1, for: role) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    if candidates.isEmpty {
                        EmptyState(
                            icon: "shield.slash",
                            title: "Nothing fits slot \(slot)",
                            message: "Relics for this slot drop from the campaign and the halls."
                        )
                    }
                    ForEach(candidates) { relic in
                        RelicRow(
                            relic: relic,
                            role: role,
                            ownerName: relic.equippedBy.flatMap { store.resolved($0)?.name }
                        ) {
                            store.equip(relicID: relic.id, on: unitID)
                            AudioLibrary.shared.play(.uiConfirm)
                            dismiss()
                        }
                    }
                }
                .padding(16)
            }
            .screen("Slot \(slot)")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
