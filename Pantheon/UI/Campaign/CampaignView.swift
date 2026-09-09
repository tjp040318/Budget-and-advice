import SwiftUI

/// PvE: the campaign as a map. The tab opens straight onto the chapter the
/// player is in — a strip of chapters along the top, the chapter's road and
/// medallions below — so a stage is one tap from the island, the way the
/// genre lays it out. The realms overview opens as a sheet for the story of
/// what is shut and why. The Halls of Essence and the relic dungeons live in
/// the Labyrinth on the island.
struct CampaignView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedStage: Stage?
    @State private var battle: BattleContext?
    /// The chapter on the map; nil until the player picks one, which means
    /// "the chapter I am in".
    @State private var chapterID: String?
    @State private var showRealms = false

    /// Engines are built before presentation so that a failure (no energy, stage
    /// locked) surfaces as an error rather than as an empty battle screen.
    @State private var pendingEngines: [String: BattleEngine] = [:]
    /// How many times the briefing asked the stage to be run on auto.
    @State private var pendingRuns: [String: Int] = [:]

    private var currentChapterID: String {
        chapterID ?? Self.currentChapter(for: store.player).id
    }

    /// The chapter the player is in: the first with a stage open and not
    /// yet cleared, else the last one that is open at all.
    static func currentChapter(for player: Player) -> Chapter {
        let chapters = StageDatabase.chapters
        if let inProgress = chapters.first(where: { chapter in
            chapter.stages.contains {
                CampaignService.isUnlocked($0, player: player) && !CampaignService.isCleared($0, player: player)
            }
        }) {
            return inProgress
        }
        return chapters.last(where: { chapter in
            chapter.stages.first.map { CampaignService.isUnlocked($0, player: player) } ?? false
        }) ?? chapters[0]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chapterStrip
                ScrollView {
                    ChapterMapView(chapterID: currentChapterID) { stage in
                        selectedStage = stage
                    }
                    .padding(12)
                }
            }
            .screen("Campaign")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showRealms = true
                    } label: {
                        Label("Realms", systemImage: "globe.europe.africa.fill")
                            .font(Theme.body(12).weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    WalletBar(wallet: store.player.wallet)
                }
            }
            .sheet(isPresented: $showRealms) {
                NavigationStack {
                    ScrollView {
                        WorldMapView { chapter in
                            chapterID = chapter.id
                            showRealms = false
                        }
                        .padding(12)
                    }
                    .screen("The Realms")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showRealms = false }
                        }
                    }
                }
                .environmentObject(store)
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

    // MARK: - The chapter strip

    /// Every chapter as a chip in story order: gold where the player is,
    /// a check where it is finished, a lock where its gate is still shut.
    private var chapterStrip: some View {
        let player = store.player
        let current = currentChapterID
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(StageDatabase.chapters) { chapter in
                    let cleared = player.campaignProgress[chapter.id] ?? 0
                    let finished = cleared >= chapter.stages.count
                    let unlocked = chapter.stages.first.map { CampaignService.isUnlocked($0, player: player) } ?? false
                    let selected = chapter.id == current
                    Button {
                        guard unlocked else {
                            Juice.notify(.warning)
                            return
                        }
                        Juice.haptic(.light)
                        withAnimation { chapterID = chapter.id }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: unlocked ? (finished ? "checkmark" : "map.fill") : "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(chapter.name)
                                .font(Theme.body(11).weight(.semibold))
                                .lineLimit(1)
                            Text("\(cleared)/\(chapter.stages.count)")
                                .font(Theme.numeric(9))
                        }
                        .foregroundStyle(selected ? Theme.ink : (unlocked ? Theme.textPrimary : Theme.textSecondary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Theme.gold : Theme.surface.opacity(unlocked ? 1 : 0.5)))
                        .overlay(
                            Capsule().strokeBorder(
                                selected ? Theme.gold : chapter.pantheon.color.opacity(unlocked ? 0.7 : 0.3),
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.ink.opacity(0.6))
    }

    // MARK: - Fighting

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

    private func launch(_ stage: Stage, runs: Int) {
        guard let engine = store.startCampaignBattle(stage: stage) else { return }
        pendingEngines[stage.id] = engine
        pendingRuns[stage.id] = runs
        battle = .campaign(stage)
    }
}

/// Pre-battle screen: what you are about to fight, wave by wave, and who
/// you are taking.
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
    /// The first wave and every wave after it; a plain stage is one wave.
    private var waves: [[ResolvedUnit]] {
        ([stage.enemies] + stage.laterWaves).map { StageDatabase.buildEnemies(spawns: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // The stage's own painting, so the briefing is a place before
                    // it is a list.
                    if BundleImage.exists(stage.environment.backdropName) {
                        BundleImage(name: stage.environment.backdropName)
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 120)
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

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(
                                title: "Opposition",
                                accessory: waves.count > 1 ? "\(waves.count) waves, the boss last" : "\(waves.first?.count ?? 0) units"
                            )
                            ForEach(waves.indices, id: \.self) { index in
                                HStack(spacing: 6) {
                                    if waves.count > 1 {
                                        Text(index == waves.count - 1 ? "BOSS" : "W\(index + 1)")
                                            .font(Theme.body(9).weight(.black))
                                            .foregroundStyle(index == waves.count - 1 ? Theme.danger : Theme.textSecondary)
                                            .frame(width: 32, alignment: .leading)
                                    }
                                    ForEach(waves[index]) { enemy in
                                        UnitCard(unit: enemy, showPower: false, size: 58)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Rewards")
                            rewardsPanel
                        }
                        .frame(width: 280)
                    }

                    SectionHeader(title: "Your team", accessory: "Power \(team.reduce(0) { $0 + $1.power })")
                    teamRow

                    SectionHeader(title: "Repeat", accessory: runs > 1 ? "×\(runs) on auto" : "Once")
                    repeatRow
                }
                .padding(12)
            }
            .screen(stage.name)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
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
                .padding(10)
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
        VStack(spacing: 6) {
            rewardRow("circle.hexagongrid.fill", "Drachma", "\(stage.rewards.drachma)")
            rewardRow("arrow.up.circle.fill", "Unit EXP", "\(stage.rewards.unitExperience)")
            if stage.rewards.relicChance > 0 {
                rewardRow(
                    "shield.lefthalf.filled",
                    "Relic (\(stage.rewards.relicGrade)★)",
                    stage.rewards.relicChance >= 1 ? "always" : "\(Int(stage.rewards.relicChance * 100))%"
                )
                if let sets = stage.rewards.relicSets, !sets.isEmpty {
                    Text(sets.map(\.displayName).joined(separator: " · "))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(stage.rewards.essenceChances.keys.sorted(), id: \.self) { id in
                if let chance = stage.rewards.essenceChances[id], chance > 0 {
                    rewardRow("drop.triangle.fill", EssenceCatalog.name(for: id), "\(Int(chance * 100))%")
                }
            }
            ForEach(stage.rewards.scrollChances.keys.sorted(), id: \.self) { id in
                if let chance = stage.rewards.scrollChances[id], chance > 0, let scroll = ScrollType(rawValue: id) {
                    rewardRow("scroll.fill", scroll.displayName, "\(Int(chance * 100))%")
                }
            }
            if !CampaignService.isCleared(stage, player: store.player), stage.rewards.firstClearDivinity > 0 {
                rewardRow("sparkles", "First clear", "\(stage.rewards.firstClearDivinity) divinity")
            }
        }
        .padding(10)
        .panelBackground()
    }

    private func rewardRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 20).foregroundStyle(Theme.goldDim)
            Text(label).font(Theme.body(12)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value).font(Theme.numeric(12)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var teamRow: some View {
        Button {
            showTeamPicker = true
        } label: {
            HStack(spacing: 8) {
                ForEach(team) { unit in
                    UnitCard(unit: unit, size: 62)
                }
                if team.count < 5 {
                    EmptyTeamSlot(size: 62, label: "Add")
                }
                Spacer()
            }
        }
    }
}
