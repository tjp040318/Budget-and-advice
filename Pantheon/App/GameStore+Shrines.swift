import Foundation

// MARK: - The Hidden Shrines' hold on the save (2026-09-23; Docs/SHRINES.md)
//
// Every write goes through `update` or `attempt`, the store's two mutation
// paths, so the shrines and the pieces are saved and mirrored like everything
// else. The rules live in `ShrineService`; this file only reads the save into
// them and writes them back.
//
// The ONE line this feature adds to `GameStore.swift` is the call to
// `noteShrines(after:result:)` in `finishCampaignBattle`, after the run has
// been settled: every fought run — one fight, or each run of an auto-repeat
// session — passes through it. `GameStore.sweep` settles its runs in its own
// loop and does not; the line it would take is in Docs/SHRINES.md.

extension GameStore {

    /// THE HOOK. A Labyrinth or Hall win may find a hidden shrine; a win in a
    /// shrine pays its pieces. Anything else — a defeat, a campaign stage, a
    /// raid, a tower floor — returns before a stream is drawn or the save is
    /// touched.
    func noteShrines(after stage: Stage, result: BattleResult) {
        guard result.outcome == .victory,
              ShrineService.isShrineStage(stage) || ShrineService.isSource(stage) else { return }
        var rng = makeRandom()
        let now = Date()
        update { player in
            _ = ShrineService.noteClear(stage: stage, result: result, player: &player, rng: &rng, now: now)
        }
    }

    /// The shrines open now, soonest to close first.
    var openShrines: [HiddenShrine] { ShrineService.openShrines(player: player, at: Date()) }

    /// The pieces held, ready ones first (`ShrineService.stocks`).
    var shrineStocks: [ShrineStock] { ShrineService.stocks(player: player) }

    /// Spends one run's energy in an open shrine and builds its engine,
    /// through `startCampaignBattle` — so the energy, the team and the
    /// battle are exactly a Hall floor's, and the win comes back through
    /// `finishCampaignBattle`, which pays the pieces. Nil, with the reason
    /// shown, when the hour is out, the energy is short or the team is
    /// empty.
    func startShrineBattle(_ shrine: HiddenShrine) -> (stage: Stage, engine: BattleEngine)? {
        guard shrine.isOpen(at: Date()) else {
            lastError = ShrineService.ShrineError.closed.localizedDescription
            return nil
        }
        guard let stage = ShrineService.stage(for: shrine) else {
            lastError = ShrineService.ShrineError.unknownForm.localizedDescription
            return nil
        }
        guard let engine = startCampaignBattle(stage: stage) else { return nil }
        return (stage: stage, engine: engine)
    }

    /// Summons a form from its pieces. Returns the reveal so the room can
    /// play it the way a scroll's is played, and counts as a summon for the
    /// day's missions and the feats, as a mileage exchange does.
    func summonFromPieces(_ blueprintID: String) -> SummonResult? {
        var rng = makeRandom()
        let result = attempt { player in
            try ShrineService.summon(blueprintID, player: &player, rng: &rng)
        }
        if let result {
            update { player in
                QuestService.record(.summoned(count: 1, bestStars: result.stars), player: &player)
            }
        }
        return result
    }

    #if DEBUG
    /// The tour's Shrines step: one shrine open — Anubis of the Tides, found
    /// on the Vault's B7 seventeen minutes ago — and three stocks in the three
    /// states a stock can be in: a 3★ ready to summon (the Wind Shabti's 20),
    /// the shrine's own 4★ part-way (26 of 40) and a 5★ begun (the Wind
    /// Sekhmet's 45 of 100). Idempotent: a second launch finds the shrine
    /// still open and sets the same stocks.
    func seedTourShrines(now: Date = Date()) {
        update { player in
            let open = ShrineService.openShrines(player: player, at: now)
            if !open.contains(where: { $0.blueprintID == "anubis_tide" }) {
                let opened = now.addingTimeInterval(-17 * 60)
                let shrine = HiddenShrine(
                    blueprintID: "anubis_tide",
                    foundOn: "lab_colossus_7",
                    openedAt: opened,
                    expiresAt: opened.addingTimeInterval(ShrineService.window)
                )
                player.shrines = open + [shrine]
            }
            var stock = player.shrinePieces ?? [:]
            stock["shabti_gale"] = 20
            stock["anubis_tide"] = 26
            stock["sekhmet_gale"] = 45
            player.shrinePieces = stock
        }
    }
    #endif
}
