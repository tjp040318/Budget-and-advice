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
                VStack(spacing: 10) {
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
                .padding(12)
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
        let tally = Dictionary(grouping: store.player.relics, by: { $0.set }).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sets", accessory: "\(store.player.relics.count) relics")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RelicSet.allCases) { relicSet in
                        let count = tally[relicSet] ?? 0
                        let complete = count >= relicSet.piecesRequired
                        let selected = setFilter == relicSet
                        Button {
                            setFilter = selected ? nil : relicSet
                        } label: {
                            HStack(spacing: 4) {
                                Text(relicSet.displayName)
                                    .font(Theme.body(11).weight(.semibold))
                                Text("\(count)/\(relicSet.piecesRequired)")
                                    .font(Theme.numeric(10))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selected ? Theme.gold : (complete ? Theme.surfaceHigh : Theme.surface))
                            )
                            .foregroundStyle(selected ? Theme.ink : (complete ? Theme.textPrimary : Theme.textSecondary))
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
                        VStack(spacing: 10) {
                            header(relic)
                            stats(relic)
                            actions(relic)
                        }
                        .padding(12)
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
/// Choosing a relic for one slot, the way the genre's rune screen does it:
/// the candidates on the left, best fit for the role first, and on the right
/// what the pick would do — every stat before and after, the sets it
/// completes or breaks — before anything is equipped.
struct RelicPickerView: View {
    let unitID: UUID
    let slot: Int

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var freeOnly = false

    private var unit: ResolvedUnit? { store.resolved(unitID) }
    private var role: CombatRole { unit?.role ?? .attacker }
    private var current: Relic? { unit?.unit.equippedRelics[slot].flatMap { store.player.relic($0) } }

    private var candidates: [Relic] {
        let role = self.role
        return store.player.relics
            .filter { $0.slot == slot && $0.equippedBy != unitID && (!freeOnly || $0.equippedBy == nil) }
            .sorted { RelicService.score($0, for: role) > RelicService.score($1, for: role) }
    }

    /// The tapped relic, or the best fit until one is tapped.
    private var selected: Relic? {
        if let selectedID, let relic = candidates.first(where: { $0.id == selectedID }) { return relic }
        return candidates.first
    }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 10) {
                list
                    .frame(maxWidth: .infinity)
                comparison
                    .frame(width: 300)
            }
            .padding(10)
            .screen("Slot \(slot) · \(unit?.name ?? "")")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - The candidates

    private var list: some View {
        VStack(spacing: 6) {
            HStack {
                Text(candidates.isEmpty ? "Nothing for this slot" : "\(candidates.count) for slot \(slot) · best fit for a \(role.displayName.lowercased()) first")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    freeOnly.toggle()
                } label: {
                    Text(freeOnly ? "Free only" : "All")
                        .font(Theme.body(10).weight(.semibold))
                        .foregroundStyle(freeOnly ? Theme.ink : Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(freeOnly ? Theme.gold : Theme.surface))
                }
            }
            ScrollView {
                VStack(spacing: 6) {
                    if candidates.isEmpty {
                        EmptyState(
                            icon: "shield.slash",
                            title: "Nothing fits slot \(slot)",
                            message: "Relics for this slot drop from the campaign and the Labyrinth on the island."
                        )
                    }
                    ForEach(candidates) { relic in
                        RelicRow(
                            relic: relic,
                            role: role,
                            ownerName: relic.equippedBy.flatMap { store.resolved($0)?.name },
                            isSelected: selected?.id == relic.id
                        ) {
                            Juice.haptic(.light)
                            selectedID = relic.id
                        }
                    }
                }
            }
        }
    }

    // MARK: - Before and after

    private var comparison: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Now", accessory: current.map { "\($0.set.displayName) +\($0.level)" } ?? "Empty")
                if let current {
                    relicSummary(current)
                } else {
                    Text("Nothing in slot \(slot).")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let selected {
                    SectionHeader(title: "If equipped", accessory: "\(selected.set.displayName) +\(selected.level)")
                    relicSummary(selected)
                    deltaTable(selected)
                    PrimaryButton(
                        title: selected.equippedBy == nil ? "Equip" : "Take and equip",
                        systemImage: "checkmark.circle.fill"
                    ) {
                        store.equip(relicID: selected.id, on: unitID)
                        AudioLibrary.shared.play(.uiConfirm)
                        dismiss()
                    }
                }
                if current != nil {
                    Button {
                        store.unequip(slot: slot, from: unitID)
                        AudioLibrary.shared.play(.uiTap)
                        dismiss()
                    } label: {
                        Text("Unequip what is there")
                            .font(Theme.body(11).weight(.semibold))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(10)
            .panelBackground(radius: Theme.tightCorner)
        }
    }

    private func relicSummary(_ relic: Relic) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                StarRow(stars: relic.grade, size: 8)
                Image(systemName: relic.set.glyph)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text(relic.effectiveMainStat.displayText)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.gold)
                Spacer()
                if let owner = relic.equippedBy.flatMap({ store.resolved($0)?.name }), relic.equippedBy != unitID {
                    Text("worn by \(owner)")
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.info)
                }
            }
            Text(relic.subStats.map(\.displayText).joined(separator: "  ·  "))
                .font(Theme.body(9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The unit's sheet with `relic` in the slot instead of what is there.
    private func resolvedWith(_ relic: Relic) -> ResolvedUnit? {
        guard let unit else { return nil }
        var equipped = unit.relics.filter { $0.slot != slot }
        equipped.append(relic)
        return ProgressionService.resolve(unit.unit, blueprint: unit.blueprint, equipped: equipped)
    }

    private func deltaTable(_ relic: Relic) -> some View {
        let before = unit?.stats ?? Stats.zero
        let after = resolvedWith(relic)?.stats ?? before
        let rows: [(label: String, before: Double, after: Double, percent: Bool)] = [
            ("HP", before.hp, after.hp, false),
            ("ATK", before.atk, after.atk, false),
            ("DEF", before.def, after.def, false),
            ("SPD", before.spd, after.spd, false),
            ("CRIT Rate", before.critRate, after.critRate, true),
            ("CRIT DMG", before.critDamage, after.critDamage, true),
            ("Accuracy", before.accuracy, after.accuracy, true),
            ("Resistance", before.resistance, after.resistance, true),
        ]
        return VStack(spacing: 3) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                let delta = row.after - row.before
                let changed = abs(delta) >= (row.percent ? 0.005 : 0.5)
                HStack(spacing: 5) {
                    Text(row.label)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 64, alignment: .leading)
                    Text(UnitDetailView.statText(row.before, percent: row.percent))
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.stroke)
                    Text(UnitDetailView.statText(row.after, percent: row.percent))
                        .font(Theme.numeric(11))
                        .foregroundStyle(changed ? Theme.textPrimary : Theme.textSecondary)
                    Spacer()
                    if changed {
                        Text((delta > 0 ? "+" : "−") + UnitDetailView.statText(abs(delta), percent: row.percent))
                            .font(Theme.numeric(10))
                            .foregroundStyle(delta > 0 ? Theme.success : Theme.danger)
                    }
                }
            }
            setsDelta(relic)
        }
    }

    /// The sets the pick completes, and the ones it breaks.
    private func setsDelta(_ relic: Relic) -> some View {
        let before = unit?.activeRelicSets ?? []
        let after = resolvedWith(relic)?.activeRelicSets ?? []
        let gained = after.filter { entry in
            !before.contains(where: { $0.set == entry.set && $0.completions >= entry.completions })
        }
        let lost = before.filter { entry in
            !after.contains(where: { $0.set == entry.set && $0.completions >= entry.completions })
        }
        return HStack(spacing: 4) {
            if gained.isEmpty && lost.isEmpty {
                Text("Sets unchanged")
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(gained) { entry in
                Text("+ \(entry.set.displayName)")
                    .font(Theme.body(9).weight(.bold))
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.success.opacity(0.15)))
            }
            ForEach(lost) { entry in
                Text("− \(entry.set.displayName)")
                    .font(Theme.body(9).weight(.bold))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.danger.opacity(0.15)))
            }
            Spacer()
        }
        .padding(.top, 2)
    }
}
