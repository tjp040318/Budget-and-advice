import SwiftUI
import UIKit

// MARK: - Manage and the bag: one relic screen (2026-09-24)
//
// The owner, with Summoners War's Manage screen beside ours: "Look how easy
// it is to see everything, and to understand what's going on." Ours spread
// one job — dress a unit — over the inventory, the filter sheet, the slot
// picker and the optimiser, four sheets deep at worst. This is the ONE screen
// that replaces the four (Docs/PLAN.md, *Relics the genre's way*; the
// builders' spec §4.2), in two modes:
//
// - MANAGE, with a unit: its stats as they would be (THEN) with the change
//   from what it wears (NOW) beside each, the sets a change completes or
//   breaks, the six as NOW over THEN, and Revert / All off / Apply — the
//   store's own loadout path, so nothing moves until Apply. Best six (the
//   optimiser's four goals) and Fill empty slots (Auto-equip) are PREVIEWS
//   here, and a kept loadout loads into THEN.
// - THE BAG, with none: the grid, the picked relic's panel, and select mode
//   with bulk sell and its total.
//
// Both modes share the right panel: the filters inline — the slot rosette and
// four wells (SET, MAIN, SUB, MORE) whose popovers drive `RelicFilter` — and
// the grid of `RelicTile`s. A confirmation is a `RelicConfirmCard`, never a
// system dialog. The parts are the kit's (RelicKit.swift, RelicTile.swift).

/// How the Relics screen opens: plainly, or already doing something. The
/// unit openings (Manage) are the unit sheet's and the collection's doors;
/// the bag openings are the set reference's and the relic card's; the tour
/// ones stage a frame the CI photographs.
enum RelicsOpening: Equatable {
    case plain
    /// Manage, filtered to one slot: the old slot picker.
    case slot(Int)
    /// Manage, THEN the optimiser's six for the goal, previewed.
    case bestSix(RelicService.OptimiserGoal)
    /// Manage, THEN today's Auto-equip, previewed.
    case fillEmpty
    /// Manage, THEN with this relic in its slot, filtered to that slot.
    case withRelic(UUID)
    /// The bag, filtered to one set: "show me my Fury relics".
    case set(RelicSet)
    /// The bag, the panel on this relic.
    case picked(UUID)
    case tourDraft, tourMoreFilters, tourSetPicker, tourSelect, tourConfirmSell
}

/// The grid's orders: the inventory's eight, fit first.
enum RelicsSort: String, CaseIterable {
    case fit, quality, grade, level, set, slot, mainStat, newest
}

extension RelicsSort {
    /// The Sort menu's word for the order.
    var title: String {
        switch self {
        case .fit: return "Fit"
        case .quality: return "Quality"
        case .grade: return "Grade"
        case .level: return "Level"
        case .set: return "Set"
        case .slot: return "Slot"
        case .mainStat: return "Main stat"
        case .newest: return "Newest"
        }
    }
}

/// The genre's Manage, in our materials: a unit's build made NOW → THEN and
/// applied at once, or — with no unit — the bag of every relic owned. Present
/// it as a sheet with the store in the environment:
/// `RelicsScreen(unitID:opening:)` for Manage, `RelicsScreen()` for the bag.
struct RelicsScreen: View {
    /// The unit whose build is made here (Manage); nil is the bag.
    let unitID: UUID?
    /// What the screen does as it opens.
    let opening: RelicsOpening

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var filter = RelicFilter()
    @State private var sortOrder: RelicsSort
    /// The role the bag's Fit order is for, chosen in the Sort menu.
    @State private var fitRole: CombatRole = .attacker
    /// THEN: the build Apply puts on, by slot. Read as NOW until the screen
    /// has appeared (`draftReady`), so the first frame never counts six
    /// changes against an empty draft.
    @State private var draft: [Int: UUID] = [:]
    @State private var draftReady = false
    @State private var selecting = false
    @State private var chosenIDs: Set<UUID> = []
    /// The relic in the bag's panel; the grid's first until one is tapped.
    @State private var pickedID: UUID?
    /// A long press opened the card: the lift that ends it is not a tap.
    @State private var suppressTap = false
    @State private var notice: RelicsNotice?
    @State private var noticeStamp = 0
    @State private var confirm: RelicConfirm?
    @State private var presented: RelicsScreenSheet?
    @State private var openPopover: RelicsFilterPopover?
    @State private var openingDone = false

    init(unitID: UUID? = nil, opening: RelicsOpening = .plain) {
        self.unitID = unitID
        self.opening = opening
        _sortOrder = State(initialValue: unitID == nil ? Self.rememberedBagSort() : .fit)
    }

    /// The bag's order is remembered between visits; Manage always opens on
    /// Fit for its unit's role. Never read or written under the tour, so one
    /// relaunch's order cannot bleed into the next.
    private static let bagSortKey = "relicsBagSort"

    private static var isTour: Bool {
        ProcessInfo.processInfo.arguments.contains("-tour")
    }

    private static func rememberedBagSort() -> RelicsSort {
        guard !isTour, let raw = UserDefaults.standard.string(forKey: bagSortKey),
              let stored = RelicsSort(rawValue: raw) else { return .grade }
        return stored
    }

    /// Revert and All off at the width their words take: 78 and 80 (the
    /// spec's 72 is under REVERT's carved title with the plate's padding).
    private static let revertWidth: CGFloat = 78
    private static let allOffWidth: CGFloat = 80
    /// The bag panel's gold button beside its three icon plates.
    private static let panelPrimaryWidth: CGFloat = 116

    var body: some View {
        let snapshot = makeSnapshot()
        return NavigationStack {
            screen(snapshot)
        }
    }

    private func screen(_ snapshot: RelicsSnapshot) -> some View {
        GameScreen(screenTitle(snapshot), subtitle: screenSubtitle(snapshot), dismiss: { leave() }) {
            stripControls(snapshot)
        } content: {
            content(snapshot)
        }
        .overlay {
            confirmLayer
        }
        .sheet(item: $presented, onDismiss: { suppressTap = false }) { sheet in
            sheetContent(sheet)
        }
        .onAppear {
            openOnce()
        }
        .onChange(of: sortOrder) { _, order in
            remember(order)
        }
        .onChange(of: store.player.relics.count) { _, _ in
            prune()
        }
        .onChange(of: nowIDs) { old, new in
            rebase(from: old, to: new)
        }
    }

    // MARK: - One render's reading

    /// Everything the strip, the panels and the grid read, computed once per
    /// render so the grid is filtered and sorted once.
    private func makeSnapshot() -> RelicsSnapshot {
        let faces = wearerFaces()
        let unit: ResolvedUnit? = unitID.flatMap { id in faces[id] ?? store.resolved(id) }
        let build: RelicsDraftBuild? = unit.map { draftBuild($0) }
        let role: CombatRole = unit?.role ?? fitRole
        let shown = sortedRelics(role: role)
        let picked: Relic? = unit == nil ? pickedRelic(in: shown) : nil
        return RelicsSnapshot(unit: unit, build: build, shown: shown, total: store.player.relics.count,
                              faces: faces, picked: picked)
    }

    /// Every unit that wears a relic, by id: the faces on the tiles. Each is
    /// resolved against its own six only — the bag indexed once — because
    /// against the whole bag every render scanned it six times a wearer.
    private func wearerFaces() -> [UUID: ResolvedUnit] {
        let player = store.player
        let boons = player.boons ?? []
        var index: [UUID: Relic] = [:]
        for relic in player.relics {
            index[relic.id] = relic
        }
        var faces: [UUID: ResolvedUnit] = [:]
        for unit in player.units where !unit.equippedRelics.isEmpty {
            let own = unit.equippedRelics.values.compactMap { index[$0] }
            if let resolved = ProgressionService.resolve(unit, relics: own, boons: boons) {
                faces[unit.id] = resolved
            }
        }
        return faces
    }

    /// NOW, as the unit wears it this moment.
    private var nowIDs: [Int: UUID] {
        guard let unitID else { return [:] }
        return store.player.unit(unitID)?.equippedRelics ?? [:]
    }

    /// THEN, or NOW before the screen has appeared.
    private var effectiveDraft: [Int: UUID] {
        draftReady ? draft : nowIDs
    }

    private func draftBuild(_ unit: ResolvedUnit) -> RelicsDraftBuild {
        let worn = unit.unit.equippedRelics
        let planned = draftReady ? draft : worn
        let wornRelics = relicsBySlot(worn)
        let plannedRelics = relicsBySlot(planned)
        let thenUnit = ProgressionService.resolve(unit.unit, blueprint: unit.blueprint, equipped: Array(plannedRelics.values),
                                                  boon: unit.boon, regalia: unit.regalia)
        let changes = RelicReading.draftChanges(now: worn, then: planned)
        return RelicsDraftBuild(nowIDs: worn, thenIDs: planned, nowRelics: wornRelics, thenRelics: plannedRelics,
                                thenUnit: thenUnit, changes: changes)
    }

    /// The relics a plan names, each in its own slot; a sold one is gone.
    private func relicsBySlot(_ ids: [Int: UUID]) -> [Int: Relic] {
        var bySlot: [Int: Relic] = [:]
        for (slot, id) in ids {
            if let relic = store.player.relic(id), relic.slot == slot {
                bySlot[slot] = relic
            }
        }
        return bySlot
    }

    /// A plan with every relic that no longer exists (or never fitted its
    /// slot) left out.
    private func livePlan(_ plan: [Int: UUID]) -> [Int: UUID] {
        plan.filter { entry in store.player.relic(entry.value)?.slot == entry.key }
    }

    private func sortedRelics(role: CombatRole) -> [Relic] {
        let matching = store.player.relics.filter { filter.matches($0) }
        return Self.ordered(matching, by: sortOrder, role: role)
    }

