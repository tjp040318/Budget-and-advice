import Foundation

// MARK: - The Draft Arena's hold on the save (2026-09-23; Docs/DRAFT.md)
//
// Every write goes through `update`, the store's one mutation path, so the
// record is saved and mirrored like everything else. The rules live in
// `DraftService`; this file only reads the save into them and writes them
// back.

extension GameStore {

    /// The Draft Arena's standing, or a fresh one before the first bout.
    var draftRecord: DraftRecord { player.draft ?? DraftRecord() }

    /// Whether the player owns five different monsters, which a draft needs.
    var canDraft: Bool { DraftService.canDraft(player) }

    /// Brings the record up to now: the day's paid bouts refill at midnight,
    /// a finished week banks its chest, an Olympiad's turn pulls the rating
    /// halfway back. The board calls it as it opens; a settle runs it itself.
    func refreshDraft(now: Date = Date()) {
        var record = draftRecord
        guard DraftService.rollOver(&record, now: now) else { return }
        update { player in
            player.draft = record
        }
    }

    /// The fight a finished draft makes: both fours, leaders first, in the
    /// arena's mode — leader skills that work in the arena and both lineups'
    /// resonance, exactly an arena attack's rules. Nil until the draft is
    /// ready. Spends nothing: the draft costs no attack and no energy.
    func startDraftBout(_ session: DraftSession) -> (engine: BattleEngine, bout: DraftBout)? {
        guard let bout = DraftService.bout(from: session) else { return nil }
        let engine = BattleEngine(
            playerTeam: bout.playerTeam,
            opponentTeam: bout.rivalTeam,
            mode: .arenaOffense,
            seed: nextSeed()
        )
        return (engine, bout)
    }

    /// Settles a fought bout: the rating, the record, a paid bout's laurels,
    /// the week's count — and the daily "win an arena battle" mission and the
    /// arena feats, since a draft bout is a fight in the arena.
    @discardableResult
    func finishDraftBout(_ bout: DraftBout, result: BattleResult) -> DraftSettlement {
        var settled: DraftSettlement?
        update { player in
            settled = DraftService.applyResult(result, bout: bout, player: &player)
            QuestService.record(.arenaBattle(won: result.outcome == .victory), player: &player)
        }
        let record = draftRecord
        return settled ?? DraftSettlement(
            outcome: result.outcome,
            ratingBefore: record.rating,
            ratingAfter: record.rating,
            laurels: 0,
            tierBefore: record.tier,
            tierAfter: record.tier,
            paidBoutsLeft: max(0, DraftService.paidBoutsPerDay - record.paidToday)
        )
    }

    /// Pays the chest a finished week left, once; nil when none waits.
    @discardableResult
    func claimDraftChest() -> DraftChest? {
        var paid: DraftChest?
        update { player in
            paid = DraftService.claimChest(player: &player)
        }
        return paid
    }
}
