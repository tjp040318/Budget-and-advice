import Foundation

/// A player-owned instance of a blueprint.
///
/// This is the only unit type that gets saved. Everything derived — final
/// stats, resolved skills, model spec — is recomputed from the blueprint on
/// demand so that balance patches apply to existing collections for free.
struct Unit: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var blueprintID: String

    var level: Int = 1
    /// Current star grade. Starts at the blueprint's natural stars and rises to
    /// 6 through evolution.
    var stars: Int
    var experience: Int = 0
    var isAwakened: Bool = false

    /// Skill levels, one per skill slot. Always the same count as the blueprint's
    /// skill array; `ProgressionService` keeps it in sync.
    var skillLevels: [Int]

    /// Relic instance ids by slot (1...6). A missing key is an empty slot.
    var equippedRelics: [Int: UUID] = [:]

    /// Locked units cannot be fed away or sold.
    var isLocked: Bool = false
    var acquiredAt: Date = Date()
    /// Set when the unit was obtained from a summon, for the collection log.
    var acquiredFrom: String = "summon"

    var maxLevel: Int { stars * 10 + 5 }
    var isMaxLevel: Bool { level >= maxLevel }
    var canEvolve: Bool { isMaxLevel && stars < 6 }

    init(blueprint: UnitBlueprint, level: Int = 1, stars: Int? = nil, awakened: Bool = false) {
        self.blueprintID = blueprint.id
        self.level = level
        self.stars = stars ?? blueprint.naturalStars
        self.isAwakened = awakened
        self.skillLevels = blueprint.skills.map { _ in 1 }
    }
}

/// A unit joined to its blueprint and its equipped relics, with final stats
/// computed. Built by `ProgressionService.resolve(_:)` and thrown away after —
/// nothing persists a `ResolvedUnit`.
struct ResolvedUnit: Identifiable, Sendable {
    var unit: Unit
    var blueprint: UnitBlueprint
    var relics: [Relic]
    var stats: Stats
    var skills: [Skill]

    var id: UUID { unit.id }
    var name: String {
        unit.isAwakened ? (blueprint.awakening?.awakenedName ?? blueprint.name) : blueprint.name
    }
    var element: Element { blueprint.element }
    var pantheon: Pantheon { blueprint.pantheon }
    var archetype: Archetype { blueprint.archetype }
    var role: CombatRole { blueprint.role }
    var stars: Int { unit.stars }
    var level: Int { unit.level }

    /// Sets with enough equipped pieces to be active, with how many times over.
    var activeRelicSets: [ActiveRelicSet] {
        var tally: [RelicSet: Int] = [:]
        for relic in relics { tally[relic.set, default: 0] += 1 }
        return tally.compactMap { set, count in
            let complete = count / set.piecesRequired
            return complete > 0 ? ActiveRelicSet(set: set, completions: complete) : nil
        }
        .sorted { $0.set.rawValue < $1.set.rawValue }
    }

    /// A single number for sorting the collection and seeding arena matchmaking.
    var power: Int {
        let offense = stats.atk * (1 + stats.critRate * stats.critDamage)
        let survivability = stats.hp * (1 + stats.def / 1000)
        let tempo = stats.spd / 100
        return Int((offense * 1.6 + survivability * 0.22) * tempo)
    }
}

/// A relic set that has enough equipped pieces to be doing something, and how
/// many times over it is completed. A named type rather than a tuple so it can
/// be used directly as a `ForEach` element.
struct ActiveRelicSet: Identifiable, Equatable, Sendable {
    var set: RelicSet
    var completions: Int

    var id: String { set.rawValue }
}
