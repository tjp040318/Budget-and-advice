import Foundation

/// The five-element combat wheel.
///
/// Ember → Gale → Tide → Ember is a hard cycle. Radiance and Umbra sit outside
/// it and counter each other. Advantage is a damage multiplier *and* a crit-rate
/// bonus; disadvantage adds a glancing-hit chance. That is the whole triangle —
/// everything else in the game reads it through `Element.modifier(attacking:)`.
enum Element: String, Codable, CaseIterable, Identifiable, Sendable {
    case ember
    case tide
    case gale
    case radiance
    case umbra

    var id: String { rawValue }

    /// The premium pair. Radiance and Umbra sit outside the wheel and counter
    /// each other, and since 2026-09-17 they are the Light & Dark scroll's
    /// alone (`Banner.excludingLightDark`) and carry
    /// `UnitDatabase.lightDarkPremium` on their attack, health and defence
    /// for it. The owner: "PREMIUM PREMIUM mons that need to be better than
    /// the rest."
    var isLightOrDark: Bool { self == .radiance || self == .umbra }

    var displayName: String {
        switch self {
        case .ember: return "Ember"
        case .tide: return "Tide"
        case .gale: return "Gale"
        case .radiance: return "Radiance"
        case .umbra: return "Umbra"
        }
    }

    var accentHex: String {
        switch self {
        case .ember: return "#F2603C"
        case .tide: return "#3C9BF2"
        case .gale: return "#4FC98A"
        case .radiance: return "#F5D96B"
        case .umbra: return "#9B6BE0"
        }
    }

    /// Symbol name used on unit cards and the battle HUD.
    var glyph: String {
        switch self {
        case .ember: return "flame.fill"
        case .tide: return "drop.fill"
        case .gale: return "wind"
        case .radiance: return "sun.max.fill"
        case .umbra: return "moon.fill"
        }
    }

    enum Matchup: Sendable {
        case advantage
        case neutral
        case disadvantage

        var damageMultiplier: Double {
            switch self {
            case .advantage: return 1.5
            case .neutral: return 1.0
            case .disadvantage: return 0.7
            }
        }

        /// Flat crit-rate added when attacking into an advantage.
        var bonusCritRate: Double {
            self == .advantage ? 0.15 : 0.0
        }

        /// Chance the hit is downgraded to a glancing blow (no crit, 0.7x).
        var glancingChance: Double {
            self == .disadvantage ? 0.15 : 0.0
        }
    }

    /// How `self` fares when attacking `defender`.
    func matchup(against defender: Element) -> Matchup {
        if self == defender { return .neutral }
        switch (self, defender) {
        case (.ember, .gale), (.gale, .tide), (.tide, .ember):
            return .advantage
        case (.gale, .ember), (.tide, .gale), (.ember, .tide):
            return .disadvantage
        case (.radiance, .umbra), (.umbra, .radiance):
            return .advantage
        default:
            return .neutral
        }
    }
}