    /// The inventory's comparators, unchanged. Fit scores each relic once
    /// before sorting: a comparator that scored both sides scored every relic
    /// about twenty times over on a full bag.
    private static func ordered(_ relics: [Relic], by order: RelicsSort, role: CombatRole) -> [Relic] {
        switch order {
        case .fit:
            let scored = relics.map { relic in (relic: relic, fit: RelicService.efficiency(relic, for: role)) }
            return scored.sorted { $0.fit > $1.fit }.map { $0.relic }
        case .quality:
            return relics.sorted { ($0.resolvedQuality, $0.grade, $0.level) > ($1.resolvedQuality, $1.grade, $1.level) }
        case .grade:
            return relics.sorted { ($0.grade, $0.level) > ($1.grade, $1.level) }
        case .level:
            return relics.sorted { ($0.level, $0.grade) > ($1.level, $1.grade) }
        case .set:
            return relics.sorted { ($0.set.rawValue, -$0.grade, -$0.level) < ($1.set.rawValue, -$1.grade, -$1.level) }
        case .slot:
            return relics.sorted { ($0.slot, -$0.grade, -$0.level) < ($1.slot, -$1.grade, -$1.level) }
        case .mainStat:
            return relics.sorted {
                ($0.mainStat.kind.rawValue, -$0.effectiveMainStat.value) < ($1.mainStat.kind.rawValue, -$1.effectiveMainStat.value)
            }
        case .newest:
            return Array(relics.reversed())
        }
    }

    private func pickedRelic(in shown: [Relic]) -> Relic? {
        if let pickedID, let hit = shown.first(where: { $0.id == pickedID }) {
            return hit
        }
        return shown.first
    }

    /// Changes whenever the order or a filter does, and restarts the grid's
    /// scroll at the top; a tap in the draft or a selection never does.
    private var gridKey: String {
        let slots = filter.slots.sorted().map { String($0) }.joined(separator: ",")
        let sets = filter.sets.map { $0.rawValue }.sorted().joined(separator: ",")
        let mains = filter.mainKinds.map { $0.rawValue }.sorted().joined(separator: ",")
        let subs = filter.subKinds.map { $0.rawValue }.sorted().joined(separator: ",")
        let grades = filter.grades.sorted().map { String($0) }.joined(separator: ",")
        let qualities = filter.qualities.map { String($0.rawValue) }.sorted().joined(separator: ",")
        let flags = "\(filter.worn.rawValue)\(filter.lockedOnly)\(filter.awakenedOnly)"
        return [sortOrder.rawValue, fitRole.rawValue, slots, sets, mains, subs, grades, qualities, flags]
            .joined(separator: "|")
    }

    // MARK: - The strip

    private func screenTitle(_ snapshot: RelicsSnapshot) -> String {
        snapshot.unit == nil ? "Relics" : "Manage"
    }

    private func screenSubtitle(_ snapshot: RelicsSnapshot) -> String {
        if let unit = snapshot.unit {
            let changes = snapshot.build?.changes ?? 0
            guard changes > 0 else { return unit.nameWithoutEpithet }
            let noun = changes == 1 ? "change" : "changes"
            return "\(unit.nameWithoutEpithet) · \(changes) \(noun)"
        }
        guard filter.isEmpty else { return "\(snapshot.shown.count) of \(snapshot.total)" }
        return snapshot.total == 1 ? "1 relic" : "\(snapshot.total) relics"
    }

    /// Manage: BEST SIX, LOADOUTS and SORT. The bag: Select, Sort, the set
    /// reference and the boons.
    @ViewBuilder
    private func stripControls(_ snapshot: RelicsSnapshot) -> some View {
        if let unit = snapshot.unit {
            bestSixMenu()
            loadoutsMenu(unit)
            sortMenu(bag: false)
        } else {
            BarButton(
                title: selecting ? "Done" : "Select",
                systemImage: selecting ? "checkmark.circle.fill" : "checklist",
                tint: selecting ? Theme.gold : Theme.textPrimary
            ) {
                toggleSelecting()
            }
            sortMenu(bag: true)
            BarButton(title: "Sets", systemImage: "book.closed.fill", showsTitle: false) {
                presented = .sets
            }
            BarButton(title: "Boons", systemImage: "seal.fill", showsTitle: false) {
                presented = .boons
            }
        }
    }

