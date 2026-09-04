import Foundation
import SwiftUI
import Combine

/// Where a battle came from, and what to do when it ends.
enum BattleContext: Identifiable {
    case campaign(Stage)
    case arena(ArenaOpponent)

    var id: String {
        switch self {
        case .campaign(let stage): return "campaign_\(stage.id)"
        case .arena(let opponent): return "arena_\(opponent.id)"
        }
    }

    var environment: BattleEnvironment {
        switch self {
        case .campaign(let stage): return stage.environment
        case .arena: return .arenaOfSouls
        }
    }

    var title: String {
        switch self {
        case .campaign(let stage): return stage.name
        case .arena(let opponent): return "vs \(opponent.name)"
        }
    }
}

/// Drives one battle: owns the engine, owns the scene, and keeps the HUD in
/// step with what the player is actually watching.
///
/// The engine resolves a whole turn the instant an action is submitted. The
/// scene then plays that turn back over a couple of seconds. The HUD reads
/// `displayedCombatants`, which advances with the *animation*, so health bars
/// and status pips never jump ahead of the hit that caused them.
@MainActor
final class BattleViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var displayedCombatants: [Combatant] = []
    @Published private(set) var turnOrderPreview: [Combatant] = []
    @Published private(set) var awaitingActor: Combatant?
    @Published private(set) var selectedSkillSlot: Int?
    @Published private(set) var isPlayingBack = false
    @Published private(set) var outcome: BattleResult?
    @Published private(set) var log: [String] = []
    @Published var autoBattle = false {
        didSet {
            engine.autoBattle = autoBattle
            if autoBattle, awaitingActor != nil { takeAutoTurn() }
        }
    }
    @Published var speed: Double = 1.0 {
        didSet { sceneController.speedMultiplier = speed }
    }
    /// Set when the player taps a unit while choosing a target.
    @Published var highlightedTarget: UUID?

    let context: BattleContext
    let sceneController = BattleSceneController()

    private let engine: BattleEngine
    private var pendingEvents: [BattleEvent] = []
    private unowned let store: GameStore

    // MARK: - Init

    init(engine: BattleEngine, context: BattleContext, store: GameStore) {
        self.engine = engine
        self.context = context
        self.store = store
        self.displayedCombatants = engine.combatants
        sceneController.delegate = self
        sceneController.speedMultiplier = speed
    }

    /// `onAppear` can fire more than once for the same view; starting the
    /// engine twice would replay the opening turn, so it is guarded.
    private var hasBegun = false

    func begin() {
        guard !hasBegun else { return }
        hasBegun = true
        sceneController.build(combatants: engine.combatants, environment: context.environment)
        consume(engine.start())
    }

    // MARK: - Player input

    var playerTeam: [Combatant] { displayedCombatants.filter { $0.side == .player } }
    var opponentTeam: [Combatant] { displayedCombatants.filter { $0.side == .opponent } }

    /// Skills the waiting actor can use, with their cooldown state.
    var availableSkills: [SkillOption] {
        guard let actor = awaitingActor else { return [] }
        return actor.skills.indices.compactMap { slot in
            let skill = actor.skills[slot]
            guard !skill.isPassive else { return nil }
            return SkillOption(
                slot: slot,
                skill: skill,
                cooldown: actor.cooldowns.indices.contains(slot) ? actor.cooldowns[slot] : 0
            )
        }
    }

    func selectSkill(_ slot: Int) {
        guard let actor = awaitingActor, actor.isSkillReady(slot) else { return }
        guard let skill = actor.skill(at: slot) else { return }

        // Skills that pick their own targets fire immediately; single-target
        // skills wait for a tap so the player can aim.
        let needsTarget: Bool
        switch skill.target {
        case .singleEnemy, .lowestHealthEnemy, .singleAlly, .deadAlly: needsTarget = true
        default: needsTarget = false
        }

        if needsTarget {
            selectedSkillSlot = slot
            // Pre-aim at the most obvious target so a single tap works.
            highlightedTarget = defaultTarget(for: skill, actor: actor)
        } else {
            submit(slot: slot, target: nil)
        }
    }

    func tapUnit(_ combatantID: UUID) {
        guard let actor = awaitingActor, let slot = selectedSkillSlot else { return }
        let legal = engine.validTargets(for: actor.id, skillSlot: slot)
        guard legal.contains(combatantID) else { return }
        submit(slot: slot, target: combatantID)
    }

    /// Confirms the currently highlighted target.
    func confirmTarget() {
        guard let slot = selectedSkillSlot, let target = highlightedTarget else { return }
        submit(slot: slot, target: target)
    }

    func cancelTargeting() {
        selectedSkillSlot = nil
        highlightedTarget = nil
    }

    private func defaultTarget(for skill: Skill, actor: Combatant) -> UUID? {
        let legal = engine.validTargets(for: actor.id, skillSlot: skill.slot)
        let candidates = displayedCombatants.filter { legal.contains($0.id) }
        if skill.target.hitsEnemies {
            return candidates.min(by: { $0.currentHealth < $1.currentHealth })?.id
        }
        return candidates.min(by: { $0.healthFraction < $1.healthFraction })?.id
    }

    private func submit(slot: Int, target: UUID?) {
        guard let actor = awaitingActor else { return }
        awaitingActor = nil
        selectedSkillSlot = nil
        highlightedTarget = nil
        let events = engine.submit(
            BattleAction(actorID: actor.id, skillSlot: slot, targetID: target)
        )
        consume(events)
    }

    private func takeAutoTurn() {
        guard let actor = awaitingActor else { return }
        var rng = SeededRandom(seed: UInt64(actor.attackBar * 1_000_000) &+ UInt64(engine.turnNumber))
        let action = AIController.chooseAction(
            actorIndex: engine.combatants.firstIndex(where: { $0.id == actor.id }) ?? 0,
            combatants: engine.combatants,
            engine: engine,
            rng: &rng
        )
        awaitingActor = nil
        consume(engine.submit(action))
    }

    // MARK: - Playback

    private func consume(_ events: [BattleEvent]) {
        guard !events.isEmpty else {
            settleAfterPlayback()
            return
        }
        pendingEvents = events
        isPlayingBack = true
        sceneController.enqueue(events)
    }

    /// Jumps to the end of the current turn's animation.
    func skipAnimation() {
        sceneController.flush(combatants: engine.combatants)
    }

    /// Abandons the battle. Campaign energy is not refunded once a turn has
    /// resolved, which is the standard rule and is stated on the confirm dialog.
    func forfeit() {
        outcome = BattleResult(
            outcome: .defeat,
            turnsTaken: engine.turnNumber,
            survivorFraction: 0,
            totalDamageDealt: 0,
            totalDamageTaken: 0,
            seed: 0
        )
    }

    private func settleAfterPlayback() {
        isPlayingBack = false
        displayedCombatants = engine.combatants
        refreshTurnOrder()

        if let result = engine.result {
            outcome = result
            return
        }

        if let waitingID = engine.awaitingActor,
           let actor = engine.combatants.first(where: { $0.id == waitingID }) {
            awaitingActor = actor
            if autoBattle { takeAutoTurn() }
        }
    }

    /// Predicts the next few actors from current speed and attack bars. It is a
    /// projection, not a promise — attack-bar manipulation changes it mid-turn,
    /// which is exactly what makes the preview worth showing.
    private func refreshTurnOrder() {
        var simulated = engine.combatants.filter(\.isAlive).map {
            (id: $0.id, bar: $0.attackBar, speed: max(1.0, $0.currentStats.spd))
        }
        var order: [UUID] = []

        for _ in 0..<6 {
            guard !simulated.isEmpty else { break }
            // Time for each to reach a full bar; smallest goes next.
            let times = simulated.map { (1.0 - $0.bar) / ($0.speed * BattleEngine.attackBarRate) }
            guard let nextIndex = times.indices.min(by: { times[$0] < times[$1] }) else { break }
            let elapsed = times[nextIndex]
            for index in simulated.indices {
                simulated[index].bar = min(1.0, simulated[index].bar + simulated[index].speed * BattleEngine.attackBarRate * elapsed)
            }
            order.append(simulated[nextIndex].id)
            simulated[nextIndex].bar = 0
        }

        turnOrderPreview = order.compactMap { id in
            engine.combatants.first(where: { $0.id == id })
        }
    }

    // MARK: - Results

    /// Applies rewards. Returns a summary the result screen renders.
    func finish() -> BattleSummary {
        guard let result = outcome else {
            return BattleSummary(outcome: .draw, lines: [], stars: 0)
        }

        switch context {
        case .campaign(let stage):
            let stageOutcome = store.finishCampaignBattle(stage: stage, result: result)
            var lines: [BattleSummary.Line] = []
            if stageOutcome.drachma > 0 {
                lines.append(.init(icon: "circle.hexagongrid.fill", label: "Drachma", value: "+\(stageOutcome.drachma)"))
            }
            if stageOutcome.unitExperience > 0 {
                lines.append(.init(icon: "arrow.up.circle.fill", label: "Unit EXP", value: "+\(stageOutcome.unitExperience)"))
            }
            if stageOutcome.divinityEarned > 0 {
                lines.append(.init(icon: "sparkles", label: "Divinity", value: "+\(stageOutcome.divinityEarned)"))
            }
            for relic in stageOutcome.relicsEarned {
                lines.append(.init(icon: "shield.lefthalf.filled", label: "\(relic.set.displayName) Relic", value: "\(relic.grade)★"))
            }
            for (id, count) in stageOutcome.essencesEarned {
                lines.append(.init(icon: "drop.triangle.fill", label: EssenceCatalog.name(for: id), value: "+\(count)"))
            }
            for (id, count) in stageOutcome.scrollsEarned {
                let name = ScrollType(rawValue: id)?.displayName ?? id
                lines.append(.init(icon: "scroll.fill", label: name, value: "+\(count)"))
            }
            for (unitID, levels) in stageOutcome.leveledUnits {
                let name = store.resolved(unitID)?.name ?? "Unit"
                lines.append(.init(icon: "chevron.up.circle.fill", label: "\(name) levelled", value: "+\(levels)"))
            }
            return BattleSummary(outcome: result.outcome, lines: lines, stars: stageOutcome.stars)

        case .arena(let opponent):
            let (delta, laurels) = store.finishArenaBattle(result: result, opponent: opponent)
            let lines: [BattleSummary.Line] = [
                .init(icon: "trophy.fill", label: "Rank Points", value: delta >= 0 ? "+\(delta)" : "\(delta)"),
                .init(icon: "laurel.leading", label: "Laurels", value: "+\(laurels)")
            ]
            return BattleSummary(
                outcome: result.outcome,
                lines: lines,
                stars: result.outcome == .victory ? 3 : 0
            )
        }
    }
}

