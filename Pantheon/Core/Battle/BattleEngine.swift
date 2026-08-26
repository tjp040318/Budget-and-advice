import Foundation

enum BattleMode: String, Codable, Sendable {
    case campaign
    case arenaOffense = "arena_offense"
    /// Headless simulation used to score a defence team without rendering it.
    case simulation
}

/// A player's chosen move.
struct BattleAction: Sendable {
    var actorID: UUID
    var skillSlot: Int
    /// Nil for skills that pick their own targets (AoE, self, team heals).
    var targetID: UUID?
}

/// The turn-based combat simulation.
///
/// The engine owns all state and emits `BattleEvent`s. It is completely free of
/// UIKit, SceneKit and Foundation date/time — the only nondeterminism is the
/// seed handed in. Call `start()`, then `submit(_:)` each time `awaitingActor`
/// is non-nil; the engine runs every AI turn in between on its own.
final class BattleEngine {

    // MARK: - Configuration

    /// Attack bar units gained per speed point per tick. Purely a pacing knob.
    static let attackBarRate: Double = 0.07
    /// Turn cap. A stalled battle is a draw rather than an infinite loop.
    static let maxTurns: Int = 150
    /// Counterattacks cannot chain past this depth.
    static let maxCounterDepth: Int = 1

    let mode: BattleMode
    private(set) var combatants: [Combatant]
    private(set) var turnNumber: Int = 0
    private(set) var isFinished: Bool = false
    private(set) var result: BattleResult?

    /// Non-nil when the engine is blocked on a player decision.
    private(set) var awaitingActor: UUID?

    /// When true the engine plays the player's side itself.
    var autoBattle: Bool = false

    private var rng: SeededRandom
    private let seed: UInt64
    private var damageDealt: Double = 0
    private var damageTaken: Double = 0
    /// Set when a passive or a relic set hands the current actor another turn.
    private var pendingExtraTurnFor: UUID?

    // MARK: - Setup

    init(
        playerTeam: [ResolvedUnit],
        opponentTeam: [ResolvedUnit],
        mode: BattleMode,
        seed: UInt64
    ) {
        self.mode = mode
        self.seed = seed
        self.rng = SeededRandom(seed: seed)

        let playerCombatants = BattleEngine.buildSide(playerTeam, side: .player, mode: mode)
        let opponentCombatants = BattleEngine.buildSide(opponentTeam, side: .opponent, mode: mode)
        self.combatants = playerCombatants + opponentCombatants
    }

    /// Builds one side, applying the leader's skill to everyone who qualifies.
    private static func buildSide(
        _ team: [ResolvedUnit],
        side: BattleSide,
        mode: BattleMode
    ) -> [Combatant] {
        guard let leader = team.first else { return [] }
        let leaderSkill = leader.blueprint.leaderSkill
        let applies: Bool = {
            guard let leaderSkill else { return false }
            switch mode {
            case .arenaOffense, .simulation: return leaderSkill.appliesInArena
            case .campaign: return leaderSkill.appliesInCampaign
            }
        }()

        return team.enumerated().map { index, resolved in
            var stats = resolved.stats
            if applies, let leaderSkill, leaderSkill.applies(to: resolved.blueprint) {
                stats = BattleEngine.apply(leaderSkill, to: stats, base: resolved.stats)
            }
            return Combatant(
                resolved: resolved,
                side: side,
                slot: index,
                isLeader: index == 0,
                statsOverride: stats
            )
        }
    }

    private static func apply(_ leader: LeaderSkill, to stats: Stats, base: Stats) -> Stats {
        var result = stats
        switch leader.stat {
        case .hpFlat, .hpPercent: result.hp += base.hp * leader.amount
        case .atkFlat, .atkPercent: result.atk += base.atk * leader.amount
        case .defFlat, .defPercent: result.def += base.def * leader.amount
        case .spd: result.spd += base.spd * leader.amount
        case .critRate: result.critRate += leader.amount
        case .critDamage: result.critDamage += leader.amount
        case .accuracy: result.accuracy += leader.amount
        case .resistance: result.resistance += leader.amount
        }
        return result.clamped()
    }

    // MARK: - Lookups

    func combatant(_ id: UUID) -> Combatant? { combatants.first(where: { $0.id == id }) }
    private func index(of id: UUID) -> Int? { combatants.firstIndex(where: { $0.id == id }) }

    func team(_ side: BattleSide) -> [Combatant] { combatants.filter { $0.side == side } }
    private func aliveIndices(_ side: BattleSide) -> [Int] {
        combatants.indices.filter { combatants[$0].side == side && combatants[$0].isAlive }
    }

