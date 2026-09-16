import Foundation

/// **Athena's Counsel** — the checklist, and the spine of the first month.
///
/// The genre's own version is Summoners War's *Summoner's Way*: a tiered list
/// of beginner tasks, each paying, the tier gating the next, and a real prize
/// at the end of each. It answers the one question a collector RPG is worst at
/// answering on day two — *what am I supposed to do now?* — and it answers it
/// in ORDER, which is what separates it from an achievement list.
///
/// This is deliberately not `QuestService.feats`. Feats are an unordered
/// lifetime tally: forty entries in any order, sorted by what happens to be
/// claimable. The Counsel is a ROAD. Three tiers of ten, each tier hidden
/// until the one before it is finished, each step naming a single next action
/// in the order a good player would take it.
///
/// **Every step is measured off the save**, never off a flag written by the
/// screen that did the thing — the rule `FirstHourStep` was built on and the
/// reason a save made before any of this existed lands in the right place
/// instead of starting a veteran at the beginning. `measure` takes a `Player`
/// and returns a number; nothing else in the game has to know the Counsel
/// exists.
enum CounselService {

    // MARK: - The three tiers

    enum Tier: String, CaseIterable, Identifiable, Sendable {
        case initiate, adept, hierophant

        var id: String { rawValue }

        var title: String {
            switch self {
            case .initiate: return "Initiate"
            case .adept: return "Adept"
            case .hierophant: return "Hierophant"
            }
        }

        /// Athena's line for the tier, on its header.
        var blurb: String {
            switch self {
            case .initiate: return "The first evening. Wake a god, arm it, and take the Duat."
            case .adept: return "The first week. Grades, sets, and the doors under the island."
            case .hierophant: return "The long game. A maxed relic, a six-star god, and Hell."
            }
        }

        /// What finishing the whole tier pays, over and above its steps.
        var prize: ShopService.Grant {
            switch self {
            case .initiate:
                return .scrolls(.divine, 1)
            case .adept:
                return .bundle([.scrolls(.lightDark, 1), .relic(grade: 6), .divinity(250)])
            case .hierophant:
                return .bundle([.scrolls(.divine, 1), .stones("gem_legend", 1), .divinity(500)])
            }
        }

        /// The id the prize is claimed under, kept apart from the steps'.
        var prizeID: String { "counsel_prize_\(rawValue)" }

        var next: Tier? {
            switch self {
            case .initiate: return .adept
            case .adept: return .hierophant
            case .hierophant: return nil
            }
        }
    }

    // MARK: - A step

    struct Step: Identifiable, Sendable {
        var id: String
        var tier: Tier
        /// The instruction, in the imperative. A step whose title does not say
        /// what to press has failed at its one job.
        var title: String
        var icon: String
        var goal: Int
        var reward: ShopService.Grant
        /// How far along, read off the save.
        var measure: @Sendable (Player) -> Int
    }

    // MARK: - The road

    static let steps: [Step] = initiateSteps + adeptSteps + hierophantSteps

    /// The first evening.
    private static let initiateSteps: [Step] = [
        Step(id: "counsel_first_stage", tier: .initiate,
             title: "Clear the first stage of the Duat", icon: "flag.fill", goal: 1,
             reward: .scrolls(.mystical, 1),
             measure: { player in min(1, player.campaignProgress["duat_1"] ?? 0) }),
        Step(id: "counsel_first_summon", tier: .initiate,
             title: "Open a scroll at the Summoning Circle", icon: "sparkles", goal: 1,
             reward: .drachma(10_000),
             measure: { player in min(1, player.lifetimeCounters?["summons"] ?? 0) }),
        Step(id: "counsel_equip", tier: .initiate,
             title: "Put a relic on a god", icon: "shield.lefthalf.filled", goal: 1,
             reward: .scrolls(.unknown, 3),
             measure: { player in min(1, player.units.filter { !$0.equippedRelics.isEmpty }.count) }),
        Step(id: "counsel_power_up", tier: .initiate,
             title: "Raise a god in the Hall of Ka", icon: "arrow.up.circle.fill", goal: 1,
             reward: .drachma(15_000),
             measure: { player in min(1, player.lifetimeCounters?["power_ups"] ?? 0) }),
        Step(id: "counsel_five_stages", tier: .initiate,
             title: "Clear five campaign stages", icon: "map.fill", goal: 5,
             reward: .energy(30),
             measure: { player in min(5, player.lifetimeCounters?["stage_clears"] ?? 0) }),
        Step(id: "counsel_relic_3", tier: .initiate,
             title: "Feed a relic to +3", icon: "hexagon.fill", goal: 1,
             reward: .drachma(25_000),
             measure: { player in min(1, player.relics.filter { $0.level >= 3 }.count) }),
        Step(id: "counsel_offering", tier: .initiate,
             title: "Take the bazaar's daily offering", icon: "gift.fill", goal: 1,
             reward: .divinity(30),
             measure: { player in player.lastDailyPackClaim == nil ? 0 : 1 }),
        Step(id: "counsel_level_5", tier: .initiate,
             title: "Reach summoner level 5", icon: "crown.fill", goal: 5,
             reward: .scrolls(.mystical, 2),
             measure: { player in min(5, player.level) }),
        Step(id: "counsel_arena", tier: .initiate,
             title: "Win a fight in the Arena of Souls", icon: "trophy.fill", goal: 1,
             reward: .divinity(50),
             measure: { player in min(1, player.lifetimeCounters?["arena_wins"] ?? 0) }),
        Step(id: "counsel_duat_1", tier: .initiate,
             title: "Take the whole of Duat 1", icon: "checkmark.seal.fill", goal: 1,
             reward: .bundle([.scrolls(.pantheonic, 1), .divinity(100)]),
             measure: { player in
                 let stages = StageDatabase.chapter("duat_1")?.stages.count ?? 5
                 return (player.campaignProgress["duat_1"] ?? 0) >= stages ? 1 : 0
             }),
    ]

