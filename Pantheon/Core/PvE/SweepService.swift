import Foundation

/// Clearing a stage you have already mastered, without watching it.
///
/// **Why the game needs this.** The auto-repeat that exists (1/5/10/20 runs)
/// still PLAYS every battle: twenty runs of a three-wave dungeon level is
/// twenty minutes of watching a fight whose outcome was settled the first
/// time. That was the genre's answer in 2014. The genre's answer in 2026 is
/// Blue Archive's instant sweep and Summoners War's own **Scout Battle**
/// (the TOMORROW update, November 2025), which farms Cairos and the Rift for
/// up to eight hours while the app is shut. The relic grind is the reason
/// people leave this kind of game; a sweep is the single change that makes
/// it survivable.
///
/// **The gate is three stars, not the clear.** A clear says you beat it once,
/// possibly by a hair with one unit standing. Three stars says everyone
/// lived and it was inside the turn par — which is the same statement as
/// "the outcome of this fight is no longer in doubt". It also gives the star
/// rating, which until now was a decoration on the map, something to earn.
///
/// **And the team is checked as well.** Three stars is a record of the past;
/// a player who mastered Duat 1-5 at level 20 and has since fed his whole
/// team to the Hall of Ka should not go on sweeping it. So the campaign team
/// that would have fought must still meet the stage's recommended power. The
/// genre does not do this — Blue Archive and Genshin both pay out on the
/// clear alone — and it costs nothing to be right about.
enum SweepService {

    /// The most runs one sweep does, matching the auto-repeat's own ×20 chip
    /// so the two controls read as the same promise.
    static let maximumRuns = 20

    /// Three stars on this stage AT THIS TIER. `Stage.at(_:)` suffixes the id
    /// (`duat_1_5@hard`), and `stageStars` is keyed by that id, so mastering
    /// a chapter on Normal grants nothing on Hard — which is the point.
    static func isMastered(_ stage: Stage, player: Player) -> Bool {
        (player.stageStars?[stage.id] ?? 0) >= 3
    }

    /// The team that would have fought, and what it is worth.
    static func teamPower(_ player: Player) -> Int {
        CampaignService.resolveTeam(player.campaignTeam, player: player)
            .reduce(0) { $0 + $1.power }
    }

    /// The current campaign team still meets the stage's recommendation.
    static func isPowered(_ stage: Stage, player: Player) -> Bool {
        let power = teamPower(player)
        return power > 0 && power >= stage.recommendedPower
    }

    static func canSweep(_ stage: Stage, player: Player) -> Bool {
        isMastered(stage, player: player) && isPowered(stage, player: player)
    }

    /// Why the button is dark, in one sentence. Nil when it is not.
    ///
    /// Written as a sentence rather than a rule because the player is reading
    /// it at the moment he wanted something to happen: "Three-star this stage
    /// first" tells him what to do, where "requirements not met" tells him
    /// nothing.
    static func refusal(_ stage: Stage, player: Player) -> String? {
        if !isMastered(stage, player: player) {
            let pips = player.stageStars?[stage.id] ?? 0
            return "Three-star this stage first — you have \(pips) of 3."
        }
        if !isPowered(stage, player: player) {
            return "Your team is \(teamPower(player)) power against this stage's \(stage.recommendedPower)."
        }
        if player.wallet.energy < stage.energyCost {
            return "A sweep costs the same energy as a fight: \(stage.energyCost) a run."
        }
        return nil
    }

    /// How many runs the energy in the wallet pays for, capped at the maximum.
    static func affordableRuns(_ stage: Stage, player: Player) -> Int {
        guard stage.energyCost > 0 else { return maximumRuns }
        return min(maximumRuns, player.wallet.energy / stage.energyCost)
    }

    /// What a swept run is paid as: the clean three-star clear the player has
    /// already proved he can get. Everyone lives, and the turns are the par
    /// exactly, so `CampaignService.starRating` reads three — the rating is
    /// not asserted here, it is EARNED by a result that satisfies the same
    /// rule a real fight would.
    static func masteredResult(for stage: Stage, seed: UInt64) -> BattleResult {
        let waves = 1 + stage.laterWaves.count
        let par = (stage.isBoss ? 30 : 18) * waves * 4 / 5
        return BattleResult(
            outcome: .victory,
            turnsTaken: par,
            survivorFraction: 1.0,
            totalDamageDealt: 0,
            totalDamageTaken: 0,
            seed: seed
        )
    }

    /// Several runs' spoils as one. Every field of `StageOutcome` is summed
    /// the way a player would add them up, so the sweep's receipt goes through
    /// the same `BattleSummary.loot` the victory screen uses and a swept haul
    /// and a fought one cannot be drawn differently.
    ///
    /// The `result` and `stars` of the first run stand for the batch: a sweep
    /// is N identical three-star clears by construction.
    static func total(_ outcomes: [StageOutcome], stage: Stage) -> StageOutcome {
        var summed = StageOutcome(
            result: masteredResult(for: stage, seed: 0),
            stars: 3,
            drachma: 0,
            playerExperience: 0,
            unitExperience: 0,
            relicsEarned: [],
            essencesEarned: [:],
            scrollsEarned: [:],
            divinityEarned: 0,
            isFirstClear: false,
            leveledUnits: [:],
            stonesEarned: [:]
        )
        for outcome in outcomes {
            summed.drachma += outcome.drachma
            summed.playerExperience += outcome.playerExperience
            summed.unitExperience += outcome.unitExperience
            summed.relicsEarned += outcome.relicsEarned
            summed.divinityEarned += outcome.divinityEarned
            for (id, count) in outcome.essencesEarned { summed.essencesEarned[id, default: 0] += count }
            for (id, count) in outcome.scrollsEarned { summed.scrollsEarned[id, default: 0] += count }
            for (id, count) in outcome.stonesEarned { summed.stonesEarned[id, default: 0] += count }
            for (id, levels) in outcome.leveledUnits { summed.leveledUnits[id, default: 0] += levels }
        }
        return summed
    }
}

/// What a sweep gave back, for the sheet that shows it.
///
/// `runs` and `requested` are kept apart on purpose: a sweep that was asked
/// for twenty and could afford eleven is not a failure, but the player is
/// owed the sentence that says so rather than a haul that quietly came up
/// short.
struct SweepReceipt: Identifiable, Sendable {
    var id = UUID()
    var stage: Stage
    var runs: Int
    var requested: Int
    var energySpent: Int
    var outcome: StageOutcome

    /// True when the energy ran out before the runs did.
    var cameUpShort: Bool { runs < requested }
}