    /// A strip menu's label on the strip's one material, the dark well.
    private func stripMenuLabel(systemImage: String?, title: String, count: String?) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(RelicPalette.label)
            }
            Text(title)
                .font(Theme.body(11).weight(.bold))
                .foregroundStyle(Theme.onGlassGold)
                .lineLimit(1)
                .fixedSize()
            if let count {
                Text(count)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 11)
        .frame(height: ScreenChrome.control)
        .background(ScreenChrome.well)
    }

    /// The optimiser's four goals and Auto-equip, each a PREVIEW in THEN.
    private func bestSixMenu() -> some View {
        Menu {
            ForEach(RelicService.OptimiserGoal.allCases) { goal in
                Button {
                    runBestSix(goal)
                } label: {
                    Label("Best for \(goal.displayName)", systemImage: goal.glyph)
                }
            }
            Divider()
            Button {
                runFillEmpty()
            } label: {
                Label("Fill empty slots", systemImage: "plus.square.on.square")
            }
        } label: {
            stripMenuLabel(systemImage: "wand.and.stars", title: "BEST SIX", count: nil)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Best six")
    }

    /// Wear a kept loadout (into THEN), keep what the unit wears under a
    /// goal's name, or delete one.
    private func loadoutsMenu(_ unit: ResolvedUnit) -> some View {
        let kept = store.relicLoadouts(for: unit.id)
        return Menu {
            loadoutItems(unit, kept: kept)
        } label: {
            stripMenuLabel(systemImage: nil, title: "LOADOUTS", count: kept.isEmpty ? nil : "\(kept.count)")
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(kept.isEmpty ? "Loadouts" : "Loadouts, \(kept.count) kept")
    }

    @ViewBuilder
    private func loadoutItems(_ unit: ResolvedUnit, kept: [RelicLoadout]) -> some View {
        Section("Wear") {
            if kept.isEmpty {
                Text("None kept yet")
            }
            ForEach(kept) { loadout in
                Button(loadout.name) {
                    wear(loadout)
                }
            }
        }
        Section("Keep what \(unit.nameWithoutEpithet) wears as") {
            ForEach(RelicService.OptimiserGoal.allCases) { goal in
                Button(goal.displayName) {
                    keep(goal, unitID: unit.id)
                }
            }
        }
        if !kept.isEmpty {
            Section("Delete") {
                ForEach(kept) { loadout in
                    Button(loadout.name, role: .destructive) {
                        store.deleteRelicLoadout(loadout.id)
                    }
                }
            }
        }
    }

    private func sortMenu(bag: Bool) -> some View {
        BarMenu(label: "Sort", value: sortOrder.title) {
            sortItems(bag: bag)
        }
    }

    @ViewBuilder
    private func sortItems(bag: Bool) -> some View {
        ForEach(RelicsSort.allCases, id: \.self) { order in
            Button {
                withAnimation(Motion.select) {
                    sortOrder = order
                }
            } label: {
                checkLabel(order.title, isOn: order == sortOrder)
            }
        }
        if bag && sortOrder == .fit {
            Section("Fit for") {
                ForEach(CombatRole.allCases) { role in
                    Button {
                        withAnimation(Motion.select) {
                            fitRole = role
                        }
                    } label: {
                        checkLabel(role.displayName, isOn: role == fitRole)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func checkLabel(_ title: String, isOn: Bool) -> some View {
        if isOn {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // MARK: - The content

    private func content(_ snapshot: RelicsSnapshot) -> some View {
        GeometryReader { proxy in
            panels(snapshot, layout: RelicsLayout(width: proxy.size.width, total: snapshot.total))
        }
        .background {
            ReliquaryBackdrop()
        }
    }

    private func panels(_ snapshot: RelicsSnapshot, layout: RelicsLayout) -> some View {
        HStack(alignment: .top, spacing: 8) {
            leftPanel(snapshot)
                .frame(width: RelicsLayout.leftWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(BasaltPanel())
            gridPanel(snapshot, layout: layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(BasaltPanel())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func leftPanel(_ snapshot: RelicsSnapshot) -> some View {
        if let unit = snapshot.unit, let build = snapshot.build {
            draftPanel(unit, build: build, faces: snapshot.faces)
        } else {
            bagPanel(snapshot)
        }
    }

    // MARK: - Manage: the draft

    /// The unit's stats as THEN would make them, the sets, NOW over THEN,
    /// and Revert / All off / Apply pinned at the foot.
    private func draftPanel(_ unit: ResolvedUnit, build: RelicsDraftBuild, faces: [UUID: ResolvedUnit]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                draftHeader(unit, build: build)
                StatLedger(rows: ledgerRows(now: unit.stats, then: build.thenUnit.stats, drafted: build.changes > 0),
                           style: .manage)
                setsRow(unit, build: build, faces: faces)
                BuildRows(now: build.nowRelics, then: build.thenRelics, onTile: { relic in
                    openCard(relic)
                }, onClear: { slot in
                    clearSlot(slot)
                })
            }
            Spacer(minLength: 6)
            draftFoot(build)
        }
        .padding(12)
    }

    /// The face, the name over its stars, and POWER now → then with the
    /// difference. A long name or a long difference is laid out to fit
    /// (`headerFit`), never cut: the difference moves up beside POWER, and
    /// a name still too long takes two lines in place of the stars (the face
    /// carries them).
    private func draftHeader(_ unit: ResolvedUnit, build: RelicsDraftBuild) -> some View {
        let before = unit.power
        let after = build.thenUnit.power
        let drafted = build.changes > 0
        let fit = headerFit(name: unit.nameWithoutEpithet, before: before, after: after, drafted: drafted)
        return HStack(alignment: .center, spacing: 8) {
            UnitPortraitTile(unit: unit, size: 32, showsLevel: false)
            nameColumn(unit, twoLines: fit.twoLines)
            Spacer(minLength: 8)
            powerColumn(before: before, after: after, drafted: drafted, deltaAbove: fit.deltaAbove)
                .layoutPriority(1)
        }
        .frame(height: 32)
    }

    private func headerFit(name: String, before: Int, after: Int, drafted: Bool) -> RelicsHeaderFit {
        let room: CGFloat = RelicsLayout.leftInner - 32 - 8 - 8 - 1
        let nameWidth = RelicsMeasure.width(name.uppercased(), face: Theme.carvedFace, size: 13)
        let eyebrowWidth = RelicsMeasure.width("POWER", face: RelicsMeasure.blackFace, size: 11, tracking: 0.8)
        let nowWidth = RelicsMeasure.width(before.formatted(), face: RelicsMeasure.boldFace, size: 13)
        guard drafted else {
            let column = max(eyebrowWidth, nowWidth)
            return RelicsHeaderFit(deltaAbove: false, twoLines: nameWidth + column > room)
        }
        let thenWidth = RelicsMeasure.width("→ \(after.formatted())", face: RelicsMeasure.boldFace, size: 13)
        var deltaWidth: CGFloat = 0
        if after != before {
            deltaWidth = RelicsMeasure.width(Self.signed(after - before), face: RelicsMeasure.boldFace, size: 12) + 4
        }
        let inline = max(eyebrowWidth, nowWidth + 4 + thenWidth + deltaWidth)
        if nameWidth + inline <= room {
            return RelicsHeaderFit(deltaAbove: false, twoLines: false)
        }
        let stacked = max(eyebrowWidth + deltaWidth, nowWidth + 4 + thenWidth)
        return RelicsHeaderFit(deltaAbove: true, twoLines: nameWidth + stacked > room)
    }

    @ViewBuilder
    private func nameColumn(_ unit: ResolvedUnit, twoLines: Bool) -> some View {
        let name = unit.nameWithoutEpithet.uppercased()
        if twoLines {
            Text(name)
                .font(Theme.title(13))
                .carved(glow: false, multiline: true)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Theme.title(15))
                    .carved(glow: false)
                    .lineLimit(1)
                    .minimumScaleFactor(13.0 / 15.0)
                StarRow(stars: unit.stars, size: 9)
            }
        }
    }

    private func powerColumn(before: Int, after: Int, drafted: Bool, deltaAbove: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 4) {
                eyebrow("Power")
                if drafted && deltaAbove {
                    deltaText(after - before)
                }
            }
            HStack(spacing: 4) {
                Text(before.formatted())
                    .font(Theme.numeric(13))
                    .foregroundStyle(drafted ? RelicPalette.dim : RelicPalette.value)
                if drafted {
                    Text("→ \(after.formatted())")
                        .font(Theme.numeric(13))
                        .foregroundStyle(RelicPalette.value)
                    if !deltaAbove {
                        deltaText(after - before)
                    }
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(drafted ? "Power \(before), then \(after)" : "Power \(before)")
    }

    @ViewBuilder
    private func deltaText(_ delta: Int) -> some View {
        if delta != 0 {
            Text(Self.signed(delta))
                .font(Theme.numeric(12))
                .foregroundStyle(delta > 0 ? RelicPalette.gain : RelicPalette.loss)
        }
    }

    private static func signed(_ delta: Int) -> String {
        let sign = delta > 0 ? "+" : "−"
        return sign + abs(delta).formatted()
    }

    private func eyebrow(_ words: String) -> some View {
        Text(words.uppercased())
            .font(Theme.body(11).weight(.black))
            .tracking(0.8)
            .foregroundStyle(RelicPalette.eyebrow)
            .lineLimit(1)
            .fixedSize()
    }

    /// THEN's eight stats, each with its change from NOW once a draft exists;
    /// with none, clean numbers.
    private func ledgerRows(now: Stats, then: Stats, drafted: Bool) -> [StatLedgerRow] {
        let lines: [(label: String, before: Double, after: Double, percent: Bool)] = [
            (label: "HP", before: now.hp, after: then.hp, percent: false),
            (label: "ATK", before: now.atk, after: then.atk, percent: false),
            (label: "DEF", before: now.def, after: then.def, percent: false),
            (label: "SPD", before: now.spd, after: then.spd, percent: false),
            (label: "CRIT Rate", before: now.critRate, after: then.critRate, percent: true),
            (label: "CRIT DMG", before: now.critDamage, after: then.critDamage, percent: true),
            (label: "Accuracy", before: now.accuracy, after: then.accuracy, percent: true),
            (label: "Resistance", before: now.resistance, after: then.resistance, percent: true),
        ]
        return lines.map { line in
            ledgerRow(line.label, before: line.before, after: line.after, percent: line.percent, drafted: drafted)
        }
    }

    private func ledgerRow(_ label: String, before: Double, after: Double, percent: Bool, drafted: Bool) -> StatLedgerRow {
        let value = UnitDetailView.statText(after, percent: percent)
        guard drafted, let change = Self.shownChange(before: before, after: after, percent: percent) else {
            return StatLedgerRow(label: label, value: value, change: nil, tone: LedgerTone.none)
        }
        return StatLedgerRow(label: label, value: value, change: change.text, tone: change.tone)
    }

    /// The difference of the two figures AS PRINTED, so "29% → 33%" says
    /// +4% and a change that rounds away says nothing (never "+0").
    private static func shownChange(before: Double, after: Double, percent: Bool) -> (text: String, tone: LedgerTone)? {
        let scale: Double = percent ? 100 : 1
        let shown = Int((after * scale).rounded()) - Int((before * scale).rounded())
        guard shown != 0 else { return nil }
        let figure = percent ? "\(abs(shown))%" : abs(shown).formatted()
        if shown > 0 {
            return (text: "+" + figure, tone: LedgerTone.gain)
        }
        return (text: "−" + figure, tone: LedgerTone.loss)
    }

    /// SETS: a set THEN completes that NOW does not ("+ ZEPHYR", green), one
    /// NOW completes that THEN breaks ("− VIGIL", rose), then the ones kept —
    /// as many as fit, then "+n" — and FROM with the faces whose relics
    /// Apply would take off them.
    private func setsRow(_ unit: ResolvedUnit, build: RelicsDraftBuild, faces: [UUID: ResolvedUnit]) -> some View {
        let chips = setChips(now: unit.activeRelicSets, then: build.thenUnit.activeRelicSets)
        let donors = donorFaces(build, unitID: unit.id, faces: faces)
        let label = RelicsMeasure.width("SETS", face: RelicsMeasure.blackFace, size: 11, tracking: 0.8)
        let fromRoom: CGFloat = donors.isEmpty ? 0 : Self.fromChipWidth(donors.count) + 6
        let fit = Self.fittedChips(chips, room: RelicsLayout.leftInner - label - 8 - fromRoom)
        return HStack(spacing: 6) {
            eyebrow("Sets")
                .padding(.trailing, 2)
            if chips.isEmpty {
                Text("No set complete")
                    .font(Theme.body(12))
                    .foregroundStyle(RelicPalette.quiet)
                    .lineLimit(1)
                    .fixedSize()
            }
            ForEach(fit.shown) { chip in
                setChip(chip.text, tone: chip.tone)
            }
            if fit.hidden > 0 {
                setChip("+\(fit.hidden)", tone: RelicPalette.dim)
            }
            if !donors.isEmpty {
                fromChip(donors)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 20)
    }

    private func setChips(now: [ActiveRelicSet], then: [ActiveRelicSet]) -> [RelicsSetChip] {
        var chips: [RelicsSetChip] = []
        for entry in then where !Self.holds(now, entry) {
            chips.append(RelicsSetChip(id: "gain-\(entry.id)", text: "+ " + Self.setWord(entry), tone: RelicPalette.gain))
        }
        for entry in now where !Self.holds(then, entry) {
            chips.append(RelicsSetChip(id: "loss-\(entry.id)", text: "− " + Self.setWord(entry), tone: RelicPalette.loss))
        }
        for entry in then where Self.holds(now, entry) {
            chips.append(RelicsSetChip(id: "kept-\(entry.id)", text: Self.setWord(entry), tone: RelicPalette.eyebrow))
        }
        return chips
    }

    /// `StatDeltaTable.sets`' rule: an entry is held when the other side
    /// completes the same set at least as many times.
    private static func holds(_ entries: [ActiveRelicSet], _ entry: ActiveRelicSet) -> Bool {
        entries.contains { $0.set == entry.set && $0.completions >= entry.completions }
    }

    private static func setWord(_ entry: ActiveRelicSet) -> String {
        let name = entry.set.displayName.uppercased()
        return entry.completions > 1 ? "\(name) ×\(entry.completions)" : name
    }

    private static func chipWidth(_ text: String) -> CGFloat {
        RelicsMeasure.width(text, face: RelicsMeasure.blackFace, size: 11) + 17
    }

    private static func fromChipWidth(_ donors: Int) -> CGFloat {
        let word: CGFloat = RelicsMeasure.width("FROM", face: RelicsMeasure.blackFace, size: 11)
        // Typed lets, not one chain: literals and a literal ternary in one
        // sum is the shape that times the type checker out.
        let parts: CGFloat = 8 + 4 + 16 + 3
        let second: CGFloat = donors > 1 ? 12 : 0
        return word + parts + second
    }

    /// At most three chips, and never one that would push the "+n" after it
    /// past the row: measured, because a cut chip reads as a broken one.
    private static func fittedChips(_ chips: [RelicsSetChip], room: CGFloat) -> (shown: [RelicsSetChip], hidden: Int) {
        var kept: [RelicsSetChip] = []
        var used: CGFloat = 0
        for (index, chip) in chips.enumerated() {
            let left = chips.count - index - 1
            let tail: CGFloat = left > 0 ? chipWidth("+\(left)") + 6 : 0
            let gap: CGFloat = kept.isEmpty ? 0 : 6
            let width = chipWidth(chip.text)
            guard kept.count < 3, used + gap + width + tail <= room else { break }
            kept.append(chip)
            used += gap + width
        }
        return (shown: kept, hidden: chips.count - kept.count)
    }

    private func setChip(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(Theme.body(11).weight(.black))
            .foregroundStyle(tone)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(RelicPalette.well))
            .overlay(Capsule().strokeBorder(tone.opacity(0.55), lineWidth: 1))
    }

    private func fromChip(_ donors: [ResolvedUnit]) -> some View {
        HStack(spacing: 4) {
            Text("FROM")
                .font(Theme.body(11).weight(.black))
                .foregroundStyle(RelicPalette.partial)
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: -4) {
                ForEach(Array(donors.prefix(2))) { donor in
                    WearerBadge(unit: donor, size: 16)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(height: 20)
        .background(Capsule().fill(RelicPalette.well))
        .overlay(Capsule().strokeBorder(RelicPalette.partial.opacity(0.55), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apply takes relics from \(donors.map { $0.nameWithoutEpithet }.joined(separator: " and "))")
    }

    /// The units THEN takes a relic from, each once, in slot order.
    private func donorFaces(_ build: RelicsDraftBuild, unitID: UUID, faces: [UUID: ResolvedUnit]) -> [ResolvedUnit] {
        var seen = Set<UUID>()
        var donors: [ResolvedUnit] = []
        for slot in 1...6 {
            guard let relic = build.thenRelics[slot], let wearer = relic.equippedBy,
                  wearer != unitID, !seen.contains(wearer), let face = faces[wearer] else { continue }
            seen.insert(wearer)
            donors.append(face)
        }
        return donors
    }

    private func draftFoot(_ build: RelicsDraftBuild) -> some View {
        HStack(spacing: 8) {
            RelicPlateButton("Revert", height: 46, isEnabled: build.changes > 0) {
                revert()
            }
            .frame(width: Self.revertWidth)
            RelicPlateButton("All off", height: 46, isEnabled: !build.thenIDs.isEmpty) {
                allOff()
            }
            .frame(width: Self.allOffWidth)
            PrimaryButton(title: applyTitle(build.changes), isEnabled: build.changes > 0) {
                apply()
            }
        }
    }

    private func applyTitle(_ changes: Int) -> String {
        changes > 0 ? "Apply · \(changes)" : "Apply"
    }

    // MARK: - Manage: what changes THEN

    /// A tap in the grid while building: a relic already in THEN comes out
    /// (back to what NOW has there); one worn now stays, with a tick; any
    /// other goes into its slot.
    private func draftTap(_ relic: Relic) {
        let slot = relic.slot
        let worn = nowIDs
        var next = effectiveDraft
        if next[slot] == relic.id {
            guard worn[slot] != relic.id else {
                Juice.haptic(.light)
                return
            }
            next[slot] = worn[slot]
        } else {
            next[slot] = relic.id
        }
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap)
        withAnimation(Motion.select) {
            draft = next
            draftReady = true
        }
    }

    private func clearSlot(_ slot: Int) {
        var next = effectiveDraft
        next[slot] = nil
        withAnimation(Motion.select) {
            draft = next
            draftReady = true
        }
    }

    private func revert() {
        withAnimation(Motion.select) {
            draft = nowIDs
            draftReady = true
        }
    }

    private func allOff() {
        withAnimation(Motion.select) {
            draft = [:]
            draftReady = true
        }
    }

    /// THEN on the unit, through the store's one loadout path: a relic
    /// another unit wears comes off it, a slot THEN leaves empty is emptied.
    private func apply() {
        guard let unitID else { return }
        store.applyRelicLoadout(livePlan(effectiveDraft), to: unitID)
        Juice.notify(.success)
        withAnimation(Motion.select) {
            draft = nowIDs
            draftReady = true
        }
        post("Applied")
    }

    /// THEN becomes the optimiser's six for the goal; nothing is worn yet.
    private func runBestSix(_ goal: RelicService.OptimiserGoal) {
        guard let unitID else { return }
        guard let solved = store.optimisedLoadout(for: unitID, goal: goal) else {
            Juice.notify(.warning)
            post("Nothing free to fit", warning: true)
            return
        }
        let proposal = livePlan(solved.relicIDs)
        let moved = RelicReading.draftChanges(now: nowIDs, then: proposal)
        Juice.haptic(.light)
        withAnimation(Motion.select) {
            draft = proposal
            draftReady = true
        }
        post(Self.bestSixWords(goal, moved: moved))
    }

    private static func bestSixWords(_ goal: RelicService.OptimiserGoal, moved: Int) -> String {
        let head = "Best for \(goal.displayName)"
        if moved == 0 {
            return "\(head): nothing to change"
        }
        return moved == 1 ? "\(head): 1 slot changes" : "\(head): \(moved) slots change"
    }

    /// Today's Auto-equip, previewed: the empty slots of THEN filled with the
    /// best free relic each, computed on a copy of the save with THEN put on
    /// it, so a slot emptied with × fills too and nothing real moves.
    private func runFillEmpty() {
        guard let unitID else { return }
        let before = effectiveDraft
        var trial = store.player
        _ = RelicService.applyLoadout(relicIDs: livePlan(before), to: unitID, player: &trial)
        let filled = RelicReading.fillEmpty(unitID: unitID, player: trial)
        let added = RelicReading.draftChanges(now: before, then: filled)
        Juice.haptic(.light)
        withAnimation(Motion.select) {
            draft = filled
            draftReady = true
        }
        if before.count >= 6 {
            post("Every slot is filled")
        } else if added == 0 {
            post("Nothing free to fit", warning: true)
        } else {
            post(added == 1 ? "Fill empty: 1 slot" : "Fill empty: \(added) slots")
        }
    }

    /// A kept loadout into THEN; Apply wears it.
    private func wear(_ loadout: RelicLoadout) {
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap)
        withAnimation(Motion.select) {
            draft = livePlan(loadout.relicIDs)
            draftReady = true
        }
        post("\(loadout.name) loaded — Apply to wear")
    }

    /// Keeps what the unit WEARS (NOW) under the goal's name, as the
    /// optimiser did.
    private func keep(_ goal: RelicService.OptimiserGoal, unitID: UUID) {
        if store.saveRelicLoadout(named: goal.displayName, for: unitID) {
            AudioLibrary.shared.play(.uiConfirm)
            post("Kept as \(goal.displayName)")
        } else {
            Juice.notify(.warning)
            post("\(RelicService.loadoutsPerUnit) kept — delete one", warning: true)
        }
    }

    private func takeInto(_ relicID: UUID) {
        guard unitID != nil, let relic = store.player.relic(relicID) else { return }
        var plan = effectiveDraft
        plan[relic.slot] = relic.id
        draft = plan
        draftReady = true
        filter.slots = [relic.slot]
    }

    // MARK: - The bag: the panel

    @ViewBuilder
    private func bagPanel(_ snapshot: RelicsSnapshot) -> some View {
        if selecting {
            sellPanel(snapshot.shown, faces: snapshot.faces)
        } else if snapshot.total == 0 {
            EmptyState(icon: "shield.slash", title: "No relics yet",
                       message: "Relics drop from the campaign and the Labyrinth.", onGlass: true)
        } else if let relic = snapshot.picked {
            pickedPanel(relic, faces: snapshot.faces)
        } else {
            EmptyState(icon: "line.3.horizontal.decrease.circle", title: "Nothing matches",
                       message: "Loosen a filter over the grid, or clear them all under MORE.", onGlass: true)
        }
    }

    /// The picked relic: what it is, what it rolled and how often, what comes
    /// next, its set, and what to do with it. The words scroll; the buttons
    /// never do.
    private func pickedPanel(_ relic: Relic, faces: [UUID: ResolvedUnit]) -> some View {
        let wearer = relic.equippedBy.flatMap { faces[$0] }
        return VStack(alignment: .leading, spacing: 6) {
            FadingScroll(fade: 12, bleed: 4, resetKey: relic.id.uuidString) {
                pickedWords(relic, wearer: wearer)
            }
            pickedFoot(relic, worn: relic.equippedBy != nil)
        }
        .padding(12)
    }

    private func pickedWords(_ relic: Relic, wearer: ResolvedUnit?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            pickedHeader(relic, wearer: wearer)
            mainStatWell(relic)
            subRows(relic)
            SetEffectRow(set: relic.set, piecesOnUnit: piecesWorn(of: relic), style: .compact)
        }
        // The tile's stars ride half above its top edge.
        .padding(.top, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pickedHeader(_ relic: Relic, wearer: ResolvedUnit?) -> some View {
        let fit = fitReading(relic, wearer: wearer)
        let mark: RelicTileMark = relic.isLocked ? RelicTileMark.locked : RelicTileMark.none
        return HStack(alignment: .center, spacing: 10) {
            RelicTile(relic: relic, size: .large, wearer: wearer, mark: mark)
            VStack(alignment: .leading, spacing: 1) {
                qualityLine(relic)
                Text(relic.set.displayName.uppercased())
                    .font(Theme.title(19))
                    .carved(glow: false)
                    .lineLimit(1)
                    .fixedSize()
                Text("Slot \(relic.slot) · \(relic.mainStat.kind.displayName)")
                    .font(Theme.body(12))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 6)
            VStack(spacing: 2) {
                RelicFitDial(value: fit.value, size: 40)
                Text(fit.role.displayName)
                    .font(Theme.body(11))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fit for \(fit.role.withArticle), \(Int((fit.value * 100).rounded())) percent")
        }
    }

    /// The role the dial reads: the wearer's, else the Sort menu's when the
    /// grid is sorted by fit, else the one the relic suits best.
    private func fitReading(_ relic: Relic, wearer: ResolvedUnit?) -> (role: CombatRole, value: Double) {
        if let wearer {
            return (role: wearer.role, value: RelicService.efficiency(relic, for: wearer.role))
        }
        if sortOrder == .fit {
            return (role: fitRole, value: RelicService.efficiency(relic, for: fitRole))
        }
        return RelicReading.bestFit(relic)
    }

    private func qualityLine(_ relic: Relic) -> some View {
        HStack(spacing: 0) {
            Text(relic.resolvedQuality.displayName.uppercased())
                .foregroundStyle(relic.resolvedQuality.tone)
            if relic.isAwakened {
                Text(" · AWAKENED")
                    .foregroundStyle(RelicPalette.halo)
            }
        }
        .font(Theme.body(12).weight(.black))
        .tracking(1)
        .lineLimit(1)
        .fixedSize()
    }

    /// The main stat large in its well: star gold at +15.
    private func mainStatWell(_ relic: Relic) -> some View {
        let main = relic.effectiveMainStat
        let outline = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(spacing: 8) {
            Text(main.kind.displayName)
                .font(Theme.body(13).weight(.bold))
                .foregroundStyle(RelicPalette.label)
            Spacer(minLength: 6)
            Text("+\(main.kind.format(main.value))")
                .font(Theme.numeric(22).weight(.heavy))
                .foregroundStyle(relic.isMaxLevel ? RelicPalette.star : RelicPalette.value)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(outline.fill(RelicPalette.well))
        .overlay(outline.strokeBorder(RelicPalette.bronze, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Main stat, \(main.kind.displayName) plus \(main.kind.format(main.value))")
    }

    /// The subs with their roll marks (read off the values, `RollMarks`),
    /// then the next one to come.
    private func subRows(_ relic: Relic) -> some View {
        let counts = RelicReading.rollCounts(relic)
        let subs = relic.effectiveSubStats
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(subs.enumerated()), id: \.offset) { index, sub in
                subRow(relic, index: index, sub: sub, rolls: index < counts.count ? counts[index] : nil)
            }
            nextRow(relic)
        }
    }

    private func subRow(_ relic: Relic, index: Int, sub: StatModifier, rolls: Int?) -> some View {
        let bonus = relic.honedBonus(at: index)
        let gemmed = relic.gemmed == index
        return HStack(spacing: 6) {
            Text(sub.kind.displayName)
                .font(Theme.body(13).weight(.semibold))
                .foregroundStyle(RelicPalette.label)
            if bonus > 0 {
                honedChip("+\(sub.kind.format(bonus))")
            }
            if gemmed {
                ItemIcon(key: "gem_hero", size: 14, glow: false)
            }
            Spacer(minLength: 4)
            Text("+\(sub.kind.format(sub.value))")
                .font(Theme.numeric(15))
                .foregroundStyle(RelicPalette.value)
            rollColumn(rolls)
        }
        .lineLimit(1)
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subSpoken(sub, rolls: rolls, honed: bonus > 0, gemmed: gemmed))
    }

    private func subSpoken(_ sub: StatModifier, rolls: Int?, honed: Bool, gemmed: Bool) -> String {
        var words = "\(sub.kind.displayName) plus \(sub.kind.format(sub.value))"
        if let rolls {
            words += rolls == 1 ? ", 1 roll" : ", \(rolls) rolls"
        }
        if honed {
            words += ", honed"
        }
        if gemmed {
            words += ", gemmed"
        }
        return words
    }

    /// The marks, or — for a gemmed sub, whose rolls went with the gem — the
    /// same width empty, so every value stands in one column.
    @ViewBuilder
    private func rollColumn(_ rolls: Int?) -> some View {
        if let rolls {
            RollMarks(count: rolls)
        } else {
            Color.clear
                .frame(width: 52, height: 8)
        }
    }

    private func honedChip(_ words: String) -> some View {
        Text(words)
            .font(Theme.numeric(11.5))
            .foregroundStyle(RelicPalette.honed)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Capsule().fill(RelicPalette.well))
    }

    /// "⊕ +12", "⊕ choose on the card" or "⊕ 5th · awaken": the sub still
    /// to come, quiet.
    @ViewBuilder
    private func nextRow(_ relic: Relic) -> some View {
        if let next = RelicReading.nextSubStat(relic) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(Self.nextWords(next))
                    .font(Theme.body(12))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(RelicPalette.quiet)
            .frame(height: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Next sub stat: \(Self.nextWords(next))")
        }
    }

    private static func nextWords(_ next: NextSubStat) -> String {
        switch next {
        case .atLevel(let level): return "+\(level)"
        case .waiting: return "choose on the card"
        case .awaken: return "5th · awaken"
        }
    }

    /// How many pieces of the relic's set its wearer has on; nil unworn.
    private func piecesWorn(of relic: Relic) -> Int? {
        guard let wearer = relic.equippedBy else { return nil }
        var count = 0
        for other in store.player.relics where other.equippedBy == wearer && other.set == relic.set {
            count += 1
        }
        return count
    }

    /// POWER UP (or AWAKEN, or OPEN) opens the card; EQUIP or MOVE chooses a
    /// wearer; LOCK toggles (its word stays LOCK — UNLOCK does not fit a
    /// 50-point plate beside the gold one — and its padlock and the tile's
    /// mark say which it is); SELL asks first.
    private func pickedFoot(_ relic: Relic, worn: Bool) -> some View {
        HStack(spacing: 6) {
            PrimaryButton(title: primaryTitle(relic)) {
                openCard(relic)
            }
            .frame(width: Self.panelPrimaryWidth)
            RelicIconPlate(worn ? "Move" : "Equip", systemImage: "person.crop.circle.badge.plus", height: 46) {
                presented = .wearer(relic.id)
            }
            RelicIconPlate("Lock", systemImage: relic.isLocked ? "lock.fill" : "lock.open", height: 46) {
                store.toggleRelicLock(relic.id)
            }
            .accessibilityLabel(relic.isLocked ? "Unlock" : "Lock")
            RelicIconPlate("Sell", itemKey: "drachma", finish: .wine, height: 46, isEnabled: !relic.isLocked) {
                askSell([relic])
            }
        }
    }

    private func primaryTitle(_ relic: Relic) -> String {
        if relic.level < relic.maxLevel {
            return "Power up"
        }
        if relic.grade >= 6 && !relic.isAwakened {
            return "Awaken"
        }
        return "Open"
    }

    // MARK: - The bag: selling

    /// Select mode's panel: how many are chosen, what they fetch, whose they
    /// were, and ALL SHOWN / CLEAR / SELL.
    private func sellPanel(_ shown: [Relic], faces: [UUID: ResolvedUnit]) -> some View {
        let chosen = chosenRelics()
        let total = chosen.reduce(0) { $0 + RelicService.sellValue($1) }
        return VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "Sell", accessory: "\(chosen.count) chosen")
            sellTotal(total)
            sellWearers(chosen, faces: faces)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                RelicPlateButton("All shown") {
                    chooseAllShown(shown)
                }
                RelicPlateButton("Clear", isEnabled: !chosenIDs.isEmpty) {
                    clearChosen()
                }
            }
            RelicPlateButton("Sell · \(chosen.count)", finish: .wine, height: 46, isEnabled: !chosen.isEmpty) {
                askSell(chosen)
            }
        }
        .padding(12)
    }

    private func sellTotal(_ total: Int) -> some View {
        HStack(spacing: 8) {
            ItemIcon(key: "drachma", size: 26)
            Text(total.formatted())
                .font(Theme.numeric(22).weight(.heavy))
                .foregroundStyle(RelicPalette.star)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) drachma")
    }

    @ViewBuilder
    private func sellWearers(_ chosen: [Relic], faces: [UUID: ResolvedUnit]) -> some View {
        let wearers = Self.wearers(of: chosen, faces: faces)
        if chosen.isEmpty {
            Text("Tap relics to choose them; a locked one stays.")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
                .fixedSize(horizontal: false, vertical: true)
        } else if !wearers.isEmpty {
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ForEach(Array(wearers.prefix(4))) { unit in
                        WearerBadge(unit: unit, size: 20)
                    }
                }
                Text("come off")
                    .font(Theme.body(12))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Worn relics come off \(wearers.count) units")
        }
    }

    /// Each wearer once, in the order their relics came.
    private static func wearers(of relics: [Relic], faces: [UUID: ResolvedUnit]) -> [ResolvedUnit] {
        var seen = Set<UUID>()
        var found: [ResolvedUnit] = []
        for relic in relics {
            guard let wearer = relic.equippedBy, !seen.contains(wearer), let face = faces[wearer] else { continue }
            seen.insert(wearer)
            found.append(face)
        }
        return found
    }

    /// The chosen relics in the bag's own order — hidden by a filter or not,
    /// as the selection has always been a set of ids.
    private func chosenRelics() -> [Relic] {
        store.player.relics.filter { chosenIDs.contains($0.id) }
    }

    /// Every unlocked, unworn relic the grid shows, as the inventory's "All
    /// shown" chose: with the filter, "sell every 3★ Normal" is three taps.
    private func chooseAllShown(_ shown: [Relic]) {
        let free = shown.filter { !$0.isLocked && $0.equippedBy == nil }
        withAnimation(Motion.select) {
            chosenIDs = Set(free.map { $0.id })
        }
    }

    private func clearChosen() {
        withAnimation(Motion.select) {
            chosenIDs.removeAll()
        }
    }

    private func toggleSelecting() {
        withAnimation(Motion.select) {
            selecting.toggle()
            if !selecting {
                chosenIDs.removeAll()
            }
        }
    }

    private func askSell(_ relics: [Relic]) {
        let total = relics.reduce(0) { $0 + RelicService.sellValue($1) }
        confirm = .sell(relics: relics, total: total)
    }

    /// The card has already played the sale's sound.
    private func sell(_ ids: [UUID]) {
        guard store.sellRelics(ids) != nil else { return }
        Juice.notify(.success)
        chosenIDs.subtract(ids)
    }

    // MARK: - The right panel: the filters and the grid

    private func gridPanel(_ snapshot: RelicsSnapshot, layout: RelicsLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            filterBlock(snapshot, layout: layout)
            gridArea(snapshot, layout: layout)
                .overlay(alignment: .top) {
                    noticeView
                        .padding(.top, 8)
                }
        }
        .padding(12)
    }

    /// The slot rosette beside two rows of wells: SET and MAIN, then SUB,
    /// MORE and the count shown.
    private func filterBlock(_ snapshot: RelicsSnapshot, layout: RelicsLayout) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RelicSlotDiagram(selection: $filter.slots)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    setFilterWell(layout)
                    mainFilterWell(layout)
                }
                HStack(spacing: 8) {
                    subFilterWell(layout)
                    moreFilterWell(layout)
                    if layout.showsCount {
                        countLabel(snapshot, width: layout.countWidth)
                    }
                }
            }
        }
    }

    private func setFilterWell(_ layout: RelicsLayout) -> some View {
        let shown = RelicsWellText.sets(filter.sets, width: layout.pairWell)
        return RelicWellButton("Set", value: shown.text, set: shown.emblem, isActive: !filter.sets.isEmpty) {
            openPopover = .set
        }
        .frame(width: layout.pairWell)
        .popover(isPresented: popoverBinding(.set)) {
            RelicSetPickerPopover(selection: $filter.sets, owned: ownedCounts(), onReference: {
                openReferenceFromPopover()
            })
        }
    }

    private func mainFilterWell(_ layout: RelicsLayout) -> some View {
        let value = RelicsWellText.mains(filter.mainKinds, width: layout.pairWell)
        return RelicWellButton("Main", value: value, isActive: !filter.mainKinds.isEmpty) {
            openPopover = .main
        }
        .frame(width: layout.pairWell)
        .popover(isPresented: popoverBinding(.main)) {
            RelicStatPickerPopover(title: "Main stat", selection: $filter.mainKinds, kinds: StatKind.allCases)
        }
    }

    private func subFilterWell(_ layout: RelicsLayout) -> some View {
        let value = RelicsWellText.subs(filter.subKinds, width: layout.subWell)
        return RelicWellButton("Sub", value: value, isActive: !filter.subKinds.isEmpty) {
            openPopover = .sub
        }
        .frame(width: layout.subWell)
        .popover(isPresented: popoverBinding(.sub)) {
            RelicStatPickerPopover(title: "Sub stats", selection: $filter.subKinds, kinds: RelicService.subStatPool,
                                   allOfThese: true)
        }
    }

    private func moreFilterWell(_ layout: RelicsLayout) -> some View {
        let axes = moreCount
        return RelicWellButton("More", value: axes > 0 ? "\(axes)" : "—", isActive: axes > 0) {
            openPopover = .more
        }
        .frame(width: layout.moreWell)
        .popover(isPresented: popoverBinding(.more)) {
            RelicMoreFiltersPopover(filter: $filter)
        }
    }

    /// The axes MORE holds that are narrowing the grid: grade, quality,
    /// worn, locked, awakened.
    private var moreCount: Int {
        let axes: [Bool] = [!filter.grades.isEmpty, !filter.qualities.isEmpty, filter.worn != .any,
                            filter.lockedOnly, filter.awakenedOnly]
        return axes.filter { $0 }.count
    }

    private func countLabel(_ snapshot: RelicsSnapshot, width: CGFloat) -> some View {
        Text("\(snapshot.shown.count)/\(snapshot.total)")
            .font(Theme.numeric(12.5))
            .foregroundStyle(RelicPalette.value)
            .lineLimit(1)
            .fixedSize()
            .frame(width: width, height: 30, alignment: .trailing)
            .accessibilityLabel("\(snapshot.shown.count) of \(snapshot.total) relics shown")
    }

    private func popoverBinding(_ which: RelicsFilterPopover) -> Binding<Bool> {
        Binding(
            get: { openPopover == which },
            set: { isShown in
                if !isShown && openPopover == which {
                    openPopover = nil
                }
            }
        )
    }

    private func ownedCounts() -> [RelicSet: Int] {
        var counts: [RelicSet: Int] = [:]
        for relic in store.player.relics {
            counts[relic.set, default: 0] += 1
        }
        return counts
    }

    /// The SET popover's book: the popover goes, then the reference comes —
    /// a sheet presented while a popover is still leaving never appears.
    private func openReferenceFromPopover() {
        openPopover = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            presented = .sets
        }
    }

    @ViewBuilder
    private func gridArea(_ snapshot: RelicsSnapshot, layout: RelicsLayout) -> some View {
        if snapshot.shown.isEmpty {
            emptyGrid(total: snapshot.total)
        } else {
            let hint = tileHint(building: snapshot.unit != nil)
            FadingScroll(fade: 12, bleed: 6, resetKey: gridKey) {
                LazyVGrid(columns: layout.gridColumns, alignment: .leading, spacing: 6) {
                    ForEach(snapshot.shown) { relic in
                        gridCell(relic, snapshot: snapshot, hint: hint)
                    }
                }
                // The stars ride half above the first row's top edge.
                .padding(.top, 5)
                .padding(.bottom, 3)
            }
        }
    }

    private func emptyGrid(total: Int) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.glassRim)
            Text(total == 0 ? "NO RELICS YET" : "NOTHING MATCHES")
                .font(Theme.title(13))
                .tracking(1.2)
                .carved(glow: false)
                .lineLimit(1)
                .fixedSize()
            if total > 0 && !filter.isEmpty {
                RelicPlateButton("Clear filters", height: 34) {
                    withAnimation(Motion.select) {
                        filter = RelicFilter()
                    }
                }
                .frame(width: 150)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One tile of the grid: a tap is the mode's (draft, pick, choose), a
    /// long press opens the card in any mode.
    private func gridCell(_ relic: Relic, snapshot: RelicsSnapshot, hint: String) -> some View {
        Button {
            tapTile(relic, snapshot: snapshot)
        } label: {
            RelicTile(
                relic: relic,
                size: .medium,
                wearer: relic.equippedBy.flatMap { snapshot.faces[$0] },
                showsSlot: filter.slots.count != 1,
                mark: tileMark(relic, build: snapshot.build),
                isSelected: tileLit(relic, snapshot: snapshot),
                dimmed: selecting && relic.isLocked
            )
        }
        // A cell of a scrolling grid: the quiet press, and its tick is in
        // the tap, which only a finished tap reaches.
        .buttonStyle(GamePressStyle(.quiet))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    holdTile(relic)
                }
        )
        .accessibilityHint(hint)
    }

    /// Manage: the draft's gold check on a relic THEN puts on, else the
    /// lock. Selecting: the check or the empty ring. Otherwise the lock.
    private func tileMark(_ relic: Relic, build: RelicsDraftBuild?) -> RelicTileMark {
        if let build {
            let slot = relic.slot
            if build.thenIDs[slot] == relic.id && build.nowIDs[slot] != relic.id {
                return RelicTileMark.inDraft
            }
            return relic.isLocked ? RelicTileMark.locked : RelicTileMark.none
        }
        if selecting {
            return RelicTileMark.selectable(chosenIDs.contains(relic.id))
        }
        return relic.isLocked ? RelicTileMark.locked : RelicTileMark.none
    }

    /// The gold ring: the bag's picked relic, outside select mode.
    private func tileLit(_ relic: Relic, snapshot: RelicsSnapshot) -> Bool {
        snapshot.unit == nil && !selecting && snapshot.picked?.id == relic.id
    }

    private func tileHint(building: Bool) -> String {
        if building {
            return "Puts it in the build, or takes it out. Hold to open its card."
        }
        if selecting {
            return "Chooses it for selling."
        }
        return "Shows it in the panel. Tap again, or hold, to open its card."
    }

    private func tapTile(_ relic: Relic, snapshot: RelicsSnapshot) {
        if suppressTap {
            suppressTap = false
            return
        }
        if snapshot.unit != nil {
            draftTap(relic)
        } else if selecting {
            chooseTap(relic)
        } else {
            pickTap(relic, picked: snapshot.picked)
        }
    }

    /// A long press opens the card; the lift that ends it is swallowed
    /// (`suppressTap`, cleared again when the card goes).
    private func holdTile(_ relic: Relic) {
        suppressTap = true
        Juice.haptic(.medium)
        openCard(relic)
    }

    /// The bag: a tap picks; a tap on the picked one opens its card.
    private func pickTap(_ relic: Relic, picked: Relic?) {
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap)
        if picked?.id == relic.id {
            openCard(relic)
        } else {
            withAnimation(Motion.select) {
                pickedID = relic.id
            }
        }
    }

    /// Select mode: a tap chooses or unchooses; a locked relic refuses.
    private func chooseTap(_ relic: Relic) {
        guard !relic.isLocked else {
            Juice.notify(.warning)
            return
        }
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap)
        // Built outside the animation: a closure whose one statement is an
        // if/else can be read as an if-EXPRESSION, and `remove` and `insert`
        // return different types.
        var next = chosenIDs
        if next.contains(relic.id) {
            _ = next.remove(relic.id)
        } else {
            _ = next.insert(relic.id)
        }
        withAnimation(Motion.select) {
            chosenIDs = next
        }
    }

    private func openCard(_ relic: Relic) {
        presented = .card(relic.id)
    }

    // MARK: - The notice

    /// What a menu just did, for 2.4 seconds over the grid's top: the grid
    /// and the ledger move, but a player needs to be told a preview is not
    /// yet worn.
    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice.text)
                .font(Theme.body(12).weight(.bold))
                .foregroundStyle(notice.isWarning ? RelicPalette.loss : RelicPalette.gain)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(RelicPalette.well))
                .overlay(Capsule().strokeBorder(RelicPalette.bronze, lineWidth: 1))
                .compositingGroup()
                .shadow(color: Color.black.opacity(0.5), radius: 6, y: 2)
                .id(notice.stamp)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func post(_ text: String, warning: Bool = false) {
        noticeStamp += 1
        let stamp = noticeStamp
        withAnimation(Motion.select) {
            notice = RelicsNotice(text: text, isWarning: warning, stamp: stamp)
        }
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard notice?.stamp == stamp else { return }
            withAnimation(Motion.exit) {
                notice = nil
            }
        }
    }

    // MARK: - Leaving, asking, presenting

    /// Back: straight out, or — with a draft not applied — the card that
    /// offers Apply or Leave.
    private func leave() {
        let pending = unitID == nil ? 0 : RelicReading.draftChanges(now: nowIDs, then: effectiveDraft)
        if pending > 0 {
            confirm = .leaveDraft(changes: pending)
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private var confirmLayer: some View {
        if let confirm {
            RelicConfirmCard(confirm: confirm, onConfirm: {
                confirmed(confirm)
            }, onCancel: {
                cancelled(confirm)
            })
        }
    }

    private func confirmed(_ ask: RelicConfirm) {
        confirm = nil
        switch ask {
        case .sell(let relics, _):
            sell(relics.map { $0.id })
        case .leaveDraft:
            apply()
            dismiss()
        case .reappraise, .awaken:
            break
        }
    }

    /// Cancel keeps the screen; the draft card's cancel is LEAVE, which
    /// leaves without applying.
    private func cancelled(_ ask: RelicConfirm) {
        confirm = nil
        if case .leaveDraft = ask {
            dismiss()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: RelicsScreenSheet) -> some View {
        switch sheet {
        case .card(let relicID):
            RelicCard(relicID: relicID)
                .environmentObject(store)
        case .wearer(let relicID):
            RelicWearerChooser(relicID: relicID)
                .environmentObject(store)
        case .sets:
            RelicSetsReference(unitID: unitID)
                .environmentObject(store)
        case .boons:
            BoonPickerView()
                .environmentObject(store)
        }
    }

    // MARK: - Opening

    private func openOnce() {
        guard !openingDone else { return }
        openingDone = true
        if let unitID, let unit = store.player.unit(unitID) {
            draft = unit.equippedRelics
        }
        draftReady = true
        begin(opening)
    }

    private func begin(_ opening: RelicsOpening) {
        switch opening {
        case .plain:
            break
        case .slot(let slot):
            filter.slots = [slot]
        case .bestSix(let goal):
            runBestSix(goal)
        case .fillEmpty:
            runFillEmpty()
        case .withRelic(let relicID):
            takeInto(relicID)
        case .set(let relicSet):
            filter.sets = [relicSet]
        case .picked(let relicID):
            pickedID = relicID
        case .tourDraft:
            tourDraft()
        case .tourMoreFilters:
            openPopoverSoon(.more)
        case .tourSetPicker:
            openPopoverSoon(.set)
        case .tourSelect:
            tourChoose()
        case .tourConfirmSell:
            tourChoose()
            askSell(chosenRelics())
        }
    }

    /// A popover presented as the screen appears presents from nothing: a
    /// beat later (the filter sheet's lesson).
    private func openPopoverSoon(_ which: RelicsFilterPopover) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            openPopover = which
        }
    }

    /// The tour's draft: the best free relic for the unit's role in slots 2
    /// and 4, so two changes, their deltas and their set chips show.
    private func tourDraft() {
        guard let unitID, let unit = store.resolved(unitID) else { return }
        let role = unit.role
        var plan = effectiveDraft
        for slot in [2, 4] {
            let free = store.player.relics.filter { $0.slot == slot && $0.equippedBy == nil }
            let best = free.max { RelicService.efficiency($0, for: role) < RelicService.efficiency($1, for: role) }
            if let best {
                plan[slot] = best.id
            }
        }
        draft = plan
        draftReady = true
    }

    /// The tour's selection: select mode with the grid's first four unlocked
    /// relics chosen.
    private func tourChoose() {
        let firstFour = sortedRelics(role: fitRole).filter { !$0.isLocked }.prefix(4)
        selecting = true
        chosenIDs = Set(firstFour.map { $0.id })
    }

    // MARK: - Keeping state honest

    private func remember(_ order: RelicsSort) {
        guard unitID == nil, !Self.isTour else { return }
        UserDefaults.standard.set(order.rawValue, forKey: Self.bagSortKey)
    }

    /// A relic sold from its card leaves THEN and the selection.
    private func prune() {
        if draftReady {
            draft = livePlan(draft)
        }
        chosenIDs = chosenIDs.filter { store.player.relic($0) != nil }
    }

    /// NOW changed under the draft — a relic removed or moved from its card,
    /// opened off the NOW row. THEN holds the player's own changes and
    /// nothing else, so every slot the draft had left as it was follows NOW:
    /// otherwise the screen would count the card's change as one of its own,
    /// and Apply would undo it.
    private func rebase(from old: [Int: UUID], to new: [Int: UUID]) {
        guard draftReady else { return }
        var next = draft
        for slot in 1...6 where next[slot] == old[slot] {
            next[slot] = new[slot]
        }
        draft = next
    }
}

