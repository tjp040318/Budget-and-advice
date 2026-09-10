import Foundation

/// The daily missions, the feats and the login gift: the reasons to open the
/// game every day, and how scrolls and divinity reach a wallet that never
/// takes real money. Every count lives in the save; a day is the player's own
/// calendar day; nothing here reads a server.
enum QuestService {

    // MARK: - What the game tells us

    /// Something the player did that a mission or a feat might count.
    enum Event {
        case stageCleared(Stage)
        case hallFloorCleared(Stage)
        case arenaBattle(won: Bool)
        case summoned(count: Int, bestStars: Int)
        case relicUpgraded(level: Int)
        case unitPoweredUp
        case unitEvolved(stars: Int)
        case unitAwakened
        /// A hexagram completed. Deliberately its own case rather than folded
        /// into `unitEvolved`: a fusion consumes four raised units and up to
        /// 120,000 drachma for a god no banner carries, which is the single
        /// largest thing a player does outside a summon, and counting it as an
        /// evolution would have credited the wrong feat and told the wrong
        /// story back to him.
        case unitFused
        case dailyOfferingClaimed
        case energySpent(Int)
    }

    // MARK: - Missions

    /// A daily mission: a counter to fill and what filling it pays.
    struct Mission: Identifiable, Sendable {
        var id: String
        var title: String
        var goal: Int
        var reward: ShopService.Grant
        var icon: String
    }

    static let missions: [Mission] = [
        Mission(id: "clear_stages", title: "Clear three campaign stages", goal: 3, reward: .scrolls(.unknown, 2), icon: "map.fill"),
        Mission(id: "clear_hall", title: "Clear a floor of a Hall of Essence", goal: 1, reward: .scrolls(.mystical, 1), icon: "flame.fill"),
        Mission(id: "arena_win", title: "Win an arena battle", goal: 1, reward: .divinity(30), icon: "trophy.fill"),
        Mission(id: "summon", title: "Summon once", goal: 1, reward: .divinity(10), icon: "sparkles"),
        Mission(id: "power_up", title: "Power up a unit", goal: 1, reward: .drachma(5_000), icon: "arrow.up.circle.fill"),
        Mission(id: "upgrade_relic", title: "Upgrade a relic", goal: 1, reward: .energy(10), icon: "shield.lefthalf.filled"),
        Mission(id: "daily_offering", title: "Claim the bazaar's daily offering", goal: 1, reward: .divinity(10), icon: "gift.fill"),
        Mission(id: "spend_energy", title: "Spend thirty energy", goal: 30, reward: .scrolls(.unknown, 1), icon: "bolt.fill"),
    ]

    /// Paid once every mission of the day is claimed.
    static let allMissionsBonus = ShopService.Grant.bundle([.scrolls(.pantheonic, 1), .divinity(30)])
    static let allMissionsID = "all_missions"

    // MARK: - Feats

    /// A one-time achievement, judged from the save's lifetime counters and
    /// the account itself.
    struct Feat: Identifiable, Sendable {
        var id: String
        var title: String
        var reward: ShopService.Grant
        var icon: String
        /// The counter the feat watches, and the value it wants; nil when
        /// `isComplete` reads the account directly.
        var counter: String?
        var goal: Int
    }

    static let feats: [Feat] = [
        Feat(id: "first_five_star", title: "Summon a 5★", reward: .divinity(100), icon: "star.fill", counter: "five_stars", goal: 1),
        Feat(id: "summons_10", title: "Ten summons", reward: .scrolls(.mystical, 2), icon: "sparkles", counter: "summons", goal: 10),
        Feat(id: "summons_50", title: "Fifty summons", reward: .scrolls(.pantheonic, 1), icon: "sparkles", counter: "summons", goal: 50),
        Feat(id: "summons_200", title: "Two hundred summons", reward: .scrolls(.divine, 1), icon: "sparkles", counter: "summons", goal: 200),
        Feat(id: "arena_wins_10", title: "Ten arena wins", reward: .divinity(50), icon: "trophy.fill", counter: "arena_wins", goal: 10),
        Feat(id: "arena_wins_50", title: "Fifty arena wins", reward: .divinity(150), icon: "trophy.fill", counter: "arena_wins", goal: 50),
        Feat(id: "hall_floors_10", title: "Ten hall floors", reward: .scrolls(.mystical, 3), icon: "flame.fill", counter: "hall_floors", goal: 10),
        Feat(id: "hall_floor_5", title: "Clear a hall's fifth floor", reward: .scrolls(.lightDark, 1), icon: "flame.fill", counter: "hall_floor_5", goal: 1),
        Feat(id: "relic_15", title: "Upgrade a relic to +15", reward: .divinity(100), icon: "shield.lefthalf.filled", counter: "relic_15", goal: 1),
        Feat(id: "awaken", title: "Awaken a unit", reward: .divinity(50), icon: "sun.max.fill", counter: "awakenings", goal: 1),
        // The hexagram had no feat at all, so the largest thing a player
        // does outside a summon paid nothing and was never mentioned back
        // to him. Two: the first one, and a habit.
        Feat(id: "fuse", title: "Complete a fusion", reward: .divinity(120), icon: "hexagon.fill", counter: "fusions", goal: 1),
        Feat(id: "fuse_3", title: "Three fusions", reward: .scrolls(.divine, 1), icon: "hexagon.fill", counter: "fusions", goal: 3),
        Feat(id: "evolve_6", title: "Evolve a unit to 6★", reward: .scrolls(.divine, 1), icon: "star.circle.fill", counter: "six_stars", goal: 1),
        Feat(id: "units_20", title: "Own twenty units", reward: .scrolls(.mystical, 3), icon: "person.3.fill", counter: nil, goal: 20),
        Feat(id: "units_40", title: "Own forty units", reward: .scrolls(.divine, 1), icon: "person.3.fill", counter: nil, goal: 40),
        Feat(id: "level_10", title: "Reach summoner level 10", reward: .divinity(100), icon: "crown.fill", counter: nil, goal: 10),
        Feat(id: "level_20", title: "Reach summoner level 20", reward: .divinity(200), icon: "crown.fill", counter: nil, goal: 20),
        Feat(id: "level_30", title: "Reach summoner level 30", reward: .divinity(300), icon: "crown.fill", counter: nil, goal: 30),
    ] + StageDatabase.chapters.map { chapter in
        Feat(id: "clear_\(chapter.id)", title: "Clear \(chapter.name)", reward: .bundle([.divinity(100), .scrolls(.pantheonic, 1)]),
             icon: "checkmark.seal.fill", counter: nil, goal: chapter.stages.count)
    }

