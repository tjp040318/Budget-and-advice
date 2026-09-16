import Foundation

/// How well a raid went, F to SSS: the genre's Rift grade, and the first
/// thing in this game a fight can be got BETTER at after its first clear.
///
/// Every other fight is binary — cleared or not — and a raid was too until
/// now. The grade decides the Aether the run pays (`RaidGradeService.aether`),
/// lifts the relic's quality floor at the top of the ladder, and is kept per
/// raid as a high-water mark (`Player.raidGrades`) so the card can name the
/// mark to beat. `Docs/PLAN.md`, *Awakened relics and the Titans*.
enum RaidGrade: String, Codable, CaseIterable, Comparable, Sendable {
    case f, d, c, b, a, s, ss, sss

    /// The letters on the stamp.
    var label: String { rawValue.uppercased() }

    /// Position on the ladder, F = 0 … SSS = 7.
    var rank: Int { RaidGrade.allCases.firstIndex(of: self) ?? 0 }

    /// A kill is never below B, and nothing short of a kill reaches it.
    var isKill: Bool { self >= .b }

    static func < (lhs: RaidGrade, rhs: RaidGrade) -> Bool { lhs.rank < rhs.rank }
}

/// The Titans' currency: what a raid pays by its grade and — from phase 2 —
/// what a relic's awakening spends. It has exactly one source on purpose: a
/// crafting currency with two sources is just another wallet line.
///
/// Elemental aether comes in the boss's own element (`aether_ember` from the
/// serpent, `aether_gale` from the Jötunn) and an awakening will want the
/// relic's set colour, so the beasts are different farms rather than one
/// repeated; **pure** aether (`aether_pure`) is the half any awakening takes
/// and comes from a KILL only.
enum Aether {
    static let prefix = "aether_"
    static let pure = "aether_pure"

    static func id(for element: Element) -> String { prefix + element.rawValue }

    static func isAether(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// The element of an elemental aether's id; nil for pure aether and for
    /// anything that is not aether at all.
    static func element(of id: String) -> Element? {
        guard isAether(id) else { return nil }
        return Element(rawValue: String(id.dropFirst(prefix.count)))
    }

    static func name(for id: String) -> String {
        if id == pure { return "Pure Aether" }
        if let element = element(of: id) { return "\(element.displayName) Aether" }
        return id
    }

    static func count(_ id: String, player: Player) -> Int { player.aether?[id] ?? 0 }

    static func add(_ id: String, _ amount: Int, player: inout Player) {
        guard amount > 0 else { return }
        var held = player.aether ?? [:]
        held[id, default: 0] += amount
        player.aether = held
    }
}

enum RaidGradeService {

    // MARK: The ladder

    /// A kill is graded on its PACE: the turns it took against the boss's own
    /// enrage turn (`RaidBossProfile.enrageTurn`, the line its designer drew
    /// between the good team and the slow one). Each bar is a fraction of it:
    /// SSS inside 70% of it (Apep: by turn 45), SS inside 85% (55), S before
    /// it enrages at all (65), A within 130% (84), and any kill is a B.
    ///
    /// The numbers come from `balance.py --grades`: its best ladder team — a
    /// maxed 6★ four with no sets, no skill-ups and no leader — kills the
    /// serpent in about 60–90 turns with its median ON the enrage turn,
    /// which is the S/A line by design (the enrage was tuned to sit there);
    /// SS asks about a fifth more pace than that team has and SSS a third,
    /// which is what the sets, the skill-ups, a leader and a fifth unit are
    /// for, none of which the sim has. Total damage cannot
    /// grade a kill here, whatever the Rift does: the barrier regenerates and
    /// the guard heals, so a SLOW kill deals MORE total damage than a fast
    /// one and the ladder would run backwards. Mirrored as `GRADE_PACE`.
    static let paceBars: [(grade: RaidGrade, fraction: Double)] = [
        (.sss, 0.70), (.ss, 0.85), (.s, 1.00), (.a, 1.30)
    ]
    /// The pace bar for a profile with no enrage clock (0 means never).
    static let defaultEnrageTurn = 60

    /// Anything short of a kill is graded on the SHARE of the boss's health
    /// the team took (`BattleResult.raidShare`): C from 60%, D from 30%, F
    /// below. It never reaches B — a kill always outranks a non-kill.
    /// Mirrored as `GRADE_SHARE`.
    static let shareBars: [(grade: RaidGrade, fraction: Double)] = [
        (.c, 0.60), (.d, 0.30)
    ]

    static func enrageBar(_ profile: RaidBossProfile) -> Int {
        profile.enrageTurn > 0 ? profile.enrageTurn : defaultEnrageTurn
    }

    /// The last turn a kill may land on and still earn a pace grade — the
    /// number the card prints, and the one `grade` compares against, so the
    /// two can never disagree. Floored, with a hair of slack so 60 × 0.7 is
    /// 42 and not 41.
    static func turnsAllowed(for grade: RaidGrade, profile: RaidBossProfile) -> Int? {
        guard let bar = paceBars.first(where: { $0.grade == grade }) else { return nil }
        return Int((Double(enrageBar(profile)) * bar.fraction + 1e-9).rounded(.down))
    }

    static func grade(result: BattleResult, profile: RaidBossProfile) -> RaidGrade {
        if result.outcome == .victory {
            let turns = max(1, result.turnsTaken)
            for bar in paceBars {
                if let allowed = turnsAllowed(for: bar.grade, profile: profile), turns <= allowed {
                    return bar.grade
                }
            }
            return .b
        }
        let share = result.raidShare ?? 0
        for bar in shareBars where share >= bar.fraction { return bar.grade }
        return .f
    }

