import SwiftUI

/// The Labyrinth: the relic dungeons, the Halls of Essence, the Endless Tower
/// and the Titans under one roof, the way the genre keeps its Cairos. It opens
/// over the island from its own building; a dungeon or a hall opens as its own
/// ROOM (`DungeonLevelsView`), and a level is one battle of three waves that
/// ends at the boss. The tower is a room with one floor to fight, the Titans a
/// room with five beasts down a rail.
///
/// The chrome is `GameScreen`: one strip carrying the wing switch and the
/// wallet, and the whole rest of the frame given to the wing.
///
/// Phase B of the premium pass (2026-09-22; PLAN.md *Phase B of the premium
/// pass*): the Dungeons and Halls wings stay on the cream ground — they are a
/// menu of places — but every card is an ART card now, the place's painting
/// filling the card and the words on a dark wash; run 211's frame 15 had
/// cream panels with the painting under a cream veil, ink names on it and the
/// Necropolis's lore running onto the frame's corner ornament. The Tower and
/// the Titans are PLACES: the painting full-bleed and the words on dark glass.
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

    /// The island opens the building on its dungeons. The CI tour opens it
    /// on the Titans so the grade stamp is photographed, and may name the
    /// Titan (`raid`, a `RaidEncounter.id`): the Unwrapped King has the
    /// longest name, the one that needs the rail's third line (2026-09-22).
    init(opening: Wing = .dungeons, raid: String? = nil) {
        _wing = State(initialValue: opening)
        _selectedRaidID = State(initialValue: raid)
    }

    /// The building's rooms. A four-way choice, so it is `BarSegments` in the
    /// strip rather than a row of capsules above the content.
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
        (value: .raids, title: "Titans"),
    ]

    /// The Titan whose room is open; nil until one is picked, which reads as
    /// the first.
    @State private var selectedRaidID: String?

    /// The Titans' rail, the summon rail's width. The longest name, "The
    /// Serpent That Swallows the Sun", is whole on three lines at the title
    /// floor of 13 in the 130 points beside its grade stamp (its widest line,
    /// "The Serpent That", is 122 in Cinzel): at 168 the rail read "THE KING
    /// WHO WAS NEVER WEIG…" on run 211's frame 39, an ellipsis in a menu.
    private static let titanRailWidth: CGFloat = 204

    private var subtitle: String {
        switch wing {
        case .dungeons: return "\(DungeonDatabase.labyrinths.count) dungeons · a relic every run"
        case .halls: return "\(DungeonDatabase.halls.count) halls · the awakening essences"
        case .tower:
            let cleared = TowerService.clearedFloor(player: store.player)
            return "\(cleared)/\(DungeonDatabase.towerFloors) floors · one battle each"
        case .raids:
            return "\(StageDatabase.raids.count) Titans · graded F to SSS, paying aether"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GameScreen("Labyrinth", subtitle: subtitle, dismiss: { dismiss() }) {
                BarSegments(options: wings, selection: $wing)
                BarWallet(wallet: store.player.wallet)
            } content: {
                wingContent
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

    /// The two menus of places keep the content's padding on the cream
    /// ground; the two places run their painting to the content's edges and
    /// pad their own words, as the summon room does.
    @ViewBuilder
    private var wingContent: some View {
        switch wing {
        case .dungeons:
            HStack(spacing: 8) {
                ForEach(DungeonDatabase.labyrinths) { labyrinth in
                    labyrinthCard(labyrinth)
                }
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
        case .halls:
            HStack(spacing: 8) {
                ForEach(DungeonDatabase.halls) { hall in
                    hallCard(hall)
                }
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
        case .tower:
            towerWing
        case .raids:
            titansWing
        }
    }

    // MARK: - A relic dungeon

    /// A relic dungeon as an art card: the place's painting fills the card,
    /// a dark wash rises from the foot, and on it the kind, the name carved
    /// in gold and the six sets it drops as their painted stones with their
    /// names — the sets are the whole reason to run it (Summoners War defines
    /// a dungeon by its set list). The lore went behind the levels screen's
    /// ? (2026-09-22): on run 211's frame 15 it ran onto the panel's corner
    /// ornament.
    private func labyrinthCard(_ labyrinth: DungeonDatabase.Labyrinth) -> some View {
        let cleared = store.player.campaignProgress[labyrinth.id] ?? 0
        let doubled = EventCalendar.isActive(.doubleRelics(labyrinth: labyrinth.id))
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            path.append(labyrinth.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color(hex: "#0E0B08")
                // `PaintingFill` (Color.clear with the painting as an
                // overlay), never a fill image under a flexible frame: the
                // fill size grew this card to the painting's own height and
                // carried the name below the clip on run 210.
                PaintingFill(name: labyrinth.environment.backdropName)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.30),
                        .init(color: Color.black.opacity(0.55), location: 0.58),
                        .init(color: Color.black.opacity(0.88), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 6) {
                    Text("RELIC DUNGEON")
                        .font(Theme.title(13))
                        .tracking(2.0)
                        .foregroundStyle(Theme.onGlassEyebrow)
                        .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                        .lineLimit(1)
                        .fixedSize()
                    // Two lines, shrinking to the title floor before either
                    // is cut: "Necropolis of the Unwrapped King" is the long one.
                    Text(labyrinth.name)
                        .font(Theme.display(18))
                        .carved()
                        .lineLimit(2)
                        .minimumScaleFactor(Theme.titleFloor / 18)
                        .fixedSize(horizontal: false, vertical: true)
                    setStones(labyrinth.sets)
                }
                .padding(12)
            }
            .labyrinthCardFrame()
            .overlay(alignment: .topTrailing) {
                GlassBead(
                    text: cleared > 0 ? "B\(cleared)/\(labyrinth.levels.count)" : "New",
                    tint: cleared > 0 ? Theme.onGlass : Theme.onGlassEyebrow
                )
                .padding(8)
            }
            .overlay(alignment: .topLeading) {
                if doubled {
                    GlassBead(text: "Relic ×2 today", systemImage: "sparkles", tint: Theme.onGlassEyebrow)
                        .padding(8)
                }
            }
        }
        .buttonStyle(PlateButtonStyle())
        .accessibilityLabel("\(labyrinth.name), \(cleared) of \(labyrinth.levels.count) levels cleared")
    }

    /// The six sets as the painted stones themselves, in a row, with their
    /// names under them: six stones at 26 points are 186 wide, inside the
    /// narrowest card's 207. The cream text pills with 9-point emblems they
    /// replace were the one place the stones were not shown.
    private func setStones(_ sets: [RelicSet]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(sets) { relicSet in
                    RelicSetEmblem(set: relicSet, size: 26)
                }
            }
            Text(sets.map(\.displayName).joined(separator: " · "))
                .font(Theme.body(11))
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - A hall

    /// A hall as a tall art card, five across the frame the way the genre
    /// draws its Hall of Magic: the hall's painting, its element's light
    /// rising from the foot, the High essence it is farmed for painted large,
    /// the name carved, and the three tiers it pays as their paintings. The
    /// 30-point SF Symbol in a tinted circle it replaces was the app-skeleton
    /// look, and the three tier paintings say what the old name line and
    /// summary said in words.
    private func hallCard(_ hall: DungeonDatabase.Hall) -> some View {
        let cleared = store.player.campaignProgress[hall.id] ?? 0
        let doubled = EventCalendar.isActive(.doubleEssence(hall.element))
        let prefix = "essence_\(hall.element.rawValue)_"
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            path.append(hall.id)
        } label: {
            ZStack {
                Color(hex: "#0E0B08")
                PaintingFill(name: hall.environment.backdropName)
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.15), location: 0),
                        .init(color: Color.black.opacity(0.45), location: 0.45),
                        .init(color: Color.black.opacity(0.88), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                LinearGradient(colors: [hall.element.color.opacity(0.28), .clear], startPoint: .bottom, endPoint: .center)
                    .allowsHitTesting(false)
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    ItemIcon(key: prefix + "high", size: 60, glow: true)
                    Text(hall.name)
                        .font(Theme.title(15))
                        .carved(glow: false)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(Theme.titleFloor / 15)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        ForEach(["low", "mid", "high"], id: \.self) { tier in
                            ItemIcon(key: prefix + tier, size: 20, glow: false)
                        }
                    }
                    GlassBead(
                        text: "B\(cleared)/\(hall.floors.count)",
                        tint: cleared > 0 ? Theme.onGlass : Theme.onGlassDim
                    )
                }
                .padding(10)
            }
            .labyrinthCardFrame()
            .overlay(alignment: .top) {
                // "×2 today" and not "Essence ×2 today": a hall card is 139
                // points wide on the CI phone and the bead never truncates.
                if doubled {
                    GlassBead(text: "×2 today", systemImage: "sparkles", tint: Theme.onGlassEyebrow)
                        .padding(.top, 8)
                }
            }
        }
        .buttonStyle(PlateButtonStyle())
        .accessibilityLabel("\(hall.name), \(cleared) of \(hall.floors.count) floors cleared")
    }

    // MARK: - The Endless Tower

    /// The tower as a place (2026-09-22): the painting of the tier the next
    /// floor stands in, full-bleed under dark scrims, the floor carved on it,
    /// what it fields and pays on one glass plate, and the climb on another.
    /// There is no page of medallions because there is nothing to choose: the
    /// climb resumes at the floor above the highest cleared and never starts
    /// over. It was two cream panels over the painting under a cream wash
    /// (`Theme.plate` 0.74 to 0.93), which is to say the painting was never
    /// seen, and the one room of the building left in the old material once
    /// the halls and the dungeons went to glass.
    private var towerWing: some View {
        let stage = TowerService.nextStage(player: store.player)
        // Past the hundredth floor there is no next stage; the summit stands
        // in the Coil, the last tier's place.
        let environment = stage?.environment
            ?? DungeonDatabase.towerTier(floor: DungeonDatabase.towerFloors).environment
        return HStack(alignment: .top, spacing: 10) {
            if let stage {
                towerFloorColumn(stage)
            } else {
                summitColumn
            }
            towerClimbPanel(stage: stage)
                .frame(width: 290)
        }
        .padding(.horizontal, ScreenChrome.contentPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            placeGround(environment.backdropName, motes: Color(hex: environment.keyLightHex), seed: 952)
        }
    }

    /// A place's painting under dark scrims with its motes over it: the
    /// ground of the Tower and the Titans. `PlaceBackdrop` is exactly the size
    /// it is given, so as a `.background` it can never spill over the strip
    /// the way the dungeon levels' painting did for a week.
    private func placeGround(_ painting: String, motes: Color, seed: UInt64) -> some View {
        ZStack {
            PlaceBackdrop(painting: painting)
            PlaceAmbience(shafts: [], motes: 16, moteColor: motes, seed: seed)
        }
        .allowsHitTesting(false)
    }

    /// What the floor fields and what it pays, shown before the energy is
    /// spent, the way the stage briefing shows a stage. A tower floor is
    /// fought once, so this is the only chance to look at it. The floor's
    /// number is carved on the painting's dark top; the foes are faces (a
    /// cream name strip on glass is a slab) and the pay is tiles.
    private func towerFloorColumn(_ stage: Stage) -> some View {
        let floor = stage.index
        let tier = DungeonDatabase.towerTier(floor: floor)
        let foes = StageDatabase.buildEnemies(for: stage)
        let warden = DungeonDatabase.isTowerBossFloor(floor)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text("F\(floor)")
                    .font(Theme.display(30))
                    .carved()
                    .lineLimit(1)
                    .fixedSize()
                PlaceTitle(
                    eyebrow: "Lv.\(DungeonDatabase.towerLevel(floor: floor)) · \(DungeonDatabase.towerGrade(floor: floor))★ foes",
                    title: tier.name,
                    size: 18
                )
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 7) {
                GlassSectionHeader(title: warden ? "The warden and two" : "\(foes.count) foes")
                HStack(spacing: 10) {
                    ForEach(Array(foes.enumerated()), id: \.offset) { index, foe in
                        UnitPortraitTile(unit: foe, size: 60, tag: warden && index == 0 ? "Warden" : nil)
                    }
                }
                // The warden's tag straddles the tile's top edge.
                .padding(.top, warden ? 6 : 0)
                GlassSectionHeader(title: "What it pays")
                HStack(alignment: .top, spacing: 6) {
                    ForEach(towerDrops(stage)) { drop in
                        RewardTile(key: drop.key, title: drop.title, amount: drop.amount, stars: drop.stars,
                                   size: 44, onGlass: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(GlassPlate())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A tower floor's pay as tiles: drachma and unit experience with the
    /// day's event in them, the divinity its clear pays, the relic every fifth
    /// floor and the warden's scroll.
    private func towerDrops(_ stage: Stage) -> [DungeonDrop] {
        let rewards = stage.rewards
        let boosts = EventCalendar.boosts(for: stage)
        var drops: [DungeonDrop] = [
            DungeonDrop(id: "drachma", key: "drachma", title: "Drachma",
                        amount: "+\(Int(Double(rewards.drachma) * boosts.drachma).formatted())", stars: nil),
            DungeonDrop(id: "unit_exp", key: "unit_exp", title: "Unit EXP",
                        amount: "+\(Int(Double(rewards.unitExperience) * boosts.experience).formatted())", stars: nil),
            DungeonDrop(id: "divinity", key: "divinity", title: "Divinity",
                        amount: "+\(rewards.firstClearDivinity)", stars: nil),
        ]
        if rewards.relicChance > 0 {
            drops.append(DungeonDrop(id: "relic", key: "relic_cache", title: "Relic",
                                     amount: rewards.relicChance >= 1 ? "×1" : DungeonDrop.percent(rewards.relicChance),
                                     stars: rewards.relicGrade))
        }
        if let scroll = DungeonDatabase.towerScroll(floor: stage.index) {
            drops.append(DungeonDrop(id: scroll.rawValue, key: ItemArt.key(scroll: scroll),
                                     title: DungeonDrop.shortName(scroll), amount: "×1", stars: nil))
        }
        return drops
    }

    /// Where the player is, what is worth reaching, who is going, and the one
    /// button. The milestone track is the whole ladder in five numbers: at
    /// floor 60 the next thing to aim at is 75, and its tiles say what 75 pays.
    private func towerClimbPanel(stage: Stage?) -> some View {
        let cleared = TowerService.clearedFloor(player: store.player)
        let team = store.team(store.player.campaignTeam)
        let power = team.reduce(0) { $0 + $1.power }
        let cost = stage.map { EventCalendar.energyCost(for: $0) } ?? 0
        let hasEnergy = store.player.wallet.energy >= cost
        return VStack(alignment: .leading, spacing: 7) {
            GlassSectionHeader(title: "The climb", accessory: "\(cleared) of \(DungeonDatabase.towerFloors)")
            milestoneTrack(cleared: cleared)

            if let next = TowerService.nextMilestone(player: store.player),
               let reward = DungeonDatabase.towerMilestoneReward(floor: next) {
                GlassSectionHeader(title: "Floor \(next) pays")
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(Self.grants(in: reward).enumerated()), id: \.offset) { _, grant in
                        RewardTile(key: ItemArt.key(for: grant), amount: Self.shortAmount(grant),
                                   stars: ItemArt.stars(for: grant), size: 40, showsTitle: false, onGlass: true)
                    }
                }
            }

            Spacer(minLength: 0)

            GlassSectionHeader(
                title: "Your team",
                accessory: stage.map { "\(power.formatted()) / \($0.recommendedPower.formatted())" },
                accessoryTint: stage.map { power >= $0.recommendedPower } == true ? Theme.onGlassSuccess : Theme.onGlassDanger
            )
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showTeamPicker = true
            } label: {
                HStack(spacing: 5) {
                    ForEach(team) { unit in
                        UnitPortraitTile(unit: unit, size: 40)
                    }
                    if team.count < 5 {
                        EmptyUnitSlot(size: 40)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your team, \(team.count) of 5")

            if let stage {
                // Both reasons the button can be dead are its title: an empty
                // team opens the picker, a short wallet says what the floor
                // costs. A disabled plate with no reason is the most annoying
                // thing in a menu.
                let ready = hasEnergy && !team.isEmpty
                PrimaryButton(
                    title: team.isEmpty ? "Choose a team"
                        : (hasEnergy ? "Climb — \(cost) energy" : "Needs \(cost) energy"),
                    systemImage: team.isEmpty ? "person.2.fill" : "arrow.up.to.line",
                    isEnabled: team.isEmpty || hasEnergy,
                    style: ready || team.isEmpty ? .painted : .glass
                ) {
                    if team.isEmpty {
                        showTeamPicker = true
                    } else {
                        climbTower()
                    }
                }
                .accessibilityHint(stage.name)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassPlate())
    }

    /// A shop grant as the tiles it pays: a bundle is its parts, so the
    /// milestone's scrolls, divinity and drachma are three tiles, not a gift.
    private static func grants(in reward: ShopService.Grant) -> [ShopService.Grant] {
        if case .bundle(let parts) = reward { return parts }
        return [reward]
    }

    /// A grant's corner count at a 40-point tile: drachma in thousands
    /// ("+100K"), since "+100,000" overhangs the socket into its neighbour
    /// and the milestone row holds six tiles across 270 points.
    private static func shortAmount(_ grant: ShopService.Grant) -> String {
        if case .drachma(let amount) = grant { return "+" + BarWallet.compact(amount) }
        return ItemArt.amount(for: grant)
    }

    /// The five milestones as a track. A pip is gold once its floor is behind
    /// the player, so the panel says how far up the hundred they are without a
    /// progress bar's worth of height.
    private func milestoneTrack(cleared: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(DungeonDatabase.towerMilestones, id: \.self) { floor in
                let reached = cleared >= floor
                Text("\(floor)")
                    .font(Theme.numeric(11.5).weight(.bold))
                    .foregroundStyle(reached ? Theme.ink : Theme.onGlassDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(reached ? AnyShapeStyle(Theme.goldPlate) : AnyShapeStyle(Color.black.opacity(0.4)))
                    )
                    .overlay(
                        Capsule().strokeBorder(reached ? Color.clear : Theme.glassRim.opacity(0.6), lineWidth: 0.8)
                    )
            }
        }
    }

    /// The hundredth floor is cleared. Nothing more to fight, so the room
    /// says so rather than offering a floor that does not exist.
    private var summitColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaceTitle(eyebrow: "The Endless Tower", title: "The tower is climbed", size: 24)
            Text("A hundred floors, and the last of them is behind you. Nothing above the Coil answers to a demigod.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.onGlass)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(GlassPlate())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - The Titans

    /// The Titan whose room is open: the one picked, or the first.
    private var chosenRaid: RaidEncounter? {
        StageDatabase.raids.first(where: { $0.id == selectedRaidID }) ?? StageDatabase.raids.first
    }

    /// Five beasts, one per element, the genre's Rift, as a PLACE since
    /// 2026-09-22: the chosen Titan's own painting full-bleed, a glass rail
    /// of the five down the left with each one's best grade stamped on it,
    /// and the room beside it — the name carved on the painting, the Titan's
    /// face, how it fights on one glass plate, and the deck on the dark foot.
    ///
    /// Run 211's frame 39 had no strip at all: the old card (a 120-point band,
    /// the summary, two mechanics, OPENS TO, the grade row, the power and
    /// Enter, about 400 points) was taller than the 329 the phone gives the
    /// content, and the overflow pushed `GameScreen`'s strip — its title, its
    /// Back and its wallet — off the top, the unit sheet's fault of runs
    /// 204–210 again. The room's middle is a scroll between a fixed title and
    /// a fixed deck, so nothing in it can grow the screen, and the lore went
    /// behind the ?.
    private var titansWing: some View {
        let chosen = chosenRaid
        return HStack(spacing: 0) {
            // Five rows of two and three lines are taller than the frame, so
            // the rail opens scrolled to the Titan whose room is open.
            ScrollViewReader { proxy in
                PlaceRail(width: Self.titanRailWidth) {
                    PlaceRailLabel("Titans")
                    ForEach(StageDatabase.raids) { raid in
                        titanTile(raid, isOn: raid.id == chosen?.id)
                            .id(raid.id)
                    }
                }
                .onAppear {
                    guard let id = chosen?.id else { return }
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .frame(width: Self.titanRailWidth)
            if let chosen {
                titanRoom(chosen)
                    .id(chosen.id)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            placeGround(
                chosen?.environment.backdropName ?? "",
                motes: chosen.map { RaidGradeService.element(of: $0).color } ?? Theme.gold,
                seed: 951
            )
        }
    }

    /// One Titan on the rail: its best grade as a stamp, its element, its
    /// name in Cinzel at the title floor on up to three lines — never cut —
    /// and a seal once it has fallen, on the summon rail's row plate.
    private func titanTile(_ raid: RaidEncounter, isOn: Bool) -> some View {
        let element = RaidGradeService.element(of: raid)
        let best = RaidGradeService.bestGrade(for: raid, player: store.player)
        let cleared = (store.player.campaignProgress[raid.stage.chapterID] ?? 0) > 0
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            selectedRaidID = raid.id
        } label: {
            HStack(spacing: 8) {
                RaidGradeStamp(grade: best, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: element.glyph)
                            .font(.system(size: 10, weight: .black))
                        Text(element.displayName.uppercased())
                            .font(Theme.body(11).weight(.black))
                            .tracking(1.0)
                            .lineLimit(1)
                            .fixedSize()
                        if cleared {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.onGlassGold)
                        }
                    }
                    .foregroundStyle(element.color)
                    Text(raid.name)
                        .font(Theme.title(13))
                        .foregroundStyle(isOn ? Color(hex: "#FFF1C2") : Theme.onGlass)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(GlassRowPlate(isOn: isOn))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(raid.name), \(element.displayName) Titan\(best.map { ", best grade \($0.label)" } ?? "")")
    }

    // MARK: - A Titan's room

    /// One Titan as a room: the name carved on the painting's dark top with
    /// the lore behind a ?, the Titan's face standing on the painted floor,
    /// what its mechanics actually are on one glass plate — a barrier that
    /// regenerates and a weakness that rotates are the fight, and meeting
    /// either for the first time inside the battle is meeting it too late —
    /// and the deck on the dark foot.
    private func titanRoom(_ raid: RaidEncounter) -> some View {
        let element = RaidGradeService.element(of: raid)
        // The Titan itself: the genre's beast panel leads with the beast, and
        // three of the five places are painted at night (run 160).
        let titan = raid.stage.enemies.first(where: { $0.raid != nil })
            .flatMap { StageDatabase.buildEnemies(spawns: [$0]).first }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                PlaceTitle(eyebrow: "Titan of \(element.displayName)", title: raid.name, size: 20)
                Spacer(minLength: 6)
                InfoDot(title: raid.name) {
                    Text(raid.summary)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        if let titan {
                            UnitPortraitTile(unit: titan, size: 84)
                                .background(alignment: .bottom) { PaintedFloorPool() }
                        }
                    }
                    .frame(width: 96)
                    .padding(.top, 4)
                    titanPlate(raid)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
            titanDeck(raid)
        }
        .padding(.leading, 14)
        .padding(.trailing, ScreenChrome.contentPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// What the Titan opens itself to, how it fights, and the grade: one
    /// plate of glass, the weaknesses as its header row.
    private func titanPlate(_ raid: RaidEncounter) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if !raid.weaknesses.isEmpty {
                HStack(spacing: 6) {
                    Text("OPENS TO")
                        .font(Theme.title(13))
                        .tracking(1.6)
                        .carved(glow: false)
                        .lineLimit(1)
                        .fixedSize()
                    ForEach(raid.weaknesses, id: \.self) { element in
                        GlassBead(text: element.displayName, systemImage: element.glyph, tint: element.color, height: 24)
                    }
                }
            }
            if let profile = raid.profile {
                VStack(alignment: .leading, spacing: 4) {
                    raidMechanic("shield.lefthalf.filled", profile.barrierName,
                                 "\(Int((profile.barrierFraction * 100).rounded()))% of its health, back after \(profile.barrierRegenTurns) of its turns; breaking it stuns for \(profile.barrierStunTurns).")
                    if !profile.adds.isEmpty {
                        raidMechanic("person.3.fill", profile.summonName,
                                     "\(profile.adds.count) every \(profile.addInterval) of its turns, and each one alive feeds it \(Int((profile.addDrain * 100).rounded()))% a turn.")
                    }
                }
                Rectangle()
                    .fill(LinearGradient(colors: [Theme.gold.opacity(0.6), Theme.gold.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                raidGradeRow(raid, profile: profile)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GlassPlate())
    }

    /// The power against the Titan's, Cleared once it has fallen, and Enter.
    /// An empty team makes the button the way to pick one; a short wallet
    /// makes it say what the fight costs.
    private func titanDeck(_ raid: RaidEncounter) -> some View {
        let cleared = (store.player.campaignProgress[raid.stage.chapterID] ?? 0) > 0
        let team = store.team(store.player.campaignTeam)
        let power = team.reduce(0) { $0 + $1.power }
        let cost = EventCalendar.energyCost(for: raid.stage)
        let hasEnergy = store.player.wallet.energy >= cost
        let strong = power >= raid.stage.recommendedPower
        return HStack(spacing: 10) {
            GlassBead(
                text: "\(power.formatted()) / \(raid.stage.recommendedPower.formatted())",
                systemImage: strong ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                tint: strong ? Theme.onGlassSuccess : Theme.onGlassDanger,
                height: 30
            )
            if cleared {
                GlassBead(text: "Cleared", systemImage: "checkmark.seal.fill", tint: Theme.onGlassGold, height: 30)
            }
            Spacer(minLength: 6)
            PrimaryButton(
                title: team.isEmpty ? "Choose a team"
                    : (hasEnergy ? "Enter — \(cost) energy" : "Needs \(cost) energy"),
                systemImage: team.isEmpty ? "person.2.fill" : "bolt.horizontal.fill",
                isEnabled: team.isEmpty || hasEnergy,
                style: team.isEmpty || hasEnergy ? .painted : .glass
            ) {
                if team.isEmpty {
                    showTeamPicker = true
                } else {
                    enterRaid(raid)
                }
            }
            .frame(maxWidth: 280)
        }
    }

    /// The grade: the best one earned as a stamp, the mark the next one asks
    /// for, and the aether in hand — the raid is farmed for it, so the room
    /// says what the player has and what the next grade would add.
    private func raidGradeRow(_ raid: RaidEncounter, profile: RaidBossProfile) -> some View {
        let best = RaidGradeService.bestGrade(for: raid, player: store.player)
        let elemental = Aether.id(for: RaidGradeService.element(of: raid))
        return HStack(alignment: .center, spacing: 8) {
            RaidGradeStamp(grade: best, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text((best.map { "Best grade \($0.label)" } ?? "Not yet graded").uppercased())
                    .font(Theme.title(13))
                    .tracking(1.0)
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .lineLimit(1)
                    .fixedSize()
                Text(RaidGradeService.target(after: best, profile: profile))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            // What it pays, and how much of it the player holds.
            VStack(alignment: .trailing, spacing: 2) {
                aetherCount(elemental)
                aetherCount(Aether.pure)
            }
        }
    }

    private func aetherCount(_ id: String) -> some View {
        HStack(spacing: 4) {
            ItemIcon(key: id, size: 16, glow: false)
            Text("\(Aether.count(id, player: store.player))")
                .font(Theme.numeric(12))
                .foregroundStyle(Theme.onGlass)
                .fixedSize()
        }
        .accessibilityLabel("\(Aether.name(for: id)) \(Aether.count(id, player: store.player))")
    }

    private func raidMechanic(_ symbol: String, _ name: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onGlassGold)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.onGlass)
                Text(detail)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
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

    // MARK: - Climbing

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

// MARK: - A dungeon's room

/// One dungeon — a relic dungeon's ten levels or a hall's five floors — as a
/// ROOM, the summon screen's recipe (2026-09-22, phase B; PLAN.md, *Phase B
/// of the premium pass*, option C of five): the place's painting full-bleed
/// under dark scrims with its own light's motes; a glass rail of the floors
/// down the left, each row saying what it pays, the stars earned, the energy
/// and the power it asks; the chosen floor carved on the painting's dark top;
/// its boss standing on the painted floor; its drops as tiles on one glass
/// plate with the dungeon's six sets as their stones (or, in a hall, what an
/// awakening spends as essence chips); and the deck on the dark foot. One tap
/// fights.
///
/// Run 211 photographed it as two cream marble slabs on a cream ground: the
/// painting was washed 62–88% toward cream, the left slab was 60% empty, the
/// boss card read the LAST level's Lv.50 on a screen whose only open floor
/// was B1, a medallion said only its energy (no grade, no stars, so nothing
/// said which floors pay what or can be swept), the Halls' drops were a
/// seven-line paragraph, and the one power reading compared the stage with
/// the best five units owned rather than the team that fights. Every fight
/// cost two screens (medallion, briefing, Begin).
///
/// The fight runs on the campaign's plumbing, and its progress lives under
/// the dungeon's id.
struct DungeonLevelsView: View {
    let chapterID: String

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    /// The floor whose briefing sheet is open: Team & runs.
    @State private var selectedStage: Stage?
    /// The floor the room shows. Nil reads as the player's current floor —
    /// the first open and uncleared one — so the room opens where he stands.
    @State private var focusedID: String?
    @State private var battle: BattleContext?
    @State private var pendingEngines: [String: BattleEngine] = [:]
    @State private var pendingRuns: [String: Int] = [:]
    @State private var pulse = false
    /// The haul of the last sweep, shown over the room.
    @State private var sweepReceipt: SweepReceipt?

    /// `focusFloor` opens the room on that floor rather than the player's
    /// current one; the CI tour pins it to photograph a mastered floor's deck.
    /// Every dungeon's and hall's stage ids are `<chapter>_<n>`.
    init(chapterID: String, focusFloor: Int? = nil) {
        self.chapterID = chapterID
        _focusedID = State(initialValue: focusFloor.map { "\(chapterID)_\($0)" })
    }

    /// The floor rail's width: the summon rail's 204 plus room for a hall
    /// row's two essence readings ("Low · 40%") beside the energy and power.
    private static let railWidth: CGFloat = 212

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
                    HStack(spacing: 0) {
                        floorRail(chapter)
                        if let stage = focused(chapter) {
                            floorRoom(chapter, stage: stage)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
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
                            .foregroundStyle(Theme.onGlassEyebrow)
                        Text("This dungeon could not be opened")
                            .font(Theme.title(13))
                            .foregroundStyle(Theme.onGlass)
                        Text(chapterID)
                            .font(Theme.numeric(11.5))
                            .foregroundStyle(Theme.onGlassDim)
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
            // never do that.
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
                  + "focus=\(focusedID ?? "current") backdrop=\(environment?.backdropName ?? "nil")")
            #endif
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
        }
        .fullScreenCover(item: $battle) { context in
            battleScreen(for: context)
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

    /// Clears a mastered level without a battle. The relic grind is the one
    /// this matters most for: ten runs of a B10 is ten minutes of watching
    /// three waves resolve the same way.
    private func sweep(_ stage: Stage, runs: Int) {
        guard let receipt = store.sweep(stage: stage, runs: runs), receipt.runs > 0 else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.medium)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { sweepReceipt = receipt }
    }

    /// The player's floor: the first open and uncleared one, or the top once
    /// every floor has fallen.
    private func currentStage(_ chapter: Chapter) -> Stage? {
        chapter.stages.first {
            CampaignService.isUnlocked($0, player: store.player) && !CampaignService.isCleared($0, player: store.player)
        } ?? chapter.stages.last
    }

    /// The floor the room shows: the one tapped on the rail, or the player's.
    private func focused(_ chapter: Chapter) -> Stage? {
        chapter.stages.first { $0.id == focusedID } ?? currentStage(chapter)
    }

    // MARK: - The place, behind everything

    /// The place's painting, UNWASHED, under the summon room's dark scrims
    /// (`PlaceBackdrop`), with motes in the place's own key light over it:
    /// amber torchlight in the Vault, the marsh's green in the Lair. It was
    /// washed 62–88% toward cream until 2026-09-22, and the room was two
    /// cream slabs on a cream ground (run 211, frame 16).
    ///
    /// `PlaceBackdrop` is exactly the size it is given. This screen's
    /// painting was once a fill image under a flexible frame, which reports
    /// the painting's own cover size — as tall as the screen is wide — and a
    /// background draws at its own size centred on its host: it spilled over
    /// the strip above and painted the title, the wallet and the BACK BUTTON
    /// out of existence, on this screen alone, for a week (the owner,
    /// 2026-09-17: "There's no back button on this").
    private var backdrop: some View {
        ZStack {
            PlaceBackdrop(painting: environment?.backdropName ?? "")
            PlaceAmbience(
                shafts: [],
                motes: 18,
                moteColor: Color(hex: environment?.keyLightHex ?? "#FFE29A"),
                seed: 931
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - The floor rail

    /// Every floor at once, which the medallion grid never could show: what
    /// each pays, the stars earned (the sweep is gated on three), the energy,
    /// and the power it asks against the CAMPAIGN team — the team that fights
    /// — never the best five units owned. It opens scrolled to the floor the
    /// room shows.
    private func floorRail(_ chapter: Chapter) -> some View {
        let teamPower = store.team(store.player.campaignTeam).reduce(0) { $0 + $1.power }
        let focus = focused(chapter)?.id
        let waves = 1 + (chapter.stages.first?.laterWaves.count ?? 0)
        return ScrollViewReader { proxy in
            PlaceRail(width: Self.railWidth) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    PlaceRailLabel(labyrinth != nil ? "Levels" : "Floors")
                    Spacer(minLength: 4)
                    Text(waves == 1 ? "ONE WAVE" : "\(waves) WAVES")
                        .font(Theme.title(13))
                        .tracking(1.2)
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.top, 8)
                        .padding(.trailing, 4)
                }
                ForEach(chapter.stages) { stage in
                    floorRow(stage, isOn: stage.id == focus, teamPower: teamPower)
                }
            }
            .onAppear {
                guard let focus else { return }
                // After the first layout, or the rail has no rows to scroll to.
                DispatchQueue.main.async { proxy.scrollTo(focus, anchor: .center) }
            }
        }
        .frame(width: Self.railWidth)
    }

    /// One floor's row. A locked floor can be picked too, to see what it
    /// pays; the deck says what opens it.
    private func floorRow(_ stage: Stage, isOn: Bool, teamPower: Int) -> some View {
        let player = store.player
        let unlocked = CampaignService.isUnlocked(stage, player: player)
        let cleared = CampaignService.isCleared(stage, player: player)
        let earned = player.stageStars?[stage.id] ?? 0
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            focusedID = stage.id
        } label: {
            HStack(spacing: 8) {
                floorMedallion(stage, unlocked: unlocked, cleared: cleared, current: unlocked && !cleared)
                VStack(alignment: .leading, spacing: 3) {
                    rowPayout(stage, dim: !unlocked)
                    starPips(earned)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 3) {
                        ItemIcon(key: "energy", size: 14, glow: false)
                        Text("\(EventCalendar.energyCost(for: stage))")
                            .font(Theme.numeric(12))
                            .foregroundStyle(Theme.onGlass)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(Self.compactPower(stage.recommendedPower))
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(teamPower >= stage.recommendedPower ? Theme.onGlassSuccess : Theme.onGlassDanger)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .opacity(unlocked || isOn ? 1 : 0.72)
            .padding(.horizontal, 7)
            .frame(height: 46)
            .background(GlassRowPlate(isOn: isOn))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(stage.id)
        .accessibilityLabel("B\(stage.index), \(stage.rewards.relicGrade) star relic, \(earned) of 3 stars\(unlocked ? "" : ", locked")")
    }

    /// The floor's medallion: gold once cleared, a dark disc while open, a
    /// shade with a lock beyond, a pulsing ring on the player's floor, and the
    /// B-number ALWAYS (a cleared medallion used to trade it for a check, so
    /// a column of checks said nothing about which floor was which). The
    /// fills are a `Group`: a gold gradient and a colour will not unify in a
    /// ternary.
    private func floorMedallion(_ stage: Stage, unlocked: Bool, cleared: Bool, current: Bool) -> some View {
        ZStack {
            if current {
                Circle()
                    .strokeBorder(Theme.gold.opacity(pulse ? 0.95 : 0.3), lineWidth: 2)
                    .frame(width: 40, height: 40)
            }
            Group {
                if cleared {
                    Circle().fill(Theme.goldPlate)
                } else if unlocked {
                    Circle().fill(Color(hex: "#1E1811"))
                } else {
                    Circle().fill(Color.black.opacity(0.45))
                }
            }
            .frame(width: 32, height: 32)
            .overlay(
                Circle().strokeBorder(
                    cleared ? Theme.goldDeep : (current ? Theme.gold : Theme.onGlassDim.opacity(0.45)),
                    lineWidth: current ? 2 : 1
                )
            )
            Text("B\(stage.index)")
                .font(Theme.numeric(11.5).weight(.heavy))
                .foregroundStyle(cleared ? Theme.ink : (unlocked ? Theme.onGlass : Theme.onGlassDim))
                .lineLimit(1)
                .fixedSize()
            if !unlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(Theme.onGlassDim)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color.black.opacity(0.8)))
                    .offset(x: 12, y: 12)
            }
        }
        .frame(width: 40, height: 40)
    }

    /// What a floor pays, in a row's width: a relic dungeon's relic grade, or
    /// a hall's essence tiers as their paintings — the sure tier by its name,
    /// a chance by its odds ("[low] Low [mid] 40%").
    @ViewBuilder
    private func rowPayout(_ stage: Stage, dim: Bool) -> some View {
        let ink = dim ? Theme.onGlassDim : Theme.onGlass
        if let hall {
            HStack(spacing: 3) {
                ForEach(Self.essenceTiers, id: \.self) { tier in
                    let id = "essence_\(hall.element.rawValue)_\(tier)"
                    let chance = stage.rewards.essenceChances[id] ?? 0
                    if chance > 0 {
                        ItemIcon(key: id, size: 16, glow: false)
                        Text(chance >= 1 ? tier.capitalized : DungeonDrop.percent(chance))
                            .font(Theme.body(11).weight(.semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.trailing, 3)
                    }
                }
            }
        } else {
            HStack(spacing: 4) {
                ItemIcon(key: "relic_cache", size: 16, glow: false)
                Text("\(stage.rewards.relicGrade)★ relic")
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// The three essence tiers in ladder order, as the ids spell them; a
    /// tier's word is its id capitalised ("Low"). Strings, not labelled
    /// tuples, so a `ForEach` can key them by `\.self`.
    private static let essenceTiers = ["low", "mid", "high"]

    private func starPips(_ earned: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(index < earned ? Theme.gold : Theme.onGlassDim.opacity(0.3))
            }
        }
    }

    /// 2,200 as "2.2K" and 30,645 as "30.6K": a rail row has room for five
    /// characters of power, and the deck's bead carries the whole number.
    private static func compactPower(_ power: Int) -> String {
        guard power >= 1_000 else { return "\(power)" }
        let thousands = Double(power) / 1_000
        return thousands >= 100 ? "\(Int(thousands.rounded()))K" : String(format: "%.1fK", thousands)
    }

    // MARK: - The room

    /// The chosen floor: its title on the painting's dark top, the boss and
    /// the drops in a middle that scrolls only when the floor pays more than
    /// fits (a 393-point phone; on the CI phone's 329 the middle is 207 and a
    /// B10's plate 205: title 42, deck 46, gaps and padding 34), and
    /// the deck pinned to the foot so it is never pushed off. The width is
    /// measured with a `GeometryReader`, which is exactly the size it is
    /// proposed — never `ViewThatFits`, which lays out every candidate.
    private func floorRoom(_ chapter: Chapter, stage: Stage) -> some View {
        GeometryReader { frame in
            VStack(alignment: .leading, spacing: 8) {
                floorTitle(chapter, stage: stage)
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        bossColumn(stage)
                        floorDrops(stage)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity)
                floorDeck(stage, width: frame.size.width - 26)
            }
            .padding(.leading, 14)
            .padding(.trailing, ScreenChrome.contentPadding)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    /// "B7" carved at display size, what it pays as a carved headline with
    /// the waves and the foes' level as its eyebrow, the day's event when one
    /// is on, and the ? that holds the lore and the ladder.
    private func floorTitle(_ chapter: Chapter, stage: Stage) -> some View {
        let level = stage.enemies.first?.level ?? 0
        let eyebrow = labyrinth != nil
            ? "\(1 + stage.laterWaves.count) waves · foes Lv.\(level)"
            : "\(stage.enemies.count) foes · Lv.\(level)"
        let eventOn = labyrinth.map { EventCalendar.isActive(.doubleRelics(labyrinth: $0.id)) }
            ?? hall.map { EventCalendar.isActive(.doubleEssence($0.element)) }
            ?? false
        return HStack(alignment: .center, spacing: 12) {
            Text("B\(stage.index)")
                .font(Theme.display(30))
                .carved()
                .lineLimit(1)
                .fixedSize()
            PlaceTitle(eyebrow: eyebrow, title: floorHeadline(stage), size: 18)
            Spacer(minLength: 6)
            if eventOn {
                GlassBead(
                    text: labyrinth != nil ? "Relic ×2 today" : "Essence ×2 today",
                    systemImage: "sparkles",
                    tint: Theme.onGlassEyebrow
                )
            }
            InfoDot(title: labyrinth != nil ? "This dungeon" : "This hall") {
                dungeonInfo(chapter)
            }
        }
    }

    /// The floor's promise in five words: "5★ relic, every run" in a relic
    /// dungeon; in a hall, the tier it is sure of ("Mid essence, every
    /// clear").
    private func floorHeadline(_ stage: Stage) -> String {
        let rewards = stage.rewards
        if let hall {
            let sure = Self.essenceTiers.first { tier in
                (rewards.essenceChances["essence_\(hall.element.rawValue)_\(tier)"] ?? 0) >= 1
            }
            if let sure { return "\(sure.capitalized) essence, every clear" }
        }
        return rewards.relicChance >= 1
            ? "\(rewards.relicGrade)★ relic, every run"
            : "\(rewards.relicGrade)★ relic, \(DungeonDrop.percent(rewards.relicChance)) of runs"
    }

    /// Behind the ?: the place's lore, which left the hub card, then what the
    /// floors pay by floor, read off the tables, and how a floor is swept.
    private func dungeonInfo(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chapter.summary)
            if let hall {
                Text(hallDrops(hall))
                    .foregroundStyle(Theme.goldDim)
            } else {
                Text(labyrinthLadder(chapter))
                    .foregroundStyle(Theme.goldDim)
            }
            Text("Three stars on a \(labyrinth != nil ? "level" : "floor") let you sweep it: the same pay, no battle.")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(Theme.body(11))
        .foregroundStyle(Theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// What a relic dungeon pays by level, read off its levels rather than
    /// written by hand: the grade ladder ("3★ on B1–3 · … · 6★ on B10"), the
    /// level whetstones and the scroll start on, and the last level's awakened
    /// relic and boon cache. The screen used to print the ladder as one line
    /// that wrapped "on B10" onto a line of its own, and said nothing of the
    /// whetstones, the scroll, the awakened relic or the boon cache.
    private func labyrinthLadder(_ chapter: Chapter) -> String {
        var groups: [(first: Stage, last: Stage)] = []
        for stage in chapter.stages {
            if let group = groups.last, group.last.rewards.relicGrade == stage.rewards.relicGrade {
                groups[groups.count - 1].last = stage
            } else {
                groups.append((first: stage, last: stage))
            }
        }
        let ladder = groups.map { group -> String in
            let span = group.first.index == group.last.index
                ? "B\(group.first.index)"
                : "B\(group.first.index)–\(group.last.index)"
            return "\(group.first.rewards.relicGrade)★ on \(span)"
        }
        var line = "Every run pays a relic of the dungeon's \(labyrinth?.sets.count ?? 0) sets: "
            + ladder.joined(separator: " · ") + "."
        if let stones = chapter.stages.first(where: { !($0.rewards.stoneChances ?? [:]).isEmpty }) {
            line += " Whetstones from B\(stones.index)."
        }
        if let scrolled = chapter.stages.first(where: { !$0.rewards.scrollChances.isEmpty }),
           let raw = scrolled.rewards.scrollChances.keys.sorted().first,
           let scroll = ScrollType(rawValue: raw) {
            line += " A \(scroll.displayName) now and then from B\(scrolled.index)."
        }
        if let top = chapter.stages.first(where: { $0.rewards.awakenedChance != nil }),
           let chance = top.rewards.awakenedChance {
            line += " B\(top.index)'s relic is awakened \(DungeonDrop.percent(chance)) of runs"
            if let boon = top.rewards.boonCacheChance {
                line += ", and it leaves a \(top.rewards.boonCacheGrade ?? 5)★ boon cache \(DungeonDrop.percent(boon)) of runs"
            }
            line += "."
        }
        return line
    }

    /// The boss of the FOCUSED floor, so its level is that floor's: the card
    /// was built from the chapter's last stage and read the Colossus at
    /// Lv.50 and Apep at Lv.60 over a B1 of Lv.14 (run 211). Only this floor
    /// is built, never one per row. A face on the painted floor, not a card:
    /// a cream name strip on glass is a slab, so the name is carved under it.
    private func bossColumn(_ stage: Stage) -> some View {
        let spawn = stage.laterWaves.last?.first ?? stage.enemies.last
        let boss = spawn.flatMap { StageDatabase.buildEnemies(spawns: [$0]).first }
        return VStack(spacing: 6) {
            Text("THE BOSS")
                .font(Theme.title(13))
                .tracking(1.0)
                .foregroundStyle(Theme.onGlassEyebrow)
                .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                .lineLimit(1)
                .fixedSize()
            if let boss {
                UnitPortraitTile(unit: boss, size: 84)
                    .background(alignment: .bottom) { PaintedFloorPool() }
                // "Colossus", not "Colossus, the Statue That Stood Up".
                Text(boss.name.split(separator: ",", maxSplits: 1).first.map { String($0) } ?? boss.name)
                    .font(Theme.title(13))
                    .carved(glow: false)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 96)
    }

    /// The floor's drops as tiles on one glass plate — they follow the floor
    /// chosen, as Star Rail's Caverns show a level's own rewards — then the
    /// dungeon's six sets as their stones with their names, or, in a hall,
    /// what an awakening spends of this element by grade. The first clear's
    /// divinity is the Drops header's accessory and the awakened relic's
    /// chance the sets header's, so a B10 keeps one row of six tiles.
    private func floorDrops(_ stage: Stage) -> some View {
        let firstClear: String? = !CampaignService.isCleared(stage, player: store.player) && stage.rewards.firstClearDivinity > 0
            ? "+\(stage.rewards.firstClearDivinity) first clear"
            : nil
        return VStack(alignment: .leading, spacing: 7) {
            GlassSectionHeader(title: "Drops", accessory: firstClear, accessoryItemKey: firstClear == nil ? nil : "divinity")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 66), spacing: 4)], alignment: .leading, spacing: 6) {
                ForEach(dropTiles(stage)) { drop in
                    RewardTile(key: drop.key, title: drop.title, amount: drop.amount, stars: drop.stars,
                               size: 44, onGlass: true)
                }
            }
            if let labyrinth {
                GlassSectionHeader(
                    title: "One of \(labyrinth.sets.count) sets",
                    accessory: stage.rewards.awakenedChance.map { "\(DungeonDrop.percent($0)) awakened" }
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 5) {
                    ForEach(labyrinth.sets) { relicSet in
                        LabyrinthSetChip(set: relicSet)
                    }
                }
            } else if let hall {
                GlassSectionHeader(title: "An awakening spends")
                HStack(spacing: 6) {
                    ForEach([3, 4, 5], id: \.self) { stars in
                        awakenChip(hall, stars: stars)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GlassPlate(radius: Theme.cornerRadius))
    }

    /// What a floor pays, in the order a farmer reads it: the relic, the
    /// essences low to high, the whetstones, the scroll, the boon cache, the
    /// drachma — each with today's event in its amount. An essence that is
    /// sure drops one or two (`CampaignService` rolls `1...2`).
    private func dropTiles(_ stage: Stage) -> [DungeonDrop] {
        let rewards = stage.rewards
        let boosts = EventCalendar.boosts(for: stage)
        var drops: [DungeonDrop] = []
        if rewards.relicChance > 0 {
            drops.append(DungeonDrop(
                id: "relic", key: "relic_cache", title: "Relic",
                amount: rewards.relicChance >= 1 ? "×\(max(1, boosts.relicRolls))" : DungeonDrop.percent(rewards.relicChance),
                stars: rewards.relicGrade
            ))
        }
        let each = max(1, boosts.essence)
        for tier in Self.essenceTiers {
            for (id, chance) in rewards.essenceChances.sorted(by: { $0.key < $1.key })
            where chance > 0 && id.hasSuffix("_" + tier) {
                drops.append(DungeonDrop(
                    id: id, key: id, title: tier.capitalized,
                    amount: chance >= 1 ? "\(each)–\(2 * each)" : DungeonDrop.percent(chance),
                    stars: nil
                ))
            }
        }
        let stones = (rewards.stoneChances ?? [:]).sorted {
            (RelicStone.from(id: $0.key)?.tier.rawValue ?? 0) < (RelicStone.from(id: $1.key)?.tier.rawValue ?? 0)
        }
        for (id, chance) in stones where chance > 0 {
            drops.append(DungeonDrop(
                id: id, key: id, title: RelicStone.from(id: id)?.tier.displayName ?? "Stone",
                amount: DungeonDrop.percent(chance), stars: nil
            ))
        }
        for (raw, chance) in rewards.scrollChances.sorted(by: { $0.key < $1.key }) where chance > 0 {
            guard let scroll = ScrollType(rawValue: raw) else { continue }
            drops.append(DungeonDrop(
                id: raw, key: ItemArt.key(scroll: scroll), title: DungeonDrop.shortName(scroll),
                amount: chance >= 1 ? "×1" : DungeonDrop.percent(chance), stars: nil
            ))
        }
        if let chance = rewards.boonCacheChance, chance > 0 {
            let grade = rewards.boonCacheGrade ?? 5
            drops.append(DungeonDrop(
                id: "boon", key: "boon_cache_\(grade)", title: "Boon",
                amount: DungeonDrop.percent(chance), stars: grade
            ))
        }
        drops.append(DungeonDrop(
            id: "drachma", key: "drachma", title: "Drachma",
            amount: Int(Double(rewards.drachma) * boosts.drachma).formatted(), stars: nil
        ))
        return drops
    }

    /// One grade's awakening bill in this hall's element, by the essences'
    /// paintings: "3★ [low] 10 [mid] 5". It replaced a seven-line paragraph
    /// of gold body text (run 211, frame 10); the paragraph is behind the ?.
    /// Only this element's tiers: the Magic essences come from elsewhere.
    private func awakenChip(_ hall: DungeonDatabase.Hall, stars: Int) -> some View {
        let asked = UnitDatabase.awakeningCost(element: hall.element, naturalStars: stars)
        let prefix = "essence_\(hall.element.rawValue)_"
        return HStack(spacing: 4) {
            Text("\(stars)★")
                .font(Theme.numeric(12))
                .foregroundStyle(Theme.onGlassEyebrow)
                .lineLimit(1)
                .fixedSize()
            ForEach(Self.essenceTiers, id: \.self) { tier in
                if let count = asked[prefix + tier], count > 0 {
                    ItemIcon(key: prefix + tier, size: 16, glow: false)
                    Text("\(count)")
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.onGlass)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .overlay(Capsule().strokeBorder(Theme.goldDim.opacity(0.7), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }

    /// What a hall pays, read off its floors rather than written by hand,
    /// so the words follow the tables: the floors grouped by the tiers they
    /// drop — Low on the first floors, Mid, then High on the top — each tier
    /// with its odds (sure, or the span a chance climbs across the group),
    /// the relic cap, and which grade's awakening spends which tier, read off
    /// `UnitDatabase.awakeningCost`. It said "Drops Mid Ember Essence" and
    /// nothing of the High, and the owner asked whether Mid was all there
    /// was (2026-09-17); the ladder that answered him is
    /// `DungeonDatabase.hallEssenceChances`, and this line is its mirror. It
    /// lives behind the room's ? since 2026-09-22; the room shows the same
    /// facts as tiles and chips.
    private func hallDrops(_ hall: DungeonDatabase.Hall) -> String {
        guard let last = hall.floors.last else { return "" }
        let prefix = "essence_\(hall.element.rawValue)_"
        let tiers: [(id: String, word: String)] = [("low", "Low"), ("mid", "Mid"), ("high", "High")]
        func chance(_ tier: String, on floor: Stage) -> Double {
            floor.rewards.essenceChances[prefix + tier] ?? 0
        }
        func percent(_ value: Double) -> String {
            "\(Int((value * 100).rounded()))%"
        }
        // The odds across a group of floors: sure, one figure, or a span.
        func odds(_ from: Double, _ to: Double) -> String {
            if from >= 1 && to >= 1 { return "sure" }
            if from == to { return percent(from) }
            if from < 1 && to < 1 { return "\(Int((from * 100).rounded()))–\(percent(to))" }
            return "\(from >= 1 ? "sure" : percent(from))–\(to >= 1 ? "sure" : percent(to))"
        }
        // The tiers a floor drops, in ladder order.
        func dropped(_ floor: Stage) -> [String] {
            tiers.map { $0.id }.filter { chance($0, on: floor) > 0 }
        }
        // Consecutive floors that drop the same tiers are one group: "B1–2".
        var groups: [(first: Stage, last: Stage)] = []
        for floor in hall.floors {
            if let group = groups.last, dropped(group.last) == dropped(floor) {
                groups[groups.count - 1].last = floor
            } else {
                groups.append((first: floor, last: floor))
            }
        }
        let byFloor = groups.map { group -> String in
            let span = group.first.index == group.last.index
                ? "B\(group.first.index)"
                : "B\(group.first.index)–\(group.last.index)"
            let paid = dropped(group.first)
            let lines = tiers.filter { paid.contains($0.id) }.map { tier -> String in
                "\(tier.word) (\(odds(chance(tier.id, on: group.first), chance(tier.id, on: group.last))))"
            }
            return "\(span) \(lines.joined(separator: " and "))"
        }
        // Which grade spends which tier of this element, off the recipe.
        let byGrade = [3, 4, 5].map { stars -> String in
            let asked = UnitDatabase.awakeningCost(element: hall.element, naturalStars: stars)
            let words = tiers.filter { asked[prefix + $0.id] != nil }.map { $0.word }
            return "a \(stars)★ \(words.joined(separator: " and "))"
        }
        return "\(hall.element.displayName) Essence by floor — \(byFloor.joined(separator: "; ")). "
            + "Relics up to \(last.rewards.relicGrade)★. An awakening spends it by natural grade — "
            + "\(byGrade.joined(separator: ", ")) — with Magic essence from the campaign and the Titans. Every clear pays."
    }

    // MARK: - The deck

    /// The foot of the room: the team's power against the floor's (dropped
    /// once the floor can be swept, which already asks for it), Team & runs
    /// (the briefing, where the team and the auto-repeat are chosen), Sweep
    /// once the floor is three-starred, and Fight — ONE tap from the rail to
    /// the battle, with the campaign team. Every reason Fight can be dead is
    /// its own title: "Clear B6 first", "Needs 8 energy"; an empty team makes
    /// it "Choose a team", which opens the briefing. A dead button is dim
    /// glass, never the cream disabled plate — that is a cream slab on the
    /// painting.
    ///
    /// `width` is the room's, measured; the wide "Team & runs" plate is drawn
    /// only where it fits (a Pro Max), the 66-point TEAM glyph elsewhere. On
    /// the CI phone the room is 512 wide: 440 without a sweep, 482 with one.
    private func floorDeck(_ stage: Stage, width: CGFloat) -> some View {
        let team = store.team(store.player.campaignTeam)
        let power = team.reduce(0) { $0 + $1.power }
        let unlocked = CampaignService.isUnlocked(stage, player: store.player)
        let cost = EventCalendar.energyCost(for: stage)
        let hasEnergy = store.player.wallet.energy >= cost
        let canSweep = unlocked && SweepService.canSweep(stage, player: store.player)
        let runs = max(1, min(SweepService.maximumRuns, SweepService.affordableRuns(stage, player: store.player)))
        let strong = power >= stage.recommendedPower
        let roomy = width >= (canSweep ? 620 : 590)
        let fightTitle: String
        if !unlocked {
            fightTitle = "Clear B\(max(1, stage.index - 1)) first"
        } else if team.isEmpty {
            fightTitle = "Choose a team"
        } else if !hasEnergy {
            fightTitle = "Needs \(cost) energy"
        } else {
            fightTitle = "Fight — \(cost) energy"
        }
        let fightLive = unlocked && (team.isEmpty || hasEnergy)
        return HStack(spacing: 10) {
            if !canSweep {
                GlassBead(
                    text: "\(power.formatted()) / \(stage.recommendedPower.formatted())",
                    systemImage: strong ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                    tint: strong ? Theme.onGlassSuccess : Theme.onGlassDanger,
                    height: 30
                )
            }
            Spacer(minLength: 6)
            if roomy {
                PrimaryButton(title: "Team & runs", systemImage: "person.2.fill", isEnabled: unlocked, style: .glass) {
                    selectedStage = stage
                }
                .frame(maxWidth: 190)
            } else {
                teamButton(stage, enabled: unlocked)
            }
            if canSweep {
                PrimaryButton(title: "Sweep ×\(runs)", systemImage: "forward.fill", isEnabled: hasEnergy, style: .glass) {
                    sweep(stage, runs: runs)
                }
                .frame(maxWidth: 170)
            }
            PrimaryButton(
                title: fightTitle,
                systemImage: team.isEmpty ? "person.2.fill" : "play.fill",
                isEnabled: fightLive,
                style: fightLive ? .painted : .glass
            ) {
                if team.isEmpty {
                    selectedStage = stage
                } else {
                    launch(stage, runs: 1)
                }
            }
            .frame(maxWidth: 250)
        }
    }

    /// Team & runs as a glyph plate the height of the buttons beside it, for
    /// a room too narrow for the words.
    private func teamButton(_ stage: Stage, enabled: Bool) -> some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            selectedStage = stage
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .black))
                Text("TEAM")
                    .font(Theme.title(13))
                    .tracking(1.0)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(enabled ? Color(hex: "#FFE9A8") : Theme.onGlassDim)
            .frame(width: 66, height: PrimaryButton.height)
            .background(GlassPlate(radius: Theme.tightCorner))
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel("Team and runs")
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

// MARK: - Shared by the rooms

/// One thing a floor pays, as its `RewardTile` draws it: the painted item's
/// key, a one-word title (the tier for an essence or a stone, the kind
/// otherwise, so no tile's name wraps and the row stays one line tall), the
/// amount or the chance on the socket's corner, and the grade's stars.
/// Private to the Labyrinth's rooms; the name is unique in the tree.
private struct DungeonDrop: Identifiable {
    let id: String
    let key: String
    let title: String
    let amount: String
    let stars: Int?

    /// A chance as the tile prints it: 0.25 as "25%".
    static func percent(_ chance: Double) -> String {
        "\(Int((chance * 100).rounded()))%"
    }

    /// A scroll's name without the word "Scroll": "Mystical", "Fire". The
    /// tile's picture is the scroll.
    static func shortName(_ scroll: ScrollType) -> String {
        scroll.displayName.replacingOccurrences(of: " Scroll", with: "")
    }
}

/// A relic set on dark glass: its painted stone and its name beside it, in a
/// dark capsule with a gold rim that fills its grid column. The dungeon's six
/// sets on the drops plate. It is the glass twin of the cream chips the room
/// had, and it is here rather than in Glass.swift because nothing else draws
/// it yet (phase B's helper set did not include one).
private struct LabyrinthSetChip: View {
    let set: RelicSet

    var body: some View {
        HStack(spacing: 5) {
            RelicSetEmblem(set: set, size: 18)
            Text(set.displayName)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .overlay(Capsule().strokeBorder(Theme.goldDim.opacity(0.7), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }
}

/// A dark pool on the painted floor under a face — the dungeon's boss, a
/// Titan — so the tile stands in the room rather than floating over it. It
/// is a background, so it is drawn wider than the tile without being measured.
private struct PaintedFloorPool: View {
    var body: some View {
        Ellipse()
            .fill(RadialGradient(colors: [Color.black.opacity(0.6), .clear], center: .center,
                                 startRadius: 2, endRadius: 64))
            .frame(width: 136, height: 36)
            .offset(y: 16)
            .allowsHitTesting(false)
    }
}

private extension View {
    /// The frame of an art card on the Labyrinth's hub: the card's full
    /// share of the row, clipped to a rounded rectangle with the glass rim,
    /// a soft shadow off the cream ground, and the whole card as the tap
    /// target (the painting declines hits, and a spacer takes none).
    func labyrinthCardFrame() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        return self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.glassRim, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .contentShape(shape)
    }
}
