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
        ("relic_sets", 2), ("tribute", 2),
    ]

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
        }
        .onReceive(timer) { _ in
            if Self.pinnedStep == nil { tick() }
            // The battles play themselves a command at a time, so the frames
            // catch a dash, a hit and a flash rather than a line of units
            // waiting for a thumb. Auto-battle would win before the first
            // frame; one basic attack every four seconds is a fight in
            // progress for the whole step.
            for model in [battleModel, arenaModel].compactMap({ $0 }) {
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
        case "relics":
            RelicInventoryView()
        case "shop":
            ShopView()
        case "chapter_map":
            // The first chapter's road, with the Normal / Hard / Hell chips
            // above it; the world map is the `island` step's neighbour and
            // is seen from there.
            CampaignView(openingChapter: "duat_1")
        case "missions":
            MissionsView()
        case "victory":
            // The two acts of a win without fighting one: the reckoning,
            // then the chest opening on its spoils. `autoplay` taps through
            // for the camera.
            BattleResultView(summary: Self.demoVictory(relic: bestRelic), onDismiss: {}, autoplay: true, store: store)
                .background(Color.black.ignoresSafeArea())
        default:
            SettingsView()
        }
    }

    /// The relic the relic steps photograph: the highest grade, and among
    /// those the highest level, so the level track and the rim both show.
    private var bestRelic: Relic? {
        store.player.relics.max(by: { ($0.grade, $0.level) < ($1.grade, $1.level) })
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
        }
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        store.grantTourRoster()
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
            .init(glyph: "circle.hexagongrid.fill", title: "Drachma", amount: "+1,240", tint: .gold),
            .init(glyph: "arrow.up.circle.fill", title: "Unit EXP", amount: "+860", tint: .verdigris),
            .init(glyph: "sparkles", title: "Divinity", amount: "+15", tint: .marble),
            .init(glyph: RelicSet.fury.glyph, title: relic?.displayName ?? "Hero Fury Relic", amount: "Slot \(relic?.slot ?? 4)",
                  tint: .gold, stars: relic?.grade ?? 5, relic: relic),
            .init(glyph: "drop.triangle.fill", title: "Ember Essence", amount: "+3", tint: .element(.ember)),
            .init(glyph: ScrollType.unknown.glyph, title: ScrollType.unknown.displayName, amount: "+1", tint: .scroll(.unknown)),
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
}
#endif