/// One entry in the battle command bar.
struct SkillOption: Identifiable {
    var slot: Int
    var skill: Skill
    var cooldown: Int

    var id: Int { slot }
    var isReady: Bool { cooldown <= 0 }
}

struct BattleSummary {
    struct Line: Identifiable {
        var id = UUID()
        var icon: String
        var label: String
        var value: String
    }

    var outcome: BattleOutcome
    var lines: [Line]
    var stars: Int
}

// MARK: - Scene playback

extension BattleViewModel: BattleSceneDelegate {

    nonisolated func battleScene(_ controller: BattleSceneController, willPresent event: BattleEvent) {
        Task { @MainActor in
            self.record(event)
            self.applyToDisplay(event)
        }
    }

    nonisolated func battleSceneDidFinishPlayback(_ controller: BattleSceneController) {
        Task { @MainActor in
            self.settleAfterPlayback()
        }
    }

    /// Advances the HUD's copy of the world one event at a time so the numbers
    /// on screen always match the animation that is playing.
    private func applyToDisplay(_ event: BattleEvent) {
        func mutate(_ id: UUID, _ change: (inout Combatant) -> Void) {
            guard let index = displayedCombatants.firstIndex(where: { $0.id == id }) else { return }
            change(&displayedCombatants[index])
        }

        switch event {
        case .damage(_, let target, _, _, _, _, let remaining, _, _):
            mutate(target) { $0.currentHealth = remaining }
        case .healed(_, let target, _, let remaining):
            mutate(target) { $0.currentHealth = remaining }
        case .statusApplied(let source, let target, let kind, let turns):
            mutate(target) {
                $0.statuses.append(ActiveStatus(kind: kind, turnsRemaining: turns, sourceID: source))
            }
        case .statusExpired(let target, let kind), .statusRemoved(let target, let kind, _):
            mutate(target) {
                if let index = $0.statuses.firstIndex(where: { $0.kind == kind }) {
                    $0.statuses.remove(at: index)
                }
            }
        case .attackBarChanged(let target, _, let newValue):
            mutate(target) { $0.attackBar = newValue }
        case .defeated(let target):
            mutate(target) { $0.currentHealth = 0; $0.statuses.removeAll() }
        case .revived(let target, let health):
            mutate(target) { $0.currentHealth = health }
        case .cooldownStarted(let actor, let slot, let turns):
            mutate(actor) {
                if $0.cooldowns.indices.contains(slot) { $0.cooldowns[slot] = turns }
            }
        default:
            break
        }
    }

