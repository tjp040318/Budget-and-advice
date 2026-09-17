import SwiftUI

/// The regalia's level as five pips, I–V: lit gold up to the level, ghosts
/// after; all ghosts while the item is locked. On the unit sheet's plate
/// and the regalia sheet.
struct RegaliaPips: View {
    let level: Int
    var lit: Bool = true
    var size: CGFloat = 6

    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(1...RegaliaTemplate.levels, id: \.self) { step in
                Circle()
                    .fill(step <= level && lit ? Theme.gold : Theme.surfaceHigh)
                    .overlay(
                        Circle().strokeBorder(lit ? Theme.goldDim.opacity(0.8) : Theme.stroke, lineWidth: 0.5)
                    )
                    .frame(width: size, height: size)
            }
        }
    }
}

/// One family's regalia (`Regalia`, `RegaliaService`; `Docs/PLAN.md`,
/// *Artifacts — the last item on the order*): opened from the plate under
/// the unit sheet's relic ring. The left is the item — the card, the name,
/// the template, the level, the blurb and the line at this level, or what
/// unlocks it; the right is the ladder of five levels with the current one
/// marked, and what raises it. Nothing here is bought or rolled: the
/// regalia is the one thing on a unit a player can plan, and this sheet
/// is the plan.
struct RegaliaSheet: View {
    let unitID: UUID

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    private var unit: ResolvedUnit? { store.resolved(unitID) }
    /// The family's regalia at the unit's banked level, unlocked or not.
    private var regalia: Regalia? {
        unit.flatMap { RegaliaService.regalia(forBlueprint: $0.blueprint.id, level: RegaliaService.level(of: $0.unit)) }
    }
    private var unlocked: Bool { unit?.regalia != nil }

    var body: some View {
        NavigationStack {
            GameScreen(
                regalia?.name ?? "Regalia",
                subtitle: unit.map { "Regalia of \($0.blueprint.name)" } ?? "The family's own item",
                dismiss: { dismiss() }
            ) {
                BarButton(title: "Done", systemImage: "checkmark.circle.fill", tint: Theme.gold) { dismiss() }
            } content: {
                if let unit, let regalia {
                    HStack(alignment: .top, spacing: 8) {
                        item(unit, regalia)
                            .frame(width: 300)
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 8) {
                                ladder(regalia)
                                raising(unit, regalia)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 6)
                } else {
                    EmptyState(icon: "crown", title: "No regalia", message: "This family has no item of its own yet.")
                }
            }
        }
    }

    // MARK: - The item

    private func item(_ unit: ResolvedUnit, _ regalia: Regalia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                UnitCard(unit: unit, showPower: false, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(regalia.name)
                        .font(Theme.title(14))
                        .foregroundStyle(unlocked ? Theme.gold : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Chip(
                        text: "\(regalia.template.displayName) · \(regalia.template.kitName)",
                        systemImage: regalia.template.glyph,
                        tint: Theme.gold,
                        filled: unlocked
                    )
                    HStack(spacing: 6) {
                        RegaliaPips(level: regalia.level, lit: unlocked, size: 7)
                        Text("Level \(regalia.levelLabel) of \(Regalia.numeral(RegaliaTemplate.levels))")
                            .font(Theme.body(10).weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(regalia.blurb)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Theme.stroke.opacity(0.7))
                .frame(height: 1)
            if unlocked {
                Text(regalia.line)
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(regalia.template.hookName)
                    .font(Theme.body(9).weight(.bold))
                    .foregroundStyle(Theme.goldDim)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.textSecondary)
                    Text(RegaliaService.unlockLine(for: unit.blueprint).uppercased())
                        .font(Theme.title(12))
                        .tracking(1.0)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(lockedLine(regalia))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// What a locked item will do once it is lit, with the banked level
    /// named when duplicates have already been fed.
    private func lockedLine(_ regalia: Regalia) -> String {
        let promise = "Once unlocked: \(regalia.line)."
        return regalia.level > 1
            ? promise + " Level \(regalia.levelLabel) is banked already and lights with it."
            : promise
    }

    // MARK: - The ladder

    private func ladder(_ regalia: Regalia) -> some View {
        SectionPanel(title: "The five levels", accessory: "I → \(Regalia.numeral(RegaliaTemplate.levels))") {
            VStack(spacing: 3) {
                ForEach(1...RegaliaTemplate.levels, id: \.self) { level in
                    ladderRow(regalia, level: level)
                }
            }
        }
    }

    private func ladderRow(_ regalia: Regalia, level: Int) -> some View {
        let current = level == regalia.level
        let reached = level <= regalia.level && unlocked
        let magnitude = regalia.template.magnitude(at: level)
        return HStack(spacing: 8) {
            Text(Regalia.numeral(level))
                .font(Theme.title(12))
                .foregroundStyle(reached ? Theme.gold : Theme.textSecondary)
                .frame(width: 26, alignment: .leading)
            Text(regalia.template.line(magnitude, level: level))
                .font(Theme.body(10))
                .foregroundStyle(reached ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if current {
                Text(unlocked ? "NOW" : "BANKED")
                    .font(Theme.body(9).weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(unlocked ? Theme.ink : Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(unlocked ? Theme.gold : Theme.surfaceHigh))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(current ? Theme.gold.opacity(0.12) : Theme.surface)
        )
    }

    // MARK: - What raises it

    private func raising(_ unit: ResolvedUnit, _ regalia: Regalia) -> some View {
        let capped = RegaliaService.skillsAreCapped(unit.unit, blueprint: unit.blueprint)
        let owed = RegaliaService.skillUpsRemaining(unit.unit, blueprint: unit.blueprint)
        let toGo = RegaliaTemplate.levels - regalia.level
        let owedLine = "\(owed) skill-up\(owed == 1 ? "" : "s") still owed: duplicates go to the skills first"
        let levelLine = "Level \(regalia.levelLabel) of \(Regalia.numeral(RegaliaTemplate.levels)) — "
            + "\(toGo) more duplicate\(toGo == 1 ? "" : "s") to V"
        return SectionPanel(title: "What raises it") {
            VStack(alignment: .leading, spacing: 6) {
                Text(RegaliaService.raisingLine)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                progressRow(
                    "sun.max.fill",
                    unlocked ? "Unlocked" : RegaliaService.unlockLine(for: unit.blueprint),
                    done: unlocked
                )
                progressRow(
                    "book.fill",
                    capped ? "Every skill at its cap — the next duplicate raises the regalia" : owedLine,
                    done: capped
                )
                progressRow(
                    "crown.fill",
                    regalia.isMaxLevel ? "Level \(regalia.levelLabel): the item is complete" : levelLine,
                    done: regalia.isMaxLevel
                )
            }
        }
    }

    private func progressRow(_ symbol: String, _ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(done ? Theme.success : Theme.goldDim)
                .frame(width: 14)
            Text(text)
                .font(Theme.body(10).weight(done ? .bold : .medium))
                .foregroundStyle(done ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
