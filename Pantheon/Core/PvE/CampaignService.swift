import Foundation

/// What the player earned from a stage clear.
struct StageOutcome: Sendable {
    var result: BattleResult
    var stars: Int
    var drachma: Int
    var playerExperience: Int
    var unitExperience: Int
    var relicsEarned: [Relic]
    var essencesEarned: [String: Int]
    var scrollsEarned: [String: Int]
    var divinityEarned: Int
    var isFirstClear: Bool
    var leveledUnits: [UUID: Int]
    /// Whetstones and gems by `RelicStone.id`. Defaulted, so the places
    /// that build an outcome with nothing of the kind need not say so.
    var stonesEarned: [String: Int] = [:]
    /// A raid's aether by id (`Aether`), paid by the grade — on a kill and
    /// on a loss alike, which is why it is not folded into the victory-only
    /// fields above.
    var aetherEarned: [String: Int] = [:]
    /// The raid's grade, F to SSS; nil for every other stage.
    var raidGrade: RaidGrade? = nil
    /// Boon caches (`BoonCache`) the clear left: a Titan at S and better, the
    /// Labyrinth's last level, a Tower milestone. Defaulted like the stones.
    var boonCachesEarned: [BoonCache] = []
    /// The calendar's multipliers this clear took (`EventCalendar`), so a
    /// receipt can say why a number is twice its usual. Flat by default.
    var eventBoosts: EventBoosts = .flat
    /// The demigod levels this clear raised (Docs/FEEL.md W1.6): the battle's
    /// level-up beat reads it, and the island's header ring. Zero on a loss
    /// and on a clear that levelled nobody; defaulted, like everything added
    /// since the first fields, so the places that build an outcome by hand
    /// need not say so.
    var playerLevelsGained: Int = 0
    /// The demigod's level after the clear. Zero where the outcome does not
    /// say — a loss, or a total summed over several runs (`SweepService`).
    var newPlayerLevel: Int = 0
}

/// PvE progression: which stages are open, and what a clear pays.
enum CampaignService {

    /// What a demigod level pays on top of the refill: two more energy in the
    /// bar and 25 divinity, the genre's way of paying a level. Named so the
    /// battle's level-up beat prints the numbers the settle paid, never a
    /// copy of them (Docs/FEEL.md W1.6).
    static let maxEnergyPerLevel = 2
    static let divinityPerLevel = 25

    /// A stage is available once the previous one in its chapter is cleared, a
    /// chapter opens once the previous chapter's boss falls, and a harder
    /// tier of a chapter opens once the tier before it is cleared to its
    /// boss: Hard behind Normal, Hell behind Hard.
    static func isUnlocked(_ stage: Stage, player: Player) -> Bool {
        let (baseChapter, tier) = CampaignDifficulty.split(stage.chapterID)
        if stage.index == 1 {
            if let easier = tier.easier {
                guard let chapter = StageDatabase.chapters.first(where: { $0.id == baseChapter }) else { return false }
                return (player.campaignProgress[baseChapter + easier.suffix] ?? 0) >= chapter.stages.count
            }
            guard let chapterIndex = StageDatabase.chapters.firstIndex(where: { $0.id == baseChapter }),
                  chapterIndex > 0 else { return true }
            let previous = StageDatabase.chapters[chapterIndex - 1]
            return (player.campaignProgress[previous.id] ?? 0) >= previous.stages.count
        }
        return (player.campaignProgress[stage.chapterID] ?? 0) >= stage.index - 1
    }

    /// Whether a tier of a chapter can be entered at all.
    static func isOpen(_ tier: CampaignDifficulty, of chapter: Chapter, player: Player) -> Bool {
        guard let first = chapter.at(tier).stages.first else { return false }
        return isUnlocked(first, player: player)
    }

    static func isCleared(_ stage: Stage, player: Player) -> Bool {
        (player.campaignProgress[stage.chapterID] ?? 0) >= stage.index
    }

    static func progress(of chapter: Chapter, player: Player) -> Double {
        let cleared = player.campaignProgress[chapter.id] ?? 0
        return chapter.stages.isEmpty ? 0 : Double(cleared) / Double(chapter.stages.count)
    }

