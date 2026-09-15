import Foundation
import SceneKit
import SwiftUI

/// The battle screen: 3D stage underneath, HUD on top.
///
/// The HUD answers four questions, and every piece below exists to answer
/// exactly one of them without the player stopping to look:
///
///   *Whose turn is it?* — the gold dot on the attack gauge, the gold ring on
///   that unit's team plate, and the actor plate in the bottom-left corner,
///   which is filled during an enemy turn as well as the player's so the
///   corner never goes blank and never means two different things.
///   *Who is next?* — the gauge, read left to right.
///   *What just happened to whom?* — the combat feed on the right: one line
///   per health change and per status landing, named, on its own dark plate.
///   The 3D damage numbers land on a sunlit floor and were measured at 1.05:1
///   against it; these are 14:1 whatever the stage.
///   *What will this button do?* — every skill tile carries its own forecast
///   line (estimated damage, hit count, or HEAL/BUFF), and the plate spells
///   out the skill in hand before it is committed rather than after.
struct BattleView: View {

    @State private var ultimateFlash: Double = 0
    @StateObject var model: BattleViewModel
    @Environment(\.dismiss) private var dismiss

    /// The gear's menu: the log, forfeit.
    @State private var showMenu = false
    @State private var showLog = false
    @State private var summary: BattleSummary?
    /// A skill held down: its card shows until a tap or four seconds.
    @State private var heldSkill: Skill?

    /// The skill under the player's finger, before the tap has committed to
    /// anything. A press on a tile sets it and a lift clears it, so the plate
    /// describes a skill *while it is being considered* — the old plate only
    /// ever described a skill that had already been chosen, and skills that
    /// pick their own targets fire on the tap, so those were never described
    /// at all.
    @State private var previewSlot: Int?


