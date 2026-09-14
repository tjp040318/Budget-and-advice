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
    /// The chapter whose road of stages is open. nil means the world map,
    /// which is where the tab starts.
    @State private var openChapterID: String?
    @State private var showRealms = false
    /// The tier of the open chapter being shown: Normal, Hard or Hell.
    @State private var difficulty: CampaignDifficulty = .normal

    /// The stage whose card is open over the map.
    @State private var popupStage: Stage?

    /// The world by default; the tour asks for a chapter so the road and
    /// the tier chips are photographed, and for a stage so its card is.
    init(openingChapter: String? = nil, openingStage: String? = nil) {
        _openChapterID = State(initialValue: openingChapter)
        _chapterID = State(initialValue: openingChapter)
        _popupStage = State(initialValue: openingStage.flatMap { StageDatabase.stage($0) })
    }

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
            GameScreen(
                openChapterID == nil ? "The World" : "Campaign",
                subtitle: openChapterID == nil ? "Three realms, and the road between them" : realmSubtitle,
                dismiss: openChapterID == nil ? nil : { openChapterID = nil }
            ) {
                if openChapterID != nil {
                    BarButton(title: "World", systemImage: "map.fill") {
                        openChapterID = nil
                    }
                }
                BarButton(title: "Realms", systemImage: "globe.europe.africa.fill") {
                    showRealms = true
                }
                BarWallet(wallet: store.player.wallet)
            } content: {
                // The campaign opens on the world, not on a menu: one painted
                // map of Egypt, Greece and the north with a city per chapter,
                // and the chapter's own road of stages one tap in.
                if let openChapterID {
                    // The chapter is a place, not a form: the painting fills
                    // the frame, the stages stand on it, and a tap opens the
                    // stage's card over the map.
                    ChapterMapView(
                        chapterID: openChapterID,
                        difficulty: $difficulty,
                        onSelect: { stage in
                            Juice.haptic(.light)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { popupStage = stage }
                        },
                        onChapter: { id in
                            withAnimation(.easeOut(duration: 0.25)) {
                                chapterID = id
                                self.openChapterID = id
                            }
                        }
                    )
                } else {
                    WorldRoadMapView { chapter in
                        chapterID = chapter.id
                        openChapterID = chapter.id
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
            .overlay {
                if let stage = popupStage, let chapter = StageDatabase.chapter(stage.chapterID) {
                    StagePopup(
                        stage: stage, chapter: chapter,
                        onPrepare: {
                            popupStage = nil
                            selectedStage = stage
                        },
                        onFight: {
                            popupStage = nil
                            launch(stage, runs: 1)
                        },
                        onClose: {
                            withAnimation(.easeOut(duration: 0.2)) { popupStage = nil }
                        }
                    )
                    .transition(.opacity)
                }
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
            Theme.surface
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

    /// The gap between two cards in a wave row, in one place because
    /// `enemyCardSize` has to do arithmetic with it.
    private static let enemyCardGap: CGFloat = 6

    /// What the opposition panel has inside it on the narrowest landscape
    /// iPhone the deployment target still allows — an SE at 667 points, which
    /// has no landscape safe-area inset: 667 less 20 of content padding, 8
    /// between the two columns, the right column's fixed 280 and the panel's
    /// own 16. A row that fits this fits every wider phone.
    private static let narrowOppositionWidth: CGFloat = 343

    /// The enemy cards shrink as the waves multiply: a campaign stage is one
    /// wave of big cards, a dungeon level three waves of small ones, and
    /// either way the whole briefing fits the frame without a scroll.
    ///
    /// A card is its size plus about 32 points of name and level. The
    /// opposition is the subject of the screen and it holds the wide half of
    /// the frame — about 500 points of it on a modern phone against the right
    /// column's 280 — so a single wave is drawn as large as it can be, 106 for
    /// the two-enemy stages that open a chapter and 92 for the rest. At 70
    /// they were thumbnails in the corner of the biggest panel.
    ///
    /// Those two are ceilings, not the answer: the width is the binding
    /// constraint, not the height, and it is the *narrow* phone that binds it.
    /// Four cards at 92 want 386 points and an SE's panel has 343, and a
    /// `UnitCard` is a fixed frame, so the fourth would have drawn outside the
    /// panel rather than shrinking. Dividing the narrow width instead lands
    /// four at 81 and three at 92, and 81 + 32 of name is 113 against the
    /// roughly 265 points a panel band gets there.
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
        case 1:
            // `stage.enemies` is the stored array, not `waves.first`: reading
            // `waves` here would re-run `buildEnemies` once per card.
            let count = max(1, stage.enemies.count)
            let ideal: CGFloat = count <= 2 ? 106 : 92
            let widest = (Self.narrowOppositionWidth - CGFloat(count - 1) * Self.enemyCardGap)
                / CGFloat(count)
            return min(ideal, widest)
        case 2: return 68
        default: return 42
        }
    }

    /// Every model this fight will put on the stage: the team, the first
    /// wave and every later one, loaded into the model cache while the
    /// briefing is read so Begin is not followed by a second of parsing.
    private func warmModels() {
        let team = store.team(store.player.campaignTeam).map { $0.blueprint.model }
        let spawns = stage.enemies + stage.laterWaves.flatMap { $0 }
        let enemies = spawns.compactMap { UnitDatabase.blueprint($0.blueprintID)?.model }
        let crowded = ModelLibrary.detail(forCombatantCount: team.count + stage.enemies.count) == .low
        ModelLibrary.shared.warm(team + enemies, crowded: crowded)
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
        .onAppear(perform: warmModels)
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

    /// The stage's painting, washed toward cream, behind the panels.
    /// Decorative only — `.clipped()` does not clip hit testing, so it must
    /// never take a tap.
    @ViewBuilder
    private var backdrop: some View {
        if BundleImage.exists(stage.environment.backdropName) {
            BundleImage(name: stage.environment.backdropName)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [Theme.plate.opacity(0.72), Theme.plate.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
    }

    private var oppositionPanel: some View {
        // One pass of `buildEnemies` per render: `waves` resolves every spawn
        // in every wave each time it is read, and the accessory below read it
        // a second time.
        let rows = waves
        return SectionPanel(
            title: "Opposition",
            accessory: waveCount > 1 ? "\(waveCount) waves, the boss last" : "\(rows.first?.count ?? 0) units"
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: Self.enemyCardGap) {
                        if waveCount > 1 {
                            Text(index == waveCount - 1 ? "BOSS" : "W\(index + 1)")
                                .font(Theme.body(9).weight(.black))
                                .foregroundStyle(index == waveCount - 1 ? Theme.danger : Theme.textSecondary)
                                .frame(width: 30, alignment: .leading)
                        }
                        ForEach(rows[index]) { enemy in
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
                                    RelicSetEmblem(set: relicSet, size: 9)
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

/// A stage's card over the map, the genre's stage popup: the stage and its
/// place on the road, the chapter's story line, the enemies of the first
/// wave, what the stage drops — the chapter's two sets first, since every
/// relic here is one of them — the energy, your power against its power,
/// and Fight. "Team & runs" opens the full briefing for the team picker and
/// the auto runs.
struct StagePopup: View {
    let stage: Stage
    let chapter: Chapter
    let onPrepare: () -> Void
    let onFight: () -> Void
    let onClose: () -> Void

    @EnvironmentObject private var store: GameStore

    private var team: [ResolvedUnit] { store.team(store.player.campaignTeam) }
    private var teamPower: Int { team.reduce(0) { $0 + $1.power } }
    private var hasEnergy: Bool { store.player.wallet.energy >= stage.energyCost }
    private var enemies: [ResolvedUnit] { StageDatabase.buildEnemies(for: stage) }
    private var waveCount: Int { 1 + stage.laterWaves.count }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            card
                .frame(maxWidth: 660)
                .padding(.horizontal, 24)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.name)
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(chapter.realmName) · Stage \(stage.index) of \(chapter.stages.count) · \(stage.environment.displayName)")
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .black))
                    Text("\(stage.energyCost)")
                        .font(Theme.numeric(12))
                }
                .foregroundStyle(hasEnergy ? Theme.info : Theme.danger)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Theme.surfaceHigh))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.surfaceHigh))
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chapter.summary)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(waveCount > 1 ? "ENEMIES · WAVE 1 OF \(waveCount)" : "ENEMIES")
                        .font(Theme.body(9).weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(enemies.prefix(5)) { enemy in
                            UnitCard(unit: enemy, showPower: false, size: 50)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                drops
                    .frame(width: 236)
            }
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: teamPower >= stage.recommendedPower ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .black))
                    Text("Power \(teamPower) / \(stage.recommendedPower)")
                        .font(Theme.numeric(11))
                }
                .foregroundStyle(teamPower >= stage.recommendedPower ? Theme.success : Theme.danger)
                Spacer(minLength: 8)
                Button(action: onPrepare) {
                    Label("Team & runs", systemImage: "person.2.fill")
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(Theme.surfaceHigh))
                        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                PrimaryButton(
                    title: "Fight — \(stage.energyCost) energy",
                    systemImage: "play.fill",
                    isEnabled: hasEnergy && !team.isEmpty
                ) {
                    onFight()
                }
                .frame(width: 220)
            }
        }
        .padding(12)
        .panelBackground()
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }

    /// What the stage drops, the chapter's two sets first.
    private var drops: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DROPS")
                .font(Theme.body(9).weight(.black))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            if let sets = stage.rewards.relicSets, !sets.isEmpty {
                HStack(spacing: 6) {
                    ForEach(sets) { relicSet in
                        HStack(spacing: 4) {
                            RelicSetEmblem(set: relicSet, size: 18)
                            Text(relicSet.displayName)
                                .font(Theme.body(10).weight(.bold))
                                .foregroundStyle(Theme.gold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .background(Capsule().fill(Theme.surfaceHigh))
                    }
                    Spacer(minLength: 0)
                }
            }
            if stage.rewards.relicChance > 0 {
                dropRow("hexagon.fill", "\(stage.rewards.relicGrade)★ relic",
                        stage.rewards.relicChance >= 1 ? "always" : "\(Int(stage.rewards.relicChance * 100))%")
            }
            ForEach(stage.rewards.essenceChances.keys.sorted(), id: \.self) { id in
                if let chance = stage.rewards.essenceChances[id], chance > 0 {
                    dropRow("drop.triangle.fill", EssenceCatalog.name(for: id), "\(Int(chance * 100))%")
                }
            }
            ForEach(stage.rewards.scrollChances.keys.sorted(), id: \.self) { id in
                if let chance = stage.rewards.scrollChances[id], chance > 0, let scroll = ScrollType(rawValue: id) {
                    dropRow("scroll.fill", scroll.displayName, "\(Int(chance * 100))%")
                }
            }
            dropRow("circle.hexagongrid.fill", "Drachma", "\(stage.rewards.drachma)")
            if !CampaignService.isCleared(stage, player: store.player), stage.rewards.firstClearDivinity > 0 {
                dropRow("sparkles", "First clear", "\(stage.rewards.firstClearDivinity) divinity")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous).fill(Theme.surface))
    }

    private func dropRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 14)
                .foregroundStyle(Theme.goldDim)
            Text(label)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(Theme.numeric(10))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
