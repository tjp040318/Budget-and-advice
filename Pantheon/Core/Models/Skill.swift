import Foundation

/// Who a skill component lands on.
enum TargetSelector: Codable, Equatable, Sendable {
    case singleEnemy
    case allEnemies
    /// Picks N enemies at random, re-rolling per hit (Summoners-War style spread).
    case randomEnemies(count: Int)
    case lowestHealthEnemy
    case caster
    case singleAlly
    case allAllies
    case lowestHealthAlly
    case deadAlly
    /// Every ally except the caster — used by sacrificial supports.
    case otherAllies

    var hitsEnemies: Bool {
        switch self {
        case .singleEnemy, .allEnemies, .randomEnemies, .lowestHealthEnemy: return true
        default: return false
        }
    }
}

/// What a damage multiplier is multiplied *by*.
enum DamageScaling: String, Codable, Sendable {
    case attack
    case maxHealth = "max_hp"
    case defense
    case speed
}

/// One damaging component of a skill.
struct DamageSpec: Codable, Equatable, Sendable {
    /// Multiplier applied to the scaling stat, per hit.
    var multiplier: Double
    var scaling: DamageScaling = .attack
    /// Number of separate strikes. Each rolls crit and applies on-hit effects.
    var hits: Int = 1
    /// Fraction of the target's DEF ignored, 0...1.
    var defenseIgnore: Double = 0
    /// Extra multiplier per debuff currently on the target (Nemesis-style scaling).
    var bonusPerTargetDebuff: Double = 0
    /// Extra multiplier per 1% of the target's *missing* health.
    var bonusPerMissingHealth: Double = 0
    /// Skips the crit roll and always crits. Reserved for finishers.
    var alwaysCrits: Bool = false

    init(
        multiplier: Double,
        scaling: DamageScaling = .attack,
        hits: Int = 1,
        defenseIgnore: Double = 0,
        bonusPerTargetDebuff: Double = 0,
        bonusPerMissingHealth: Double = 0,
        alwaysCrits: Bool = false
    ) {
        self.multiplier = multiplier
        self.scaling = scaling
        self.hits = hits
        self.defenseIgnore = defenseIgnore
        self.bonusPerTargetDebuff = bonusPerTargetDebuff
        self.bonusPerMissingHealth = bonusPerMissingHealth
        self.alwaysCrits = alwaysCrits
    }
}

/// A status application attached to a skill.
struct StatusSpec: Codable, Equatable, Sendable {
    var kind: StatusKind
    var chance: Double
    var turns: Int
    var target: TargetSelector
    /// Payload: shield size as a fraction of caster max HP, bomb damage as a
    /// multiple of caster ATK, and so on. Zero means "use the status default".
    var magnitude: Double = 0
    /// Rolled once per skill rather than once per hit. Multi-hit skills usually
    /// want per-hit rolls; AoE control usually wants one roll per target.
    var rollsPerHit: Bool = false

    init(
        _ kind: StatusKind,
        chance: Double,
        turns: Int = 2,
        target: TargetSelector = .singleEnemy,
        magnitude: Double = 0,
        rollsPerHit: Bool = false
    ) {
        self.kind = kind
        self.chance = chance
        self.turns = turns
        self.target = target
        self.magnitude = magnitude
        self.rollsPerHit = rollsPerHit
    }
}

/// Non-damage, non-status utility a skill can perform.
enum UtilityEffect: Codable, Equatable, Sendable {
    /// Heals for a fraction of the *target's* max HP.
    case healTargetMaxHealth(Double, TargetSelector)
    /// Heals for a multiple of the *caster's* ATK.
    case healFromAttack(Double, TargetSelector)
    /// Moves the attack bar by a signed fraction (+0.3 = fill 30%).
    case attackBarChange(Double, chance: Double, TargetSelector)
    /// Removes up to N debuffs from the target.
    case cleanse(count: Int, TargetSelector)
    /// Removes up to N buffs from the target.
    case strip(count: Int, chance: Double, TargetSelector)
    /// Revives one dead ally at a fraction of max HP.
    case revive(healthFraction: Double)
    /// Puts every other skill of the caster back to zero cooldown.
    case resetOwnCooldowns
    /// Heals the caster for a fraction of the damage this skill dealt.
    case lifesteal(Double)
    /// Grants the caster another turn immediately.
    case extraTurn(chance: Double)
}