    /// The first week.
    private static let adeptSteps: [Step] = [
        Step(id: "counsel_level_12", tier: .adept,
             title: "Reach summoner level 12", icon: "crown.fill", goal: 12,
             reward: .divinity(80),
             measure: { player in min(12, player.level) }),
        Step(id: "counsel_evolve_4", tier: .adept,
             title: "Evolve a god to four stars", icon: "star.circle.fill", goal: 1,
             reward: .drachma(40_000),
             measure: { player in min(1, player.units.filter { $0.stars >= 4 }.count) }),
        Step(id: "counsel_hall", tier: .adept,
             title: "Clear a floor of a Hall of Essence", icon: "flame.fill", goal: 1,
             reward: .essences("essence_magic_mid", 5),
             measure: { player in min(1, player.lifetimeCounters?["hall_floors"] ?? 0) }),
        Step(id: "counsel_labyrinth", tier: .adept,
             title: "Take the Labyrinth's first floor", icon: "square.grid.3x3.fill", goal: 1,
             reward: .scrolls(.mystical, 2),
             measure: { player in min(1, player.relics.filter { $0.grade >= 4 }.count) }),
        Step(id: "counsel_dressed", tier: .adept,
             title: "Fill all six relic slots on one god", icon: "circle.hexagongrid.fill", goal: 6,
             reward: .divinity(100),
             measure: { player in player.units.map(\.equippedRelics.count).max() ?? 0 }),
        Step(id: "counsel_relic_9", tier: .adept,
             title: "Feed a relic to +9", icon: "hexagon.fill", goal: 1,
             reward: .drachma(50_000),
             measure: { player in min(1, player.relics.filter { $0.level >= 9 }.count) }),
        Step(id: "counsel_units_20", tier: .adept,
             title: "Own twenty gods", icon: "person.3.fill", goal: 20,
             reward: .scrolls(.pantheonic, 1),
             measure: { player in min(20, player.units.count) }),
        Step(id: "counsel_hard", tier: .adept,
             title: "Clear five stages on Hard", icon: "bolt.shield.fill", goal: 5,
             reward: .divinity(120),
             measure: { player in
                 min(5, player.campaignProgress.filter { $0.key.hasSuffix("@hard") }.values.reduce(0, +))
             }),
        Step(id: "counsel_tribute", tier: .adept,
             title: "Claim a tribute chest on a chapter's road", icon: "shippingbox.fill", goal: 1,
             reward: .scrolls(.unknown, 5),
             measure: { player in min(1, player.tributesClaimed?.count ?? 0) }),
        Step(id: "counsel_awaken", tier: .adept,
             title: "Awaken a god", icon: "sun.max.fill", goal: 1,
             reward: .bundle([.divinity(100), .essences("essence_magic_high", 2)]),
             measure: { player in min(1, player.lifetimeCounters?["awakenings"] ?? 0) }),
    ]

