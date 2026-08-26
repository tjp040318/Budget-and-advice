import Foundation

/// Competitive tiers. Rank points move between them and never reset below the
/// tier floor, so a bad night cannot undo a season.
enum ArenaTier: Int, Codable, CaseIterable, Identifiable, Sendable {
    case initiate = 0
    case acolyte
    case oracle
    case champion
    case demigod
    case olympian

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .initiate: return "Initiate"
        case .acolyte: return "Acolyte"
        case .oracle: return "Oracle"
        case .champion: return "Champion"
        case .demigod: return "Demigod"
        case .olympian: return "Olympian"
        }
    }

    /// Rank points needed to enter, and the floor you cannot drop below.
    var threshold: Int {
        switch self {
        case .initiate: return 0
        case .acolyte: return 1_200
        case .oracle: return 1_700
        case .champion: return 2_300
        case .demigod: return 3_000
        case .olympian: return 3_800
        }
    }

    var accentHex: String {
        switch self {
        case .initiate: return "#9AA3B0"
        case .acolyte: return "#7FB88C"
        case .oracle: return "#5FA8D8"
        case .champion: return "#C08CE8"
        case .demigod: return "#E8B04F"
        case .olympian: return "#F25C4F"
        }
    }

    /// Laurels paid out each day at this tier.
    var dailyLaurels: Int { 40 + rawValue * 35 }

    static func tier(forPoints points: Int) -> ArenaTier {
        allCases.last(where: { points >= $0.threshold }) ?? .initiate
    }
}

/// The player's arena standing, persisted in the save.
struct ArenaRecord: Codable, Equatable, Sendable {
    var points: Int = 1_000
    var wins: Int = 0
    var losses: Int = 0
    var defenseWins: Int = 0
    var defenseLosses: Int = 0
    /// Attack attempts left today.
    var attacksRemaining: Int = 10
    var maxAttacks: Int = 10
    var lastRefresh: Date = Date()
    var highestPoints: Int = 1_000
    /// Ids of opponents already beaten from the current pool, so the refresh
    /// button is the only way to see them again.
    var defeatedOpponentIDs: [String] = []

    var tier: ArenaTier { ArenaTier.tier(forPoints: points) }
    var winRate: Double {
        let total = wins + losses
        return total == 0 ? 0 : Double(wins) / Double(total)
    }
}

/// A matchmaking candidate.
struct ArenaOpponent: Identifiable, Sendable {
    var id: String
    var name: String
    var points: Int
    var tier: ArenaTier
    var team: [ResolvedUnit]
    var power: Int
    /// Points swing if you win, and if you lose.
    var pointsForWin: Int
    var pointsForLoss: Int
}

/// PvP.
///
/// There is no server yet, so opponents are generated deterministically from a
/// seed derived from the player's rank and the day. When the backend lands, the
/// only thing that changes is where `pool(for:)` gets its teams — the battle
/// path, the scoring and the rewards are already the real ones, and defence
/// teams are already simulated with the same engine the attacker uses.
enum ArenaService {

    static let teamSize = 4

    /// Names used for generated opponents. Replaced by real display names when
    /// matchmaking goes online.
    private static let opponentNames = [
        "Thalassa", "Kyrios", "Nikandros", "Eirene", "Damaris", "Praxis",
        "Alkaios", "Xanthe", "Leontios", "Phaidra", "Melitta", "Orestes",
        "Zenon", "Kallias", "Hypatia", "Straton"
    ]

    /// Deterministic seed for a day's opponent pool.
    static func poolSeed(points: Int, day: Int) -> UInt64 {
        UInt64(bitPattern: Int64(points &* 31 &+ day &* 7919)) &+ 0xA5A5_5A5A
    }

    /// Builds a fresh set of opponents near the player's rating.
    static func pool(for record: ArenaRecord, day: Int, count: Int = 5) -> [ArenaOpponent] {
        var rng = SeededRandom(seed: poolSeed(points: record.points, day: day))
        return (0..<count).map { index in
            // Spread the pool around the player's rating: mostly close matches,
            // with one reach and one easy win so there is always something to do.
            let offsetBucket = [-180, -90, 0, 90, 220][min(index, 4)]
            let jitter = rng.int(in: -40...40)
            let points = max(800, record.points + offsetBucket + jitter)
            return opponent(points: points, index: index, day: day, rng: &rng)
        }
    }

    private static func opponent(
        points: Int,
        index: Int,
        day: Int,
        rng: inout SeededRandom
    ) -> ArenaOpponent {
        let tier = ArenaTier.tier(forPoints: points)
        let team = generateTeam(points: points, rng: &rng)
        let power = team.reduce(0) { $0 + $1.power }
        let name = rng.pickMutating(opponentNames) ?? "Rival"

        return ArenaOpponent(
            id: "arena_\(day)_\(index)_\(points)",
            name: name,
            points: points,
            tier: tier,
            team: team,
            power: power,
            pointsForWin: pointsForWin(playerPoints: points, opponentPoints: points),
            pointsForLoss: pointsForLoss(playerPoints: points, opponentPoints: points)
        )
    }

