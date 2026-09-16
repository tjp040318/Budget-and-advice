import Foundation

/// Pantheon resonance: what a team lights by WHO stands in it
/// (`Docs/PLAN.md`, *Pantheon resonance — set bonuses that read the whole
/// team*). A pair of one pantheon lights its resonance at rank I, three or
/// more at rank II; four or more DIFFERENT pantheons light the Concord
/// instead. Read off the lineup (`ResonanceService.active`), applied like a
/// leader skill for the numbers and at the engine's hooks for the rest.
/// Nothing here is saved: a resonance is a fact about a lineup, recomputed
/// wherever the lineup is.
enum ResonanceKind: String, Codable, CaseIterable, Sendable {
    case weighingOfHearts
    case olympianHubris
    case valhalla
    case theLegion
    case mandateOfHeaven
    case concord

    /// The pantheon that lights it; nil for the Concord, which variety lights.
    var pantheon: Pantheon? {
        switch self {
        case .weighingOfHearts: return .egyptian
        case .olympianHubris: return .greek
        case .valhalla: return .norse
        case .theLegion: return .roman
        case .mandateOfHeaven: return .chinese
        case .concord: return nil
        }
    }

    static func kind(for pantheon: Pantheon) -> ResonanceKind? {
        allCases.first { $0.pantheon == pantheon }
    }

    var displayName: String {
        switch self {
        case .weighingOfHearts: return "The Weighing of Hearts"
        case .olympianHubris: return "Olympian Hubris"
        case .valhalla: return "Valhalla"
        case .theLegion: return "The Legion"
        case .mandateOfHeaven: return "The Mandate of Heaven"
        case .concord: return "Concord of the Gods"
        }
    }

    /// How the pantheon's allies are named in a line.
    var allies: String {
        switch self {
        case .weighingOfHearts: return "Egyptian allies"
        case .olympianHubris: return "Greek allies"
        case .valhalla: return "Norse allies"
        case .theLegion: return "Roman allies"
        case .mandateOfHeaven: return "Jade Court allies"
        case .concord: return "Every ally"
        }
    }

    var glyph: String {
        switch self {
        case .weighingOfHearts: return "scalemass.fill"
        case .olympianHubris: return "bolt.fill"
        case .valhalla: return "snowflake"
        case .theLegion: return "shield.lefthalf.filled"
        case .mandateOfHeaven: return "leaf.fill"
        case .concord: return "sparkles"
        }
    }

    /// The line at a rank, the numbers read off `ResonanceService` so the
    /// words and the engine cannot drift apart.
    func line(rank: ResonanceRank) -> String {
        let bonuses = ResonanceService.bonuses(self, rank: rank)
        func percent(_ stat: StatKind) -> String {
            let amount = bonuses.first(where: { $0.stat == stat })?.amount ?? 0
            return "\(Int((amount * 100).rounded()))%"
        }
        switch self {
        case .weighingOfHearts:
            let judged = Int((ResonanceService.weighingDamage(rank: rank) * 100).rounded())
            let base = "\(allies) deal +\(judged)% damage against a debuffed enemy"
            return rank == .one ? base
                : base + ", and the first Egyptian ally to fall leaves its Ka: the others heal "
                    + "\(Int((ResonanceService.kaHeal * 100).rounded()))% of max health"
        case .olympianHubris:
            let base = "\(allies) +\(percent(.critDamage)) crit damage"
            return rank == .one ? base
                : base + ", and a Greek ally that kills gains \(Int((ResonanceService.hubrisBar * 100).rounded())) attack bar"
        case .valhalla:
            let base = "\(allies) +\(percent(.atkPercent)) attack"
            let turns = ResonanceService.valhallaTurns == 1 ? "a turn" : "\(ResonanceService.valhallaTurns) turns"
            return rank == .one ? base
                : base + ", and when a Norse ally falls the others gain Attack Up for \(turns)"
        case .theLegion:
            let base = "\(allies) +\(percent(.defPercent)) defence"
            return rank == .one ? base
                : base + ", and the first to fall under half health gains a shield of "
                    + "\(Int((ResonanceService.legionShield * 100).rounded()))% of max health"
        case .mandateOfHeaven:
            let base = "\(allies) +\(percent(.hpPercent)) health"
            return rank == .one ? base
                : base + ", and the first to fall under half health gains Recovery for \(ResonanceService.mandateTurns) turns"
        case .concord:
            return "\(allies) +\(percent(.atkPercent)) attack, health and defence, and +\(percent(.accuracy)) accuracy and resistance"
        }
    }
}

enum ResonanceRank: Int, Codable, Comparable, Sendable {
    case one = 1
    case two = 2

    var label: String { self == .one ? "I" : "II" }

    static func < (lhs: ResonanceRank, rhs: ResonanceRank) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A resonance a lineup lights, with its rank and how many light it: the
/// pantheon's members, or for the Concord the count of different pantheons.
struct ActiveResonance: Equatable, Identifiable, Sendable {
    var kind: ResonanceKind
    var rank: ResonanceRank
    var members: Int

    var id: String { kind.rawValue }
    var displayName: String { "\(kind.displayName) \(rank.label)" }
    var line: String { kind.line(rank: rank) }
}
