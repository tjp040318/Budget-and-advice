import Foundation

/// Reads a lineup for its resonances and holds every number they use
/// (`Docs/PLAN.md`, *Pantheon resonance*). Mirrored in `tools/balance.py`
/// as `RESONANCE`; `--resonance` measures each rank on a mono team.
enum ResonanceService {

    // MARK: - The numbers

    /// A pair of one pantheon lights rank I, three or more rank II; four or
    /// more different pantheons light the Concord.
    static let pairCount = 2
    static let majorityCount = 3
    static let concordPantheons = 4

    /// The Weighing of Hearts is a conditional line, not a stat: the judged
    /// — a debuffed enemy — take more from every Egyptian.
    static func weighingDamage(rank: ResonanceRank) -> Double { rank == .one ? 0.08 : 0.12 }

    /// Rank II's extras, read by the engine at its hooks. Every one is
    /// measured by `balance.py --resonance`: Valhalla's Attack Up is a turn
    /// (three turns measured 35% on the arena), and the Legion's shield and
    /// the Mandate's Recovery are given ONCE a side, to the first of the
    /// pantheon to fall under half health — not at the battle's start,
    /// where a full unit wastes a heal and a flat shield pool dwarfs a
    /// fight that takes little damage (an opening 12% measured 57%).
    static let kaHeal = 0.15
    static let hubrisBar = 0.25
    static let valhallaTurns = 1
    static let legionShield = 0.20
    static let mandateTurns = 3
    static let lowHealthBelow = 0.5

    /// A stat bonus a member gets: percent stats as a fraction of the BASE,
    /// the rate stats flat — exactly a leader skill's terms, so
    /// `BattleEngine.apply` handles both alike.
    struct Bonus: Equatable, Sendable {
        var stat: StatKind
        var amount: Double
    }

    static func bonuses(_ kind: ResonanceKind, rank: ResonanceRank) -> [Bonus] {
        switch kind {
        case .weighingOfHearts:
            return []
        case .olympianHubris:
            return [Bonus(stat: .critDamage, amount: rank == .one ? 0.10 : 0.20)]
        case .valhalla:
            return [Bonus(stat: .atkPercent, amount: rank == .one ? 0.05 : 0.08)]
        case .theLegion:
            return [Bonus(stat: .defPercent, amount: rank == .one ? 0.10 : 0.15)]
        case .mandateOfHeaven:
            return [Bonus(stat: .hpPercent, amount: rank == .one ? 0.08 : 0.12)]
        case .concord:
            return [
                Bonus(stat: .atkPercent, amount: 0.06), Bonus(stat: .hpPercent, amount: 0.06),
                Bonus(stat: .defPercent, amount: 0.06),
                Bonus(stat: .accuracy, amount: 0.05), Bonus(stat: .resistance, amount: 0.05),
            ]
        }
    }

    // MARK: - Reading a lineup

    static func active(for blueprints: [UnitBlueprint]) -> [ActiveResonance] {
        var tally: [Pantheon: Int] = [:]
        for blueprint in blueprints { tally[blueprint.pantheon, default: 0] += 1 }
        var lit: [ActiveResonance] = []
        for (pantheon, count) in tally where count >= pairCount {
            guard let kind = ResonanceKind.kind(for: pantheon) else { continue }
            lit.append(ActiveResonance(kind: kind, rank: count >= majorityCount ? .two : .one, members: count))
        }
        if tally.count >= concordPantheons {
            lit.append(ActiveResonance(kind: .concord, rank: .one, members: tally.count))
        }
        // The strongest first, then the fullest, then by name: the same order
        // on every screen.
        return lit.sorted {
            ($0.rank.rawValue, $0.members, $1.kind.rawValue) > ($1.rank.rawValue, $1.members, $0.kind.rawValue)
        }
    }

    static func active(for team: [ResolvedUnit]) -> [ActiveResonance] {
        active(for: team.map(\.blueprint))
    }

    /// Whether a resonance reaches a unit: its pantheon's members, or for
    /// the Concord everyone.
    static func applies(_ resonance: ActiveResonance, to blueprint: UnitBlueprint) -> Bool {
        guard let pantheon = resonance.kind.pantheon else { return true }
        return blueprint.pantheon == pantheon
    }

    /// The nearest unlit line, for the picker: what one more unit would
    /// light. Nil when the lineup is full, or when nothing is one away.
    static func hint(for blueprints: [UnitBlueprint], maxSize: Int) -> String? {
        guard blueprints.count < maxSize else { return nil }
        var tally: [Pantheon: Int] = [:]
        for blueprint in blueprints { tally[blueprint.pantheon, default: 0] += 1 }
        // The Concord first when it is one away: the rarer thing to know.
        if tally.count == concordPantheons - 1 {
            return "A unit of a \(ordinal(concordPantheons)) pantheon lights the \(ResonanceKind.concord.displayName)."
        }
        // Else the pantheon nearest its next rank, fullest first, a tie to
        // the first by name.
        let candidates = tally
            .filter { $0.value < majorityCount && ResonanceKind.kind(for: $0.key) != nil }
            .sorted { a, b in a.value != b.value ? a.value > b.value : a.key.rawValue < b.key.rawValue }
        if let (pantheon, count) = candidates.first, let kind = ResonanceKind.kind(for: pantheon) {
            let rank: ResonanceRank = count + 1 >= majorityCount ? .two : .one
            return "One more \(pantheon.displayName) ally lights \(kind.displayName) \(rank.label)."
        }
        return nil
    }

    private static func ordinal(_ number: Int) -> String {
        switch number {
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        case 5: return "fifth"
        default: return "\(number)th"
        }
    }
}
