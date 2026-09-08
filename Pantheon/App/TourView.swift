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

    @State private var index = 0
    @State private var ticksOnStep = 0
    @State private var battleModel: BattleViewModel?
    @State private var seeded = false

    /// One entry per screen: what to show and how many ticks to hold it.
    private static let schedule: [(name: String, ticks: Int)] = [
        ("island", 2), ("collection", 2), ("detail", 2), ("training", 2),
        ("summon", 2), ("reveal", 3), ("battle", 8), ("arena", 2), ("more", 2),
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
        .onAppear { seedIfNeeded() }
        .onReceive(timer) { _ in tick() }
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
        }
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        store.grantTourRoster()
    }

    private func startBattle() {
        guard battleModel == nil,
              let stage = StageDatabase.stage("duat_1_2") ?? StageDatabase.stage("duat_1_1"),
              let engine = store.startCampaignBattle(stage: stage) else { return }
        let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
        model.autoBattle = true
        battleModel = model
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
