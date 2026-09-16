#if DEBUG
import SwiftUI

/// A self-driving pass through the app's screens, for a machine with no
/// fingers.
///
/// The CI job builds the app on a macOS runner, launches it in a simulator
/// with `-tour`, and takes a screenshot every few seconds. This view is what
/// it launches into: each screen in turn, held for a few ticks, with a caption
/// in the corner so a sheet of frames reads without a key. The battle runs on
/// auto for a while so the models are caught fighting, not standing. Nothing
/// here ships: the whole file is debug-only and the switch is one launch
/// argument in `PantheonApp`.
struct TourView: View {
    @EnvironmentObject private var store: GameStore

    @State private var index = TourView.pinnedStep ?? 0
    @State private var ticksOnStep = 0
    @State private var battleModel: BattleViewModel?
    @State private var realmModel: BattleViewModel?
    @State private var arenaModel: BattleViewModel?
    @State private var dungeonModel: BattleViewModel?
    @State private var seeded = false

    /// `-tour-step N` pins the tour to one screen for the whole run. The CI
    /// job launches the app once per step and photographs it, because a
    /// timer-driven tour raced the simulator's first, slow screenshot and
    /// every frame came out of the last screen.
    static var pinnedStep: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-step"), at + 1 < args.count,
              let step = Int(args[at + 1]) else { return nil }
        return min(max(0, step), schedule.count - 1)
    }

    /// One entry per screen: what to show and how many ticks to hold it.
    private static let schedule: [(name: String, ticks: Int)] = [
        ("island", 2), ("collection", 2), ("detail", 2), ("training", 2),
        ("summon", 2), ("reveal", 3), ("battle", 8), ("arena", 2), ("arena_battle", 6), ("more", 2),
        ("halls", 2), ("relics", 2), ("shop", 2), ("chapter_map", 2), ("missions", 2),
        ("labyrinth", 2), ("dungeon", 2), ("relic_picker", 2), ("dungeon_battle", 6), ("relic_powerup", 2),
        ("victory", 4), ("collection_stage", 2), ("relic_drop", 2), ("relic_filter", 2), ("launch", 2),
        ("relic_sets", 2), ("tribute", 2), ("stage_popup", 2), ("chapter_maps", 2), ("realm_battle", 6),
        ("guide", 2), ("lessons", 2), ("night_market", 2), ("counsel", 2),
        ("sweep", 3), ("mileage", 2), ("selector", 2), ("relic_roll", 2),
        ("raid_grade", 4), ("raids", 2), ("relic_awaken", 3), ("boons", 2),
    ]

    /// `-tour-chapter K` picks which chapter the `chapter_maps` step opens;
    /// the CI job relaunches that step once per chapter so every painted
    /// map is photographed.
    static var pinnedChapter: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-chapter"), at + 1 < args.count,
              let chapter = Int(args[at + 1]) else { return 0 }
        return min(max(0, chapter), StageDatabase.chapters.count - 1)
    }

    /// `-tour-environment <rawValue>` picks the set the `realm_battle` step
    /// fights on; the CI job relaunches that step once per realm so every
    /// dressed set is photographed, not only Egypt's three the other battle
    /// steps happen to use.
    static var pinnedEnvironment: BattleEnvironment? {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-environment"), at + 1 < args.count else { return nil }
        return BattleEnvironment(rawValue: args[at + 1])
    }

    /// Seconds per tick. The runner screenshots on the same period, so every
    /// step is caught at least once.
    static let tickSeconds: TimeInterval = 4

    private let timer = Timer.publish(every: TourView.tickSeconds, on: .main, in: .common).autoconnect()

    private var current: String { Self.schedule[min(index, Self.schedule.count - 1)].name }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            content
                .id(index)
            Text("tour \(index + 1)/\(Self.schedule.count) · \(current)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7), in: Capsule())
                .padding(10)
        }
        .preferredColorScheme(.light)
        .onAppear {
            seedIfNeeded()
            if current == "battle" { startBattle() }
            if current == "arena_battle" { startArenaBattle() }
            if current == "dungeon_battle" { startDungeonBattle() }
            if current == "realm_battle" { startRealmBattle() }
        }
        .onReceive(timer) { _ in
            if Self.pinnedStep == nil { tick() }
            // The battles play themselves a command at a time, so the frames
            // catch a dash, a hit and a flash rather than a line of units
            // waiting for a thumb. Auto-battle would win before the first
            // frame; one basic attack every four seconds is a fight in
            // progress for the whole step.
            for model in [battleModel, arenaModel, realmModel].compactMap({ $0 }) {
                model.selectSkill(0)
                model.confirmTarget()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch current {
        case "island":
            IslandView { _ in }
        case "collection":
            CollectionView()
        case "collection_stage":
            // The collection's other shape: the rail along the bottom, the
            // picked unit's model on the stage, the words and slots on the
            // left. Opened in that layout because nothing here taps the
            // switch; the `collection` step above keeps the Cards.
            CollectionView(initialLayout: .stage)
        case "detail":
            if let unit = store.player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }) ?? store.player.units.first {
                UnitDetailView(unitID: unit.id)
            } else {
                CollectionView()
            }
        case "training":
            TrainingView()
        case "summon":
            SummonView()
        case "reveal":
            SummonRevealView(results: Self.demoReveal()) {}
        case "battle":
            if let battleModel {
                BattleView(model: battleModel)
            } else {
                Theme.surface.ignoresSafeArea()
                    .onAppear { startBattle() }
            }
        case "arena":
            ArenaView()
        case "arena_battle":
            // The arena fight is a different stage, a 4v4 and an AI-built
            // enemy team, so the camera and the placement are photographed
            // here as well as in the campaign.
            if let arenaModel {
                BattleView(model: arenaModel)
            } else {
                Theme.surface.ignoresSafeArea()
                    .onAppear { startArenaBattle() }
            }
        case "halls":
            NavigationStack {
                DungeonLevelsView(chapterID: "hall_ember")
            }
        case "labyrinth":
            LabyrinthView()
        case "dungeon":
            NavigationStack {
                DungeonLevelsView(chapterID: "lab_colossus")
            }
        case "relic_picker":
            if let unit = store.player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }) ?? store.player.units.first {
                RelicPickerView(unitID: unit.id, slot: 2)
            } else {
                RelicInventoryView()
            }
        case "relic_powerup":
            // The power-up screen on the best relic the roster owns.
            if let relic = bestRelic {
                RelicDetailView(relicID: relic.id)
            } else {
                RelicInventoryView()
            }
        case "relic_drop":
            // The card a relic drop opens from the chest's shelf: Sell, Keep,
            // Lock and keep.
            if let relic = bestRelic {
                RelicDropCard(relicID: relic.id)
                    .background(Color.black.ignoresSafeArea())
            } else {
                RelicInventoryView()
            }
        case "relic_filter":
            // The inventory with its filter sheet open.
            RelicInventoryView(openingFilter: true)
        case "launch":
            // The loading screen, frozen part way along its bar, on the key
            // art when it is in the bundle.
            LaunchView(progress: LaunchProgress(
                preview: 0.62, step: "Raising the stages",
                art: BundleArt.exists(LaunchProgress.keyArt) ? LaunchProgress.keyArt : "banner_olympus_stirs"
            ))
        case "tribute":
            // A tribute chest's card: the road's, earned by the tour's player
            // (three stages of the Duat walked) and waiting to be claimed.
            if let chapter = StageDatabase.chapter("duat_1") {
                TributeCard(tribute: TributeService.tributes(for: chapter)[0], chapterID: chapter.id, difficulty: .normal)
            } else {
                CampaignView(openingChapter: "duat_1")
            }
        case "guide":
            // Athena over the island, saying the first thing she says. The
            // tour's save is a veteran's, so the opening would be silent on
            // its own: the plate is put up directly, which is what a picture
            // of it needs.
            ZStack {
                IslandView(isActive: false) { _ in }
                GuidePlate(
                    beat: LessonBook.opening.first?.beats.first
                        ?? LessonBeat("The gods of five worlds are asleep under the stone."),
                    title: LessonBook.opening.first?.title ?? "",
                    isLast: false,
                    onAdvance: {},
                    onSkip: {}
                )
            }
        case "lessons":
            LessonsView()
        case "night_market":
            // The rolled shelf. Opened straight on its stall, because nothing
            // in a pinned tour taps the bazaar's dropdown.
            ShopView(opening: .nightMarket)
        case "counsel":
            // Athena's road: the tier the tour's save is on, its steps and the
            // tier's prize. Opened on that tab for the same reason.
            MissionsView(opening: .counsel)
        case "sweep":
            // The briefing with its Sweep button, and the receipt over it once
            // the sweep has run. The tour's save three-stars Duat 1-1, so this
            // is a real sweep of a real stage; if it were ever refused the
            // frame still shows the button and the sentence that says why,
            // which is the other thing worth photographing.
            TourSweepScene()
        case "mileage":
            // The Duat banner's exchange, with the tour's save partway up it:
            // the 4★ row can be taken and the 5★ row cannot, which is the
            // difference the screen exists to show.
            MileageSheet(banner: Banner.duatOpens) { _ in }
        case "selector":
            // The opening gift, presented directly. The tour's save has
            // already spent it (a veteran's save would otherwise pop this
            // over the summoning room at step 4), so it is put up here the
            // way the guide plate is.
            SelectorSheet { _ in }
        case "relic_roll":
            // The choice of two, on a relic whose seed the tour's save sets.
            // The same screen as step 19, in the state it spends most of a
            // player's attention in.
            if let relic = store.player.relics.first(where: { $0.hasPendingRoll }) ?? bestRelic {
                RelicDetailView(relicID: relic.id)
            }
        case "relic_sets":
            // The set reference, opened from a unit so its counts show.
            if let unit = store.player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }) ?? store.player.units.first {
                RelicSetsSheet(unitID: unit.id)
            } else {
                RelicSetsSheet()
            }
        case "dungeon_battle":
            // A Labyrinth run on auto, so the frames catch the second and
            // third waves walking on and the Wave chip counting.
            if let dungeonModel {
                BattleView(model: dungeonModel)
            } else {
                Theme.surface.ignoresSafeArea()
                    .onAppear { startDungeonBattle() }
            }
        case "realm_battle":
            // A fight on the realm named at launch (-tour-environment), one
            // command a tick, so each set's floor, walls, light and weather
            // are seen — the other battle steps only ever show Egypt.
            if let realmModel {
                BattleView(model: realmModel)
            } else {
                Theme.surface.ignoresSafeArea()
                    .onAppear { startRealmBattle() }
            }
        case "relics":
            RelicInventoryView()
        case "shop":
            ShopView()
        case "chapter_map":
            // The first chapter as a place: the painting, the road, the
            // medallions and the chests; the world map is the `island`
            // step's neighbour and is seen from there.
            CampaignView(openingChapter: "duat_1")
        case "stage_popup":
            // The fourth stage's card over the map: story, enemies, drops,
            // power, Fight.
            CampaignView(openingChapter: "duat_1", openingStage: "duat_1_4")
        case "chapter_maps":
            // Every chapter's map in turn (-tour-chapter K), so a painted
            // region's medallions are seen on their landmarks before the
            // owner does.
            CampaignView(openingChapter: StageDatabase.chapters[Self.pinnedChapter].id)
        case "missions":
            MissionsView()
        case "victory":
            // The two acts of a win without fighting one: the reckoning,
            // then the chest opening on its spoils. `autoplay` taps through
            // for the camera.
            BattleResultView(summary: Self.demoVictory(relic: bestRelic), onDismiss: {}, autoplay: true, store: store)
                .background(Color.black.ignoresSafeArea())
        case "raid_grade":
            // A raid's win: the same two acts with the grade stamped on the
            // reckoning and the aether on the shelf. The grade and its line
            // are computed by `RaidGradeService` from a 46-turn kill of the
            // serpent, so the frame shows what the code writes, not a mock.
            BattleResultView(summary: Self.demoRaidVictory(relic: bestRelic), onDismiss: {}, autoplay: true, store: store)
                .background(Color.black.ignoresSafeArea())
        case "raids":
            // The Raids wing: the two cards with the tour save's best grade
            // stamped on the serpent's, the mark to beat, and the aether held.
            LabyrinthView(opening: .raids)
        case "relic_awaken":
            // The awakening, performed as the screen appears on the tour
            // save's 6★ +15 (the debug seed's, with the aether to pay for
            // it): the rite in the first frame, then the halo on the stone,
            // the Awakened chip and the fifth sub stat's choice of two.
            //
            // Picked by a rule that still holds AFTER the awakening: the
            // store changes the moment it lands, this `content` is
            // re-evaluated, and a rule of "not yet awakened" swapped the
            // sheet for the best climbing relic between the two frames —
            // run 159 photographed the Vigil +12 twice and the rite never.
            if let relic = store.player.relics.first(where: { $0.grade >= 6 && $0.isMaxLevel }) {
                RelicDetailView(relicID: relic.id, awakenOnAppear: !relic.isAwakened)
            } else if let relic = bestRelic {
                RelicDetailView(relicID: relic.id)
            }
        case "boons":
            // The socket's picker, opened on the tour save's shut cache: its
            // three doors on the right, the boons owned on the left, for
            // Zeus's socket (the detail step shows the socket filled).
            if let zeus = store.player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }) {
                BoonPickerView(unitID: zeus.id, openingCache: true)
            } else {
                BoonPickerView(openingCache: true)
            }
        default:
            SettingsView()
        }
    }

    /// The relic the relic steps photograph: the highest grade, and among
    /// those the highest level, so the level track and the rim both show —
    /// but never one already at +15, whose power-up panel has nothing to
    /// photograph (the seed's awakening candidate is one, for step 40).
    private var bestRelic: Relic? {
        let climbing = store.player.relics.filter { !$0.isMaxLevel }
        return (climbing.isEmpty ? store.player.relics : climbing)
            .max(by: { ($0.grade, $0.level) < ($1.grade, $1.level) })
    }

    private func tick() {
        ticksOnStep += 1
        guard ticksOnStep >= Self.schedule[min(index, Self.schedule.count - 1)].ticks else { return }
        ticksOnStep = 0
        if index + 1 < Self.schedule.count {
            index += 1
            if current == "battle" { startBattle() }
            if current == "arena_battle" { startArenaBattle() }
            if current == "dungeon_battle" { startDungeonBattle() }
            if current == "realm_battle" { startRealmBattle() }
        }
    }

    /// The first stage set in the pinned realm. It is locked on a fresh
    /// save, so the engine is built directly rather than through the
    /// store's gate: no energy is spent and no clear is recorded.
    private func startRealmBattle() {
        guard realmModel == nil else { return }
        let environment = Self.pinnedEnvironment ?? .olympusGate
        guard let stage = StageDatabase.allStages.first(where: { $0.environment == environment }) else { return }
        let team = CampaignService.resolveTeam(store.player.campaignTeam, player: store.player)
        guard !team.isEmpty else { return }
        let engine = BattleEngine(
            playerTeam: team,
            opponentTeam: StageDatabase.buildEnemies(for: stage),
            mode: .campaign,
            seed: 7,
            laterWaves: stage.laterWaves.map { StageDatabase.buildEnemies(spawns: $0) }
        )
        let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
        model.autoBattle = false
        realmModel = model
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        store.grantTourRoster()
        // The opening's lessons, given. Without this the library photographs
        // as fourteen greyed rows — true of a save that has never met Athena,
        // and useless as a picture of the screen: what it is FOR is the
        // difference between a lesson kept and a lesson still locked.
        for lesson in LessonBook.opening.prefix(4) {
            store.markLessonRead(lesson.id)
        }
    }

    private func startBattle() {
        guard battleModel == nil else { return }
        // The first gate is the one stage every account has open; a fresh
        // save has not cleared it, so Reed Fields would refuse and the step
        // would stay black.
        for id in ["duat_1_1", "duat_1_2"] {
            guard let stage = StageDatabase.stage(id),
                  let engine = store.startCampaignBattle(stage: stage) else { continue }
            let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
            // Not on auto: a levelled team won the first gate before the
            // runner's first frame and every battle frame was the victory
            // panel. Waiting for a command shows the stage, the HUD and the
            // idle clips, which is what the frames are for.
            model.autoBattle = false
            battleModel = model
            return
        }
    }

    private func startDungeonBattle() {
        guard dungeonModel == nil else { return }
        guard let stage = StageDatabase.stage("lab_colossus_1"),
              let engine = store.startCampaignBattle(stage: stage) else { return }
        let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
        // On auto: the point of the step is the waves, and the tour roster
        // clears the first in a few turns.
        model.autoBattle = true
        dungeonModel = model
    }

    private func startArenaBattle() {
        guard arenaModel == nil else { return }
        guard let opponent = store.arenaPool.first,
              let engine = store.startArenaBattle(against: opponent) else { return }
        let model = BattleViewModel(engine: engine, context: .arena(opponent), store: store)
        model.autoBattle = false
        arenaModel = model
    }

    /// A 5★ reveal without spending a scroll, so the stage is caught with a
    /// real model on it.
    private static func demoReveal() -> [SummonResult] {
        guard let blueprint = UnitDatabase.blueprint("sekhmet_ember") ?? UnitDatabase.summonPool.first.flatMap(UnitDatabase.blueprint) else {
            return []
        }
        return [SummonResult(
            unit: Unit(blueprint: blueprint),
            blueprint: blueprint,
            stars: blueprint.naturalStars,
            isNew: true,
            isFeatured: true,
            fromPity: false
        )]
    }

    /// A won stage as the result screen reads it: three of the first
    /// families, one of them the MVP, one fallen, and a chest with every
    /// kind of spoil in it, so the tiles are all photographed at once.
    private static func demoVictory(relic: Relic? = nil) -> BattleSummary {
        let cast: [(id: String, dealt: Double, taken: Double, healed: Double, kills: Int, survived: Bool)] = [
            ("anubis_umbra", 14_820, 3_960, 0, 3, true),
            ("sekhmet_ember", 9_140, 6_210, 0, 2, true),
            ("thoth_radiance", 2_380, 1_100, 5_640, 0, true),
            ("zeus_tide", 6_470, 8_900, 0, 1, false),
        ]
        var stats: [BattleSummary.UnitStat] = []
        for member in cast {
            guard let blueprint = UnitDatabase.blueprint(member.id) else { continue }
            stats.append(BattleSummary.UnitStat(
                id: UUID(),
                name: blueprint.name,
                portraitName: blueprint.model.portraitName(awakened: false),
                element: blueprint.element,
                stars: blueprint.naturalStars,
                dealt: member.dealt,
                taken: member.taken,
                healed: member.healed,
                kills: member.kills,
                survived: member.survived
            ))
        }
        let loot: [BattleSummary.Loot] = [
            .init(glyph: "circle.hexagongrid.fill", title: "Drachma", amount: "+1,240", tint: .gold, key: "drachma"),
            .init(glyph: "arrow.up.circle.fill", title: "Unit EXP", amount: "+860", tint: .verdigris, key: "unit_exp"),
            .init(glyph: "sparkles", title: "Divinity", amount: "+15", tint: .marble, key: "divinity"),
            .init(glyph: RelicSet.fury.glyph, title: relic?.displayName ?? "Hero Fury Relic", amount: "Slot \(relic?.slot ?? 4)",
                  tint: .gold, stars: relic?.grade ?? 5, relic: relic),
            .init(glyph: "drop.triangle.fill", title: "Mid Ember Essence", amount: "+3", tint: .element(.ember), key: "essence_ember_mid"),
            .init(glyph: ScrollType.unknown.glyph, title: ScrollType.unknown.displayName, amount: "+1", tint: .scroll(.unknown), key: ItemArt.key(scroll: .unknown)),
        ]
        return BattleSummary(
            outcome: .victory,
            lines: [],
            stars: 3,
            title: "The Weighing of the Heart",
            turns: 11,
            damageDealt: stats.reduce(0) { $0 + $1.dealt },
            damageTaken: stats.reduce(0) { $0 + $1.taken },
            unitStats: stats,
            mvpID: stats.first?.id,
            loot: loot,
            isFirstClear: true
        )
    }

    /// The serpent's raid as its result screen reads it: the demo win's cast,
    /// a kill on turn 46 graded by the real service, and the raid's own shelf
    /// — its 6★ relic, the aether the grade pays, a whetstone, its essence.
    private static func demoRaidVictory(relic: Relic? = nil) -> BattleSummary {
        var summary = demoVictory(relic: relic)
        summary.stars = 2
        summary.turns = 46
        summary.isFirstClear = false
        guard let raid = StageDatabase.raids.first, let profile = raid.profile else { return summary }
        let result = BattleResult(
            outcome: .victory, turnsTaken: 46, survivorFraction: 0.75,
            totalDamageDealt: summary.damageDealt, totalDamageTaken: summary.damageTaken,
            seed: 0, raidShare: 1
        )
        let grade = RaidGradeService.grade(result: result, profile: profile)
        let pay = RaidGradeService.aether(for: grade)
        let elemental = Aether.id(for: RaidGradeService.element(of: raid))
        summary.title = raid.name
        summary.raidGrade = grade
        summary.raidGradeLine = RaidGradeService.caption(grade: grade, result: result, profile: profile)
        summary.loot = [
            .init(glyph: "circle.hexagongrid.fill", title: "Drachma", amount: "+12,000", tint: .gold, key: "drachma"),
            .init(glyph: "arrow.up.circle.fill", title: "Unit EXP", amount: "+2,400", tint: .verdigris, key: "unit_exp"),
            .init(glyph: RelicSet.fury.glyph, title: relic?.displayName ?? "Legend Fury Relic", amount: "Slot \(relic?.slot ?? 2)",
                  tint: .gold, stars: relic?.grade ?? 6, relic: relic),
            .init(glyph: "circle.hexagonpath.fill", title: Aether.name(for: elemental), amount: "+\(pay.elemental)",
                  tint: .element(RaidGradeService.element(of: raid)), key: elemental),
            .init(glyph: "circle.hexagonpath.fill", title: Aether.name(for: Aether.pure), amount: "+\(pay.pure)",
                  tint: .marble, key: Aether.pure),
            .init(glyph: RelicStone.Kind.whetstone.glyph, title: "Hero Whetstone", amount: "+1", tint: .rarity(RelicQuality.hero.rarity), key: "whetstone_hero"),
            .init(glyph: "drop.triangle.fill", title: "High Ember Essence", amount: "+2", tint: .element(.ember), key: "essence_ember_high"),
        ]
        return summary
    }
}
#endif

