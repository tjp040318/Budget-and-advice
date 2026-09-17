import Foundation

/// The eight passives a regalia can carry — one per `UnitDatabase.Kit`, so a
/// family's item sharpens the thing its kit already does (`Docs/PLAN.md`,
/// *Artifacts — the last item on the order*, option 3). A striker's whets
/// the crit, a duelist's the crit damage, a marksman's the first turn, a
/// bruiser's the defence under half, a warden's the shields, a healer's the
/// heals, an oracle's the debuffs' hold, a trickster's the attack bar. The
/// eleven hand-written families choose theirs by hand
/// (`UnitDatabase.handwrittenRegaliaTemplates`), as their skills were.
///
/// Every number is in ONE table, `magnitudes`, five per template for the
/// levels I–V, mirrored in `tools/balance.py` as `REGALIA`; `--regalia`
/// measures each template's V on three real fights and holds the best to
/// the rank II resonance's band (8–16%), none over it. No RNG anywhere in it on purpose: the
/// boons and the relics are the dice, the regalia is the one thing on a
/// unit a player can plan.
enum RegaliaTemplate: String, CaseIterable, Sendable {
    /// Striker: crit rate.
    case keenEdge
    /// Duelist: crit damage.
    case heavyHand
    /// Marksman: attack bar when the battle begins and as each wave walks on.
    case firstOffTheMark
    /// Bruiser: defence while under half health.
    case unbowed
    /// Warden: the shields it casts are larger.
    case bulwark
    /// Healer: the heals it casts are larger.
    case wellspring
    /// Oracle: accuracy, and from level III the debuffs it lands hold a
    /// turn longer (never a stun, a freeze or a sleep).
    case lastingWord
    /// Trickster: its attack-bar drains and gains are larger.
    case thiefOfTurns

    /// I–V.
    static let levels = 5
    /// The level from which a Lasting Word's debuffs hold a turn longer.
    static let lastingWordExtendsFrom = 3
    /// The health fraction Unbowed turns on under.
    static let unbowedBelow = 0.5

    /// The one table: five numbers per template, level I first. A rate stat
    /// (crit rate, crit damage, accuracy) is flat; a bar is a fraction of it;
    /// the rest are the fraction ADDED to the thing the kit does.
    static let magnitudes: [RegaliaTemplate: [Double]] = [
        .keenEdge:        [0.04, 0.06, 0.08, 0.10, 0.12],
        .heavyHand:       [0.06, 0.09, 0.12, 0.15, 0.18],
        .firstOffTheMark: [0.10, 0.15, 0.20, 0.25, 0.30],
        .unbowed:         [0.15, 0.20, 0.25, 0.30, 0.40],
        .bulwark:         [0.10, 0.15, 0.20, 0.25, 0.35],
        .wellspring:      [0.06, 0.09, 0.12, 0.15, 0.20],
        .lastingWord:     [0.05, 0.08, 0.10, 0.12, 0.15],
        .thiefOfTurns:    [0.15, 0.20, 0.25, 0.30, 0.40],
    ]

    /// The magnitude at a level, 1...5; a level outside that is clamped.
    func magnitude(at level: Int) -> Double {
        let table = RegaliaTemplate.magnitudes[self] ?? []
        guard !table.isEmpty else { return 0 }
        let index = min(table.count - 1, max(0, level - 1))
        return table[index]
    }

    /// The kit's template.
    static func template(for kit: UnitDatabase.Kit) -> RegaliaTemplate {
        switch kit {
        case .striker: return .keenEdge
        case .duelist: return .heavyHand
        case .marksman: return .firstOffTheMark
        case .bruiser: return .unbowed
        case .warden: return .bulwark
        case .healer: return .wellspring
        case .oracle: return .lastingWord
        case .trickster: return .thiefOfTurns
        }
    }

    /// The stat a template adds at build, flat, in a leader skill's terms
    /// (`BattleEngine.buildSide`); nil for the five that read at a hook.
    var buildStat: StatKind? {
        switch self {
        case .keenEdge: return .critRate
        case .heavyHand: return .critDamage
        case .lastingWord: return .accuracy
        case .firstOffTheMark, .unbowed, .bulwark, .wellspring, .thiefOfTurns: return nil
        }
    }

    var displayName: String {
        switch self {
        case .keenEdge: return "Keen Edge"
        case .heavyHand: return "Heavy Hand"
        case .firstOffTheMark: return "First Off the Mark"
        case .unbowed: return "Unbowed"
        case .bulwark: return "Bulwark"
        case .wellspring: return "Wellspring"
        case .lastingWord: return "Lasting Word"
        case .thiefOfTurns: return "Thief of Turns"
        }
    }

