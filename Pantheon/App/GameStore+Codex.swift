import Foundation

// MARK: - The Codex's claims (2026-09-23; Docs/CODEX.md)
//
// Every claim goes through `attempt` or `update`, the store's two mutation
// paths, so the save is marked dirty and a refused claim puts its reason in
// `lastError` as every other claim in the game does (`claimMission`,
// `claimTribute`). The rules — what pays, what pays once — are
// `CodexService`'s; this file only carries them into the store.
extension GameStore {

    /// Pages and pantheon tiers waiting to be claimed, for a badge: the gold
    /// mark on the Collection strip's Codex control.
    var codexRewardsWaiting: Int { CodexService.readyCount(player: player) }

    /// Claims one page of the Codex. Nil, with the reason shown, when the
    /// page is not recorded or was already taken.
    @discardableResult
    func claimCodexEntry(_ entryID: String) -> [ShopService.Grant]? {
        var rng = makeRandom()
        return attempt { player in
            try CodexService.claim(entryID, player: &player, rng: &rng)
        }
    }

    /// Claims a pantheon's completion tier. Nil, with the reason shown,
    /// before the tier is reached or once it has been taken.
    @discardableResult
    func claimCodexTier(_ tier: CodexTier, of pantheon: Pantheon) -> [ShopService.Grant]? {
        var rng = makeRandom()
        return attempt { player in
            try CodexService.claimTier(tier, of: pantheon, player: &player, rng: &rng)
        }
    }

    /// Claims everything waiting, in one pantheon or the whole book, and
    /// returns what it paid merged for one receipt.
    @discardableResult
    func claimAllCodexRewards(in pantheon: Pantheon? = nil) -> [ShopService.Grant] {
        var rng = makeRandom()
        var paid: [ShopService.Grant] = []
        update { player in
            paid = CodexService.claimAll(of: pantheon, player: &player, rng: &rng)
        }
        return paid
    }
}
