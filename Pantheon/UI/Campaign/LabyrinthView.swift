import SwiftUI

/// The Labyrinth: the relic dungeons and the Halls of Essence under one
/// roof, the way the genre keeps its Cairos. It opens over the island from
/// its own building; a dungeon opens as a page of level medallions, and a
/// level is one battle of three waves that ends at the boss.
struct LabyrinthView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Relic dungeons", accessory: "a relic every run")
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(DungeonDatabase.labyrinths) { labyrinth in
                            labyrinthCard(labyrinth)
                        }
                    }
                    SectionHeader(title: "Halls of Essence", accessory: "the awakening essences")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 8)], spacing: 8) {
                        ForEach(DungeonDatabase.halls) { hall in
                            hallCard(hall)
                        }
                    }
                }
                .padding(12)
            }
            .screen("Labyrinth")
            .navigationDestination(for: String.self) { chapterID in
                DungeonLevelsView(chapterID: chapterID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    WalletBar(wallet: store.player.wallet)
                }
            }
        }
    }

    // MARK: - A relic dungeon

    private func labyrinthCard(_ labyrinth: DungeonDatabase.Labyrinth) -> some View {
        let cleared = store.player.campaignProgress[labyrinth.id] ?? 0
        let scene = labyrinth.environment.sceneName
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            path.append(labyrinth.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    if BundleImage.exists("\(scene)_bg") {
                        BundleImage(name: "\(scene)_bg")
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 96)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Theme.surfaceHigh)
                            .frame(height: 96)
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func hallCard(_ hall: DungeonDatabase.Hall) -> some View {
        let cleared = store.player.campaignProgress[hall.id] ?? 0
        let essence = EssenceCatalog.name(for: "essence_\(hall.element.rawValue)_mid")
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            path.append(hall.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: hall.element.glyph)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(hall.element.color)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(hall.element.color.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(hall.name)
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(essence)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("B\(cleared)/\(hall.floors.count)")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// One dungeon's levels — a relic dungeon's ten or a hall's five — as a row
/// of medallions: gold once cleared, ringed where the player stands, shut
/// beyond. Tapping one opens the briefing; the fight runs on the campaign's
/// plumbing, and its progress lives under the dungeon's id.
struct DungeonLevelsView: View {
    let chapterID: String

    @EnvironmentObject private var store: GameStore
    @State private var selectedStage: Stage?
    @State private var battle: BattleContext?
    @State private var pendingEngines: [String: BattleEngine] = [:]
    @State private var pendingRuns: [String: Int] = [:]
    @State private var pulse = false

    private var labyrinth: DungeonDatabase.Labyrinth? { DungeonDatabase.labyrinth(chapterID) }
    private var hall: DungeonDatabase.Hall? { DungeonDatabase.hall(chapterID) }
    private var chapter: Chapter? { labyrinth?.chapter ?? hall?.chapter }
    private var environment: BattleEnvironment? { labyrinth?.environment ?? hall?.environment }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let chapter {
                    banner(chapter)
                    HStack(alignment: .top, spacing: 10) {
                        dropsPanel(chapter)
                        levelsPanel(chapter)
                    }
                }
            }
            .padding(12)
        }
        .screen(chapter?.name ?? "Dungeon")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                WalletBar(wallet: store.player.wallet)
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

    // MARK: - Banner

    private func banner(_ chapter: Chapter) -> some View {
        let scene = environment?.sceneName ?? ""
        let cleared = store.player.campaignProgress[chapter.id] ?? 0
        return ZStack(alignment: .bottomLeading) {
            if BundleImage.exists("\(scene)_bg") {
                BundleImage(name: "\(scene)_bg")
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                Rectangle().fill(Theme.surfaceHigh).frame(height: 92)
            }
            LinearGradient(colors: [.clear, Theme.ink.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(labyrinth != nil ? "RELIC DUNGEON" : "HALL OF ESSENCE")
                        .font(Theme.body(9).weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.goldDim)
                    Text(chapter.name)
                        .font(Theme.title(18))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text("B\(cleared)/\(chapter.stages.count)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(10)
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
