import Foundation

/// The nine kinds of boon: a CONDITIONAL line the engine reads at one of
/// four hooks, never a flat stat (`Docs/PLAN.md`, *Boons — the earned
/// socket*). A Bane and a Ward come in the five colours (`BoonKind.element`);
/// the other seven have none. The numbers are mirrored in `tools/balance.py`
/// as `BOONS`, and `--boons` measures every kind against five fights.
enum BoonFamily: String, Codable, CaseIterable, Sendable {
    case bane
    case giantSlayer
    case firstBlood
    case lastStand
    case executioner
    case ward
    case unfading
    case swiftFooted
    case hydrasBlood

    /// Where the engine reads the line.
    enum Hook: String, Sendable {
        case damage
        case damageTaken
        case turnStart
        case battleStart
        case afterHit

        var displayName: String {
            switch self {
            case .damage: return "On the damage roll"
            case .damageTaken: return "On damage taken"
            case .turnStart: return "At the start of a turn"
            case .battleStart: return "When the battle begins"
            case .afterHit: return "After a hit"
            }
        }
    }

    /// The health fractions the conditional kinds turn on. Mirrored in
    /// `tools/balance.py` as `BOON_THRESHOLDS`.
    static let lastStandBelow = 0.50
    static let executionerBelow = 0.30
    static let unfadingBelow = 0.50

    /// A Bane or a Ward is of one element.
    var isElemental: Bool { self == .bane || self == .ward }

    var hook: Hook {
        switch self {
        case .bane, .giantSlayer, .firstBlood, .lastStand, .executioner: return .damage
        case .ward: return .damageTaken
        case .unfading: return .turnStart
        case .swiftFooted: return .battleStart
        case .hydrasBlood: return .afterHit
        }
    }

    /// The line's size at 6★ before the roll: a fraction of the damage, of
    /// max health, of the attack bar, or of the damage dealt. A cache of a
    /// lower grade scales it (`BoonService.gradeScale`), the roll spreads it
    /// (`BoonService.rollRange`) and every push lifts it (`pushStep`).
    ///
    /// Measured, not guessed: `balance.py --boons` plays each kind on five
    /// fights and holds every kind's best fight to a 6–18% lift. A Bane and
    /// a Ward are worth about their number where every foe is their colour;
    /// First Blood, Last Stand and Executioner are big numbers on rare
    /// turns, so they carry the biggest; Hydra's Blood is small because an
    /// attacker deals many times what it takes.
    var base: Double {
        switch self {
        case .bane: return 0.15
        case .giantSlayer: return 0.18
        case .firstBlood: return 0.30
        case .lastStand: return 0.70
        case .executioner: return 0.35
        case .ward: return 0.14
        case .unfading: return 0.08
        case .swiftFooted: return 0.40
        case .hydrasBlood: return 0.05
        }
    }

    /// The kind's glyph; a Bane or a Ward wears its element's instead.
    var glyph: String {
        switch self {
        case .bane: return "flame.fill"
        case .giantSlayer: return "hammer.fill"
        case .firstBlood: return "drop.fill"
        case .lastStand: return "flag.fill"
        case .executioner: return "scope"
        case .ward: return "shield.fill"
        case .unfading: return "leaf.fill"
        case .swiftFooted: return "hare.fill"
        case .hydrasBlood: return "heart.fill"
        }
    }

    var displayName: String {
        switch self {
        case .bane: return "Bane"
        case .giantSlayer: return "Giant-slayer"
        case .firstBlood: return "First Blood"
        case .lastStand: return "Last Stand"
        case .executioner: return "Executioner"
        case .ward: return "Ward"
        case .unfading: return "Unfading"
        case .swiftFooted: return "Swift-footed"
        case .hydrasBlood: return "Hydra's Blood"
        }
    }
}

/// One kind of boon: a family, and for a Bane or a Ward its colour. Seventeen
/// in all (`all`): five Banes, five Wards, and the seven of no colour.
struct BoonKind: Codable, Equatable, Hashable, Sendable {
    var family: BoonFamily
    /// The colour of a Bane or a Ward; nil for the seven kinds that have none.
    var element: Element?

    init(_ family: BoonFamily, element: Element? = nil) {
        self.family = family
        self.element = family.isElemental ? element : nil
    }

    static var all: [BoonKind] {
        BoonFamily.allCases.flatMap { family -> [BoonKind] in
            family.isElemental
                ? Element.allCases.map { BoonKind(family, element: $0) }
                : [BoonKind(family)]
        }
    }

    var displayName: String {
        guard let element, family.isElemental else { return family.displayName }
        return "\(family.displayName) of \(element.displayName)"
    }

    var glyph: String { element?.glyph ?? family.glyph }

    /// The aether a push is paid in: the colour's own, or pure for a kind of
    /// no colour — the Titans' currency either way, so the Titans stay the
    /// source (`Aether`).
    var aetherID: String { element.map { Aether.id(for: $0) } ?? Aether.pure }

