import SwiftUI
import UIKit

/// The battle screen: 3D stage underneath, HUD on top.
struct BattleView: View {

    @StateObject var model: BattleViewModel
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var showForfeitConfirm = false
    @State private var showLog = false
    @State private var summary: BattleSummary?
    /// A skill held down: its card shows until a tap or four seconds.
    @State private var heldSkill: Skill?

    var body: some View {
        ZStack {
            BattleSceneView(controller: model.sceneController) { id in
                model.tapUnit(id)
            }
            .ignoresSafeArea()

            // A landscape HUD: one row across the top with the turn order in
            // it, and a bottom bar whose middle is open, so a short screen
            // keeps its centre for the stage.
            VStack(spacing: 6) {
                topBar
                if let boss = model.displayedCombatants.first(where: { $0.isBoss && $0.isAlive }) {
                    bossBar(boss)
                }
                if model.awaitingActor != nil, model.selectedSkillSlot != nil {
                    targetPrompt
                }
                Spacer()
                if let actor = model.awaitingActor {
                    commandPanel(actor: actor)
                } else if model.isPlayingBack {
                    playbackHint
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)

            if let cutIn = model.cutIn {
                cutInBanner(cutIn)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
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
                    .background(Capsule().fill(Theme.ink.opacity(0.82)))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { model.repeatBanner = nil }
                        }
                    }
            }

            if let summary {
                BattleResultView(summary: summary) { dismiss() }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.begin()
            AudioLibrary.shared.playMusic(.battle)
        }
        .onDisappear { AudioLibrary.shared.playMusic(.island) }
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
        .confirmationDialog(
            "Forfeit this battle?",
            isPresented: $showForfeitConfirm,
            titleVisibility: .visible
        ) {
            Button("Forfeit", role: .destructive) { model.forfeit() }
            Button("Keep fighting", role: .cancel) {}
        } message: {
            Text("It counts as a loss, and energy already spent is not refunded.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                showForfeitConfirm = true
            } label: {
                hudChip {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 14)
                }
            }

            hudChip {
                // One line, always: a boss stage is named "<place> — Confrontation",
                // long enough to wrap and shove the whole HUD down over the field.
                Text(model.context.title)
                    .font(Theme.title(14))
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

            turnGauge

            Spacer(minLength: 0)

            Button {
                model.autoBattle.toggle()
            } label: {
                hudChip(active: model.autoBattle) {
                    Text("AUTO")
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(model.autoBattle ? Theme.gold : Theme.textSecondary)
                }
            }
            .accessibilityAddTraits(model.autoBattle ? .isSelected : [])

            Button {
                model.speed = model.speed >= 3 ? 1 : model.speed * 2
            } label: {
                hudChip(active: model.speed > 1) {
                    Text("×\(Int(model.speed))")
                        .font(Theme.numeric(12).weight(.bold))
                        .foregroundStyle(model.speed > 1 ? Theme.gold : Theme.textSecondary)
                        .frame(minWidth: 20)
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

            Button {
                withAnimation { showLog.toggle() }
            } label: {
                hudChip(active: showLog) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(showLog ? Theme.gold : Theme.textSecondary)
                        .frame(width: 16)
                }
            }
        }
        .padding(.top, 6)
    }

    /// One height and one shape for every control in the top row, and one way
    /// for a stateful control — AUTO, fast-forward, the log — to say it is
    /// on: a gold plate under a gold hairline.
    private func hudChip<C: View>(active: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(height: 30)
            .padding(.horizontal, 10)
            .background(Capsule().fill(active ? Theme.goldDeep.opacity(0.9) : Theme.ink.opacity(0.82)))
            .overlay(Capsule().strokeBorder(active ? Theme.gold : Theme.stroke, lineWidth: 1))
    }

    // MARK: - The attack gauge

    /// The genre's clock: every living unit's portrait slides along one
    /// track as its attack bar fills — yours above the line with a blue
    /// ring, theirs below with a red one, gold where a unit stands ready.
    /// Read left to right it is the turn order and the distance between
    /// turns, and a speed buff or a bar knock is visible the moment it lands.
    private var turnGauge: some View {
        let units = model.displayedCombatants.filter(\.isAlive)
        let dot: CGFloat = 26
        return GeometryReader { geo in
            let width = geo.size.width
            let placed = gaugePositions(units, width: width, dot: dot)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.ink.opacity(0.82))
                    .frame(width: width, height: 10)
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                ForEach(1..<4, id: \.self) { quarter in
                    Rectangle()
                        .fill(Theme.stroke)
                        .frame(width: 1, height: 10)
                        .offset(x: width * CGFloat(quarter) / 4)
                }
                ForEach(units) { unit in
                    let x = placed[unit.id] ?? 0
                    gaugeDot(unit, ready: model.awaitingActor?.id == unit.id)
                        .offset(x: x, y: unit.side == .player ? -9 : 9)
                        .animation(.easeOut(duration: 0.35), value: x)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        // Flexible, because the row it sits in also carries a stage name, a
        // wave counter and a repeat chip; fixed at 300 it pushed them off.
        .frame(minWidth: 150, maxWidth: 260, height: 44)
    }

    /// Where each portrait sits on the track. Two units with level bars land
    /// on the same pixel — and a fresh wave arrives with every enemy at zero,
    /// so three enemies read as one dot. Walk each side in bar order and hold
    /// each portrait a little clear of the one before it; the order, which is
    /// what the gauge is for, is unchanged.
    private func gaugePositions(_ units: [Combatant], width: CGFloat, dot: CGFloat) -> [UUID: CGFloat] {
        let span = max(0, width - dot)
        var placed: [UUID: CGFloat] = [:]
        for side in [BattleSide.player, BattleSide.opponent] {
            var lastX = -CGFloat.greatestFiniteMagnitude
            let line = units
                .filter { $0.side == side }
                .sorted { $0.attackBar < $1.attackBar }
            for unit in line {
                let ready = model.awaitingActor?.id == unit.id
                let fraction = ready ? 1.0 : min(1, max(0, unit.attackBar))
                let x = min(max(CGFloat(fraction) * span, lastX + dot * 0.62), span)
                placed[unit.id] = x
                lastX = x
            }
        }
        return placed
    }

    private func gaugeDot(_ unit: Combatant, ready: Bool) -> some View {
        let portrait = unit.model.portraitName(awakened: unit.isAwakened)
        let ring = ready ? Theme.gold : (unit.side == .player ? Theme.info : Theme.danger)
        return ZStack {
            Circle()
                .fill(unit.side == .player ? Theme.info.opacity(0.35) : Theme.danger.opacity(0.35))
            if BundleImage.exists(portrait) {
                BundleImage(name: portrait)
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                Text(String(unit.name.prefix(1)))
                    .font(Theme.body(10).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Circle()
                .strokeBorder(ring, lineWidth: ready ? 2 : 1.2)
        }
        .frame(width: 26, height: 26)
        .shadow(color: ready ? Theme.gold.opacity(0.8) : .clear, radius: 5)
    }

    // MARK: - Command panel

    /// The actor at the left, the skills at the right, nothing in between:
    /// the player line stands in the open middle of a landscape screen.
    private func commandPanel(actor: Combatant) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            actorPlate(actor)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(model.availableSkills) { option in
                    SkillButton(
                        skill: option.skill,
                        cooldown: option.cooldown,
                        isSelected: model.selectedSkillSlot == option.slot,
                        onHold: { withAnimation { heldSkill = option.skill } }
                    ) {
                        model.selectSkill(option.slot)
                    }
                }
            }
            .padding(6)
            // 14 around the buttons' 8 plus 6 of padding: concentric corners.
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.ink.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        }
    }

    /// The unit whose turn it is: portrait, health, what it is under, and
    /// the skill in hand in words — all in the corner, where the genre keeps
    /// it, so the field stays clear.
    private func actorPlate(_ actor: Combatant) -> some View {
        let skill = model.selectedSkillSlot.flatMap { actor.skill(at: $0) }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if BundleImage.exists(actor.model.portraitName(awakened: actor.isAwakened)) {
                    BundleImage(name: actor.model.portraitName(awakened: actor.isAwakened))
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(actor.element.color, lineWidth: 1.5)
                        )
                        .shadow(color: actor.element.color.opacity(0.6), radius: 5)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(actor.name)
                            .font(Theme.body(12).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        ElementBadge(element: actor.element, compact: true)
                    }
                    HStack(spacing: 5) {
                        StatBar(
                            value: actor.currentHealth,
                            maximum: actor.maxHealth,
                            tint: actor.healthFraction < 0.3 ? Theme.danger : Theme.success,
                            height: 6
                        )
                        .frame(width: 104)
                        Text("\(Int(actor.currentHealth.rounded()))")
                            .font(Theme.numeric(9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !actor.statuses.isEmpty {
                        statusChips(actor.statuses, compact: true)
                    }
                }
            }
            // Always drawn, never conditional: the plate's height must not
            // jump the instant a skill is tapped.
            VStack(alignment: .leading, spacing: 1) {
                Text(skill?.name ?? "Choose a skill")
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(skill == nil ? Theme.textSecondary : Theme.gold)
                    .lineLimit(1)
                Text(skill?.description ?? "Hold a skill to read it in full.")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 300, height: 50, alignment: .topLeading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.ink.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }

    /// Buffs and debuffs as chips: blue for a buff, red for a debuff, the
    /// turns left last. `compact` drops the name and keeps the glyph, so the
    /// actor plate can show six where it had room for four names.
    private func statusChips(_ statuses: [ActiveStatus], compact: Bool = false) -> some View {
        let limit = compact ? 6 : 4
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

    /// Where to aim, in one slim line under the top row, so nothing sits
    /// over the field while a target is chosen.
    private var targetPrompt: some View {
        // The skill pre-aims, so the common case is that a target is already
        // chosen: say which one, not that one exists.
        let aim = model.displayedCombatants.first { $0.id == model.highlightedTarget }
        return HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.gold)
            Text(aim.map { "Target: \($0.name)" } ?? "Tap a target on the field")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if aim != nil {
                Button {
                    model.confirmTarget()
                } label: {
                    Text("Confirm")
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(Theme.gold))
                }
            }
            Button {
                model.cancelTargeting()
            } label: {
                Text("Cancel")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(Theme.ink.opacity(0.82)))
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.ink.opacity(0.82)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    /// The boss's bar across the top: the fight that matters, on one line.
    private func bossBar(_ boss: Combatant) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.danger)
            Text(boss.name.uppercased())
                .font(Theme.body(10).weight(.black))
                .tracking(1.2)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            // maxWidth, not width: with four named chips beside it the row
            // would otherwise be wider than the screen.
            StatBar(value: boss.currentHealth, maximum: boss.maxHealth, tint: Theme.danger, height: 6)
                .frame(maxWidth: 260)
            Text("\(Int(boss.currentHealth.rounded())) / \(Int(boss.maxHealth.rounded()))")
                .font(Theme.numeric(9))
                .foregroundStyle(Theme.textSecondary)
            if !boss.statuses.isEmpty {
                statusChips(boss.statuses)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.ink.opacity(0.82)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    /// An ultimate's announcement: a dark band across the field, the
    /// caster's card sliding in from the left and the skill's name from the
    /// right, gone in a second.
    private func cutInBanner(_ cutIn: BattleViewModel.CutIn) -> some View {
        let accent = Color(hex: cutIn.accentHex)
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
                        Text(cutIn.skillName)
                            .font(Theme.display(26))
                            .foregroundStyle(Theme.textPrimary)
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

    /// Nothing asks for a tap while the turn plays, so the bottom band held
    /// one Skip pill and nothing else. The commentary the log already writes
    /// goes here instead: on an enemy turn, on auto, and through a whole
    /// repeat run, this is the only line that says what is happening.
    private var playbackHint: some View {
        HStack(spacing: 10) {
            if let line = model.log.last {
                Text(line)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(Theme.ink.opacity(0.82)))
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    .animation(nil, value: model.log.count)
            }
            Spacer(minLength: 0)
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
                .background(Capsule().fill(Theme.ink.opacity(0.82)))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
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

/// One skill in the command bar.
struct SkillButton: View {
    let skill: Skill
    let cooldown: Int
    let isSelected: Bool
    /// Held down: show what the skill does.
    var onHold: (() -> Void)? = nil
    let action: () -> Void

    /// Set by a hold so the release that follows it is not read as a tap:
    /// reading a skill must never cast it.
    @State private var wasHeld = false

    private var isReady: Bool { cooldown <= 0 }

    var body: some View {
        Button {
            if wasHeld { wasHeld = false; return }
            if isReady { action() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(isReady ? Theme.surfaceRaised : Theme.surface)

                VStack(spacing: 2) {
                    Image(systemName: glyph)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isReady ? Theme.gold : Theme.textSecondary)
                    Text(skill.name)
                        .font(Theme.body(9.5).weight(.semibold))
                        .foregroundStyle(isReady ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.85)
                }
                .padding(4)

                if !isReady {
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .fill(Color.black.opacity(0.62))
                    Text("\(cooldown)")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: 56, height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(isSelected ? Theme.gold : Theme.stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
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
}

/// The end-of-battle panel.
struct BattleResultView: View {
    let summary: BattleSummary
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()

            // Across the wide axis, not down a short one: a repeat run's
            // summary is fifteen lines, and stacked they pushed Continue —
            // the only way out of the battle — off the bottom of the screen.
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 8) {
                    Text(headline)
                        .font(Theme.display(38))
                        .foregroundStyle(summary.outcome == .victory ? Theme.gold : Theme.danger)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if summary.outcome == .victory, summary.stars > 0 {
                        HStack(spacing: 8) {
                            ForEach(1...3, id: \.self) { index in
                                Image(systemName: index <= summary.stars ? "star.fill" : "star")
                                    .font(.system(size: 26))
                                    .foregroundStyle(index <= summary.stars ? Theme.gold : Theme.stroke)
                            }
                        }
                    }
                }
                .frame(width: 190)

                VStack(spacing: 10) {
                    if summary.lines.isEmpty {
                        Text("No rewards this time.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.panel())
                    } else if summary.lines.count > 7 {
                        // A repeat run banks fifteen lines; those scroll.
                        ScrollView {
                            rewardRows
                        }
                        .frame(maxHeight: 190)
                        .background(Theme.panel())
                    } else {
                        rewardRows
                            .background(Theme.panel())
                    }

                    PrimaryButton(title: "Continue", action: onDismiss)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: 620)
        }
    }

    private var rewardRows: some View {
        VStack(spacing: 6) {
            ForEach(summary.lines) { line in
                HStack {
                    Image(systemName: line.icon)
                        .font(.system(size: 12))
                        .frame(width: 22)
                        .foregroundStyle(Theme.goldDim)
                    Text(line.label)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(line.value)
                        .font(Theme.numeric(13))
                        .foregroundStyle(Theme.success)
                }
            }
        }
        .padding(10)
    }

    private var headline: String {
        switch summary.outcome {
        case .victory: return "VICTORY"
        case .defeat: return "DEFEAT"
        case .draw: return "DRAW"
        }
    }
}
