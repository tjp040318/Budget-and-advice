import SwiftUI

/// PvE: the campaign as a map. The tab opens straight onto the chapter the
/// player is in — one slim strip of chrome, a rail of chapters, the chapter's
/// road and medallions below — so a stage is one tap from the island, the way
/// the genre lays it out. The realms overview opens as a sheet for the story of
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

    /// The realm the map is standing in, for the strip's second line.
    private var realmSubtitle: String? {
        StageDatabase.chapter(currentChapterID)?.realmName
    }

    private var clearedStages: Int {
        StageDatabase.chapters.reduce(0) { $0 + (store.player.campaignProgress[$1.id] ?? 0) }
    }

    private var totalStages: Int {
        StageDatabase.chapters.reduce(0) { $0 + $1.stages.count }
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
            GameScreen("Campaign", subtitle: realmSubtitle) {
                BarButton(title: "Realms", systemImage: "globe.europe.africa.fill") {
                    showRealms = true
                }
                BarWallet(wallet: store.player.wallet)
            } content: {
                VStack(spacing: 0) {
                    chapterStrip
                    ScrollView {
                        ChapterMapView(chapterID: currentChapterID) { stage in
                            selectedStage = stage
                        }
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 8)
                    }
                }
            }
            .sheet(isPresented: $showRealms) {
                NavigationStack {
                    GameScreen(
                        "The Realms",
                        subtitle: "The gates, and what shuts them",
                        dismiss: { showRealms = false }
                    ) {
                        BarCount(value: "\(clearedStages)/\(totalStages)", systemImage: "flag.checkered")
                    } content: {
                        ScrollView {
                            WorldMapView { chapter in
                                chapterID = chapter.id
                                showRealms = false
                            }
                            .padding(.horizontal, ScreenChrome.contentPadding)
                            .padding(.vertical, 8)
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
    /// It is a selector, not a filter, so it stays in the content — but at
    /// 28 points, a rail under the strip rather than a second bar.
    ///
    /// Eight chapters at full name are wider than the frame, so the rail
    /// scrolls itself to the chapter the player is in: without that, a player
    /// deep in Yggdrasil opened Campaign with no gold chip on screen and a map
    /// below that belonged to a chapter he could not see.
    private var chapterStrip: some View {
        let player = store.player
        let current = currentChapterID
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
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
                            HStack(spacing: 4) {
                                Image(systemName: unlocked ? (finished ? "checkmark" : "map.fill") : "lock.fill")
                                    .font(.system(size: 8, weight: .black))
                                Text(chapter.name)
                                    .font(Theme.body(10).weight(.semibold))
                                    .lineLimit(1)
                                Text("\(cleared)/\(chapter.stages.count)")
                                    .font(Theme.numeric(8))
                            }
                            .foregroundStyle(selected ? Theme.ink : (unlocked ? Theme.textPrimary : Theme.textSecondary))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(selected ? Theme.gold : Theme.surface.opacity(unlocked ? 1 : 0.5)))
                            .overlay(
                                Capsule().strokeBorder(
                                    selected ? Theme.gold : chapter.pantheon.color.opacity(unlocked ? 0.7 : 0.3),
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .id(chapter.id)
                    }
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 4)
            }
            .background(Theme.ink.opacity(0.6))
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
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
///
/// One landscape screen, no scroll: the opposition on the left, the rewards
/// and the team on the right, the runs and the Begin button along the bottom,
/// and the stage's own painting behind all of it so the briefing is a place
/// before it is a list.
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
    private var waveCount: Int { 1 + stage.laterWaves.count }
    private var hasEnergy: Bool { store.player.wallet.energy >= stage.energyCost }
    private var teamPower: Int { team.reduce(0) { $0 + $1.power } }
    private var meetsRecommended: Bool { teamPower >= stage.recommendedPower }

    /// Your team's power against the stage's, in the strip. The map tints
    /// exactly this comparison green or red and the briefing — the screen where
    /// the energy is actually spent — had nothing to compare its "Power 1420"
    /// against. The strip is the one place on the screen that can carry it
    /// without taking a point of height from the panels below.
    private var powerChip: some View {
        HStack(spacing: 4) {
            Image(systemName: meetsRecommended ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .black))
            Text("\(teamPower) / \(stage.recommendedPower)")
                .font(Theme.numeric(11))
        }
        .foregroundStyle(meetsRecommended ? Theme.success : Theme.danger)
        .padding(.horizontal, 8)
        .frame(height: ScreenChrome.control)
        .background(ScreenChrome.controlShape.fill(Theme.surface.opacity(0.8)))
        .overlay(
            ScreenChrome.controlShape.strokeBorder(
                (meetsRecommended ? Theme.success : Theme.danger).opacity(0.55),
                lineWidth: 0.5
            )
        )
    }

    /// The enemy cards shrink as the waves multiply: a campaign stage is one
    /// wave of big cards, a dungeon level three waves of small ones, and
    /// either way the whole briefing fits the frame without a scroll.
    ///
    /// A card is its size plus about 32 points of name and level. The
    /// opposition is the subject of the screen and it holds the wide half of
    /// the frame — about 500 points of it against the right column's 280 — so
    /// a single wave is drawn as large as its own height allows: four cards at
    /// 92 use 386 of the width and 154 of the roughly 270 points a panel gets,
    /// and a stage that fields two use 106. At 70 they were thumbnails in the
    /// corner of the biggest panel.
    ///
    /// The tight case is the other end: the three-wave dungeon level on the
    /// shortest landscape phone (375 points, so 341 under the strip). Three
    /// rows of 42, 8 of spacing and 35 of panel is 253, and the launch bar,
    /// the spacing and the padding are 79 more — 332, with nine points in
    /// hand. At 44 and a 6-point gap that came to 342 and the cards met the
    /// launch bar, and nothing in the CI tour photographs this screen to
    /// catch it.
    private var enemyCardSize: CGFloat {
        switch waveCount {
        case 1: return stage.enemies.count <= 2 ? 106 : 92
        case 2: return 68
        default: return 42
        }
    }

    var body: some View {
        NavigationStack {
            GameScreen(
                stage.name,
                subtitle: stage.environment.displayName,
                dismiss: { dismiss() }
            ) {
                BarCount(
                    value: "Cost \(stage.energyCost)",
                    systemImage: "bolt.fill",
                    tint: hasEnergy ? Theme.info : Theme.danger
                )
                powerChip
                BarWallet(wallet: store.player.wallet, shows: [.energy])
            } content: {
                briefing
            }
            .sheet(isPresented: $showTeamPicker) {
                TeamPickerView(slot: .campaign, maxSize: 5)
                    .environmentObject(store)
            }
        }
    }

    // MARK: - The one screen

    private var briefing: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                oppositionPanel
                VStack(spacing: 8) {
                    rewardsPanel
                    teamPanel
                }
                .frame(width: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            launchBar
        }
        .padding(.horizontal, ScreenChrome.contentPadding)
        .padding(.vertical, 8)
        .background(alignment: .center) { backdrop }
    }

    /// The stage's painting, dimmed, behind the panels. Decorative only —
    /// `.clipped()` does not clip hit testing, so it must never take a tap.
    @ViewBuilder
    private var backdrop: some View {
        if BundleImage.exists(stage.environment.backdropName) {
            BundleImage(name: stage.environment.backdropName)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [Theme.ink.opacity(0.72), Theme.ink.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
    }

    private var oppositionPanel: some View {
        SectionPanel(
            title: "Opposition",
            accessory: waveCount > 1 ? "\(waveCount) waves, the boss last" : "\(waves.first?.count ?? 0) units"
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(waves.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        if waveCount > 1 {
                            Text(index == waveCount - 1 ? "BOSS" : "W\(index + 1)")
                                .font(Theme.body(9).weight(.black))
                                .foregroundStyle(index == waveCount - 1 ? Theme.danger : Theme.textSecondary)
                                .frame(width: 30, alignment: .leading)
                        }
                        ForEach(waves[index]) { enemy in
                            UnitCard(unit: enemy, showPower: false, size: enemyCardSize)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rewardsPanel: some View {
        SectionPanel(title: "Rewards", accessory: nil) {
            VStack(spacing: 3) {
                rewardRow("circle.hexagongrid.fill", "Drachma", "\(stage.rewards.drachma)")
                rewardRow("arrow.up.circle.fill", "Unit EXP", "\(stage.rewards.unitExperience)")
                if stage.rewards.relicChance > 0 {
                    rewardRow(
                        "shield.lefthalf.filled",
                        "Relic (\(stage.rewards.relicGrade)★)",
                        stage.rewards.relicChance >= 1 ? "always" : "\(Int(stage.rewards.relicChance * 100))%"
                    )
                    // The sets the run can drop, drawn the way the Labyrinth
                    // draws them two taps away: a chip with the set's glyph
                    // reads as a set, where six names joined by dots read as a
                    // sentence and wrapped to two lines of run-on gold.
                    if let sets = stage.rewards.relicSets, !sets.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 56, maximum: 90), spacing: 4)],
                            spacing: 4
                        ) {
                            ForEach(sets) { relicSet in
                                HStack(spacing: 3) {
                                    Image(systemName: relicSet.glyph)
                                        .font(.system(size: 8, weight: .bold))
                                    Text(relicSet.displayName)
                                        .font(Theme.body(9).weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(Theme.surfaceHigh))
                            }
                        }
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
        }
    }

    private func rewardRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 16)
                .foregroundStyle(Theme.goldDim)
            Text(label).font(Theme.body(11)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 4)
            Text(value).font(Theme.numeric(11)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var teamPanel: some View {
        SectionPanel(title: "Your team", accessory: "Power \(teamPower) / \(stage.recommendedPower)") {
            Button {
                showTeamPicker = true
            } label: {
                HStack(spacing: 6) {
                    ForEach(team) { unit in
                        UnitCard(unit: unit, size: 46)
                    }
                    if team.count < 5 {
                        EmptyTeamSlot(size: 46, label: "Add")
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Once, or a run of the same stage on auto: the loot is totted up at
    /// the end, and the run stops on a loss or when the energy is gone.
    private var launchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Text("RUNS")
                    .font(Theme.body(9).weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(Self.runChoices, id: \.self) { count in
                    Button {
                        runs = count
                    } label: {
                        Text(count == 1 ? "Once" : "×\(count)")
                            .font(Theme.body(11).weight(.bold))
                            .foregroundStyle(runs == count ? Theme.ink : Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(runs == count ? Theme.gold : Theme.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !hasEnergy {
                Text("Not enough energy — this stage costs \(stage.energyCost).")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            } else if runs > 1 {
                Text("On auto until the runs are done, a run is lost, or the energy runs out.")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            PrimaryButton(
                title: runs > 1
                    ? "Begin ×\(runs) — \(stage.energyCost) energy each"
                    : "Begin — \(stage.energyCost) energy",
                systemImage: runs > 1 ? "repeat" : "play.fill",
                isEnabled: hasEnergy && !team.isEmpty
            ) {
                onStart(runs)
            }
            .frame(width: 260)
        }
        .padding(8)
        .background(Theme.panel(Theme.tightCorner))
    }
}
