import SwiftUI

/// The Labyrinth: the relic dungeons, the Halls of Essence and the Endless
/// Tower under one roof, the way the genre keeps its Cairos. It opens over the
/// island from its own building; a dungeon opens as a page of level medallions,
/// and a level is one battle of three waves that ends at the boss. The tower
/// is the third room and has no page of its own — a hundred floors with one
/// way up is a button, not a list.
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
    /// The tower fights from this screen rather than pushing a page: there is
    /// only ever one floor to fight, so there is nothing to navigate to.
    @State private var towerEngine: BattleEngine?
    @State private var towerBattle: BattleContext?
    /// A raid fights from this screen for the same reason the tower does:
    /// there is one encounter behind the card, so there is nothing to
    /// navigate to.
    @State private var raidEngine: BattleEngine?
    @State private var raidBattle: BattleContext?
    @State private var openRaid: RaidEncounter?
    @State private var showTeamPicker = false

    /// The building's three rooms. A three-way choice, so it is `BarSegments`
    /// in the strip rather than a row of capsules above the content.
    enum Wing: Hashable {
        case dungeons
        case halls
        case tower
        case raids
    }

    private let wings: [(value: Wing, title: String)] = [
        (value: .dungeons, title: "Dungeons"),
        (value: .halls, title: "Halls"),
        (value: .tower, title: "Tower"),
        (value: .raids, title: "Raids"),
    ]

    private var subtitle: String {
        switch wing {
        case .dungeons: return "\(DungeonDatabase.labyrinths.count) dungeons · a relic every run"
        case .halls: return "\(DungeonDatabase.halls.count) halls · the awakening essences"
        case .tower:
            let cleared = TowerService.clearedFloor(player: store.player)
            return "\(cleared)/\(DungeonDatabase.towerFloors) floors · one battle each"
        case .raids:
            return "\(StageDatabase.raids.count) bosses · barriers, guards and enrage"
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
                    case .tower:
                        towerWing
                    case .raids:
                        HStack(spacing: 8) {
                            ForEach(StageDatabase.raids) { raid in
                                raidCard(raid)
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
        .sheet(isPresented: $showTeamPicker) {
            TeamPickerView(slot: .campaign, maxSize: 5)
                .environmentObject(store)
        }
        .fullScreenCover(item: $towerBattle, onDismiss: { towerEngine = nil }) { context in
            towerBattleScreen(context)
        }
        .fullScreenCover(item: $raidBattle, onDismiss: { raidEngine = nil; openRaid = nil }) { context in
            raidBattleScreen(context)
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
                    LinearGradient(colors: [.clear, Theme.plate.opacity(0.92)], startPoint: .center, endPoint: .bottom)
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
            // The painting is most of the card now and it declines hits, so
            // the tap would otherwise fall through to whatever the panel
            // background happens to be. The card's own bounds are the target.
            .contentShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
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
            // Two `Spacer`s hold this tile open; a spacer takes no taps, so
            // the whole tile is declared the target instead.
            .contentShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
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

    // MARK: - The Endless Tower

    /// The tower as the building's third room. There is no page of medallions
    /// because there is nothing to choose: the climb resumes at the floor above
    /// the highest cleared and never starts over, so the screen is the next
    /// floor — what it fields, what it pays, and one button.
    private var towerWing: some View {
        let stage = TowerService.nextStage(player: store.player)
        return HStack(alignment: .top, spacing: 8) {
            if let stage {
                towerFloorPanel(stage)
            } else {
                summitPanel
            }
            towerClimbPanel(stage: stage)
                .frame(width: 290)
        }
        .background(alignment: .center) { towerBackdrop(stage) }
    }

    /// The painting of the place the next floor stands in, behind the panels.
    /// Decorative, and `.clipped()` does not clip hit-testing, so it declines
    /// taps or it would swallow the Climb button's half of the screen.
    @ViewBuilder
    private func towerBackdrop(_ stage: Stage?) -> some View {
        if let stage, BundleImage.exists(stage.environment.backdropName) {
            BundleImage(name: stage.environment.backdropName)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [Theme.plate.opacity(0.74), Theme.plate.opacity(0.93)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
    }

    /// What the floor fields and what it pays, shown before the energy is
    /// spent, the way the stage briefing shows a stage. A tower floor is
    /// fought once, so this is the only chance to look at it.
    private func towerFloorPanel(_ stage: Stage) -> some View {
        let floor = stage.index
        let foes = StageDatabase.buildEnemies(for: stage)
        return VStack(alignment: .leading, spacing: 8) {
            // `stage.name` is already "Floor 37 · The Weighing Floor": the
            // floor and the tier it belongs to, which is the whole heading.
            SectionHeader(
                title: stage.name,
                accessory: DungeonDatabase.isTowerBossFloor(floor)
                    ? "the warden and two" : "\(foes.count) foes"
            )
            HStack(spacing: 6) {
                ForEach(foes) { foe in
                    UnitCard(unit: foe, showPower: false, size: 92)
                }
                Spacer(minLength: 0)
            }
            Text("Level \(DungeonDatabase.towerLevel(floor: floor)) · \(DungeonDatabase.towerGrade(floor: floor))★ · ×\(String(format: "%.2f", DungeonDatabase.towerDifficulty(floor: floor))) · \(stage.environment.displayName)")
                .font(Theme.numeric(10))
                .foregroundStyle(Theme.gold)
            VStack(spacing: 3) {
                towerRewardRow("circle.hexagongrid.fill", "Drachma", "\(stage.rewards.drachma)")
                towerRewardRow("arrow.up.circle.fill", "Unit EXP", "\(stage.rewards.unitExperience)")
                towerRewardRow("sparkles", "Divinity", "\(stage.rewards.firstClearDivinity)")
                if stage.rewards.relicChance > 0 {
                    towerRewardRow("shield.lefthalf.filled", "Relic (\(stage.rewards.relicGrade)★)", "always")
                }
                if let scroll = DungeonDatabase.towerScroll(floor: floor) {
                    towerRewardRow("scroll.fill", scroll.displayName, "always")
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .panelBackground()
    }

    private func towerRewardRow(_ icon: String, _ label: String, _ value: String) -> some View {
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

    /// Where the player is, what is worth reaching, who is going, and the one
    /// button. The milestone track is the whole ladder in five numbers: at
    /// floor 60 the next thing to aim at is 75, and it says what 75 pays.
    private func towerClimbPanel(stage: Stage?) -> some View {
        let cleared = TowerService.clearedFloor(player: store.player)
        let team = store.team(store.player.campaignTeam)
        let power = team.reduce(0) { $0 + $1.power }
        let hasEnergy = stage.map { store.player.wallet.energy >= $0.energyCost } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stage.map { "F\($0.index)" } ?? "DONE")
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.gold)
                Text("of \(DungeonDatabase.towerFloors)")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
                Text("\(cleared) cleared")
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.textPrimary)
            }

            milestoneTrack(cleared: cleared)

            if let next = TowerService.nextMilestone(player: store.player) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT MILESTONE · FLOOR \(next)")
                        .font(Theme.body(9).weight(.black))
                        .tracking(1.0)
                        .foregroundStyle(Theme.goldDim)
                    if let reward = DungeonDatabase.towerMilestoneReward(floor: next) {
                        Text(ShopService.describe(reward))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous).fill(Theme.surfaceHigh))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("YOUR TEAM")
                        .font(Theme.body(9).weight(.black))
                        .tracking(1.0)
                        .foregroundStyle(Theme.goldDim)
                    Spacer(minLength: 4)
                    if let stage {
                        Text("\(power) / \(stage.recommendedPower)")
                            .font(Theme.numeric(10))
                            .foregroundStyle(power >= stage.recommendedPower ? Theme.success : Theme.danger)
                    }
                }
                Button {
                    Juice.haptic(.light)
                    showTeamPicker = true
                } label: {
                    HStack(spacing: 5) {
                        ForEach(team) { unit in
                            UnitCard(unit: unit, size: 42)
                        }
                        if team.count < 5 {
                            EmptyTeamSlot(size: 42, label: "Add")
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if let stage {
                // Both reasons the button can be dead say so. `TowerService`
                // throws for either, but the throw never happens while the
                // button is disabled, so the panel has to word them itself or
                // an empty team is a Climb button that silently does nothing.
                if team.isEmpty {
                    Text("Pick at least one unit for your team.")
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !hasEnergy {
                    Text("Not enough energy — this floor costs \(stage.energyCost).")
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton(
                    title: "Climb — \(stage.energyCost) energy",
                    systemImage: "arrow.up.to.line",
                    isEnabled: hasEnergy && !team.isEmpty
                ) {
                    climbTower()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .panelBackground()
    }

    /// The five milestones as a track. A pip is gold once its floor is behind
    /// the player, so the panel says how far up the hundred they are without a
    /// progress bar's worth of height.
    private func milestoneTrack(cleared: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(DungeonDatabase.towerMilestones, id: \.self) { floor in
                let reached = cleared >= floor
                Text("\(floor)")
                    .font(Theme.numeric(11).weight(.bold))
                    .foregroundStyle(reached ? Theme.ink : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(reached ? Theme.gold : Theme.surfaceHigh)
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            reached ? Color.clear : Theme.stroke,
                            lineWidth: 0.5
                        )
                    )
            }
        }
    }

    /// The hundredth floor is cleared. Nothing more to fight, so the panel
    /// says so rather than offering a floor that does not exist.
    private var summitPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "The tower is climbed")
            Text("A hundred floors, and the last of them is behind you. Nothing above the Coil answers to a summoner.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .panelBackground()
    }

    // MARK: - Climbing

    // MARK: - A raid

    /// One raid as a card: the painting of the place, the boss's own words,
    /// and what its mechanics actually are, because a barrier that regenerates
    /// and a weakness that rotates are the fight, and meeting either of them
    /// for the first time inside the battle is meeting them too late.
    private func raidCard(_ raid: RaidEncounter) -> some View {
        let cleared = (store.player.campaignProgress[raid.stage.chapterID] ?? 0) > 0
        let team = store.team(store.player.campaignTeam)
        let power = team.reduce(0) { $0 + $1.power }
        let hasEnergy = store.player.wallet.energy >= raid.stage.energyCost
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                if BundleImage.exists(raid.environment.backdropName) {
                    BundleImage(name: raid.environment.backdropName)
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                LinearGradient(colors: [.clear, Theme.plate.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text("RAID")
                        .font(Theme.body(9).weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.danger)
                    Text(raid.name)
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                .padding(8)
            }
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            // The painting fills, and a fill declines nothing on its own.
            .allowsHitTesting(false)

            Text(raid.summary)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let profile = raid.profile {
                VStack(alignment: .leading, spacing: 3) {
                    raidMechanic("shield.lefthalf.filled", profile.barrierName,
                                 "\(Int((profile.barrierFraction * 100).rounded()))% of its health, back after \(profile.barrierRegenTurns) of its turns; breaking it stuns for \(profile.barrierStunTurns).")
                    if !profile.adds.isEmpty {
                        raidMechanic("person.3.fill", profile.summonName,
                                     "\(profile.adds.count) every \(profile.addInterval) of its turns, and each one alive feeds it \(Int((profile.addDrain * 100).rounded()))% a turn.")
                    }
                }
            }

            if !raid.weaknesses.isEmpty {
                HStack(spacing: 4) {
                    Text("OPENS TO")
                        .font(Theme.body(9).weight(.black))
                        .tracking(1.0)
                        .foregroundStyle(Theme.goldDim)
                    ForEach(raid.weaknesses, id: \.self) { element in
                        Chip(text: element.displayName, systemImage: element.glyph, tint: element.color)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("\(power) / \(raid.stage.recommendedPower)")
                    .font(Theme.numeric(10))
                    .foregroundStyle(power >= raid.stage.recommendedPower ? Theme.success : Theme.danger)
                if cleared {
                    Chip(text: "Cleared", systemImage: "checkmark.seal.fill", tint: Theme.gold)
                }
            }
            PrimaryButton(
                title: "Enter — \(raid.stage.energyCost) energy",
                systemImage: "bolt.horizontal.fill",
                isEnabled: hasEnergy && !team.isEmpty
            ) {
                enterRaid(raid)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .panelBackground()
    }

    private func raidMechanic(_ symbol: String, _ name: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(Theme.body(10).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func enterRaid(_ raid: RaidEncounter) {
        guard let engine = store.startRaid(raid) else { return }
        Juice.haptic(.light)
        raidEngine = engine
        openRaid = raid
        raidBattle = .campaign(raid.stage)
    }

    /// A raid is a campaign battle as far as the plumbing is concerned — the
    /// same view model, the same result panel — and `GameStore.finishRaid`
    /// hands it to `finishCampaignBattle`, which stamps the raid's own id in
    /// `campaignProgress` so a first clear pays exactly once.
    @ViewBuilder
    private func raidBattleScreen(_ context: BattleContext) -> some View {
        if let engine = raidEngine {
            BattleView(model: BattleViewModel(engine: engine, context: context, store: store))
                .environmentObject(store)
        } else {
            Theme.surface
                .ignoresSafeArea()
                .onAppear { raidBattle = nil }
        }
    }

    private func climbTower() {
        guard let stage = TowerService.nextStage(player: store.player) else { return }
        guard let engine = store.startTowerBattle() else { return }
        Juice.haptic(.light)
        towerEngine = engine
        towerBattle = .campaign(stage)
    }

    /// A floor is a campaign battle: the same view model, the same result
    /// panel, and `GameStore.finishCampaignBattle` pays it and moves the mark.
    /// Never a repeat run — a floor is fought once, so there is nothing to
    /// repeat.
    @ViewBuilder
    private func towerBattleScreen(_ context: BattleContext) -> some View {
        if let engine = towerEngine {
            BattleView(model: BattleViewModel(engine: engine, context: context, store: store))
                .environmentObject(store)
        } else {
            Theme.surface
                .ignoresSafeArea()
                .onAppear { towerBattle = nil }
        }
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
                if let chapter {
                    HStack(spacing: 8) {
                        dropsPanel(chapter)
                        levelsPanel(chapter)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 8)
                } else {
                    // Never show an empty room. The CI tour photographed this
                    // screen twice on 2026-09-10 — once for a Hall of Essence
                    // and once for a relic dungeon — and both frames came back
                    // as two panel frames with nothing inside them. If the id
                    // does not resolve, say so on the screen rather than
                    // drawing furniture around a hole.
                    VStack(spacing: 6) {
                        Image(systemName: "questionmark.square.dashed")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Theme.goldDim)
                        Text("This dungeon could not be opened")
                            .font(Theme.title(13))
                            .foregroundStyle(Theme.textPrimary)
                        Text(chapterID)
                            .font(Theme.numeric(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // The painting is a BACKGROUND, never a sibling in the stack.
            // As a sibling it was a fill-aspect image under an unbounded
            // `.frame(maxWidth: .infinity, maxHeight: .infinity)`, which is
            // the oldest trap in SwiftUI: `.clipped()` clips the drawing and
            // not the reported size, so the image grew the ZStack past the
            // window, GameScreen's whole column with it. The CI tour caught
            // it on 2026-09-10 — both frames of this screen came back as two
            // tall panel frames with nothing inside, because the strip and
            // the panels' top-aligned content had been pushed off the top of
            // the screen. A background is measured by its parent and can
            // never do that. The same pattern is safe inside the dungeon
            // cards on the Labyrinth screen because a card bounds it.
            .background(backdrop)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            #if DEBUG
            // One line the CI tour's console will carry, because a photograph
            // of an empty screen does not say whether the data was missing or
            // the layout was.
            print("[DungeonLevels] id=\(chapterID) hall=\(hall != nil) labyrinth=\(labyrinth != nil) "
                  + "chapter=\(chapter?.id ?? "nil") stages=\(chapter?.stages.count ?? -1) "
                  + "backdrop=\(environment?.backdropName ?? "nil")")
            #endif
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
                    colors: [Theme.plate.opacity(0.62), Theme.plate.opacity(0.88)],
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
            Theme.surface
                .ignoresSafeArea()
                .onAppear { battle = nil }
        }
    }
}