// MARK: - The screen's reading and measures

/// One render's reading of the store (`RelicsScreen.makeSnapshot`).
private struct RelicsSnapshot {
    /// The unit being built; nil in the bag.
    let unit: ResolvedUnit?
    let build: RelicsDraftBuild?
    /// The grid: filtered and sorted.
    let shown: [Relic]
    /// Every relic owned.
    let total: Int
    /// Every wearer, by id.
    let faces: [UUID: ResolvedUnit]
    /// The bag's panel relic.
    let picked: Relic?
}

/// NOW and THEN, and what THEN would make of the unit.
private struct RelicsDraftBuild {
    let nowIDs: [Int: UUID]
    let thenIDs: [Int: UUID]
    let nowRelics: [Int: Relic]
    let thenRelics: [Int: Relic]
    let thenUnit: ResolvedUnit
    let changes: Int
}

/// How Manage's header fits a long name or a long power difference.
private struct RelicsHeaderFit {
    /// The difference beside POWER instead of after the figures.
    let deltaAbove: Bool
    /// The name on two lines at 13, the stars left to the face.
    let twoLines: Bool
}

/// One chip of Manage's SETS row.
private struct RelicsSetChip: Identifiable {
    let id: String
    let text: String
    let tone: Color
}

/// The line over the grid for a moment (`RelicsScreen.post`).
private struct RelicsNotice: Equatable {
    let text: String
    let isWarning: Bool
    let stamp: Int
}