    var body: some View {
        ZStack {
            BattleSceneView(controller: model.sceneController) { id in
                model.tapUnit(id)
            }
            .ignoresSafeArea()

            // The genre's HUD and nothing else on the field (2026-09-15): a
            // boss's bar across the very top, the stage's name small under
            // it at the left, the three controls at the bottom left, the
            // skills at the bottom right. The bars stand over the heads
            // (`UnitPlate`). The actor plate, the side column, the turn
            // gauge and the combat feed of the earlier HUDs are gone — the
            // owner, with Summoners War's frame beside ours: "the UI of the
            // skills and the descriptions like the bottom left UI and more
            // I just don't like."
            let boss = model.displayedCombatants.first { $0.isBoss && $0.isAlive }
            VStack(spacing: 6) {
                if let boss {
                    bossBar(boss)
                }
                topStrip
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 10) {
                    controls
                    Spacer(minLength: 0)
                    if let actor = model.awaitingActor {
                        skillRow(actor)
                    } else if model.isPlayingBack {
                        skipButton
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 8)

            // The frame goes white for a beat as an ultimate's cut-in lands.
            Color.white
                .opacity(ultimateFlash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onChange(of: model.cutIn) { _, cutIn in
                    guard let cutIn, !cutIn.isSpeech else { return }
                    ultimateFlash = 0.6
                    withAnimation(.easeOut(duration: 0.5)) { ultimateFlash = 0 }
                }

            if let cutIn = model.cutIn {
                cutInBanner(cutIn)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .onAppear {
                        // A skill's name is read at a glance; a sentence is
                        // not, so a boss's line is held nearly twice as long.
                        DispatchQueue.main.asyncAfter(deadline: .now() + (cutIn.isSpeech ? 2.4 : 1.15)) {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if model.cutIn == cutIn { model.cutIn = nil }
                            }
                        }
                    }
            }

            if showLog { logOverlay }

            if let heldSkill {
                skillCard(heldSkill)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .onTapGesture { withAnimation { self.heldSkill = nil } }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation { self.heldSkill = nil }
                        }
                    }
            }

            if let banner = model.repeatBanner {
                Text(banner)
                    .font(Theme.title(16))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.plate.opacity(0.6)))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { model.repeatBanner = nil }
                        }
                    }
            }

            if let summary {
                BattleResultView(summary: summary, onDismiss: { dismiss() }, store: model.store)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.begin()
            // A chapter boss or a raid says its one line as the fight opens;
            // every other stage returns from this without doing anything.
            model.announceBoss(ifPresentIn: model.displayedCombatants)
            AudioLibrary.shared.playMusic(.battle)
        }
        .onDisappear { AudioLibrary.shared.playMusic(.island) }
        // A new actor means the old one's skill preview is meaningless.
        .onChange(of: model.awaitingActor?.id) { _, _ in previewSlot = nil }
        .onChange(of: model.outcome?.outcome) { _, newValue in
            guard newValue != nil else { return }
            // Let the last animation land before the result panel takes over.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // On a repeat run this banks the loot and starts the next
                // fight instead of returning a panel.
                if let concluded = model.conclude() {
                    withAnimation(.easeOut(duration: 0.35)) {
                        summary = concluded
                    }
                }
            }
        }
        // The gear's menu: the genre keeps everything that is not a skill
        // behind one button.
        .confirmationDialog("Battle", isPresented: $showMenu, titleVisibility: .visible) {
            Button(showLog ? "Hide the battle log" : "Show the battle log") { withAnimation { showLog.toggle() } }
            Button("Forfeit", role: .destructive) { model.forfeit() }
            Button("Keep fighting", role: .cancel) {}
        } message: {
            Text("Forfeiting counts as a loss, and energy already spent is not refunded.")
        }
    }

    // MARK: - Top bar

    /// One height and one shape for every control in the top row, and one way
    /// for a stateful control — AUTO, fast-forward, the log — to say it is
    /// on: a gold plate under a gold hairline.
    private func hudChip<C: View>(active: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(height: 30)
            .padding(.horizontal, 10)
            .background(Capsule().fill(active ? Theme.goldDeep.opacity(0.92) : Theme.plate.opacity(0.6)))
            .overlay(Capsule().strokeBorder(active ? Theme.gold : Theme.stroke, lineWidth: 1))
    }

    // MARK: - The player's team

    /// Statuses at team-plate size: the glyph on a coloured disc, three of
    /// them and a count. The named chips are for the actor plate and the boss
    /// bar, where there is room for words.
    private func statusPips(_ statuses: [ActiveStatus]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(statuses.prefix(3).enumerated()), id: \.offset) { _, status in
                Image(systemName: status.kind.glyph)
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 11, height: 11)
                    .background(
                        Circle().fill(status.kind.isBuff ? Color(hex: "#2E8FBF") : Color(hex: "#B8403A"))
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
            }
            if statuses.count > 3 {
                Text("+\(statuses.count - 3)")
                    .font(Theme.numeric(7))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - The combat feed

    // MARK: - Command bar

    // MARK: - The strip and the controls

    /// The stage's name and the wave, small at the top left; a repeat run's
    /// count beside them. Nothing else at the top of a normal wave — the
    /// genre's frame is empty there.
    private var topStrip: some View {
        HStack(spacing: 6) {
            hudChip {
                Text(model.context.title)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .leading)
            }
            if model.waveCount > 1 {
                hudChip {
                    Text("Wave \(model.waveIndex)/\(model.waveCount)")
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                }
            }
            if let session = model.repeatSession {
                // Runs done of runs asked for; a tap stops after this one.
                Button {
                    model.stopRepeating()
                } label: {
                    hudChip(active: true) {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                            Text("\(min(session.completed + 1, session.requested))/\(session.requested)")
                        }
                        .font(Theme.numeric(11).weight(.bold))
                        .foregroundStyle(Theme.gold)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The genre's three: a gear (the log, forfeit), the speed, and auto.
    private var controls: some View {
        HStack(spacing: 6) {
            squareControl(active: showLog) {
                showMenu = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .bold))
            }
            squareControl(active: model.speed > 1) {
                model.speed = model.speed >= 3 ? 1 : model.speed * 2
            } label: {
                Text("×\(Int(model.speed))")
                    .font(Theme.numeric(13).weight(.black))
            }
            squareControl(active: model.autoBattle) {
                model.autoBattle.toggle()
            } label: {
                Image(systemName: model.autoBattle ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .black))
            }
            .accessibilityAddTraits(model.autoBattle ? .isSelected : [])
        }
    }

    /// One control: a 36-point plate, gold-rimmed and gold-lit when it is on.
    private func squareControl<L: View>(active: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(active ? Theme.ink : Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Theme.gold.opacity(0.92) : Theme.plate.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(active ? Theme.goldDeep : Theme.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// The skills as the genre's squares at the bottom right: no plate
    /// behind them, the caster's element lighting each.
    private func skillRow(_ actor: Combatant) -> some View {
        HStack(spacing: 10) {
            ForEach(model.availableSkills) { option in
                SkillButton(
                    skill: option.skill,
                    cooldown: option.cooldown,
                    isSelected: model.selectedSkillSlot == option.slot,
                    tint: actor.element.color,
                    forecast: forecast(option.skill, actor: actor),
                    onHold: { withAnimation { heldSkill = option.skill } },
                    onPreview: { pressed in
                        previewSlot = pressed ? option.slot : nil
                    }
                ) {
                    model.selectSkill(option.slot)
                }
            }
        }
    }

    private var skipButton: some View {
        Button {
            model.skipAnimation()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "forward.fill")
                Text("Skip")
            }
            .font(Theme.body(12).weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(Theme.plate.opacity(0.6)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }

    /// The target the next tap would hit, if one is aimed.
    private var aimedTarget: Combatant? {
        model.displayedCombatants.first { $0.id == model.highlightedTarget }
    }

    // MARK: - Shared readouts

    /// One health colour ramp for the whole HUD. Green until 60%, amber to
    /// 30%, red under it — the old single break at 30% meant a unit on 35%
    /// looked exactly like one on 100%, which is the difference between
    /// healing it this turn and losing it next turn.
    private func healthTint(_ fraction: Double) -> Color {
        if fraction < 0.3 { return Theme.danger }
        if fraction < 0.6 { return Color(hex: "#F2A03C") }
        return Theme.success
    }

    /// How the element wheel reads for this particular attack, as a chip, so
    /// "will this hurt" is answered before the skill is spent rather than by
    /// the size of the number afterwards.
    private func matchupChip(attacker: Combatant, defender: Combatant) -> some View {
        let matchup = attacker.element.matchup(against: defender.element)
        let text: String
        let tint: Color
        let glyph: String
        switch matchup {
        case .advantage:
            text = "STRONG ×1.5"
            tint = Theme.success
            glyph = "arrow.up.right.circle.fill"
        case .neutral:
            text = "NEUTRAL"
            tint = Theme.textSecondary
            glyph = "equal.circle.fill"
        case .disadvantage:
            text = "WEAK ×0.7"
            tint = Theme.danger
            glyph = "arrow.down.right.circle.fill"
        }
        return Chip(text: text, systemImage: glyph, tint: tint, filled: matchup != .neutral)
    }

    /// What a skill will do, in one short string, for the face of its tile.
    private func forecast(_ skill: Skill, actor: Combatant) -> String? {
        if let damage = skill.damage {
            let value = Int(estimatedDamage(skill, actor: actor))
            return damage.hits > 1 ? "≈\(value) ×\(damage.hits)" : "≈\(value)"
        }
        if skill.utilities.contains(where: {
            if case .healTargetMaxHealth = $0 { return true }
            if case .healFromAttack = $0 { return true }
            return false
        }) { return "HEAL" }
        if skill.utilities.contains(where: {
            if case .revive = $0 { return true }
            return false
        }) { return "REVIVE" }
        if skill.utilities.contains(where: {
            if case .cleanse = $0 { return true }
            return false
        }) { return "CLEANSE" }
        if skill.utilities.contains(where: {
            if case .strip = $0 { return true }
            return false
        }) { return "STRIP" }
        if let status = skill.statuses.first {
            return status.kind.isBuff ? "BUFF" : "DEBUFF"
        }
        return nil
    }

    /// The damage the skill would do to the unit currently aimed at — its real
    /// defence and the real element matchup, not the collection screen's
    /// standing dummy. It is an estimate and it is labelled with a ≈: the crit
    /// roll and the damage variance are still ahead of it.
    private func estimatedDamage(_ skill: Skill, actor: Combatant) -> Double {
        guard let damage = skill.damage else { return 0 }
        let target = aimedTarget
            ?? model.displayedCombatants.first { $0.side == actor.side.opposing && $0.isAlive }
        var value = DamageCalculator.previewDamage(
            attackStat: actor.scalingValue(for: damage.scaling),
            spec: damage,
            againstDefense: target?.currentStats.def ?? 800
        )
        if let target, target.side != actor.side {
            value *= actor.element.matchup(against: target.element).damageMultiplier
        }
        return value.rounded()
    }

    /// Who a skill lands on, in one or two words.
    private func scopeWord(_ target: TargetSelector) -> String {
        switch target {
        case .singleEnemy: return "1 enemy"
        case .allEnemies: return "All enemies"
        case .randomEnemies(let count): return "\(count) random"
        case .lowestHealthEnemy: return "Weakest"
        case .caster: return "Self"
        case .singleAlly: return "1 ally"
        case .allAllies: return "All allies"
        case .lowestHealthAlly: return "Hurt ally"
        case .deadAlly: return "Fallen ally"
        case .otherAllies: return "Other allies"
        }
    }

    /// Buffs and debuffs as chips: blue for a buff, red for a debuff, the
    /// turns left last. `compact` drops the name and keeps the glyph, and it
    /// stops at four rather than six: compact or not, four chips are 105
    /// points, and these now share the actor plate's health line rather than
    /// having a line of their own. The rest are counted in a `+n`.
    private func statusChips(_ statuses: [ActiveStatus], compact: Bool = false) -> some View {
        let limit = 4
        return HStack(spacing: 3) {
            ForEach(Array(statuses.prefix(limit).enumerated()), id: \.offset) { _, status in
                HStack(spacing: 2) {
                    Image(systemName: status.kind.glyph)
                        .font(.system(size: 9, weight: .bold))
                    if !compact {
                        Text(status.kind.displayName)
                            .font(Theme.body(9).weight(.semibold))
                            .lineLimit(1)
                    }
                    Text("\(status.turnsRemaining)")
                        .font(Theme.numeric(9))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(status.kind.isBuff ? Color(hex: "#2E8FBF") : Color(hex: "#B8403A")))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            }
            if statuses.count > limit {
                Text("+\(statuses.count - limit)")
                    .font(Theme.numeric(9))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// The boss's bar across the whole top of the frame, the genre's: its
    /// name and its numbers on a line, then a gold health bar with the blue
    /// attack bar under it in one dark track; a raid's barrier over the
    /// health in the weakness's colour; its chips at the right.
    private func bossBar(_ boss: Combatant) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text(boss.name.uppercased())
                    .font(Theme.body(10).weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                if let weakness = model.raidWeakness(boss.id) {
                    Chip(text: "Open to \(weakness.displayName)", systemImage: weakness.glyph, tint: weakness.color)
                }
                // Only above 1: an enrage that has not started yet is not news.
                if model.raidEnrage(boss.id) > 1.001 {
                    Chip(
                        text: String(format: "Enraged ×%.1f", model.raidEnrage(boss.id)),
                        systemImage: "flame.fill",
                        tint: Theme.danger,
                        filled: true
                    )
                }
                if !boss.statuses.isEmpty {
                    statusChips(boss.statuses)
                }
                Spacer(minLength: 0)
                Text("\(Int(boss.currentHealth.rounded())) / \(Int(boss.maxHealth.rounded()))")
                    .font(Theme.numeric(10).weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
            }
            VStack(spacing: 1.5) {
                // A raid boss's barrier sits ON the health bar, because it is
                // the bar the player is actually hitting: damage goes into it
                // first, and the health underneath does not move until it
                // breaks. Drawn in the boss's current weakness colour.
                if let barrier = model.raidBarrierFraction(boss.id) {
                    let tint = model.raidWeakness(boss.id)?.color ?? Theme.gold
                    StatBar(value: barrier, maximum: 1, tint: tint, height: 4)
                }
                StatBar(value: boss.currentHealth, maximum: boss.maxHealth, tint: Theme.gold, height: 9)
                StatBar(value: boss.attackBar, maximum: 1, tint: Color(hex: "#5CC4F0"), height: 3)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.goldDeep.opacity(0.7), lineWidth: 1))
        }
        .padding(.horizontal, 2)
        // The one thing a player taps a boss for is to aim at it, and its
        // head reaches the band this bar lies across.
        .allowsHitTesting(false)
    }

    /// An ultimate's announcement: a dark band across the field, the
    /// caster's card sliding in from the left and the skill's name from the
    /// right, gone in a second.
    private func cutInBanner(_ cutIn: BattleViewModel.CutIn) -> some View {
        let accent = Color(hex: cutIn.accentHex)
        // Annotated rather than inferred inside the modifier: nil is the
        // "leave it alone" value for both, and a bare ternary against nil is
        // the sort of thing that needs a compiler to settle.
        let speechLines: Int? = cutIn.isSpeech ? 3 : nil
        let speechWidth: CGFloat? = cutIn.isSpeech ? 420 : nil
        return VStack {
            Spacer().frame(height: 90)
            ZStack {
                LinearGradient(
                    colors: [.clear, Theme.ink.opacity(0.92), Theme.ink.opacity(0.92), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                Rectangle().fill(accent.opacity(0.9)).frame(height: 2).frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(accent.opacity(0.9)).frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom)
                HStack(spacing: 16) {
                    if BundleImage.exists(cutIn.portrait) {
                        BundleImage(name: cutIn.portrait)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accent, lineWidth: 2))
                            .shadow(color: accent.opacity(0.8), radius: 12)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cutIn.unitName.uppercased())
                            .font(Theme.body(11).weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(accent)
                        // A skill's name is two or three words and wears the
                        // display face; a boss's line is a sentence, and at 26pt
                        // an eighty-character one runs straight out of the 84pt
                        // band. It is set smaller, allowed three lines and given
                        // a width to wrap inside.
                        Text(cutIn.skillName)
                            .font(cutIn.isSpeech ? Theme.title(15) : Theme.display(26))
                            .foregroundStyle(Theme.textPrimary)
                            // Every one of these is written so that it is the
                            // no-op it used to be when this is not speech: the
                            // ultimate's announcement must look exactly as it did.
                            .lineLimit(speechLines)
                            .minimumScaleFactor(cutIn.isSpeech ? 0.8 : 1)
                            .fixedSize(horizontal: false, vertical: cutIn.isSpeech)
                            .frame(maxWidth: speechWidth, alignment: .leading)
                            .shadow(color: accent.opacity(0.9), radius: 10)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(height: 84)
            Spacer()
        }
    }

    /// The card a held skill shows: name, cooldown, what it does.
    private func skillCard(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(skill.name)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.gold)
                Spacer()
                Text(skill.cooldown > 0 ? "Cooldown \(skill.cooldown) turns" : "No cooldown")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(skill.description)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap to close")
                .font(Theme.body(9))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: 360)
        .background(Theme.panel(Theme.tightCorner))
    }

    // MARK: - Log

    private var logOverlay: some View {
        VStack {
            Spacer()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(model.log.indices, id: \.self) { index in
                            let line = model.log[index]
                            Text(line)
                                .font(Theme.body(11))
                                .foregroundStyle(
                                    line.hasPrefix("—") ? Theme.gold : Theme.textSecondary
                                )
                                .id(index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 150)
                .background(Theme.panel())
                .onChange(of: model.log.count) { _, count in
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 96)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// One skill, the genre's square: a dark socket lit from behind in the
/// caster's element, the glyph large and white, the name small under it,
/// the estimate printed on the bottom edge, a gold frame that brightens
/// and grows on the skill in hand, a dark veil with the turns left while
/// it cools. 60 points, three abreast at the bottom right, no plate
/// behind them.
struct SkillButton: View {
    let skill: Skill
    let cooldown: Int
    let isSelected: Bool
    /// The caster's element, the light behind the glyph.
    var tint: Color = Theme.gold
    /// One line saying what the skill will do — "≈1240 ×3", "HEAL",
    /// "DEBUFF". Worked out by the view that knows the caster's stats and
    /// what is aimed at, because the tile does not.
    var forecast: String? = nil
    /// Held down: show what the skill does.
    var onHold: (() -> Void)? = nil
    /// True the moment a finger lands on the tile, false when it lifts.
    var onPreview: ((Bool) -> Void)? = nil
    let action: () -> Void

    /// Set by a hold so the release that follows it is not read as a tap:
    /// reading a skill must never cast it.
    @State private var wasHeld = false

    private var isReady: Bool { cooldown <= 0 }
    private static let corner: CGFloat = 10

    var body: some View {
        Button {
            if wasHeld { wasHeld = false; return }
            if isReady { action() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#3B2F22"), Color(hex: "#1A1410")], startPoint: .top, endPoint: .bottom))
                RadialGradient(colors: [tint.opacity(isReady ? 0.8 : 0.25), .clear], center: .center, startRadius: 2, endRadius: 34)
                VStack(spacing: 2) {
                    Image(systemName: glyph)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(isReady ? Color.white : Theme.textSecondary)
                        .shadow(color: tint.opacity(isReady ? 0.9 : 0), radius: 6)
                    Text(skill.name)
                        .font(Theme.body(8).weight(.bold))
                        .foregroundStyle(Color.white.opacity(isReady ? 0.92 : 0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 3)
                }
                .padding(.bottom, forecast == nil ? 0 : 6)
                if let forecast {
                    OutlinedText(text: forecast, font: Theme.numeric(9).weight(.black), width: 0.8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 2)
                }
                if !isReady {
                    RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                    OutlinedText(text: "\(cooldown)", font: Theme.display(26), fill: .white, width: 1.2)
                }
            }
            .frame(width: 60, height: 60)
            .overlay(alignment: .topTrailing) {
                // Who it lands on, as a glyph in the corner: one figure,
                // three figures, a heart.
                Image(systemName: Self.targetGlyph(for: skill))
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .padding(2.5)
                    .background(Circle().fill(Theme.plate.opacity(0.95)))
                    .offset(x: 3, y: -3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(
                        isReady ? Rarity.legendary.frame : Rarity.common.frame,
                        lineWidth: isSelected ? 3 : 2
                    )
            )
            .shadow(color: isSelected ? Theme.gold.opacity(0.9) : Color.black.opacity(0.5), radius: isSelected ? 10 : 4, y: isSelected ? 0 : 2)
            .scaleEffect(isSelected ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        // A ButtonStyle rather than a gesture: `isPressed` is the one way to
        // watch a finger land that cannot swallow the tap it is watching.
        .buttonStyle(PressStyle(onPress: { pressed in onPreview?(pressed) }))
        // A hold shows the card even on a skill that is cooling down.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                wasHeld = true
                onHold?()
                // The button may or may not fire on the release after a hold
                // (it varies by iOS); either way the flag is spent shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { wasHeld = false }
            }
        )
        .disabled(!isReady && onHold == nil)
    }

    /// Reports the press to the caller and shrinks the tile while it is held.
    struct PressStyle: ButtonStyle {
        var onPress: (Bool) -> Void

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.93 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
        }
    }

    private var glyph: String { Self.glyph(for: skill) }

    /// A glyph per skill shape, so the bar is readable without art. The
    /// unit sheet's skill tiles use the same one.
    static func glyph(for skill: Skill) -> String {
        if skill.utilities.contains(where: {
            if case .healTargetMaxHealth = $0 { return true }
            if case .healFromAttack = $0 { return true }
            return false
        }) { return "cross.case.fill" }
        if skill.cooldown >= 4 { return "burst.fill" }
        if skill.statuses.contains(where: { $0.kind.isHardCC }) { return "bolt.slash.fill" }
        if (skill.damage?.hits ?? 1) > 1 { return "square.stack.3d.down.right.fill" }
        return skill.cooldown > 0 ? "flame.fill" : "figure.fencing"
    }

    /// A glyph per target shape: how many, and which side.
    static func targetGlyph(for skill: Skill) -> String {
        switch skill.target {
        case .allEnemies: return "person.3.fill"
        case .randomEnemies: return "die.face.5.fill"
        case .allAllies, .otherAllies: return "heart.circle.fill"
        case .singleAlly, .lowestHealthAlly: return "heart.fill"
        case .deadAlly: return "arrow.uturn.up.circle.fill"
        case .caster: return "person.crop.circle.fill"
        default: return "person.fill"
        }
    }
}

/// The end of a battle, in two acts.
///
/// The owner: "when we win a battle, it should first show the stats of the
/// battle, then you tap to show a chest that opens or like a greek chest, as
/// it opens it shows your prize. Again, I want this to feel PREMIUM."
///
/// ACT ONE, THE RECKONING. The word, the stars ticking in one at a time, the
/// three numbers of the fight, and a row per unit saying what each one did —
/// damage dealt as a bar against the best, damage taken, healing, kills — with
/// a laurel on the one that did the most. A defeat gets the same reckoning in
/// wine instead of gold, and a Continue button, because there is no chest to
/// open after losing.
///
/// ACT TWO, THE CHEST. One tap and the reckoning gives way to a marble
/// strongbox bound in bronze, shut, waiting. A second tap lifts the lid: a
/// flash, rays, the inside lit gold, and the spoils rise out of it one by one
/// onto a shelf above, each with a tick and a pulse in the hand. Only then does
/// Continue appear. Every timed step checks it still belongs to the current
/// sequence, so a tap that skips ahead cannot be followed by a stale step.
///
/// Nothing here is a flat fill. The chest is stone plate and bronze plate over
/// a bevel; the tiles are panels; the light is additive over the scrim. That
/// is the whole difference between a receipt and a reward.
struct BattleResultView: View {
    let summary: BattleSummary
    let onDismiss: () -> Void
    /// The CI tour sets this so a five-second photograph catches the chest
    /// open with the spoils out, rather than the reckoning waiting for a tap.
    var autoplay: Bool = false
    /// The store, for the relic drop card a spoil tile opens; without one
    /// the tiles are not tappable.
    var store: GameStore? = nil

    private enum Phase { case reckoning, chest, opened }

    @State private var phase: Phase = .reckoning
    @State private var shownStars = 0
    @State private var rowsShown = 0
    @State private var lidOpen = false
    /// The chest has lifted and faded under the flash; the spoils remain.
    @State private var chestGone = false
    @State private var flash: Double = 0
    @State private var raysShown = false
    @State private var rays: Double = 0
    @State private var lootShown = 0
    @State private var continueShown = false
    @State private var pulse = false
    @State private var sequence = 0
    /// The relic whose drop card is up.
    @State private var openedRelic: Relic?

    private var won: Bool { summary.outcome == .victory }
    private var hasSpoils: Bool { won && !summary.loot.isEmpty }

    var body: some View {
        ZStack {
            // The scrim. Darker than the old 0.78 because the stage under it is
            // sunlit now, and the two acts are read against it. It stays dark
            // on a cream interface on purpose: the chest's beam, the flash and
            // the rays are additive light and vanish on cream, and everything
            // written straight on it is gold or marble, never ink — the panels
            // carry the ink.
            Color.black.opacity(0.84).ignoresSafeArea()

            switch phase {
            case .reckoning:
                reckoning
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .chest, .opened:
                chestAct
                    .transition(.opacity)
            }
        }
        .onAppear { beginReckoning() }
    }

    // MARK: - Act one

    private var reckoning: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                verdict
                    .frame(width: 292)
                unitRows
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)

            Spacer(minLength: 6)

            if hasSpoils {
                Text("TAP TO CLAIM YOUR SPOILS")
                    .font(Theme.body(11).weight(.black))
                    .tracking(2.2)
                    .foregroundStyle(Theme.gold)
                    .opacity(pulse ? 1 : 0.45)
                    .padding(.bottom, 14)
            } else {
                PrimaryButton(title: "Continue", action: onDismiss)
                    .frame(width: 220)
                    .padding(.bottom, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasSpoils else { return }
            advanceToChest()
        }
    }

    /// The word, the stars and the three numbers.
    private var verdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(Theme.display(46))
                .foregroundStyle(won ? Theme.gold : (summary.outcome == .draw ? Theme.marble : Theme.wine))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: (won ? Theme.gold : Theme.wine).opacity(0.45), radius: 18)
            if !summary.title.isEmpty {
                // Marble, not the caption ink: this line stands straight on
                // the dark scrim, with no panel under it.
                Text(summary.title)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.marble)
                    .lineLimit(1)
            }
            if won, summary.stars > 0 {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(index <= shownStars ? Theme.gold : Theme.stroke)
                            .scaleEffect(index <= shownStars ? 1 : 0.7)
                            .shadow(color: Theme.gold.opacity(index <= shownStars ? 0.7 : 0), radius: 8)
                            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: shownStars)
                    }
                    if summary.isFirstClear {
                        Chip(text: "First clear", systemImage: "seal.fill", tint: Theme.verdigris, filled: true)
                            .padding(.leading, 6)
                    }
                }
                .padding(.top, 2)
            }
            HStack(spacing: 8) {
                statTile("TURNS", value: "\(summary.turns)")
                statTile("DEALT", value: Int(summary.damageDealt).formatted())
                statTile("TAKEN", value: Int(summary.damageTaken).formatted())
            }
            .padding(.top, 8)
        }
    }

    private func statTile(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(Theme.body(8).weight(.black))
                .tracking(1.4)
                .foregroundStyle(Theme.goldDim)
            Text(value)
                .font(Theme.numeric(15))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Theme.panel(Theme.tightCorner))
    }

    /// One row per unit, damage as a bar against the best in the team, and the
    /// laurel on whoever earned it.
    private var unitRows: some View {
        let best = max(1, summary.unitStats.map { $0.dealt + $0.healed }.max() ?? 1)
        return VStack(spacing: 6) {
            ForEach(Array(summary.unitStats.enumerated()), id: \.element.id) { index, unit in
                unitRow(unit, share: (unit.dealt + unit.healed) / best)
                    .opacity(index < rowsShown ? 1 : 0)
                    .offset(x: index < rowsShown ? 0 : 28)
                    .animation(.spring(response: 0.42, dampingFraction: 0.8), value: rowsShown)
            }
            if summary.unitStats.isEmpty {
                Text("No reckoning for this one.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.marble)
            }
        }
    }

    private func unitRow(_ unit: BattleSummary.UnitStat, share: Double) -> some View {
        let isMVP = unit.id == summary.mvpID
        return HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if BundleImage.exists(unit.portraitName) {
                        BundleImage(name: unit.portraitName, renderedAt: 44)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(unit.element.color.opacity(0.5))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .rarityFrame(Rarity(stars: unit.stars), radius: 6)
                .saturation(unit.survived ? 1 : 0.15)
                .opacity(unit.survived ? 1 : 0.6)
                if isMVP {
                    Image(systemName: "laurel.leading")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .padding(3)
                        .background(Circle().fill(Theme.gold))
                        .offset(x: 6, y: -6)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(unit.name)
                        .font(Theme.title(12))
                        .foregroundStyle(isMVP ? Theme.gold : Theme.textPrimary)
                        .lineLimit(1)
                    if isMVP {
                        Text("MVP")
                            .font(Theme.body(8).weight(.black))
                            .tracking(1)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.gold))
                    }
                    if !unit.survived {
                        Chip(text: "Fallen", systemImage: "xmark", tint: Theme.wine)
                    }
                    Spacer(minLength: 0)
                    if unit.kills > 0 {
                        Chip(text: "\(unit.kills) \(unit.kills == 1 ? "kill" : "kills")", systemImage: "bolt.fill", tint: Theme.gold)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.plate.opacity(0.6))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.goldDim, Theme.gold], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * share))
                    }
                }
                .frame(height: 5)
                HStack(spacing: 10) {
                    Text("Dealt \(Int(unit.dealt).formatted())")
                    if unit.healed > 0 { Text("Healed \(Int(unit.healed).formatted())") }
                    Text("Taken \(Int(unit.taken).formatted())")
                }
                .font(Theme.numeric(9))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.panel(Theme.tightCorner))
    }

    // MARK: - Act two

    private var chestAct: some View {
        ZStack {
            // Rays behind the chest, additive, only once it is open. Half
            // the reveal's strength: there is a shelf of tiles to read here.
            AngularGradient(
                colors: [Theme.gold.opacity(0), Theme.gold.opacity(0.16), Theme.gold.opacity(0),
                         Theme.gold.opacity(0.16), Theme.gold.opacity(0), Theme.gold.opacity(0.16),
                         Theme.gold.opacity(0), Theme.gold.opacity(0.16), Theme.gold.opacity(0)],
                center: .center
            )
            .scaleEffect(2.2)
            .opacity(raysShown ? 1 : 0)
            .animation(.easeOut(duration: 0.8), value: raysShown)
            .rotationEffect(.degrees(rays))
            .blendMode(.plusLighter)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            RadialGradient(
                colors: [Theme.gold.opacity(lidOpen ? 0.34 : 0.08), Theme.gold.opacity(lidOpen ? 0.12 : 0.03), .clear],
                center: .init(x: 0.5, y: 0.62),
                startRadius: 0,
                endRadius: lidOpen ? 330 : 160
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.6), value: lidOpen)

            // The chest, centred, until the flash takes it; then the
            // spoils panel stands where it stood — the genre's reward box,
            // with the tiles popping in one by one and the way out inside
            // it. The shelf this replaces floated six pale tiles in the
            // empty middle of the screen once the chest had gone.
            if chestGone {
                SpoilsPanel(
                    title: summary.title,
                    stars: summary.stars,
                    isFirstClear: summary.isFirstClear,
                    loot: summary.loot,
                    shown: lootShown,
                    continueShown: continueShown,
                    tapAction: tapAction(for:),
                    onContinue: onDismiss
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                VStack(spacing: 14) {
                    Spacer(minLength: 0)

                    RewardChestView(open: lidOpen, gone: chestGone)
                        .frame(width: 300, height: 170)
                        .contentShape(Rectangle())
                        .onTapGesture { openChest() }

                    Group {
                        if phase == .chest {
                            Text("TAP TO OPEN")
                                .font(Theme.body(11).weight(.black))
                                .tracking(2.2)
                                .foregroundStyle(Theme.gold)
                                .opacity(pulse ? 1 : 0.45)
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                    .frame(height: 44)

                    Spacer(minLength: 0)
                }
            }

            // The flash on the lid coming up. White over gold, gone in under
            // half a second.
            Color(hex: "#FFF3D0")
                .opacity(flash * 0.85)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if phase == .chest { openChest() } else if phase == .opened, !continueShown { finishOpeningNow() }
        }
        // The genre's rune-obtained card: a tap on a relic's tile shows it
        // large with Sell, Keep or Lock and keep, before the inventory.
        .sheet(item: $openedRelic) { relic in
            if let store {
                RelicDropCard(relicID: relic.id)
                    .environmentObject(store)
            }
        }
    }

    /// A relic's tile opens its card when there is a store to sell through;
    /// every other spoil is just shown.
    private func tapAction(for item: BattleSummary.Loot) -> (() -> Void)? {
        guard store != nil, let relic = item.relic else { return nil }
        return { openedRelic = relic }
    }

    // MARK: - Sequencing

    private func after(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func beginReckoning() {
        sequence += 1
        let mine = sequence
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        AudioLibrary.shared.play(won ? .victory : .defeat, volume: 0.9)
        Juice.haptic(won ? .heavy : .medium)

        let stars = won ? summary.stars : 0
        for i in 0..<stars {
            after(0.45 + Double(i) * 0.18) {
                guard mine == sequence else { return }
                shownStars = i + 1
                AudioLibrary.shared.play(.starTick, volume: 0.8)
                Juice.haptic(i == stars - 1 ? .medium : .light)
            }
        }
        let rowStart = 0.45 + Double(stars) * 0.18 + 0.1
        for i in 0..<summary.unitStats.count {
            after(rowStart + Double(i) * 0.09) {
                guard mine == sequence else { return }
                rowsShown = i + 1
            }
        }
        if autoplay, hasSpoils {
            after(rowStart + Double(summary.unitStats.count) * 0.09 + 3.2) {
                guard mine == sequence else { return }
                advanceToChest()
                // `advanceToChest()` has just bumped the sequence, so the
                // second step must guard on the NEW number: guarding on
                // `mine` here is what left the tour's chest shut.
                // Two seconds closed, so the tour photographs the chest
                // on its beat before the lid goes.
                let chestSequence = sequence
                after(2.2) {
                    guard chestSequence == sequence else { return }
                    openChest()
                }
            }
        }
    }

    private func advanceToChest() {
        guard phase == .reckoning else { return }
        sequence += 1
        AudioLibrary.shared.play(.uiConfirm, volume: 0.6)
        Juice.haptic(.light)
        withAnimation(.easeInOut(duration: 0.4)) { phase = .chest }
        withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) { rays = 360 }
    }

    private func openChest() {
        guard phase == .chest else { return }
        sequence += 1
        let mine = sequence
        phase = .opened
        Juice.haptic(.medium)
        // The chest shakes, the lid swings back and the light stands up out
        // of it (`RewardChestView`, about a second); then the flash, under
        // which the chest lifts away, and the spoils rise onto the shelf.
        lidOpen = true
        after(0.3) {
            guard mine == sequence else { return }
            AudioLibrary.shared.play(.summonBurst, volume: 0.9)
        }
        after(1.4) {
            guard mine == sequence else { return }
            Juice.haptic(.heavy)
            flash = 1
            withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
            raysShown = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { chestGone = true }
        }

        let count = min(SpoilsPanel.capacity, summary.loot.count)
        for i in 0..<count {
            after(1.6 + Double(i) * 0.14) {
                guard mine == sequence else { return }
                lootShown = i + 1
                AudioLibrary.shared.play(.starTick, volume: 0.7)
                Juice.haptic(.light)
            }
        }
        after(1.6 + Double(count) * 0.14 + 0.35) {
            guard mine == sequence else { return }
            withAnimation(.easeOut(duration: 0.3)) { continueShown = true }
        }
    }

    /// A tap during the opening lands everything at once.
    private func finishOpeningNow() {
        sequence += 1
        lidOpen = true
        withAnimation(.easeOut(duration: 0.25)) { chestGone = true }
        raysShown = true
        flash = 0
        lootShown = min(SpoilsPanel.capacity, summary.loot.count)
        withAnimation(.easeOut(duration: 0.2)) { continueShown = true }
    }

    private var headline: String {
        switch summary.outcome {
        case .victory: return "VICTORY"
        case .defeat: return "DEFEAT"
        case .draw: return "DRAW"
        }
    }
}

/// The third act of a win, the genre's reward box: a framed panel with a
/// ribbon, the chest and the stars at its head, the spoils as a grid of
/// tiles with their counts printed on them, and the way out under them. The
/// owner, with Summoners War's box beside our shelf of six pale glyph tiles
/// on a gradient: "You see how nice this looks? Why does ours look so basic
/// and ugly?" The tiles are `RewardTile`, the same one every screen that
/// pays out now draws, so the painted icons land here the day they ship.
struct SpoilsPanel: View {
    let title: String
    let stars: Int
    let isFirstClear: Bool
    let loot: [BattleSummary.Loot]
    /// How many tiles have popped in so far.
    let shown: Int
    let continueShown: Bool
    var tapAction: (BattleSummary.Loot) -> (() -> Void)? = { _ in nil }
    let onContinue: () -> Void

    /// Two rows of six; a longer haul says how many more.
    static let capacity = 12

    private var items: [BattleSummary.Loot] { Array(loot.prefix(Self.capacity)) }
    /// Up to six in one row; more than six splits into two rows as even as
    /// they come.
    private var columns: Int { items.count <= 6 ? max(1, items.count) : min(6, (items.count + 1) / 2) }
    private var tileSize: CGFloat { columns >= 6 ? 58 : 64 }

    var body: some View {
        VStack(spacing: 10) {
            header
            grid
            Group {
                if continueShown {
                    PrimaryButton(title: "Continue", action: onContinue)
                        .frame(width: 220)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Color.clear
                }
            }
            .frame(height: Theme.buttonHeight)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .frame(width: 600)
        .panelBackground()
        .overlay(alignment: .top) {
            ribbon.offset(y: -14)
        }
    }

    private var ribbon: some View {
        Text("SPOILS OF VICTORY")
            .font(Theme.title(13))
            .tracking(2)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 28)
            .padding(.vertical, 7)
            .background {
                if let ribbon = Chrome.slice("ui_ribbon", Chrome.ribbonInsets) {
                    ribbon
                } else {
                    Capsule().fill(Theme.gold)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    /// The chest, the stage and its stars: what was won, and how well.
    private var header: some View {
        HStack(spacing: 12) {
            TributeChestImage(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "The spoils" : title)
                    .font(Theme.title(13))
                    .tracking(1)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(1...3, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(index <= stars ? Theme.gold : Theme.stroke)
                            .shadow(color: Theme.gold.opacity(index <= stars ? 0.6 : 0), radius: 4)
                    }
                    if isFirstClear {
                        Chip(text: "First clear", systemImage: "seal.fill", tint: Theme.verdigris, filled: true)
                            .padding(.leading, 6)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("\(loot.count) \(loot.count == 1 ? "spoil" : "spoils")")
                .font(Theme.body(10).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var grid: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { column, item in
                        let index = rowIndex * columns + column
                        RewardTile(
                            key: item.key ?? "",
                            title: item.title,
                            amount: item.amount,
                            stars: item.relic == nil ? item.stars : nil,
                            relic: item.relic,
                            size: tileSize,
                            onTap: tapAction(item)
                        )
                        .opacity(index < shown ? 1 : 0)
                        .scaleEffect(index < shown ? 1 : 0.4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.62), value: shown)
                    }
                }
            }
            if loot.count > items.count {
                Text("+\(loot.count - items.count) more in the inventory")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// The reward chest: the Meshy-made box and lid — `prop_reward_chest` and
/// `prop_reward_chest_lid`, one 30-credit image-to-3D mesh from a Gemini
/// concept, cut in two by `tools/prop.py --split-lid` — on a small stage of
/// its own, transparent over the act's rays and glow.
///
/// Closed, it sits on its shadow, turns a few degrees either way so the gold
/// catches the light, and gives a hop every second or so: the tap prompt's
/// beat. Opened, it shakes, the lid swings back past open and settles on the
/// hinge the split left at its back edge, a pillar of gold light stands up
/// out of the box with sparks rising in it, and at the flash the chest lifts
/// and fades and the spoils are what is left. The owner, with the drawn
/// marble strongbox on his phone: "That chest SUCKS. Maybe get a 3D model?
/// Where it opens and then flashes and goes away and shows the reward (like
/// summoners war)."
struct RewardChestView: UIViewRepresentable {
    var open: Bool
    var gone: Bool

    /// Where the split put the lid's origin: the middle of its back-bottom
    /// edge, in metres of a 1 m chest. `prop.py` prints it as it ships; a
    /// lid hinged anywhere else swings through the box or floats.
    private static let hinge = SCNVector3(0, 0.617, -0.433)

    final class Coordinator {
        var scene: SCNScene?
        let chest = SCNNode()
        var lid: SCNNode?
        var opened = false
        var vanished = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        // Transparent, like the reveal's stage: the rays and the gold glow
        // behind this view are the light the chest sits in. The beam and the
        // sparks it spawns are the reveal's own and write no alpha.
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        // The tap belongs to SwiftUI.
        view.isUserInteractionEnabled = false

        let coordinator = context.coordinator
        coordinator.scene = scene
        let chest = coordinator.chest
        chest.addChildNode(StageBuilder.loadProp("prop_reward_chest") ?? Self.standInBox())
        let lid = SCNNode()
        lid.position = Self.hinge
        lid.addChildNode(StageBuilder.loadProp("prop_reward_chest_lid") ?? Self.standInLid())
        chest.addChildNode(lid)
        // The split leaves both halves open shells, and an open lid shows the
        // camera its inside — back faces, culled, a ghost outline in the
        // first frames. Both sides drawn: the lid has an inside, the box has
        // a floor and walls to look into.
        chest.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] { material.isDoubleSided = true }
        }
        coordinator.lid = lid
        scene.rootNode.addChildNode(chest)

        // The shadow under it, the reveal's own image.
        let shadow = SCNPlane(width: 2.1, height: 1.4)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = SummonStageView.contactShadowImage
        shadowMaterial.writesToDepthBuffer = false
        shadow.firstMaterial = shadowMaterial
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadowNode.position = SCNVector3(0, 0.004, 0)
        shadowNode.opacity = 0.7
        scene.rootNode.addChildNode(shadowNode)

        // A 28° lens from in front and a little above, aimed at the lock:
        // the closed chest stands about two thirds of the frame's height,
        // and the lid has room to swing up.
        let camera = SCNCamera()
        camera.fieldOfView = 28
        camera.projectionDirection = .vertical
        camera.zNear = 0.2
        camera.zFar = 60
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.42
        camera.bloomThreshold = 0.9
        camera.bloomBlurRadius = 14
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.45, 3.4)
        cameraNode.look(at: SCNVector3(0, 0.6, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Key from the front-left, warm; a cool fill from the right; a gold
        // rim from behind for the edge of the lid; an ambient floor.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = UIColor(hex: "#FFF1D6") ?? .white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.75, -0.55, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.color = UIColor(hex: "#8FA3D9") ?? .white
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.4, 0.8, 0)
        scene.rootNode.addChildNode(fillNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 560
        rim.color = UIColor(hex: "#FFD36A") ?? .yellow
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.5, 2.7, 0)
        scene.rootNode.addChildNode(rimNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 210
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // The idle: a hop on the prompt's beat, and a slow turn either way.
        let hop = SCNAction.sequence([
            .wait(duration: 1.1),
            .moveBy(x: 0, y: 0.05, z: 0, duration: 0.09),
            .moveBy(x: 0, y: -0.05, z: 0, duration: 0.14),
        ])
        chest.runAction(.repeatForever(hop), forKey: "hop")
        let swayRight = SCNAction.rotateTo(x: 0, y: 0.2, z: 0, duration: 2.8, usesShortestUnitArc: true)
        swayRight.timingMode = .easeInEaseOut
        let swayLeft = SCNAction.rotateTo(x: 0, y: -0.2, z: 0, duration: 2.8, usesShortestUnitArc: true)
        swayLeft.timingMode = .easeInEaseOut
        chest.eulerAngles.y = -0.2
        chest.runAction(.repeatForever(.sequence([swayRight, swayLeft])), forKey: "sway")

        if open { openSequence(coordinator) }
        if gone { vanish(coordinator) }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        if open, !coordinator.opened { openSequence(coordinator) }
        if gone, !coordinator.vanished { vanish(coordinator) }
    }

    /// The shake, the lid, the light. About a second; the flash follows.
    private func openSequence(_ coordinator: Coordinator) {
        guard !coordinator.opened, let lid = coordinator.lid, let scene = coordinator.scene else { return }
        coordinator.opened = true
        let chest = coordinator.chest
        chest.removeAction(forKey: "hop")
        chest.removeAction(forKey: "sway")
        let square = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.15, usesShortestUnitArc: true)
        square.timingMode = .easeOut
        chest.runAction(square)

        // Four quick jolts, a third of a second.
        var jolts: [SCNAction] = []
        for index in 0..<4 {
            let dx: CGFloat = index % 2 == 0 ? 0.06 : -0.06
            jolts.append(.moveBy(x: dx, y: 0.02, z: 0, duration: 0.04))
            jolts.append(.moveBy(x: -dx, y: -0.02, z: 0, duration: 0.04))
        }
        chest.runAction(.sequence(jolts), forKey: "shake")

        // The lid swings back past open and settles. Its origin is its back
        // edge, so a negative turn about X is what lifts the front.
        let swing = SCNAction.rotateTo(x: -2.05, y: 0, z: 0, duration: 0.32, usesShortestUnitArc: false)
        swing.timingMode = .easeOut
        let settle = SCNAction.rotateTo(x: -1.85, y: 0, z: 0, duration: 0.2, usesShortestUnitArc: false)
        settle.timingMode = .easeInEaseOut
        lid.runAction(.sequence([.wait(duration: 0.32), swing, settle]))

        // The light standing up out of the box, and a flare at its mouth.
        let gold = UIColor(hex: "#FFD36A") ?? .yellow
        chest.runAction(.sequence([
            .wait(duration: 0.5),
            .run { _ in
                VFXLibrary.summonBeam(at: SCNVector3(0, 0.3, 0), in: scene, tint: gold)
                VFXLibrary.spawn("impact_radiance", at: SCNVector3(0, 0.8, 0), in: scene, tint: gold, scale: 1.3)
            },
        ]))
    }

    /// Lifts and fades under the flash; the spoils on the shelf are what stay.
    private func vanish(_ coordinator: Coordinator) {
        guard !coordinator.vanished else { return }
        coordinator.vanished = true
        let chest = coordinator.chest
        let away = SCNAction.group([
            .fadeOut(duration: 0.32),
            .moveBy(x: 0, y: 0.5, z: 0, duration: 0.32),
            .scale(to: 1.12, duration: 0.32),
        ])
        away.timingMode = .easeIn
        chest.runAction(away)
    }

    /// A box of wood banded in gold for a bundle without the mesh, at the
    /// mesh's own size, so the sequence plays either way.
    private static func standInBox() -> SCNNode {
        let node = SCNNode()
        let box = SCNBox(width: 1.35, height: 0.62, length: 0.86, chamferRadius: 0.03)
        box.firstMaterial?.diffuse.contents = UIColor(hex: "#5A3A22") ?? .brown
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(0, 0.31, 0)
        node.addChildNode(boxNode)
        for x in [-0.42, 0.42] as [CGFloat] {
            let band = SCNBox(width: 0.14, height: 0.64, length: 0.88, chamferRadius: 0.01)
            band.firstMaterial?.diffuse.contents = UIColor(hex: "#D9A93C") ?? .yellow
            let bandNode = SCNNode(geometry: band)
            bandNode.position = SCNVector3(Float(x), 0.31, 0)
            node.addChildNode(bandNode)
        }
        return node
    }

    private static func standInLid() -> SCNNode {
        let lid = SCNBox(width: 1.35, height: 0.36, length: 0.86, chamferRadius: 0.1)
        lid.firstMaterial?.diffuse.contents = UIColor(hex: "#D9A93C") ?? .yellow
        let node = SCNNode(geometry: lid)
        // Relative to the hinge at the back-bottom edge.
        node.position = SCNVector3(0, 0.18, 0.43)
        return node
    }
}
