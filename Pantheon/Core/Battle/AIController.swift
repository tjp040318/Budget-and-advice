import Foundation

/// Picks moves for opponent teams, for auto-battle, and for arena defence.
///
/// The scoring is deliberately readable rather than clever: every candidate
/// (skill, target) pair gets a number, the best one wins, and ties break on the
/// RNG so two identical teams do not mirror each other exactly. If a skill ever
/// feels like the AI misuses it, the fix belongs in `score(_:)` and nowhere else.
enum AIController {

    static func chooseAction(
        actorIndex: Int,
        combatants: [Combatant],
        engine: BattleEngine,
        rng: inout SeededRandom
    ) -> BattleAction {
        let actor = combatants[actorIndex]
        let readySlots = actor.skills.indices.filter { actor.isSkillReady($0) }
        guard !readySlots.isEmpty else {
            return BattleAction(actorID: actor.id, skillSlot: 0, targetID: nil)
        }

        var best: (score: Double, action: BattleAction)?

        for slot in readySlots {
            guard let skill = actor.skill(at: slot) else { continue }
            let candidates = engine.validTargets(for: actor.id, skillSlot: slot)
            let targetOptions: [UUID?] = candidates.isEmpty ? [nil] : candidates.map { Optional($0) }

            for target in targetOptions {
                var value = score(
                    skill: skill,
                    slot: slot,
                    actor: actor,
                    targetID: target,
                    combatants: combatants
                )
                // Small jitter keeps mirror matches from being deterministic
                // stalemates while staying reproducible from the seed.
                value += rng.double(in: -0.03...0.03) * max(1, abs(value))
                if best == nil || value > best!.score {
                    best = (value, BattleAction(actorID: actor.id, skillSlot: slot, targetID: target))
                }
            }
        }

        return best?.action ?? BattleAction(actorID: actor.id, skillSlot: 0, targetID: nil)
    }

    // MARK: - Scoring

    private static func score(
        skill: Skill,
        slot: Int,
        actor: Combatant,
        targetID: UUID?,
        combatants: [Combatant]
    ) -> Double {
        let allies = combatants.filter { $0.side == actor.side && $0.isAlive }
        let enemies = combatants.filter { $0.side != actor.side && $0.isAlive }
        let target = targetID.flatMap { id in combatants.first(where: { $0.id == id }) }

        var value: Double = 0

        // Cooldown skills are worth more than the basic attack by default, so
        // the AI does not sit on its kit.
        value += Double(skill.cooldown) * 6

        if let damage = skill.damage {
            let hitTargets: [Combatant] = {
                switch skill.target {
                case .allEnemies: return enemies
                case .randomEnemies(let count): return Array(enemies.prefix(count))
                default: return target.map { [$0] } ?? Array(enemies.prefix(1))
                }
            }()

            for victim in hitTargets {
                let matchup = actor.element.matchup(against: victim.element)
                let expected = DamageCalculator.previewDamage(
                    attackStat: actor.scalingValue(for: damage.scaling),
                    spec: damage,
                    againstDefense: victim.currentStats.def
                ) * matchup.damageMultiplier

                let fractionOfHealth = min(1.5, expected / max(1, victim.currentHealth))
                value += fractionOfHealth * 40

                // Finishing a unit is worth more than the damage suggests.
                if expected >= victim.currentHealth { value += 55 }
                // Softer targets first, all else equal.
                value += (1 - victim.healthFraction) * 10
                // Prefer killing the dangerous ones.
                if victim.role == .attacker || victim.role == .controller { value += 8 }
                if victim.isLeader { value += 4 }
                // Do not waste a big cooldown into a wall.
                if matchup == .disadvantage { value -= 12 }
            }
        }

        for spec in skill.statuses {
            switch spec.target {
            case .allEnemies, .singleEnemy, .randomEnemies, .lowestHealthEnemy:
                let victims: [Combatant] = spec.target.hitsEnemies && isAoE(spec.target)
                    ? enemies
                    : (target.map { [$0] } ?? Array(enemies.prefix(1)))
                for victim in victims {
                    guard !victim.has(spec.kind) else { value -= 4; continue }
                    if victim.has(.immunity) { value -= 10; continue }
                    value += statusValue(spec.kind) * spec.chance
                    // Control is at its best against something about to act.
                    if spec.kind.isHardCC { value += victim.attackBar * 18 }
                }
            case .allAllies, .caster, .singleAlly, .lowestHealthAlly, .otherAllies:
                let beneficiaries: [Combatant] = isAoE(spec.target) ? allies : (target.map { [$0] } ?? [actor])
                for ally in beneficiaries {
                    guard !ally.has(spec.kind) else { value -= 6; continue }
                    value += statusValue(spec.kind) * spec.chance * 0.8
                }
            case .deadAlly:
                break
            }
        }

        for utility in skill.utilities {
            switch utility {
            case .healTargetMaxHealth(let fraction, _), .healFromAttack(let fraction, _):
                // Healing is only worth anything if someone is hurt.
                let neediest = allies.map(\.healthFraction).min() ?? 1
                value += (1 - neediest) * fraction * 120
                if neediest > 0.9 { value -= 25 }
            case .attackBarChange(let delta, let chance, let selector):
                let magnitude = abs(delta) * chance * 45
                value += selector.hitsEnemies ? magnitude : magnitude * 0.9
            case .cleanse:
                let debuffs = allies.reduce(0) { $0 + $1.debuffCount }
                value += Double(debuffs) * 12
                if debuffs == 0 { value -= 20 }
            case .strip(_, let chance, _):
                let buffs = enemies.reduce(0) { $0 + $1.buffCount }
                value += Double(buffs) * chance * 14
                if buffs == 0 { value -= 18 }
            case .revive:
                let dead = combatants.contains { $0.side == actor.side && !$0.isAlive }
                value += dead ? 140 : -200
            case .resetOwnCooldowns:
                value += 25
            case .lifesteal:
                value += (1 - actor.healthFraction) * 25
            case .extraTurn(let chance):
                value += chance * 30
            }
        }

        return value
    }

    private static func isAoE(_ selector: TargetSelector) -> Bool {
        switch selector {
        case .allEnemies, .allAllies, .otherAllies, .randomEnemies: return true
        default: return false
        }
    }

    /// Rough worth of landing a status, used only for comparison between moves.
    private static func statusValue(_ kind: StatusKind) -> Double {
        switch kind {
        case .stun, .freeze, .sleep: return 45
        case .defenseDown: return 30
        case .attackUp: return 26
        case .defenseUp: return 22
        case .speedUp: return 24
        case .attackDown: return 20
        case .brand: return 20
        case .bomb: return 40
        case .invincible: return 42
        case .immunity: return 24
        case .shield: return 22
        case .recovery: return 18
        case .critRateUp: return 18
        case .counterStance: return 20
        case .reflect: return 16
        case .endure: return 20
        case .speedDown: return 20
        case .glancing: return 14
        case .silence: return 22
        case .burn: return 18
        case .unrecoverable: return 16
        case .provoke: return 24
        }
    }

    /// Builds a defence-team score for arena matchmaking without running a full
    /// battle: cheap enough to run over a whole opponent pool.
    static func defenseRating(_ team: [ResolvedUnit]) -> Int {
        guard !team.isEmpty else { return 0 }
        let raw = team.reduce(0) { $0 + $1.power }
        let speedSpread = team.map(\.stats.spd).max() ?? 0
        return Int(Double(raw) * (1 + speedSpread / 400))
    }
}
