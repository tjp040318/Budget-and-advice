import Foundation

/// Every buff and debuff in the game.
///
/// The battle engine never special-cases a status by name outside of this file:
/// it asks each active status what it does to a stat, what it does at the start
/// or end of a turn, and whether it blocks the unit from acting. New statuses
/// slot in by adding a case and filling in those three answers.
enum StatusKind: String, Codable, CaseIterable, Identifiable, Sendable {
    // MARK: Buffs
    case attackUp = "attack_up"
    case defenseUp = "defense_up"
    case speedUp = "speed_up"
    case critRateUp = "crit_rate_up"
    case immunity
    case invincible
    case shield
    case recovery
    case counterStance = "counter_stance"
    case reflect
    case endure

    // MARK: Debuffs
    case attackDown = "attack_down"
    case defenseDown = "defense_down"
    case speedDown = "speed_down"
    case glancing
    case brand
    case stun
    case freeze
    case sleep
    case silence
    case burn
    case bomb
    case unrecoverable
    case provoke

    var id: String { rawValue }

    var isBuff: Bool {
        switch self {
        case .attackUp, .defenseUp, .speedUp, .critRateUp, .immunity,
             .invincible, .shield, .recovery, .counterStance, .reflect, .endure:
            return true
        default:
            return false
        }
    }

    var isDebuff: Bool { !isBuff }

    /// Hard crowd control — the turn is consumed and the unit does nothing.
    /// Provoke is deliberately not here: it redirects the target, it does not
    /// skip the turn.
    var isHardCC: Bool {
        switch self {
        case .stun, .freeze, .sleep: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .attackUp: return "Attack Up"
        case .defenseUp: return "Defense Up"
        case .speedUp: return "Haste"
        case .critRateUp: return "Focus"
        case .immunity: return "Immunity"
        case .invincible: return "Invincible"
        case .shield: return "Shield"
        case .recovery: return "Recovery"
        case .counterStance: return "Counter"
        case .reflect: return "Reflect"
        case .endure: return "Endure"
        case .attackDown: return "Attack Down"
        case .defenseDown: return "Defense Break"
        case .speedDown: return "Slow"
        case .glancing: return "Glancing"
        case .brand: return "Brand"
        case .stun: return "Stun"
        case .freeze: return "Freeze"
        case .sleep: return "Sleep"
        case .silence: return "Silence"
        case .burn: return "Burn"
        case .bomb: return "Bomb"
        case .unrecoverable: return "Unrecoverable"
        case .provoke: return "Provoke"
        }
    }

    var glyph: String {
        switch self {
        case .attackUp: return "arrow.up.circle.fill"
        case .defenseUp: return "shield.lefthalf.filled"
        case .speedUp: return "hare.fill"
        case .critRateUp: return "scope"
        case .immunity: return "checkmark.shield.fill"
        case .invincible: return "sparkles.rectangle.stack.fill"
        case .shield: return "shield.fill"
        case .recovery: return "cross.case.fill"
        case .counterStance: return "arrow.uturn.left.circle.fill"
        case .reflect: return "arrow.triangle.2.circlepath"
        case .endure: return "heart.circle.fill"
        case .attackDown: return "arrow.down.circle.fill"
        case .defenseDown: return "shield.slash.fill"
        case .speedDown: return "tortoise.fill"
        case .glancing: return "eye.slash.fill"
        case .brand: return "flame.circle.fill"
        case .stun: return "bolt.slash.fill"
        case .freeze: return "snowflake"
        case .sleep: return "moon.zzz.fill"
        case .silence: return "speaker.slash.fill"
        case .burn: return "flame.fill"
        case .bomb: return "burst.fill"
        case .unrecoverable: return "bandage.fill"
        case .provoke: return "exclamationmark.triangle.fill"
        }
    }

    /// Multiplicative factor this status applies to a stat while active.
    /// Returning 1.0 means "no effect on that stat".
    func multiplier(for stat: StatKind) -> Double {
        switch (self, stat) {
        case (.attackUp, .atkPercent): return 1.50
        case (.attackDown, .atkPercent): return 0.50
        case (.defenseUp, .defPercent): return 1.70
        case (.defenseDown, .defPercent): return 0.30
        case (.speedUp, .spd): return 1.30
        case (.speedDown, .spd): return 0.70
        default: return 1.0
        }
    }

    /// Flat addition applied to a rate stat while active.
    func flatBonus(for stat: StatKind) -> Double {
        switch (self, stat) {
        case (.critRateUp, .critRate): return 0.30
        default: return 0.0
        }
    }

    /// Whether landing this status is resisted by the target's Resistance stat.
    /// Buffs are never resisted; a handful of debuffs are guaranteed once the
    /// skill's own chance roll succeeds.
    var isResistible: Bool { isDebuff }

    /// Turns the status lasts if a skill does not say otherwise.
    var defaultDuration: Int {
        switch self {
        case .stun, .freeze, .sleep: return 1
        case .bomb: return 2
        default: return 2
        }
    }
}

/// A status currently sitting on a combatant.
struct ActiveStatus: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var kind: StatusKind
    var turnsRemaining: Int
    /// Combatant that applied it — bombs and reflects credit damage back to them.
    var sourceID: UUID?
    /// Payload for statuses that carry a number: shield HP, bomb damage, burn tick.
    var magnitude: Double = 0

    var isExpired: Bool { turnsRemaining <= 0 }
}