    /// Nil when the stage is not a raid.
    static func grade(for stage: Stage, result: BattleResult) -> RaidGrade? {
        guard let profile = StageDatabase.raid(containing: stage)?.profile else { return nil }
        return grade(result: result, profile: profile)
    }

    // MARK: What a grade pays

    /// Aether per grade: the elemental kind, and the pure kind a kill alone
    /// pays. An F pays nothing, so a forfeit farms nothing; a D that took a
    /// third of the boss's health still leaves with the elemental half of an
    /// awakening's price, which is what keeps a summoner who cannot beat it
    /// yet coming back. Mirrored as `AETHER_BY_GRADE`.
    static func aether(for grade: RaidGrade) -> (elemental: Int, pure: Int) {
        switch grade {
        case .f: return (0, 0)
        case .d: return (2, 0)
        case .c: return (4, 0)
        case .b: return (5, 1)
        case .a: return (6, 1)
        case .s: return (8, 2)
        case .ss: return (10, 3)
        case .sss: return (12, 4)
        }
    }

    /// The relic quality the top of the ladder guarantees, over the raid's
    /// own floor (`StageRewards.qualityFloor`, Rare): Hero from S, Legend at
    /// SSS. Nil below S. Mirrored as `GRADE_QUALITY_FLOOR`.
    static func qualityFloor(for grade: RaidGrade) -> RelicQuality? {
        switch grade {
        case .sss: return .legend
        case .s, .ss: return .hero
        case .f, .d, .c, .b, .a: return nil
        }
    }

    /// The chance the raid's relic drops AWAKENED, at the top of the ladder
    /// only: SS one in twelve, SSS one in seven — the dream beside the
    /// awakening the aether buys. Mirrored as `AWAKENED_DROP`.
    static func awakenedChance(for grade: RaidGrade) -> Double {
        switch grade {
        case .sss: return 0.15
        case .ss: return 0.08
        case .f, .d, .c, .b, .a, .s: return 0
        }
    }

    /// The element a raid's aether comes in: its boss's own — Apep is ember,
    /// the Jötunn gale. Read off the blueprint so it cannot drift from the
    /// fight the player just had.
    static func element(of raid: RaidEncounter) -> Element {
        let bossID = raid.stage.enemies.first(where: { $0.raid != nil })?.blueprintID
        return bossID.flatMap { UnitDatabase.blueprint($0)?.element } ?? .ember
    }

    /// Pays a graded run's aether into the save and moves the raid's
    /// high-water mark. Returns what was paid, keyed by aether id, for the
    /// receipt.
    @discardableResult
    static func pay(_ grade: RaidGrade, raid: RaidEncounter, player: inout Player) -> [String: Int] {
        record(grade, raid: raid, player: &player)
        let pay = aether(for: grade)
        var paid: [String: Int] = [:]
        if pay.elemental > 0 {
            let id = Aether.id(for: element(of: raid))
            paid[id] = pay.elemental
            Aether.add(id, pay.elemental, player: &player)
        }
        if pay.pure > 0 {
            paid[Aether.pure] = pay.pure
            Aether.add(Aether.pure, pay.pure, player: &player)
        }
        return paid
    }

    // MARK: The mark to beat

    static func bestGrade(for raid: RaidEncounter, player: Player) -> RaidGrade? {
        player.raidGrades?[raid.id].flatMap(RaidGrade.init(rawValue:))
    }

    /// The high-water mark only ever rises.
    static func record(_ grade: RaidGrade, raid: RaidEncounter, player: inout Player) {
        var marks = player.raidGrades ?? [:]
        if let held = marks[raid.id].flatMap(RaidGrade.init(rawValue:)), held >= grade { return }
        marks[raid.id] = grade.rawValue
        player.raidGrades = marks
    }

    // MARK: Words

    /// One line under the stamp: what the grade was earned for.
    static func caption(grade: RaidGrade, result: BattleResult, profile: RaidBossProfile) -> String {
        if result.outcome == .victory {
            let enrage = enrageBar(profile)
            let turns = result.turnsTaken
            if turns < enrage {
                return "Fell in \(turns) turns, \(enrage - turns) before the enrage"
            }
            return "Fell in \(turns) turns, enraged from turn \(enrage)"
        }
        let share = Int(((result.raidShare ?? 0) * 100).rounded())
        return "Took \(share)% of its health"
    }

    static func caption(for stage: Stage, result: BattleResult) -> String? {
        guard let profile = StageDatabase.raid(containing: stage)?.profile else { return nil }
        return caption(grade: grade(result: result, profile: profile), result: result, profile: profile)
    }

    /// The card's line: what the next grade up asks for.
    static func target(after best: RaidGrade?, profile: RaidBossProfile) -> String {
        func turns(_ grade: RaidGrade) -> Int { turnsAllowed(for: grade, profile: profile) ?? enrageBar(profile) }
        guard let best, best.isKill else {
            return "Bring it down for a B. S inside \(turns(.s)) turns, SSS inside \(turns(.sss))."
        }
        switch best {
        case .b: return "A inside \(turns(.a)) turns."
        case .a: return "S inside \(turns(.s)) turns, before it enrages."
        case .s: return "SS inside \(turns(.ss)) turns."
        case .ss: return "SSS inside \(turns(.sss)) turns."
        case .sss: return "Nothing stands above SSS."
        case .f, .d, .c: return "Bring it down for a B."
        }
    }
}
