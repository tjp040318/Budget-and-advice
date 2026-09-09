import SwiftUI

/// One unit on one screen, the way the genre lays it out: the card and its
/// progress on the left, the six relic slots in a ring in the middle, the
/// stats with their relic bonuses on the right, and the skills along the
/// bottom with their words a tap away. Nothing to scroll for on a landscape
/// phone; the lore sits behind the book, and the fodder pickers open as
/// sheets. A relic slot opens the picker for that slot.
struct UnitDetailView: View {
    let unitID: UUID

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickingSlot: SlotPick?
    @State private var showFodderPicker = false
    @State private var fodderPurpose: FodderPurpose = .levelUp
    @State private var showAwakening = false
    @State private var showLore = false
    @State private var selectedSkill = 0

    /// A slot number that can drive a sheet.
    struct SlotPick: Identifiable {
        let id: Int
    }

    enum FodderPurpose { case levelUp, evolve }

    private var unit: ResolvedUnit? { store.resolved(unitID) }
    private var isLocked: Bool { unit?.unit.isLocked == true }

    var body: some View {
        NavigationStack {
            Group {
                if let unit {
                    ScrollView {
                        // Three columns, sized so a landscape phone holds
                        // the lot without a scroll: card and actions, the
                        // ring, then stats over skills.
                        HStack(alignment: .top, spacing: 8) {
                            identity(unit)
                                .frame(width: 158)
                            relicRing(unit)
                                .frame(width: 212)
                            VStack(spacing: 8) {
                                stats(unit)
                                skills(unit)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(10)
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
                    HStack(spacing: 16) {
                        Button {
                            showLore = true
                        } label: {
                            Image(systemName: "book.fill")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Button {
                            Juice.haptic(.light)
                            store.autoEquip(unitID)
                        } label: {
                            Label("Auto-equip", systemImage: "wand.and.stars")
                                .font(Theme.body(12).weight(.semibold))
                                .foregroundStyle(Theme.info)
                        }
                        Button {
                            store.toggleLock(unitID)
                        } label: {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                                .foregroundStyle(isLocked ? Theme.gold : Theme.textSecondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showFodderPicker) {
                if let unit {
                    FodderPickerView(target: unit, purpose: fodderPurpose)
                        .environmentObject(store)
                }
            }
            .sheet(item: $pickingSlot) { pick in
                RelicPickerView(unitID: unitID, slot: pick.id)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAwakening) {
                if let unit {
                    AwakeningSheet(unit: unit)
                        .environmentObject(store)
                }
            }
            .alert(unit?.blueprint.epithet ?? "", isPresented: $showLore) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(unit?.blueprint.lore ?? "")
            }
        }
    }

    // MARK: - Left: the card and what to do with it

    private func identity(_ unit: ResolvedUnit) -> some View {
        VStack(spacing: 6) {
            UnitCard(unit: unit, size: 100)
            HStack(spacing: 4) {
                ElementBadge(element: unit.element, compact: true)
                Text(unit.blueprint.epithet)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            StatBar(
                value: Double(unit.unit.experience),
                maximum: Double(ProgressionService.experienceForNextLevel(level: unit.level, stars: unit.stars)),
                tint: Theme.info,
                height: 5,
                label: "Lv.\(unit.level) / \(unit.unit.maxLevel)"
            )
            // The three things to do with a unit, in one row.
            HStack(spacing: 5) {
                actionButton("Power up", "arrow.up.circle.fill", tint: Theme.info) {
                    fodderPurpose = .levelUp
                    showFodderPicker = true
                }
                actionButton(
                    unit.unit.canEvolve ? "Evolve" : "Evolve at max",
                    "star.circle.fill", tint: Theme.gold, enabled: unit.unit.canEvolve
                ) {
                    fodderPurpose = .evolve
                    showFodderPicker = true
                }
                if unit.blueprint.awakening != nil {
                    actionButton(
                        unit.unit.isAwakened ? "Awakened" : "Awaken",
                        "sun.max.fill", tint: Theme.gold, enabled: !unit.unit.isAwakened
                    ) {
                        showAwakening = true
                    }
                }
            }
        }
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func actionButton(
        _ title: String, _ symbol: String, tint: Color, enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(Theme.body(7).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(enabled ? Theme.ink : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(enabled ? tint : Theme.surface)
            )
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(!enabled)
    }

    // MARK: - Middle: the relic ring

    /// Six slots around the element's emblem, slot 1 at the top and the
    /// rest clockwise — the arrangement every player of the genre knows.
    private func relicRing(_ unit: ResolvedUnit) -> some View {
        let size: CGFloat = 196
        let radius: CGFloat = 70
        let centre = CGPoint(x: size / 2, y: size / 2)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(centre)
                ZStack {
                    Circle()
                        .fill(unit.element.color.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: unit.element.glyph)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(unit.element.color)
                }
                .position(centre)
                ForEach(1...6, id: \.self) { slot in
                    let angle = (Double(slot - 1) * 60 - 90) * Double.pi / 180
                    slotTile(slot: slot, unit: unit)
                        .position(
                            x: centre.x + CGFloat(cos(angle)) * radius,
                            y: centre.y + CGFloat(sin(angle)) * radius
                        )
                }
            }
            .frame(width: size, height: size)
            setsRow(unit)
        }
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func slotTile(slot: Int, unit: ResolvedUnit) -> some View {
        let relic = unit.unit.equippedRelics[slot].flatMap { store.player.relic($0) }
        let worn = relic != nil
        return Button {
            Juice.haptic(.light)
            pickingSlot = SlotPick(id: slot)
        } label: {
            VStack(spacing: 2) {
                if let relic {
                    Image(systemName: relic.set.glyph)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    Text(relic.effectiveMainStat.displayText)
                        .font(Theme.numeric(8))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(relic.grade)★ +\(relic.level)")
                        .font(Theme.numeric(7))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("\(slot)")
                        .font(Theme.numeric(15).weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("empty")
                        .font(Theme.body(7))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 54, height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(worn ? Theme.surfaceHigh : Theme.surface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(
                        worn ? Theme.gold.opacity(0.7) : Theme.stroke,
                        style: StrokeStyle(lineWidth: 1, dash: worn ? [] : [3, 3])
                    )
            )
            .overlay(alignment: .topLeading) {
                Text("\(slot)")
                    .font(Theme.numeric(7))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(worn ? Theme.gold : Theme.textSecondary))
                    .offset(x: -4, y: -4)
            }
        }
        .buttonStyle(PlateButtonStyle())
    }

    private func setsRow(_ unit: ResolvedUnit) -> some View {
        HStack(spacing: 4) {
            if unit.activeRelicSets.isEmpty {
                Text("No set bonus yet: two of a kind for a stat, four for an effect.")
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(unit.activeRelicSets) { entry in
                    Text(entry.completions > 1 ? "\(entry.set.displayName) ×\(entry.completions)" : entry.set.displayName)
                        .font(Theme.body(9).weight(.bold))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.surfaceHigh))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Right: the stats

    private func stats(_ unit: ResolvedUnit) -> some View {
        // Base is grade, level and awakening; the difference to the final
        // number is the relics, shown beside it the way the genre does, so
        // equipping a relic is visible on the sheet and not only in battle.
        let base = ProgressionService.baseStats(for: unit.unit, blueprint: unit.blueprint)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars, size: 10)
                tag(unit.pantheon.displayName, color: unit.pantheon.color)
                tag(unit.archetype.displayName, color: Theme.textSecondary)
                tag(unit.role.displayName, color: Theme.textSecondary)
            }
            .padding(.bottom, 3)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 3) {
                    statRow("HP", base.hp, unit.stats.hp)
                    statRow("ATK", base.atk, unit.stats.atk)
                    statRow("DEF", base.def, unit.stats.def)
                    statRow("SPD", base.spd, unit.stats.spd)
                }
                VStack(spacing: 3) {
                    statRow("CRIT Rate", base.critRate, unit.stats.critRate, percent: true)
                    statRow("CRIT DMG", base.critDamage, unit.stats.critDamage, percent: true)
                    statRow("Accuracy", base.accuracy, unit.stats.accuracy, percent: true)
                    statRow("Resistance", base.resistance, unit.stats.resistance, percent: true)
                }
            }
            if let leader = unit.blueprint.leaderSkill {
                Divider().overlay(Theme.stroke).padding(.vertical, 2)
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    Text(leader.description)
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let awakening = unit.blueprint.awakening {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(unit.unit.isAwakened ? Theme.gold : Theme.textSecondary)
                    Text(unit.unit.isAwakened
                         ? "Awakened: \(awakening.bonusDescription)"
                         : "Awakens into \(awakening.awakenedName): \(awakening.bonusDescription)")
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.body(9).weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func statRow(_ label: String, _ base: Double, _ total: Double, percent: Bool = false) -> some View {
        let bonus = total - base
        let shown = abs(bonus) >= (percent ? 0.005 : 0.5)
        return HStack(spacing: 4) {
            Text(label)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(Self.statText(total, percent: percent))
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 2)
            Text(shown ? ((bonus > 0 ? "+" : "−") + Self.statText(abs(bonus), percent: percent)) : "")
                .font(Theme.numeric(9))
                .foregroundStyle(bonus > 0 ? Theme.success : Theme.danger)
        }
    }

    static func statText(_ value: Double, percent: Bool) -> String {
        percent ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded()))"
    }

    // MARK: - Bottom: the skills

    private func skills(_ unit: ResolvedUnit) -> some View {
        let index = min(selectedSkill, max(0, unit.skills.count - 1))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(unit.skills.indices, id: \.self) { slot in
                    skillTile(unit.skills[slot], selected: slot == index)
                        .onTapGesture {
                            Juice.haptic(.light)
                            selectedSkill = slot
                        }
                }
                Spacer(minLength: 0)
            }
            if unit.skills.indices.contains(index) {
                skillWords(unit.skills[index], index: index, unit: unit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func skillTile(_ skill: Skill, selected: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: SkillButton.glyph(for: skill))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(selected ? Theme.gold : Theme.textSecondary)
            Text(skill.name)
                .font(Theme.body(7).weight(.semibold))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 58, height: 44)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(selected ? Theme.surfaceHigh : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(selected ? Theme.gold : Theme.stroke, lineWidth: selected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
    }

    private func skillWords(_ skill: Skill, index: Int, unit: ResolvedUnit) -> some View {
        let level = unit.unit.skillLevels.indices.contains(index) ? unit.unit.skillLevels[index] : 1
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if skill.isPassive {
                    Text("PASSIVE")
                        .font(Theme.body(7).weight(.black))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold.opacity(0.25)))
                        .foregroundStyle(Theme.gold)
                }
                if skill.cooldown > 0 {
                    Label("\(skill.cooldown) turns", systemImage: "clock.fill")
                        .font(Theme.numeric(9))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let damage = skill.damage {
                    Text("≈ \(Int(DamageCalculator.previewDamage(attackStat: unit.stats.atk, spec: damage))) dmg" + (damage.hits > 1 ? " × \(damage.hits)" : ""))
                        .font(Theme.numeric(9))
                        .foregroundStyle(Theme.gold)
                }
                Spacer()
                if !skill.levelUpBonuses.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(skill.levelUpBonuses.indices, id: \.self) { bonusIndex in
                            Circle()
                                .fill(level > bonusIndex + 1 ? Theme.success : Theme.stroke)
                                .frame(width: 6, height: 6)
                        }
                        Text("skill-ups")
                            .font(Theme.body(8))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Text(skill.description)
                .font(Theme.body(9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let next = skill.levelUpBonuses.indices.first(where: { level <= $0 + 1 }) {
                Text("Next skill-up: \(skill.levelUpBonuses[next].label) — feed a duplicate in the Hall of Ka.")
                    .font(Theme.body(8))
                    .foregroundStyle(Theme.goldDim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Awakening in one sheet: the form it has and the form it becomes, what the
/// change is worth, and the essences it costs.
struct AwakeningSheet: View {
    let unit: ResolvedUnit

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let awakening = unit.blueprint.awakening {
                    let costs = awakening.essenceCost.sorted { $0.key < $1.key }
                    let affordable = awakening.essenceCost.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
                    HStack(alignment: .top, spacing: 14) {
                        formTile(unit.blueprint.model.portraitName(awakened: false), caption: unit.blueprint.name)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.gold)
                            .padding(.top, 56)
                        formTile(unit.blueprint.model.portraitName(awakened: true), caption: awakening.awakenedName)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(awakening.awakenedName)
                                .font(Theme.title(16))
                                .foregroundStyle(Theme.gold)
                            Text(awakening.bonusDescription)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
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
                            if unit.unit.isAwakened {
                                Text("Already awakened.")
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.gold)
                            } else {
                                PrimaryButton(title: "Awaken", systemImage: "sun.max.fill", isEnabled: affordable) {
                                    store.awaken(unit.id)
                                    dismiss()
                                }
                                Text("Essences drop in the Halls of Essence, in the Labyrinth on the island.")
                                    .font(Theme.body(10))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                }
            }
            .screen("Awakening")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func formTile(_ portrait: String, caption: String) -> some View {
        VStack(spacing: 4) {
            if BundleImage.exists(portrait) {
                BundleImage(name: portrait)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 104, height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.surface)
                    .frame(width: 104, height: 136)
            }
            Text(caption)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 8)], spacing: 10) {
                        ForEach(candidates) { candidate in
                            Button {
                                toggle(candidate.id)
                            } label: {
                                UnitCard(unit: candidate, isSelected: selection.contains(candidate.id), size: 76)
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .screen(purpose == .evolve ? "Evolve" : "Power up")
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
                .padding(10)
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