    /// The line at a magnitude: "+18% damage against Tide".
    func line(_ magnitude: Double) -> String { line(amount: BoonKind.percent(magnitude)) }

    /// The line over a range, for a cache's three doors: "+12–20% damage
    /// against Tide".
    func line(over range: ClosedRange<Double>) -> String {
        line(amount: "\(BoonKind.percent(range.lowerBound))–\(BoonKind.percent(range.upperBound))")
    }

    /// The short form for a chip beside the name: "+18% vs Tide".
    func shortLine(_ magnitude: Double) -> String {
        let amount = BoonKind.percent(magnitude)
        let colour = element?.displayName ?? ""
        switch family {
        case .bane: return "+\(amount)% vs \(colour)"
        case .giantSlayer: return "+\(amount)% vs bosses"
        case .firstBlood: return "+\(amount)% first turn"
        case .lastStand: return "+\(amount)% under \(BoonKind.percent(BoonFamily.lastStandBelow))%"
        case .executioner: return "+\(amount)% vs under \(BoonKind.percent(BoonFamily.executionerBelow))%"
        case .ward: return "−\(amount)% from \(colour)"
        case .unfading: return "+\(amount)% HP under \(BoonKind.percent(BoonFamily.unfadingBelow))%"
        case .swiftFooted: return "+\(amount) bar at start"
        case .hydrasBlood: return "+\(amount)% lifesteal"
        }
    }

    private func line(amount: String) -> String {
        let colour = element?.displayName ?? ""
        switch family {
        case .bane:
            return "+\(amount)% damage against \(colour)"
        case .giantSlayer:
            return "+\(amount)% damage against a boss"
        case .firstBlood:
            return "+\(amount)% damage until this unit's first turn ends"
        case .lastStand:
            return "+\(amount)% damage while under \(BoonKind.percent(BoonFamily.lastStandBelow))% health"
        case .executioner:
            return "+\(amount)% damage against a target under \(BoonKind.percent(BoonFamily.executionerBelow))% health"
        case .ward:
            return "\(amount)% less damage from \(colour)"
        case .unfading:
            return "Heals \(amount)% of max health at the start of a turn begun under \(BoonKind.percent(BoonFamily.unfadingBelow))%"
        case .swiftFooted:
            return "+\(amount) attack bar when the battle begins"
        case .hydrasBlood:
            return "Recovers \(amount)% of the damage dealt"
        }
    }

    /// A fraction as its percentage, to a tenth when it is not whole: "18",
    /// "18.3".
    static func percent(_ value: Double) -> String {
        let tenths = (value * 1000).rounded() / 10
        if tenths == tenths.rounded() { return "\(Int(tenths))" }
        return String(format: "%.1f", tenths)
    }
}

/// A boon: the item in the socket at the centre of a unit's relic ring. The
/// KIND is chosen (a cache's three doors), the MAGNITUDE rolls, and a push
/// lifts it as a choice of two — so the RNG is inside a thing the player
/// picked, and a better one always exists (`BoonService`).
struct Boon: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var kind: BoonKind
    /// 4...6 stars: the cache's grade, which sets the base the roll is on.
    var grade: Int
    /// The rolled line, as a fraction (0.183 is +18.3%). It only ever goes up.
    var magnitude: Double
    /// Pushes taken, 0...`BoonService.maxPushes`.
    var pushes: Int = 0
    /// Set by `BoonService` when the boon is socketed, so the list can show
    /// who wears it without scanning the roster.
    var equippedBy: UUID? = nil
    var isLocked: Bool = false
    /// A push paid for and WAITING ON THE PLAYER: the seed its two bumps are
    /// derived from (`BoonService.pushCandidates`), exactly as a relic's
    /// `pendingRoll` — a seed and not a rolled pair, so closing the sheet and
    /// coming back shows the same two. Optional, like every save field added
    /// since the first.
    var pendingRoll: UInt64? = nil

    var hasPendingRoll: Bool { pendingRoll != nil }
    var isFullyPushed: Bool { pushes >= BoonService.maxPushes }
    var displayName: String { kind.displayName }
    var line: String { kind.line(magnitude) }
    var shortLine: String { kind.shortLine(magnitude) }
    /// The roll against the grade's base: 0.75...1.25 fresh, higher pushed.
    var quality: Double {
        let base = BoonService.base(kind, grade: grade)
        return base > 0 ? magnitude / base : 0
    }
}

/// A boon not yet chosen: a cache of a grade, whose three doors are derived
/// from its seed (`BoonService.offers`) so a player who closes the sheet
/// comes back to the same three.
struct BoonCache: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var grade: Int
    var seed: UInt64
    /// Where it came from, for the card: a Titan, the Labyrinth, the Tower,
    /// a Judgment.
    var source: String = ""

    var displayName: String { "\(grade)★ Boon Cache" }
}