    /// Skill slots the actor can legally use right now.
    func availableSkillSlots(for actorID: UUID) -> [Int] {
        guard let idx = index(of: actorID) else { return [] }
        let actor = combatants[idx]
        return actor.skills.indices.filter { actor.isSkillReady($0) }
    }

    /// Legal targets for a slot. Self- and team-targeting skills return allies.
    func validTargets(for actorID: UUID, skillSlot: Int) -> [UUID] {
        guard let idx = index(of: actorID), let skill = combatants[idx].skill(at: skillSlot) else { return [] }
        let actor = combatants[idx]
        if let provoke = actor.status(.provoke), let sourceID = provoke.sourceID,
           skill.target.hitsEnemies, let source = combatant(sourceID), source.isAlive {
            return [sourceID]
        }
        switch skill.target {
        case .singleEnemy, .lowestHealthEnemy, .allEnemies, .randomEnemies:
            return aliveIndices(actor.side.opposing).map { combatants[$0].id }
        case .singleAlly, .lowestHealthAlly, .allAllies:
            return aliveIndices(actor.side).map { combatants[$0].id }
        case .otherAllies:
            return aliveIndices(actor.side).map { combatants[$0].id }.filter { $0 != actorID }
        case .caster:
            return [actorID]
        case .deadAlly:
            return combatants.filter { $0.side == actor.side && !$0.isAlive }.map(\.id)
        }
    }

    // MARK: - Driving the battle

    /// Begins the battle and runs until the first player decision (or the end).
    func start() -> [BattleEvent] {
        var events: [BattleEvent] = [
            .battleStart(
                playerTeam: team(.player).map(\.id),
                opponentTeam: team(.opponent).map(\.id)
            )
        ]
        events += applyBattleStartEffects()
        events += advance()
        return events
    }

    /// Applies opening effects — currently the Fates shield.
    private func applyBattleStartEffects() -> [BattleEvent] {
        var events: [BattleEvent] = []
        for idx in combatants.indices where combatants[idx].hasRelicSet(.fates) {
            let shieldValue = combatants[idx].maxHealth * 0.15
            combatants[idx].statuses.append(
                ActiveStatus(kind: .shield, turnsRemaining: 3, sourceID: combatants[idx].id, magnitude: shieldValue)
            )
            events.append(.statusApplied(source: combatants[idx].id, target: combatants[idx].id, kind: .shield, turns: 3))
        }
        for idx in combatants.indices {
            events += firePassive(.onBattleStart, actorIndex: idx)
        }
        return events
    }

    // MARK: - Passives

    /// Fires the actor's passive if it matches the trigger. Passives apply their
    /// statuses and utilities but never deal damage directly — a passive that
    /// needs to hit something casts one of the unit's own skills instead.
    private func firePassive(_ trigger: PassiveTrigger, actorIndex: Int) -> [BattleEvent] {
        guard combatants.indices.contains(actorIndex), combatants[actorIndex].isAlive else { return [] }
        guard let passive = combatants[actorIndex].skills.first(where: { $0.isPassive && $0.trigger == trigger })
        else { return [] }

        // Once-only triggers are spent the first time they fire.
        let onceOnly = trigger == .onBattleStart || trigger == .onLowHealth
        if onceOnly {
            guard !combatants[actorIndex].firedPassives.contains(passive.id) else { return [] }
            combatants[actorIndex].firedPassives.insert(passive.id)
        }

        // Oblivion-style suppression would be checked here; Silence blocks
        // beneficial passives only.
        if combatants[actorIndex].has(.silence), passive.statuses.contains(where: { $0.kind.isBuff }) {
            return []
        }

        var events: [BattleEvent] = [.passiveTriggered(actor: combatants[actorIndex].id, name: passive.name)]
        for spec in passive.statuses {
            let targets = resolveTargets(spec.target, actorIndex: actorIndex, explicit: nil)
            events += applyStatus(spec, actorIndex: actorIndex, defaultTargets: targets)
        }
        for utility in passive.utilities {
            events += applyUtility(utility, actorIndex: actorIndex, explicit: nil, damageDealt: 0)
        }
        return events
    }

    /// Resolves the awaited player action, then runs on to the next decision.
    func submit(_ action: BattleAction) -> [BattleEvent] {
        guard !isFinished, awaitingActor == action.actorID, let idx = index(of: action.actorID) else {
            return []
        }
        awaitingActor = nil
        var events = performTurn(actorIndex: idx, action: action)
        events += finishTurn(actorIndex: idx)
        if let ending = checkForEnding() {
            events.append(ending)
            return events
        }
        events += advance()
        return events
    }

