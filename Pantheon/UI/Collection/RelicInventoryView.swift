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
    @State private var showOptimiser = false

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

    /// Three columns of rows on a landscape phone, more on an iPad. A row is
    /// a fixed 66 points now that the sub stats sit in a 2×2 block, so the
    /// frame holds twelve relics where it used to hold six. 224 rather than a
    /// rounder number because an iPhone 16 Pro leaves 736 points inside the
    /// safe area and the content padding: three columns need 234 or less.
    private let columns = [GridItem(.adaptive(minimum: 224), spacing: 6)]

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
                // A glyph and no word. This strip already carries the slot
                // filter, the sort, the fit, the unequipped checkbox and
                // Select, and a sixth control with a word on it does not fit
                // beside them on a 667-point landscape phone.
                BarButton(
                    title: "Optimise",
                    systemImage: "wand.and.stars",
                    tint: Theme.info,
                    showsTitle: false
                ) {
                    showOptimiser = true
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
            .sheet(isPresented: $showOptimiser) {
                // No unit: the inventory is not about one, so the optimiser
                // opens on its roster grid.
                RelicOptimiserView()
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
    ///
    /// ALL is pinned outside the scroller: sixteen chips scroll, and clearing
    /// the filter by re-tapping the lit chip meant chasing a chip that had
    /// scrolled off. The line under the rail is always drawn, so picking a set
    /// no longer grows the rail and shoves the whole grid down under the
    /// finger.
    private var setBar: some View {
        let tally = Dictionary(grouping: store.player.relics, by: { $0.set }).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Button {
                    Juice.haptic(.light)
                    setFilter = nil
                } label: {
                    Text("ALL")
                        .font(Theme.body(9).weight(.black))
                        .tracking(0.4)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                .fill(setFilter == nil ? Theme.gold : Theme.surface)
                        )
                        .foregroundStyle(setFilter == nil ? Theme.ink : Theme.textSecondary)
                }
                .buttonStyle(.plain)
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
                                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                        .fill(selected ? Theme.gold : (complete ? Theme.surfaceHigh : Theme.surface))
                                )
                                .foregroundStyle(selected ? Theme.ink : (complete ? Theme.textPrimary : Theme.textSecondary))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text(setFilter?.effectDescription ?? "Tap a set to filter; a completed set is lit.")
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// One relic in a list: grade, set, slot, level, the main stat, the subs,
/// who wears it, and how good it is for the role being sorted by.
///
/// The row is a fixed 66 points. It used to grow with the number of sub stats
/// and the owner line, which drew a ragged grid, and the four subs of a 6★ —
/// the only relics worth judging — were joined into one string that truncated
/// at two lines. They sit in a fixed 2×2 block now, and the grade is a leading
/// tile in its rarity's metal carrying the set's glyph, so every set name
/// starts at the same x instead of at wherever a one-to-six star row ended.
struct RelicRow: View {
    let relic: Relic
    let role: CombatRole
    var ownerName: String? = nil
    var isSelected: Bool = false
    var selecting: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : (relic.isLocked ? "lock.fill" : "circle"))
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Theme.gold : (relic.isLocked ? Theme.gold : Theme.textSecondary))
                }
                gradeTile
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("\(relic.set.displayName) · Slot \(relic.slot)")
                            .font(Theme.body(12).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if relic.level > 0 {
                            Text("+\(relic.level)")
                                .font(Theme.numeric(11))
                                .foregroundStyle(Theme.gold)
                        }
                        if relic.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.gold)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 3) {
                        Text(relic.effectiveMainStat.displayText)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.gold)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let ownerName {
                            Image(systemName: "person.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.info)
                            Text(ownerName)
                                .font(Theme.body(9))
                                .foregroundStyle(Theme.info)
                                .lineLimit(1)
                        }
                    }
                    subStatBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                EfficiencyDial(value: RelicService.efficiency(relic, for: role))
            }
            .padding(.horizontal, 10)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(isSelected ? Theme.surfaceHigh : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(isSelected ? Theme.gold : Theme.stroke, lineWidth: 1)
            )
            .opacity(selecting && relic.isLocked ? 0.45 : 1)
        }
        .buttonStyle(.plain)
    }

    /// Grade as the app's rarity metal, with the set's glyph inside it and the
    /// number in the corner: a fixed 30 points where a star row ran from ten
    /// to fifty-seven.
    ///
    /// The metal is stroked here rather than through `rarityFrame`, because
    /// every `ui_frame_*` painting ships, so `hasPaintedFrame` is true and
    /// `rarityFrame` draws its border at zero width, expecting the caller to
    /// lay the painted frame over a portrait. There is no portrait here. The
    /// glow is kept to four points for the top two grades so it cannot bleed
    /// across a six-point column gap.
    private var gradeTile: some View {
        let rarity = Rarity(stars: relic.grade)
        return ZStack {
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surfaceHigh)
            Image(systemName: relic.set.glyph)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.gold)
        }
        .frame(width: 30, height: 30)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(rarity.frame, lineWidth: rarity >= .epic ? 2 : 1.5)
        )
        .shadow(color: rarity.glow.opacity(rarity >= .legendary ? 0.5 : 0), radius: 4)
        .overlay(alignment: .bottomTrailing) {
            Text("\(relic.grade)")
                .font(Theme.numeric(8))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 2)
                .background(Capsule().fill(Theme.gold))
        }
    }

    /// All four sub stats, always in the same two-by-two block, so the rows
    /// line up whether a relic rolled two or four.
    private var subStatBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            subStatPair(0)
            subStatPair(2)
        }
        .frame(height: 26, alignment: .top)
    }

    private func subStatPair(_ start: Int) -> some View {
        HStack(spacing: 8) {
            subStatCell(start)
            subStatCell(start + 1)
        }
    }

    @ViewBuilder private func subStatCell(_ index: Int) -> some View {
        if index < relic.subStats.count {
            let sub = relic.subStats[index]
            HStack(spacing: 3) {
                Text(sub.kind.displayName)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                // The number is the load-bearing half of the cell and takes
                // its width first: a cell is ~63 points at three columns and
                // ~50 while the 26-point checkbox is in the row, and at equal
                // priority a squeeze clipped "+52%" as readily as the name.
                // A shortened name is still readable; a clipped value is not.
                Text("+\(sub.kind.format(sub.value))")
                    .font(Theme.numeric(9))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
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
                // Two columns: a full-width row put the name at one edge of a
                // 400-point panel and its value at the other, with the eye
                // crossing the whole panel to pair them.
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                    spacing: 4
                ) {
                    ForEach(relic.subStats.indices, id: \.self) { index in
                        let sub = relic.subStats[index]
                        let changed = lastOutcome?.subStatChange.map { $0.kind == sub.kind } ?? false
                        HStack(spacing: 6) {
                            Text(sub.kind.displayName)
                                .font(Theme.body(11))
                                .foregroundStyle(changed ? Theme.textPrimary : Theme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
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
            actionRow(relic)
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
    /// the sub stats roll, a crown on +15, and a gold halo around the one
    /// level the next attempt buys. Every reached pip used to be the same
    /// gold, so on the screen where the money goes nothing said where you
    /// were or what you were paying for; and the milestone ring was goldDim
    /// on a gold fill, invisible on exactly the pips that matter.
    private func levelTrack(_ relic: Relic) -> some View {
        HStack(spacing: 3) {
            ForEach(1...relic.maxLevel, id: \.self) { level in
                let reached = level <= relic.level
                let rolls = RelicService.levelRollsSubStat(level)
                let isNext = level == relic.level + 1
                ZStack {
                    if isNext {
                        Circle()
                            .fill(Theme.gold.opacity(0.25))
                            .frame(width: 16, height: 16)
                        Circle()
                            .strokeBorder(Theme.gold, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                    }
                    Circle()
                        .fill(reached ? Theme.gold : Theme.surface)
                        .frame(width: rolls || level == relic.maxLevel ? 12 : 8, height: rolls || level == relic.maxLevel ? 12 : 8)
                        .overlay(
                            Circle().strokeBorder(
                                rolls ? (reached ? Theme.ink.opacity(0.5) : Theme.goldDim) : Theme.stroke,
                                lineWidth: 1
                            )
                        )
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
            // RelicService.upgrade takes the drachma before it rolls, and the
            // failure line below says so; this line used to promise the
            // opposite, which is a player gambling at 40% believing failure is
            // free and watching the bank drain with no explanation.
            Text("A failed attempt still spends the drachma; only the level stays put. Sub stats roll at +3, +6, +9 and +12; the first four are added, after that one grows.")
                .font(Theme.body(9))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .panelBackground()
    }

    /// Change, unequip, reappraise and sell. These lived at the foot of the
    /// 300-point power-up column as four 7-point captions under glyphs — the
    /// wrong size for a control that permanently destroys a relic. In the wide
    /// left column each is a horizontal plate with a readable word on it.
    private func actionRow(_ relic: Relic) -> some View {
        let canReappraise = relic.level >= RelicService.reappraisalMinimumLevel
            && store.player.wallet.drachma >= RelicService.reappraisalCost(relic)
        return HStack(spacing: 8) {
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
            if relic.isLocked {
                smallButton("Locked", "lock.fill", tint: Theme.gold, enabled: false) {}
            } else {
                smallButton("Sell", "circle.hexagongrid.fill", tint: Theme.danger) {
                    showSellConfirm = true
                }
            }
        }
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
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(Theme.body(11).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(enabled ? tint : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 32)
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
    @State private var showOptimiser = false

    private var unit: ResolvedUnit? { store.resolved(unitID) }
    private var role: CombatRole { unit?.role ?? .attacker }
    private var current: Relic? { unit?.unit.equippedRelics[slot].flatMap { store.player.relic($0) } }

    private var candidates: [Relic] {
        let role = self.role
        return store.player.relics
            .filter { $0.slot == slot && $0.equippedBy != unitID && (!freeOnly || $0.equippedBy == nil) }
            // By the number the rows actually draw. Sorting by `score` while
            // every dial showed `efficiency` (score over a ceiling that moves
            // with grade and level) put 62%, 71%, 55% down the list under a
            // subtitle promising the best fit first. Auto-equip still ranks by
            // `score`; this is the display order only.
            .sorted { RelicService.efficiency($0, for: role) > RelicService.efficiency($1, for: role) }
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
                // The way to the optimiser from the unit sheet: every slot in
                // the ring opens this screen, so the offer to solve all six
                // belongs where the player is already choosing one.
                BarButton(title: "All six", systemImage: "wand.and.stars", tint: Theme.info) {
                    showOptimiser = true
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
            .sheet(isPresented: $showOptimiser) {
                RelicOptimiserView(initialUnitID: unitID)
                    .environmentObject(store)
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

    /// The stats scroll; the screen's whole point — Equip — does not. For a
    /// filled slot the column carries two headers, two summaries, eight delta
    /// rows, the sets line and the footer, comfortably past the height a
    /// landscape frame leaves under the strip, so the primary action used to
    /// sit below the fold at the end of the scroll.
    private var comparison: some View {
        VStack(spacing: 6) {
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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            if let selected {
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
        let after = resolvedWith(relic)
        return StatDeltaTable(
            before: unit?.stats ?? Stats.zero,
            after: after?.stats ?? unit?.stats ?? Stats.zero,
            beforeSets: unit?.activeRelicSets ?? [],
            afterSets: after?.activeRelicSets ?? []
        )
    }
}

// MARK: - The optimiser

/// Every stat before and after a change, with the sets it completes or breaks.
///
/// This was the relic picker's own table until the optimiser needed the same
/// eight rows in the same order: two screens that answer "what would this do
/// to my unit" must not answer it in two layouts. The widths are the ones the
/// picker measured — fixed columns, because free-width values put the arrow at
/// a different x on every row and the comparison read as a ragged block, and
/// the longest cell is a five-digit HP.
struct StatDeltaTable: View {
    let before: Stats
    let after: Stats
    var beforeSets: [ActiveRelicSet] = []
    var afterSets: [ActiveRelicSet] = []

    var body: some View {
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
                        .frame(width: 46, alignment: .trailing)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.stroke)
                    Text(UnitDetailView.statText(row.after, percent: row.percent))
                        .font(Theme.numeric(11))
                        .foregroundStyle(changed ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 46, alignment: .trailing)
                    Spacer(minLength: 4)
                    if changed {
                        Text((delta > 0 ? "+" : "−") + UnitDetailView.statText(abs(delta), percent: row.percent))
                            .font(Theme.numeric(10))
                            .foregroundStyle(delta > 0 ? Theme.success : Theme.danger)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            sets
        }
    }

    /// The sets the change completes, and the ones it breaks.
    private var sets: some View {
        let gained = afterSets.filter { entry in
            !beforeSets.contains(where: { $0.set == entry.set && $0.completions >= entry.completions })
        }
        let lost = beforeSets.filter { entry in
            !afterSets.contains(where: { $0.set == entry.set && $0.completions >= entry.completions })
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

/// The optimiser: a unit, a goal, and the best six relics the account can
/// field for it — every stat before and after, the sets it completes, and the
/// loadouts it keeps.
///
/// It is the relic picker's screen on purpose, because a player who has used
/// that one has used this one: what would go on down the left, what it would
/// do on the right, and the button that does it under the table where it
/// cannot scroll away. The roster grid stands in for the picker's candidate
/// list until a unit is chosen — a rail beside the six slots and the stat
/// table does not fit the 647 points a 667-point landscape phone leaves, so
/// the screen does one job at a time.
struct RelicOptimiserView: View {
    /// The unit to open on: the wearer, when the screen is reached from a
    /// relic slot on the unit sheet. Nil from the relic inventory, which is
    /// not about any one unit, and where the roster grid chooses.
    let initialUnitID: UUID?

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var target: UUID?
    @State private var goal: RelicService.OptimiserGoal = .power
    @State private var solution: RelicService.OptimisedLoadout?
    /// The last thing that happened, said in the loadout bar: equipping six
    /// relics moves nothing on screen except the numbers, and a screen that
    /// answers a tap with nothing reads as broken.
    @State private var notice: String?
    /// Whether that last thing was a refusal. One of the three notices is a
    /// no — the loadout cap — and a no painted in the success colour reads as
    /// a yes at a glance.
    @State private var noticeIsWarning = false

    /// The target is seeded here rather than in `onAppear`, so the screen
    /// solves once. Assigning it in `onAppear` changes `target` after the
    /// first render, `onChange(of: target)` then fires, and the search runs a
    /// second time — 46,656 loadouts weighed twice before the first frame,
    /// on the main thread, in the debug build the CI tour photographs.
    init(initialUnitID: UUID? = nil) {
        self.initialUnitID = initialUnitID
        _target = State(initialValue: initialUnitID)
    }

    /// The four goals as the strip's segments.
    private var goals: [(value: RelicService.OptimiserGoal, title: String)] {
        RelicService.OptimiserGoal.allCases.map { (value: $0, title: $0.displayName) }
    }

    /// Everything owned, strongest first — the Hall of Ka's order, and the
    /// unit worth re-gearing is usually near the top of it.
    private var roster: [ResolvedUnit] {
        store.resolvedUnits.sorted { $0.power > $1.power }
    }

    private var unit: ResolvedUnit? {
        guard let target else { return nil }
        return store.resolved(target)
    }

    /// How many of the six slots the solve would actually change. The Equip
    /// button reads it: proposing what the unit already wears is worth
    /// saying, not worth tapping.
    private var changeCount: Int {
        guard let unit, let solution else { return 0 }
        return (1...6).filter { slot in
            solution.relics.first(where: { $0.slot == slot })?.id
                != unit.relics.first(where: { $0.slot == slot })?.id
        }.count
    }

    private let cardColumns = [GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 8)]

    var body: some View {
        NavigationStack {
            GameScreen(
                "Optimise",
                subtitle: unit.map { "\($0.name) · \(goal.summary)" } ?? "which unit?",
                dismiss: { dismiss() }
            ) {
                BarSegments(options: goals, selection: $goal)
                if unit != nil {
                    BarCount(
                        value: "\(solution?.candidatesConsidered ?? 0)",
                        systemImage: "shield.lefthalf.filled"
                    )
                    BarButton(
                        title: "Change unit",
                        systemImage: "person.2.fill",
                        tint: Theme.textSecondary,
                        showsTitle: false
                    ) {
                        target = nil
                    }
                }
            } content: {
                if let unit {
                    HStack(alignment: .top, spacing: 8) {
                        proposal(unit)
                            .frame(maxWidth: .infinity)
                        comparison(unit)
                            .frame(width: 290)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.top, 6)
                    .safeAreaInset(edge: .bottom) { loadoutBar(unit) }
                } else {
                    chooser
                }
            }
            .onAppear { solve() }
            .onChange(of: goal) { _, _ in solve() }
            .onChange(of: target) { _, _ in solve() }
        }
    }

    // MARK: - Which unit

    @ViewBuilder private var chooser: some View {
        if roster.isEmpty {
            EmptyState(
                icon: "person.crop.circle.badge.questionmark",
                title: "No one to gear",
                message: "Summon a unit first; the optimiser dresses whoever you own."
            )
        } else {
            ScrollView {
                LazyVGrid(columns: cardColumns, spacing: 8) {
                    ForEach(roster) { entry in
                        Button {
                            Juice.haptic(.light)
                            target = entry.id
                        } label: {
                            // `clipShape` does not clip hit-testing and a
                            // portrait is taller than its card, so the art
                            // overhangs into the row above and the later card
                            // wins the tap. The hit area is the card itself.
                            UnitCard(unit: entry, isSelected: entry.id == target, size: 76)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - What it would wear

    /// The six slots, and the footer that says what the answer cost. The
    /// column scrolls on its own: six rows and a footer are taller than what
    /// a landscape phone leaves under the strip.
    @ViewBuilder private func proposal(_ unit: ResolvedUnit) -> some View {
        if let solution {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(1...6, id: \.self) { slot in
                            slotRow(
                                unit: unit,
                                slot: slot,
                                proposed: solution.relics.first(where: { $0.slot == slot })
                            )
                        }
                    }
                    .padding(.bottom, 4)
                }
                Text("\(solution.loadoutsSearched) loadouts weighed, from \(solution.candidatesConsidered) relics no one else is wearing")
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            EmptyState(
                icon: "shield.slash",
                title: "Nothing free to fit",
                message: "Every relic you own is on another unit. Take one off, or clear a stage: relics drop from the campaign and from the Labyrinth."
            )
        }
    }

    /// One slot: what the solve puts in it, and what that displaces.
    private func slotRow(unit: ResolvedUnit, slot: Int, proposed: Relic?) -> some View {
        let current = unit.relics.first(where: { $0.slot == slot })
        let changed = proposed?.id != current?.id
        return HStack(spacing: 8) {
            Text("\(slot)")
                .font(Theme.numeric(11).weight(.black))
                .foregroundStyle(changed ? Theme.gold : Theme.textSecondary)
                .frame(width: 12)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.surfaceHigh)
                Image(systemName: proposed?.set.glyph ?? "questionmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(proposed == nil ? Theme.textSecondary : Theme.gold)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(Rarity(stars: proposed?.grade ?? 1).frame, lineWidth: 1.5)
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let proposed {
                        Text("\(proposed.set.displayName) +\(proposed.level)")
                            .font(Theme.body(11).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        // The main stat is the load-bearing half of the row and
                        // takes its width first: the set name shortens
                        // readably, "+52%" does not.
                        Text(proposed.effectiveMainStat.displayText)
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.gold)
                            .lineLimit(1)
                            .layoutPriority(1)
                    } else {
                        Text("Nothing fits")
                            .font(Theme.body(11).weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                    }
                }
                Text(displacement(current: current, changed: changed))
                    .font(Theme.body(9))
                    .foregroundStyle(changed ? Theme.info : Theme.textSecondary)
                    .lineLimit(1)
            }
            if changed {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.gold)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(changed ? Theme.surfaceHigh : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(changed ? Theme.goldDim : Theme.stroke, lineWidth: 1)
        )
    }

    /// What a row's second line says. A solve that keeps a relic has to say so
    /// as plainly as one that moves it, or six rows of set names read as six
    /// changes.
    private func displacement(current: Relic?, changed: Bool) -> String {
        guard changed else { return "already worn" }
        guard let current else { return "the slot is empty now" }
        return "off comes \(current.set.displayName) +\(current.level)"
    }

    // MARK: - What it would do

    /// Before and after, and the button that does it. The table scrolls; the
    /// button does not — the picker learned that with Equip below the fold at
    /// the end of a scroll.
    private func comparison(_ unit: ResolvedUnit) -> some View {
        let after = solution.map { solved(unit, relics: $0.relics) }
        return VStack(spacing: 6) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Now", accessory: "\(unit.power) power")
                    if let after {
                        SectionHeader(title: "If equipped", accessory: "\(after.power) power")
                        StatDeltaTable(
                            before: unit.stats,
                            after: after.stats,
                            beforeSets: unit.activeRelicSets,
                            afterSets: after.activeRelicSets
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            PrimaryButton(
                title: changeCount == 0 ? "Nothing to change" : "Equip these six",
                systemImage: "wand.and.stars",
                isEnabled: changeCount > 0
            ) {
                equipSolution()
            }
        }
        .padding(10)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// The unit as the solve would leave it. Through `ProgressionService` and
    /// not the solver's own arithmetic: the numbers on this screen and the
    /// numbers in battle come from one place.
    private func solved(_ unit: ResolvedUnit, relics: [Relic]) -> ResolvedUnit {
        ProgressionService.resolve(unit.unit, blueprint: unit.blueprint, equipped: relics)
    }

    // MARK: - Loadouts

    /// The unit's saved loadouts, and the button that keeps what it wears
    /// under the goal in the strip. Along the bottom, where the inventory
    /// keeps its sell bar.
    private func loadoutBar(_ unit: ResolvedUnit) -> some View {
        let saved = store.relicLoadouts(for: unit.id)
        return HStack(spacing: 6) {
            Text("LOADOUTS")
                .font(Theme.body(9).weight(.black))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            ForEach(saved) { loadout in
                HStack(spacing: 6) {
                    Button {
                        wear(loadout)
                    } label: {
                        Text(loadout.name)
                            .font(Theme.body(10).weight(.bold))
                            .foregroundStyle(Theme.gold)
                    }
                    .buttonStyle(.plain)
                    // Its own button, not a corner of the chip: a loadout is
                    // four taps to rebuild, but deleting the one you meant to
                    // wear is the annoying half of that.
                    Button {
                        Juice.haptic(.light)
                        store.deleteRelicLoadout(loadout.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 16, height: 24)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 9)
                .padding(.trailing, 3)
                .frame(height: 24)
                .background(Capsule().fill(Theme.surfaceHigh))
            }
            if saved.isEmpty {
                Text("none kept yet — equip a set and keep it under a name")
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let notice {
                Text(notice)
                    .font(Theme.body(10))
                    .foregroundStyle(noticeIsWarning ? Theme.danger : Theme.success)
                    .lineLimit(1)
            }
            BarButton(
                title: "Keep as \(goal.displayName)",
                systemImage: "square.and.arrow.down.fill",
                tint: Theme.info
            ) {
                keep(unit)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Theme.ink)
    }

    // MARK: - Doing it

    /// Runs the solver for the unit and the goal in hand.
    ///
    /// Synchronous on purpose: a solve is tens of thousands of additions,
    /// which is milliseconds, and an asynchronous one would have to be
    /// cancelled and restarted every time a segment is tapped.
    private func solve() {
        notice = nil
        noticeIsWarning = false
        guard let target else {
            solution = nil
            return
        }
        solution = store.optimisedLoadout(for: target, goal: goal)
    }

    private func equipSolution() {
        guard let target, let solution else { return }
        // Counted before the store moves anything: afterwards nothing has
        // changed, by definition.
        let moved = changeCount
        store.applyRelicLoadout(solution.relicIDs, to: target)
        Juice.notify(.success)
        solve()
        notice = moved == 1 ? "One slot changed." : "\(moved) slots changed."
        noticeIsWarning = false
    }

    /// Keeps **what the unit is wearing**, not the proposal on screen — so
    /// the order is Equip, then Keep, which is what the bar's empty hint says.
    /// The notice says "what it wears" rather than repeating the goal's name
    /// because the chip that appears beside it already carries the name, and
    /// a player who tapped Keep before Equip has to be able to see that the
    /// old six are what got kept.
    private func keep(_ unit: ResolvedUnit) {
        if store.saveRelicLoadout(named: goal.displayName, for: unit.id) {
            AudioLibrary.shared.play(.uiConfirm)
            notice = "Kept what it wears."
            noticeIsWarning = false
        } else {
            Juice.notify(.warning)
            // Short on purpose: this fires only when four chips are already in
            // the bar, which is when there is least room left for a sentence.
            notice = "\(RelicService.loadoutsPerUnit) kept already; delete one."
            noticeIsWarning = true
        }
    }

    private func wear(_ loadout: RelicLoadout) {
        store.applySavedLoadout(loadout.id)
        AudioLibrary.shared.play(.uiConfirm)
        Juice.notify(.success)
        solve()
        notice = "Wearing \(loadout.name)."
        noticeIsWarning = false
    }
}
