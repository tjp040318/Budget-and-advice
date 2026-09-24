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
    /// Titan (`raid`, a `RaidEncounter.id`): the Unwrapped King is the last
    /// of the five and has the longest name (2026-09-22).
    init(opening: Wing = .dungeons, raid: String? = nil) {
        _wing = State(initialValue: opening)
        _selectedRaidID = State(initialValue: raid)
    }

    /// The building's rooms. A five-way choice, so it is `BarSegments` in the
    /// strip rather than a row of capsules above the content. The fifth, the
    /// Hidden Shrines (2026-09-23; Docs/SHRINES.md), is `ShrinesWing`.
    enum Wing: Hashable {
        case dungeons
        case halls
        case tower
        case raids
        case shrines
    }

    private let wings: [(value: Wing, title: String)] = [
        (value: .dungeons, title: "Dungeons"),
        (value: .halls, title: "Halls"),
        (value: .tower, title: "Tower"),
        (value: .raids, title: "Titans"),
        (value: .shrines, title: "Shrines"),
    ]

    /// The Titan whose room is open; nil until one is picked, which reads as
    /// the first.
    @State private var selectedRaidID: String?

    /// The Titans' rail: wide enough that every Titan's name stands on TWO
    /// lines at the title floor of 13 in the 146 points beside its seal —
    /// the widest lines are "The King Who Was" (128 in Cinzel) and
    /// "Swallows the Sun" (126). Run 224's frame 39 had the rail at 204 with
    /// the element's word as an eyebrow over each name: the Serpent and the
    /// King ran to three lines, the five rows came to 386 points against the
    /// 303 the CI phone gives the rail, and the rail opened scrolled past
    /// Ember and Gale with nothing to say they were there. Now the element
    /// rides the seal and the rows are 46 points, so all five stand whole and
    /// unscrolled (258 points). At 168 the rail read "THE KING WHO WAS NEVER
    /// WEIG…" (run 211), an ellipsis in a menu.
    private static let titanRailWidth: CGFloat = 222

    /// The strip's second line. Five segments leave the title's column 147
    /// points on an iPhone 16 Pro with a new wallet and 126 with a veteran's
    /// ("158/158 · 9,999 · 999K"), measured with the bundled faces, and the
    /// line never truncates — so every wing's is 116 points or under at
    /// Manrope 11 ("100/100 floors climbed"; the Shrines' longest is "Hidden ·
    /// an hour each", 110). The four wings' longer lines ("5 Titans · graded F to SSS,
    /// paying aether" was 205) went when the Shrines segment came (2026-09-23);
    /// what they said is on the rooms themselves.
    private var subtitle: String {
        switch wing {
        case .dungeons: return "A relic every run"
        case .halls: return "\(DungeonDatabase.halls.count) halls · the essences"
        case .tower:
            let cleared = TowerService.clearedFloor(player: store.player)
            return "\(cleared)/\(DungeonDatabase.towerFloors) floors climbed"
        case .raids:
            return "\(StageDatabase.raids.count) Titans · F to SSS"
        case .shrines:
            return ShrinesWing.subtitle(player: store.player)
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
        case .shrines:
            ShrinesWing()
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
        let standing = dungeonStanding(labyrinth, cleared: cleared).uppercased()
        return Button {
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
                    // Where the player stands, not the wing's own name said
                    // three times over (run 216): "NEXT B7 · 5★ RELIC". Its
                    // figures in Manrope: Cinzel's 1 is a Roman I, and
                    // "NEXT B1" read "NEXT BI" (run 221).
                    Text.inscribed(standing, letters: Theme.title(13), digits: Theme.numeric(12.6))
                        .tracking(1.2)
                        .foregroundStyle(Theme.onGlassEyebrow)
                        .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                        .lineLimit(1)
                        .fixedSize()
                    // Two lines, shrinking to the title floor before either
                    // is cut: "Necropolis of the Unwrapped King" is the long
                    // one. The flat gold keeps the second line as light as
                    // the first (run 216 carved it in dark bronze). Every
                    // card reserves both lines, so the three eyebrows share
                    // one line: the Lair's one-line name dropped its eyebrow
                    // 24 points below the others' (run 221).
                    Text(labyrinth.name)
                        .font(Theme.display(18))
                        .carved(multiline: true)
                        .lineLimit(2, reservesSpace: true)
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
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("\(labyrinth.name), \(cleared) of \(labyrinth.levels.count) levels cleared")
    }

    /// The card's eyebrow, read off the dungeon's levels: the next level and
    /// the grade it pays ("Next B7 · 5★ relic"; B1 for a dungeon not yet
    /// entered), or that every level has fallen. `campaignProgress` holds the
    /// highest level cleared.
    private func dungeonStanding(_ labyrinth: DungeonDatabase.Labyrinth, cleared: Int) -> String {
        guard let next = labyrinth.levels.first(where: { $0.index == cleared + 1 }) else {
            return "All \(labyrinth.levels.count) cleared"
        }
        return "Next B\(next.index) · \(next.rewards.relicGrade)★ relic"
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
            Text(Self.setNameLines(sets))
                .font(Theme.body(11))
                .foregroundStyle(Theme.onGlassDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The set names as two lines of three, every card alike. One line
    /// wrapped where it ran out on run 217's frame 15 and began the second
    /// with its separator ("· Chains"). The widest half of any dungeon is
    /// 135 points in Manrope at 11, inside the narrowest card's 207; the
    /// space before each dot is non-breaking, so a line that ever did wrap
    /// would end "Titanfall ·" and never start with the dot.
    private static func setNameLines(_ sets: [RelicSet]) -> String {
        let names = sets.map(\.displayName)
        let split = names.count > 3 ? (names.count + 1) / 2 : names.count
        let lines = [names.prefix(split), names.dropFirst(split)].filter { !$0.isEmpty }
        return lines.map { $0.joined(separator: "\u{00A0}· ") }.joined(separator: "\n")
    }

    // MARK: - A hall

    /// A hall as a tall art card, five across the frame the way the genre
    /// draws its Hall of Magic: the hall's painting, the High essence it is
    /// farmed for painted large in its element's light, "HALL OF" over the
    /// element's word carved, and the three tiers it pays as their paintings. The
    /// 30-point SF Symbol in a tinted circle it replaces was the app-skeleton
    /// look, and the three tier paintings say what the old name line and
    /// summary said in words.
    private func hallCard(_ hall: DungeonDatabase.Hall) -> some View {
        let cleared = store.player.campaignProgress[hall.id] ?? 0
        let doubled = EventCalendar.isActive(.doubleEssence(hall.element))
        let prefix = "essence_\(hall.element.rawValue)_"
        // "HALL OF" as an eyebrow and the element's word carved on ONE line,
        // so every card has the same stack: "Hall of Tides" fitted one line
        // and "Hall of Radiance" wrapped to two, and the five essences stood
        // at two heights (run 216).
        let named = hall.name.hasPrefix("Hall of ")
        let word = (named ? String(hall.name.dropFirst(8)) : hall.name).uppercased()
        let eyebrow = named ? "HALL OF" : "HALL"
        return Button {
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
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    // The element's light as a glow round the essence, not a
                    // wash over the foot: radiance's pale gold lifted the
                    // black foot to khaki under the carved name (run 216).
                    ItemIcon(key: prefix + "high", size: 60, glow: true)
                        .background(
                            Circle()
                                .fill(RadialGradient(colors: [hall.element.color.opacity(0.35), .clear],
                                                     center: .center, startRadius: 4, endRadius: 58))
                                .frame(width: 116, height: 116)
                                .blendMode(.plusLighter)
                                .allowsHitTesting(false)
                        )
                    VStack(spacing: 1) {
                        Text(eyebrow)
                            .font(Theme.title(13))
                            .tracking(2.0)
                            .foregroundStyle(Theme.onGlassEyebrow)
                            .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                            .lineLimit(1)
                            .fixedSize()
                        Text(word)
                            .font(Theme.title(15))
                            .carved(glow: false)
                            .lineLimit(1)
                            .minimumScaleFactor(Theme.titleFloor / 15)
                    }
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
        .buttonStyle(GamePressStyle(.plate))
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
            // The tower crops its painting higher than the room of the same
            // place: the Sand Stair borrows the Vault's corridor, and on
            // run 216 the Tower read as the Vault with other plates.
            placeGround(environment, focus: environment.towerFocus,
                        motes: Color(hex: environment.roomMoteHex), seed: 952)
        }
    }

    /// A place's painting under dark scrims with its motes over it: the
    /// ground of the Tower and the Titans. `PlaceBackdrop` is exactly the size
    /// it is given, so as a `.background` it can never spill over the strip
    /// the way the dungeon levels' painting did for a week. A dark painting
    /// (`roomIsDark`) takes lighter scrims: the ones tuned for a bright
    /// painting turned the Serpent Deep into a black panel (run 216).
    private func placeGround(_ environment: BattleEnvironment?, focus: UnitPoint, motes: Color, seed: UInt64) -> some View {
        let dark = environment?.roomIsDark ?? false
        return ZStack {
            PlaceBackdrop(
                painting: environment?.backdropName ?? "",
                focus: focus,
                topScrim: dark ? 0.3 : 0.55,
                footScrim: dark ? 0.45 : 0.62
            )
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
                Self.floorNumber("F", floor)
                PlaceTitle(
                    eyebrow: "Lv.\(DungeonDatabase.towerLevel(floor: floor)) · \(DungeonDatabase.towerGrade(floor: floor))★ foes",
                    title: tier.name,
                    size: 18
                )
                Spacer(minLength: 0)
            }
            // The foes as the dungeon room draws its boss — large faces with
            // their names under them — and the plate the column's full
            // height, so it ends on the climb panel's line. At 60 points with
            // no names the plate was half empty glass and ended 90 points
            // short of its neighbour (run 216).
            VStack(alignment: .leading, spacing: 7) {
                GlassSectionHeader(title: warden ? "The warden and two" : "\(foes.count) foes")
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(foes.enumerated()), id: \.offset) { index, foe in
                        VStack(spacing: 4) {
                            UnitPortraitTile(unit: foe, size: 72, tag: warden && index == 0 ? "Warden" : nil)
                            Text(Self.bareName(foe.name))
                                .font(Theme.body(11).weight(.semibold))
                                .foregroundStyle(Theme.onGlass)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(width: 84)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                GlassSectionHeader(title: "What it pays")
                HStack(alignment: .top, spacing: 6) {
                    ForEach(towerDrops(stage)) { drop in
                        RewardTile(key: drop.key, title: drop.title, amount: drop.amount, stars: drop.stars,
                                   size: 44, onGlass: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassPlate())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A name before its epithet: "Colossus", not "Colossus, the Statue That
    /// Stood Up". The full name is on the battle's plates.
    private static func bareName(_ name: String) -> String {
        name.split(separator: ",", maxSplits: 1).first.map { String($0) } ?? name
    }

    /// A floor's number carved at display size — the tower's "F12" — the
    /// letter in Cinzel and the figures in Manrope (`Text.inscribed`):
    /// Cinzel's 1 is a Roman I, and "F1" read "FI" (run 221).
    fileprivate static func floorNumber(_ letter: String, _ number: Int) -> some View {
        Text.inscribed("\(letter)\(number)", letters: Theme.display(30), digits: Theme.numeric(29).weight(.heavy))
            .carved()
            .lineLimit(1)
            .fixedSize()
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
        let next = TowerService.nextMilestone(player: store.player)
        let previous = DungeonDatabase.towerMilestones.last(where: { $0 <= cleared }) ?? 0
        return VStack(alignment: .leading, spacing: 7) {
            GlassSectionHeader(title: "The climb", accessory: "\(cleared) of \(DungeonDatabase.towerFloors)")
            milestoneTrack(cleared: cleared, next: next)
            // How far along the way to the next milestone: the five pills
            // alone read as a segmented control (run 216).
            if let next {
                GlassMeter(value: Double(cleared - previous), maximum: Double(max(1, next - previous)), height: 5)
            }

            if let next, let reward = DungeonDatabase.towerMilestoneReward(floor: next) {
                let togo = next - cleared
                GlassSectionHeader(title: "Floor \(next) pays", accessory: togo == 1 ? "1 floor to go" : "\(togo) floors to go")
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(Self.grants(in: reward).enumerated()), id: \.offset) { _, grant in
                        RewardTile(key: ItemArt.key(for: grant), amount: Self.shortAmount(grant),
                                   stars: ItemArt.stars(for: grant), size: 40, showsTitle: false, onGlass: true)
                    }
                }
            }

            // The team sits under what the climb pays and the button alone
            // at the foot: a 90-point gap of empty glass stood between the
            // pay and the team (run 216).
            GlassSectionHeader(
                title: "Your team",
                accessory: stage.map { "\(power.formatted()) / \($0.recommendedPower.formatted())" },
                accessoryTint: stage.map { power >= $0.recommendedPower } == true ? Theme.onGlassSuccess : Theme.onGlassDanger
            )
            Button {
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
            .buttonStyle(GamePressStyle(.plate))
            .accessibilityLabel("Your team, \(team.count) of 5")

            Spacer(minLength: 0)

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
    /// the player, and the NEXT one wears a gold rim and a glow with its
    /// number in pale gold, so the track says both how far up the hundred
    /// the player is and what he is climbing toward.
    private func milestoneTrack(cleared: Int, next: Int?) -> some View {
        HStack(spacing: 4) {
            ForEach(DungeonDatabase.towerMilestones, id: \.self) { floor in
                let reached = cleared >= floor
                let aimed = floor == next
                Text("\(floor)")
                    .font(Theme.numeric(11.5).weight(.bold))
                    .foregroundStyle(reached ? Theme.ink : (aimed ? Color(hex: "#FFE9A8") : Theme.onGlassDim))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(reached ? AnyShapeStyle(Theme.goldPlate) : AnyShapeStyle(Color.black.opacity(0.4)))
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            reached ? Color.clear : (aimed ? Theme.gold : Theme.glassRim.opacity(0.6)),
                            lineWidth: aimed ? 1.4 : 0.8
                        )
                    )
                    .shadow(color: aimed ? Theme.gold.opacity(0.55) : .clear, radius: 5)
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
            // The five rows fit the rail on the CI phone and stand unscrolled
            // (`titanRailWidth`). On a shorter phone the rail still opens on
            // the Titan whose room is open with a WHOLE row at its top
            // (`WholeRowRail`; run 217 opened on the Gale Titan cut through
            // its eyebrow). The label is pinned above the scroll: inside it,
            // the scroll to the chosen Titan carried it off the top and cut
            // the first row on the strip's edge (run 216).
            VStack(spacing: 0) {
                LabyrinthRailHead(title: "Titans")
                WholeRowRail(width: Self.titanRailWidth, items: StageDatabase.raids, focus: chosen?.id) { raid in
                    titanTile(raid, isOn: raid.id == chosen?.id)
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
                chosen?.environment,
                focus: chosen?.environment.roomFocus ?? .center,
                motes: chosen.map { RaidGradeService.element(of: $0).color } ?? Theme.gold,
                seed: 951
            )
        }
    }

    /// One Titan on the rail: its seal — the best grade's stamp wearing the
    /// Titan's element, or before the first grade the dashed ring that is
    /// the element — and its name in Cinzel at the title floor, on the
    /// summon rail's row plate. The element's WORD was an eyebrow over the
    /// name until run 224, and with it the Serpent and the King ran to three
    /// lines and the rail to 386 points; the room's own eyebrow ("Titan of
    /// Umbra") says the word. Every name stands on two lines at this width;
    /// three are allowed, never an ellipsis, should a longer one come.
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
                titanRailSeal(best, element: element, cleared: cleared)
                // The name takes the rest of the row itself: a Spacer after
                // it took the stack's 8-point gap again, out of the name.
                Text(Self.railName(raid.name))
                    .font(Theme.title(13))
                    .foregroundStyle(isOn ? Color(hex: "#FFF1C2") : Theme.onGlass)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(GlassRowPlate(isOn: isOn))
            .contentShape(Rectangle())
        }
        // A row of the Titans' scrolling rail: quiet, its tap kept
        // in the action, on a finished tap (2026-09-24).
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel("\(raid.name), \(element.displayName) Titan\(best.map { ", best grade \($0.label)" } ?? "")\(cleared ? ", fallen" : "")")
    }

    /// A Titan's name for the rail, its last two words bound by a no-break
    /// space so no name ends on a word alone: at this width "The King Under
    /// the" fits a line and left "Ice" under it.
    private static func railName(_ name: String) -> String {
        guard let last = name.range(of: " ", options: .backwards) else { return name }
        return name.replacingCharacters(in: last, with: "\u{00A0}")
    }

    /// The seal on a Titan's rail row, 36 points. A graded Titan's stamp
    /// wears its element as a disc on its lower right, clear of the grade's
    /// letters; an ungraded one's dashed ring already holds the element's
    /// glyph. A gold check stands on the seal's shoulder once the Titan has
    /// fallen — it was the end of the eyebrow the element's word is gone
    /// from. Both stay inside the row's 5-point padding.
    private func titanRailSeal(_ grade: RaidGrade?, element: Element, cleared: Bool) -> some View {
        titanSeal(grade, element: element, size: 36)
            .overlay(alignment: .bottomTrailing) {
                if grade != nil {
                    TitanElementPip(element: element)
                        .offset(x: 5, y: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if cleared {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.onGlassGold)
                        .shadow(color: .black.opacity(0.8), radius: 1)
                        .offset(x: 4, y: -3)
                        .allowsHitTesting(false)
                }
            }
    }

    /// The best grade's stamp, or — before the first grade — a dim dashed
    /// ring holding the Titan's element. `RaidGradeStamp`'s circled dash is
    /// iOS's remove control, and four rows of five read as delete buttons
    /// (run 216).
    @ViewBuilder
    private func titanSeal(_ grade: RaidGrade?, element: Element, size: CGFloat) -> some View {
        if let grade {
            RaidGradeStamp(grade: grade, size: size)
        } else {
            UngradedTitanSeal(element: element, size: size)
        }
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
                InfoDot(title: raid.name, seated: true) {
                    Text(raid.summary)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    // The Titan stands on the floor with its name carved
                    // under it, as the dungeon's boss does; run 216 had the
                    // card alone over the void.
                    VStack(spacing: 6) {
                        if let titan {
                            UnitPortraitTile(unit: titan, size: 84)
                                .background(alignment: .bottom) { PaintedFloorPool() }
                            Text(Self.bareName(titan.name))
                                .font(Theme.title(13))
                                .carved(glow: false, multiline: true)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
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
    /// for, the aether in hand after its word, and what the grade aimed at
    /// PAYS — the raid is farmed for it, and run 216's room ended in two bare
    /// numbers with nothing saying what a grade brings.
    private func raidGradeRow(_ raid: RaidEncounter, profile: RaidBossProfile) -> some View {
        let best = RaidGradeService.bestGrade(for: raid, player: store.player)
        let element = RaidGradeService.element(of: raid)
        let elemental = Aether.id(for: element)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                titanSeal(best, element: element, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text((best.map { "Best grade \($0.label)" } ?? "Not yet graded").uppercased())
                            .font(Theme.title(13))
                            .tracking(1.0)
                            .foregroundStyle(Theme.onGlassEyebrow)
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: 6)
                        // The aether the player holds, after its word, on the
                        // eyebrow's line so the target keeps the plate's
                        // width: two bare numbers by 16-point glyphs said
                        // nothing (run 216).
                        Text("Held")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.onGlassDim)
                            .lineLimit(1)
                            .fixedSize()
                        aetherCount(elemental)
                        aetherCount(Aether.pure)
                    }
                    Text(RaidGradeService.target(after: best, profile: profile))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlassDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            gradePays(raid, best: best, element: element)
        }
    }

    /// The grade worth aiming at — S until it is held (where the relic is
    /// lifted to Hero and the boon cache opens), then SS, then SSS.
    private func aimedGrade(after best: RaidGrade?) -> RaidGrade {
        guard let best, best >= .s else { return .s }
        return best == .s ? .ss : .sss
    }

    /// What the aimed grade pays, as one line of painted items with their
    /// words, read off `RaidGradeService` so it cannot drift from the payout:
    /// the Titan's aether and the pure, the relic the grade lifts, and the
    /// boon cache's chance. A line and not a row of tiles because the room's
    /// middle has no height for one: tiles put it below the fold.
    private func gradePays(_ raid: RaidEncounter, best: RaidGrade?, element: Element) -> some View {
        let aim = aimedGrade(after: best)
        let aether = RaidGradeService.aether(for: aim)
        let quality = RaidGradeService.qualityFloor(for: aim)
        let boon = RaidGradeService.boonCacheChance(for: aim)
        let heading = "\(aim.label) pays"
        let relicWords = quality.map { "\(raid.stage.rewards.relicGrade)★ \($0.displayName) relic" }
        let boonWords = "Boon \(DungeonDrop.percent(boon))"
        return HStack(spacing: 10) {
            Text(heading.uppercased())
                .font(Theme.title(13))
                .tracking(1.2)
                .carved(glow: false)
                .lineLimit(1)
                .fixedSize()
            payItem(Aether.id(for: element), "+\(aether.elemental)")
            if aether.pure > 0 {
                payItem(Aether.pure, "+\(aether.pure)")
            }
            if let relicWords {
                payItem("relic_cache", relicWords)
            }
            if boon > 0 {
                payItem("chest_gold", boonWords)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func payItem(_ key: String, _ words: String) -> some View {
        HStack(spacing: 3) {
            ItemIcon(key: key, size: 18, glow: false)
            Text(words)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
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
        raidEngine = engine
        openRaid = raid
        // Straight onto the stage card, with no slide (Docs/FEEL.md W2.24).
        BattleCover.open { raidBattle = .campaign(raid.stage) }
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
        towerEngine = engine
        // Straight onto the stage card, with no slide (Docs/FEEL.md W2.24).
        BattleCover.open { towerBattle = .campaign(stage) }
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
    /// The floor whose sweep choices (×1, ×5, ×10, Max) stand open over the
    /// deck. A sweep never spends on one tap: run 216's "Sweep ×13" spent 78
    /// of 79 energy with no choice and no confirmation.
    @State private var sweepChoicesFor: String?
    /// The Hidden Shrines (2026-09-23; Docs/SHRINES.md): the shrines open
    /// before a fight or a sweep, so one it found is announced when it comes
    /// back (`ShrineNoticeCard`, the genre's "Secret Dungeon discovered!"),
    /// and the shrine whose room is open over this one.
    @State private var shrinesBefore: Set<UUID> = []
    @State private var shrineNotice: HiddenShrine?
    @State private var shrineRoom: HiddenShrine?
    /// The tour's: the notice over the room from the first frame, on the
    /// first shrine open.
    private let announcesShrine: Bool

    /// `focusFloor` opens the room on that floor rather than the player's
    /// current one; the CI tour pins it to photograph a mastered floor's deck.
    /// Every dungeon's and hall's stage ids are `<chapter>_<n>`.
    ///
    /// `opensSweep` opens the focused floor's sweep choices, so the tour can
    /// photograph them over a mastered floor. `announcesShrine` stands the
    /// shrine notice over the room, so the tour can photograph it.
    init(chapterID: String, focusFloor: Int? = nil, opensSweep: Bool = false, announcesShrine: Bool = false) {
        self.chapterID = chapterID
        let focus = focusFloor.map { "\(chapterID)_\($0)" }
        _focusedID = State(initialValue: focus)
        _sweepChoicesFor = State(initialValue: opensSweep ? focus : nil)
        self.announcesShrine = announcesShrine
    }

    /// The floor rail's width: the summon rail's 204 plus room for a hall
    /// row's essence tiers in words ("Mid · High 50%") beside the energy and power.
    private static let railWidth: CGFloat = 212

    private var labyrinth: DungeonDatabase.Labyrinth? { DungeonDatabase.labyrinth(chapterID) }
    private var hall: DungeonDatabase.Hall? { DungeonDatabase.hall(chapterID) }
    private var chapter: Chapter? { labyrinth?.chapter ?? hall?.chapter }
    private var environment: BattleEnvironment? { labyrinth?.environment ?? hall?.environment }

    /// The strip's subtitle says something the room does not: the sets a
    /// relic dungeon drops, the essence a hall pays. It said "three waves a
    /// level" and "Hall of Essence", both said again on the same screen
    /// (run 216).
    private var kindLabel: String {
        if let labyrinth { return "Relic dungeon · \(labyrinth.sets.count) sets" }
        if let hall { return "\(hall.element.displayName) essence" }
        return "Dungeon"
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
            if announcesShrine, shrineNotice == nil {
                // The tour's notice frame seeds its own shrine, so the order
                // the tour's and this room's appearances run in cannot leave
                // the card with nothing to announce.
                #if DEBUG
                store.seedTourShrines()
                #endif
                shrineNotice = store.openShrines.first
            }
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
        .fullScreenCover(item: $battle, onDismiss: announceShrine) { context in
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
                        announceShrine()
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if let notice = shrineNotice {
                ShrineNoticeCard(
                    shrine: notice,
                    onEnter: {
                        shrineNotice = nil
                        shrineRoom = notice
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) { shrineNotice = nil }
                    }
                )
            }
        }
        .background {
            Color.clear
                .fullScreenCover(item: $shrineRoom) { shrine in
                    ShrineRoomScreen(focus: shrine.id)
                        .environmentObject(store)
                }
        }
    }

    /// A shrine a fight or a sweep found, announced over the room when it
    /// comes back: the first one open now that was not open before it. Every
    /// shrine open counts as seen afterwards, so none is announced twice.
    private func announceShrine() {
        let found = store.openShrines.first { !shrinesBefore.contains($0.id) }
        shrinesBefore = Set(store.openShrines.map { $0.id })
        guard let found else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.medium)
        withAnimation(.easeOut(duration: 0.25)) { shrineNotice = found }
    }

    /// Clears a mastered level without a battle. The relic grind is the one
    /// this matters most for: ten runs of a B10 is ten minutes of watching
    /// three waves resolve the same way.
    private func sweep(_ stage: Stage, runs: Int) {
        shrinesBefore = Set(store.openShrines.map { $0.id })
        guard let receipt = store.sweep(stage: stage, runs: runs), receipt.runs > 0 else { return }
        // The choice's press ticked on touch-down; the confirm is the "done".
        AudioLibrary.shared.play(.uiConfirm)
        withAnimation(Motion.panel) { sweepReceipt = receipt }
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
    ///
    /// The crop and the scrims follow the painting (`roomFocus`,
    /// `roomIsDark`): the Serpent Deep's lake is black under its statues, and
    /// the centre crop under the summon room's scrims was a black panel with
    /// the Hall of Shadows' boss on it (run 216). The motes are the room's
    /// own light, saturated — a hall's in its element — since the battle's
    /// key light read as grey dust.
    private var backdrop: some View {
        let dark = environment?.roomIsDark ?? false
        let motes = hall.map { $0.element.color } ?? Color(hex: environment?.roomMoteHex ?? "#FFE29A")
        return ZStack {
            PlaceBackdrop(
                painting: environment?.backdropName ?? "",
                focus: environment?.roomFocus ?? .center,
                topScrim: dark ? 0.3 : 0.55,
                footScrim: dark ? 0.45 : 0.62
            )
            PlaceAmbience(
                shafts: [],
                motes: 18,
                moteColor: motes,
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
    /// room shows, with a whole row at its top (`WholeRowRail`): centring the
    /// focused floor left B4's disc cut through its label under the head on
    /// run 217's frame 16, and B5's on the B10 frame.
    ///
    /// The label is pinned ABOVE the scroll: inside it, the scroll to the
    /// focused floor carried it off the top and cut the first row on the
    /// strip's edge (run 216). The waves are said once, in the room's
    /// eyebrow.
    private func floorRail(_ chapter: Chapter) -> some View {
        let teamPower = store.team(store.player.campaignTeam).reduce(0) { $0 + $1.power }
        let focus = focused(chapter)?.id
        return VStack(spacing: 0) {
            LabyrinthRailHead(title: labyrinth != nil ? "Levels" : "Floors")
            WholeRowRail(width: Self.railWidth, items: chapter.stages, focus: focus) { stage in
                floorRow(stage, isOn: stage.id == focus, teamPower: teamPower)
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
        // A row of the floors' scrolling rail: quiet, its tap kept.
        .buttonStyle(GamePressStyle(.quiet))
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
    /// a hall's essence tiers by NAME — the sure tier alone, a chance with
    /// its odds ("Low · Mid 40%"). The paintings with a bare percent read
    /// "Low 40%" as if Low dropped at 40%, and at 16 points the Low and Mid
    /// paintings are one stone (run 216). "Mid · High 50%" is 76 points of
    /// Manrope at 11, inside the 80 a row leaves it.
    @ViewBuilder
    private func rowPayout(_ stage: Stage, dim: Bool) -> some View {
        let ink = dim ? Theme.onGlassDim : Theme.onGlass
        if let hall {
            Text(hallRowWords(hall, stage: stage))
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
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

    /// A hall floor's tiers in words: "Low · Mid 40%".
    private func hallRowWords(_ hall: DungeonDatabase.Hall, stage: Stage) -> String {
        let parts: [String] = Self.essenceTiers.compactMap { tier -> String? in
            let chance = stage.rewards.essenceChances["essence_\(hall.element.rawValue)_\(tier)"] ?? 0
            guard chance > 0 else { return nil }
            return chance >= 1 ? tier.capitalized : tier.capitalized + " " + DungeonDrop.percent(chance)
        }
        return parts.joined(separator: " · ")
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
                    // 10 between the boss and the plate, and a 90-point boss
                    // column (the 84-point face; "Unwrapped", its widest
                    // word, is 81): the ten points go to the drops, whose
                    // six names on a B10 have no room to spare (run 221).
                    HStack(alignment: .top, spacing: 10) {
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
        // One format in both rooms, the level first (run 216 had "3 waves ·
        // foes Lv.38" in a dungeon and "4 foes · Lv.44" in a hall).
        let eyebrow = labyrinth != nil
            ? "Lv.\(level) · \(1 + stage.laterWaves.count) waves"
            : "Lv.\(level) · \(stage.enemies.count) foes"
        let eventOn = labyrinth.map { EventCalendar.isActive(.doubleRelics(labyrinth: $0.id)) }
            ?? hall.map { EventCalendar.isActive(.doubleEssence($0.element)) }
            ?? false
        return HStack(alignment: .center, spacing: 12) {
            // The number and the words as one block, for the scrim under it.
            HStack(spacing: 12) {
                LabyrinthView.floorNumber("B", stage.index)
                PlaceTitle(eyebrow: eyebrow, title: floorHeadline(stage), size: 18)
            }
            // A soft dark pool behind the words: the Vault's torch burns
            // right behind "5★" and the headline's comma, and the gold
            // glyphs merged with the flame (run 221). Blurred, so it has no
            // edge; drawn wider than the words and never measured.
            .background(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.5), location: 0),
                        .init(color: Color.black.opacity(0.34), location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .padding(.leading, -6)
                .padding(.trailing, -24)
                .padding(.vertical, -6)
                .blur(radius: 8)
                .allowsHitTesting(false)
            }
            Spacer(minLength: 6)
            if eventOn {
                GlassBead(
                    text: labyrinth != nil ? "Relic ×2 today" : "Essence ×2 today",
                    systemImage: "sparkles",
                    tint: Theme.onGlassEyebrow
                )
            }
            InfoDot(title: labyrinth != nil ? "This dungeon" : "This hall", seated: true) {
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
                    .carved(glow: false, multiline: true)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 90)
    }

    /// The floor's drops as tiles on one glass plate — they follow the floor
    /// chosen, as Star Rail's Caverns show a level's own rewards — then the
    /// dungeon's six sets as their stones with their names under them, or,
    /// in a hall, what an awakening spends of this element by grade. The
    /// first clear's divinity is the Drops header's accessory and the
    /// awakened relic's chance the sets header's, so a B10 keeps one row of
    /// six tiles.
    ///
    /// Run 216's judges: the tile rows stood at three heights (a grid row
    /// centres its items, and a relic's stars or a two-line name made some
    /// taller), so every item is TOP-aligned; the sets were six mostly empty
    /// capsules like the fields of a form, so they are the six painted
    /// stones with their names, the hub card's treatment; and a floor that
    /// pays two things left 400 points of empty glass beside them, so a
    /// relic dungeon floor of three tiles or fewer lays the tiles and the
    /// sets side by side. There the first clear is a TILE of its own (the
    /// divinity, "+20", "First clear") rather than the header's accessory:
    /// in a column two tiles wide the accessory left the Drops rule a stub,
    /// ran into the sets' title and stood over an empty block (run 221).
    ///
    /// The tiles ask for `dropSpacing` between them: a tile's name is as
    /// wide as its frame (`RewardTile`, 1.35 of the socket), and at 4 points
    /// two "Whetstone"s read as one phrase on a B10 (run 221). At 7.6 points
    /// they still did (run 224, "Whetstone Whetstone"), so a run of one
    /// stone's tiers is ONE slot now (`dropSlots`, `stoneRun`): the tiers'
    /// stones side by side over their tiers' words, the stone named once.
    /// That row is an HStack, since a grid's column cannot hold a pair; a
    /// row too wide for the plate falls back to the grid and the full names.
    private func floorDrops(_ stage: Stage) -> some View {
        let firstClearPays = !CampaignService.isCleared(stage, player: store.player) && stage.rewards.firstClearDivinity > 0
        let firstClear: String? = firstClearPays ? "+\(stage.rewards.firstClearDivinity) first clear" : nil
        let tiles = dropTiles(stage)
        let besideSets = firstClearPays ? tiles + [Self.firstClearTile(stage)] : tiles
        let awakened = stage.rewards.awakenedChance.map { "\(DungeonDrop.percent($0)) awakened" }
        let slots = Self.dropSlots(tiles)
        return VStack(alignment: .leading, spacing: 7) {
            if let labyrinth, besideSets.count <= 3 {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        GlassSectionHeader(title: "Drops")
                        dropRow(Self.dropSlots(besideSets))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 7) {
                        GlassSectionHeader(title: "One of \(labyrinth.sets.count) sets", accessory: awakened)
                        setGrid(labyrinth.sets, perRow: 3)
                    }
                }
            } else {
                GlassSectionHeader(title: "Drops", accessory: firstClear, accessoryItemKey: firstClear == nil ? nil : "divinity")
                if slots.count < tiles.count {
                    // A B10's five slots are 374 points of the CI phone's 392.
                    ViewThatFits(in: .horizontal) {
                        dropRow(slots)
                        dropGrid(tiles)
                    }
                } else {
                    dropGrid(tiles)
                }
                if let labyrinth {
                    GlassSectionHeader(title: "One of \(labyrinth.sets.count) sets", accessory: awakened)
                    setGrid(labyrinth.sets, perRow: 6)
                } else if let hall {
                    GlassSectionHeader(title: "An awakening spends")
                    HStack(spacing: 6) {
                        ForEach([3, 4, 5], id: \.self) { stars in
                            awakenChip(hall, stars: stars)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GlassPlate(radius: Theme.cornerRadius))
    }

    private func dropRewardTile(_ drop: DungeonDrop) -> some View {
        RewardTile(key: drop.key, title: drop.title, amount: drop.amount, stars: drop.stars,
                   size: Self.dropTile, imageName: drop.imageName, onGlass: true)
    }

    /// The drops as a grid of tiles, six to a row at the CI phone's 392
    /// points: 6 × 54 + 5 × 10 is 374, and a minimum of 58 at this spacing
    /// made it five and sent a B10's sixth tile to a second row, past the
    /// room's middle.
    private func dropGrid(_ tiles: [DungeonDrop]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 54, maximum: 66), spacing: Self.dropSpacing, alignment: .top)],
                  alignment: .leading, spacing: 6) {
            ForEach(tiles) { drop in
                dropRewardTile(drop)
            }
        }
    }

    /// The drops as one row of slots, top-aligned.
    private func dropRow(_ slots: [DungeonDropSlot]) -> some View {
        HStack(alignment: .top, spacing: Self.dropSpacing) {
            ForEach(slots) { slot in
                dropSlot(slot)
            }
        }
    }

    @ViewBuilder
    private func dropSlot(_ slot: DungeonDropSlot) -> some View {
        switch slot {
        case .tile(let drop):
            dropRewardTile(drop)
        case .stones(let kind, let run):
            stoneRun(kind, run)
        }
    }

    /// One stone's tiers as ONE drop: the tiers' stones side by side, 8
    /// points apart where tiles stand 25, each over its tier's word in its
    /// quality's colour (Rare's blue, Hero's violet — the stones' own), and
    /// the stone named once under the pair: "Rare  Hero / Whetstone". Run
    /// 224's B10 read "Rare Whetstone Hero Whetstone" across two tiles, and
    /// the tier alone on each read as a relic's quality (run 216); here the
    /// name under both says what the tiers are of.
    private func stoneRun(_ kind: RelicStone.Kind, _ run: [DungeonDrop]) -> some View {
        let spoken = run.map { drop in
            "\(RelicStone.from(id: drop.id)?.tier.displayName ?? drop.title) \(drop.amount)"
        }
        return VStack(spacing: Self.captionGap) {
            HStack(alignment: .top, spacing: Self.stoneRunGap) {
                ForEach(run) { drop in
                    let tier = RelicStone.from(id: drop.id)?.tier
                    VStack(spacing: Self.captionGap) {
                        RewardTile(key: drop.key, amount: drop.amount, size: Self.dropTile,
                                   showsTitle: false, onGlass: true)
                        Text(tier?.displayName ?? drop.title)
                            .font(Theme.body(11).weight(.semibold))
                            .foregroundStyle(tier.map { $0.quality.rarity.glow } ?? Theme.onGlass)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(width: Self.dropTile)
                }
            }
            Text(kind.displayName)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.displayName): " + spoken.joined(separator: ", "))
    }

    /// Where a stone stands among a floor's stones: whetstones before gems,
    /// each kind's tiers low to high.
    private static func stoneOrder(_ id: String) -> Int {
        guard let stone = RelicStone.from(id: id) else { return 0 }
        let kind = RelicStone.Kind.allCases.firstIndex(of: stone.kind) ?? 0
        return kind * 10 + stone.tier.rawValue
    }

    /// A drop row's slots: every tile on its own, except a run of one
    /// stone's tiers (a B10's Rare and Hero whetstones), which is one slot.
    /// A stone alone keeps its tile and its full name.
    private static func dropSlots(_ drops: [DungeonDrop]) -> [DungeonDropSlot] {
        var slots: [DungeonDropSlot] = []
        var run: [DungeonDrop] = []
        var runKind: RelicStone.Kind? = nil
        func closeRun() {
            if let kind = runKind, run.count > 1 {
                slots.append(.stones(kind, run))
            } else {
                slots.append(contentsOf: run.map { DungeonDropSlot.tile($0) })
            }
            run = []
            runKind = nil
        }
        for drop in drops {
            let kind = RelicStone.from(id: drop.id)?.kind
            if kind == nil || kind != runKind {
                closeRun()
            }
            if let kind {
                runKind = kind
                run.append(drop)
            } else {
                slots.append(.tile(drop))
            }
        }
        closeRun()
        return slots
    }

    /// Between two drop tiles. The names under them are as wide as the
    /// tiles' frames, so this is all the air two names get.
    private static let dropSpacing: CGFloat = 10
    /// A drop tile's socket.
    private static let dropTile: CGFloat = 44
    /// Between the sockets of one stone's tiers: a pair, where tiles stand
    /// about 25 apart.
    private static let stoneRunGap: CGFloat = 8
    /// `RewardTile`'s own gap between its socket and its name, 0.05 of the
    /// socket, so a tier's word stands where a tile's name does.
    private static let captionGap: CGFloat = max(2, dropTile * 0.05)

    /// A floor's first-clear divinity as a drop tile.
    private static func firstClearTile(_ stage: Stage) -> DungeonDrop {
        DungeonDrop(id: "first_clear", key: "divinity", title: "First clear",
                    amount: "+\(stage.rewards.firstClearDivinity)", stars: nil)
    }

    /// The dungeon's sets as their painted stones with their names under
    /// them, `perRow` to a row in equal columns.
    private func setGrid(_ sets: [RelicSet], perRow: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2, alignment: .top), count: perRow),
                  alignment: .leading, spacing: 6) {
            ForEach(sets) { relicSet in
                LabyrinthSetStone(set: relicSet)
            }
        }
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
        // Each kind's tiers together, low to high, so a kind's run is one
        // slot in the row (`dropSlots`).
        let stones = (rewards.stoneChances ?? [:]).sorted {
            Self.stoneOrder($0.key) < Self.stoneOrder($1.key)
        }
        for (id, chance) in stones where chance > 0 {
            // "Rare Whetstone", not "Rare": the tier alone read as a relic's
            // quality (run 216). Two lines; the grid's rows are top-aligned.
            // Two tiers of one stone side by side are drawn as one slot,
            // named once (`dropSlots`); this name is a lone stone's.
            drops.append(DungeonDrop(
                id: id, key: id, title: RelicStone.from(id: id)?.displayName ?? "Stone",
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
            // The boon cache has no painting of its own yet; the shut gold
            // chest stands in for it, since the seal glyph was the one
            // unpainted thing in a row of paintings (run 216).
            drops.append(DungeonDrop(
                id: "boon", key: "boon_cache_\(grade)", title: "Boon cache",
                amount: DungeonDrop.percent(chance), stars: grade, imageName: "item_chest_gold"
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
        let choosing = canSweep && sweepChoicesFor == stage.id
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
                // Opens the choices over the deck; it never spends by itself.
                PrimaryButton(title: "Sweep", systemImage: "forward.fill", isEnabled: hasEnergy, style: .glass) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        sweepChoicesFor = choosing ? nil : stage.id
                    }
                }
                .frame(maxWidth: 150)
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
        // The choices float over the room above the deck, as an overlay, so
        // opening them moves nothing.
        .overlay(alignment: .bottomTrailing) {
            if choosing {
                sweepChoices(stage)
                    .offset(y: -(PrimaryButton.height + 8))
                    .transition(.opacity)
            }
        }
    }

    /// The sweep's choices: once, five, ten, and as many as the energy pays
    /// for (never past `SweepService.maximumRuns`), each with the energy it
    /// spends — the campaign briefing's 1 / 5 / 10 / 20, with the last one
    /// "Max" because the wallet, not the menu, is usually the limit. The
    /// energy per run is the same `EventCalendar.energyCost` the fight
    /// charges.
    private func sweepChoices(_ stage: Stage) -> some View {
        let most = min(SweepService.maximumRuns, SweepService.affordableRuns(stage, player: store.player))
        let cost = EventCalendar.energyCost(for: stage)
        let short: [Int] = [1, 5, 10].filter { $0 < most }
        let counts: [Int] = most >= 1 ? short + [most] : short
        return HStack(spacing: 6) {
            Text("SWEEP")
                .font(Theme.title(13))
                .tracking(1.2)
                .carved(glow: false)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 2)
            ForEach(counts, id: \.self) { runs in
                sweepChoice(stage, runs: runs, spend: cost * runs, isMost: runs == most && runs > 1)
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { sweepChoicesFor = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.onGlassDim)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GamePressStyle(.medallion))
            .accessibilityLabel("Close")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(GlassPlate(radius: Theme.tightCorner, opacity: 0.92))
        .fixedSize()
    }

    private func sweepChoice(_ stage: Stage, runs: Int, spend: Int, isMost: Bool) -> some View {
        let label = isMost ? "Max ×\(runs)" : "×\(runs)"
        let spent = "\(spend)"
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { sweepChoicesFor = nil }
            sweep(stage, runs: runs)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(Theme.numeric(12).weight(.heavy))
                    .foregroundStyle(Color(hex: "#FFE9A8"))
                    .lineLimit(1)
                    .fixedSize()
                ItemIcon(key: "energy", size: 13, glow: false)
                Text(spent)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("Sweep \(runs) times for \(spend) energy")
    }

    /// Team & runs as a glyph plate the height of the buttons beside it, for
    /// a room too narrow for the words.
    private func teamButton(_ stage: Stage, enabled: Bool) -> some View {
        Button {
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
        .buttonStyle(GamePressStyle(.plate))
        .disabled(!enabled)
        .accessibilityLabel("Team and runs")
    }

    // MARK: - Fighting

    private func launch(_ stage: Stage, runs: Int) {
        guard let engine = store.startCampaignBattle(stage: stage) else { return }
        pendingEngines[stage.id] = engine
        pendingRuns[stage.id] = runs
        shrinesBefore = Set(store.openShrines.map { $0.id })
        // Straight onto the stage card, with no slide (Docs/FEEL.md W2.24).
        BattleCover.open { battle = .campaign(stage) }
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
/// key, a short title (the tier for an essence, the tier and the noun for a
/// stone — "Rare Whetstone" — the kind otherwise; a two-line name is fine,
/// since the rows are top-aligned), the amount or the chance on the socket's
/// corner, and the grade's stars.
/// Private to the Labyrinth's rooms; the name is unique in the tree.
private struct DungeonDrop: Identifiable {
    let id: String
    let key: String
    let title: String
    let amount: String
    let stars: Int?
    /// A bundle painting drawn in the socket in place of the item's own
    /// (`RewardTile.imageName`): the boon cache's stand-in chest.
    var imageName: String? = nil

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

/// A place in a floor's drop row: one tile, or a run of one stone's tiers
/// drawn as one (`DungeonLevelsView.dropSlots`, `stoneRun`).
private enum DungeonDropSlot: Identifiable {
    case tile(DungeonDrop)
    case stones(RelicStone.Kind, [DungeonDrop])

    var id: String {
        switch self {
        case .tile(let drop): return drop.id
        case .stones(let kind, _): return "stones_" + kind.rawValue
        }
    }
}

/// A relic set on dark glass as the hub card draws its sets: the painted
/// stone at 30 points with its name under it, in an equal column. Run 216's
/// judges read the capsules it replaced — a stone and a name in the left
/// third of a 180-point dark pill, six of them in a 3×2 grid — as the empty
/// fields of a form.
private struct LabyrinthSetStone: View {
    let set: RelicSet

    var body: some View {
        VStack(spacing: 3) {
            RelicSetEmblem(set: set, size: 30)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
            Text(set.displayName)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A rail's label pinned above its scroll, on the rail's own dark glass
/// (the `GlassRailPlate` gradient, under the leading inset as the plate is,
/// without its gold hairline, which fades in below it). Inside the scroll,
/// the scroll to the chosen row carried the label off the top and cut the
/// first row on the strip (run 216).
private struct LabyrinthRailHead: View {
    let title: String

    var body: some View {
        PlaceRailLabel(title)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#0E0B08").opacity(0.86), Color(hex: "#0E0B08").opacity(0.62)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea(.container, edges: .leading)
                .allowsHitTesting(false)
            )
    }
}

/// A Titan not yet graded: a dim dashed ring holding its element, in place
/// of `RaidGradeStamp`'s circled dash, which is iOS's remove control.
private struct UngradedTitanSeal: View {
    let element: Element
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.35))
            Circle().strokeBorder(Theme.onGlassDim.opacity(0.7),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            Image(systemName: element.glyph)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(element.color.opacity(0.75))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Not graded")
    }
}

/// A graded Titan's element on its rail seal: a 17-point disc of the
/// element's colour with its glyph, where the element's word stood over the
/// name until run 224. Radiance's gold is pale, so its glyph is ink, as the
/// card's `ElementBadge` has it; the others are white.
private struct TitanElementPip: View {
    let element: Element

    var body: some View {
        let pale = element == .radiance
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [element.color, element.color.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 1)
            Image(systemName: element.glyph)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(pale ? Theme.ink : Color.white)
        }
        .frame(width: 17, height: 17)
        .shadow(color: element.color.opacity(0.5), radius: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The floor a face stands on — the dungeon's boss, a Titan — so the tile
/// stands in the room rather than floating over it: a warm pool of light
/// on the painted floor and a dark contact shadow at the card's foot,
/// centred on its bottom edge and wider than it. The dark pool it replaces
/// sat under the name at 0.6 on grounds already dark and was never seen
/// (run 216). A background, so it is drawn wider than the tile without
/// being measured.
private struct PaintedFloorPool: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Theme.gold.opacity(0.30), Theme.gold.opacity(0.08), .clear],
                                     center: .center, startRadius: 4, endRadius: 88))
                .frame(width: 176, height: 46)
                .blendMode(.plusLighter)
            Ellipse()
                .fill(RadialGradient(colors: [Color.black.opacity(0.8), .clear], center: .center,
                                     startRadius: 2, endRadius: 54))
                .frame(width: 116, height: 18)
        }
        .offset(y: 25)
        .allowsHitTesting(false)
    }
}

/// How a Labyrinth room shows its place's painting, measured off the
/// paintings (run 216's judges; `framelight`-style means of 0–255 over the
/// band a room shows at 874 × 350 points).
private extension BattleEnvironment {
    /// Where a room crops its painting. The Serpent Deep is a square whose
    /// statues, pillars and glowing mushrooms fill its top 38% over a black
    /// lake: the centre crop showed the lake (mean 15, the ground under the
    /// portrait 7–8) and the Titans' first room and the Hall of Shadows were
    /// black; its top band is 34. Every other room's painting reads at the
    /// centre (51–110).
    var roomFocus: UnitPoint {
        switch self {
        case .serpentDeep: return UnitPoint(x: 0.5, y: 0.02)
        default: return .center
        }
    }

    /// The tower's crop: higher than a room's, so the Sand Stair — which
    /// borrows the Vault of the Colossus's corridor — shows its torches and
    /// ceiling rather than the Vault room's statues.
    var towerFocus: UnitPoint {
        switch self {
        case .serpentDeep: return UnitPoint(x: 0.5, y: 0.02)
        default: return UnitPoint(x: 0.5, y: 0.15)
        }
    }

    /// A painting too dark for the summon room's scrims (0.55 over the top,
    /// 0.62 under the foot), which take 0.3 and 0.45.
    var roomIsDark: Bool {
        switch self {
        case .serpentDeep: return true
        default: return false
        }
    }

    /// The motes' light: the room's own, saturated. The battle's key light
    /// (the Necropolis's #D8C8A8) drew motes as grey specks (run 216).
    var roomMoteHex: String {
        switch self {
        case .colossusVault: return "#FFC870"
        case .necropolis: return "#B98CFF"
        case .hydraLair: return "#A6F07A"
        case .jotunheimHall: return "#9FD8FF"
        case .serpentDeep: return "#C08CFF"
        default: return keyLightHex
        }
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