    /// Runs ticks and AI turns until a player must choose or the battle ends.
    private func advance() -> [BattleEvent] {
        var events: [BattleEvent] = []

        while !isFinished {
            if let ending = checkForEnding() {
                events.append(ending)
                break
            }

            guard let actorIndex = nextActorIndex() else {
                events.append(finishBattle(outcome: .draw))
                break
            }

            turnNumber += 1
            if turnNumber > BattleEngine.maxTurns {
                events.append(finishBattle(outcome: .draw))
                break
            }

            let actorID = combatants[actorIndex].id
            combatants[actorIndex].attackBar = 0
            events.append(.turnBegan(actor: actorID, turnNumber: turnNumber))
            events += applyTurnStartEffects(actorIndex: actorIndex)

            // Turn-start damage can kill the actor outright.
            guard combatants[actorIndex].isAlive else {
                events += finishTurn(actorIndex: actorIndex)
                continue
            }

            if let cc = combatants[actorIndex].statuses.first(where: { $0.kind.isHardCC && $0.turnsRemaining > 0 }) {
                events.append(.turnSkipped(actor: actorID, reason: cc.kind))
                events += finishTurn(actorIndex: actorIndex)
                continue
            }

            let isPlayerControlled = combatants[actorIndex].side == .player && !autoBattle && mode != .simulation
            if isPlayerControlled {
                awaitingActor = actorID
                break
            }

            let action = AIController.chooseAction(
                actorIndex: actorIndex,
                combatants: combatants,
                engine: self,
                rng: &rng
            )
            events += performTurn(actorIndex: actorIndex, action: action)
            events += finishTurn(actorIndex: actorIndex)
        }

        return events
    }

    /// Advances every attack bar until exactly one combatant is ready to act.
    /// Uses continuous time rather than fixed ticks so identical speeds resolve
    /// by slot order instead of by float drift.
    private func nextActorIndex() -> Int? {
        let alive = combatants.indices.filter { combatants[$0].isAlive }
        guard !alive.isEmpty else { return nil }

        // Anyone already at full bar acts first.
        if let ready = readyActor(from: alive) { return ready }

        var smallestTime = Double.greatestFiniteMagnitude
        for idx in alive {
            let speed = max(1, combatants[idx].currentStats.spd) * BattleEngine.attackBarRate
            let time = (1.0 - combatants[idx].attackBar) / speed
            smallestTime = min(smallestTime, time)
        }
        guard smallestTime.isFinite else { return nil }

        for idx in alive {
            let speed = max(1, combatants[idx].currentStats.spd) * BattleEngine.attackBarRate
            combatants[idx].attackBar = min(1.0, combatants[idx].attackBar + speed * smallestTime)
        }
        return readyActor(from: alive)
    }

    /// Ties break on higher effective speed, then the player's side, then slot.
    private func readyActor(from alive: [Int]) -> Int? {
        let ready = alive.filter { combatants[$0].attackBar >= 1.0 - 1e-9 }
        guard !ready.isEmpty else { return nil }
        return ready.max { lhs, rhs in
            let l = combatants[lhs], r = combatants[rhs]
            if l.currentStats.spd != r.currentStats.spd { return l.currentStats.spd < r.currentStats.spd }
            if l.side != r.side { return l.side == .opponent }
            return l.slot > r.slot
        }
    }

    // MARK: - Turn phases