/// What the screen presents over itself.
private enum RelicsScreenSheet: Identifiable {
    case card(UUID)
    case wearer(UUID)
    case sets
    case boons

    var id: String {
        switch self {
        case .card(let relicID): return "card-\(relicID.uuidString)"
        case .wearer(let relicID): return "wearer-\(relicID.uuidString)"
        case .sets: return "sets"
        case .boons: return "boons"
        }
    }
}

/// The four wells' popovers.
private enum RelicsFilterPopover {
    case set, main, sub, more
}

/// The Relics screen's measures, from the width its content is given — never
/// the phone's constants (spec §1). The left panel is 310 on every phone; the
/// right takes the rest, and the grid packs as many 48-point tiles as leave a
/// gap of four or more: 7 across on the design target and the CI's phone, 9
/// on a Pro Max, 5 on an SE. (The spec's own formula, `(inner + 6) / 54`,
/// gives 6 and 8 on the first and third, against the 7 and 9 it states and
/// the mock draws; the stated results are what this reproduces.)
private struct RelicsLayout {
    static let leftWidth: CGFloat = 310
    static let leftInner: CGFloat = 286
    static let tile: CGFloat = 48
    static let diagramWidth: CGFloat = RelicRosette.frameSize(radius: 12, gap: 2).width

