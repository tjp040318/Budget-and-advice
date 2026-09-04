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
}

/// PvE progression: which stages are open, and what a clear pays.
enum CampaignService {

    /// A stage is available once the previous one in its chapter is cleared, and
    /// a chapter opens once the previous chapter's boss falls.
    static func isUnlocked(_ stage: Stage, player: Player) -> Bool {
        if stage.index == 1 {
            guard let chapterIndex = StageDatabase.chapters.firstIndex(where: { $0.id == stage.chapterID }),
                  chapterIndex > 0 else { return true }
            let previous = StageDatabase.chapters[chapterIndex - 1]
            return (player.campaignProgress[previous.id] ?? 0) >= previous.stages.count
        }
        return (player.campaignProgress[stage.chapterID] ?? 0) >= stage.index - 1
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
        let par = stage.isBoss ? 30 : 18
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
        seed: UInt64
    ) throws -> BattleEngine {
        guard isUnlocked(stage, player: player) else { throw CampaignError.locked }
        guard player.wallet.energy >= stage.energyCost else {
            throw CampaignError.notEnoughEnergy(needed: stage.energyCost)
        }

        let team = resolveTeam(player.campaignTeam, player: player)
        guard !team.isEmpty else { throw CampaignError.emptyTeam }

        player.wallet.energy -= stage.energyCost

        return BattleEngine(
            playerTeam: team,
            opponentTeam: StageDatabase.buildEnemies(for: stage),
            mode: .campaign,
            seed: seed
        )
    }

    static func resolveTeam(_ preset: TeamPreset, player: Player) -> [ResolvedUnit] {
        preset.unitIDs.compactMap { id in
            player.unit(id).flatMap { ProgressionService.resolve($0, relics: player.relics) }
        }
    }

    /// Grants rewards for a finished stage and writes progress back.
    @discardableResult
    static func applyRewards(
        stage: Stage,
        result: BattleResult,
        player: inout Player,
        rng: inout SeededRandom
    ) -> StageOutcome {
        let stars = starRating(result: result, stage: stage)
        guard result.outcome == .victory else {
            return StageOutcome(
                result: result, stars: 0, drachma: 0, playerExperience: 0,
                unitExperience: 0, relicsEarned: [], essencesEarned: [:],
                scrollsEarned: [:], divinityEarned: 0, isFirstClear: false,
                leveledUnits: [:]
            )
        }

        let isFirstClear = !isCleared(stage, player: player)
        let rewards = stage.rewards

        // Three stars pays a 25% bonus. Nothing else scales with performance,
        // so a clean clear is worth chasing without making a sloppy one useless.
        let bonus = stars == 3 ? 1.25 : 1.0
        let drachma = Int(Double(rewards.drachma) * bonus)
        let unitXP = Int(Double(rewards.unitExperience) * bonus)

        player.wallet.drachma += drachma
        player.experience += rewards.playerExperience
        while player.experience >= player.experienceToNextLevel {
            player.experience -= player.experienceToNextLevel
            player.level += 1
            player.wallet.maxEnergy += 2
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
        if rewards.relicChance > 0, rng.chance(rewards.relicChance) {
            let relic = RelicService.generate(grade: rewards.relicGrade, rng: &rng)
            relics.append(relic)
            player.relics.append(relic)
        }

        var essences: [String: Int] = [:]
        for (id, chance) in rewards.essenceChances where rng.chance(chance) {
            let amount = rng.int(in: 1...2)
            essences[id, default: 0] += amount
            player.essences[id, default: 0] += amount
        }

        var scrolls: [String: Int] = [:]
        for (id, chance) in rewards.scrollChances where rng.chance(chance) {
            scrolls[id, default: 0] += 1
            player.wallet.scrolls[id, default: 0] += 1
        }

        var divinity = 0
        if isFirstClear {
            divinity = rewards.firstClearDivinity
            player.wallet.divinity += divinity
            player.campaignProgress[stage.chapterID] = max(
                player.campaignProgress[stage.chapterID] ?? 0, stage.index
            )
        }

        return StageOutcome(
            result: result, stars: stars, drachma: drachma,
            playerExperience: rewards.playerExperience, unitExperience: unitXP,
            relicsEarned: relics, essencesEarned: essences, scrollsEarned: scrolls,
            divinityEarned: divinity, isFirstClear: isFirstClear,
            leveledUnits: leveled
        )
    }

    /// Refunds the energy when a run is abandoned before the first turn resolves.
    static func refund(stage: Stage, player: inout Player) {
        player.wallet.energy = min(player.wallet.maxEnergy, player.wallet.energy + stage.energyCost)
    }
}
