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
        ("halls", 2), ("relics", 2), ("shop", 2),
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
        .preferredColorScheme(.dark)
        .onAppear {
            seedIfNeeded()
            if current == "battle" { startBattle() }
            if current == "arena_battle" { startArenaBattle() }
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
                Color.black.ignoresSafeArea()
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
                Color.black.ignoresSafeArea()
                    .onAppear { startArenaBattle() }
            }
        case "halls":
            CampaignView(mode: .halls)
        case "relics":
            RelicInventoryView()
        case "shop":
            ShopView()
        default:
            SettingsView()
        }
    }

    private func tick() {
        ticksOnStep += 1
        guard ticksOnStep >= Self.schedule[min(index, Self.schedule.count - 1)].ticks else { return }
        ticksOnStep = 0
        if index + 1 < Self.schedule.count {
            index += 1
            if current == "battle" { startBattle() }
            if current == "arena_battle" { startArenaBattle() }
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
}
#endif