    let rightInner: CGFloat
    let columns: Int
    let spacing: CGFloat
    /// SET and MAIN, side by side.
    let pairWell: CGFloat
    /// MORE, at the width its eyebrow and a dash take.
    let moreWell: CGFloat
    /// SUB, the rest of its row.
    let subWell: CGFloat
    /// The "38/214" count, at its widest ("214/214").
    let countWidth: CGFloat
    /// Whether the count has room beside SUB; on an SE the strip's subtitle
    /// carries it instead.
    let showsCount: Bool

    init(width: CGFloat, total: Int) {
        let inner: CGFloat = max(0, width - 24 - Self.leftWidth - 8 - 24)
        rightInner = inner
        let fitted = Int((inner + 4) / 52)
        columns = max(4, fitted)
        let free = inner - CGFloat(columns) * Self.tile
        spacing = max(2, free / CGFloat(max(1, columns - 1)))
        let wells = max(0, inner - Self.diagramWidth - 10)
        pairWell = max(0, (wells - 8) / 2)
        moreWell = RelicsWellText.naturalWidth(eyebrow: "More", value: "—")
        countWidth = RelicsMeasure.width("\(total)/\(total)", face: RelicsMeasure.boldFace, size: 12.5) + 1
        let beside = wells - moreWell - 8 - countWidth - 8
        showsCount = beside >= 110
        subWell = max(0, showsCount ? beside : wells - moreWell - 8)
    }

    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.tile), spacing: spacing), count: columns)
    }
}

