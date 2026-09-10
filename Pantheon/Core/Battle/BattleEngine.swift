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
    /// A dungeon run is one battle of several waves: when a wave is down the
    /// next takes the field, and the fight is won when the last one falls.
    private var pendingWaves: [[ResolvedUnit]]
    /// 1-based; the HUD shows "Wave 2/3".
    private(set) var waveIndex: Int = 1
    let waveCount: Int
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
    /// Raid mechanics by boss combatant id. Empty for every ordinary fight,
    /// which is what keeps this whole feature off the existing code paths.
    private var raids: [UUID: RaidState] = [:]
    /// Whose turn is being resolved right now. Only the raid barrier needs it,
    /// and only to tell a break landing on the boss's own turn from one landing
    /// on somebody else's — see `absorbBarrier`.
    private var actingCombatantID: UUID?

    // MARK: - Setup

    init(
        playerTeam: [ResolvedUnit],
        opponentTeam: [ResolvedUnit],
        mode: BattleMode,
        seed: UInt64,
        laterWaves: [[ResolvedUnit]] = [],
        raidBosses: [Int: RaidBossProfile] = [:]
    ) {
        self.mode = mode
        self.seed = seed
        self.rng = SeededRandom(seed: seed)
        self.pendingWaves = laterWaves
        self.waveCount = 1 + laterWaves.count

        let playerCombatants = BattleEngine.buildSide(playerTeam, side: .player, mode: mode)
        let opponentCombatants = BattleEngine.buildSide(opponentTeam, side: .opponent, mode: mode)
        self.combatants = playerCombatants + opponentCombatants

        // The content keys a profile to the boss's place in the opponent team,
        // because that is all a table of spawns knows. From here on it is keyed
        // by combatant id: a raid summons minions, so an index into the team
        // stops meaning anything the moment the first one walks on.
        for (index, profile) in raidBosses where opponentCombatants.indices.contains(index) {
            let boss = opponentCombatants[index]
            raids[boss.id] = RaidState(profile: profile, maxHealth: boss.maxHealth)
        }
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
        events += raidOpening()
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
            events += spawnWaveIfNeeded()
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

            // The enrage belongs to the battle's clock, not to whoever happens
            // to be acting, so it is checked as the turn number moves.
            events += raidEnrageCheck()

            let actorID = combatants[actorIndex].id
            actingCombatantID = actorID
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
        events += raidTurnStart(actorIndex: actorIndex)

        return events
    }

    /// Applies cooldowns, decrements statuses and honours extra-turn effects.
    private func finishTurn(actorIndex: Int) -> [BattleEvent] {
        var events: [BattleEvent] = []
        let actorID = combatants[actorIndex].id
        // The turn's own resolution — counterattacks included — is over by the
        // time this runs, so nothing after this point is "during" anyone's turn.
        actingCombatantID = nil

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
                        amount: hit.rawDamage * raidDamageMultiplier(attackerIndex: actorIndex, targetIndex: targetIndex),
                        sourceID: actorID,
                        isCritical: hit.isCritical,
                        isGlancing: hit.isGlancing,
                        matchup: raidMatchup(hit.matchup, attackerIndex: actorIndex, targetIndex: targetIndex),
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

        // A raid boss's barrier soaks before anything else. It is the plate on
        // the outside and the bar the player is aiming at, so the numbers he
        // watches go into it first.
        events += absorbBarrier(targetIndex: targetIndex, sourceID: sourceID, incoming: &remaining)

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
            events += collapseGuard(of: targetID)
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
        // A wave down with waves to come is not a win; `advance` brings the
        // next one on before the next turn is dealt.
        if !opponentAlive && pendingWaves.isEmpty { return finishBattle(outcome: .victory) }
        if !playerAlive { return finishBattle(outcome: .defeat) }
        return nil
    }

    /// The next wave walks on once the field is clear of the last. The
    /// player's bars and health carry over, the way a dungeon run does.
    private func spawnWaveIfNeeded() -> [BattleEvent] {
        guard !isFinished, !pendingWaves.isEmpty, aliveIndices(.opponent).isEmpty else { return [] }
        let wave = pendingWaves.removeFirst()
        waveIndex += 1
        let arrivals = BattleEngine.buildSide(wave, side: .opponent, mode: mode)
        combatants.append(contentsOf: arrivals)
        return [.waveStarted(wave: waveIndex, count: waveCount, opponents: arrivals)]
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

    // MARK: - Raid bosses
    //
    // Four mechanics, all of them optional and all of them driven off the
    // boss's `RaidBossProfile`: a barrier that has to be broken and buys a stun
    // when it goes, a guard the boss calls and drinks from, an enrage clock
    // that turns a war of attrition into a race, and a weakness that rotates so
    // a team of one element is punished for it.
    //
    // Nothing here invents an event. Every moment goes out through the stream
    // the scene and the HUD already read — `shieldAbsorbed` for the barrier,
    // `passiveTriggered` for the announcements, a real `stun` status for the
    // window, `waveStarted` for the arrivals and `healed` for the drain —
    // because `BattleSceneController.present(_:)` switches over every case
    // without a default, and a new case there is a compile error in a file this
    // work is not allowed to touch. It also means a raid needs no HUD work to
    // be legible: the break floats its name, the stun shows as a chip on the
    // boss bar, the drain shows as green numbers on the boss.

    /// The live state of one raid boss. Keyed by combatant id in `raids`.
    private struct RaidState {
        let profile: RaidBossProfile
        var barrier: Double
        let barrierMaximum: Double
        /// Boss turns until a broken barrier comes back; 0 while it is up.
        var regenCountdown: Int = 0
        /// One entry per spawn in `profile.adds`: whoever is standing in that
        /// place of the guard now, or nil while it is empty. Indexed by the
        /// spawn's own position rather than kept as a flat list, because a flat
        /// list can only say HOW MANY are missing, not WHICH — a guard of two
        /// different creatures would then bring back the wrong one.
        var guardSlots: [UUID?] = []
        var turnsUntilSummon: Int
        var enrageStacks: Int = 0
        var weaknessIndex: Int = 0
        var turnsUntilRotation: Int

        init(profile: RaidBossProfile, maxHealth: Double) {
            let pool = maxHealth * max(0, profile.barrierFraction)
            self.profile = profile
            self.barrier = pool
            self.barrierMaximum = pool
            self.guardSlots = Array(repeating: nil, count: profile.adds.count)
            self.turnsUntilSummon = max(1, profile.addInterval)
            self.turnsUntilRotation = max(1, profile.weaknessInterval)
        }

        var weakness: Element? {
            profile.weaknesses.isEmpty ? nil : profile.weaknesses[weaknessIndex % profile.weaknesses.count]
        }

        /// Compounding, so a fight that runs long gets worse and worse.
        var enrageFactor: Double {
            enrageStacks > 0 ? pow(profile.enrageMultiplier, Double(enrageStacks)) : 1.0
        }
    }

    // MARK: Reading a raid from outside

    /// Ids of the raid bosses on the field, in combatant order.
    var raidBossIDs: [UUID] {
        combatants.map(\.id).filter { raids[$0] != nil }
    }

    /// The barrier on a raid boss: what is left of it and what it holds when
    /// full. Nil for anything that is not a raid boss carrying one.
    func raidBarrier(for id: UUID) -> (remaining: Double, maximum: Double)? {
        guard let state = raids[id], state.barrierMaximum > 0 else { return nil }
        return (state.barrier, state.barrierMaximum)
    }

    /// The element the boss is open to at this moment.
    func raidWeakness(for id: UUID) -> Element? { raids[id]?.weakness }

    /// What the boss's enrage is currently multiplying its damage by; 1 until
    /// the clock runs out.
    func raidEnrage(for id: UUID) -> Double { raids[id]?.enrageFactor ?? 1.0 }

    // MARK: The clock

    /// Announces each boss's barrier and opening weakness so the first thing
    /// the player sees is what he is up against.
    private func raidOpening() -> [BattleEvent] {
        var events: [BattleEvent] = []
        for index in combatants.indices {
            let id = combatants[index].id
            guard let state = raids[id] else { continue }
            if state.barrierMaximum > 0 {
                events.append(.passiveTriggered(actor: id, name: "\(state.profile.barrierName) Raised"))
            }
            if let weakness = state.weakness {
                events.append(.passiveTriggered(actor: id, name: "Weak to \(weakness.displayName)"))
            }
        }
        return events
    }

    /// Enrage steps as the battle's turn counter passes the threshold, whoever
    /// is acting. Walked in combatant order rather than dictionary order: the
    /// event stream for a given seed has to be identical every time.
    private func raidEnrageCheck() -> [BattleEvent] {
        var events: [BattleEvent] = []
        for index in combatants.indices {
            let id = combatants[index].id
            guard var state = raids[id], combatants[index].isAlive else { continue }
            let profile = state.profile
            guard profile.enrageTurn > 0, profile.enrageMultiplier > 1, turnNumber >= profile.enrageTurn else { continue }

            // One step at the threshold, then one more per interval. An
            // interval of 0 means it steps once and stays there.
            let extra = profile.enrageInterval > 0
                ? (turnNumber - profile.enrageTurn) / profile.enrageInterval
                : 0
            let stacks = 1 + extra
            guard stacks > state.enrageStacks else { continue }
            state.enrageStacks = stacks
            raids[id] = state
            events.append(.passiveTriggered(
                actor: id,
                name: "Enraged ×\(String(format: "%.1f", state.enrageFactor))"
            ))
        }
        return events
    }

    /// The boss's own turn: the barrier's regeneration clock, the weakness
    /// rotation, the guard's drain and the next summon.
    private func raidTurnStart(actorIndex: Int) -> [BattleEvent] {
        let bossID = combatants[actorIndex].id
        guard var state = raids[bossID], combatants[actorIndex].isAlive else { return [] }
        var events: [BattleEvent] = []

        // The regeneration clock runs on the boss's turns whether it acts or
        // not: the stun the break bought is the window, and letting it stop the
        // clock would mean the window paid for itself twice.
        if state.regenCountdown > 0 {
            state.regenCountdown -= 1
            if state.regenCountdown == 0 {
                state.barrier = state.barrierMaximum
                events.append(.passiveTriggered(actor: bossID, name: "\(state.profile.barrierName) Restored"))
            }
        }

        // Everything else is something the boss does, so a turn it loses to the
        // stun costs it the rotation, the drain and the summon as well.
        if !combatants[actorIndex].isIncapacitated {
            if state.profile.weaknesses.count > 1 {
                state.turnsUntilRotation -= 1
                if state.turnsUntilRotation <= 0 {
                    state.weaknessIndex = (state.weaknessIndex + 1) % state.profile.weaknesses.count
                    state.turnsUntilRotation = max(1, state.profile.weaknessInterval)
                    if let weakness = state.weakness {
                        events.append(.passiveTriggered(actor: bossID, name: "Weak to \(weakness.displayName)"))
                    }
                }
            }

            // The drain runs before the summon, so a minion never feeds the
            // boss on the turn it walks on. `applyHealing` refuses a boss under
            // Unrecoverable, which makes that debuff the answer to the guard
            // for a team that cannot kill two minions a turn.
            let living = state.guardSlots.compactMap { $0 }.filter { combatant($0)?.isAlive == true }
            if !living.isEmpty, state.profile.addDrain > 0, combatants[actorIndex].canBeHealed {
                events.append(.passiveTriggered(actor: bossID, name: state.profile.drainName))
                let amount = combatants[actorIndex].maxHealth * state.profile.addDrain
                for minionID in living {
                    events += applyHealing(targetIndex: actorIndex, amount: amount, sourceID: minionID)
                }
            }

            if !state.profile.adds.isEmpty {
                state.turnsUntilSummon -= 1
                if state.turnsUntilSummon <= 0 {
                    state.turnsUntilSummon = max(1, state.profile.addInterval)
                    events += summonGuard(bossIndex: actorIndex, state: &state)
                }
            }
        }

        raids[bossID] = state
        return events
    }

    /// Tops the guard back up to its full number. Only the missing ones are
    /// called, so ignoring the minions cannot bury the field in them — it just
    /// leaves them alive and drinking.
    private func summonGuard(bossIndex: Int, state: inout RaidState) -> [BattleEvent] {
        let bossID = combatants[bossIndex].id

        // Which places in the guard stand empty, in the spawn table's own
        // order. `adds[i]` is the creature that belongs at `i`, so what comes
        // back is what actually fell rather than a copy of the last spawn in
        // the table.
        let empty = state.profile.adds.indices.filter { place in
            guard let standing = state.guardSlots[place] else { return true }
            return combatant(standing)?.isAlive != true
        }
        guard !empty.isEmpty else { return [] }

        // The marks of the fallen are free — the scene clears defeated
        // opponents on this same event — so a second guard stands where the
        // first one died instead of a rank further back every time.
        let marks = freeOpponentSlots(count: empty.count)
        var arrivals: [Combatant] = []
        for (offset, place) in empty.enumerated() where offset < marks.count {
            // Resolved one at a time: `buildEnemies` drops a spawn whose
            // blueprint has gone missing, and a batch call would then hand
            // back a shorter array and slide every creature into the wrong
            // place of the guard.
            guard let unit = StageDatabase.buildEnemies(spawns: [state.profile.adds[place]]).first
            else { continue }
            let arrival = Combatant(resolved: unit, side: .opponent, slot: marks[offset], isLeader: false)
            state.guardSlots[place] = arrival.id
            arrivals.append(arrival)
        }
        guard !arrivals.isEmpty else { return [] }

        combatants.append(contentsOf: arrivals)

        // `waveStarted` is how arrivals reach the scene, and it carries the
        // wave the fight is actually on so a raid does not lie to the HUD's
        // wave counter.
        return [
            .passiveTriggered(actor: bossID, name: state.profile.summonName),
            .waveStarted(wave: waveIndex, count: waveCount, opponents: arrivals)
        ]
    }

    /// The lowest marks no living opponent is standing on.
    private func freeOpponentSlots(count: Int) -> [Int] {
        let taken = Set(combatants.filter { $0.side == .opponent && $0.isAlive }.map(\.slot))
        var slots: [Int] = []
        var candidate = 0
        while slots.count < count, candidate < 16 {
            if !taken.contains(candidate) { slots.append(candidate) }
            candidate += 1
        }
        return slots
    }

    // MARK: The barrier

    /// Soaks damage into the boss's barrier and breaks it if the damage runs
    /// out the other side. Whatever is left over carries on into health in the
    /// same hit, so the strike that breaks it still lands.
    private func absorbBarrier(targetIndex: Int, sourceID: UUID, incoming: inout Double) -> [BattleEvent] {
        let targetID = combatants[targetIndex].id
        guard var state = raids[targetID], state.barrier > 0, incoming > 0 else { return [] }
        var events: [BattleEvent] = []

        let absorbed = min(incoming, state.barrier)
        state.barrier -= absorbed
        incoming -= absorbed
        events.append(.shieldAbsorbed(target: targetID, amount: absorbed, shieldRemaining: state.barrier))

        if state.barrier <= 0 {
            state.regenCountdown = max(1, state.profile.barrierRegenTurns)
            events.append(.passiveTriggered(actor: targetID, name: "\(state.profile.barrierName) Shattered"))

            // Applied straight rather than rolled: this is a window the player
            // earned by breaking the barrier, and losing it to the boss's
            // resistance stat would make the whole mechanic a coin flip.
            //
            // Statuses only tick on their owner's own turn, so a barrier broken
            // during the boss's turn — by a counterattack, a bomb, a reflect —
            // would tick this away before it ever cost a turn. Hence the extra
            // turn while the boss is the one acting.
            let turns = max(1, state.profile.barrierStunTurns) + (actingCombatantID == targetID ? 1 : 0)
            combatants[targetIndex].statuses.append(
                ActiveStatus(kind: .stun, turnsRemaining: turns, sourceID: sourceID)
            )
            events.append(.statusApplied(source: sourceID, target: targetID, kind: .stun, turns: turns))
        }

        raids[targetID] = state
        return events
    }

    /// A raid boss's summons are held up by it. When it falls they fall with
    /// it, so a won raid ends on the boss rather than on a mop-up.
    private func collapseGuard(of bossID: UUID) -> [BattleEvent] {
        guard let state = raids[bossID] else { return [] }
        let guards = Set(state.guardSlots.compactMap { $0 })
        guard !guards.isEmpty else { return [] }
        var events: [BattleEvent] = []
        let standing = combatants.indices.filter {
            combatants[$0].isAlive && guards.contains(combatants[$0].id)
        }
        for index in standing {
            combatants[index].currentHealth = 0
            combatants[index].statuses.removeAll()
            combatants[index].attackBar = 0
            events.append(.defeated(target: combatants[index].id))
        }
        return events
    }

    // MARK: The weakness, and what enrage does to a number

    /// Enrage on the way out of a raid boss, the rotating weakness on the way
    /// in. 1 for every fight that has no raid in it.
    private func raidDamageMultiplier(attackerIndex: Int, targetIndex: Int) -> Double {
        var multiplier = 1.0
        if let attacker = raids[combatants[attackerIndex].id] {
            multiplier *= attacker.enrageFactor
        }
        if let defender = raids[combatants[targetIndex].id], let weakness = defender.weakness {
            multiplier *= combatants[attackerIndex].element == weakness
                ? defender.profile.weaknessMultiplier
                : defender.profile.offElementMultiplier
        }
        return multiplier
    }

    /// The matchup the damage event reports. A hit into the boss's open
    /// element is called an advantage even when the element wheel says
    /// otherwise: the number is already bigger, and the green number and the
    /// "(advantage)" in the log are how the player is told which of his units
    /// is the one to be using right now. It changes nothing but the reporting —
    /// `DamageCalculator` has already applied the real wheel to the number.
    private func raidMatchup(
        _ matchup: Element.Matchup,
        attackerIndex: Int,
        targetIndex: Int
    ) -> Element.Matchup {
        guard let defender = raids[combatants[targetIndex].id],
              let weakness = defender.weakness,
              combatants[attackerIndex].element == weakness else { return matchup }
        return .advantage
    }

    /// Runs the whole battle with no player input. Used by arena scoring, the
    /// balance harness and the tests.
    static func simulate(
        playerTeam: [ResolvedUnit],
        opponentTeam: [ResolvedUnit],
        seed: UInt64,
        laterWaves: [[ResolvedUnit]] = []
    ) -> BattleResult {
        let engine = BattleEngine(
            playerTeam: playerTeam, opponentTeam: opponentTeam,
            mode: .simulation, seed: seed, laterWaves: laterWaves
        )
        engine.autoBattle = true
        _ = engine.start()
        return engine.result ?? BattleResult(
            outcome: .draw, turnsTaken: 0, survivorFraction: 0,
            totalDamageDealt: 0, totalDamageTaken: 0, seed: seed
        )
    }
}