    private func applyTurnStartEffects(actorIndex: Int) -> [BattleEvent] {
        var events: [BattleEvent] = []
        let actorID = combatants[actorIndex].id

        // Bombs detonate before the victim can act, and eat the turn.
        let bombs = combatants[actorIndex].statuses.filter { $0.kind == .bomb && $0.turnsRemaining <= 1 }
        for bomb in bombs {
            let amount = bomb.magnitude
            events += applyDamage(
                targetIndex: actorIndex,
                amount: amount,
                sourceID: bomb.sourceID ?? actorID,
                isCritical: true,
                isGlancing: false,
                matchup: .neutral,
                hitIndex: 0,
                hitCount: 1,
                allowCounter: false
            )
            combatants[actorIndex].statuses.removeAll { $0.id == bomb.id }
            events.append(.statusRemoved(target: actorID, kind: .bomb, byStrip: false))
            if combatants[actorIndex].isAlive {
                combatants[actorIndex].statuses.append(
                    ActiveStatus(kind: .stun, turnsRemaining: 1, sourceID: bomb.sourceID)
                )
                events.append(.statusApplied(source: bomb.sourceID ?? actorID, target: actorID, kind: .stun, turns: 1))
            }
        }

        guard combatants[actorIndex].isAlive else { return events }

        // Burn ticks for a flat share of max HP.
        if combatants[actorIndex].has(.burn) {
            let amount = combatants[actorIndex].maxHealth * 0.05
            let sourceID = combatants[actorIndex].status(.burn)?.sourceID ?? actorID
            events += applyDamage(
                targetIndex: actorIndex,
                amount: amount,
                sourceID: sourceID,
                isCritical: false,
                isGlancing: false,
                matchup: .neutral,
                hitIndex: 0,
                hitCount: 1,
                allowCounter: false
            )
        }

        guard combatants[actorIndex].isAlive else { return events }

        // Recovery regenerates.
        if combatants[actorIndex].has(.recovery) {
            let amount = combatants[actorIndex].maxHealth * 0.15
            events += applyHealing(targetIndex: actorIndex, amount: amount, sourceID: actorID)
        }

        // Ichor tops up the bar for the *next* turn.
        let ichorStacks = combatants[actorIndex].relicSetStacks(.ichor)
        if ichorStacks > 0 {
            let delta = 0.25 * Double(ichorStacks)
            events.append(contentsOf: changeAttackBar(index: actorIndex, delta: delta))
        }

        events += firePassive(.onTurnStart, actorIndex: actorIndex)

        return events
    }

    /// Applies cooldowns, decrements statuses and honours extra-turn effects.
    private func finishTurn(actorIndex: Int) -> [BattleEvent] {
        var events: [BattleEvent] = []
        let actorID = combatants[actorIndex].id

        for slot in combatants[actorIndex].cooldowns.indices where combatants[actorIndex].cooldowns[slot] > 0 {
            combatants[actorIndex].cooldowns[slot] -= 1
        }

        events += tickStatuses(index: actorIndex)

        guard combatants[actorIndex].isAlive else { return events }

        // Wrath: another turn, immediately.
        if pendingExtraTurnFor == actorID {
            pendingExtraTurnFor = nil
            combatants[actorIndex].attackBar = 1.0
            events.append(.extraTurnGranted(actor: actorID, source: "skill"))
        } else if combatants[actorIndex].hasRelicSet(.wrath), rng.chance(0.22) {
            combatants[actorIndex].attackBar = 1.0
            events.append(.extraTurnGranted(actor: actorID, source: RelicSet.wrath.displayName))
        }

        return events
    }

    private func tickStatuses(index: Int) -> [BattleEvent] {
        var events: [BattleEvent] = []
        let targetID = combatants[index].id
        for statusIndex in combatants[index].statuses.indices {
            combatants[index].statuses[statusIndex].turnsRemaining -= 1
        }
        let expired = combatants[index].statuses.filter { $0.isExpired }
        combatants[index].statuses.removeAll { $0.isExpired }
        for status in expired {
            events.append(.statusExpired(target: targetID, kind: status.kind))
        }
        return events
    }

    // MARK: - Skill resolution

    private func performTurn(actorIndex: Int, action: BattleAction) -> [BattleEvent] {
        guard let skill = combatants[actorIndex].skill(at: action.skillSlot),
              combatants[actorIndex].isSkillReady(action.skillSlot) else {
            // Fall back to the basic attack rather than wasting the turn.
            guard let basic = combatants[actorIndex].skill(at: 0) else { return [] }
            return cast(basic, slot: 0, actorIndex: actorIndex, explicitTarget: action.targetID)
        }
        return cast(skill, slot: action.skillSlot, actorIndex: actorIndex, explicitTarget: action.targetID)
    }