    /// Star rating: one for the clear, one for keeping everyone alive, one for
    /// doing it inside the turn par.
    static func starRating(result: BattleResult, stage: Stage) -> Int {
        guard result.outcome == .victory else { return 0 }
        var stars = 1
        if result.survivorFraction >= 1.0 { stars += 1 }
        // Par turns for the third star: a wave is a fight of its own, so a
        // three-wave stage is allowed three of them (measured medians in
        // `balance.py --campaign`).
        let waves = 1 + stage.laterWaves.count
        let par = (stage.isBoss ? 30 : 18) * waves * 4 / 5
        if result.turnsTaken <= par { stars += 1 }
        return stars
    }

    enum CampaignError: Error, LocalizedError {
        case notEnoughEnergy(needed: Int)
        case locked
        case emptyTeam

        var errorDescription: String? {
            switch self {
            case .notEnoughEnergy(let needed): return "This stage costs \(needed) energy."
            case .locked: return "Clear the previous stage first."
            case .emptyTeam: return "Pick at least one unit for your team."
            }
        }
    }

    /// Spends energy and builds the engine. The caller drives it and then hands
    /// the result back to `applyRewards`.
    static func startBattle(
        stage: Stage,
        player: inout Player,
        seed: UInt64,
        now: Date = Date()
    ) throws -> BattleEngine {
        guard isUnlocked(stage, player: player) else { throw CampaignError.locked }
        // event: half on the campaign's half-energy day, the base otherwise.
        let cost = EventCalendar.energyCost(for: stage, at: now)
        guard player.wallet.energy >= cost else {
            throw CampaignError.notEnoughEnergy(needed: cost)
        }

        let team = resolveTeam(player.campaignTeam, player: player)
        guard !team.isEmpty else { throw CampaignError.emptyTeam }

        player.wallet.energy -= cost

        return BattleEngine(
            playerTeam: team,
            opponentTeam: StageDatabase.buildEnemies(for: stage),
            mode: .campaign,
            seed: seed,
            laterWaves: stage.laterWaves.map { StageDatabase.buildEnemies(spawns: $0) },
            unloseable: isTutorialFight(stage, player: player)
        )
    }

    /// The one fight in the game that cannot be lost: the FIRST stage of the
    /// Duat, at Normal, on a save that has never cleared it. Every condition
    /// matters — a tier suffix (`duat_1_1@hard`) is a different stage, and a
    /// player who has cleared it once is no longer being taught.
    static func isTutorialFight(_ stage: Stage, player: Player) -> Bool {
        stage.id == "duat_1_1" && (player.campaignProgress["duat_1"] ?? 0) < 1
    }

    static func resolveTeam(_ preset: TeamPreset, player: Player) -> [ResolvedUnit] {
        preset.unitIDs.compactMap { id in
            player.unit(id).flatMap { ProgressionService.resolve($0, relics: player.relics, boons: player.boons ?? []) }
        }
    }