    private func record(_ event: BattleEvent) {
        func name(_ id: UUID) -> String {
            displayedCombatants.first(where: { $0.id == id })?.name ?? "?"
        }

        let line: String?
        switch event {
        case .turnBegan(let actor, let turn):
            line = "— Turn \(turn): \(name(actor))"
        case .turnSkipped(let actor, let reason):
            line = "\(name(actor)) is \(reason.displayName) and loses the turn."
        case .skillCast(let actor, _, let skill, _, _, _, _):
            line = "\(name(actor)) uses \(skill)."
        case .damage(_, let target, let amount, let crit, let glancing, let matchup, _, _, _):
            var suffix = ""
            if crit { suffix = " (CRIT)" }
            else if glancing { suffix = " (glancing)" }
            else if matchup == .advantage { suffix = " (advantage)" }
            line = "\(name(target)) takes \(Int(amount.rounded())) damage\(suffix)."
        case .healed(_, let target, let amount, _):
            line = "\(name(target)) recovers \(Int(amount.rounded())) HP."
        case .statusApplied(_, let target, let kind, let turns):
            line = "\(name(target)) gains \(kind.displayName) for \(turns) turn\(turns == 1 ? "" : "s")."
        case .statusResisted(_, let target, let kind):
            line = "\(name(target)) resists \(kind.displayName)."
        case .counterattack(let actor, _):
            line = "\(name(actor)) counterattacks."
        case .extraTurnGranted(let actor, let source):
            line = "\(name(actor)) gains an extra turn (\(source))."
        case .passiveTriggered(let actor, let passive):
            line = "\(name(actor)): \(passive)."
        case .revived(let target, _):
            line = "\(name(target)) is revived."
        case .defeated(let target):
            line = "\(name(target)) is defeated."
        case .battleEnded(let result):
            line = result.outcome == .victory ? "Victory." : (result.outcome == .defeat ? "Defeat." : "Draw.")
        default:
            line = nil
        }

        if let line {
            log.append(line)
            if log.count > 200 { log.removeFirst(log.count - 200) }
        }
    }
}