    private func cast(
        _ skill: Skill,
        slot: Int,
        actorIndex: Int,
        explicitTarget: UUID?,
        isCounter: Bool = false,
        counterDepth: Int = 0
    ) -> [BattleEvent] {
        var events: [BattleEvent] = []
        let actorID = combatants[actorIndex].id

        // Provoke overrides the chosen target for anything aimed at an enemy.
        var target = explicitTarget
        if let provoke = combatants[actorIndex].status(.provoke),
           let sourceID = provoke.sourceID,
           skill.target.hitsEnemies,
           let source = combatant(sourceID), source.isAlive {
            target = sourceID
        }

        let primaryTargets = resolveTargets(skill.target, actorIndex: actorIndex, explicit: target)
        guard !primaryTargets.isEmpty else { return events }

        events.append(.skillCast(
            actor: actorID,
            skillID: skill.id,
            skillName: skill.name,
            targets: primaryTargets.map { combatants[$0].id },
            shot: skill.cameraShot,
            animation: skill.animation,
            vfx: skill.vfx
        ))

        var dealtThisSkill: Double = 0

        if let damageSpec = skill.damage {
            let hits = max(1, damageSpec.hits)
            for hitIndex in 0..<hits {
                // Random-target skills re-roll their victim on every strike.
                let targetsForHit: [Int]
                if case .randomEnemies(let count) = skill.target {
                    targetsForHit = randomTargets(count: count, side: combatants[actorIndex].side.opposing)
                } else {
                    targetsForHit = primaryTargets.filter { combatants[$0].isAlive }
                }

                for targetIndex in targetsForHit {
                    guard combatants[targetIndex].isAlive else { continue }
                    let hit = DamageCalculator.resolve(
                        attacker: combatants[actorIndex],
                        defender: combatants[targetIndex],
                        spec: damageSpec,
                        rng: &rng
                    )
                    let before = combatants[targetIndex].currentHealth
                    events += applyDamage(
                        targetIndex: targetIndex,
                        amount: hit.rawDamage,
                        sourceID: actorID,
                        isCritical: hit.isCritical,
                        isGlancing: hit.isGlancing,
                        matchup: hit.matchup,
                        hitIndex: hitIndex,
                        hitCount: hits,
                        allowCounter: counterDepth < BattleEngine.maxCounterDepth
                    )
                    dealtThisSkill += max(0, before - combatants[targetIndex].currentHealth)

                    // Per-hit status rolls, plus the Chains set proc.
                    for spec in skill.statuses where spec.rollsPerHit {
                        events += applyStatus(spec, actorIndex: actorIndex, defaultTargets: [targetIndex])
                    }
                    if combatants[actorIndex].hasRelicSet(.chains), combatants[targetIndex].isAlive {
                        let chainSpec = StatusSpec(.speedDown, chance: 0.25, turns: 2, target: .singleEnemy)
                        events += applyStatus(chainSpec, actorIndex: actorIndex, defaultTargets: [targetIndex])
                    }
                }
            }
        }

        // Statuses rolled once per target rather than per hit.
        for spec in skill.statuses where !spec.rollsPerHit {
            let specTargets = resolveTargets(spec.target, actorIndex: actorIndex, explicit: target)
            events += applyStatus(spec, actorIndex: actorIndex, defaultTargets: specTargets)
        }

        for utility in skill.utilities {
            events += applyUtility(utility, actorIndex: actorIndex, explicit: target, damageDealt: dealtThisSkill)
        }

        // Styx lifesteal is a set effect rather than a skill effect.
        if combatants[actorIndex].hasRelicSet(.styx), dealtThisSkill > 0, combatants[actorIndex].isAlive {
            events += applyHealing(targetIndex: actorIndex, amount: dealtThisSkill * 0.35, sourceID: actorID)
        }

        if !isCounter, skill.cooldown > 0, combatants[actorIndex].cooldowns.indices.contains(slot) {
            combatants[actorIndex].cooldowns[slot] = skill.cooldown
            events.append(.cooldownStarted(actor: actorID, skillSlot: slot, turns: skill.cooldown))
        }

        return events
    }

    // MARK: - Targeting

    private func resolveTargets(_ selector: TargetSelector, actorIndex: Int, explicit: UUID?) -> [Int] {
        let actor = combatants[actorIndex]
        let enemies = aliveIndices(actor.side.opposing)
        let allies = aliveIndices(actor.side)

        switch selector {
        case .caster:
            return [actorIndex]
        case .singleEnemy:
            if let explicit, let idx = index(of: explicit), combatants[idx].isAlive, combatants[idx].side != actor.side {
                return [idx]
            }
            return enemies.isEmpty ? [] : [enemies[0]]
        case .allEnemies:
            return enemies
        case .randomEnemies(let count):
            return randomTargets(count: count, side: actor.side.opposing)
        case .lowestHealthEnemy:
            return enemies.min(by: { combatants[$0].healthFraction < combatants[$1].healthFraction }).map { [$0] } ?? []
        case .singleAlly:
            if let explicit, let idx = index(of: explicit), combatants[idx].isAlive, combatants[idx].side == actor.side {
                return [idx]
            }
            return [actorIndex]
        case .allAllies:
            return allies
        case .otherAllies:
            return allies.filter { $0 != actorIndex }
        case .lowestHealthAlly:
            return allies.min(by: { combatants[$0].healthFraction < combatants[$1].healthFraction }).map { [$0] } ?? []
        case .deadAlly:
            let dead = combatants.indices.filter { combatants[$0].side == actor.side && !combatants[$0].isAlive }
            return dead.isEmpty ? [] : [dead[0]]
        }
    }