    /// Grants rewards for a finished stage and writes progress back.
    ///
    /// `boosts` are the calendar's multipliers (`EventCalendar.boosts`),
    /// resolved by `settle` — this function never reads a clock, so a test
    /// that asserts a payout holds whatever day it runs on.
    @discardableResult
    static func applyRewards(
        stage: Stage,
        result: BattleResult,
        player: inout Player,
        rng: inout SeededRandom,
        boosts: EventBoosts = .flat
    ) -> StageOutcome {
        let stars = starRating(result: result, stage: stage)

        // A raid is graded, kill or not, and the grade pays its aether before
        // anything else is settled: a D that took a third of the serpent's
        // health leaves with the elemental half of an awakening's price, so a
        // summoner who cannot beat it yet is still building toward one. The
        // pure half comes from a kill only (`RaidGradeService.aether`).
        var grade: RaidGrade?
        var aether: [String: Int] = [:]
        if let raid = StageDatabase.raid(containing: stage), let profile = raid.profile {
            let earned = RaidGradeService.grade(result: result, profile: profile)
            grade = earned
            aether = RaidGradeService.pay(earned, raid: raid, player: &player)
        }

        guard result.outcome == .victory else {
            return StageOutcome(
                result: result, stars: 0, drachma: 0, playerExperience: 0,
                unitExperience: 0, relicsEarned: [], essencesEarned: [:],
                scrollsEarned: [:], divinityEarned: 0, isFirstClear: false,
                leveledUnits: [:], stonesEarned: [:],
                aetherEarned: aether, raidGrade: grade
            )
        }

        let isFirstClear = !isCleared(stage, player: player)
        let rewards = stage.rewards

        // Three stars pays a 25% bonus. Nothing else scales with performance,
        // so a clean clear is worth chasing without making a sloppy one useless.
        let bonus = stars == 3 ? 1.25 : 1.0
        // event: Monday's drachma and Tuesday's experience, from the boosts.
        let drachma = Int(Double(rewards.drachma) * bonus * boosts.drachma)
        let unitXP = Int(Double(rewards.unitExperience) * bonus * boosts.experience)
        let playerXP = Int(Double(rewards.playerExperience) * boosts.experience)

        player.wallet.drachma += drachma
        player.experience += playerXP
        var levelsGained = 0
        while player.experience >= player.experienceToNextLevel {
            player.experience -= player.experienceToNextLevel
            player.level += 1
            levelsGained += 1
            player.wallet.maxEnergy += maxEnergyPerLevel
            player.wallet.energy = player.wallet.maxEnergy
        }

        // Everyone who fought gains experience, alive or not.
        var leveled: [UUID: Int] = [:]
        for unitID in player.campaignTeam.unitIDs {
            guard let index = player.units.firstIndex(where: { $0.id == unitID }) else { continue }
            let gained = ProgressionService.grantExperience(unitXP, to: &player.units[index])
            if gained > 0 { leveled[unitID] = gained }
        }

        var relics: [Relic] = []
        // event: the weekend's Labyrinth makes the roll twice — two relics on
        // a level that drops one every run. One roll draws exactly as before.
        for _ in 0..<max(1, boosts.relicRolls) {
            guard rewards.relicChance > 0, rng.chance(rewards.relicChance) else { continue }
            // A dungeon drops its own sets; anywhere else, any set.
            var set: RelicSet?
            if let sets = rewards.relicSets, !sets.isEmpty { set = rng.pickMutating(sets) }
            // The top of a raid's ladder lifts the quality floor over the
            // raid's own: Hero from S, Legend at SSS.
            let floor = max(
                rewards.qualityFloor ?? .normal,
                grade.flatMap(RaidGradeService.qualityFloor(for:)) ?? .normal
            )
            // The dream: the hardest content drops the relic AWAKENED now
            // and then — the stage's own chance, or a raid's by its grade.
            let awakenedChance = max(
                rewards.awakenedChance ?? 0,
                grade.map(RaidGradeService.awakenedChance(for:)) ?? 0
            )
            let awakened = awakenedChance > 0 && rng.chance(awakenedChance)
            let relic = RelicService.generate(
                grade: rewards.relicGrade, set: set,
                qualityFloor: floor, awakened: awakened, rng: &rng
            )
            relics.append(relic)
            player.relics.append(relic)
        }

        // Whetstones and gems, sorted so the seed's rolls fall in one order.
        var stones: [String: Int] = [:]
        for (id, chance) in (rewards.stoneChances ?? [:]).sorted(by: { $0.key < $1.key }) where rng.chance(chance) {
            stones[id, default: 0] += 1
            RelicService.addStones(id, 1, player: &player)
        }

        var essences: [String: Int] = [:]
        for (id, chance) in rewards.essenceChances where rng.chance(chance) {
            // event: the weekend's Hall pays twice the amount, not the chance.
            let amount = rng.int(in: 1...2) * max(1, boosts.essence)
            essences[id, default: 0] += amount
            player.essences[id, default: 0] += amount
        }

        var scrolls: [String: Int] = [:]
        for (id, chance) in rewards.scrollChances where rng.chance(chance) {
            scrolls[id, default: 0] += 1
            player.wallet.scrolls[id, default: 0] += 1
        }

        // A summoner level is worth 25 divinity, the way the genre pays
        // levelling, on top of the first clear's own.
        var divinity = levelsGained * divinityPerLevel
        player.wallet.divinity += divinity
        if isFirstClear {
            divinity += rewards.firstClearDivinity
            player.wallet.divinity += rewards.firstClearDivinity
            player.campaignProgress[stage.chapterID] = max(
                player.campaignProgress[stage.chapterID] ?? 0, stage.index
            )
        }

        // A boon cache, from the hardest content only: the stage's own chance
        // (the Labyrinth's last level) or a Titan's by its grade, S and
        // better. Rolled last, so nothing above it draws differently.
        var caches: [BoonCache] = []
        var cacheChance = rewards.boonCacheChance ?? 0
        var cacheGrade = rewards.boonCacheGrade ?? RaidGradeService.titanBoonGrade
        if let grade, RaidGradeService.boonCacheChance(for: grade) > 0 {
            cacheChance = max(cacheChance, RaidGradeService.boonCacheChance(for: grade))
            cacheGrade = RaidGradeService.titanBoonGrade
        }
        if cacheChance > 0, rng.chance(cacheChance) {
            let cache = BoonCache(grade: cacheGrade, seed: rng.next(), source: grade != nil ? "Titan" : "Labyrinth")
            BoonService.addCache(cache, player: &player)
            caches.append(cache)
        }

        return StageOutcome(
            result: result, stars: stars, drachma: drachma,
            playerExperience: playerXP, unitExperience: unitXP,
            relicsEarned: relics, essencesEarned: essences, scrollsEarned: scrolls,
            divinityEarned: divinity, isFirstClear: isFirstClear,
            leveledUnits: leveled,
            stonesEarned: stones,
            aetherEarned: aether, raidGrade: grade,
            boonCachesEarned: caches,
            eventBoosts: boosts,
            playerLevelsGained: levelsGained,
            newPlayerLevel: player.level
        )
    }

