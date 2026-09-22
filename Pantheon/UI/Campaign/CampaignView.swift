import SwiftUI

/// PvE: the campaign as a map. The tab opens on the painted world with a
/// city per chapter; a city opens the chapter as a place — its own painted
/// map, the stages standing on it, its name carved in the strip and its
/// tiers beside it — so a stage is one tap from the island, the way the
/// genre lays it out. The realms overview opens as a sheet for the story of
/// what is shut and why. The Halls of Essence and the relic dungeons live in
/// the Labyrinth on the island.
struct CampaignView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selectedStage: Stage?
    @State private var battle: BattleContext?
    /// The chapter whose road of stages is open. nil means the world map,
    /// which is where the tab starts.
    @State private var openChapterID: String?
    @State private var showRealms = false
    /// The tier of the open chapter being shown: Normal, Hard or Hell.
    @State private var difficulty: CampaignDifficulty

    /// The stage whose card is open over the map.
    @State private var popupStage: Stage?

    /// Whether the chapter's scroll opens with the map (the tour's
    /// `-tour-chapter-scroll`); a player opens it from the tab.
    private let openingScroll: Bool
    /// The tour's walked copy of the player (2026-09-22, phase B): eleven of
    /// the twelve chapter-map frames of run 211 showed a chapter no player
    /// can open — every medallion locked — because the tour's save has only
    /// the Duat walked, so they judged nothing but the lock. The tour passes
    /// `tourWalk(_:chapterIndex:tier:)`'s copy, which is read by the map,
    /// the tiers and the popup and NEVER saved (the tour's save persists
    /// between launches; runs 158 and 159). nil everywhere else.
    private let previewPlayer: Player?

    /// The world by default; the tour asks for a chapter so the road and
    /// the tier well are photographed, for a stage so its card is, for a
    /// tier and the open scroll so Hell's grade and terms are.
    init(
        openingChapter: String? = nil,
        openingStage: String? = nil,
        openingDifficulty: CampaignDifficulty = .normal,
        openingScroll: Bool = false,
        previewPlayer: Player? = nil
    ) {
        _openChapterID = State(initialValue: openingChapter)
        _popupStage = State(initialValue: openingStage.flatMap { StageDatabase.stage($0) })
        _difficulty = State(initialValue: openingDifficulty)
        self.openingScroll = openingScroll || openingDifficulty != .normal
        self.previewPlayer = previewPlayer
    }

    /// Engines are built before presentation so that a failure (no energy, stage
    /// locked) surfaces as an error rather than as an empty battle screen.
    @State private var pendingEngines: [String: BattleEngine] = [:]
    /// How many times the briefing asked the stage to be run on auto.
    @State private var pendingRuns: [String: Int] = [:]
    /// The haul of the last sweep, shown over the map until it is dismissed.
    @State private var sweepReceipt: SweepReceipt?

    private var player: Player { previewPlayer ?? store.player }

    /// The open chapter at the tier shown, or nil on the world.
    private var openChapter: Chapter? {
        openChapterID.flatMap { StageDatabase.chapter($0)?.at(difficulty) }
    }

    private var clearedStages: Int {
        StageDatabase.chapters.reduce(0) { $0 + (player.campaignProgress[$1.id] ?? 0) }
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

    /// The strip's second line on a chapter: where it is on the road, the
    /// tier when it is not Normal, and how far it is walked — "The Duat ·
    /// Chapter 1 · 3/5". The progress is here as well as on the map's tab,
    /// because on the most crowded maps the tab is the two stones alone.
    private func chapterSubtitle(_ chapter: Chapter) -> String {
        let count = chapter.stages.count
        let cleared = min(count, player.campaignProgress[chapter.id] ?? 0)
        var parts = ["\(chapter.realmName) · Chapter \(StageDatabase.chapterOrder(of: chapter.id))"]
        if difficulty != .normal { parts.append(difficulty.displayName) }
        parts.append("\(cleared)/\(count)")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            GameScreen(
                // The chapter's name is the strip's carved title (2026-09-22):
                // it was an 11-point caption in the plate on the map, under a
                // strip that said CAMPAIGN.
                openChapter?.name ?? "The World",
                subtitle: openChapter.map { chapterSubtitle($0) } ?? "Three realms, and the road between them",
                dismiss: openChapterID == nil ? nil : { openChapterID = nil }
            ) {
                // On a chapter the strip is the tier well and the energy —
                // the one currency the map spends — and nothing else, so
                // the longest name ("The Sand of the Colosseum", 360 points
                // at 19) keeps 0.92 of its size on the CI phone and 0.73 on
                // an SE, over the 0.7 floor. The Realms sheet is the world's:
                // from a chapter it is the chevron back, or an edge arrow.
                if let openChapterID, let base = StageDatabase.chapter(openChapterID) {
                    TierChips(base: base, player: player, difficulty: $difficulty)
                    BarWallet(wallet: player.wallet, shows: [.energy])
                } else {
                    BarButton(title: "Realms", systemImage: "globe.europe.africa.fill") {
                        showRealms = true
                    }
                    BarWallet(wallet: player.wallet)
                }
            } content: {
                // The campaign opens on the world, not on a menu: one painted
                // map of Egypt, Greece and the north with a city per chapter,
                // and the chapter's own road of stages one tap in.
                if let openChapterID {
                    ChapterMapView(
                        chapterID: openChapterID,
                        previewPlayer: previewPlayer,
                        difficulty: $difficulty,
                        openingScroll: openingScroll,
                        onSelect: { stage in
                            Juice.haptic(.light)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { popupStage = stage }
                        },
                        onChapter: { id in
                            withAnimation(.easeOut(duration: 0.25)) {
                                self.openChapterID = id
                            }
                        }
                    )
                } else {
                    WorldRoadMapView { chapter in
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
                            // A chapter picked here opens its map: the sheet
                            // used to set a chapter nothing on the screen
                            // read, so the tap did nothing but close it.
                            WorldMapView { chapter in
                                openChapterID = chapter.id
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
                StageBriefingView(
                    stage: stage,
                    onStart: { runs in
                        selectedStage = nil
                        launch(stage, runs: runs)
                    },
                    onSweep: { runs in
                        selectedStage = nil
                        sweep(stage, runs: runs)
                    }
                )
                .environmentObject(store)
            }
            .fullScreenCover(item: $battle) { context in
                battleScreen(for: context)
            }
            // The stage's card covers this screen and not the game's tab bar,
            // which is `RootView`'s bottom inset and draws above every tab:
            // a tap on a tab with the card open still changes screens. The
            // fix is RootView's (hide the bar while a card is up); said in
            // the phase-B report.
            .overlay {
                if let stage = popupStage, let chapter = StageDatabase.chapter(stage.chapterID) {
                    StagePopup(
                        stage: stage, chapter: chapter,
                        previewPlayer: previewPlayer,
                        onPrepare: {
                            popupStage = nil
                            selectedStage = stage
                        },
                        onFight: {
                            popupStage = nil
                            launch(stage, runs: 1)
                        },
                        onSweep: { runs in
                            popupStage = nil
                            sweep(stage, runs: runs)
                        },
                        onClose: {
                            withAnimation(.easeOut(duration: 0.2)) { popupStage = nil }
                        }
                    )
                    .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
                }
            }
            .overlay {
                if let receipt = sweepReceipt {
                    SweepReceiptCard(
                        receipt: receipt,
                        loot: BattleSummary.loot(from: receipt.outcome) {
                            store.resolved($0)?.name ?? "Unit"
                        },
                        onClose: {
                            withAnimation(.easeOut(duration: 0.2)) { sweepReceipt = nil }
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

    /// Clears a mastered stage without a battle and shows what it paid.
    private func sweep(_ stage: Stage, runs: Int) {
        guard let receipt = store.sweep(stage: stage, runs: runs), receipt.runs > 0 else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.medium)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sweepReceipt = receipt }
    }
}

#if DEBUG
extension CampaignView {
    /// The player the tour photographs a chapter map with: every chapter
    /// before `chapterIndex` walked to its end, the tiers under `tier` on
    /// that chapter walked to theirs (so the tier is open), and the tier
    /// itself four stages in with three, three, two and one stars — so every
    /// painted map shows gold medallions with their stars, the medallion
    /// where the player stands with his leader's face over it, shut ones
    /// beyond, and the boss. A COPY, handed to `previewPlayer` and never
    /// written anywhere: the tour's save persists between launches.
    static func tourWalk(_ player: Player, chapterIndex: Int, tier: CampaignDifficulty = .normal) -> Player {
        var walked = player
        let chapters = StageDatabase.chapters
        guard chapters.indices.contains(chapterIndex) else { return walked }
        for chapter in chapters.prefix(chapterIndex) {
            walked.campaignProgress[chapter.id] = max(walked.campaignProgress[chapter.id] ?? 0, chapter.stages.count)
        }
        let base = chapters[chapterIndex]
        var easier = tier.easier
        while let step = easier {
            walked.campaignProgress[base.id + step.suffix] = base.stages.count
            easier = step.easier
        }
        let road = base.at(tier)
        walked.campaignProgress[road.id] = min(4, max(0, road.stages.count - 1))
        var stars = walked.stageStars ?? [:]
        for (index, pips) in [3, 3, 2, 1].enumerated() where index < road.stages.count {
            stars[road.stages[index].id] = pips
        }
        walked.stageStars = stars
        return walked
    }
}
#endif

// MARK: - What a stage pays, as tiles

/// One thing a stage can pay, as the painted tile draws it: the chapter's
/// sets each as its own stone with its true share of the relic chance
/// (`CampaignService` picks the set uniformly, so a 45% relic of two sets is
/// 22.5% each), the essences, the scrolls, the stones, the drachma, the
/// experience and the first clear's divinity. The popup and the briefing
/// read the same list, so the two cannot disagree. It was a text list with
/// 14-point glyphs although every item has a painted icon (run 211, frame
/// 27).
private struct StageDrop: Identifiable {
    let id: String
    let key: String
    let title: String
    let amount: String?
    var stars: Int? = nil
    var imageName: String? = nil

    /// Main actor: it reads `BarWallet.compact`, a static of a `View` (so
    /// main-actor isolated), and its only callers are the popup and the
    /// briefing, both views.
    @MainActor
    static func list(for stage: Stage, firstClear: Bool, experience: Bool) -> [StageDrop] {
        let rewards = stage.rewards
        var drops: [StageDrop] = []
        if rewards.relicChance > 0 {
            let sets = rewards.relicSets ?? []
            if sets.isEmpty {
                drops.append(StageDrop(id: "relic", key: "relic_cache", title: "\(rewards.relicGrade)★ relic",
                                       amount: percent(rewards.relicChance), stars: rewards.relicGrade))
            } else {
                let share = rewards.relicChance / Double(sets.count)
                for relicSet in sets {
                    drops.append(StageDrop(id: "relic_\(relicSet.rawValue)", key: "relic_cache",
                                           title: relicSet.displayName, amount: percent(share),
                                           stars: rewards.relicGrade, imageName: relicSet.stoneImageName))
                }
            }
        }
        for id in rewards.essenceChances.keys.sorted() {
            if let chance = rewards.essenceChances[id], chance > 0 {
                drops.append(StageDrop(id: id, key: id, title: shortTitle(EssenceCatalog.name(for: id)),
                                       amount: percent(chance)))
            }
        }
        for id in rewards.scrollChances.keys.sorted() {
            if let chance = rewards.scrollChances[id], chance > 0, let scroll = ScrollType(rawValue: id) {
                drops.append(StageDrop(id: "scroll_\(id)", key: ItemArt.key(scroll: scroll),
                                       title: shortTitle(scroll.displayName), amount: percent(chance)))
            }
        }
        for id in (rewards.stoneChances ?? [:]).keys.sorted() {
            if let chance = rewards.stoneChances?[id], chance > 0,
               let stone = RelicStone.all.first(where: { $0.id == id }) {
                drops.append(StageDrop(id: id, key: id, title: stone.displayName, amount: percent(chance)))
            }
        }
        drops.append(StageDrop(id: "drachma", key: "drachma", title: "Drachma",
                               amount: BarWallet.compact(rewards.drachma)))
        if experience {
            drops.append(StageDrop(id: "unit_exp", key: "unit_exp", title: "Unit EXP",
                                   amount: BarWallet.compact(rewards.unitExperience)))
        }
        if firstClear, rewards.firstClearDivinity > 0 {
            drops.append(StageDrop(id: "divinity", key: "divinity", title: "First clear",
                                   amount: "+\(rewards.firstClearDivinity)"))
        }
        return drops
    }

    /// A chance as the corner of a tile reads it: "Sure", "7.5%", "25%".
    static func percent(_ chance: Double) -> String {
        if chance >= 0.995 { return "Sure" }
        let points = chance * 100
        if points < 10 { return String(format: "%.1f%%", points) }
        return "\(Int(points.rounded()))%"
    }

    /// A tile's name without the word the picture already says: "High
    /// Radiance", "Light & Dark" — two lines at most in the tile's 62 points.
    static func shortTitle(_ name: String) -> String {
        for suffix in [" Essence", " Scroll"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}

/// A row of drop tiles given `available` points: it fits, or it scrolls
/// sideways and fades at its trailing edge to say so. The width is the
/// caller's arithmetic, never a `ViewThatFits` (which lays out every
/// candidate) — the popup and the briefing both know their column's width.
private struct StageDropStrip: View {
    let drops: [StageDrop]
    let tile: CGFloat
    let titled: Bool
    let available: CGFloat

    var body: some View {
        // A titled tile is as wide as its name's frame (1.35 of the tile).
        let footprint = titled ? tile * 1.35 : tile
        let gap: CGFloat = titled ? 4 : 8
        let needed = CGFloat(drops.count) * footprint + CGFloat(max(0, drops.count - 1)) * gap
        let overflows = needed > available + 0.5
        // The trailing sixth fades out only when there is more to scroll to.
        let fadeFrom: CGFloat = overflows ? 0.84 : 1
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(drops) { drop in
                    RewardTile(key: drop.key, title: drop.title, amount: drop.amount, stars: drop.stars,
                               size: tile, showsTitle: titled, imageName: drop.imageName, onGlass: true)
                }
            }
            .padding(.trailing, overflows ? 24 : 0)
        }
        .scrollDisabled(!overflows)
        .fixedSize(horizontal: false, vertical: true)
        .mask(
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: fadeFrom),
                        .init(color: overflows ? .clear : .black, location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }
}

/// Whether a foe is the stage's boss: the chapter's named boss, or anything
/// the engine would frame as one (`Combatant.isBoss`: a primordial, or 3 m
/// tall — a Labyrinth level's chapter is not a campaign chapter and names
/// none).
private func foeIsBoss(_ unit: ResolvedUnit, bossID: String?) -> Bool {
    if let bossID, !bossID.isEmpty, unit.blueprint.id == bossID { return true }
    return unit.archetype == .primordial || unit.blueprint.model.height >= 3.0
}

// MARK: - The briefing

/// Pre-battle screen: what you are about to fight, wave by wave, who you
/// are taking, what it pays, and how many times.
///
/// A room in the stage (2026-09-22, phase B): the stage's own battle
/// painting full-bleed under the summon room's scrims and motes, and the
/// words on dark glass. It was washed 72–92% toward cream behind three
/// cream panels — the painting could not be seen — and run 211 photographed
/// the wave label wrapped to "BOS / S" in its 30-point column. The
/// opposition holds the wide left of the frame as nameless faces; the right
/// column is the team (power against the stage's, the leader and the lit
/// resonances) and the spoils as painted tiles; the runs, the sweep and
/// Begin float on the painting's dark foot. The genre sets up its repeat
/// runs here, on the team screen (Summoners War's Battle Preparation), and
/// the runs raise the cost on the button before the start (Honkai: Star
/// Rail's Calyx).
///
/// It is a sheet (from the campaign and from the Labyrinth), so there is no
/// tab bar under it: on the CI phone the content is 734 × 320. The budget is
/// written where each number is used.
struct StageBriefingView: View {
    let stage: Stage
    /// Called with how many runs to fight on auto (1 is one fight by hand).
    let onStart: (Int) -> Void
    /// Called with how many runs to sweep — the same stage, the same energy,
    /// no battle. The screen that presented this one shows the receipt,
    /// because the sweep closes this sheet.
    let onSweep: (Int) -> Void

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var showTeamPicker = false
    @State private var runs = 1

    private static let runChoices = [1, 5, 10, 20]

    /// The right column: five 48-point faces and the chevron (278) inside
    /// the plate's 20 points of padding.
    private static let columnWidth: CGFloat = 320
    /// The deck is as tall as its buttons.
    private static let deckHeight: CGFloat = PrimaryButton.height
    /// "BOSS" in Cinzel at 13 is 35 points; one width for every wave's label
    /// so the faces line up.
    private static let waveLabelWidth: CGFloat = 40
    private static let tileGap: CGFloat = 6
    /// Measured in the shipped fonts: the runs well 169, "SWEEP ×20" 133,
    /// "BEGIN ×20 · 200" 207 (the dearest: a Hell boss at ten energy).
    private static let runsWidth: CGFloat = 169
    private static let sweepWidth: CGFloat = 140
    private static let beginWidth: CGFloat = 212
    /// The deck's line of explanation is shown only where it has at least
    /// this much room — three lines of the longest refusal at 11 points.
    /// 149 on the CI phone; an SE (82) goes without it.
    private static let hintMinimum: CGFloat = 140

    private var team: [ResolvedUnit] { store.team(store.player.campaignTeam) }
    /// The first wave and every wave after it; a plain stage is one wave.
    private var waves: [[ResolvedUnit]] {
        ([stage.enemies] + stage.laterWaves).map { StageDatabase.buildEnemies(spawns: $0) }
    }
    private var cost: Int { EventCalendar.energyCost(for: stage) }
    private var hasEnergy: Bool { store.player.wallet.energy >= cost }

    /// The strip's second line: the chapter and the stage's place in it, or
    /// for a Labyrinth level (whose chapter is not the campaign's) the place.
    private var subtitle: String {
        if let chapter = StageDatabase.chapter(stage.chapterID) {
            return "\(chapter.name) · Stage \(stage.index) of \(chapter.stages.count)"
        }
        return stage.environment.displayName
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
            // The cost is on Begin and the power in the team's plate: the
            // strip keeps the energy the runs will spend and nothing else.
            GameScreen(
                stage.name,
                subtitle: subtitle,
                dismiss: { dismiss() }
            ) {
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
        // One pass of `buildEnemies` per render: `waves` resolves every spawn
        // in every wave each time it is read.
        let rows = waves
        let bossID = StageDatabase.chapter(stage.chapterID)?.bossBlueprintID
        return GeometryReader { geometry in
            let size = geometry.size
            let tile = enemyTile(rows: rows, in: size)
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    oppositionPlate(rows, tile: tile, bossID: bossID)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(spacing: 8) {
                        teamPlate
                        spoilsPlate
                    }
                    .frame(width: Self.columnWidth)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                launchDeck(width: size.width - ScreenChrome.contentPadding * 2)
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
            .frame(width: size.width, height: size.height)
        }
        .background(backdrop)
    }

    /// The stage's own painting, unwashed, under the summon room's scrims
    /// (`PlaceBackdrop`: dark at the top for the plates, dark at the foot
    /// for the deck), with motes in the place's key light. A background is
    /// measured by its host and never takes a tap.
    private var backdrop: some View {
        ZStack {
            PlaceBackdrop(painting: stage.environment.backdropName)
            PlaceAmbience(shafts: [], motes: 16, moteColor: Color(hex: stage.environment.keyLightHex), seed: 1600)
        }
        .allowsHitTesting(false)
    }

    /// The faces grow as the waves thin out, and every size is solved from
    /// the frame rather than a phone's constant: the widest wave must fit the
    /// opposition plate's inside (the frame less the padding, the 10-point
    /// gap, the right column and the plate's 20), and every wave must fit
    /// its height (the frame less the padding, the deck and its gap, the
    /// plate's padding and header, and 8 between rows — the room a BOSS
    /// ribbon straddles). The ceilings are the genre's portrait sizes: a
    /// single wave of two at 104 is the subject of the screen; three waves
    /// stop at 64. On the CI phone a three-wave stage of three draws at 62,
    /// and on an SE a wave of four at 56; the old 42-point cards are gone.
    private func enemyTile(rows: [[ResolvedUnit]], in size: CGSize) -> CGFloat {
        let waveCount = max(1, rows.count)
        let widest = max(1, rows.map(\.count).max() ?? 1)
        let label: CGFloat = waveCount > 1 ? Self.waveLabelWidth + Self.tileGap : 0
        let inner = size.width - ScreenChrome.contentPadding * 2 - 10 - Self.columnWidth - 20
        let byWidth = (inner - label - CGFloat(widest - 1) * Self.tileGap) / CGFloat(widest)
        let plates = size.height - 16 - 8 - Self.deckHeight
        let byHeight = (plates - 20 - 18 - 8 - CGFloat(waveCount - 1) * 8) / CGFloat(waveCount)
        let ceiling: CGFloat
        switch waveCount {
        case 1: ceiling = widest <= 2 ? 104 : 92
        case 2: ceiling = 76
        default: ceiling = 64
        }
        return max(36, floor(min(ceiling, byWidth, byHeight)))
    }

    private func oppositionPlate(_ rows: [[ResolvedUnit]], tile: CGFloat, bossID: String?) -> some View {
        let bossLast = rows.last?.contains(where: { foeIsBoss($0, bossID: bossID) }) ?? false
        return GlassSection(title: "Opposition", accessory: oppositionNote(rows, bossLast: bossLast)) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: Self.tileGap) {
                        if rows.count > 1 {
                            waveLabel(index: index, boss: bossLast && index == rows.count - 1)
                        }
                        ForEach(rows[index]) { enemy in
                            UnitPortraitTile(unit: enemy, size: tile, tag: foeIsBoss(enemy, bossID: bossID) ? "Boss" : nil)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func oppositionNote(_ rows: [[ResolvedUnit]], bossLast: Bool) -> String {
        if rows.count > 1 {
            return bossLast ? "\(rows.count) waves · boss last" : "\(rows.count) waves"
        }
        let foes = rows.first?.count ?? 0
        return foes == 1 ? "1 foe" : "\(foes) foes"
    }

    /// A wave's label in carved Cinzel at its own width: W1, W2, and BOSS in
    /// rose for the boss's wave.
    private func waveLabel(index: Int, boss: Bool) -> some View {
        Group {
            if boss {
                Text("BOSS")
                    .font(Theme.title(13))
                    .foregroundStyle(Theme.onGlassDanger)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            } else {
                Text("W\(index + 1)")
                    .font(Theme.title(13))
                    .carved(glow: false)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .frame(width: Self.waveLabelWidth, alignment: .leading)
    }

    /// The team as faces (the leader crowned when his skill works here),
    /// the empty places dashed, the whole row one tap to the team picker;
    /// the power against the stage's in green or rose as the header's
    /// accessory, where it was a cream pill in the strip; and under it the
    /// bonuses the lineup lights.
    private var teamPlate: some View {
        let team = self.team
        let power = team.reduce(0) { $0 + $1.power }
        let leads = team.first?.blueprint.leaderSkill?.appliesInCampaign == true
        let lit = ResonanceService.active(for: team)
        return GlassSection(
            title: "Your team",
            accessory: "\(power.formatted()) / \(stage.recommendedPower.formatted())",
            accessoryTint: power >= stage.recommendedPower ? Theme.onGlassSuccess : Theme.onGlassDanger
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showTeamPicker = true
                } label: {
                    HStack(spacing: Self.tileGap) {
                        ForEach(Array(team.enumerated()), id: \.element.id) { index, unit in
                            UnitPortraitTile(unit: unit, size: 48, isLeader: index == 0 && leads)
                        }
                        ForEach(0..<max(0, 5 - team.count), id: \.self) { _ in
                            EmptyUnitSlot(size: 48)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Theme.onGlassDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlateButtonStyle())
                .accessibilityLabel("Change the team")
                if leads || !lit.isEmpty {
                    teamBonuses(team: team, leads: leads, lit: lit)
                }
            }
        }
    }

    /// The leader's bonus and the lit resonances as glass beads — the
    /// resonance by its glyph and rank, since "The Weighing of Hearts II"
    /// three times over does not fit a 300-point row and a chip that shrank
    /// to fit rendered at 8 points (the old `minimumScaleFactor(0.75)` under
    /// the 11-point floor) — and a ? with every line in words.
    private func teamBonuses(team: [ResolvedUnit], leads: Bool, lit: [ActiveResonance]) -> some View {
        let skill = leads ? team.first?.blueprint.leaderSkill : nil
        return HStack(spacing: 6) {
            if let skill {
                GlassBead(text: leaderLine(skill), systemImage: "crown.fill", tint: Theme.onGlassGold, height: 24)
            }
            ForEach(lit) { resonance in
                GlassBead(text: resonance.rank.label, systemImage: resonance.kind.glyph, tint: Theme.onGlass, height: 24)
                    .accessibilityLabel(resonance.displayName)
            }
            InfoDot(title: "Team bonuses") {
                VStack(alignment: .leading, spacing: 6) {
                    if let skill {
                        Text("Leader: \(skill.description)")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(lit) { resonance in
                        Text("\(resonance.displayName): \(resonance.line)")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "ATK +18%": the leader skill in the words of a stat line.
    private func leaderLine(_ skill: LeaderSkill) -> String {
        let stat = skill.stat.displayName.replacingOccurrences(of: " %", with: "")
        return "\(stat) +\(Int((skill.amount * 100).rounded()))%"
    }

    /// What the stage pays, as the popup's tiles without their names (a
    /// tile's painting says what it is; the popup has the names): on the
    /// campaign's stages the row fits, on a Labyrinth level of six sets it
    /// scrolls and fades.
    private var spoilsPlate: some View {
        let drops = StageDrop.list(for: stage, firstClear: !CampaignService.isCleared(stage, player: store.player),
                                   experience: true)
        return GlassSection(title: "Spoils") {
            StageDropStrip(drops: drops, tile: 44, titled: false, available: Self.columnWidth - 20)
        }
    }

    // MARK: - The deck

    /// Once, or a run of the same stage on auto, beside the sweep and
    /// Begin, on the painting's dark foot with no tray: the runs are a
    /// dark well like every other choice of its kind, and the cost of the
    /// runs is on Begin ("BEGIN ×20 · 80"), where it was a sentence. The
    /// line between them says why something is dark — no energy, the sweep
    /// not earned — where there is room for it.
    private func launchDeck(width: CGFloat) -> some View {
        let hintWidth = width - Self.runsWidth - Self.sweepWidth - Self.beginWidth - 40 - 8
        let hint = deckHint
        return HStack(spacing: 10) {
            BarSegments(
                options: Self.runChoices.map { (value: $0, title: $0 == 1 ? "Once" : "×\($0)") },
                selection: $runs
            )
            if hintWidth >= Self.hintMinimum, let hint {
                Text(hint.text)
                    .font(Theme.body(11))
                    .foregroundStyle(hint.tint)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: hintWidth, alignment: .leading)
            }
            Spacer(minLength: 0)
            SweepButton(stage: stage, runs: runs, onSweep: onSweep, onGlass: true)
                .frame(width: Self.sweepWidth)
            PrimaryButton(
                title: runs > 1 ? "Begin ×\(runs) · \(cost * runs)" : "Begin · \(cost)",
                systemImage: runs > 1 ? "repeat" : "play.fill",
                isEnabled: hasEnergy && !team.isEmpty,
                itemKey: "energy"
            ) {
                onStart(runs)
            }
            .frame(width: Self.beginWidth)
        }
        .frame(height: Self.deckHeight)
    }

    /// The deck's one line: what stops Begin, what the runs do, or why the
    /// sweep is dark.
    private var deckHint: (text: String, tint: Color)? {
        if !hasEnergy { return ("Not enough energy: a run costs \(cost).", Theme.onGlassDanger) }
        if runs > 1 { return ("On auto until done, a loss, or no energy.", Theme.onGlassDim) }
        if let refusal = SweepService.refusal(stage, player: store.player) { return (refusal, Theme.onGlassDim) }
        return nil
    }
}

// MARK: - The stage's card

/// A stage's card over the map, the genre's stage popup: a window onto the
/// place the fight is in (the stage's own battle painting as its band, the
/// stage's name carved over it), the first wave's faces and the last wave's
/// boss or leader, what it drops as painted tiles — the chapter's two sets
/// first, each its own stone — your power against the stage's, and Fight.
/// "Team & runs" opens the full briefing for the team and the auto runs.
///
/// Deep glass over the dimmed map (2026-09-22, phase B). It was a cream
/// slab 88% of the map wide with half its body empty, the enemies' names cut
/// to "Sun-Scar…", the drops a text list and the chapter's story repeated
/// from the map (run 211, frame 27). It stands in the campaign's content,
/// which on the CI phone is 734 × 314 under the tab bar, so its height is
/// a budget: the band 64, the body 10 + 18 + 8 + 88 (a titled tile), the
/// foot 10 + 48 + 12 — about 258, centred in 314 with 56 to spare. The enemies
/// and the drops stand side by side to make that fit: stacked they came to
/// 346.
struct StagePopup: View {
    let stage: Stage
    let chapter: Chapter
    /// The tour's walked copy of the player; nil reads the store's.
    var previewPlayer: Player? = nil
    let onPrepare: () -> Void
    let onFight: () -> Void
    /// Sweep this stage as many times as the energy allows, up to the
    /// maximum. The popup's Fight is one run, but a sweep of one is barely
    /// worth the tap — the point of it is the twenty.
    let onSweep: (Int) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var store: GameStore

    private static let maxWidth: CGFloat = 700
    private static let enemyTile: CGFloat = 50
    private static let dropTile: CGFloat = 46
    /// "ENEMIES" and "Wave 1 of 3" with their hairline: 158 points.
    private static let enemiesMinimum: CGFloat = 170
    /// The foot's buttons, measured in Cinzel at 15: "TEAM & RUNS" with
    /// its glyph 177, "TEAM" 102, "FIGHT · 10" with the painted bolt 156,
    /// the sweep 133; the power readout is 137.
    private static let teamWide: CGFloat = 184
    private static let teamNarrow: CGFloat = 110
    private static let fightWidth: CGFloat = 164
    private static let sweepWidth: CGFloat = 140
    private static let powerWidth: CGFloat = 137

    private var player: Player { previewPlayer ?? store.player }
    private var team: [ResolvedUnit] { store.team(store.player.campaignTeam) }
    private var teamPower: Int { team.reduce(0) { $0 + $1.power } }
    private var cost: Int { EventCalendar.energyCost(for: stage) }
    private var hasEnergy: Bool { player.wallet.energy >= cost }
    private var waveCount: Int { 1 + stage.laterWaves.count }

    var body: some View {
        GeometryReader { frame in
            let width = min(Self.maxWidth, max(0, frame.size.width - 32))
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                card(width: width)
            }
            .frame(width: frame.size.width, height: frame.size.height)
        }
    }

    private func card(width: CGFloat) -> some View {
        let foes = Array(StageDatabase.buildEnemies(for: stage).prefix(4))
        let headline = headlineFoe()
        let tiles = CGFloat(foes.count) * Self.enemyTile + CGFloat(max(0, foes.count - 1)) * 6
            + (headline == nil ? 0 : 13 + Self.enemyTile)
        let enemiesWidth = max(Self.enemiesMinimum, tiles)
        let inner = width - 28
        let drops = StageDrop.list(for: stage, firstClear: !CampaignService.isCleared(stage, player: player),
                                   experience: false)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 0) {
            band
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionHeader(title: "Enemies", accessory: waveCount > 1 ? "Wave 1 of \(waveCount)" : nil)
                    HStack(alignment: .center, spacing: 6) {
                        ForEach(foes) { foe in
                            UnitPortraitTile(unit: foe, size: Self.enemyTile)
                        }
                        if let headline {
                            Rectangle()
                                .fill(Theme.glassRim.opacity(0.6))
                                .frame(width: 1, height: 40)
                            UnitPortraitTile(
                                unit: headline.unit,
                                size: Self.enemyTile,
                                tag: headline.isBoss ? "Boss" : "Wave \(waveCount)",
                                tagTint: headline.isBoss ? Theme.onGlassDanger : Theme.onGlassEyebrow
                            )
                        }
                    }
                }
                .frame(width: enemiesWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    GlassSectionHeader(title: "Drops")
                    StageDropStrip(drops: drops, tile: Self.dropTile, titled: true,
                                   available: max(0, inner - enemiesWidth - 16))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            footer(inner: inner)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .frame(width: width)
        .background(GlassPlate(radius: 16, opacity: 0.88))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.glassRim, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 22, y: 10)
    }

    /// The band: the stage's own battle painting, a window onto where the
    /// fight is, darkened toward its foot, with the tier, the stage's place
    /// on the road and the place's name as a gold eyebrow and the stage's
    /// name carved over it; the energy and the close at the right. The name
    /// shrinks to 0.6 of 22 before anything cuts it (13.2, over the floor):
    /// the longest, "The Sand of the Colosseum — Confrontation · Hell", is
    /// 738 points at 22 and gets 536 on the CI phone.
    private var band: some View {
        let tier = CampaignDifficulty.split(stage.chapterID).difficulty
        return ZStack(alignment: .bottomLeading) {
            PaintingFill(name: stage.environment.backdropName, focus: UnitPoint(x: 0.5, y: 0.42))
            LinearGradient(
                stops: [.init(color: Color(hex: "#17120E").opacity(0.15), location: 0),
                        .init(color: Color(hex: "#17120E").opacity(0.92), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        if tier != .normal {
                            tierCapsule(tier)
                        }
                        if stage.isBoss {
                            Text("BOSS ·")
                                .font(Theme.body(11).weight(.black))
                                .tracking(1.4)
                                .foregroundStyle(Theme.onGlassDanger)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        Text("STAGE \(stage.index) OF \(chapter.stages.count) · \(stage.environment.displayName.uppercased())")
                            .font(Theme.body(11).weight(.black))
                            .tracking(1.4)
                            .foregroundStyle(Theme.onGlassEyebrow)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                    Text(stage.name.uppercased())
                        .font(Theme.display(22))
                        .tracking(0.8)
                        .carved()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                GlassBead(
                    text: "\(player.wallet.energy)/\(player.wallet.maxEnergy)",
                    itemKey: "energy",
                    tint: hasEnergy ? Theme.onGlass : Theme.onGlassDanger,
                    height: 28
                )
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Theme.onGlass)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(Circle().strokeBorder(Theme.glassRim, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(PlateButtonStyle())
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The eyebrow's 18 and the name's 30 (Cinzel's line is 1.35 of its
        // size) and 12 of padding.
        .frame(height: 64)
    }

    /// Hard or Hell, in the tier's colour lifted for glass.
    private func tierCapsule(_ tier: CampaignDifficulty) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tier.glyph)
                .font(.system(size: 9, weight: .black))
            Text(tier.displayName.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(1.0)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Color(hex: tier.glowHex))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Color(hex: tier.glowHex).opacity(0.8), lineWidth: 0.8))
    }

    /// The foot: your power against the stage's at the left, under the
    /// enemies it is compared with (it was green text in the far corner),
    /// then the team and runs on glass, the sweep once the stage is
    /// mastered, and Fight on gold with the painted bolt and its cost. On a
    /// card too narrow for all of it (an SE with the sweep) "Team & runs"
    /// says "Team".
    private func footer(inner: CGFloat) -> some View {
        let canSweep = SweepService.canSweep(stage, player: player)
        let full = Self.powerWidth + 18 + Self.teamWide + Self.fightWidth + 10
            + (canSweep ? Self.sweepWidth + 10 : 0)
        let roomy = inner >= full
        let meets = teamPower >= stage.recommendedPower
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("YOUR POWER")
                    .font(Theme.body(11).weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .lineLimit(1)
                    .fixedSize()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: meets ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(meets ? Theme.onGlassSuccess : Theme.onGlassDanger)
                    Text(teamPower.formatted())
                        .font(Theme.numeric(16))
                        .foregroundStyle(Theme.onGlass)
                    Text("/ \(stage.recommendedPower.formatted())")
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.onGlassDim)
                }
                .lineLimit(1)
                .fixedSize()
                if !hasEnergy {
                    Text("Not enough energy")
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(Theme.onGlassDanger)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Spacer(minLength: 8)
            PrimaryButton(title: roomy ? "Team & runs" : "Team", systemImage: "person.2.fill", style: .glass) {
                onPrepare()
            }
            .frame(width: roomy ? Self.teamWide : Self.teamNarrow)
            if canSweep {
                SweepButton(stage: stage, runs: SweepService.maximumRuns, onSweep: onSweep, onGlass: true)
                    .frame(width: Self.sweepWidth)
            }
            PrimaryButton(
                title: "Fight · \(cost)",
                systemImage: "play.fill",
                isEnabled: hasEnergy && !team.isEmpty,
                itemKey: "energy"
            ) {
                onFight()
            }
            .frame(width: Self.fightWidth)
        }
    }

    /// The last wave's headliner, drawn after a rule beside the first wave:
    /// the boss when the stage has one, else the leader a grade up that
    /// every generated stage ends on. Built once per card.
    private func headlineFoe() -> (unit: ResolvedUnit, isBoss: Bool)? {
        guard waveCount > 1, let last = stage.laterWaves.last else { return nil }
        let wave = StageDatabase.buildEnemies(spawns: last)
        if let boss = wave.first(where: { foeIsBoss($0, bossID: chapter.bossBlueprintID) }) {
            return (boss, true)
        }
        guard let leader = wave.max(by: { ($0.stars, $0.level) < ($1.stars, $1.level) }) else { return nil }
        return (leader, false)
    }
}
