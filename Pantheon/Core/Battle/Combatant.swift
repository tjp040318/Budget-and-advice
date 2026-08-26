import Foundation

enum BattleSide: String, Codable, Sendable {
    case player
    case opponent

    var opposing: BattleSide { self == .player ? .opponent : .player }
}

/// A unit as it exists inside a running battle.
///
/// Created from a `ResolvedUnit` at battle start and discarded at the end.
/// `baseStats` never change; every buff, debuff and set effect is applied on
/// read through `currentStats`, so removing a status can never leave residue.
struct Combatant: Identifiable, Sendable {
    let id: UUID
    /// Id of the owning `Unit`, or nil for generated opponents.
    let sourceUnitID: UUID?
    let side: BattleSide
    /// 0-based position on its side, which is also the 3D stage position.
    let slot: Int

    let name: String
    let blueprintID: String
    let element: Element
    let pantheon: Pantheon
    let archetype: Archetype
    let role: CombatRole
    let model: ModelSpec
    let isLeader: Bool

    /// Stats after levels, relics, set bonuses and leader skill — but before
    /// any in-battle status.
    let baseStats: Stats
    var skills: [Skill]

    var currentHealth: Double
    /// 0...1. At 1 the combatant takes a turn.
    var attackBar: Double = 0
    var statuses: [ActiveStatus] = []
    /// Remaining cooldown per skill slot.
    var cooldowns: [Int]
    /// Completed relic sets, with multiplicity, so the engine can check effects.
    var relicSets: [RelicSet: Int] = [:]
    /// Passive triggers already spent this battle, for once-only passives.
    var firedPassives: Set<String> = []

    var isAlive: Bool { currentHealth > 0 }
    var maxHealth: Double { baseStats.hp }
    var healthFraction: Double { maxHealth > 0 ? max(0, currentHealth / maxHealth) : 0 }
    var missingHealthFraction: Double { 1 - healthFraction }

    init(
        resolved: ResolvedUnit,
        side: BattleSide,
        slot: Int,
        isLeader: Bool,
        statsOverride: Stats? = nil
    ) {
        self.id = UUID()
        self.sourceUnitID = resolved.unit.id
        self.side = side
        self.slot = slot
        self.name = resolved.name
        self.blueprintID = resolved.blueprint.id
        self.element = resolved.element
        self.pantheon = resolved.pantheon
        self.archetype = resolved.archetype
        self.role = resolved.role
        self.model = resolved.blueprint.model
        self.isLeader = isLeader
        let stats = (statsOverride ?? resolved.stats).clamped()
        self.baseStats = stats
        self.skills = resolved.skills
        self.currentHealth = stats.hp
        self.cooldowns = resolved.skills.map { _ in 0 }
        for active in resolved.activeRelicSets {
            self.relicSets[active.set] = active.completions
        }
    }

    // MARK: - Status queries

    func has(_ kind: StatusKind) -> Bool {
        statuses.contains { $0.kind == kind && $0.turnsRemaining > 0 }
    }

    func status(_ kind: StatusKind) -> ActiveStatus? {
        statuses.first { $0.kind == kind && $0.turnsRemaining > 0 }
    }

    var debuffCount: Int { statuses.filter { $0.kind.isDebuff }.count }
    var buffCount: Int { statuses.filter { $0.kind.isBuff }.count }

    /// Hard CC keeps the unit from acting at all.
    var isIncapacitated: Bool {
        statuses.contains { $0.kind.isHardCC && $0.turnsRemaining > 0 }
    }

    var canBeHealed: Bool {
        !has(.unrecoverable) && (relicSets[.titanfall] ?? 0) == 0
    }

    func hasRelicSet(_ set: RelicSet) -> Bool { (relicSets[set] ?? 0) > 0 }

    /// How many times a stacking set is completed — Ichor x2 fills twice as much.
    func relicSetStacks(_ set: RelicSet) -> Int { relicSets[set] ?? 0 }

    // MARK: - Effective stats

    /// Stats with every active status folded in. This is what the damage
    /// calculator and the turn scheduler read; nothing reads `baseStats` directly.
    var currentStats: Stats {
        var result = baseStats
        var atkMul = 1.0, defMul = 1.0, spdMul = 1.0
        var critBonus = 0.0

        for status in statuses where status.turnsRemaining > 0 {
            atkMul *= status.kind.multiplier(for: .atkPercent)
            defMul *= status.kind.multiplier(for: .defPercent)
            spdMul *= status.kind.multiplier(for: .spd)
            critBonus += status.kind.flatBonus(for: .critRate)
        }

        result.atk *= atkMul
        result.def *= defMul
        result.spd *= spdMul
        result.critRate += critBonus
        return result.clamped()
    }

    /// Multiplier on damage this combatant deals, from sets and statuses.
    var outgoingDamageMultiplier: Double {
        var multiplier = 1.0
        if hasRelicSet(.titanfall) { multiplier *= 1.30 }
        return multiplier
    }

    /// Multiplier on damage this combatant receives.
    var incomingDamageMultiplier: Double {
        var multiplier = 1.0
        if has(.brand) { multiplier *= 1.25 }
        return multiplier
    }

    func scalingValue(for scaling: DamageScaling) -> Double {
        let stats = currentStats
        switch scaling {
        case .attack: return stats.atk
        case .maxHealth: return stats.hp
        case .defense: return stats.def
        case .speed: return stats.spd
        }
    }

    func skill(at slot: Int) -> Skill? {
        skills.indices.contains(slot) ? skills[slot] : nil
    }

    func isSkillReady(_ slot: Int) -> Bool {
        guard let skill = skill(at: slot), !skill.isPassive else { return false }
        guard cooldowns.indices.contains(slot) else { return false }
        return cooldowns[slot] <= 0
    }

    var passiveSkill: Skill? { skills.first(where: { $0.isPassive }) }
}