/// When a passive skill fires. Active skills leave this nil.
enum PassiveTrigger: String, Codable, Sendable {
    /// Once, as the battle opens.
    case onBattleStart = "on_battle_start"
    /// Whenever this unit lands the killing blow.
    case onKill = "on_kill"
    /// At the start of every one of this unit's turns.
    case onTurnStart = "on_turn_start"
    /// Whenever this unit drops below half health, once per battle.
    case onLowHealth = "on_low_health"
}

/// One of a unit's three active skills, or its passive.
struct Skill: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String

    /// Index within the unit's kit. 0 is the basic attack and never has a cooldown.
    var slot: Int
    /// Turns before the skill can be used again. 0 = every turn.
    var cooldown: Int
    /// Primary target of the damage component.
    var target: TargetSelector

    var damage: DamageSpec?
    var statuses: [StatusSpec] = []
    var utilities: [UtilityEffect] = []

    /// Levelling a skill adds these. Index 0 is the bonus for skill level 2.
    var levelUpBonuses: [SkillUpgrade] = []

    /// Passive skills are never chosen; the engine queries them by hook.
    var isPassive: Bool = false
    /// When a passive fires. Ignored for active skills.
    var trigger: PassiveTrigger? = nil
    /// Skills hidden until the unit is awakened — usually the passive.
    var requiresAwakening: Bool = false
    /// Name of the animation clip in the unit's 3D model to play when cast.
    var animation: AnimationClip = .attackBasic
    /// Camera treatment. Ultimates get the cinematic push-in.
    var cameraShot: CameraShot = .standard
    /// VFX identifier resolved by `VFXLibrary`.
    var vfx: String = "impact_generic"

    var maxSkillLevel: Int { levelUpBonuses.count + 1 }

    /// The skill as it exists at a given skill level (1-based).
    func leveled(to level: Int) -> Skill {
        var result = self
        let applied = max(0, min(level - 1, levelUpBonuses.count))
        for bonus in levelUpBonuses.prefix(applied) {
            bonus.apply(to: &result)
        }
        return result
    }
}

/// A single skill-up. Kept as data so the collection UI can render the ladder
/// ("Lv.2 Damage +5%") straight from the blueprint.
struct SkillUpgrade: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case damageMultiplier
        case effectChance
        case cooldown
        case healing
    }

    var kind: Kind
    var amount: Double
    var label: String

    func apply(to skill: inout Skill) {
        switch kind {
        case .damageMultiplier:
            if var dmg = skill.damage {
                dmg.multiplier *= (1 + amount)
                skill.damage = dmg
            }
        case .effectChance:
            skill.statuses = skill.statuses.map {
                var s = $0
                s.chance = min(1.0, s.chance + amount)
                return s
            }
        case .cooldown:
            skill.cooldown = max(0, skill.cooldown - Int(amount))
        case .healing:
            skill.utilities = skill.utilities.map { utility in
                switch utility {
                case .healTargetMaxHealth(let v, let t):
                    return .healTargetMaxHealth(v * (1 + amount), t)
                case .healFromAttack(let v, let t):
                    return .healFromAttack(v * (1 + amount), t)
                default:
                    return utility
                }
            }
        }
    }
}

/// Team-wide bonus granted only when the unit leads the team.
struct LeaderSkill: Codable, Equatable, Sendable {
    enum Scope: Codable, Equatable, Sendable {
        case allAllies
        case pantheon(Pantheon)
        case element(Element)
        case archetype(Archetype)
    }

    var stat: StatKind
    var amount: Double
    var scope: Scope
    /// Where the bonus applies. Arena-only leader skills are a real thing in the
    /// genre and the UI needs to say so.
    var appliesInArena: Bool = true
    var appliesInCampaign: Bool = true

    var description: String {
        let target: String
        switch scope {
        case .allAllies: target = "all allies"
        case .pantheon(let p): target = "\(p.displayName) allies"
        case .element(let e): target = "\(e.displayName) allies"
        case .archetype(let a): target = "\(a.displayName) allies"
        }
        return "Increases the \(stat.displayName) of \(target) by \(Int(amount * 100))%."
    }

    func applies(to unit: UnitBlueprint) -> Bool {
        switch scope {
        case .allAllies: return true
        case .pantheon(let p): return unit.pantheon == p
        case .element(let e): return unit.element == e
        case .archetype(let a): return unit.archetype == a
        }
    }
}