/// Text widths in the bundled faces, for the few things on this screen that
/// choose a long or a short form before they draw — a well's value, the
/// header's name, the SETS chips — because the kit draws each at its own
/// width (`fixedSize`) and a cut label reads as a broken one.
private enum RelicsMeasure {
    static let boldFace = Theme.numberFace
    static let blackFace = "Manrope-ExtraBold"

    static func width(_ text: String, face: String, size: CGFloat, tracking: CGFloat = 0) -> CGFloat {
        let font = UIFont(name: face, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(measured + tracking * CGFloat(text.count))
    }

    /// The wells' chevron, SF `chevron.down` at 10 points, black.
    static let chevronWidth: CGFloat = {
        let shape = UIImage.SymbolConfiguration(pointSize: 10, weight: .black)
        let measured = UIImage(systemName: "chevron.down", withConfiguration: shape)?.size.width ?? 11
        return ceil(max(10, measured))
    }()
}

/// The wells' values, shortened by the caller as the kit asks (spec §2.5):
/// the fullest form that fits the well, then shorter ones, and last a bare
/// count, which always fits.
private enum RelicsWellText {
    /// The room a well leaves its value: the kit's 8 points of padding a
    /// side, 6 between its parts, the chevron and a spacer of at least 4
    /// after the value, and the set's stone at 20 when it carries one.
    static func room(width: CGFloat, eyebrow: String, emblem: Bool) -> CGFloat {
        let label = RelicsMeasure.width(eyebrow.uppercased(), face: RelicsMeasure.blackFace, size: 11, tracking: 0.6)
        let parts: CGFloat = emblem ? 20 + 4 * 6 : 3 * 6
        return width - 16 - label - 4 - RelicsMeasure.chevronWidth - parts - 1
    }

    /// A well's width at its content's own size.
    static func naturalWidth(eyebrow: String, value: String) -> CGFloat {
        let label: CGFloat = RelicsMeasure.width(eyebrow.uppercased(), face: RelicsMeasure.blackFace, size: 11, tracking: 0.6)
        let figure: CGFloat = RelicsMeasure.width(value, face: RelicsMeasure.boldFace, size: 13)
        // The padding (16), the spacer (4), three gaps of 6 and a point
        // over, as one typed constant: seven terms in one call to the
        // overloaded `ceil` is the shape that times the type checker out.
        let fixed: CGFloat = 16 + 4 + 3 * 6 + 1
        let total: CGFloat = fixed + label + figure + RelicsMeasure.chevronWidth
        return ceil(total)
    }

    static func fits(_ text: String, room: CGFloat) -> Bool {
        RelicsMeasure.width(text, face: RelicsMeasure.boldFace, size: 13) <= room
    }

    static func firstFitting(_ forms: [String], room: CGFloat) -> String? {
        forms.first { fits($0, room: room) }
    }

    /// SET: "Any", the one set with its stone, or the first set "+n".
    static func sets(_ chosen: Set<RelicSet>, width: CGFloat) -> (text: String, emblem: RelicSet?) {
        let ordered = RelicSet.allCases.filter { chosen.contains($0) }
        guard let lead = ordered.first else { return (text: "Any", emblem: nil) }
        let plain = room(width: width, eyebrow: "Set", emblem: false)
        if ordered.count == 1 {
            if fits(lead.displayName, room: room(width: width, eyebrow: "Set", emblem: true)) {
                return (text: lead.displayName, emblem: lead)
            }
            return (text: firstFitting([lead.displayName, "1 set"], room: plain) ?? "1", emblem: nil)
        }
        let forms = ["\(lead.displayName) +\(ordered.count - 1)", "\(ordered.count) sets"]
        return (text: firstFitting(forms, room: plain) ?? "\(ordered.count)", emblem: nil)
    }

    /// MAIN: "Any", "ATK %", or "ATK % +1".
    static func mains(_ chosen: Set<StatKind>, width: CGFloat) -> String {
        let ordered = StatKind.allCases.filter { chosen.contains($0) }
        guard let lead = ordered.first else { return "Any" }
        let space = room(width: width, eyebrow: "Main", emblem: false)
        let rest = ordered.count - 1
        var forms: [String] = [lead.displayName, short(lead)]
        if rest > 0 {
            forms = ["\(lead.displayName) +\(rest)", "\(short(lead)) +\(rest)", "\(ordered.count) stats"]
        }
        return firstFitting(forms, room: space) ?? "\(ordered.count)"
    }