    private func randomTargets(count: Int, side: BattleSide) -> [Int] {
        let pool = aliveIndices(side)
        guard !pool.isEmpty else { return [] }
        return (0..<max(1, count)).compactMap { _ in rng.pickMutating(pool) }
    }

    // MARK: - Effect application

    private func applyStatus(_ spec: StatusSpec, actorIndex: Int, defaultTargets: [Int]) -> [BattleEvent] {
        var events: [BattleEvent] = []
        let actorID = combatants[actorIndex].id

        for targetIndex in defaultTargets {
            guard combatants[targetIndex].isAlive else { continue }

            if spec.kind.isDebuff {
                let landed = DamageCalculator.landsDebuff(
                    chance: spec.chance,
                    attacker: combatants[actorIndex],
                    defender: combatants[targetIndex],
                    rng: &rng
                )
                guard landed else {
                    // Emitted even on a failed chance roll so the HUD can show RESIST.
                    events.append(.statusResisted(source: actorID, target: combatants[targetIndex].id, kind: spec.kind))
                    continue
                }
            } else if !rng.chance(spec.chance) {
                continue
            }

            let turns = spec.turns > 0 ? spec.turns : spec.kind.defaultDuration
            let magnitude: Double = {
                switch spec.kind {
                case .shield:
                    return spec.magnitude > 0
                        ? combatants[actorIndex].maxHealth * spec.magnitude
                        : combatants[actorIndex].maxHealth * 0.15
                case .bomb:
                    return combatants[actorIndex].currentStats.atk * max(spec.magnitude, 4.0)
                default:
                    return spec.magnitude
                }
            }()

            // Re-applying a status refreshes it rather than stacking it, except
            // bombs and shields which are allowed to sit side by side.
            let stackable = spec.kind == .bomb || spec.kind == .shield
            if !stackable, let existing = combatants[targetIndex].statuses.firstIndex(where: { $0.kind == spec.kind }) {
                combatants[targetIndex].statuses[existing].turnsRemaining = max(
                    combatants[targetIndex].statuses[existing].turnsRemaining, turns
                )
            } else {
                combatants[targetIndex].statuses.append(
                    ActiveStatus(kind: spec.kind, turnsRemaining: turns, sourceID: actorID, magnitude: magnitude)
                )
            }
            events.append(.statusApplied(source: actorID, target: combatants[targetIndex].id, kind: spec.kind, turns: turns))
        }

        return events
    }

    private func applyUtility(
        _ utility: UtilityEffect,
        actorIndex: Int,
        explicit: UUID?,
        damageDealt: Double
    ) -> [BattleEvent] {
        var events: [BattleEvent] = []
        let actorID = combatants[actorIndex].id

        switch utility {
        case .healTargetMaxHealth(let fraction, let selector):
            for idx in resolveTargets(selector, actorIndex: actorIndex, explicit: explicit) {
                events += applyHealing(targetIndex: idx, amount: combatants[idx].maxHealth * fraction, sourceID: actorID)
            }

        case .healFromAttack(let multiplier, let selector):
            let amount = combatants[actorIndex].currentStats.atk * multiplier
            for idx in resolveTargets(selector, actorIndex: actorIndex, explicit: explicit) {
                events += applyHealing(targetIndex: idx, amount: amount, sourceID: actorID)
            }

        case .attackBarChange(let delta, let chance, let selector):
            for idx in resolveTargets(selector, actorIndex: actorIndex, explicit: explicit) {
                if delta < 0 {
                    let landed = DamageCalculator.landsDebuff(
                        chance: chance, attacker: combatants[actorIndex], defender: combatants[idx], rng: &rng
                    )
                    guard landed else { continue }
                } else if !rng.chance(chance) {
                    continue
                }
                events += changeAttackBar(index: idx, delta: delta)
            }

        case .cleanse(let count, let selector):
            for idx in resolveTargets(selector, actorIndex: actorIndex, explicit: explicit) {
                let debuffs = combatants[idx].statuses.filter { $0.kind.isDebuff }.prefix(count)
                for debuff in debuffs {
                    combatants[idx].statuses.removeAll { $0.id == debuff.id }
                    events.append(.statusRemoved(target: combatants[idx].id, kind: debuff.kind, byStrip: false))
                }
            }

        case .strip(let count, let chance, let selector):
            for idx in resolveTargets(selector, actorIndex: actorIndex, explicit: explicit) {
                guard DamageCalculator.landsDebuff(
                    chance: chance, attacker: combatants[actorIndex], defender: combatants[idx], rng: &rng
                ) else { continue }
                let buffs = combatants[idx].statuses.filter { $0.kind.isBuff }.prefix(count)
                for buff in buffs {
                    combatants[idx].statuses.removeAll { $0.id == buff.id }
                    events.append(.statusRemoved(target: combatants[idx].id, kind: buff.kind, byStrip: true))
                }
            }

        case .revive(let fraction):
            if let idx = resolveTargets(.deadAlly, actorIndex: actorIndex, explicit: nil).first {
                combatants[idx].currentHealth = combatants[idx].maxHealth * fraction
                combatants[idx].statuses.removeAll()
                combatants[idx].attackBar = 0
                events.append(.revived(target: combatants[idx].id, health: combatants[idx].currentHealth))
            }

        case .resetOwnCooldowns:
            for slot in combatants[actorIndex].cooldowns.indices {
                combatants[actorIndex].cooldowns[slot] = 0
            }
            events.append(.passiveTriggered(actor: actorID, name: "Cooldowns Reset"))

        case .lifesteal(let fraction):
            if damageDealt > 0 {
                events += applyHealing(targetIndex: actorIndex, amount: damageDealt * fraction, sourceID: actorID)
            }

        case .extraTurn(let chance):
            if rng.chance(chance) { pendingExtraTurnFor = actorID }
        }

        return events
    }