    /// The kit it belongs to, for the sheet.
    var kitName: String {
        switch self {
        case .keenEdge: return "Striker"
        case .heavyHand: return "Duelist"
        case .firstOffTheMark: return "Marksman"
        case .unbowed: return "Bruiser"
        case .bulwark: return "Warden"
        case .wellspring: return "Healer"
        case .lastingWord: return "Oracle"
        case .thiefOfTurns: return "Trickster"
        }
    }

    var glyph: String {
        switch self {
        case .keenEdge: return "scope"
        case .heavyHand: return "hammer.fill"
        case .firstOffTheMark: return "hare.fill"
        case .unbowed: return "shield.lefthalf.filled"
        case .bulwark: return "shield.fill"
        case .wellspring: return "heart.fill"
        case .lastingWord: return "hourglass"
        case .thiefOfTurns: return "clock.arrow.circlepath"
        }
    }

    /// Where the engine reads it, for the sheet.
    var hookName: String {
        switch self {
        case .keenEdge, .heavyHand, .lastingWord: return "Added to the stats at the battle's start"
        case .firstOffTheMark: return "When the battle begins, and as each wave walks on"
        case .unbowed: return "On every hit taken under half health"
        case .bulwark: return "On every shield it casts"
        case .wellspring: return "On every heal it casts"
        case .thiefOfTurns: return "On every attack bar it moves"
        }
    }

    /// The line at a magnitude and level: "+12% crit rate".
    func line(_ magnitude: Double, level: Int) -> String {
        let amount = BoonKind.percent(magnitude)
        switch self {
        case .keenEdge:
            return "+\(amount)% crit rate"
        case .heavyHand:
            return "+\(amount)% crit damage"
        case .firstOffTheMark:
            return "+\(amount) attack bar when the battle begins and as each wave walks on"
        case .unbowed:
            return "+\(amount)% defence while under \(BoonKind.percent(RegaliaTemplate.unbowedBelow))% health"
        case .bulwark:
            return "The shields it casts are \(amount)% larger"
        case .wellspring:
            return "The heals it casts are \(amount)% larger"
        case .lastingWord:
            let base = "+\(amount)% accuracy"
            return level >= RegaliaTemplate.lastingWordExtendsFrom
                ? base + ", and the debuffs it lands hold a turn longer (never a stun, a freeze or a sleep)"
                : base
        case .thiefOfTurns:
            return "Its attack-bar drains and gains are \(amount)% larger"
        }
    }

    /// The short form for the unit sheet's plate: "+12% crit".
    func shortLine(_ magnitude: Double, level: Int) -> String {
        let amount = BoonKind.percent(magnitude)
        switch self {
        case .keenEdge: return "+\(amount)% crit"
        case .heavyHand: return "+\(amount)% crit dmg"
        case .firstOffTheMark: return "+\(amount) bar per wave"
        case .unbowed: return "+\(amount)% DEF under half"
        case .bulwark: return "+\(amount)% shields"
        case .wellspring: return "+\(amount)% heals"
        case .lastingWord:
            return level >= RegaliaTemplate.lastingWordExtendsFrom ? "+\(amount)% ACC · debuffs +1 turn" : "+\(amount)% ACC"
        case .thiefOfTurns: return "+\(amount)% bar effects"
        }
    }
}

/// A family's own item: NAMED per family in its own myth
/// (`UnitDatabase.regaliaNames`), its passive the kit's template, its level
/// I–V the family's duplicates fed past the skill-up cap
/// (`RegaliaService.feed`). Unlocked by awakening. Never saved as a thing —
/// the level is one Optional on the `Unit`, and everything else is derived
/// from the family, so a rename or a retune reaches every save for free.
struct Regalia: Equatable, Sendable, Identifiable {
    var familyKey: String
    var name: String
    var blurb: String
    var template: RegaliaTemplate
    /// 1...5.
    var level: Int

    var id: String { familyKey }
    var magnitude: Double { template.magnitude(at: level) }
    var isMaxLevel: Bool { level >= RegaliaTemplate.levels }
    /// "III".
    var levelLabel: String { Regalia.numeral(level) }
    var line: String { template.line(magnitude, level: level) }
    var shortLine: String { template.shortLine(magnitude, level: level) }
    /// Whether a Lasting Word is holding the debuffs a turn longer yet.
    var extendsDebuffs: Bool {
        template == .lastingWord && level >= RegaliaTemplate.lastingWordExtendsFrom
    }

    static func numeral(_ level: Int) -> String {
        switch level {
        case ...1: return "I"
        case 2: return "II"
        case 3: return "III"
        case 4: return "IV"
        default: return "V"
        }
    }
}