    /// Generates a plausible defence team at a rating.
    ///
    /// The roster is small right now, so opponents are built from the summonable
    /// pool plus campaign monsters as mercenaries. When the roster grows this
    /// becomes a straight sample of the summon pool.
    private static func generateTeam(points: Int, rng: inout SeededRandom) -> [ResolvedUnit] {
        // Rating maps to gear and level. A 1000-point opponent is roughly a
        // fresh account; a 3800-point one is fully built.
        let normalized = min(1.0, max(0.0, Double(points - 900) / 3_000))
        let level = Int(15 + normalized * 45)
        let stars = min(6, 3 + Int(normalized * 3))
        let relicGrade = min(6, 3 + Int(normalized * 3))
        let relicLevel = Int(normalized * 15)

        var candidates = ["zeus", "cerberus", "menoetius", "bronze_automaton", "naiad", "harpy"]
        candidates = rng.shuffled(candidates)

        return candidates.prefix(teamSize).compactMap { blueprintID in
            guard let blueprint = UnitDatabase.blueprint(blueprintID) else { return nil }
            let unitStars = min(6, max(blueprint.naturalStars, stars))
            var unit = Unit(
                blueprint: blueprint,
                level: min(ProgressionService.maxLevel(stars: unitStars), level),
                stars: unitStars,
                awakened: normalized > 0.4 && blueprint.awakening != nil
            )
            unit.skillLevels = blueprint.skills.map { _ in max(1, Int(normalized * 5)) }

            let primary: RelicSet = blueprint.role == .attacker ? .fury : .bulwark
            let secondary: RelicSet = blueprint.role == .attacker ? .ruin : .aegis
            let relics = RelicService.generateLoadout(
                grade: relicGrade,
                primarySet: primary,
                secondarySet: secondary,
                upgradeLevel: relicLevel,
                rng: &rng
            )
            return ProgressionService.resolve(unit, blueprint: blueprint, equipped: relics)
        }
    }

    // MARK: - Scoring

    /// Elo-flavoured swing: beating someone above you is worth more.
    static func pointsForWin(playerPoints: Int, opponentPoints: Int) -> Int {
        let delta = Double(opponentPoints - playerPoints)
        return max(6, min(45, Int(18 + delta / 20)))
    }

    static func pointsForLoss(playerPoints: Int, opponentPoints: Int) -> Int {
        let delta = Double(playerPoints - opponentPoints)
        return max(4, min(30, Int(12 + delta / 25)))
    }

    static func laurelsForWin(tier: ArenaTier) -> Int { 12 + tier.rawValue * 6 }

    enum ArenaError: Error, LocalizedError {
        case noAttacksLeft
        case teamTooSmall
        case noDefenseTeam

        var errorDescription: String? {
            switch self {
            case .noAttacksLeft: return "No arena attacks left. They refill over time."
            case .teamTooSmall: return "Arena teams need \(ArenaService.teamSize) units."
            case .noDefenseTeam: return "Set a defence team before you attack — you can be attacked back."
            }
        }
    }

    /// Spends an attack and builds the battle.
    static func startAttack(
        against opponent: ArenaOpponent,
        player: inout Player,
        seed: UInt64
    ) throws -> BattleEngine {
        guard player.arena.attacksRemaining > 0 else { throw ArenaError.noAttacksLeft }
        let team = CampaignService.resolveTeam(player.arenaOffenseTeam, player: player)
        guard team.count >= 1 else { throw ArenaError.teamTooSmall }

        player.arena.attacksRemaining -= 1

        return BattleEngine(
            playerTeam: Array(team.prefix(teamSize)),
            opponentTeam: opponent.team,
            mode: .arenaOffense,
            seed: seed
        )
    }

    /// Applies the result of an arena attack.
    @discardableResult
    static func applyResult(
        _ result: BattleResult,
        against opponent: ArenaOpponent,
        player: inout Player
    ) -> (pointsDelta: Int, laurels: Int) {
        let won = result.outcome == .victory
        let delta = won
            ? pointsForWin(playerPoints: player.arena.points, opponentPoints: opponent.points)
            : -pointsForLoss(playerPoints: player.arena.points, opponentPoints: opponent.points)

        let floor = player.arena.tier.threshold
        player.arena.points = max(floor, player.arena.points + delta)
        player.arena.highestPoints = max(player.arena.highestPoints, player.arena.points)

        if won {
            player.arena.wins += 1
            player.arena.defeatedOpponentIDs.append(opponent.id)
            // Opponent ids are day-scoped, so old entries can never match again.
            // Trim rather than let the save grow forever.
            if player.arena.defeatedOpponentIDs.count > 60 {
                player.arena.defeatedOpponentIDs.removeFirst(
                    player.arena.defeatedOpponentIDs.count - 60
                )
            }
        } else {
            player.arena.losses += 1
        }

        let laurels = won ? laurelsForWin(tier: player.arena.tier) : 3
        player.wallet.laurels += laurels
        return (delta, laurels)
    }

    /// Scores the player's own defence team by simulating it against the pool it
    /// will actually face. Shown on the arena screen so a defence is not a guess.
    static func rateDefense(player: Player, samples: Int = 5) -> Double {
        let defense = CampaignService.resolveTeam(player.arenaDefenseTeam, player: player)
        guard !defense.isEmpty else { return 0 }

        var wins = 0
        for index in 0..<samples {
            var rng = SeededRandom(seed: poolSeed(points: player.arena.points, day: index))
            let attackers = generateTeam(points: player.arena.points, rng: &rng)
            // The defence is the *opponent* here: it wins by surviving.
            let result = BattleEngine.simulate(
                playerTeam: attackers,
                opponentTeam: defense,
                seed: UInt64(index &* 104_729 &+ 17)
            )
            if result.outcome != .victory { wins += 1 }
        }
        return Double(wins) / Double(samples)
    }

    /// Refills attacks over real time — one every 30 minutes.
    static func refreshAttacks(_ record: inout ArenaRecord, now: Date = Date()) {
        let elapsed = now.timeIntervalSince(record.lastRefresh)
        guard elapsed > 0 else { return }
        let interval: TimeInterval = 30 * 60
        let restored = Int(elapsed / interval)
        guard restored > 0 else { return }
        record.attacksRemaining = min(record.maxAttacks, record.attacksRemaining + restored)
        record.lastRefresh = record.lastRefresh.addingTimeInterval(Double(restored) * interval)
    }
}
