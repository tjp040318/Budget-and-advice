import Foundation

/// What kind of being a unit is. Purely flavour for combat, but it gates
/// awakening materials, campaign drops and some relic set bonuses.
enum Archetype: String, Codable, CaseIterable, Identifiable, Sendable {
    case god
    case demigod
    case hero
    case titan
    case monster
    case spirit
    case primordial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .god: return "God"
        case .demigod: return "Demigod"
        case .hero: return "Hero"
        case .titan: return "Titan"
        case .monster: return "Monster"
        case .spirit: return "Spirit"
        case .primordial: return "Primordial"
        }
    }

    /// Highest natural star grade this archetype is allowed to be summoned at.
    /// Gods and primordials are the only 5★ naturals; monsters cap at 4★.
    var maxNaturalStars: Int {
        switch self {
        case .god, .primordial: return 5
        case .titan, .demigod: return 5
        case .hero: return 4
        case .monster, .spirit: return 4
        }
    }

    /// Scale applied to the 3D model so a Titan reads as enormous next to a Hero.
    var modelScale: Float {
        switch self {
        case .primordial: return 1.6
        case .titan: return 1.45
        case .god: return 1.15
        case .demigod: return 1.02
        case .hero: return 1.0
        case .monster: return 1.1
        case .spirit: return 0.95
        }
    }
}

/// Battlefield job. Drives AI targeting priority and the auto-team builder.
enum CombatRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case attacker
    case defender
    case support
    case controller
    case hpTank = "hp_tank"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .attacker: return "Attacker"
        case .defender: return "Defender"
        case .support: return "Support"
        case .controller: return "Controller"
        case .hpTank: return "Vanguard"
        }
    }
}
