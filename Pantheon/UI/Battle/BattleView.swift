import SwiftUI

/// The battle screen: 3D stage underneath, HUD on top.
struct BattleView: View {

    @StateObject var model: BattleViewModel
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var showForfeitConfirm = false
    @State private var showLog = false
    @State private var summary: BattleSummary?

    var body: some View {
        ZStack {
            BattleSceneView(controller: model.sceneController) { id in
                model.tapUnit(id)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                turnOrderStrip
                Spacer()
                if let actor = model.awaitingActor {
                    commandPanel(actor: actor)
                } else if model.isPlayingBack {
                    playbackHint
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            if showLog { logOverlay }

            if let summary {
                BattleResultView(summary: summary) { dismiss() }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.begin() }
        .onChange(of: model.outcome?.outcome) { _, newValue in
            guard newValue != nil else { return }
            // Let the last animation land before the result panel takes over.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.35)) {
                    summary = model.finish()
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

    // MARK: - Turn order

    private var turnOrderStrip: some View {
        HStack(spacing: 6) {
            Text("NEXT")
                .font(Theme.body(9).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)

            let preview = Array(model.turnOrderPreview.prefix(6))
            ForEach(preview.indices, id: \.self) { index in
                let combatant = preview[index]
                ZStack {
                    Circle()
                        .fill(combatant.side == .player ? Theme.info.opacity(0.3) : Theme.danger.opacity(0.3))
                    Circle()
                        .strokeBorder(
                            combatant.element.color,
                            lineWidth: index == 0 ? 2 : 1
                        )
                    Text(String(combatant.name.prefix(1)))
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: index == 0 ? 30 : 24, height: index == 0 ? 30 : 24)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.ink.opacity(0.55)))
        .padding(.top, 8)
    }

    // MARK: - Command panel

    private func commandPanel(actor: Combatant) -> some View {
        VStack(spacing: 8) {
            if model.selectedSkillSlot != nil {
                targetingBar
            }

            HStack(spacing: 10) {
                // Actor plate
                VStack(spacing: 3) {
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
                    .frame(width: 74)
                }
                .frame(width: 86)
                .padding(8)
                .background(Theme.panel(Theme.tightCorner))

                // Skills
                HStack(spacing: 8) {
                    ForEach(model.availableSkills) { option in
                        SkillButton(
                            skill: option.skill,
                            cooldown: option.cooldown,
                            isSelected: model.selectedSkillSlot == option.slot
                        ) {
                            model.selectSkill(option.slot)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.ink.opacity(0.82))
        )
    }

    private var targetingBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .foregroundStyle(Theme.gold)
            Text("Tap a target on the field")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.surface))
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
                .frame(maxHeight: 220)
                .background(Theme.panel())
                .onChange(of: model.log.count) { _, count in
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 150)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// One skill in the command bar.
struct SkillButton: View {
    let skill: Skill
    let cooldown: Int
    let isSelected: Bool
    let action: () -> Void

    private var isReady: Bool { cooldown <= 0 }

    var body: some View {
        Button(action: action) {
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
            .frame(width: 66, height: 66)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(isSelected ? Theme.gold : Theme.stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .disabled(!isReady)
    }

    /// A glyph per skill shape, so the bar is readable without art.
    private var glyph: String {
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

            VStack(spacing: 18) {
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
                    .padding(14)
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
