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
    /// The wave on the field, 1-based; a dungeon run has three.
    @Published private(set) var waveIndex = 1
    /// An ultimate's cut-in: the caster's card and the skill's name sweep
    /// across the screen for a second, the genre's announcement of a big
    /// move. Cleared by the view.
    @Published var cutIn: CutIn?

    struct CutIn: Equatable {
        var portrait: String
        var unitName: String
        var skillName: String
        var accentHex: String
        /// A boss's opening line rather than a skill's name. The band is the
        /// same; the words are a sentence, so the view sets them smaller, lets
        /// them wrap and holds them longer.
        var isSpeech: Bool = false
    }
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

    private var engine: BattleEngine
    private var pendingEvents: [BattleEvent] = []

    var waveCount: Int { engine.waveCount }
    /// Not private: the result view hands it to the relic drop card.
    unowned let store: GameStore

    // MARK: - Init

    init(engine: BattleEngine, context: BattleContext, store: GameStore, repeatCount: Int = 1) {
        self.engine = engine
        self.context = context
        self.store = store
        self.displayedCombatants = engine.combatants
        sceneController.delegate = self
        sceneController.speedMultiplier = speed
        // A repeat run is on auto from the first turn; a property observer
        // does not fire in an initialiser, so the engine is told directly.
        if repeatCount > 1, case .campaign = context {
            repeatSession = RepeatSession(requested: repeatCount)
            autoBattle = true
            engine.autoBattle = true
        }
    }

    // MARK: - Auto-repeat

    /// The same stage several times over on auto, the grind the genre is
    /// built on: what was asked for, what is done, and what it all paid.
    /// Campaign stages and hall floors only; the arena spends an attack per
    /// fight and is fought by hand.
    struct RepeatSession {
        var requested: Int
        var completed = 0
        var wins = 0
        var drachma = 0
        var unitExperience = 0
        var divinity = 0
        var relics: [Relic] = []
        var essences: [String: Int] = [:]
        var scrolls: [String: Int] = [:]
        var stones: [String: Int] = [:]
        var stoppedBecause: String?

        var isFinished: Bool { completed >= requested || stoppedBecause != nil }
    }

    @Published private(set) var repeatSession: RepeatSession?
    /// A line for the HUD between runs ("Run 3 of 10"); the view clears it.
    @Published var repeatBanner: String?

    /// Asks the session to end after the run in progress.
    func stopRepeating() {
        guard var session = repeatSession else { return }
        session.requested = min(session.requested, session.completed + 1)
        repeatSession = session
    }

    /// Called by the view once the outcome has landed. On a repeat run with
    /// runs still to go, banks the rewards, starts the next fight and returns
    /// nil; otherwise returns the summary the result panel shows.
    func conclude() -> BattleSummary? {
        guard let result = outcome else { return nil }
        guard case .campaign(let stage) = context, var session = repeatSession else {
            return finish()
        }
        let stageOutcome = store.finishCampaignBattle(stage: stage, result: result)
        session.completed += 1
        if result.outcome == .victory { session.wins += 1 }
        session.drachma += stageOutcome.drachma
        session.unitExperience += stageOutcome.unitExperience
        session.divinity += stageOutcome.divinityEarned
        session.relics += stageOutcome.relicsEarned
        for (id, count) in stageOutcome.essencesEarned { session.essences[id, default: 0] += count }
        for (id, count) in stageOutcome.scrollsEarned { session.scrolls[id, default: 0] += count }
        for (id, count) in stageOutcome.stonesEarned { session.stones[id, default: 0] += count }

        if result.outcome != .victory {
            session.stoppedBecause = "Stopped after a defeat."
        } else if session.completed < session.requested, store.player.wallet.energy < stage.energyCost {
            session.stoppedBecause = "Out of energy."
        }
        repeatSession = session
        guard !session.isFinished else { return repeatSummary(session) }

        guard let next = store.startCampaignBattle(stage: stage) else {
            session.stoppedBecause = "The next run could not start."
            repeatSession = session
            return repeatSummary(session)
        }
        repeatBanner = "Run \(session.completed + 1) of \(session.requested)"
        restart(with: next)
        return nil
    }

    /// Swaps in a fresh engine for the same stage and plays it from the top;
    /// the scene is rebuilt, the HUD reset, the log kept.
    private func restart(with next: BattleEngine) {
        engine = next
        engine.autoBattle = true
        autoBattle = true
        outcome = nil
        awaitingActor = nil
        selectedSkillSlot = nil
        highlightedTarget = nil
        pendingEvents = []
        waveIndex = 1
        tallies = [:]
        lastHitter = [:]
        log.append("— Again")
        displayedCombatants = engine.combatants
        hasBegun = false
        begin()
    }

    private func repeatSummary(_ session: RepeatSession) -> BattleSummary {
        var lines: [BattleSummary.Line] = [
            .init(icon: "repeat", label: "Runs", value: "\(session.wins) won of \(session.completed)")
        ]
        if session.drachma > 0 {
            lines.append(.init(icon: "circle.hexagongrid.fill", label: "Drachma", value: "+\(session.drachma)"))
        }
        if session.unitExperience > 0 {
            lines.append(.init(icon: "arrow.up.circle.fill", label: "Unit EXP", value: "+\(session.unitExperience)"))
        }
        if session.divinity > 0 {
            lines.append(.init(icon: "sparkles", label: "Divinity", value: "+\(session.divinity)"))
        }
        if !session.relics.isEmpty {
            let byGrade = Dictionary(grouping: session.relics, by: \.grade)
            let text = byGrade.keys.sorted(by: >).map { "\($0)★ ×\(byGrade[$0]?.count ?? 0)" }.joined(separator: ", ")
            lines.append(.init(icon: "shield.lefthalf.filled", label: "Relics", value: text))
        }
        for (id, count) in session.stones.sorted(by: { $0.key < $1.key }) {
            lines.append(.init(icon: "diamond.fill", label: RelicStone.from(id: id)?.displayName ?? id, value: "+\(count)"))
        }
        for (id, count) in session.essences.sorted(by: { $0.key < $1.key }) {
            lines.append(.init(icon: "drop.triangle.fill", label: EssenceCatalog.name(for: id), value: "+\(count)"))
        }
        for (id, count) in session.scrolls.sorted(by: { $0.key < $1.key }) {
            lines.append(.init(icon: "scroll.fill", label: ScrollType(rawValue: id)?.displayName ?? id, value: "+\(count)"))
        }
        if let why = session.stoppedBecause {
            lines.append(.init(icon: "exclamationmark.triangle.fill", label: why, value: ""))
        }
        var loot: [BattleSummary.Loot] = []
        if session.drachma > 0 {
            loot.append(.init(glyph: "circle.hexagongrid.fill", title: "Drachma", amount: "+\(session.drachma.formatted())", tint: .gold))
        }
        if session.unitExperience > 0 {
            loot.append(.init(glyph: "arrow.up.circle.fill", title: "Unit EXP", amount: "+\(session.unitExperience.formatted())", tint: .verdigris))
        }
        if session.divinity > 0 {
            loot.append(.init(glyph: "sparkles", title: "Divinity", amount: "+\(session.divinity)", tint: .marble))
        }
        for relic in session.relics {
            loot.append(.init(glyph: relic.set.glyph, title: relic.displayName, amount: "Slot \(relic.slot)", tint: .gold, stars: relic.grade, relic: relic))
        }
        for (id, count) in session.stones.sorted(by: { $0.key < $1.key }) {
            guard let stone = RelicStone.from(id: id) else { continue }
            loot.append(.init(glyph: stone.kind.glyph, title: stone.displayName, amount: "+\(count)", tint: .rarity(stone.tier.quality.rarity)))
        }
        for (id, count) in session.essences.sorted(by: { $0.key < $1.key }) {
            let element = Element(rawValue: id.split(separator: "_").dropFirst().first.map(String.init) ?? "")
            loot.append(.init(glyph: "drop.triangle.fill", title: EssenceCatalog.name(for: id), amount: "+\(count)", tint: element.map { .element($0) } ?? .verdigris))
        }
        for (id, count) in session.scrolls.sorted(by: { $0.key < $1.key }) {
            if let scroll = ScrollType(rawValue: id) {
                loot.append(.init(glyph: scroll.glyph, title: scroll.displayName, amount: "+\(count)", tint: .scroll(scroll)))
            }
        }
        let (stats, mvp) = reckoning()
        let won = session.wins > 0
        return BattleSummary(
            outcome: won ? .victory : .defeat, lines: lines, stars: 0,
            title: "\(session.wins) of \(session.completed) runs won",
            turns: outcome?.turnsTaken ?? 0,
            damageDealt: outcome?.totalDamageDealt ?? 0, damageTaken: outcome?.totalDamageTaken ?? 0,
            unitStats: stats, mvpID: mvp, loot: won ? loot : []
        )
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

    /// Set the first time a boss speaks, for the reason `hasBegun` exists.
    private var hasSpoken = false

    /// The boss's line, once, into the band the ultimates use.
    ///
    /// Only a chapter's boss stage and a raid have one (`StageDatabase.bossLine`);
    /// everything else returns without touching `cutIn`, so an ordinary fight is
    /// exactly as it was. Guarded on `hasSpoken` for the same reason `begin()`
    /// is guarded: `onAppear` fires more than once, and an auto-repeat run keeps
    /// this view alive across fights — the line belongs to walking in, not to
    /// every lap.
    func announceBoss() {
        guard !hasSpoken else { return }
        hasSpoken = true
        guard case .campaign(let stage) = context,
              let boss = StageDatabase.bossLine(for: stage),
              let blueprint = UnitDatabase.blueprint(boss.blueprintID) else { return }
        cutIn = CutIn(
            portrait: blueprint.model.portraitName(awakened: false),
            unitName: blueprint.name,
            skillName: boss.line,
            accentHex: blueprint.element.accentHex,
            isSpeech: true
        )
    }

    // MARK: - Player input

    var playerTeam: [Combatant] { displayedCombatants.filter { $0.side == .player } }
    var opponentTeam: [Combatant] { displayedCombatants.filter { $0.side == .opponent } }

    // MARK: - What a raid boss is doing
    //
    // Read straight off the engine rather than mirrored into a @Published
    // field. A raid's barrier, weakness and enrage change on the BOSS's turn,
    // and `displayedCombatants` deliberately lags the engine so health bars
    // drain with the animation; mirroring these would have made the barrier
    // and the health disagree with each other on screen. The HUD reads them
    // during a render that `displayedCombatants` has already invalidated, so
    // they refresh with everything else.

    /// The barrier on a raid boss, 0...1 of its full size, or nil for a boss
    /// that carries none. The size in points is the boss's own, so a barrier
    /// at full always reads full whatever the boss's health is.
    func raidBarrierFraction(_ id: UUID) -> Double? {
        guard let bar = engine.raidBarrier(for: id), bar.maximum > 0 else { return nil }
        return min(1, max(0, bar.remaining / bar.maximum))
    }

    /// The element the boss is open to at this moment, or nil if it is not a
    /// raid boss or its weakness has not rotated in yet.
    func raidWeakness(_ id: UUID) -> Element? { engine.raidWeakness(for: id) }

    /// What the boss's enrage multiplies its damage by. 1 until its clock runs
    /// out, and worth showing only above 1.
    func raidEnrage(_ id: UUID) -> Double { engine.raidEnrage(for: id) }

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

    /// Whether the player has to aim this one, or it picks its own targets.
    static func needsTarget(_ skill: Skill) -> Bool {
        switch skill.target {
        case .singleEnemy, .lowestHealthEnemy, .singleAlly, .deadAlly: return true
        default: return false
        }
    }

    /// The first tap ARMS a skill. The second uses it.
    ///
    /// It used to be that a skill picking its own targets fired on the first
    /// tap, and only a single-target one waited. The owner met that on
    /// 2026-09-10: "when I click skill 3 for Anubis, it just immediately uses
    /// it instead of showing me what it is first." He is right, and the
    /// inconsistency was the worst part of it — two of a unit's skills paused
    /// to be read and the third went off, so the one skill a player is least
    /// likely to know is the one he could not look at without spending a turn.
    ///
    /// Now every skill arms first and shows its words in the actor plate. A
    /// second tap on the SAME skill commits it, which is also what tapping a
    /// target does for the ones that need one, so the rhythm is the same
    /// either way: choose, read, commit.
    func selectSkill(_ slot: Int) {
        guard let actor = awaitingActor, actor.isSkillReady(slot) else { return }
        guard let skill = actor.skill(at: slot) else { return }

        if selectedSkillSlot == slot {
            if Self.needsTarget(skill) {
                if let target = highlightedTarget { submit(slot: slot, target: target) }
            } else {
                submit(slot: slot, target: nil)
            }
            return
        }

        selectedSkillSlot = slot
        // Pre-aim at the most obvious target so the second tap works without
        // choosing one; a skill that needs no target simply has none.
        highlightedTarget = Self.needsTarget(skill) ? defaultTarget(for: skill, actor: actor) : nil
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
        sceneController.syncPlates(combatants: engine.combatants)
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
    /// The player's units with what each did, and who did the most. Score is
    /// damage dealt plus healing: a healer who kept the line alive is worth
    /// the laurel as much as the unit that landed the numbers.
    private func reckoning() -> (stats: [BattleSummary.UnitStat], mvp: UUID?) {
        let mine = displayedCombatants.filter { $0.side == .player }
        let stats = mine.map { unit -> BattleSummary.UnitStat in
            let tally = tallies[unit.id] ?? Tally()
            let stars = unit.sourceUnitID.flatMap { store.resolved($0)?.stars } ?? 3
            return BattleSummary.UnitStat(
                id: unit.id,
                name: unit.name,
                portraitName: unit.model.portraitName(awakened: unit.isAwakened),
                element: unit.element,
                stars: stars,
                dealt: tally.dealt,
                taken: tally.taken,
                healed: tally.healed,
                kills: tally.kills,
                survived: unit.isAlive
            )
        }
        let mvp = stats.max { ($0.dealt + $0.healed) < ($1.dealt + $1.healed) }
        return (stats, (mvp?.dealt ?? 0) + (mvp?.healed ?? 0) > 0 ? mvp?.id : nil)
    }

    private func loot(from stageOutcome: StageOutcome) -> [BattleSummary.Loot] {
        var items: [BattleSummary.Loot] = []
        if stageOutcome.drachma > 0 {
            items.append(.init(glyph: "circle.hexagongrid.fill", title: "Drachma",
                               amount: "+\(stageOutcome.drachma.formatted())", tint: .gold))
        }
        if stageOutcome.unitExperience > 0 {
            items.append(.init(glyph: "arrow.up.circle.fill", title: "Unit EXP",
                               amount: "+\(stageOutcome.unitExperience.formatted())", tint: .verdigris))
        }
        if stageOutcome.divinityEarned > 0 {
            items.append(.init(glyph: "sparkles", title: "Divinity",
                               amount: "+\(stageOutcome.divinityEarned)", tint: .marble))
        }
        for relic in stageOutcome.relicsEarned {
            items.append(.init(glyph: relic.set.glyph, title: relic.displayName,
                               amount: "Slot \(relic.slot)", tint: .gold, stars: relic.grade, relic: relic))
        }
        for (id, count) in stageOutcome.stonesEarned.sorted(by: { $0.key < $1.key }) {
            guard let stone = RelicStone.from(id: id) else { continue }
            items.append(.init(glyph: stone.kind.glyph, title: stone.displayName,
                               amount: "+\(count)", tint: .rarity(stone.tier.quality.rarity)))
        }
        for (id, count) in stageOutcome.essencesEarned.sorted(by: { $0.key < $1.key }) {
            let element = Element(rawValue: id.split(separator: "_").dropFirst().first.map(String.init) ?? "")
            items.append(.init(glyph: "drop.triangle.fill", title: EssenceCatalog.name(for: id),
                               amount: "+\(count)", tint: element.map { .element($0) } ?? .verdigris))
        }
        for (id, count) in stageOutcome.scrollsEarned.sorted(by: { $0.key < $1.key }) {
            if let scroll = ScrollType(rawValue: id) {
                items.append(.init(glyph: scroll.glyph, title: scroll.displayName,
                                   amount: "+\(count)", tint: .scroll(scroll)))
            } else {
                items.append(.init(glyph: "scroll.fill", title: id, amount: "+\(count)", tint: .gold))
            }
        }
        for (unitID, levels) in stageOutcome.leveledUnits {
            let name = store.resolved(unitID)?.name ?? "Unit"
            items.append(.init(glyph: "chevron.up.circle.fill", title: "\(name) levelled",
                               amount: "+\(levels)", tint: .laurel))
        }
        return items
    }

    func finish() -> BattleSummary {
        guard let result = outcome else {
            return BattleSummary(outcome: .draw, lines: [], stars: 0)
        }
        let (stats, mvp) = reckoning()

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
                lines.append(.init(icon: "shield.lefthalf.filled", label: relic.displayName, value: "\(relic.grade)★"))
            }
            for (id, count) in stageOutcome.stonesEarned.sorted(by: { $0.key < $1.key }) {
                lines.append(.init(icon: "diamond.fill", label: RelicStone.from(id: id)?.displayName ?? id, value: "+\(count)"))
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
            return BattleSummary(
                outcome: result.outcome, lines: lines, stars: stageOutcome.stars,
                title: stage.name, turns: result.turnsTaken,
                damageDealt: result.totalDamageDealt, damageTaken: result.totalDamageTaken,
                unitStats: stats, mvpID: mvp,
                loot: result.outcome == .victory ? loot(from: stageOutcome) : [],
                isFirstClear: stageOutcome.isFirstClear
            )

        case .arena(let opponent):
            let (delta, laurels) = store.finishArenaBattle(result: result, opponent: opponent)
            let lines: [BattleSummary.Line] = [
                .init(icon: "trophy.fill", label: "Rank Points", value: delta >= 0 ? "+\(delta)" : "\(delta)"),
                .init(icon: "laurel.leading", label: "Laurels", value: "+\(laurels)")
            ]
            var loot: [BattleSummary.Loot] = []
            if result.outcome == .victory {
                loot.append(.init(glyph: "trophy.fill", title: "Rank Points",
                                  amount: delta >= 0 ? "+\(delta)" : "\(delta)", tint: .gold))
                loot.append(.init(glyph: "laurel.leading", title: "Laurels", amount: "+\(laurels)", tint: .laurel))
            }
            return BattleSummary(
                outcome: result.outcome,
                lines: lines,
                stars: result.outcome == .victory ? 3 : 0,
                title: "vs \(opponent.name)", turns: result.turnsTaken,
                damageDealt: result.totalDamageDealt, damageTaken: result.totalDamageTaken,
                unitStats: stats, mvpID: mvp, loot: loot
            )
        }
    }

    // MARK: - The reckoning's tallies
    //
    // Kept on the class, not in the scene-delegate extension that fills
    // them: an extension may declare methods and computed properties only.
    /// What each combatant did, kept as the display advances so the reckoning
    /// at the end can name a most valuable unit. Kills go to whoever landed
    /// the last hit, which is the only definition a player will agree with.
    struct Tally {
        var dealt: Double = 0
        var taken: Double = 0
        var healed: Double = 0
        var kills: Int = 0
    }
    private var tallies: [UUID: Tally] = [:]
    private var lastHitter: [UUID: UUID] = [:]
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

    /// One of the player's units, as the reckoning reads it out.
    struct UnitStat: Identifiable {
        var id: UUID
        var name: String
        var portraitName: String
        var element: Element
        var stars: Int
        var dealt: Double
        var taken: Double
        var healed: Double
        var kills: Int
        var survived: Bool
    }

    /// A colour the model can name without importing SwiftUI; the view turns
    /// it into paint.
    enum LootTint {
        case gold, verdigris, laurel, wine, marble
        case element(Element)
        case scroll(ScrollType)
        /// A whetstone or a gem, in its tier's metal.
        case rarity(Rarity)
    }

    /// One thing the chest gives up. A relic carries itself so the tile can
    /// draw the stone and open the drop card; everything else is a glyph on
    /// a plate.
    struct Loot: Identifiable {
        var id = UUID()
        var glyph: String
        var title: String
        var amount: String
        var tint: LootTint
        var stars: Int? = nil
        var relic: Relic? = nil
    }

    var outcome: BattleOutcome
    var lines: [Line]
    var stars: Int

    // The reckoning. Defaulted so the places that only ever built a three
    // field summary keep compiling; `finish()` and the repeat summary fill
    // them, the forfeit path does not need them.
    var title: String = ""
    var turns: Int = 0
    var damageDealt: Double = 0
    var damageTaken: Double = 0
    var unitStats: [UnitStat] = []
    var mvpID: UUID? = nil
    var loot: [Loot] = []
    var isFirstClear: Bool = false
}

