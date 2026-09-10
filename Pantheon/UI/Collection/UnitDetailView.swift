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
    /// A worn relic opened from its slot: the power-up screen.
    @State private var openingRelic: RelicPick?
    @State private var showFodderPicker = false
    @State private var fodderPurpose: FodderPurpose = .levelUp
    @State private var showAwakening = false
    @State private var showLore = false
    @State private var selectedSkill = 0

    /// A slot number that can drive a sheet.
    struct SlotPick: Identifiable {
        let id: Int
    }

    struct RelicPick: Identifiable {
        let id: UUID
    }

    enum FodderPurpose { case levelUp, evolve }

    private var unit: ResolvedUnit? { store.resolved(unitID) }
    private var isLocked: Bool { unit?.unit.isLocked == true }

    var body: some View {
        NavigationStack {
            GameScreen(
                unit?.name ?? "Unit",
                subtitle: unit?.blueprint.epithet,
                dismiss: { dismiss() }
            ) {
                BarButton(
                    title: "Lore",
                    systemImage: "book.fill",
                    tint: Theme.textSecondary,
                    showsTitle: false
                ) {
                    showLore = true
                }
                BarButton(title: "Auto-equip", systemImage: "wand.and.stars", tint: Theme.info) {
                    store.autoEquip(unitID)
                }
                BarButton(
                    title: isLocked ? "Locked" : "Unlocked",
                    systemImage: isLocked ? "lock.fill" : "lock.open",
                    tint: isLocked ? Theme.gold : Theme.textSecondary,
                    showsTitle: false
                ) {
                    store.toggleLock(unitID)
                }
            } content: {
                if let unit {
                    // Three columns, sized so a landscape phone holds the lot
                    // without a scroll: card and actions, the ring, then stats
                    // over skills. No ScrollView — the sheet is one frame, and
                    // each panel stretches to a common bottom rail so no band
                    // of bare backdrop is left under a short column.
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
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 8)
                } else {
                    EmptyState(icon: "questionmark", title: "Gone", message: "This unit is no longer in your collection.")
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
            .sheet(item: $openingRelic) { pick in
                RelicDetailView(relicID: pick.id, role: unit?.role ?? .attacker)
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
            Spacer(minLength: 0)
            // The three things to do with a unit, one wide row each: a 4pt
            // label in a square tile was the least legible thing on the most
            // important control, so each row now says what it costs and
            // whether it is ready.
            VStack(spacing: 4) {
                actionButton(
                    "Power up",
                    unit.unit.isMaxLevel
                        ? "Max level · feed duplicates to skill up"
                        : "500 drachma per unit",
                    "arrow.up.circle.fill", tint: Theme.info
                ) {
                    fodderPurpose = .levelUp
                    showFodderPicker = true
                }
                actionButton(
                    "Evolve",
                    unit.unit.canEvolve
                        ? "\(ProgressionService.evolutionFodderRequired(currentStars: unit.stars)) × \(unit.stars)★ · \(ProgressionService.drachmaCostToEvolve(currentStars: unit.stars)) drachma"
                        : "Reach Lv.\(unit.unit.maxLevel) first",
                    "star.circle.fill", tint: Theme.gold, enabled: unit.unit.canEvolve
                ) {
                    fodderPurpose = .evolve
                    showFodderPicker = true
                }
                if let awakening = unit.blueprint.awakening {
                    let ready = awakening.essenceCost.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
                    actionButton(
                        unit.unit.isAwakened ? "Awakened" : "Awaken",
                        unit.unit.isAwakened
                            ? "Form unlocked"
                            : (ready ? "Essences ready" : "Essences short"),
                        "sun.max.fill", tint: Theme.gold, enabled: !unit.unit.isAwakened
                    ) {
                        showAwakening = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func actionButton(
        _ title: String, _ subtitle: String, _ symbol: String, tint: Color,
        enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Theme.body(10).weight(.bold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Theme.body(8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(enabled ? Theme.ink : Theme.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 32)
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
        let radius: CGFloat = 67
        let centre = CGPoint(x: size / 2, y: size / 2)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(centre)
                // The largest clear space on the sheet carries the number the
                // whole sheet exists to raise, not a second copy of the element.
                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(unit.element.color.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: unit.element.glyph)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(unit.element.color)
                    }
                    Text("\(unit.power)")
                        .font(Theme.numeric(16))
                        .foregroundStyle(Theme.gold)
                    Text("POWER")
                        .font(Theme.body(8).weight(.black))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func slotTile(slot: Int, unit: ResolvedUnit) -> some View {
        let relic = unit.unit.equippedRelics[slot].flatMap { store.player.relic($0) }
        let worn = relic != nil
        return Button {
            Juice.haptic(.light)
            // A worn relic opens its power-up screen (Change is on it);
            // an empty slot opens the picker.
            if let relic {
                openingRelic = RelicPick(id: relic.id)
            } else {
                pickingSlot = SlotPick(id: slot)
            }
        } label: {
            VStack(spacing: 2) {
                if let relic {
                    Image(systemName: relic.set.glyph)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    // The number over its kind: "CRIT Rate +32%" as one 5pt
                    // sentence was the one figure a player checks, unreadable.
                    Text(relic.effectiveMainStat.kind.format(relic.effectiveMainStat.value))
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(relic.effectiveMainStat.kind.displayName.uppercased())
                        .font(Theme.body(7))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(relic.grade)★ +\(relic.level)")
                        .font(Theme.numeric(7))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 2) {
                        ForEach(relic.subStats.indices, id: \.self) { _ in
                            Circle()
                                .fill(Theme.info)
                                .frame(width: 3, height: 3)
                        }
                    }
                } else {
                    // An empty slot states the rule the relic system runs on:
                    // odd slots carry a fixed main stat, even ones are free.
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Theme.goldDim)
                    Text(Relic.fixedMainStat(forSlot: slot)?.displayName.uppercased() ?? "FREE")
                        .font(Theme.body(7).weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 60, height: 60)
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
        // One row per completed set, saying what it granted: a capsule
        // reading only "Fury" told the player nothing they gained.
        VStack(alignment: .leading, spacing: 3) {
            if unit.activeRelicSets.isEmpty {
                Text("No set bonus · 2 pieces for a stat, 4 for an effect")
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(unit.activeRelicSets) { entry in
                    HStack(spacing: 5) {
                        Image(systemName: entry.set.glyph)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.gold)
                        Text(entry.completions > 1 ? "\(entry.set.displayName) ×\(entry.completions)" : entry.set.displayName)
                            .font(Theme.body(9).weight(.bold))
                            .foregroundStyle(Theme.gold)
                        Spacer(minLength: 4)
                        Text(entry.set.statBonus?.displayText ?? "4-piece effect")
                            .font(Theme.numeric(8))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 3) {
                    statRow("HP", base.hp, unit.stats.hp, strong: true)
                    statRow("ATK", base.atk, unit.stats.atk, strong: true)
                    statRow("DEF", base.def, unit.stats.def, strong: true)
                    statRow("SPD", base.spd, unit.stats.spd, strong: true)
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
                        .lineLimit(2)
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// Three fixed columns — label, total, relic bonus — so the numbers line
    /// up down the group instead of landing on a ragged edge that moves per
    /// row. `strong` weights the four combat stats over the four percentages.
    private func statRow(
        _ label: String, _ base: Double, _ total: Double,
        percent: Bool = false, strong: Bool = false
    ) -> some View {
        let bonus = total - base
        let shown = abs(bonus) >= (percent ? 0.005 : 0.5)
        return HStack(spacing: 4) {
            Text(label)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 54, alignment: .leading)
            Text(Self.statText(total, percent: percent))
                .font(strong ? Theme.numeric(13) : Theme.numeric(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 44, alignment: .trailing)
            Text(shown ? ((bonus > 0 ? "+" : "−") + Self.statText(abs(bonus), percent: percent)) : "")
                .font(Theme.numeric(9))
                .foregroundStyle(bonus > 0 ? Theme.success : Theme.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 36, alignment: .trailing)
        }
    }

    static func statText(_ value: Double, percent: Bool) -> String {
        percent ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded()))"
    }

    /// The stat a skill's damage is multiplied by, so a max-health or defence
    /// skill no longer advertises the figure it would hit for off ATK.
    static func scalingStat(_ scaling: DamageScaling, _ stats: Stats) -> Double {
        switch scaling {
        case .attack: return stats.atk
        case .maxHealth: return stats.hp
        case .defense: return stats.def
        case .speed: return stats.spd
        }
    }

    // MARK: - Bottom: the skills

    private func skills(_ unit: ResolvedUnit) -> some View {
        let index = min(selectedSkill, max(0, unit.skills.count - 1))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(unit.skills.indices, id: \.self) { slot in
                    Button {
                        Juice.haptic(.light)
                        selectedSkill = slot
                    } label: {
                        skillTile(
                            unit.skills[slot],
                            selected: slot == index,
                            level: unit.unit.skillLevels.indices.contains(slot) ? unit.unit.skillLevels[slot] : 1
                        )
                    }
                    .buttonStyle(PlateButtonStyle())
                }
            }
            if unit.skills.indices.contains(index) {
                skillWords(unit.skills[index], index: index, unit: unit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func skillTile(_ skill: Skill, selected: Bool, level: Int) -> some View {
        VStack(spacing: 2) {
            Image(systemName: SkillButton.glyph(for: skill))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(selected ? Theme.gold : Theme.textSecondary)
            Text(skill.name)
                .font(Theme.body(9).weight(.semibold))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            Text("Lv.\(level)/\(skill.maxSkillLevel)")
                .font(Theme.numeric(7))
                .foregroundStyle(level >= skill.maxSkillLevel ? Theme.gold : Theme.textSecondary)
        }
        .padding(.horizontal, 3)
        // The tiles divide the row rather than sitting at a fixed 58 with a
        // Spacer holding the rest of it open — which also overflowed on a
        // narrower phone.
        .frame(maxWidth: .infinity, minHeight: 52)
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
                    // previewDamage already multiplies by the hit count, so the
                    // old " × 3" read as an instruction to triple the figure.
                    let estimate = DamageCalculator.previewDamage(
                        attackStat: Self.scalingStat(damage.scaling, unit.stats), spec: damage
                    )
                    Text("≈ \(Int(estimate)) dmg" + (damage.hits > 1 ? " · \(damage.hits) hits" : ""))
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
            GameScreen("Awakening", subtitle: unit.name, dismiss: { dismiss() }) {
                EmptyView()
            } content: {
                ScrollView {
                    if let awakening = unit.blueprint.awakening {
                        let costs = awakening.essenceCost.sorted { $0.key < $1.key }
                        let affordable = awakening.essenceCost.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
                        HStack(alignment: .top, spacing: 14) {
                            formTile(unit.blueprint.model.portraitName(awakened: false), caption: unit.blueprint.name)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.gold)
                                .frame(height: 136)
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
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 10)
                    }
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
                    // A near-square portrait filled into a 104x136 frame hangs
                    // ~30 points past each side, and clipShape does not clip
                    // hit-testing: without this the art swallows taps meant for
                    // the Awaken button beside it.
                    .allowsHitTesting(false)
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
            GameScreen(
                purpose == .evolve ? "Evolve" : "Power up",
                subtitle: target.name,
                dismiss: { dismiss() }
            ) {
                EmptyView()
            } content: {
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
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 8)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 6) {
                        let cost = purpose == .evolve
                            ? ProgressionService.drachmaCostToEvolve(currentStars: target.stars)
                            : selection.count * 500
                        if purpose == .evolve {
                            Text("\(selection.count) / \(required) selected · \(cost) drachma")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            let xp = candidates
                                .filter { selection.contains($0.id) }
                                .reduce(0) { $0 + ProgressionService.feedValue(of: $1.unit) }
                            let duplicates = candidates.filter {
                                selection.contains($0.id) && $0.unit.blueprintID == target.unit.blueprintID
                            }.count
                            // A unit at its cap gains no experience — the old
                            // "+18,400 EXP" was a lie and the fodder vanished
                            // for nothing unless it was a duplicate.
                            Text(target.unit.isMaxLevel
                                 ? "Max level · no EXP · \(duplicates) duplicate\(duplicates == 1 ? "" : "s") will skill up"
                                 : "+\(xp) EXP · \(cost) drachma")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        // GameStore bails silently when the drachma is short,
                        // so the button says so rather than closing on nothing.
                        Text("You have \(store.player.wallet.drachma) drachma")
                            .font(Theme.numeric(10))
                            .foregroundStyle(store.player.wallet.drachma >= cost ? Theme.textSecondary : Theme.danger)
                        PrimaryButton(
                            title: purpose == .evolve ? "Evolve" : "Consume",
                            isEnabled: (purpose == .evolve ? selection.count == required : !selection.isEmpty)
                                && store.player.wallet.drachma >= cost
                        ) {
                            commit()
                        }
                    }
                    .padding(10)
                    .background(Theme.ink)
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