    /// Everything a finished run does to the save, in one place: the rewards,
    /// the star high-water mark, a tower floor's milestone and the quests it
    /// advances.
    ///
    /// `GameStore.finishCampaignBattle` and `GameStore.sweep` both come
    /// through here, so a swept run and a fought one cannot pay differently —
    /// which was the whole risk of adding a second way to clear a stage.
    @discardableResult
    static func settle(
        stage: Stage,
        result: BattleResult,
        player: inout Player,
        rng: inout SeededRandom,
        now: Date = Date()
    ) -> StageOutcome {
        // event: the calendar's multipliers for this stage today, read ONCE
        // here — the one path a fought and a swept run share — so
        // `applyRewards` stays a pure function of its arguments.
        let boosts = EventCalendar.boosts(for: stage, at: now)
        var outcome = applyRewards(stage: stage, result: result, player: &player, rng: &rng, boosts: boosts)

        // The stars the clear earned, kept as a high-water mark for the map's
        // pips, the realm's judgment (`TributeService`) and the sweep's gate.
        if result.outcome == .victory {
            TributeService.recordStars(stage: stage, stars: outcome.stars, player: &player)
        }
        // A tower floor pays like any other stage. What a stage cannot express
        // is the high-water mark and the milestone, so the tower settles those
        // here, after the floor has been paid, and folds the milestone's
        // grants into the same receipt rather than letting them arrive
        // silently in the wallet.
        if DungeonDatabase.isTowerFloor(stage) {
            TowerService.recordClear(
                stage: stage, result: result, outcome: &outcome,
                player: &player, rng: &rng
            )
        }
        if result.outcome == .victory {
            let event: QuestService.Event = DungeonDatabase.hall(containing: stage) != nil
                ? .hallFloorCleared(stage)
                : .stageCleared(stage)
            QuestService.record(event, player: &player)
        }
        // event: the mission counts what was actually charged.
        QuestService.record(.energySpent(EventCalendar.energyCost(for: stage, at: now)), player: &player)
        // Every run, won or lost, fought or swept: what the anonymous play
        // data reads a stage's difficulty from (`Docs/ANALYTICS.md`).
        QuestService.record(.stageSettled(stage, result, stars: outcome.stars, firstClear: outcome.isFirstClear),
                            player: &player)
        return outcome
    }

    /// Spends one swept run's energy, or refuses, and returns what it charged
    /// so a receipt can add the runs up. The sweep's own gates — three stars
    /// and a team that still meets the stage — are `SweepService.canSweep`,
    /// checked once before the loop; this is only the wallet.
    @discardableResult
    static func spendSweptRun(stage: Stage, player: inout Player, now: Date = Date()) throws -> Int {
        // event: the same half price a fought run pays on the half-energy day.
        let cost = EventCalendar.energyCost(for: stage, at: now)
        guard player.wallet.energy >= cost else {
            throw CampaignError.notEnoughEnergy(needed: cost)
        }
        player.wallet.energy -= cost
        return cost
    }

    /// Refunds the energy when a run is abandoned before the first turn resolves.
    static func refund(stage: Stage, player: inout Player, now: Date = Date()) {
        // event: gives back what the day charged, not the base.
        let cost = EventCalendar.energyCost(for: stage, at: now)
        player.wallet.energy = min(player.wallet.maxEnergy, player.wallet.energy + cost)
    }
}

// MARK: - Tributes