// MARK: - Scene playback

extension BattleViewModel: BattleSceneDelegate {

    nonisolated func battleScene(_ controller: BattleSceneController, willPresent event: BattleEvent) {
        Task { @MainActor in
            self.record(event)
            self.applyToDisplay(event)
            if case .skillCast(let actor, _, let skillName, _, _, let animation, _) = event, animation == .ultimate,
               let caster = self.displayedCombatants.first(where: { $0.id == actor }) {
                self.cutIn = CutIn(
                    portrait: caster.model.portraitName(awakened: caster.isAwakened),
                    unitName: caster.name,
                    skillName: skillName,
                    accentHex: caster.element.accentHex
                )
            }
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
        case .damage(let source, let target, let amount, _, _, _, let remaining, _, _):
            mutate(target) { $0.currentHealth = remaining }
            tallies[source, default: Tally()].dealt += amount
            tallies[target, default: Tally()].taken += amount
            lastHitter[target] = source
        case .healed(let source, let target, let amount, let remaining):
            mutate(target) { $0.currentHealth = remaining }
            tallies[source, default: Tally()].healed += amount
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
            if let killer = lastHitter[target] { tallies[killer, default: Tally()].kills += 1 }
        case .revived(let target, let health):
            mutate(target) { $0.currentHealth = health }
        case .cooldownStarted(let actor, let slot, let turns):
            mutate(actor) {
                if $0.cooldowns.indices.contains(slot) { $0.cooldowns[slot] = turns }
            }
        case .waveStarted(let wave, _, let opponents):
            waveIndex = wave
            for arrival in opponents where !displayedCombatants.contains(where: { $0.id == arrival.id }) {
                displayedCombatants.append(arrival)
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
        case .waveStarted(let wave, let count, _):
            line = "Wave \(wave) of \(count) takes the field."
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