    /// The long game.
    private static let hierophantSteps: [Step] = [
        Step(id: "counsel_level_25", tier: .hierophant,
             title: "Reach summoner level 25", icon: "crown.fill", goal: 25,
             reward: .divinity(200),
             measure: { player in min(25, player.level) }),
        Step(id: "counsel_evolve_6", tier: .hierophant,
             title: "Evolve a god to six stars", icon: "star.circle.fill", goal: 1,
             reward: .scrolls(.pantheonic, 1),
             measure: { player in min(1, player.units.filter { $0.stars >= 6 }.count) }),
        Step(id: "counsel_relic_15", tier: .hierophant,
             title: "Feed a relic all the way to +15", icon: "hexagon.fill", goal: 1,
             reward: .divinity(200),
             measure: { player in min(1, player.relics.filter { $0.level >= 15 }.count) }),
        Step(id: "counsel_legend", tier: .hierophant,
             title: "Own a six-star Legend relic", icon: "diamond.fill", goal: 1,
             reward: .stones("whetstone_hero", 1),
             measure: { player in
                 min(1, player.relics.filter { $0.grade >= 6 && $0.resolvedQuality == .legend }.count)
             }),
        Step(id: "counsel_labyrinth_7", tier: .hierophant,
             title: "Reach the Labyrinth's seventh floor", icon: "square.grid.3x3.fill", goal: 1,
             reward: .divinity(150),
             measure: { player in min(1, player.relics.filter { $0.grade >= 6 }.count) }),
        Step(id: "counsel_tower_30", tier: .hierophant,
             title: "Climb to the Tower's thirtieth floor", icon: "building.columns.fill", goal: 30,
             reward: .divinity(250),
             measure: { player in min(30, player.tower?.highestFloorCleared ?? 0) }),
        Step(id: "counsel_fusion", tier: .hierophant,
             title: "Complete a fusion", icon: "hexagon.fill", goal: 1,
             reward: .divinity(150),
             measure: { player in min(1, player.lifetimeCounters?["fusions"] ?? 0) }),
        Step(id: "counsel_hell", tier: .hierophant,
             title: "Clear five stages on Hell", icon: "flame.circle.fill", goal: 5,
             reward: .scrolls(.pantheonic, 1),
             measure: { player in
                 min(5, player.campaignProgress.filter { $0.key.hasSuffix("@hell") }.values.reduce(0, +))
             }),
        Step(id: "counsel_summons_100", tier: .hierophant,
             title: "Open a hundred scrolls", icon: "sparkles", goal: 100,
             reward: .divinity(300),
             measure: { player in min(100, player.lifetimeCounters?["summons"] ?? 0) }),
        Step(id: "counsel_collection_40", tier: .hierophant,
             title: "Record forty families in the codex", icon: "book.fill", goal: 40,
             reward: .bundle([.scrolls(.pantheonic, 1), .divinity(200)]),
             measure: { player in min(40, player.codex.count) }),
    ]

    static func steps(in tier: Tier) -> [Step] { steps.filter { $0.tier == tier } }

    static func step(_ id: String) -> Step? { steps.first(where: { $0.id == id }) }

    // MARK: - Reading

    static func progress(of step: Step, player: Player) -> Int {
        min(step.goal, max(0, step.measure(player)))
    }

    static func isComplete(_ step: Step, player: Player) -> Bool {
        progress(of: step, player: player) >= step.goal
    }

    static func isClaimed(_ id: String, player: Player) -> Bool {
        player.counselClaimed?.contains(id) ?? false
    }

    /// A tier opens when every step of the one before it is DONE — not
    /// claimed. Gating on the claim would strand a player who cleared the tier
    /// and forgot to collect it, which is a wall the road is there to remove.
    static func isUnlocked(_ tier: Tier, player: Player) -> Bool {
        switch tier {
        case .initiate: return true
        case .adept: return steps(in: .initiate).allSatisfy { isComplete($0, player: player) }
        case .hierophant: return steps(in: .adept).allSatisfy { isComplete($0, player: player) }
        }
    }

    /// The tier's own prize needs every step of it CLAIMED: it is the receipt
    /// for the whole road, not another step.
    static func isPrizeReady(_ tier: Tier, player: Player) -> Bool {
        steps(in: tier).allSatisfy { isClaimed($0.id, player: player) }
            && !isClaimed(tier.prizeID, player: player)
    }

    /// The tier the player is on: the first one whose prize is unclaimed.
    static func currentTier(for player: Player) -> Tier {
        Tier.allCases.first { !isClaimed($0.prizeID, player: player) } ?? .hierophant
    }

    /// Everything on the road that can be collected right now, for the badge.
    static func claimableCount(player: Player) -> Int {
        var count = steps.filter {
            isUnlocked($0.tier, player: player)
                && isComplete($0, player: player)
                && !isClaimed($0.id, player: player)
        }.count
        count += Tier.allCases.filter { isPrizeReady($0, player: player) }.count
        return count
    }

    // MARK: - Claiming

    enum CounselError: Error, LocalizedError {
        case locked
        case notComplete
        case alreadyClaimed

        var errorDescription: String? {
            switch self {
            case .locked: return "Athena has not set that one yet."
            case .notComplete: return "That is not finished yet."
            case .alreadyClaimed: return "Already claimed."
            }
        }
    }

    /// Claims a step, or a tier's prize when given its `prizeID`.
    @discardableResult
    static func claim(_ id: String, player: inout Player, rng: inout SeededRandom) throws -> [ShopService.Grant] {
        guard !isClaimed(id, player: player) else { throw CounselError.alreadyClaimed }

        if let tier = Tier.allCases.first(where: { $0.prizeID == id }) {
            guard isPrizeReady(tier, player: player) else { throw CounselError.notComplete }
            var claimed = player.counselClaimed ?? []
            claimed.insert(id)
            player.counselClaimed = claimed
            return ShopService.grant(tier.prize, to: &player, rng: &rng)
        }

        guard let step = step(id) else { throw CounselError.notComplete }
        guard isUnlocked(step.tier, player: player) else { throw CounselError.locked }
        guard isComplete(step, player: player) else { throw CounselError.notComplete }
        var claimed = player.counselClaimed ?? []
        claimed.insert(id)
        player.counselClaimed = claimed
        return ShopService.grant(step.reward, to: &player, rng: &rng)
    }
}