/// Where on a chapter's road a tribute chest stands, and what earns it. The
/// genre pays a campaign as it is walked — first clears, area chests, a
/// three-star track — and this is that in the realm's own terms: the road's
/// tribute, the gate's, and the realm's judgment.
enum TributeMilestone: String, CaseIterable, Identifiable, Sendable {
    /// The third stage cleared: the realm's first tribute, a scroll of its
    /// own pantheon.
    case third
    /// The boss fallen: the realm's essence and a relic of the chapter's set.
    case boss
    /// Every stage of the chapter at three stars: the realm's judgment, its
    /// finest relic.
    case flawless

    var id: String { rawValue }

    var title: String {
        switch self {
        case .third: return "Tribute of the Road"
        case .boss: return "Tribute of the Gate"
        case .flawless: return "Judgment of the Realm"
        }
    }
}

/// One tribute chest: what it pays. Built from the chapter at its tier and
/// never stored; only the claim is (`Player.tributesClaimed`).
struct Tribute: Identifiable, Equatable, Sendable {
    let chapterID: String
    let milestone: TributeMilestone
    /// Divinity, scrolls, essences, stones.
    let grants: [ShopService.Grant]
    /// A guaranteed relic of the chapter's own sets, when the tribute pays
    /// one: its grade and quality.
    let relicGrade: Int?
    let relicQuality: RelicQuality?

    var id: String { "\(chapterID)#\(milestone.rawValue)" }
}

enum TributeService {
    /// What a milestone pays at a tier. Mirrored in `tools/balance.py` as
    /// `TRIBUTES`. A Pantheon scroll is 100 divinity in the bazaar, so the
    /// road's tribute on Normal is worth a summon and a third; the
    /// judgment on Hell, a Legend 6★ of the set and two summons' worth.
    struct Payout: Equatable, Sendable {
        var divinity: Int
        var pantheonScrolls: Int
        var mysticalScrolls: Int
        var essences: Int
        var stone: String?
        var relicGrade: Int?
        var relicQuality: RelicQuality?
        /// A boon cache of this grade in the chest: the Judgment on Hell.
        var boonCacheGrade: Int? = nil
    }

    static func payout(_ milestone: TributeMilestone, tier: CampaignDifficulty) -> Payout {
        switch (tier, milestone) {
        case (.normal, .third):
            return Payout(divinity: 30, pantheonScrolls: 1, mysticalScrolls: 0, essences: 0, stone: nil, relicGrade: nil, relicQuality: nil)
        case (.normal, .boss):
            return Payout(divinity: 60, pantheonScrolls: 0, mysticalScrolls: 0, essences: 3, stone: nil, relicGrade: 4, relicQuality: .rare)
        case (.normal, .flawless):
            return Payout(divinity: 120, pantheonScrolls: 0, mysticalScrolls: 2, essences: 0, stone: nil, relicGrade: 5, relicQuality: .hero)
        case (.hard, .third):
            return Payout(divinity: 50, pantheonScrolls: 1, mysticalScrolls: 0, essences: 2, stone: nil, relicGrade: nil, relicQuality: nil)
        case (.hard, .boss):
            return Payout(divinity: 100, pantheonScrolls: 0, mysticalScrolls: 0, essences: 4, stone: nil, relicGrade: 5, relicQuality: .hero)
        case (.hard, .flawless):
            return Payout(divinity: 180, pantheonScrolls: 0, mysticalScrolls: 2, essences: 0, stone: "whetstone_rare", relicGrade: 6, relicQuality: .hero)
        case (.hell, .third):
            return Payout(divinity: 80, pantheonScrolls: 2, mysticalScrolls: 0, essences: 3, stone: nil, relicGrade: nil, relicQuality: nil)
        case (.hell, .boss):
            return Payout(divinity: 150, pantheonScrolls: 0, mysticalScrolls: 0, essences: 5, stone: "gem_rare", relicGrade: 6, relicQuality: .hero)
        case (.hell, .flawless):
            return Payout(divinity: 250, pantheonScrolls: 0, mysticalScrolls: 3, essences: 0, stone: "whetstone_hero", relicGrade: 6, relicQuality: .legend, boonCacheGrade: 6)
        }
    }