    private func changeAttackBar(index: Int, delta: Double) -> [BattleEvent] {
        let before = combatants[index].attackBar
        combatants[index].attackBar = max(0, min(1.0, before + delta))
        let applied = combatants[index].attackBar - before
        guard abs(applied) > 0.0001 else { return [] }
        return [.attackBarChanged(target: combatants[index].id, delta: applied, newValue: combatants[index].attackBar)]
    }

    // MARK: - Damage and healing

    private func applyDamage(
        targetIndex: Int,
        amount: Double,
        sourceID: UUID,
        isCritical: Bool,
        isGlancing: Bool,
        matchup: Element.Matchup,
        hitIndex: Int,
        hitCount: Int,
        allowCounter: Bool
    ) -> [BattleEvent] {
        var events: [BattleEvent] = []
        guard combatants[targetIndex].isAlive else { return events }
        let targetID = combatants[targetIndex].id

        if combatants[targetIndex].has(.invincible) {
            events.append(.damage(
                source: sourceID, target: targetID, amount: 0,
                isCritical: false, isGlancing: false, matchup: matchup,
                remainingHealth: combatants[targetIndex].currentHealth,
                hitIndex: hitIndex, hitCount: hitCount
            ))
            return events
        }

        var remaining = amount

        // Shields soak first, oldest shield first.
        while remaining > 0,
              let shieldIndex = combatants[targetIndex].statuses.firstIndex(where: { $0.kind == .shield && $0.magnitude > 0 }) {
            let absorbed = min(remaining, combatants[targetIndex].statuses[shieldIndex].magnitude)
            combatants[targetIndex].statuses[shieldIndex].magnitude -= absorbed
            remaining -= absorbed
            events.append(.shieldAbsorbed(
                target: targetID,
                amount: absorbed,
                shieldRemaining: combatants[targetIndex].statuses[shieldIndex].magnitude
            ))
            if combatants[targetIndex].statuses[shieldIndex].magnitude <= 0 {
                combatants[targetIndex].statuses.remove(at: shieldIndex)
                events.append(.statusRemoved(target: targetID, kind: .shield, byStrip: false))
            }
        }

        let healthBefore = combatants[targetIndex].currentHealth
        combatants[targetIndex].currentHealth = max(0, healthBefore - remaining)

        // Endure keeps the unit at 1 HP once.
        if combatants[targetIndex].currentHealth <= 0, combatants[targetIndex].has(.endure) {
            combatants[targetIndex].currentHealth = 1
            combatants[targetIndex].statuses.removeAll { $0.kind == .endure }
            events.append(.statusRemoved(target: targetID, kind: .endure, byStrip: false))
        }

        let applied = healthBefore - combatants[targetIndex].currentHealth
        if combatants[targetIndex].side == .opponent { damageDealt += applied } else { damageTaken += applied }

        events.append(.damage(
            source: sourceID, target: targetID, amount: applied + (amount - remaining),
            isCritical: isCritical, isGlancing: isGlancing, matchup: matchup,
            remainingHealth: combatants[targetIndex].currentHealth,
            hitIndex: hitIndex, hitCount: hitCount
        ))

        // Nemesis converts lost health into attack bar.
        if applied > 0, combatants[targetIndex].hasRelicSet(.nemesis), combatants[targetIndex].maxHealth > 0 {
            let lostFraction = applied / combatants[targetIndex].maxHealth
            let stacks = Double(combatants[targetIndex].relicSetStacks(.nemesis))
            let gain = (lostFraction / 0.07) * 0.04 * stacks
            if gain > 0 { events += changeAttackBar(index: targetIndex, delta: gain) }
        }

        if combatants[targetIndex].currentHealth <= 0 {
            combatants[targetIndex].statuses.removeAll()
            combatants[targetIndex].attackBar = 0
            events.append(.defeated(target: targetID))
            if let killerIndex = index(of: sourceID), combatants[killerIndex].side != combatants[targetIndex].side {
                events += firePassive(.onKill, actorIndex: killerIndex)
            }
            return events
        }

        if combatants[targetIndex].healthFraction < 0.5 {
            events += firePassive(.onLowHealth, actorIndex: targetIndex)
        }

        // Counterattack, once, with the basic skill.
        if allowCounter, applied > 0,
           let attackerIndex = index(of: sourceID),
           combatants[attackerIndex].isAlive,
           combatants[attackerIndex].side != combatants[targetIndex].side {
            let counters = combatants[targetIndex].has(.counterStance)
                || combatants[targetIndex].hasRelicSet(.vigil)
            let counterChance = combatants[targetIndex].has(.counterStance) ? 1.0 : 0.15
            if counters, rng.chance(counterChance), let basic = combatants[targetIndex].skill(at: 0) {
                events.append(.counterattack(actor: targetID, target: sourceID))
                events += cast(
                    basic, slot: 0, actorIndex: targetIndex,
                    explicitTarget: sourceID, isCounter: true, counterDepth: 1
                )
            }
        }

        return events
    }