    static func feat(_ id: String) -> Feat? { feats.first(where: { $0.id == id }) }

    // MARK: - The login gift

    /// Seven days of gifts; the eighth day starts over. A missed day starts
    /// the count again, the way the genre keeps people coming back.
    static let loginGifts: [ShopService.Grant] = [
        .scrolls(.mystical, 1), .drachma(5_000), .energy(30), .scrolls(.unknown, 3),
        .divinity(50), .scrolls(.mystical, 2), .scrolls(.pantheonic, 1),
    ]

    // MARK: - Days

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Rolls the daily counters over when the calendar day has changed, and
    /// advances or resets the login streak. Safe to call any time; called on
    /// launch, on foreground and before every record and claim.
    static func refreshDay(player: inout Player, now: Date = Date()) {
        let today = dayKey(now)
        var quests = player.quests ?? QuestProgress()
        if quests.dayKey != today {
            quests = QuestProgress(dayKey: today)
        }
        player.quests = quests

        var streak = player.loginStreak ?? LoginStreak()
        if streak.lastDayKey != today {
            let yesterday = dayKey(now.addingTimeInterval(-86_400))
            if streak.lastDayKey == yesterday, streak.day > 0 {
                streak.day = streak.day % loginGifts.count + 1
            } else {
                streak.day = 1
            }
            streak.lastDayKey = today
        }
        player.loginStreak = streak
    }

    // MARK: - Recording

    /// Counts an event toward today's missions and the lifetime feats.
    static func record(_ event: Event, player: inout Player, now: Date = Date()) {
        refreshDay(player: &player, now: now)
        var quests = player.quests ?? QuestProgress()
        var lifetime = player.lifetimeCounters ?? [:]

        func bump(_ key: String, _ amount: Int = 1) { quests.counters[key, default: 0] += amount }
        func life(_ key: String, _ amount: Int = 1) { lifetime[key, default: 0] += amount }

        switch event {
        case .stageCleared:
            bump("clear_stages")
            life("stage_clears")
        case .hallFloorCleared(let stage):
            bump("clear_hall")
            life("hall_floors")
            if stage.index >= DungeonDatabase.floorCount { life("hall_floor_5") }
        case .arenaBattle(let won):
            if won { bump("arena_win"); life("arena_wins") }
        case .summoned(let count, let bestStars):
            bump("summon", count)
            life("summons", count)
            if bestStars >= 5 { life("five_stars") }
        case .relicUpgraded(let level):
            bump("upgrade_relic")
            life("relic_upgrades")
            if level >= 15 { life("relic_15") }
        case .unitPoweredUp:
            bump("power_up")
            life("power_ups")
        case .unitEvolved(let stars):
            life("evolutions")
            if stars >= 6 { life("six_stars") }
        case .unitAwakened:
            life("awakenings")
        case .unitFused:
            life("fusions")
        case .dailyOfferingClaimed:
            bump("daily_offering")
        case .energySpent(let amount):
            bump("spend_energy", amount)
            life("energy_spent", amount)
        }

        player.quests = quests
        player.lifetimeCounters = lifetime
    }

    // MARK: - Reading

    static func progress(of mission: Mission, player: Player) -> Int {
        min(mission.goal, player.quests?.counters[mission.id] ?? 0)
    }

