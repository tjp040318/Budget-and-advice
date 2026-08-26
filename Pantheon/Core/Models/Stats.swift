import Foundation

/// The eight numbers a unit fights with.
///
/// `hp`, `atk`, `def` and `spd` are absolute. The remaining four are rates in
/// 0...1 space (0.15 == 15%) so relic maths never has to know about percent
/// signs. `critDamage` is the *bonus* over a normal hit, so 0.5 means 150% total.
struct Stats: Codable, Equatable, Sendable {
    var hp: Double = 0
    var atk: Double = 0
    var def: Double = 0
    var spd: Double = 0
    var critRate: Double = 0
    var critDamage: Double = 0
    var accuracy: Double = 0
    var resistance: Double = 0

    static let zero = Stats()

    /// Every unit starts with these before blueprint bases are applied.
    static let baseline = Stats(
        hp: 0, atk: 0, def: 0, spd: 0,
        critRate: 0.15, critDamage: 0.50,
        accuracy: 0.0, resistance: 0.15
    )

    static func + (lhs: Stats, rhs: Stats) -> Stats {
        Stats(
            hp: lhs.hp + rhs.hp,
            atk: lhs.atk + rhs.atk,
            def: lhs.def + rhs.def,
            spd: lhs.spd + rhs.spd,
            critRate: lhs.critRate + rhs.critRate,
            critDamage: lhs.critDamage + rhs.critDamage,
            accuracy: lhs.accuracy + rhs.accuracy,
            resistance: lhs.resistance + rhs.resistance
        )
    }

    static func += (lhs: inout Stats, rhs: Stats) { lhs = lhs + rhs }

    static func * (lhs: Stats, scalar: Double) -> Stats {
        Stats(
            hp: lhs.hp * scalar,
            atk: lhs.atk * scalar,
            def: lhs.def * scalar,
            spd: lhs.spd * scalar,
            critRate: lhs.critRate * scalar,
            critDamage: lhs.critDamage * scalar,
            accuracy: lhs.accuracy * scalar,
            resistance: lhs.resistance * scalar
        )
    }

    /// Clamp the rate stats to the ranges the battle engine assumes.
    func clamped() -> Stats {
        var s = self
        s.hp = max(1, s.hp.rounded())
        s.atk = max(1, s.atk.rounded())
        s.def = max(1, s.def.rounded())
        s.spd = max(1, s.spd.rounded())
        s.critRate = min(1.0, max(0, s.critRate))
        s.critDamage = max(0, s.critDamage)
        s.accuracy = min(1.0, max(0, s.accuracy))
        s.resistance = min(1.0, max(0, s.resistance))
        return s
    }
}

/// Addressable stat identity — used by relics, buffs and the stat inspector so
/// that "increase ATK by 40%" is data rather than a switch statement.
enum StatKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hpFlat = "hp_flat"
    case hpPercent = "hp_pct"
    case atkFlat = "atk_flat"
    case atkPercent = "atk_pct"
    case defFlat = "def_flat"
    case defPercent = "def_pct"
    case spd
    case critRate = "crit_rate"
    case critDamage = "crit_dmg"
    case accuracy
    case resistance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hpFlat: return "HP"
        case .hpPercent: return "HP %"
        case .atkFlat: return "ATK"
        case .atkPercent: return "ATK %"
        case .defFlat: return "DEF"
        case .defPercent: return "DEF %"
        case .spd: return "SPD"
        case .critRate: return "CRIT Rate"
        case .critDamage: return "CRIT DMG"
        case .accuracy: return "Accuracy"
        case .resistance: return "Resistance"
        }
    }

    var isPercentage: Bool {
        switch self {
        case .hpFlat, .atkFlat, .defFlat, .spd: return false
        default: return true
        }
    }

    /// Format a raw value for display, e.g. `0.32 -> "32%"`, `184 -> "184"`.
    func format(_ value: Double) -> String {
        isPercentage
            ? "\(Int((value * 100).rounded()))%"
            : "\(Int(value.rounded()))"
    }
}

/// A stat delta that may be flat or proportional to a base value.
/// Relic sub-stats, set bonuses and leader skills are all expressed as these.
struct StatModifier: Codable, Equatable, Sendable {
    var kind: StatKind
    var value: Double

    init(_ kind: StatKind, _ value: Double) {
        self.kind = kind
        self.value = value
    }

    var displayText: String {
        "\(kind.displayName) +\(kind.format(value))"
    }
}
