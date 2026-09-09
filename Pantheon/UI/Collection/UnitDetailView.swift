import SwiftUI

/// One unit: stats, skills, relics, and the progression actions.
struct UnitDetailView: View {
    let unitID: UUID

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .overview
    @State private var pickingSlot: SlotPick?
    @State private var showFodderPicker = false
    @State private var fodderPurpose: FodderPurpose = .levelUp

    enum Tab: String, CaseIterable, Identifiable {
        case overview, skills, relics
        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }
    }

    enum FodderPurpose { case levelUp, evolve }

    private var unit: ResolvedUnit? { store.resolved(unitID) }

    var body: some View {
        NavigationStack {
            Group {
                if let unit {
                    ScrollView {
                        VStack(spacing: 12) {
                            header(unit)
                            Picker("", selection: $tab) {
                                ForEach(Tab.allCases) { tab in
                                    Text(tab.displayName).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)

                            switch tab {
                            case .overview: overview(unit)
                            case .skills: skills(unit)
                            case .relics: relics(unit)
                            }
                        }
                        .padding(12)
                    }
                } else {
                    EmptyState(icon: "questionmark", title: "Gone", message: "This unit is no longer in your collection.")
                }
            }
            .screen(unit?.name ?? "Unit")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.toggleLock(unitID)
                    } label: {
                        Image(systemName: unit?.unit.isLocked == true ? "lock.fill" : "lock.open")
                            .foregroundStyle(unit?.unit.isLocked == true ? Theme.gold : Theme.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showFodderPicker) {
                if let unit {
                    FodderPickerView(target: unit, purpose: fodderPurpose)
                        .environmentObject(store)
                }
            }
        }
    }

    // MARK: - Header

    private func header(_ unit: ResolvedUnit) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                UnitCard(unit: unit, size: 108)

                VStack(alignment: .leading, spacing: 6) {
                    Text(unit.blueprint.epithet)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        Text(unit.pantheon.displayName)
                            .font(Theme.body(11).weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(unit.pantheon.color.opacity(0.18)))
                            .foregroundStyle(unit.pantheon.color)
                        Text(unit.archetype.displayName)
                            .font(Theme.body(11).weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.stroke))
                            .foregroundStyle(Theme.textSecondary)
                        Text(unit.role.displayName)
                            .font(Theme.body(11).weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.stroke))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    StatBar(
                        value: Double(unit.unit.experience),
                        maximum: Double(ProgressionService.experienceForNextLevel(
                            level: unit.level, stars: unit.stars
                        )),
                        tint: Theme.info,
                        height: 5,
                        label: "Lv.\(unit.level) / \(unit.unit.maxLevel)"
                    )
                    Text("Power \(unit.power)")
                        .font(Theme.numeric(13))
                        .foregroundStyle(Theme.gold)
                }
            }

            Text(unit.blueprint.lore)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .panelBackground()
    }

    // MARK: - Overview

    private func overview(_ unit: ResolvedUnit) -> some View {
        VStack(spacing: 10) {
            statsPanel(unit)
            if let leader = unit.blueprint.leaderSkill {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Leader Skill")
                    Text(leader.description)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .panelBackground()
            }
            awakeningPanel(unit)
            actionsPanel(unit)
        }
    }

    private func statsPanel(_ unit: ResolvedUnit) -> some View {
        // Base is grade, level and awakening; the difference to the final
        // number is the relics, shown beside it the way the genre does, so
        // equipping a relic is visible on the sheet and not only in battle.
        let base = ProgressionService.baseStats(for: unit.unit, blueprint: unit.blueprint)
        return VStack(spacing: 8) {
            SectionHeader(title: "Stats")
            statRow("HP", base: base.hp, total: unit.stats.hp)
            statRow("ATK", base: base.atk, total: unit.stats.atk)
            statRow("DEF", base: base.def, total: unit.stats.def)
            statRow("SPD", base: base.spd, total: unit.stats.spd)
            statRow("CRIT Rate", base: base.critRate, total: unit.stats.critRate, percent: true)
            statRow("CRIT DMG", base: base.critDamage, total: unit.stats.critDamage, percent: true)
            statRow("Accuracy", base: base.accuracy, total: unit.stats.accuracy, percent: true)
            statRow("Resistance", base: base.resistance, total: unit.stats.resistance, percent: true)

            if !unit.activeRelicSets.isEmpty {
                Divider().overlay(Theme.stroke)
                ForEach(unit.activeRelicSets) { entry in
                    HStack {
                        Text("\(entry.set.displayName) ×\(entry.completions)")
                            .font(Theme.body(12).weight(.semibold))
                            .foregroundStyle(Theme.gold)
                        Spacer()
                        Text(entry.set.effectDescription)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(10)
        .panelBackground()
    }

    private func statRow(_ label: String, base: Double, total: Double, percent: Bool = false) -> some View {
        let bonus = total - base
        let shown = abs(bonus) >= (percent ? 0.005 : 0.5)
        return HStack(spacing: 6) {
            Text(label).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(Self.statText(base, percent: percent))
                .font(Theme.numeric(14))
                .foregroundStyle(Theme.textPrimary)
            if shown {
                Text((bonus > 0 ? "+" : "−") + Self.statText(abs(bonus), percent: percent))
                    .font(Theme.numeric(13))
                    .foregroundStyle(bonus > 0 ? Theme.success : Theme.danger)
            }
        }
    }

    private static func statText(_ value: Double, percent: Bool) -> String {
        percent ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded()))"
    }

    @ViewBuilder
    private func awakeningPanel(_ unit: ResolvedUnit) -> some View {
        if let awakening = unit.blueprint.awakening {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeader(title: "Awakening")
                Text(unit.unit.isAwakened ? awakening.awakenedName : "Not yet awakened")
                    .font(Theme.title(16))
                    .foregroundStyle(unit.unit.isAwakened ? Theme.gold : Theme.textPrimary)
                Text(awakening.bonusDescription)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !unit.unit.isAwakened {
                    let costs = awakening.essenceCost.sorted { $0.key < $1.key }
                    ForEach(costs.indices, id: \.self) { costIndex in
                        let id = costs[costIndex].key
                        let needed = costs[costIndex].value
                        let have = store.player.essences[id] ?? 0
                        HStack {
                            Text(EssenceCatalog.name(for: id))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(have) / \(needed)")
                                .font(Theme.numeric(12))
                                .foregroundStyle(have >= needed ? Theme.success : Theme.danger)
                        }
                    }
                    PrimaryButton(
                        title: "Awaken",
                        systemImage: "sun.max.fill",
                        isEnabled: awakening.essenceCost.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
                    ) {
                        store.awaken(unitID)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .panelBackground()
        }
    }

    private func actionsPanel(_ unit: ResolvedUnit) -> some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Progression")
            PrimaryButton(title: "Level up with fodder", systemImage: "arrow.up.circle.fill", tint: Theme.info) {
                fodderPurpose = .levelUp
                showFodderPicker = true
            }
            PrimaryButton(
                title: unit.unit.canEvolve
                    ? "Evolve to \(unit.stars + 1)★ — \(ProgressionService.evolutionFodderRequired(currentStars: unit.stars)) fodder"
                    : "Evolve (needs max level)",
                systemImage: "star.circle.fill",
                isEnabled: unit.unit.canEvolve
            ) {
                fodderPurpose = .evolve
                showFodderPicker = true
            }
        }
        .padding(10)
        .panelBackground()
    }

    // MARK: - Skills

    private func skills(_ unit: ResolvedUnit) -> some View {
        VStack(spacing: 12) {
            ForEach(unit.skills.indices, id: \.self) { index in
                let skill = unit.skills[index]
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(skill.name)
                            .font(Theme.title(16))
                            .foregroundStyle(Theme.textPrimary)
                        if skill.isPassive {
                            Text("PASSIVE")
                                .font(Theme.body(8).weight(.black))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.gold.opacity(0.25)))
                                .foregroundStyle(Theme.gold)
                        }
                        Spacer()
                        if skill.cooldown > 0 {
                            Label("\(skill.cooldown)", systemImage: "clock.fill")
                                .font(Theme.numeric(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Text(skill.description)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let damage = skill.damage {
                        HStack(spacing: 12) {
                            metric("Multiplier", "\(String(format: "%.2f", damage.multiplier))×")
                            if damage.hits > 1 { metric("Hits", "\(damage.hits)") }
                            if damage.defenseIgnore > 0 {
                                metric("DEF ignore", "\(Int(damage.defenseIgnore * 100))%")
                            }
                            metric(
                                "Est. damage",
                                "\(Int(DamageCalculator.previewDamage(attackStat: unit.stats.atk, spec: damage)))"
                            )
                        }
                    }

                    let level = unit.unit.skillLevels.indices.contains(index) ? unit.unit.skillLevels[index] : 1
                    if !skill.levelUpBonuses.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(skill.levelUpBonuses.indices, id: \.self) { bonusIndex in
                                let bonus = skill.levelUpBonuses[bonusIndex]
                                HStack(spacing: 6) {
                                    Image(systemName: level > bonusIndex + 1 ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(level > bonusIndex + 1 ? Theme.success : Theme.stroke)
                                    Text("Lv.\(bonusIndex + 2) — \(bonus.label)")
                                        .font(Theme.body(11))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .panelBackground()
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Theme.body(9)).foregroundStyle(Theme.textSecondary)
            Text(value).font(Theme.numeric(13)).foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Relics

    /// A slot number that can drive a sheet.
    struct SlotPick: Identifiable {
        let id: Int
    }

    private func relics(_ unit: ResolvedUnit) -> some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "Auto-equip best available", systemImage: "wand.and.stars", tint: Theme.info) {
                store.autoEquip(unitID)
            }

            // The sets in play, the way the genre shows them on the sheet.
            if !unit.activeRelicSets.isEmpty {
                HStack(spacing: 6) {
                    ForEach(unit.activeRelicSets) { entry in
                        Text(entry.completions > 1 ? "\(entry.set.displayName) ×\(entry.completions)" : entry.set.displayName)
                            .font(Theme.body(11).weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.surfaceHigh))
                            .foregroundStyle(Theme.gold)
                    }
                    Spacer()
                }
            }

            ForEach(1...6, id: \.self) { slot in
                relicSlot(slot: slot, unit: unit)
            }
        }
        .sheet(item: $pickingSlot) { pick in
            RelicPickerView(unitID: unitID, slot: pick.id)
                .environmentObject(store)
        }
    }

    private func relicSlot(slot: Int, unit: ResolvedUnit) -> some View {
        let equipped = unit.unit.equippedRelics[slot].flatMap { store.player.relic($0) }

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Slot \(slot)")
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.goldDim)
                Spacer()
                if let equipped {
                    Text("\(equipped.set.displayName) +\(equipped.level)")
                        .font(Theme.body(12).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            if let equipped {
                let stats = equipped.allStats
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
                HStack(spacing: 10) {
                    Button {
                        store.upgradeRelic(equipped.id)
                    } label: {
                        Text(equipped.isMaxLevel
                             ? "Max"
                             : "Upgrade — \(RelicService.upgradeCost(grade: equipped.grade, level: equipped.level))")
                            .font(Theme.body(11).weight(.semibold))
                            .foregroundStyle(equipped.isMaxLevel ? Theme.textSecondary : Theme.gold)
                    }
                    .disabled(equipped.isMaxLevel)

                    Button("Unequip") { store.unequip(slot: slot, from: unitID) }
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Change") { pickingSlot = SlotPick(id: slot) }
                        .font(Theme.body(11).weight(.semibold))
                        .foregroundStyle(Theme.info)
                    Spacer()
                }
            } else {
                HStack {
                    Text("Empty")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Choose") { pickingSlot = SlotPick(id: slot) }
                        .font(Theme.body(11).weight(.semibold))
                        .foregroundStyle(Theme.info)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panelBackground(radius: Theme.tightCorner)
    }
}

/// Picks units to consume for levelling or evolution.
struct FodderPickerView: View {
    let target: ResolvedUnit
    let purpose: UnitDetailView.FodderPurpose

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    private var candidates: [ResolvedUnit] {
        store.resolvedUnits.filter { candidate in
            guard candidate.id != target.id, !candidate.unit.isLocked else { return false }
            if purpose == .evolve { return candidate.stars == target.stars }
            return true
        }
        .sorted { $0.power < $1.power }
    }

    private var required: Int {
        purpose == .evolve
            ? ProgressionService.evolutionFodderRequired(currentStars: target.stars)
            : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if candidates.isEmpty {
                    EmptyState(
                        icon: "tray",
                        title: "No fodder available",
                        message: purpose == .evolve
                            ? "Evolution needs \(required) unlocked units at exactly \(target.stars)★."
                            : "Every other unit you own is locked."
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 10)], spacing: 12) {
                        ForEach(candidates) { candidate in
                            Button {
                                toggle(candidate.id)
                            } label: {
                                UnitCard(unit: candidate, isSelected: selection.contains(candidate.id), size: 96)
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .screen(purpose == .evolve ? "Evolve" : "Level Up")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if purpose == .evolve {
                        Text("\(selection.count) / \(required) selected · \(ProgressionService.drachmaCostToEvolve(currentStars: target.stars)) drachma")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        let xp = candidates
                            .filter { selection.contains($0.id) }
                            .reduce(0) { $0 + ProgressionService.feedValue(of: $1.unit) }
                        Text("+\(xp) EXP · \(selection.count * 500) drachma")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    PrimaryButton(
                        title: purpose == .evolve ? "Evolve" : "Consume",
                        isEnabled: purpose == .evolve ? selection.count == required : !selection.isEmpty
                    ) {
                        commit()
                    }
                }
                .padding(12)
                .background(Theme.ink)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else if purpose != .evolve || selection.count < required {
            selection.insert(id)
        }
    }

    private func commit() {
        let ids = Array(selection)
        switch purpose {
        case .levelUp: store.levelUp(target.id, feeding: ids)
        case .evolve: store.evolve(target.id, fodderIDs: ids)
        }
        dismiss()
    }
}
