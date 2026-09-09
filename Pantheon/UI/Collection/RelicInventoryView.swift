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

    /// Two columns of rows on a landscape phone, three on an iPad: the list
    /// fills the wide frame instead of spending it on one row's whitespace.
    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 6)]

    var body: some View {
        NavigationStack {
            GameScreen(
                "Relics",
                subtitle: "\(relics.count) of \(store.player.relics.count)",
                dismiss: { dismiss() }
            ) {
                BarMenu(label: "Slot", value: slotFilter.map { "\($0)" } ?? "All") {
                    Button("All slots") { slotFilter = nil }
                    ForEach(1...6, id: \.self) { slot in
                        Button("Slot \(slot)") { slotFilter = slot }
                    }
                }
                BarMenu(label: "Sort", value: sort.displayName) {
                    ForEach(Sort.allCases) { order in
                        Button(order.displayName) { sort = order }
                    }
                }
                BarMenu(label: "Fit", value: role.displayName) {
                    ForEach(roles, id: \.self) { entry in
                        Button(entry.displayName) { role = entry }
                    }
                }
                BarButton(
                    title: "Unequipped",
                    systemImage: hideEquipped ? "checkmark.square.fill" : "square",
                    tint: hideEquipped ? Theme.gold : Theme.textSecondary
                ) {
                    hideEquipped.toggle()
                }
                BarButton(
                    title: selecting ? "Done" : "Select",
                    systemImage: selecting ? "checkmark.circle.fill" : "checklist",
                    tint: selecting ? Theme.gold : Theme.textPrimary
                ) {
                    selecting.toggle()
                    if !selecting { selection.removeAll() }
                }
            } content: {
                VStack(spacing: 6) {
                    setBar
                    if relics.isEmpty {
                        EmptyState(
                            icon: "shield.slash",
                            title: "No relics here",
                            message: "Clear a stage or a hall floor; relics drop from both."
                        )
                        Spacer(minLength: 0)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 6) {
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
                            .padding(.bottom, 6)
                        }
                    }
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.top, 6)
                .safeAreaInset(edge: .bottom) { sellBar }
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

    /// The bulk-sell bar, along the bottom while selecting.
    @ViewBuilder private var sellBar: some View {
        if selecting {
            HStack(spacing: 12) {
                Text("\(selection.count) selected")
                    .font(Theme.body(12))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.ink)
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
    /// needs; a chip is a filter as well. One 22-point rail now, where the
    /// panel with its own header and border cost sixty.
    private var setBar: some View {
        let tally = Dictionary(grouping: store.player.relics, by: { $0.set }).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(RelicSet.allCases) { relicSet in
                        let count = tally[relicSet] ?? 0
                        let complete = count >= relicSet.piecesRequired
                        let selected = setFilter == relicSet
                        Button {
                            Juice.haptic(.light)
                            setFilter = selected ? nil : relicSet
                        } label: {
                            HStack(spacing: 4) {
                                Text(relicSet.displayName)
                                    .font(Theme.body(10).weight(.semibold))
                                Text("\(count)/\(relicSet.piecesRequired)")
                                    .font(Theme.numeric(9))
                            }
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: ScreenChrome.corner, style: .continuous)
                                    .fill(selected ? Theme.gold : (complete ? Theme.surfaceHigh : Theme.surface))
                            )
                            .foregroundStyle(selected ? Theme.ink : (complete ? Theme.textPrimary : Theme.textSecondary))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let setFilter {
                Text(setFilter.effectDescription)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
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
    @State private var showPicker = false
    /// The last attempt, for the result line and the highlighted sub stat.
    @State private var lastOutcome: RelicService.PowerUpOutcome?
    @State private var glow = false
    @State private var shakeOffset: CGFloat = 0

    private var relic: Relic? { store.player.relic(relicID) }
    private var wearer: ResolvedUnit? { relic?.equippedBy.flatMap { store.resolved($0) } }

    var body: some View {
        NavigationStack {
            GameScreen(
                relic.map { "\($0.set.displayName) · Slot \($0.slot)" } ?? "Relic",
                subtitle: relic.map { "+\($0.level) · fit for a \(role.displayName.lowercased())" },
                dismiss: { dismiss() }
            ) {
                BarButton(
                    title: relic?.isLocked == true ? "Locked" : "Lock",
                    systemImage: relic?.isLocked == true ? "lock.fill" : "lock.open",
                    tint: relic?.isLocked == true ? Theme.gold : Theme.textSecondary
                ) {
                    store.toggleRelicLock(relicID)
                }
                BarWallet(wallet: store.player.wallet, shows: [.drachma])
            } content: {
                if let relic {
                    // Two columns that each scroll on their own, so a short
                    // landscape frame never hides the power-up button.
                    HStack(alignment: .top, spacing: 8) {
                        ScrollView {
                            sheet(relic)
                        }
                        .frame(maxWidth: .infinity)
                        ScrollView {
                            powerUpPanel(relic)
                        }
                        .frame(width: 300)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.top, 6)
                } else {
                    EmptyState(icon: "shield.slash", title: "Sold", message: "This relic is gone.")
                        .onAppear { dismiss() }
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
                    lastOutcome = nil
                    AudioLibrary.shared.play(.uiConfirm)
                }
                Button("Leave it", role: .cancel) {}
            } message: {
                Text("Every sub stat is rolled again from scratch. The main stat, the level, the set and the slot stay. There is no undo.")
            }
            .sheet(isPresented: $showPicker) {
                if let wearer, let relic {
                    RelicPickerView(unitID: wearer.id, slot: relic.slot)
                        .environmentObject(store)
                }
            }
        }
    }

    // MARK: - The relic

    /// The relic as a sheet: what it is, its main stat and where the next
    /// level takes it, its sub stats with the last roll marked, and the
    /// level track with the sub-stat levels on it.
    private func sheet(_ relic: Relic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .fill(Theme.surfaceHigh)
                        .frame(width: 64, height: 64)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                .strokeBorder(glow ? Theme.gold : Theme.gold.opacity(0.5), lineWidth: glow ? 2.5 : 1)
                        )
                        .shadow(color: Theme.gold.opacity(glow ? 0.9 : 0), radius: glow ? 16 : 0)
                    Image(systemName: relic.set.glyph)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        StarRow(stars: relic.grade, size: 11)
                        Text("+\(relic.level)")
                            .font(Theme.numeric(15).weight(.bold))
                            .foregroundStyle(Theme.gold)
                    }
                    Text("\(relic.set.displayName) · Slot \(relic.slot)")
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.textPrimary)
                    Text(relic.set.effectDescription)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let wearer {
                        Label("Worn by \(wearer.name)", systemImage: "person.fill")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.info)
                    }
                }
                Spacer(minLength: 4)
                VStack(spacing: 2) {
                    EfficiencyDial(value: RelicService.efficiency(relic, for: role))
                    Text("fit for a \(role.displayName.lowercased())")
                        .font(Theme.body(8))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // The main stat, and where the next level takes it.
            HStack(spacing: 6) {
                Text(relic.effectiveMainStat.kind.displayName)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.gold)
                Spacer()
                Text("+\(relic.effectiveMainStat.kind.format(relic.effectiveMainStat.value))")
                    .font(Theme.numeric(14).weight(.bold))
                    .foregroundStyle(Theme.gold)
                if let next = relic.nextMainStat {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.stroke)
                    Text("+\(next.kind.format(next.value))")
                        .font(Theme.numeric(11))
                        .foregroundStyle(relic.level + 1 == relic.maxLevel ? Theme.gold : Theme.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous).fill(Theme.surfaceHigh))

            // The sub stats, the last roll marked, and the slot the next
            // roll would fill.
            VStack(spacing: 4) {
                ForEach(relic.subStats.indices, id: \.self) { index in
                    let sub = relic.subStats[index]
                    let changed = lastOutcome?.subStatChange.map { $0.kind == sub.kind } ?? false
                    HStack(spacing: 6) {
                        Text(sub.kind.displayName)
                            .font(Theme.body(11))
                            .foregroundStyle(changed ? Theme.textPrimary : Theme.textSecondary)
                        Spacer()
                        if changed, let change = lastOutcome?.subStatChange {
                            Text(change.isNew ? "new" : "+\(sub.kind.format(change.after - change.before))")
                                .font(Theme.numeric(9).weight(.bold))
                                .foregroundStyle(Theme.success)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.success.opacity(0.15)))
                        }
                        Text("+\(sub.kind.format(sub.value))")
                            .font(Theme.numeric(12))
                            .foregroundStyle(changed ? Theme.success : Theme.textPrimary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                            .fill(changed ? Theme.success.opacity(0.12) : Theme.surface)
                    )
                }
                if relic.subStats.count < 4, let at = nextSubStatLevel(relic) {
                    HStack {
                        Text("A new sub stat at +\(at)")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                            .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
                }
            }

            levelTrack(relic)
        }
        .padding(10)
        .panelBackground()
    }

    /// The next level that rolls a sub stat, if any is left.
    private func nextSubStatLevel(_ relic: Relic) -> Int? {
        guard relic.level < relic.maxLevel else { return nil }
        return ((relic.level + 1)...relic.maxLevel).first(where: { RelicService.levelRollsSubStat($0) })
    }

    /// Fifteen pips: gold where reached, ringed at +3, +6, +9 and +12 where
    /// the sub stats roll, a crown on +15.
    private func levelTrack(_ relic: Relic) -> some View {
        HStack(spacing: 3) {
            ForEach(1...relic.maxLevel, id: \.self) { level in
                let reached = level <= relic.level
                let rolls = RelicService.levelRollsSubStat(level)
                ZStack {
                    Circle()
                        .fill(reached ? Theme.gold : Theme.surface)
                        .frame(width: rolls || level == relic.maxLevel ? 12 : 8, height: rolls || level == relic.maxLevel ? 12 : 8)
                        .overlay(Circle().strokeBorder(rolls ? Theme.goldDim : Theme.stroke, lineWidth: 1))
                    if level == relic.maxLevel {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 6, weight: .black))
                            .foregroundStyle(reached ? Theme.ink : Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Power-up

    private func powerUpPanel(_ relic: Relic) -> some View {
        let cost = RelicService.upgradeCost(grade: relic.grade, level: relic.level)
        let chance = RelicService.successChance(toLevel: relic.level + 1)
        let affordable = store.player.wallet.drachma >= cost
        let canReappraise = relic.level >= RelicService.reappraisalMinimumLevel
            && store.player.wallet.drachma >= RelicService.reappraisalCost(relic)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Power-up", accessory: relic.isMaxLevel ? "+15, the top" : "+\(relic.level) → +\(relic.level + 1)")
            if !relic.isMaxLevel {
                HStack {
                    Text("Success rate")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int((chance * 100).rounded()))%")
                        .font(Theme.numeric(13).weight(.bold))
                        .foregroundStyle(chance >= 1 ? Theme.success : (chance >= 0.6 ? Theme.gold : Theme.danger))
                }
                HStack {
                    Text("Cost")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(cost) drachma")
                        .font(Theme.numeric(12))
                        .foregroundStyle(affordable ? Theme.textPrimary : Theme.danger)
                }
                if RelicService.levelRollsSubStat(relic.level + 1) {
                    Label(relic.subStats.count < 4 ? "This level adds a sub stat" : "This level grows a sub stat", systemImage: "sparkles")
                        .font(Theme.body(10).weight(.semibold))
                        .foregroundStyle(Theme.gold)
                } else if relic.level + 1 == relic.maxLevel {
                    Label("+15 lifts the main stat", systemImage: "crown.fill")
                        .font(Theme.body(10).weight(.semibold))
                        .foregroundStyle(Theme.gold)
                }
                PrimaryButton(title: "Power up", systemImage: "arrow.up.circle.fill", isEnabled: affordable) {
                    attempt()
                }
                .offset(x: shakeOffset)
            } else {
                Text("This relic is +15. Its main stat is at its top; the sub stats are what they rolled.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let outcome = lastOutcome {
                resultLine(outcome)
            }
            Text("A failed attempt keeps the drachma and the level stays. Sub stats roll at +3, +6, +9 and +12; the first four are added, after that one grows.")
                .font(Theme.body(9))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.stroke)

            HStack(spacing: 8) {
                if wearer != nil {
                    smallButton("Change", "arrow.left.arrow.right", tint: Theme.info) { showPicker = true }
                    smallButton("Unequip", "minus.circle", tint: Theme.textPrimary) {
                        if let wearer { store.unequip(slot: relic.slot, from: wearer.id) }
                        AudioLibrary.shared.play(.uiTap)
                    }
                }
                smallButton(
                    relic.level >= RelicService.reappraisalMinimumLevel ? "Reappraise" : "Reappraise +\(RelicService.reappraisalMinimumLevel)",
                    "arrow.triangle.2.circlepath", tint: Theme.gold, enabled: canReappraise
                ) { showReappraiseConfirm = true }
                smallButton("Sell \(RelicService.sellValue(relic))", "circle.hexagongrid.fill", tint: Theme.danger, enabled: !relic.isLocked) {
                    showSellConfirm = true
                }
            }
        }
        .padding(10)
        .panelBackground()
    }

    private func resultLine(_ outcome: RelicService.PowerUpOutcome) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(outcome.succeeded ? "Success — +\(outcome.level)" : "Failed — still +\(outcome.level)")
                .font(Theme.body(12).weight(.bold))
                .foregroundStyle(outcome.succeeded ? Theme.success : Theme.danger)
            if let change = outcome.subStatChange {
                Text(change.isNew
                     ? "New sub stat: \(change.kind.displayName) +\(change.kind.format(change.after))"
                     : "\(change.kind.displayName) +\(change.kind.format(change.before)) → +\(change.kind.format(change.after))")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.gold)
            } else if !outcome.succeeded {
                Text("\(outcome.cost) drachma spent at \(Int((outcome.chance * 100).rounded()))%.")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill((outcome.succeeded ? Theme.success : Theme.danger).opacity(0.12))
        )
    }

    private func smallButton(
        _ title: String, _ symbol: String, tint: Color, enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(Theme.body(8).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(enabled ? tint : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Theme.panel(Theme.tightCorner))
        }
        .disabled(!enabled)
    }

    /// One attempt: the flash and the sound on a success, a shake on a
    /// failure, and the result line either way.
    private func attempt() {
        guard let outcome = store.powerUpRelic(relicID) else { return }
        lastOutcome = outcome
        if outcome.succeeded {
            AudioLibrary.shared.play(.uiConfirm)
            Juice.notify(.success)
            withAnimation(.easeOut(duration: 0.15)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.5)) { glow = false }
            }
        } else {
            AudioLibrary.shared.play(.uiTap)
            Juice.notify(.error)
            withAnimation(.default.speed(4)) { shakeOffset = 7 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.default.speed(4)) { shakeOffset = -7 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.default.speed(4)) { shakeOffset = 0 }
            }
        }
    }
}

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
            GameScreen(
                "Slot \(slot)",
                subtitle: unit.map { "\($0.name) · best fit for a \(role.displayName.lowercased()) first" },
                dismiss: { dismiss() }
            ) {
                BarCount(value: "\(candidates.count)", systemImage: "shield.lefthalf.filled")
                BarButton(
                    title: "Free only",
                    systemImage: freeOnly ? "checkmark.square.fill" : "square",
                    tint: freeOnly ? Theme.gold : Theme.textSecondary
                ) {
                    freeOnly.toggle()
                }
            } content: {
                HStack(alignment: .top, spacing: 8) {
                    list
                        .frame(maxWidth: .infinity)
                    comparison
                        .frame(width: 300)
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.top, 6)
            }
        }
    }

    // MARK: - The candidates

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
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
            .padding(.bottom, 6)
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
