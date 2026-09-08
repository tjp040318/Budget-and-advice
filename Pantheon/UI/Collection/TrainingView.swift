import SwiftUI

/// The Hall of Ka: where a unit is made stronger.
///
/// Summoners War's power-up circle, evolution and awakening under one roof.
/// Pick a unit, then feed it: every fed unit is consumed for experience, a fed
/// duplicate of the same character is a skill-up on top, evolution takes
/// same-grade fodder at max level, awakening takes essences. The rules all
/// live in `ProgressionService` and `GameStore`; this screen only shows their
/// consequences before the player commits, and what changed after.
struct TrainingView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetID: UUID?
    @State private var mode: Mode = .powerUp
    @State private var fodder: Set<UUID> = []
    @State private var outcome: String?

    enum Mode: String, CaseIterable, Identifiable {
        case powerUp = "Power up"
        case evolve = "Evolve"
        case awaken = "Awaken"
        var id: String { rawValue }
    }

    /// Everything owned, strongest first, so the unit worth training is near
    /// the front of the strip.
    private var units: [ResolvedUnit] {
        store.resolvedUnits.sorted { $0.power > $1.power }
    }

    private var target: ResolvedUnit? {
        guard let targetID else { return nil }
        return units.first { $0.id == targetID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    targetStrip

                    if let target {
                        Picker("", selection: $mode) {
                            ForEach(Mode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if let outcome {
                            Text(outcome)
                                .font(Theme.title(15))
                                .foregroundStyle(Theme.gold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .panelBackground()
                        }

                        targetPanel(target)

                        switch mode {
                        case .powerUp: powerUp(target)
                        case .evolve: evolve(target)
                        case .awaken: awaken(target)
                        }
                    } else {
                        EmptyState(
                            icon: "person.crop.circle.badge.questionmark",
                            title: "Choose a unit",
                            message: "Tap a unit above to train it."
                        )
                    }
                }
                .padding(16)
            }
            .screen("Hall of Ka")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if targetID == nil { targetID = units.first?.id }
            }
            .onChange(of: mode) { _, _ in fodder = [] }
            .onChange(of: targetID) { _, _ in
                fodder = []
                outcome = nil
            }
        }
    }

    // MARK: - Target

    private var targetStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Who trains")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(units) { unit in
                        Button {
                            targetID = unit.id
                        } label: {
                            UnitCard(unit: unit, isSelected: unit.id == targetID, size: 84)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func targetPanel(_ unit: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(unit.name)
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(repeating: "★", count: unit.stars))
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.gold)
            }
            StatBar(
                value: Double(unit.unit.experience),
                maximum: Double(ProgressionService.experienceForNextLevel(level: unit.level, stars: unit.stars)),
                tint: Theme.info,
                height: 6,
                label: unit.unit.isMaxLevel ? "Lv.\(unit.level) — max for \(unit.stars)★" : "Lv.\(unit.level) / \(unit.unit.maxLevel)"
            )
            HStack {
                Text("Power \(unit.power)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.gold)
                Spacer()
                Text("\(store.player.wallet.drachma) drachma")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .panelBackground()
    }

    // MARK: - Power up

    private func powerUp(_ target: ResolvedUnit) -> some View {
        let candidates = units.filter { $0.id != target.id && !$0.unit.isLocked }
        let chosen = candidates.filter { fodder.contains($0.id) }
        let experience = chosen.reduce(0) { $0 + ProgressionService.feedValue(of: $1.unit) }
        let duplicates = chosen.filter { $0.blueprint.id == target.blueprint.id }.count
        let cost = chosen.count * 500
        var preview = target.unit
        let gained = ProgressionService.grantExperience(experience, to: &preview)
        let affordable = store.player.wallet.drachma >= cost

        return VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Feed")
                Text("Every unit you pick is consumed. A duplicate of \(target.name) is a skill-up as well as experience.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if candidates.isEmpty {
                    EmptyState(
                        icon: "tray",
                        title: "Nothing to feed",
                        message: "Summon more units, or unlock one. Locked units are never consumed."
                    )
                } else {
                    fodderGrid(candidates, limit: 12)
                }
            }
            .padding(14)
            .panelBackground()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Result")
                resultRow("Experience", "+\(experience)")
                resultRow("Level", gained > 0 ? "Lv.\(target.level) → Lv.\(preview.level)" : "Lv.\(target.level), no change")
                if duplicates > 0 {
                    resultRow("Skill-ups", "×\(duplicates)", tint: Theme.gold)
                }
                resultRow("Cost", "\(cost) drachma", tint: affordable ? Theme.textPrimary : Theme.danger)
                if target.unit.isMaxLevel {
                    Text("\(target.name) is at the level cap for \(target.stars)★. Evolve to keep going.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                PrimaryButton(
                    title: chosen.isEmpty ? "Pick units to feed" : "Power up",
                    systemImage: "arrow.up.circle.fill",
                    isEnabled: !chosen.isEmpty && affordable
                ) {
                    commitPowerUp(target, feeding: chosen)
                }
            }
            .padding(14)
            .panelBackground()
        }
    }

    private func commitPowerUp(_ target: ResolvedUnit, feeding chosen: [ResolvedUnit]) {
        let before = target.unit
        store.levelUp(target.id, feeding: chosen.map(\.id))
        fodder = []
        guard let after = store.resolved(target.id)?.unit else { return }
        var parts: [String] = []
        if after.level > before.level { parts.append("Lv.\(before.level) → Lv.\(after.level)") }
        let skillUps = zip(after.skillLevels, before.skillLevels).filter { $0 > $1 }.count
        if skillUps > 0 { parts.append("skill-up ×\(skillUps)") }
        if parts.isEmpty {
            outcome = after.level == before.level ? "Experience banked" : "Powered up"
        } else {
            outcome = "Powered up: " + parts.joined(separator: ", ")
        }
        Juice.notify(.success)
        AudioLibrary.shared.play(.uiConfirm)
    }

    // MARK: - Evolve

    private func evolve(_ target: ResolvedUnit) -> some View {
        let required = ProgressionService.evolutionFodderRequired(currentStars: target.stars)
        let cost = ProgressionService.drachmaCostToEvolve(currentStars: target.stars)
        let candidates = units.filter { $0.id != target.id && !$0.unit.isLocked && $0.stars == target.stars }
        let chosen = candidates.filter { fodder.contains($0.id) }
        let affordable = store.player.wallet.drachma >= cost
        let ready = target.unit.canEvolve && chosen.count == required && affordable

        return VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: target.stars >= 6 ? "Fully evolved" : "Evolve to \(target.stars + 1)★")
                if target.stars >= 6 {
                    Text("\(target.name) is 6★, the top of the ladder.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    requirement("At max level", met: target.unit.isMaxLevel,
                                detail: "Lv.\(target.level) / \(target.unit.maxLevel)")
                    requirement("\(required) fodder at exactly \(target.stars)★", met: chosen.count == required,
                                detail: "\(chosen.count) / \(required) picked")
                    requirement("\(cost) drachma", met: affordable,
                                detail: "you have \(store.player.wallet.drachma)")
                    Text("Evolving resets the level to 1 and raises every stat; the fodder is consumed.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .panelBackground()

            if target.stars < 6 {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Fodder")
                    if candidates.isEmpty {
                        EmptyState(
                            icon: "tray",
                            title: "No \(target.stars)★ fodder",
                            message: "Evolution takes unlocked units at exactly \(target.stars)★. Raise some fodder to that grade first."
                        )
                    } else {
                        fodderGrid(candidates, limit: required)
                    }
                    PrimaryButton(
                        title: "Evolve",
                        systemImage: "star.circle.fill",
                        isEnabled: ready
                    ) {
                        store.evolve(target.id, fodderIDs: chosen.map(\.id))
                        fodder = []
                        if let after = store.resolved(target.id), after.stars > target.stars {
                            outcome = "\(after.name) evolved to \(after.stars)★"
                            Juice.notify(.success)
                            AudioLibrary.shared.play(.uiConfirm)
                        }
                    }
                }
                .padding(14)
                .panelBackground()
            }
        }
    }

    // MARK: - Awaken

    @ViewBuilder
    private func awaken(_ target: ResolvedUnit) -> some View {
        if let awakening = target.blueprint.awakening {
            let costs = awakening.essenceCost.sorted { $0.key < $1.key }
            let ready = costs.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
            VStack(alignment: .leading, spacing: 9) {
                SectionHeader(title: "Awakening")
                Text(target.unit.isAwakened ? awakening.awakenedName : "Becomes \(awakening.awakenedName)")
                    .font(Theme.title(16))
                    .foregroundStyle(target.unit.isAwakened ? Theme.gold : Theme.textPrimary)
                Text(awakening.bonusDescription)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if target.unit.isAwakened {
                    Text("Already awakened.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(costs.indices, id: \.self) { index in
                        let id = costs[index].key
                        let needed = costs[index].value
                        let have = store.player.essences[id] ?? 0
                        requirement(EssenceCatalog.name(for: id), met: have >= needed, detail: "\(have) / \(needed)")
                    }
                    Text("Essences drop in the campaign; the element's own essence from its stages, magic essence from any.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Awaken", systemImage: "sun.max.fill", isEnabled: ready) {
                        store.awaken(target.id)
                        if let after = store.resolved(target.id), after.unit.isAwakened {
                            outcome = "\(after.name) awakened"
                            Juice.notify(.success)
                            AudioLibrary.shared.play(.uiConfirm)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .panelBackground()
        } else {
            EmptyState(
                icon: "sun.max",
                title: "No awakened form",
                message: "\(target.name) has no awakening; power up and evolve instead."
            )
        }
    }

    // MARK: - Pieces

    private func fodderGrid(_ candidates: [ResolvedUnit], limit: Int) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 92), spacing: 8)], spacing: 10) {
            ForEach(candidates) { candidate in
                Button {
                    if fodder.contains(candidate.id) {
                        fodder.remove(candidate.id)
                    } else if fodder.count < limit {
                        fodder.insert(candidate.id)
                        Juice.haptic(.light)
                    } else {
                        Juice.notify(.warning)
                    }
                } label: {
                    UnitCard(unit: candidate, isSelected: fodder.contains(candidate.id), size: 74)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func requirement(_ label: String, met: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(met ? Theme.success : Theme.stroke)
            Text(label)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(detail)
                .font(Theme.numeric(12))
                .foregroundStyle(met ? Theme.success : Theme.textSecondary)
        }
    }

    private func resultRow(_ label: String, _ value: String, tint: Color = Theme.textPrimary) -> some View {
        HStack {
            Text(label).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.numeric(14)).foregroundStyle(tint)
        }
    }
}
