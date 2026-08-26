import Foundation

/// The summoning currencies.
enum ScrollType: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The common scroll. Mostly 3★, with a thin 5★ tail.
    case mystical
    /// Banner scroll — rate-up on a featured unit, with pity.
    case pantheonic
    /// Guaranteed 4★ or better.
    case divine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mystical: return "Mystical Scroll"
        case .pantheonic: return "Pantheon Scroll"
        case .divine: return "Divine Scroll"
        }
    }

    var glyph: String {
        switch self {
        case .mystical: return "scroll.fill"
        case .pantheonic: return "sparkles"
        case .divine: return "crown.fill"
        }
    }

    /// Star-grade odds. Must sum to 1.
    var odds: [Int: Double] {
        switch self {
        case .mystical: return [3: 0.885, 4: 0.100, 5: 0.015]
        case .pantheonic: return [3: 0.790, 4: 0.180, 5: 0.030]
        case .divine: return [4: 0.880, 5: 0.120]
        }
    }

    /// Divinity price when bought directly, or nil if it is not for sale.
    var divinityPrice: Int? {
        switch self {
        case .mystical: return 75
        case .pantheonic: return 100
        case .divine: return nil
        }
    }

    var description: String {
        switch self {
        case .mystical:
            return "A common scroll. 1.5% chance of a 5★."
        case .pantheonic:
            return "Banner scroll. 3% chance of a 5★, with the featured unit at double weight and a guaranteed 5★ by the 90th summon."
        case .divine:
            return "Guarantees a 4★ or better."
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
