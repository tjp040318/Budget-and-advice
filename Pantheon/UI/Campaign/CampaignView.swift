import SwiftUI

/// PvE: chapters, stages and the run-in to a battle.
struct CampaignView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedStage: Stage?
    @State private var battle: BattleContext?
    @State private var mode: Mode
    @State private var path = NavigationPath()

    /// The two kinds of PvE: the story chapters, and the Halls of Essence
    /// that are run over and over for essences and relics.
    enum Mode: String, CaseIterable, Identifiable {
        case chapters = "Chapters"
        case halls = "Halls of Essence"
        var id: String { rawValue }
    }

    init(mode: Mode = .chapters) {
        _mode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { candidate in
                            Text(candidate.rawValue).tag(candidate)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .chapters:
                        // The realms and their chapters; a chapter opens as
                        // a map of its stages.
                        WorldMapView { chapter in
                            path.append(chapter.id)
                        }
                    case .halls:
                        ForEach(DungeonDatabase.halls) { hall in
                            hallSection(hall)
                        }
                    }
                }
                .padding(16)
            }
            .screen(mode == .chapters ? "Campaign" : "Halls of Essence")
            .navigationDestination(for: String.self) { chapterID in
                ChapterMapView(chapterID: chapterID) { stage in
                    selectedStage = stage
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WalletBar(wallet: store.player.wallet)
                }
            }
            .sheet(item: $selectedStage) { stage in
                StageBriefingView(stage: stage) { runs in
                    selectedStage = nil
                    launch(stage, runs: runs)
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
            BattleView(model: BattleViewModel(
                engine: engine, context: context, store: store, repeatCount: pendingRuns[stage.id] ?? 1
            ))
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
    /// How many times the briefing asked the stage to be run on auto.
    @State private var pendingRuns: [String: Int] = [:]

    private func launch(_ stage: Stage, runs: Int) {
        guard let engine = store.startCampaignBattle(stage: stage) else { return }
        pendingEngines[stage.id] = engine
        pendingRuns[stage.id] = runs
        battle = .campaign(stage)
    }

    // MARK: - Halls

    /// A hall reads like a chapter — its painting, its name, its floors —
    /// with the element it pays out in and a note that every clear pays.
    private func hallSection(_ hall: DungeonDatabase.Hall) -> some View {
        let cleared = store.player.campaignProgress[hall.id] ?? 0
        let essence = EssenceCatalog.name(for: "essence_\(hall.element.rawValue)_mid")
        return VStack(alignment: .leading, spacing: 10) {
            if BundleImage.exists("\(hall.environment.sceneName)_bg") {
                BundleImage(name: "\(hall.environment.sceneName)_bg")
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                    .overlay(
                        LinearGradient(colors: [.clear, Theme.surface.opacity(0.15), Theme.surface],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
                    .padding(.bottom, -4)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        ElementBadge(element: hall.element, compact: true)
                        Text("HALL OF ESSENCE")
                            .font(Theme.body(10).weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(hall.element.color)
                    }
                    Text(hall.name)
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text("B\(cleared)/\(hall.floors.count)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(hall.summary)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Drops \(essence) and relics up to \(hall.floors.last?.rewards.relicGrade ?? 6)★. Every clear pays; the next floor opens when this one falls.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            StatBar(
                value: Double(cleared),
                maximum: Double(hall.floors.count),
                tint: hall.element.color,
                height: 5
            )

            VStack(spacing: 8) {
                ForEach(hall.floors) { floor in
                    stageRow(floor)
                }
            }
        }
        .padding(14)
        .panelBackground()
    }

    // MARK: - Stage rows

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
    /// Called with how many runs to fight on auto (1 is one fight by hand).
    let onStart: (Int) -> Void

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var showTeamPicker = false
    @State private var runs = 1

    private static let runChoices = [1, 5, 10, 20]

    private var team: [ResolvedUnit] { store.team(store.player.campaignTeam) }
    private var enemies: [ResolvedUnit] { StageDatabase.buildEnemies(for: stage) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // The stage's own painting, so the briefing is a place before
                    // it is a list.
                    if BundleImage.exists("\(stage.environment.sceneName)_bg") {
                        BundleImage(name: "\(stage.environment.sceneName)_bg")
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .allowsHitTesting(false)
                            .overlay(
                                LinearGradient(colors: [.clear, Theme.ink.opacity(0.85)],
                                               startPoint: .center, endPoint: .bottom)
                            )
                            .overlay(alignment: .bottomLeading) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stage.environment.displayName.uppercased())
                                        .font(Theme.body(10).weight(.bold))
                                        .tracking(1.4)
                                        .foregroundStyle(Theme.textSecondary)
                                    Text(stage.name)
                                        .font(Theme.title(20))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                .padding(12)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    }

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

                    SectionHeader(title: "Repeat", accessory: runs > 1 ? "×\(runs) on auto" : "Once")
                    repeatRow
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
                        title: runs > 1
                            ? "Begin ×\(runs) — \(stage.energyCost) energy each"
                            : "Begin — \(stage.energyCost) energy",
                        systemImage: runs > 1 ? "repeat" : "play.fill",
                        isEnabled: store.player.wallet.energy >= stage.energyCost && !team.isEmpty
                    ) {
                        onStart(runs)
                    }
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

    /// Once, or a run of the same stage on auto: the loot is totted up at
    /// the end, and the run stops on a loss or when the energy is gone.
    private var repeatRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Self.runChoices, id: \.self) { count in
                    Button {
                        runs = count
                    } label: {
                        Text(count == 1 ? "Once" : "×\(count)")
                            .font(Theme.body(12).weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(runs == count ? Theme.gold : Theme.surfaceRaised))
                            .foregroundStyle(runs == count ? Theme.ink : Theme.textSecondary)
                    }
                }
                Spacer()
            }
            if runs > 1 {
                Text("Fights on auto until the runs are done, a run is lost, or the energy runs out. The loot is added up at the end.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            ForEach(stage.rewards.essenceChances.keys.sorted(), id: \.self) { id in
                if let chance = stage.rewards.essenceChances[id], chance > 0 {
                    rewardRow("drop.triangle.fill", EssenceCatalog.name(for: id), "\(Int(chance * 100))%")
                }
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