    /// SUB: "Any", one name, "SPD · CRIT Rate", or the two "+n".
    static func subs(_ chosen: Set<StatKind>, width: CGFloat) -> String {
        let ordered = RelicService.subStatPool.filter { chosen.contains($0) }
        guard let lead = ordered.first else { return "Any" }
        let space = room(width: width, eyebrow: "Sub", emblem: false)
        var forms: [String] = [lead.displayName, short(lead)]
        if ordered.count > 1 {
            let second = ordered[1]
            let tail = ordered.count > 2 ? " +\(ordered.count - 2)" : ""
            forms = [
                "\(lead.displayName) · \(second.displayName)\(tail)",
                "\(short(lead)) · \(short(second))\(tail)",
                "\(short(lead)) +\(ordered.count - 1)",
                "\(ordered.count) stats",
            ]
        }
        return firstFitting(forms, room: space) ?? "\(ordered.count)"
    }

    /// The genre's own short names for the four long stats (Summoners War's
    /// rune filter reads "CRI Rate"), used only when the full one does not
    /// fit its well: on the design target a lone CRIT Rate in SUB is six
    /// points too wide for the kit's well, "CRI Rate" fits with three over.
    static func short(_ kind: StatKind) -> String {
        switch kind {
        case .critRate: return "CRI Rate"
        case .critDamage: return "CRI DMG"
        case .accuracy: return "ACC"
        case .resistance: return "RES"
        default: return kind.displayName
        }
    }
}

// MARK: - The scroll

/// A column that scrolls only when its content is taller than its frame, and
/// only then fades its last `fade` points into the panel, its content padded
/// by as much so the last row scrolls clear — the old `RelicFitScroll`'s
/// logic, measured with a GeometryReader, never `ViewThatFits`. A new
/// `resetKey` starts it again at the top (a new filter, a new relic). The
/// relic card keeps its own copy as `CardFadingScroll`.
///
/// `bleed` lets the content draw that far past the scroll's sides, into the
/// panel's padding: a tile's gold ring stands 2.5 points outside it, the
/// awakened halo 1.5 and the wearer's face 2, and a scroll clipped at its own
/// edge shaved all three off every tile in the first and last columns. The
/// fade's mask still clips the top and the foot.
private struct FadingScroll<Content: View>: View {
    let fade: CGFloat
    let bleed: CGFloat
    let resetKey: String
    let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    init(fade: CGFloat = 12, bleed: CGFloat = 0, resetKey: String = "",
         @ViewBuilder content: @escaping () -> Content) {
        self.fade = fade
        self.bleed = bleed
        self.resetKey = resetKey
        self.content = content
    }

    private var overflows: Bool { contentHeight > viewportHeight + 0.5 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            content()
                .background(contentReader)
                .padding(.bottom, overflows ? fade : 0)
        }
        .id(resetKey)
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled(bleed > 0)
        .background(viewportReader)
        .mask {
            footMask
                .padding(.horizontal, -bleed)
        }
    }

    private var contentReader: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            Color.clear
                .onAppear { contentHeight = height }
                .onChange(of: height) { _, measured in contentHeight = measured }
        }
    }

    private var viewportReader: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            Color.clear
                .onAppear { viewportHeight = height }
                .onChange(of: height) { _, measured in viewportHeight = measured }
        }
    }

    /// Opaque to the foot when the content fits; a fade over the last
    /// `fade` points when it does not.
    private var footMask: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: overflows ? fade : 0)
        }
    }
}

// MARK: - The popovers

/// A popover's ground: basalt to its edges, a popover even on a phone.
private struct RelicsPopoverGround: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(width: width, alignment: .leading)
            .background(RelicPalette.basaltFoot)
            .presentationBackground(RelicPalette.basaltFoot)
            .presentationCompactAdaptation(.popover)
    }
}

/// A chip of a filter popover: a dark well, gold leaf with dark ink when on.
/// A quality chip (`tone`) reads in its quality's colour and lights in it.
private struct RelicsWellChip: View {
    let title: String
    let isOn: Bool
    var tone: Color? = nil
    var height: CGFloat = 30
    let action: () -> Void

    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(12).weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(ground)
                .contentShape(outline)
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var ink: Color {
        if let tone {
            return tone
        }
        return isOn ? RelicPalette.goldInk : RelicPalette.value
    }

    @ViewBuilder
    private var ground: some View {
        if let tone {
            outline.fill(isOn ? tone.opacity(0.25) : RelicPalette.well)
                .overlay(outline.strokeBorder(isOn ? tone : RelicPalette.bronze, lineWidth: isOn ? 1.5 : 1))
        } else if isOn {
            outline.fill(RelicPalette.goldLeaf)
        } else {
            outline.fill(RelicPalette.well)
                .overlay(outline.strokeBorder(RelicPalette.bronze, lineWidth: 1))
        }
    }
}

/// SET: the sixteen sets as their stones, each with its name and how many
/// are owned, several at once; ANY clears, the book opens the reference.
private struct RelicSetPickerPopover: View {
    @Binding var selection: Set<RelicSet>
    let owned: [RelicSet: Int]
    let onReference: () -> Void

    private static let columns: [GridItem] = Array(repeating: GridItem(.fixed(72), spacing: 4), count: 4)
    private static let litRim: Color = Color(hex: "#FFE08A")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 4) {
                ForEach(RelicSet.allCases) { relicSet in
                    cell(relicSet)
                }
            }
        }
        .modifier(RelicsPopoverGround(width: 324))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("SETS")
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            RelicsWellChip(title: "Any", isOn: selection.isEmpty, height: 26) {
                selection = []
            }
            .frame(width: 60)
            referenceButton
        }
    }

    private var referenceButton: some View {
        Button(action: onReference) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(RelicPalette.label)
                .frame(width: 34, height: 26)
                .background(Capsule().fill(RelicPalette.well))
                .overlay(Capsule().strokeBorder(RelicPalette.bronze, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("What every set does")
    }

    private func toggle(_ relicSet: RelicSet) {
        if selection.contains(relicSet) {
            _ = selection.remove(relicSet)
        } else {
            _ = selection.insert(relicSet)
        }
    }

    private func cell(_ relicSet: RelicSet) -> some View {
        let isOn = selection.contains(relicSet)
        let count = owned[relicSet] ?? 0
        return Button {
            toggle(relicSet)
        } label: {
            VStack(spacing: 1) {
                RelicSetEmblem(set: relicSet, size: 30)
                Text(relicSet.displayName)
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(RelicPalette.value)
                    .lineLimit(1)
                    .fixedSize()
                Text("\(count)")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 72, height: 62)
            .background(cellGround(isOn))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("\(relicSet.displayName), \(count) owned")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func cellGround(_ isOn: Bool) -> some View {
        let outline = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if isOn {
            outline.fill(RelicPalette.well)
                .overlay(outline.strokeBorder(Self.litRim, lineWidth: 1.5))
                .compositingGroup()
                .shadow(color: RelicPalette.star.opacity(0.5), radius: 5)
        } else {
            outline.fill(RelicPalette.well)
                .overlay(outline.strokeBorder(RelicPalette.bronze, lineWidth: 1))
        }
    }
}

/// MAIN or SUB: the stats as chips, several at once. SUB says its rule once
/// — every sub ticked must be on the relic.
private struct RelicStatPickerPopover: View {
    let title: String
    @Binding var selection: Set<StatKind>
    let kinds: [StatKind]
    var allOfThese: Bool = false

    private static let columns: [GridItem] = Array(repeating: GridItem(.fixed(92), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 6) {
                ForEach(kinds) { kind in
                    RelicsWellChip(title: kind.displayName, isOn: selection.contains(kind)) {
                        toggle(kind)
                    }
                    .frame(width: 92)
                }
            }
        }
        .modifier(RelicsPopoverGround(width: 312))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .lineLimit(1)
                .fixedSize()
            if allOfThese {
                Text("ALL OF THESE")
                    .font(Theme.body(11))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 6)
            RelicsWellChip(title: "Any", isOn: selection.isEmpty, height: 26) {
                selection = []
            }
            .frame(width: 60)
        }
    }

    private func toggle(_ kind: StatKind) {
        if selection.contains(kind) {
            _ = selection.remove(kind)
        } else {
            _ = selection.insert(kind)
        }
    }
}

/// MORE: grade, quality, worn, lock and awakening — the axes the wells do
/// not show — and Clear all, which clears every filter.
private struct RelicMoreFiltersPopover: View {
    @Binding var filter: RelicFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            gradeSection
            qualitySection
            wornSection
            flagSection
            RelicPlateButton("Clear all", finish: .wine, height: 34, isEnabled: !filter.isEmpty) {
                filter = RelicFilter()
            }
        }
        .modifier(RelicsPopoverGround(width: 340))
    }

    private func section(_ title: String, @ViewBuilder chips: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 6) {
                chips()
            }
        }
    }

    private var gradeSection: some View {
        section("Grade") {
            ForEach(1...6, id: \.self) { grade in
                RelicsWellChip(title: "\(grade)★", isOn: filter.grades.contains(grade)) {
                    toggleGrade(grade)
                }
            }
        }
    }

    private var qualitySection: some View {
        section("Quality") {
            ForEach(RelicQuality.allCases) { quality in
                RelicsWellChip(title: quality.displayName, isOn: filter.qualities.contains(quality), tone: quality.tone) {
                    toggleQuality(quality)
                }
            }
        }
    }

    private var wornSection: some View {
        section("Worn") {
            ForEach(RelicFilter.Worn.allCases, id: \.self) { worn in
                RelicsWellChip(title: Self.wornTitle(worn), isOn: filter.worn == worn) {
                    filter.worn = worn
                }
            }
        }
    }

    private var flagSection: some View {
        section("Lock & awakening") {
            RelicsWellChip(title: "Locked only", isOn: filter.lockedOnly) {
                filter.lockedOnly.toggle()
            }
            RelicsWellChip(title: "Awakened only", isOn: filter.awakenedOnly) {
                filter.awakenedOnly.toggle()
            }
        }
    }

    private static func wornTitle(_ worn: RelicFilter.Worn) -> String {
        switch worn {
        case .any: return "Any"
        case .unequipped: return "Free"
        case .equipped: return "Worn"
        }
    }

    private func toggleGrade(_ grade: Int) {
        if filter.grades.contains(grade) {
            _ = filter.grades.remove(grade)
        } else {
            _ = filter.grades.insert(grade)
        }
    }

    private func toggleQuality(_ quality: RelicQuality) {
        if filter.qualities.contains(quality) {
            _ = filter.qualities.remove(quality)
        } else {
            _ = filter.qualities.insert(quality)
        }
    }
}
