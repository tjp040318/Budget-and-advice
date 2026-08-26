import SwiftUI

/// PvE: chapters, stages and the run-in to a battle.
struct CampaignView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedStage: Stage?
    @State private var battle: BattleContext?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(StageDatabase.chapters) { chapter in
                        chapterSection(chapter)
                    }
                }
                .padding(16)
            }
            .screen("Campaign")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WalletBar(wallet: store.player.wallet)
                }
            }
            .sheet(item: $selectedStage) { stage in
                StageBriefingView(stage: stage) {
                    selectedStage = nil
                    launch(stage)
                }
            }
            .fullScreenCover(item: $battle) { context in
                battleScreen(for: context)
            }
        }
    }

    @ViewBuilder
    private func battleScreen(for context: BattleContext) -> some View {
        if case .campaign(let stage) = context, let engine = pendingEngines[stage.id] {
            BattleView(model: BattleViewModel(engine: engine, context: context, store: store))
                .environmentObject(store)
        } else {
            // Engine could not be created (energy, lock). Bail out cleanly.
            Color.black
                .ignoresSafeArea()
                .onAppear { battle = nil }
        }
    }

    /// Engines are built before presentation so that a failure (no energy, stage
    /// locked) surfaces as an error rather than as an empty battle screen.
    @State private var pendingEngines: [String: BattleEngine] = [:]

    private func launch(_ stage: Stage) {
        guard let engine = store.startCampaignBattle(stage: stage) else { return }
        pendingEngines[stage.id] = engine
        battle = .campaign(stage)
    }

    // MARK: - Chapter

    private func chapterSection(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.realmName.uppercased())
                        .font(Theme.body(10).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(chapter.pantheon.color)
                    Text(chapter.name)
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                let cleared = store.player.campaignProgress[chapter.id] ?? 0
                Text("\(cleared)/\(chapter.stages.count)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(chapter.summary)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            StatBar(
                value: Double(store.player.campaignProgress[chapter.id] ?? 0),
                maximum: Double(chapter.stages.count),
                tint: chapter.pantheon.color,
                height: 5
            )

            VStack(spacing: 8) {
                ForEach(chapter.stages) { stage in
                    stageRow(stage)
                }
            }
        }
        .padding(14)
        .panelBackground()
    }

    private func stageRow(_ stage: Stage) -> some View {
        let unlocked = CampaignService.isUnlocked(stage, player: store.player)
        let cleared = CampaignService.isCleared(stage, player: store.player)
        let power = store.totalPower

        return Button {
            guard unlocked else { return }
            selectedStage = stage
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(cleared ? Theme.gold.opacity(0.2) : Theme.surface)
                    if unlocked {
                        Text("\(stage.index)")
                            .font(Theme.numeric(14).weight(.bold))
                            .foregroundStyle(cleared ? Theme.gold : Theme.textPrimary)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(stage.name)
                            .font(Theme.body(14).weight(.semibold))
                            .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textSecondary)
                        if stage.isBoss {
                            Text("BOSS")
                                .font(Theme.body(8).weight(.black))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.danger.opacity(0.25)))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                    HStack(spacing: 8) {
                        Label("\(stage.energyCost)", systemImage: "bolt.fill")
                            .font(Theme.numeric(10))
                            .foregroundStyle(Theme.info)
                        Text("Power \(stage.recommendedPower)")
                            .font(Theme.numeric(10))
                            .foregroundStyle(power >= stage.recommendedPower ? Theme.success : Theme.danger)
                    }
                }

                Spacer()

                if cleared {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.gold)
                } else if unlocked {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.surface.opacity(unlocked ? 1 : 0.4))
            )
        }
        .disabled(!unlocked)
    }
}

/// Pre-battle screen: what you are about to fight, and who you are taking.
struct StageBriefingView: View {
    let stage: Stage
    let onStart: () -> Void

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var showTeamPicker = false

    private var team: [ResolvedUnit] { store.team(store.player.campaignTeam) }
    private var enemies: [ResolvedUnit] { StageDatabase.buildEnemies(for: stage) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(title: "Opposition", accessory: "\(enemies.count) units")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(enemies) { enemy in
                            UnitCard(unit: enemy, showPower: false, size: 66)
                        }
                    }

                    SectionHeader(title: "Rewards")
                    rewardsPanel

                    SectionHeader(title: "Your team", accessory: "Power \(team.reduce(0) { $0 + $1.power })")
                    teamRow
                }
                .padding(16)
            }
            .screen(stage.name)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if store.player.wallet.energy < stage.energyCost {
                        Text("Not enough energy — this stage costs \(stage.energyCost).")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.danger)
                    }
                    PrimaryButton(
                        title: "Begin — \(stage.energyCost) energy",
                        systemImage: "play.fill",
                        isEnabled: store.player.wallet.energy >= stage.energyCost && !team.isEmpty,
                        action: onStart
                    )
                }
                .padding(16)
                .background(Theme.ink)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showTeamPicker) {
                TeamPickerView(slot: .campaign, maxSize: 5)
                    .environmentObject(store)
            }
        }
    }

    private var rewardsPanel: some View {
        VStack(spacing: 7) {
            rewardRow("circle.hexagongrid.fill", "Drachma", "\(stage.rewards.drachma)")
            rewardRow("arrow.up.circle.fill", "Unit EXP", "\(stage.rewards.unitExperience)")
            if stage.rewards.relicChance > 0 {
                rewardRow(
                    "shield.lefthalf.filled",
                    "Relic (\(stage.rewards.relicGrade)★)",
                    "\(Int(stage.rewards.relicChance * 100))%"
                )
            }
            if !CampaignService.isCleared(stage, player: store.player), stage.rewards.firstClearDivinity > 0 {
                rewardRow("sparkles", "First clear", "\(stage.rewards.firstClearDivinity) divinity")
            }
        }
        .padding(12)
        .panelBackground()
    }

    private func rewardRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 20).foregroundStyle(Theme.goldDim)
            Text(label).font(Theme.body(13)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value).font(Theme.numeric(13)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var teamRow: some View {
        Button {
            showTeamPicker = true
        } label: {
            HStack(spacing: 8) {
                ForEach(team) { unit in
                    UnitCard(unit: unit, size: 66)
                }
                if team.count < 5 {
                    EmptyTeamSlot(size: 66, label: "Add")
                }
                Spacer()
            }
        }
    }
}
