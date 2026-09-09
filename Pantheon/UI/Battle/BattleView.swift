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
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let actor = model.awaitingActor {
                    commandPanel(actor: actor)
                } else if model.isPlayingBack {
                    playbackHint
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

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
                    .background(Capsule().fill(Theme.ink.opacity(0.8)))
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
        HStack(spacing: 10) {
            Button {
                showForfeitConfirm = true
            } label: {
                Image(systemName: "flag.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surface.opacity(0.85)))
            }

            Text(model.context.title)
                .font(Theme.title(14))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.surface.opacity(0.85)))

            if model.waveCount > 1 {
                Text("Wave \(model.waveIndex)/\(model.waveCount)")
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surface.opacity(0.85)))
            }

            turnGauge

            Spacer()

            Toggle(isOn: $model.autoBattle) {
                Text("AUTO").font(Theme.body(11).weight(.bold))
            }
            .toggleStyle(.button)
            .tint(Theme.gold)

            Button {
                model.speed = model.speed >= 3 ? 1 : model.speed * 2
            } label: {
                Text("×\(Int(model.speed))")
                    .font(Theme.numeric(12).weight(.bold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 40, height: 34)
                    .background(Capsule().fill(Theme.surface.opacity(0.85)))
            }

            if let session = model.repeatSession {
                // Runs done of runs asked for; a tap stops after this one.
                Button {
                    model.stopRepeating()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                        Text("\(min(session.completed + 1, session.requested))/\(session.requested)")
                    }
                    .font(Theme.numeric(11).weight(.bold))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Capsule().fill(Theme.surface.opacity(0.85)))
                }
            }

            Button {
                withAnimation { showLog.toggle() }
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surface.opacity(0.85)))
            }
        }
        .padding(.top, 6)
    }

    // MARK: - The attack gauge

    /// The genre's clock: every living unit's portrait slides along one
    /// track as its attack bar fills — yours above the line with a blue
    /// ring, theirs below with a red one, gold where a unit stands ready.
    /// Read left to right it is the turn order and the distance between
    /// turns, and a speed buff or a bar knock is visible the moment it lands.
    private var turnGauge: some View {
        let units = model.displayedCombatants.filter(\.isAlive)
        let width: CGFloat = 300
        let dot: CGFloat = 26
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.ink.opacity(0.7))
                .frame(width: width, height: 10)
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            ForEach(1..<4, id: \.self) { quarter in
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 1, height: 10)
                    .offset(x: width * CGFloat(quarter) / 4)
            }
            ForEach(units) { unit in
                let ready = model.awaitingActor?.id == unit.id
                let fraction = ready ? 1.0 : min(1, max(0, unit.attackBar))
                gaugeDot(unit, ready: ready)
                    .offset(x: CGFloat(fraction) * (width - dot), y: unit.side == .player ? -9 : 9)
                    .animation(.easeOut(duration: 0.35), value: fraction)
            }
        }
        .frame(width: width, height: 44)
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
            VStack(alignment: .trailing, spacing: 8) {
                if model.selectedSkillSlot != nil {
                    targetingBar
                }
                HStack(spacing: 8) {
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
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.ink.opacity(0.82))
            )
        }
    }

    private func actorPlate(_ actor: Combatant) -> some View {
        HStack(spacing: 8) {
            if BundleImage.exists(actor.model.portraitName(awakened: actor.isAwakened)) {
                BundleImage(name: actor.model.portraitName(awakened: actor.isAwakened))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(actor.element.color, lineWidth: 1.5)
                    )
                    .shadow(color: actor.element.color.opacity(0.6), radius: 5)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(actor.name)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                ElementBadge(element: actor.element, compact: true)
                StatBar(
                    value: actor.currentHealth,
                    maximum: actor.maxHealth,
                    tint: Theme.success,
                    height: 4
                )
                .frame(width: 90)
            }
        }
        .padding(8)
        .background(Theme.panel(Theme.tightCorner))
    }

    /// The skill in hand, in words, and where to aim it: a player should be
    /// able to see what they are about to do before they do it.
    private var targetingBar: some View {
        let skill = model.selectedSkillSlot.flatMap { slot in model.awaitingActor?.skill(at: slot) }
        return VStack(alignment: .leading, spacing: 5) {
            if let skill {
                Text(skill.name)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.gold)
                Text(skill.description)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(Theme.gold)
                Text("Tap a target on the field")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if model.highlightedTarget != nil {
                    Button("Confirm") { model.confirmTarget() }
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(Theme.gold)
                }
                Button("Cancel") { model.cancelTargeting() }
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 440)
        .background(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous).fill(Theme.surface))
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

    private var playbackHint: some View {
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
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.ink.opacity(0.7)))
        }
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
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isReady ? Theme.gold : Theme.textSecondary)
                    Text(skill.name)
                        .font(Theme.body(8).weight(.semibold))
                        .foregroundStyle(isReady ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .padding(4)

                if !isReady {
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                    Text("\(cooldown)")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: 62, height: 62)
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

            VStack(spacing: 12) {
                Text(headline)
                    .font(Theme.display(38))
                    .foregroundStyle(summary.outcome == .victory ? Theme.gold : Theme.danger)

                if summary.outcome == .victory, summary.stars > 0 {
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { index in
                            Image(systemName: index <= summary.stars ? "star.fill" : "star")
                                .font(.system(size: 26))
                                .foregroundStyle(index <= summary.stars ? Theme.gold : Theme.stroke)
                        }
                    }
                }

                if summary.lines.isEmpty {
                    Text("No rewards this time.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(spacing: 9) {
                        ForEach(summary.lines) { line in
                            HStack {
                                Image(systemName: line.icon)
                                    .frame(width: 22)
                                    .foregroundStyle(Theme.goldDim)
                                Text(line.label)
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(line.value)
                                    .font(Theme.numeric(13))
                                    .foregroundStyle(Theme.success)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.panel())
                }

                PrimaryButton(title: "Continue", action: onDismiss)
            }
            .padding(24)
            .frame(maxWidth: 380)
        }
    }

    private var headline: String {
        switch summary.outcome {
        case .victory: return "VICTORY"
        case .defeat: return "DEFEAT"
        case .draw: return "DRAW"
        }
    }
}