    private func applyHealing(targetIndex: Int, amount: Double, sourceID: UUID) -> [BattleEvent] {
        guard combatants[targetIndex].isAlive, combatants[targetIndex].canBeHealed, amount > 0 else { return [] }
        let before = combatants[targetIndex].currentHealth
        combatants[targetIndex].currentHealth = min(combatants[targetIndex].maxHealth, before + amount)
        let healed = combatants[targetIndex].currentHealth - before
        guard healed > 0 else { return [] }
        return [.healed(
            source: sourceID,
            target: combatants[targetIndex].id,
            amount: healed,
            remainingHealth: combatants[targetIndex].currentHealth
        )]
    }

    // MARK: - Ending

    private func checkForEnding() -> BattleEvent? {
        guard !isFinished else { return nil }
        let playerAlive = !aliveIndices(.player).isEmpty
        let opponentAlive = !aliveIndices(.opponent).isEmpty
        if !opponentAlive { return finishBattle(outcome: .victory) }
        if !playerAlive { return finishBattle(outcome: .defeat) }
        return nil
    }

    private func finishBattle(outcome: BattleOutcome) -> BattleEvent {
        isFinished = true
        awaitingActor = nil
        let playerTeam = team(.player)
        let survivors = playerTeam.filter(\.isAlive).count
        let result = BattleResult(
            outcome: outcome,
            turnsTaken: turnNumber,
            survivorFraction: playerTeam.isEmpty ? 0 : Double(survivors) / Double(playerTeam.count),
            totalDamageDealt: damageDealt,
            totalDamageTaken: damageTaken,
            seed: seed
        )
        self.result = result
        return .battleEnded(result: result)
    }

    /// Runs the whole battle with no player input. Used by arena scoring, the
    /// balance harness and the tests.
    static func simulate(
        playerTeam: [ResolvedUnit],
        opponentTeam: [ResolvedUnit],
        seed: UInt64
    ) -> BattleResult {
        let engine = BattleEngine(
            playerTeam: playerTeam, opponentTeam: opponentTeam,
            mode: .simulation, seed: seed
        )
        engine.autoBattle = true
        _ = engine.start()
        return engine.result ?? BattleResult(
            outcome: .draw, turnsTaken: 0, survivorFraction: 0,
            totalDamageDealt: 0, totalDamageTaken: 0, seed: seed
        )
    }
}