    /// The three tributes of a chapter at the tier its id carries.
    static func tributes(for chapter: Chapter) -> [Tribute] {
        let tier = chapter.difficulty
        let essence = chapterEssence(chapter)
        return TributeMilestone.allCases.map { milestone in
            let pay = payout(milestone, tier: tier)
            var grants: [ShopService.Grant] = [.divinity(pay.divinity)]
            if pay.pantheonScrolls > 0 { grants.append(.scrolls(.pantheonic, pay.pantheonScrolls)) }
            if pay.mysticalScrolls > 0 { grants.append(.scrolls(.mystical, pay.mysticalScrolls)) }
            if pay.essences > 0, let essence { grants.append(.essences(essence, pay.essences)) }
            if let stone = pay.stone { grants.append(.stones(stone, 1)) }
            if let cacheGrade = pay.boonCacheGrade { grants.append(.boonCache(grade: cacheGrade)) }
            return Tribute(
                chapterID: chapter.id, milestone: milestone, grants: grants,
                relicGrade: pay.relicGrade, relicQuality: pay.relicQuality
            )
        }
    }

    /// The realm's essence, read off the chapter's boss stage: what the
    /// chapter already drops, so a tribute pays more of the same.
    static func chapterEssence(_ chapter: Chapter) -> String? {
        chapter.stages.last?.rewards.essenceChances.keys.sorted().first
    }

    /// The stage the milestone stands at on the road: the third, the boss,
    /// or nil for the judgment, which stands beyond the boss.
    static func stageIndex(for milestone: TributeMilestone, in chapter: Chapter) -> Int? {
        switch milestone {
        case .third: return min(3, chapter.stages.count)
        case .boss: return chapter.stages.count
        case .flawless: return nil
        }
    }

    static func isEarned(_ tribute: Tribute, chapter: Chapter, player: Player) -> Bool {
        let cleared = player.campaignProgress[chapter.id] ?? 0
        switch tribute.milestone {
        case .third: return cleared >= min(3, chapter.stages.count)
        case .boss: return cleared >= chapter.stages.count
        case .flawless: return chapter.stages.allSatisfy { (player.stageStars?[$0.id] ?? 0) >= 3 }
        }
    }

    static func isClaimed(_ tribute: Tribute, player: Player) -> Bool {
        player.tributesClaimed?.contains(tribute.id) ?? false
    }

    /// Earned and unclaimed on a chapter: the map's reason to come back.
    static func unclaimedCount(for chapter: Chapter, player: Player) -> Int {
        tributes(for: chapter).filter { isEarned($0, chapter: chapter, player: player) && !isClaimed($0, player: player) }.count
    }

    /// What earns it, in words, for the card.
    static func requirement(_ tribute: Tribute, chapter: Chapter) -> String {
        switch tribute.milestone {
        case .third:
            let stage = chapter.stages[min(2, chapter.stages.count - 1)]
            return "Clear \(stage.name)"
        case .boss:
            return "Bring down the boss of \(chapter.name)"
        case .flawless:
            return "Three stars on every stage of \(chapter.name): nobody falls, and within the turns"
        }
    }

    /// The pips a clear earned, kept as a high-water mark.
    static func recordStars(stage: Stage, stars: Int, player: inout Player) {
        guard stars > 0 else { return }
        var marks = player.stageStars ?? [:]
        marks[stage.id] = max(marks[stage.id] ?? 0, stars)
        player.stageStars = marks
    }

    /// What a claim paid, for the card to show.
    struct Receipt: Equatable, Sendable {
        let grants: [ShopService.Grant]
        let relic: Relic?
    }

    /// Pays a tribute once. Nil when it is not earned or was claimed.
    static func claim(
        _ tribute: Tribute, chapter: Chapter, player: inout Player, rng: inout SeededRandom
    ) -> Receipt? {
        guard isEarned(tribute, chapter: chapter, player: player), !isClaimed(tribute, player: player) else { return nil }
        var claimed = player.tributesClaimed ?? []
        claimed.append(tribute.id)
        player.tributesClaimed = claimed
        var granted: [ShopService.Grant] = []
        for grant in tribute.grants {
            granted += ShopService.grant(grant, to: &player, rng: &rng)
        }
        var relic: Relic?
        if let grade = tribute.relicGrade {
            let pool = chapter.relicSets.isEmpty ? RelicSet.allCases : chapter.relicSets
            let set = rng.pickMutating(pool)
            let piece = RelicService.generate(grade: grade, set: set, quality: tribute.relicQuality, rng: &rng)
            player.relics.append(piece)
            relic = piece
        }
        return Receipt(grants: granted, relic: relic)
    }
}
