import Foundation
import SwiftUI

/// The summoning currencies.
enum ScrollType: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The common scroll. Mostly 3★, with a thin 5★ tail.
    case mystical
    /// Banner scroll — rate-up on a featured unit, with pity.
    case pantheonic
    /// Guaranteed 4★ or better.
    case divine
    /// The commons only: the 3★ tier of every pantheon, the Hall of Ka's bread.
    case unknown
    /// Radiance and Umbra units only, of every pantheon.
    case lightDark = "light_dark"
    /// One element's units only.
    case ember, tide, gale

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mystical: return "Mystical Scroll"
        case .pantheonic: return "Pantheon Scroll"
        case .divine: return "Divine Scroll"
        case .unknown: return "Unknown Scroll"
        case .lightDark: return "Light & Dark Scroll"
        case .ember: return "Fire Scroll"
        case .tide: return "Water Scroll"
        case .gale: return "Wind Scroll"
        }
    }

    var glyph: String {
        switch self {
        case .mystical: return "scroll.fill"
        case .pantheonic: return "sparkles"
        case .divine: return "crown.fill"
        case .unknown: return "questionmark.circle.fill"
        case .lightDark: return "circle.lefthalf.filled"
        case .ember: return "flame.fill"
        case .tide: return "drop.fill"
        case .gale: return "wind"
        }
    }

    /// The colour this scroll burns in: the summoning circle takes its glow
    /// from here, so a fire scroll lights the room red and a light-and-dark
    /// one lights it violet. An elemental scroll uses its element's own colour
    /// so the ring and the unit that steps out of it agree.
    var tint: Color {
        switch self {
        case .mystical: return Color(hex: "#8FB8FF")
        case .pantheonic: return Theme.gold
        case .divine: return Color(hex: "#FFE9A8")
        case .unknown: return Color(hex: "#9E97C4")
        case .lightDark: return Color(hex: "#C89BFF")
        case .ember: return Element.ember.color
        case .tide: return Element.tide.color
        case .gale: return Element.gale.color
        }
    }

    /// Star-grade odds. Must sum to 1.
    var odds: [Int: Double] {
        switch self {
        case .mystical: return [3: 0.885, 4: 0.100, 5: 0.015]
        case .pantheonic: return [3: 0.790, 4: 0.180, 5: 0.030]
        case .divine: return [4: 0.880, 5: 0.120]
        case .unknown: return [3: 1.0]
        case .lightDark: return [3: 0.850, 4: 0.120, 5: 0.030]
        case .ember, .tide, .gale: return [3: 0.820, 4: 0.150, 5: 0.030]
        }
    }

    /// Divinity price when bought directly, or nil when it is not sold that
    /// way (the unknown scroll is drachma, in the bazaar).
    var divinityPrice: Int? {
        switch self {
        case .mystical: return 75
        case .pantheonic: return 100
        case .divine: return 600
        case .unknown: return nil
        case .lightDark: return 450
        case .ember, .tide, .gale: return 200
        }
    }

    var description: String {
        switch self {
        case .mystical:
            return "A common scroll. 1.5% chance of a 5★."
        case .pantheonic:
            return "Banner scroll. 3% chance of a 5★, with the featured unit at double weight and a guaranteed 5★ by the 90th summon."
        case .divine:
            return "Never less than a 4★; 12% chance of a 5★."
        case .unknown:
            return "The commons of every pantheon, 3★ only. Cheap, plentiful, and what the Hall of Ka feeds on."
        case .lightDark:
            return "Only Radiance and Umbra units, of every pantheon. 3% chance of a 5★."
        case .ember:
            return "Only Fire units, of every pantheon. 3% chance of a 5★."
        case .tide:
            return "Only Water units, of every pantheon. 3% chance of a 5★."
        case .gale:
            return "Only Wind units, of every pantheon. 3% chance of a 5★."
        }
    }
}

/// Pity state per banner. Persisted in the player save.
struct PityState: Codable, Equatable, Sendable {
    /// Summons since the last 5★ on this banner.
    var sinceLegendary: Int = 0
    /// Summons since the last 4★-or-better.
    var sinceRare: Int = 0
    /// True when the next 5★ is guaranteed to be the featured unit, because the
    /// previous one was not.
    var featuredGuaranteed: Bool = false
    var totalPulls: Int = 0
}