/// The sweep, photographed: the briefing it is launched from and the chest it
/// leaves. It runs a REAL sweep on the tour's save — `duat_1_1`, which the
/// debug save three-stars — rather than building a receipt by hand, because a
/// hand-built one would photograph a screen the game cannot actually produce.
private struct TourSweepScene: View {
    @EnvironmentObject private var store: GameStore
    @State private var receipt: SweepReceipt?

    private var stage: Stage? { StageDatabase.stage("duat_1_1") }

    var body: some View {
        ZStack {
            if let stage {
                StageBriefingView(stage: stage, onStart: { _ in }, onSweep: { _ in })
                if let receipt {
                    SweepReceiptCard(
                        receipt: receipt,
                        loot: BattleSummary.loot(from: receipt.outcome) {
                            store.resolved($0)?.name ?? "Unit"
                        },
                        onClose: {}
                    )
                }
            }
        }
        .onAppear {
            guard let stage, receipt == nil else { return }
            receipt = store.sweep(stage: stage, runs: 5)
            print("[Tour] sweep duat_1_1 runs=\(receipt?.runs ?? -1) "
                  + "mastered=\(SweepService.isMastered(stage, player: store.player)) "
                  + "powered=\(SweepService.isPowered(stage, player: store.player))")
        }
    }
}