    static func isMissionComplete(_ mission: Mission, player: Player) -> Bool {
        progress(of: mission, player: player) >= mission.goal
    }

    static func isMissionClaimed(_ id: String, player: Player) -> Bool {
        player.quests?.claimed.contains(id) ?? false
    }

    static func allMissionsClaimable(_ player: Player) -> Bool {
        missions.allSatisfy { isMissionClaimed($0.id, player: player) } && !isMissionClaimed(allMissionsID, player: player)
    }

    /// How far a feat is, in its own units.
    static func progress(of feat: Feat, player: Player) -> Int {
        if let counter = feat.counter {
            return min(feat.goal, player.lifetimeCounters?[counter] ?? 0)
        }
        if feat.id.hasPrefix("units_") { return min(feat.goal, player.units.count) }
        if feat.id.hasPrefix("level_") { return min(feat.goal, player.level) }
        if feat.id.hasPrefix("clear_") {
            let chapterID = String(feat.id.dropFirst("clear_".count))
            return min(feat.goal, player.campaignProgress[chapterID] ?? 0)
        }
        return 0
    }

    static func isFeatComplete(_ feat: Feat, player: Player) -> Bool {
        progress(of: feat, player: player) >= feat.goal
    }

    static func isFeatClaimed(_ id: String, player: Player) -> Bool {
        player.featsClaimed?.contains(id) ?? false
    }

    static func isLoginGiftClaimed(player: Player, now: Date = Date()) -> Bool {
        (player.loginStreak?.claimedDayKey ?? "") == dayKey(now)
    }

    /// Everything that can be claimed right now, for the badge on the island.
    static func claimableCount(player: Player, now: Date = Date()) -> Int {
        var count = missions.filter { isMissionComplete($0, player: player) && !isMissionClaimed($0.id, player: player) }.count
        if allMissionsClaimable(player) { count += 1 }
        count += feats.filter { isFeatComplete($0, player: player) && !isFeatClaimed($0.id, player: player) }.count
        if !isLoginGiftClaimed(player: player, now: now) { count += 1 }
        return count
    }

    // MARK: - Claiming

    enum QuestError: Error, LocalizedError {
        case notComplete
        case alreadyClaimed

        var errorDescription: String? {
            switch self {
            case .notComplete: return "That is not finished yet."
            case .alreadyClaimed: return "Already claimed."
            }
        }
    }

    @discardableResult
    static func claimMission(_ id: String, player: inout Player, rng: inout SeededRandom, now: Date = Date()) throws -> [ShopService.Grant] {
        refreshDay(player: &player, now: now)
        if id == allMissionsID {
            guard !isMissionClaimed(id, player: player) else { throw QuestError.alreadyClaimed }
            guard allMissionsClaimable(player) else { throw QuestError.notComplete }
            player.quests?.claimed.insert(id)
            return ShopService.grant(allMissionsBonus, to: &player, rng: &rng)
        }
        guard let mission = missions.first(where: { $0.id == id }) else { throw QuestError.notComplete }
        guard !isMissionClaimed(id, player: player) else { throw QuestError.alreadyClaimed }
        guard isMissionComplete(mission, player: player) else { throw QuestError.notComplete }
        player.quests?.claimed.insert(id)
        return ShopService.grant(mission.reward, to: &player, rng: &rng)
    }

    @discardableResult
    static func claimFeat(_ id: String, player: inout Player, rng: inout SeededRandom) throws -> [ShopService.Grant] {
        guard let feat = feat(id) else { throw QuestError.notComplete }
        guard !isFeatClaimed(id, player: player) else { throw QuestError.alreadyClaimed }
        guard isFeatComplete(feat, player: player) else { throw QuestError.notComplete }
        var claimed = player.featsClaimed ?? []
        claimed.insert(id)
        player.featsClaimed = claimed
        return ShopService.grant(feat.reward, to: &player, rng: &rng)
    }

    @discardableResult
    static func claimLoginGift(player: inout Player, rng: inout SeededRandom, now: Date = Date()) throws -> [ShopService.Grant] {
        refreshDay(player: &player, now: now)
        guard !isLoginGiftClaimed(player: player, now: now) else { throw QuestError.alreadyClaimed }
        var streak = player.loginStreak ?? LoginStreak(lastDayKey: dayKey(now), day: 1)
        streak.claimedDayKey = dayKey(now)
        player.loginStreak = streak
        let gift = loginGifts[max(0, min(loginGifts.count - 1, streak.day - 1))]
        return ShopService.grant(gift, to: &player, rng: &rng)
    }
}

/// Today's mission counters and what has been claimed. Rebuilt on a new day.
struct QuestProgress: Codable, Equatable, Sendable {
    var dayKey: String = ""
    var counters: [String: Int] = [:]
    var claimed: Set<String> = []
}

/// Where the login streak stands.
struct LoginStreak: Codable, Equatable, Sendable {
    var lastDayKey: String = ""
    /// 1...7 within the streak; 0 before the first day is seen.
    var day: Int = 0
    var claimedDayKey: String = ""
}
