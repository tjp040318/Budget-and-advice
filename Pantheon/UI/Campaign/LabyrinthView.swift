import SwiftUI

/// The Labyrinth: the relic dungeons and the Halls of Essence under one
/// roof, the way the genre keeps its Cairos. It opens over the island from
/// its own building; a dungeon opens as a page of level medallions, and a
/// level is one battle of three waves that ends at the boss.
///
/// The chrome is `GameScreen`: one 34-point strip carrying the wing switch
/// and the wallet, and the whole rest of the frame given to the cards. The
/// two section headers the old layout spent rows on are the strip's subtitle
/// now, and the three dungeons — or the five halls — fill the frame instead
/// of stacking into a scroll under a navigation bar.
struct LabyrinthView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()
    @State private var wing: Wing = .dungeons

    /// The building's two halves. A two-way choice, so it is `BarSegments`
    /// in the strip rather than a row of capsules above the content.
    enum Wing: Hashable {
        case dungeons
        case halls
    }

    private let wings: [(value: Wing, title: String)] = [
        (value: .dungeons, title: "Dungeons"),
        (value: .halls, title: "Halls"),
    ]

    private var subtitle: String {
        switch wing {
        case .dungeons: return "\(DungeonDatabase.labyrinths.count) dungeons · a relic every run"
        case .halls: return "\(DungeonDatabase.halls.count) halls · the awakening essences"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GameScreen("Labyrinth", subtitle: subtitle, dismiss: { dismiss() }) {
                BarSegments(options: wings, selection: $wing)
                BarWallet(wallet: store.player.wallet)
            } content: {
                Group {
                    switch wing {
                    case .dungeons:
                        HStack(spacing: 8) {
                            ForEach(DungeonDatabase.labyrinths) { labyrinth in
                                labyrinthCard(labyrinth)
                            }
                        }
                    case .halls:
                        HStack(spacing: 8) {
                            ForEach(DungeonDatabase.halls) { hall in
                                hallCard(hall)
                            }
                        }
                    }
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
            }
            .navigationDestination(for: String.self) { chapterID in
                DungeonLevelsView(chapterID: chapterID)
            }
        }
    }

    // MARK: - A relic dungeon

    private func labyrinthCard(_ labyrinth: DungeonDatabase.Labyrinth) -> some View {
        let cleared = store.player.campaignProgress[labyrinth.id] ?? 0
        let backdrop = labyrinth.environment.backdropName
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            path.append(labyrinth.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    if BundleImage.exists(backdrop) {
                        BundleImage(name: backdrop)
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Theme.surfaceHigh)
                    }
                    LinearGradient(colors: [.clear, Theme.ink.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("RELIC DUNGEON")
                            .font(Theme.body(9).weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.goldDim)
                        Text(labyrinth.name)
                            .font(Theme.title(15))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(8)
                }
                // The painting takes whatever height the card has left, so
                // three cards fill a landscape frame instead of leaving a
                // third of it black under a 96-point strip of art.
                .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Text(cleared > 0 ? "B\(cleared)/\(labyrinth.levels.count)" : "New")
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.gold))
                        .padding(6)
                }

                // The sets this one drops, which is the whole reason to run it.
                setChips(labyrinth.sets)

                Text(labyrinth.summary)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(8)
            .panelBackground(radius: Theme.tightCorner)
        }
        .buttonStyle(.plain)
    }

    private func setChips(_ sets: [RelicSet]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 90), spacing: 4)], spacing: 4) {
            ForEach(sets) { relicSet in
                HStack(spacing: 3) {
                    Image(systemName: relicSet.glyph)
                        .font(.system(size: 8, weight: .bold))
                    Text(relicSet.displayName)
                        .font(Theme.body(9).weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Theme.surfaceHigh))
            }
        }
    }

    // MARK: - A hall

    /// A hall as a tall tile in its element's colour: five of them across a
    /// landscape frame, the way the genre draws its Hall of Magic.
    private func hallCard(_ hall: DungeonDatabase.Hall) -> some View {
        let cleared = store.player.campaignProgress[hall.id] ?? 0
        let essence = EssenceCatalog.name(for: "essence_\(hall.element.rawValue)_mid")
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            path.append(hall.id)
        } label: {
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: hall.element.glyph)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(hall.element.color)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(hall.element.color.opacity(0.16)))
                    .overlay(Circle().strokeBorder(hall.element.color.opacity(0.5), lineWidth: 1))
                    .shadow(color: hall.element.color.opacity(0.45), radius: 8)
                VStack(spacing: 2) {
                    Text(hall.name)
                        .font(Theme.title(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(essence)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(hall.summary)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("B\(cleared)/\(hall.floors.count)")
                    .font(Theme.numeric(11))
                    .foregroundStyle(cleared > 0 ? Theme.gold : Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.surfaceHigh))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [hall.element.color.opacity(0.20), Theme.surface],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(hall.element.color.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// One dungeon's levels — a relic dungeon's ten or a hall's five — as a row
/// of medallions: gold once cleared, ringed where the player stands, shut
/// beyond. Tapping one opens the briefing; the fight runs on the campaign's
/// plumbing, and its progress lives under the dungeon's id.
///
/// The chrome is `GameScreen` here too: the name, the kind and the progress
/// the old 92-point banner carried are the strip's title, subtitle and count,
/// and the dungeon's painting is the whole content's backdrop instead of a
/// band across the top — so the two panels get the frame.
struct DungeonLevelsView: View {
    let chapterID: String

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStage: Stage?
    @State private var battle: BattleContext?
    @State private var pendingEngines: [String: BattleEngine] = [:]
    @State private var pendingRuns: [String: Int] = [:]
    @State private var pulse = false

    private var labyrinth: DungeonDatabase.Labyrinth? { DungeonDatabase.labyrinth(chapterID) }
    private var hall: DungeonDatabase.Hall? { DungeonDatabase.hall(chapterID) }
    private var chapter: Chapter? { labyrinth?.chapter ?? hall?.chapter }
    private var environment: BattleEnvironment? { labyrinth?.environment ?? hall?.environment }

    private var kindLabel: String {
        labyrinth != nil ? "Relic dungeon · three waves a level" : "Hall of Essence"
    }

    private var progressLabel: String {
        let cleared = store.player.campaignProgress[chapter?.id ?? chapterID] ?? 0
        return "B\(cleared)/\(chapter?.stages.count ?? 0)"
    }

    var body: some View {
        GameScreen(
            chapter?.name ?? "Dungeon",
            subtitle: kindLabel,
            dismiss: { dismiss() }
        ) {
            BarCount(value: progressLabel, systemImage: "flag.checkered", tint: Theme.gold)
            BarWallet(wallet: store.player.wallet)
        } content: {
            ZStack {
                backdrop
                if let chapter {
                    HStack(spacing: 8) {
                        dropsPanel(chapter)
                        levelsPanel(chapter)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
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

    // MARK: - The place, behind everything

    private var backdrop: some View {
        let painting = environment?.backdropName ?? ""
        return ZStack {
            if BundleImage.exists(painting) {
                BundleImage(name: painting)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                LinearGradient(
                    colors: [Theme.ink.opacity(0.62), Theme.ink.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        // A painting scaled to fill swallows taps far outside its frame:
        // `.clipped()` does not clip hit-testing.
        .allowsHitTesting(false)
    }

    // MARK: - What it drops

    private func dropsPanel(_ chapter: Chapter) -> some View {
        let last = chapter.stages.last
        let bossSpawn = last?.laterWaves.last?.first ?? last?.enemies.last
        let boss = bossSpawn.flatMap { StageDatabase.buildEnemies(spawns: [$0]).first }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "The boss")
            HStack(alignment: .top, spacing: 8) {
                if let boss {
                    UnitCard(unit: boss, showPower: false, size: 70)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let labyrinth {
                        Text("Three waves; the boss holds the last. A run pays a relic of the dungeon's own sets, every time.")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("3★ on B1–3 · 4★ on B4–6 · 5★ on B7–9 · 6★ on B10")
                            .font(Theme.numeric(9))
                            .foregroundStyle(Theme.gold)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56, maximum: 90), spacing: 4)], spacing: 4) {
                            ForEach(labyrinth.sets) { relicSet in
                                Text(relicSet.displayName)
                                    .font(Theme.body(9).weight(.semibold))
                                    .foregroundStyle(Theme.gold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(Theme.surfaceHigh))
                            }
                        }
                    } else if let hall {
                        Text(hall.summary)
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Drops \(EssenceCatalog.name(for: "essence_\(hall.element.rawValue)_mid")) and relics up to \(hall.floors.last?.rewards.relicGrade ?? 6)★. Every clear pays.")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .panelBackground()
    }

    // MARK: - The levels

    private func levelsPanel(_ chapter: Chapter) -> some View {
        let player = store.player
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Levels", accessory: "tap one to fight")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 72), spacing: 8)], spacing: 8) {
                ForEach(chapter.stages) { stage in
                    let unlocked = CampaignService.isUnlocked(stage, player: player)
                    let cleared = CampaignService.isCleared(stage, player: player)
                    medallion(stage, unlocked: unlocked, cleared: cleared, current: unlocked && !cleared)
                }
            }
            Spacer(minLength: 0)
            if let next = chapter.stages.first(where: { CampaignService.isUnlocked($0, player: player) && !CampaignService.isCleared($0, player: player) }) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Theme.gold)
                    Text("Next: B\(next.index) · Power \(next.recommendedPower)")
                        .font(Theme.body(11).weight(.semibold))
                        .foregroundStyle(store.totalPower >= next.recommendedPower ? Theme.success : Theme.danger)
                }
            } else {
                Label("Every level cleared", systemImage: "checkmark.seal.fill")
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(Theme.gold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .panelBackground()
    }

    private func medallion(_ stage: Stage, unlocked: Bool, cleared: Bool, current: Bool) -> some View {
        Button {
            guard unlocked else { return }
            Juice.haptic(.light)
            selectedStage = stage
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if current {
                        Circle()
                            .fill(Theme.gold.opacity(pulse ? 0.35 : 0.1))
                            .frame(width: 56, height: 56)
                    }
                    Circle()
                        .fill(cleared ? Theme.gold : (unlocked ? Theme.surfaceHigh : Theme.surface.opacity(0.7)))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().strokeBorder(
                                cleared ? Theme.goldDeep : (current ? Theme.gold : Theme.stroke),
                                lineWidth: current ? 2.5 : 1.5
                            )
                        )
                    if cleared {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Theme.ink)
                    } else if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("B\(stage.index)")
                            .font(Theme.numeric(12).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                    Text("\(stage.energyCost)")
                }
                .font(Theme.body(9).weight(.black))
                .foregroundStyle(Theme.info)
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    // MARK: - Fighting

    private func launch(_ stage: Stage, runs: Int) {
        guard let engine = store.startCampaignBattle(stage: stage) else { return }
        pendingEngines[stage.id] = engine
        pendingRuns[stage.id] = runs
        battle = .campaign(stage)
    }

    @ViewBuilder
    private func battleScreen(for context: BattleContext) -> some View {
        if case .campaign(let stage) = context, let engine = pendingEngines[stage.id] {
            BattleView(model: BattleViewModel(
                engine: engine, context: context, store: store, repeatCount: pendingRuns[stage.id] ?? 1
            ))
            .environmentObject(store)
        } else {
            Color.black
                .ignoresSafeArea()
                .onAppear { battle = nil }
        }
    }
}
