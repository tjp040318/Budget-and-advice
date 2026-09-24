import Foundation
import Combine

/// The single source of truth for the running game.
///
/// Views read from it, services mutate through it, and every mutation marks the
/// save dirty. Nothing else in the app is allowed to hold a `Player` — passing
/// copies around is how save files start disagreeing with what is on screen.
@MainActor
final class GameStore: ObservableObject {

    @Published private(set) var player: Player
    @Published var lastError: String?
    @Published private(set) var isSaving = false
    /// True while a modal CARD stands over a tab screen (the stage popup, the
    /// sweep receipt): `GameTabBar` dims under it and takes no tap, so a door
    /// cannot switch screens under an open card (run 216). Set only through
    /// `View.dimsTabBar(_:)`; never saved.
    @Published var tabBarDimmed = false
    /// A demigod level-up the island has not shown yet (Docs/FEEL.md W1.6):
    /// on the next visit the header's level ring bursts once and its number
    /// rolls from `from` to `to`. Set by every settle that raised the level
    /// (a fought clear, a sweep), merged across several, and taken by the
    /// island (`takeLevelCelebration`). Never saved: a level-up the island
    /// has not shown by the next launch is simply not replayed there.
    @Published private(set) var pendingLevelCelebration: LevelCelebration?
    /// The last campaign clear the chapter map has not played yet
    /// (Docs/FEEL.md W2.5): the medallion to turn gold, the stars to stamp,
    /// the road it opened. Set where a stage settles — a fought run and a
    /// swept one alike (`noteClear`) — merged across an auto-repeat's runs
    /// of one stage, and let go by the map once it has played it
    /// (`finishClearBeat`), so a repeat never plays it again. Never saved:
    /// a clear the map has not shown by the next launch is simply not.
    @Published private(set) var lastClear: StageClear?
    /// The next chapter's city, left by a road conquered on Normal for the
    /// world road to light once (`takeCityIgnition`). Never saved.
    @Published private(set) var pendingCityIgnition: String?
    /// The clear whose tier seal the map's ribbon has broken: `TierChips`
    /// holds the tier a clear opened shut until then, and its lock falls.
    @Published private(set) var unsealedClear: Int?
    private var clearSerial = 0

    /// The account this store plays as. Its save goes under
    /// `account.storageKey` and nowhere else, so a store retired at sign-out
    /// cannot write the old player into the next account's file
    /// (`Docs/PLAN.md`, *Accounts — Sign in with Apple*).
    let account: Account
    /// The iCloud mirror of the save: an Apple account on a build signed for
    /// iCloud, nil otherwise (a guest, CI, an unentitled dev build).
    let cloudSave: CloudSaveSyncing?
    /// What the app does once `signOut()` has saved and retired this store:
    /// drop it and show the sign-in screen. Set by `AppSession`.
    var onSignedOut: (() -> Void)?
    /// Set by `retire()`: no save, no timer, no cloud upload from here on.
    private(set) var retired = false

    /// Rolling seed. Every operation that needs randomness takes a fresh stream
    /// from here so two summons in the same second cannot share a result.
    private var seedStream: SeededRandom
    private var saveTask: Task<Void, Never>?
    private var energyTimer: AnyCancellable?

    // MARK: - Lifecycle

    init(save: SaveGame, account: Account, cloudSave: CloudSaveSyncing? = nil) {
        // A save written before units left their teams on removal can hold
        // ids of units long gone (`Player.dropMissingUnitsFromTeams`).
        var loaded = save.player
        loaded.dropMissingUnitsFromTeams()
        self.player = loaded
        self.account = account
        self.cloudSave = cloudSave
        self.seedStream = SeededRandom(seed: save.rngSeed)
        cloudSave?.onChange = { [weak self] in self?.objectWillChange.send() }
        startEnergyTimer()
        refreshTimedResources()
    }

    /// The store for an account: its save from disk, or a new game named for
    /// the player Apple sent. The legacy save and the cloud copy have been
    /// dealt with by the caller (`AppSession.open`) before this runs.
    static func bootstrap(account: Account, cloudSave: CloudSaveSyncing? = nil) -> GameStore {
        let key = account.storageKey
        do {
            if let existing = try SaveStore.load(key: key) {
                return GameStore(save: existing, account: account, cloudSave: cloudSave)
            }
        } catch {
            // A corrupt save has already been quarantined by the store; start
            // fresh rather than refusing to launch.
            let store = GameStore(save: NewGame.create(displayName: account.demigodName), account: account, cloudSave: cloudSave)
            store.lastError = error.localizedDescription
            return store
        }
        // A new account's file exists from its first minute, so a second
        // launch finds it and the cloud copy is made before the first fight.
        let store = GameStore(save: NewGame.create(displayName: account.demigodName), account: account, cloudSave: cloudSave)
        store.markDirty()
        return store
    }

    /// A fresh random stream for one operation.
    func nextSeed() -> UInt64 { seedStream.next() }

    func makeRandom() -> SeededRandom { seedStream.derive() }

    // MARK: - Saving

    /// Coalesces rapid mutations into one write a moment later.
    func markDirty() {
        guard !retired else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    func saveNow() async {
        guard !retired else { return }
        isSaving = true
        defer { isSaving = false }
        var snapshot = player
        snapshot.lastSeenAt = Date()
        player = snapshot
        let started = Perf.begin()
        do {
            let written = try SaveStore.save(SaveGame(player: snapshot, rngSeed: seedStream.next()), key: account.storageKey)
            // The cloud copy follows the file, at most once a minute; the
            // player's `createdAt` is the save's lineage, which is what keeps
            // a fresh game from burying a veteran's copy.
            cloudSave?.schedule(written.data, savedAt: written.savedAt, lineage: snapshot.createdAt)
        } catch {
            lastError = error.localizedDescription
        }
        Perf.end(started, "save (\(snapshot.units.count) units, \(snapshot.relics.count) relics)", over: 30)
    }

    /// The cloud copy brought up to date now — on the way to the background.
    func flushCloud() async {
        await cloudSave?.flush()
    }

    /// Saves, retires this store and tells the app to show the sign-in
    /// screen (`onSignedOut`). The file stays on disk under this account's
    /// key, and the same account signs back in to it.
    func signOut() async {
        await saveNow()
        await flushCloud()
        retire()
        onSignedOut?()
    }

    /// No more writes from this store: the coalesced save and the energy
    /// timer are cancelled and `markDirty` becomes a no-op. Called before an
    /// account swap, so a save pending across the swap cannot land in the
    /// next account's file.
    func retire() {
        retired = true
        saveTask?.cancel()
        saveTask = nil
        energyTimer?.cancel()
        energyTimer = nil
    }

    /// Mutates the player and schedules a save. The only mutation path.
    func update(_ mutation: (inout Player) -> Void) {
        var copy = player
        mutation(&copy)
        player = copy
        markDirty()
    }

    /// Runs an operation that can fail, surfacing the message to the UI.
    @discardableResult
    func attempt<T>(_ operation: (inout Player) throws -> T) -> T? {
        var copy = player
        do {
            let value = try operation(&copy)
            player = copy
            markDirty()
            return value
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Timed resources

    private func startEnergyTimer() {
        energyTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshTimedResources() }
    }

    /// Restores energy and arena attacks based on wall-clock time. Called on
    /// launch, on foreground and every 30 seconds while running.
    func refreshTimedResources(now: Date = Date()) {
        var copy = player
        var changed = false

        // One energy every 5 minutes.
        let interval: TimeInterval = 5 * 60
        let elapsed = now.timeIntervalSince(copy.wallet.lastEnergyTick)
        if elapsed >= interval, copy.wallet.energy < copy.wallet.maxEnergy {
            let restored = Int(elapsed / interval)
            copy.wallet.energy = min(copy.wallet.maxEnergy, copy.wallet.energy + restored)
            copy.wallet.lastEnergyTick = copy.wallet.lastEnergyTick.addingTimeInterval(
                Double(restored) * interval
            )
            changed = true
        } else if copy.wallet.energy >= copy.wallet.maxEnergy {
            copy.wallet.lastEnergyTick = now
        }

        let attacksBefore = copy.arena.attacksRemaining
        ArenaService.refreshAttacks(&copy.arena, now: now)
        if copy.arena.attacksRemaining != attacksBefore { changed = true }

        // Missions roll over at midnight and the login streak advances.
        let questsBefore = copy.quests
        let streakBefore = copy.loginStreak
        QuestService.refreshDay(player: &copy, now: now)
        if copy.quests != questsBefore || copy.loginStreak != streakBefore { changed = true }

        // The Night Market turns over on the hour, on this same clock.
        if NightMarketService.refreshIfNeeded(player: &copy, now: now) { changed = true }

        if changed {
            player = copy
            markDirty()
        }
    }

    // MARK: - Derived views of the roster

    var resolvedUnits: [ResolvedUnit] {
        player.units.compactMap { ProgressionService.resolve($0, relics: player.relics, boons: player.boons ?? []) }
    }

    func resolved(_ unitID: UUID) -> ResolvedUnit? {
        player.unit(unitID).flatMap { ProgressionService.resolve($0, relics: player.relics, boons: player.boons ?? []) }
    }

    func team(_ preset: TeamPreset) -> [ResolvedUnit] {
        CampaignService.resolveTeam(preset, player: player)
    }

    var totalPower: Int {
        resolvedUnits.sorted { $0.power > $1.power }.prefix(5).reduce(0) { $0 + $1.power }
    }

    // MARK: - Summoning

    func summon(banner: Banner, count: Int) -> [SummonResult] {
        var rng = makeRandom()
        let results = attempt { player in
            try SummonService.summon(banner: banner, count: count, player: &player, rng: &rng)
        }
        if let results, !results.isEmpty {
            update { player in
                QuestService.record(.summoned(count: results.count, bestStars: results.map(\.stars).max() ?? 3), player: &player)
            }
        }
        return results ?? []
    }

    /// Spends mileage on a unit the player named. Returns the reveal so the
    /// summon screen can play it the way a rolled unit is played: this IS a
    /// summon, it just had its result chosen in advance.
    func redeemMileage(_ offer: MileageService.Offer, on banner: Banner) -> SummonResult? {
        var rng = makeRandom()
        let result = attempt { player in
            try MileageService.redeem(offer, on: banner, player: &player, rng: &rng)
        }
        if let result {
            update { player in
                QuestService.record(.summoned(count: 1, bestStars: result.stars), player: &player)
            }
        }
        return result
    }

    /// Takes the opening selector. Nil when it is not owed or the pick is not
    /// on the shortlist — both of which mean a stale screen, not an error to
    /// put in front of the player.
    func claimSelector(_ blueprint: UnitBlueprint) -> SummonResult? {
        var result: SummonResult?
        update { player in
            result = SelectorService.claim(blueprint, player: &player)
        }
        return result
    }

    func buyScroll(_ scroll: ScrollType, count: Int = 1) {
        guard let price = scroll.divinityPrice else { return }
        let total = price * count
        guard player.wallet.divinity >= total else {
            lastError = "Not enough divinity — that costs \(total)."
            return
        }
        update { player in
            player.wallet.divinity -= total
            player.wallet.add(scroll, count)
        }
    }

    // MARK: - Teams

    func setTeam(_ preset: TeamPreset, for slot: TeamSlot) {
        update { player in
            switch slot {
            case .campaign: player.campaignTeam = preset
            case .arenaOffense: player.arenaOffenseTeam = preset
            case .arenaDefense: player.arenaDefenseTeam = preset
            }
        }
    }

    enum TeamSlot { case campaign, arenaOffense, arenaDefense }

    func teamPreset(for slot: TeamSlot) -> TeamPreset {
        switch slot {
        case .campaign: return player.campaignTeam
        case .arenaOffense: return player.arenaOffenseTeam
        case .arenaDefense: return player.arenaDefenseTeam
        }
    }

    // MARK: - Units

    func toggleLock(_ unitID: UUID) {
        update { player in
            guard let index = player.units.firstIndex(where: { $0.id == unitID }) else { return }
            player.units[index].isLocked.toggle()
        }
    }

    func levelUp(_ unitID: UUID, feeding fodderIDs: [UUID]) {
        var rng = makeRandom()
        update { player in
            guard let index = player.units.firstIndex(where: { $0.id == unitID }) else { return }
            let fodder = player.units.filter { fodderIDs.contains($0.id) && !$0.isLocked && $0.id != unitID }
            let experience = fodder.reduce(0) { $0 + ProgressionService.feedValue(of: $1) }
            let cost = fodder.count * 500
            guard player.wallet.drachma >= cost else { return }
            player.wallet.drachma -= cost
            ProgressionService.grantExperience(experience, to: &player.units[index])
            // Feeding a duplicate of the same character is a skill-up on top
            // of its experience, the way the genre does it — and once every
            // skill is capped (or for a copy of another element of the same
            // family), the copy raises the family's regalia a level instead
            // (2026-09-17; `RegaliaService.feed` banks it while locked).
            let target = player.units[index]
            let kin = fodder.filter { RegaliaService.isSameFamily($0, as: target) }
            for copy in kin {
                let skilled = copy.blueprintID == target.blueprintID
                    && ProgressionService.applySkillUp(to: &player.units[index], using: &rng) != nil
                if !skilled { RegaliaService.feed(duplicate: copy, into: &player.units[index]) }   // regalia
            }
            QuestService.record(.unitPoweredUp, player: &player)
            // Unequip the fodder before it disappears, so relics come back.
            for id in fodderIDs {
                guard let fodderIndex = player.units.firstIndex(where: { $0.id == id }) else { continue }
                for slot in player.units[fodderIndex].equippedRelics.keys {
                    RelicService.unequip(slot: slot, from: id, player: &player)
                }
            }
            player.units.removeAll { fodderIDs.contains($0.id) && !$0.isLocked }
            player.dropMissingUnitsFromTeams()
        }
    }

    func evolve(_ unitID: UUID, fodderIDs: [UUID]) {
        attempt { player in
            guard let index = player.units.firstIndex(where: { $0.id == unitID }) else { return }
            let fodder = player.units.filter { fodderIDs.contains($0.id) }
            var unit = player.units[index]
            var wallet = player.wallet
            try ProgressionService.evolve(&unit, fodder: fodder, wallet: &wallet)
            player.units[index] = unit
            player.wallet = wallet
            QuestService.record(.unitEvolved(stars: unit.stars), player: &player)
            for id in fodderIDs {
                guard let fodderIndex = player.units.firstIndex(where: { $0.id == id }) else { continue }
                for slot in player.units[fodderIndex].equippedRelics.keys {
                    RelicService.unequip(slot: slot, from: id, player: &player)
                }
            }
            player.units.removeAll { fodderIDs.contains($0.id) }
            player.dropMissingUnitsFromTeams()
        }
    }

    func awaken(_ unitID: UUID) {
        attempt { player in
            guard let index = player.units.firstIndex(where: { $0.id == unitID }) else { return }
            var unit = player.units[index]
            var essences = player.essences
            try ProgressionService.awaken(&unit, essences: &essences)
            player.units[index] = unit
            player.essences = essences
            QuestService.record(.unitAwakened, player: &player)
        }
    }

    // MARK: - Fusion

    /// Runs a fusion hexagram: the four corners and the drachma are spent and
    /// the prize joins the roster. Nil, with the reason shown, when it cannot
    /// run — the board disables the button first, so this is the backstop and
    /// not the check.
    ///
    /// Alone among the mutations here it records no quest event, because there
    /// is no truthful one to record: `.summoned` would fill the summon mission
    /// with something that was not a summon and `.unitEvolved` would fill the
    /// evolution feat. A fusion counts for nothing until `QuestService.Event`
    /// gains a case of its own.
    @discardableResult
    func fuse(_ recipe: FusionService.Recipe) -> ResolvedUnit? {
        let created: Unit? = attempt { player in
            try FusionService.fuse(recipe, player: &player)
        }
        guard let created else { return nil }
        // Recorded as its own event rather than folded into an evolution: a
        // hexagram eats four raised units and up to 120,000 drachma for a god
        // no banner carries, and the feats should say so.
        update { player in
            QuestService.record(.unitFused, player: &player)
        }
        return resolved(created.id)
    }

    // MARK: - Relics

    func equip(relicID: UUID, on unitID: UUID) {
        attempt { player in
            try RelicService.equip(relicID: relicID, on: unitID, player: &player)
        }
    }

    func unequip(slot: Int, from unitID: UUID) {
        update { player in
            RelicService.unequip(slot: slot, from: unitID, player: &player)
        }
    }

    func autoEquip(_ unitID: UUID) {
        update { player in
            RelicService.autoEquip(unitID: unitID, player: &player)
        }
    }

    /// One power-up attempt: the drachma is spent either way. Nil when the
    /// attempt could not be made (max level, not enough drachma), with the
    /// reason shown.
    @discardableResult
    func powerUpRelic(_ relicID: UUID) -> RelicService.PowerUpOutcome? {
        var rng = makeRandom()
        let result: RelicService.PowerUpOutcome?? = attempt { player in
            guard let index = player.relics.firstIndex(where: { $0.id == relicID }) else { return nil }
            var relic = player.relics[index]
            var wallet = player.wallet
            let outcome = try RelicService.upgrade(&relic, wallet: &wallet, rng: &rng)
            player.relics[index] = relic
            player.wallet = wallet
            if outcome.succeeded {
                QuestService.record(.relicUpgraded(level: relic.level), player: &player)
            }
            return outcome
        }
        return result ?? nil
    }

    func upgradeRelic(_ relicID: UUID) {
        powerUpRelic(relicID)
    }

    /// Takes one of the two rolls a successful +3/+6/+9/+12 offered. The
    /// candidates are derived from the relic's own seed, so this cannot be
    /// used to draw a different pair — it only spends the one on the table.
    @discardableResult
    func takeRelicRoll(_ relicID: UUID, candidate: Int) -> RelicService.SubStatChange? {
        var change: RelicService.SubStatChange?
        update { player in
            guard let index = player.relics.firstIndex(where: { $0.id == relicID }) else { return }
            var relic = player.relics[index]
            change = RelicService.takeRoll(&relic, candidate: candidate)
            player.relics[index] = relic
        }
        return change
    }

    /// Sells relics, taking any off their wearers first. Nil, and an error
    /// shown, if one of them is locked.
    @discardableResult
    func sellRelics(_ relicIDs: [UUID]) -> Int? {
        attempt { player in
            try RelicService.sell(relicIDs: relicIDs, player: &player)
        }
    }

    func reappraiseRelic(_ relicID: UUID) {
        var rng = makeRandom()
        attempt { player in
            guard let index = player.relics.firstIndex(where: { $0.id == relicID }) else { return }
            var relic = player.relics[index]
            var wallet = player.wallet
            try RelicService.reappraise(&relic, wallet: &wallet, rng: &rng)
            player.relics[index] = relic
            player.wallet = wallet
        }
    }

    func toggleRelicLock(_ relicID: UUID) {
        update { player in
            guard let index = player.relics.firstIndex(where: { $0.id == relicID }) else { return }
            player.relics[index].isLocked.toggle()
        }
    }

    /// Power-up attempts until the relic reaches `target` or the drachma
    /// runs out, every outcome handed back for the summary line. Capped so a
    /// run of failures cannot spin: sixty attempts is far past the expected
    /// bill from +0 to +15.
    func powerUpRelic(_ relicID: UUID, to target: Int) -> [RelicService.PowerUpOutcome] {
        var outcomes: [RelicService.PowerUpOutcome] = []
        // `!relic.hasPendingRoll` is the stop: a batch that powered straight
        // through +3 would have to pick for the player, which is the whole
        // thing this feature exists to stop. It halts and the screen shows
        // the two candidates.
        while outcomes.count < 60, let relic = player.relic(relicID),
              !relic.hasPendingRoll, relic.level < min(target, relic.maxLevel) {
            let cost = RelicService.upgradeCost(grade: relic.grade, level: relic.level)
            guard player.wallet.drachma >= cost, let outcome = powerUpRelic(relicID) else { break }
            outcomes.append(outcome)
        }
        return outcomes
    }

    /// Hones one sub stat with a whetstone. Nil, and the reason shown, when
    /// there is no stone or no drachma.
    @discardableResult
    func honeRelic(_ relicID: UUID, subStat index: Int, tier: RelicStone.Tier) -> RelicService.HoneOutcome? {
        var rng = makeRandom()
        let result: RelicService.HoneOutcome?? = attempt { player in
            try RelicService.hone(relicID: relicID, subStat: index, tier: tier, player: &player, rng: &rng)
        }
        return result ?? nil
    }

    /// Replaces one sub stat with a gem's roll of `kind`.
    @discardableResult
    func gemRelic(_ relicID: UUID, subStat index: Int, with kind: StatKind, tier: RelicStone.Tier) -> RelicService.GemOutcome? {
        var rng = makeRandom()
        let result: RelicService.GemOutcome?? = attempt { player in
            try RelicService.engrave(relicID: relicID, subStat: index, with: kind, tier: tier, player: &player, rng: &rng)
        }
        return result ?? nil
    }

    func stoneCount(_ stone: RelicStone) -> Int {
        RelicService.stoneCount(stone, player: player)
    }

    /// Awakens a 6★ +15 relic for the Titans' aether: the flag, and the
    /// choice of two for its fifth sub stat. Nil, with the reason shown,
    /// when it is not eligible or the aether is short.
    @discardableResult
    func awakenRelic(_ relicID: UUID, paying element: Element) -> RelicService.AwakeningOutcome? {
        var rng = makeRandom()
        let result: RelicService.AwakeningOutcome?? = attempt { player in
            try RelicService.awaken(relicID: relicID, paying: element, player: &player, rng: &rng)
        }
        return result ?? nil
    }

    func unequipAll(_ unitID: UUID) {
        update { player in
            RelicService.unequipAll(unitID: unitID, player: &player)
        }
    }

    // MARK: - Boons

    /// Opens a cache on one of its three doors: the boon, rolled. Nil, with
    /// the reason shown, when the cache is gone or the door is not one of
    /// its three.
    @discardableResult
    func openBoonCache(_ cacheID: UUID, choice: Int) -> Boon? {
        var rng = makeRandom()
        let result: Boon?? = attempt { player in
            try BoonService.open(cacheID: cacheID, choice: choice, player: &player, rng: &rng)
        }
        return result ?? nil
    }

    /// Pays for a push and opens its choice of two. Nil, with the reason
    /// shown, when the boon is fully pushed or the price is short.
    @discardableResult
    func pushBoon(_ boonID: UUID) -> Boon? {
        var rng = makeRandom()
        let result: Boon?? = attempt { player in
            try BoonService.push(boonID: boonID, player: &player, rng: &rng)
        }
        return result ?? nil
    }

    /// Takes one of the two bumps a push offered. The candidates are derived
    /// from the boon's own seed, so this spends the pair on the table and
    /// cannot draw another.
    @discardableResult
    func takeBoonPush(_ boonID: UUID, candidate: Int) -> Double? {
        var bump: Double?
        update { player in
            guard var boons = player.boons, let index = boons.firstIndex(where: { $0.id == boonID }) else { return }
            bump = BoonService.takePush(&boons[index], candidate: candidate)
            player.boons = boons
        }
        return bump
    }

    func equipBoon(_ boonID: UUID, on unitID: UUID) {
        attempt { player in
            try BoonService.equip(boonID: boonID, unitID: unitID, player: &player)
        }
    }

    func unequipBoon(from unitID: UUID) {
        update { player in
            BoonService.unequip(unitID: unitID, player: &player)
        }
    }

    func toggleBoonLock(_ boonID: UUID) {
        update { player in
            guard var boons = player.boons, let index = boons.firstIndex(where: { $0.id == boonID }) else { return }
            boons[index].isLocked.toggle()
            player.boons = boons
        }
    }

    /// Sells boons, taking any out of its socket first. Nil, and an error
    /// shown, if one of them is locked.
    @discardableResult
    func sellBoons(_ boonIDs: [UUID]) -> Int? {
        attempt { player in
            try BoonService.sell(boonIDs: boonIDs, player: &player)
        }
    }

    // MARK: - The optimiser and loadouts

    /// The best six relics for a unit under one goal. A read, not a mutation:
    /// nothing moves until the player taps Equip, so the screen can re-solve
    /// on every tap of a goal segment without touching the save.
    func optimisedLoadout(for unitID: UUID, goal: RelicService.OptimiserGoal) -> RelicService.OptimisedLoadout? {
        RelicService.optimise(unitID: unitID, goal: goal, player: player)
    }

    /// Equips a whole six by slot, emptying any slot the plan does not name and
    /// taking a relic off another unit if that is where it is.
    func applyRelicLoadout(_ relicIDs: [Int: UUID], to unitID: UUID) {
        update { player in
            // `_ =` rather than a bare call: `applyLoadout` hands back how many
            // slots it filled, and `update` wants a closure that returns Void.
            _ = RelicService.applyLoadout(relicIDs: relicIDs, to: unitID, player: &player)
        }
    }

    func relicLoadouts(for unitID: UUID) -> [RelicLoadout] {
        RelicService.loadouts(for: unitID, in: player.relicLoadouts ?? [])
    }

    /// Keeps what the unit is wearing under `name`, replacing its loadout of
    /// that name. False when it already keeps `RelicService.loadoutsPerUnit`
    /// under other names, so the screen says so rather than the save quietly
    /// dropping the oldest.
    @discardableResult
    func saveRelicLoadout(named name: String, for unitID: UUID) -> Bool {
        var saved = false
        update { player in
            guard let loadout = RelicService.captureLoadout(named: name, for: unitID, player: player) else { return }
            var all = player.relicLoadouts ?? []
            saved = RelicService.saveLoadout(loadout, into: &all)
            player.relicLoadouts = all
        }
        return saved
    }

    func deleteRelicLoadout(_ loadoutID: UUID) {
        update { player in
            var all = player.relicLoadouts ?? []
            RelicService.removeLoadout(loadoutID, from: &all)
            player.relicLoadouts = all
        }
    }

    func applySavedLoadout(_ loadoutID: UUID) {
        update { player in
            guard let loadout = (player.relicLoadouts ?? []).first(where: { $0.id == loadoutID }) else { return }
            _ = RelicService.applyLoadout(
                relicIDs: loadout.relicIDs, to: loadout.unitID, player: &player
            )
        }
    }

    // MARK: - The bazaar

    /// Buys an item, or claims the daily offering. Nil, and an error shown,
    /// when it cannot be paid for or was already claimed today.
    func buy(_ item: ShopService.Item) -> [ShopService.Grant]? {
        var rng = makeRandom()
        let grants = attempt { player in
            try ShopService.buy(item, player: &player, rng: &rng)
        }
        if grants != nil, item.isDaily {
            update { player in QuestService.record(.dailyOfferingClaimed, player: &player) }
        }
        return grants
    }

    // MARK: - The island's decorations

    /// Buys a piece for the island for good; false, with the reason shown,
    /// when it cannot be paid for, is locked, or is already owned.
    @discardableResult
    func buyDecoration(_ id: String) -> Bool {
        attempt { player in try IslandDecorService.buy(id, player: &player) } != nil
    }

    /// Stands an owned piece in a slot; a piece standing elsewhere moves.
    func placeDecoration(_ id: String, in slot: String) {
        _ = attempt { player in try IslandDecorService.place(id, in: slot, player: &player) }
    }

    /// Empties a slot; the piece stays owned.
    func clearDecoration(in slot: String) {
        update { player in IslandDecorService.clear(slot: slot, player: &player) }
    }

    // MARK: - The Night Market

    /// Tonight's shelf. Empty only in the instant before the first tick rolls
    /// one, which the view handles by asking for a refresh on appear.
    var nightMarketStalls: [NightMarketService.Stall] {
        NightMarketService.stalls(for: player)
    }

    /// When the shelf turns over for nothing, or nil before it has opened.
    var nightMarketRefreshesAt: Date? {
        player.nightMarket.map { NightMarketService.refreshesAt($0) }
    }

    /// What the next paid re-roll costs, in divinity.
    var nightMarketRerollPrice: Int {
        NightMarketService.rerollPrice(
            afterRerolls: player.nightMarket.map { NightMarketService.rerollsToday($0) } ?? 0
        )
    }

    /// Opens the market if it has never been opened, or if the hour is up.
    func refreshNightMarket() {
        var copy = player
        guard NightMarketService.refreshIfNeeded(player: &copy) else { return }
        player = copy
        markDirty()
    }

    func buyFromNightMarket(slot: Int) -> [ShopService.Grant]? {
        var rng = makeRandom()
        return attempt { player in
            try NightMarketService.buy(slot: slot, player: &player, rng: &rng)
        }
    }

    func rerollNightMarket() {
        attempt { player in
            try NightMarketService.reroll(player: &player)
        }
    }

    // MARK: - Missions

    func claimMission(_ id: String) -> [ShopService.Grant]? {
        var rng = makeRandom()
        return attempt { player in
            try QuestService.claimMission(id, player: &player, rng: &rng)
        }
    }

    func claimFeat(_ id: String) -> [ShopService.Grant]? {
        var rng = makeRandom()
        return attempt { player in
            try QuestService.claimFeat(id, player: &player, rng: &rng)
        }
    }

    func claimLoginGift() -> [ShopService.Grant]? {
        var rng = makeRandom()
        return attempt { player in
            try QuestService.claimLoginGift(player: &player, rng: &rng)
        }
    }

    /// Claims one step of Athena's Counsel, or a tier's prize.
    func claimCounsel(_ id: String) -> [ShopService.Grant]? {
        var rng = makeRandom()
        return attempt { player in
            try CounselService.claim(id, player: &player, rng: &rng)
        }
    }

    /// Claims every finished mission of the day and then the Daily Tribute
    /// they open (Docs/FEEL.md W2.12): the existing claims, looped until a
    /// pass claims nothing (`QuestService.claimAllMissions`). What it paid,
    /// as the claims paid it; empty when nothing was waiting.
    func claimAllMissions() -> [ShopService.Grant] {
        var rng = makeRandom()
        var paid: [ShopService.Grant] = []
        update { player in
            paid = QuestService.claimAllMissions(player: &player, rng: &rng)
        }
        return paid
    }

    /// Claims every finished feat (W2.12).
    func claimAllFeats() -> [ShopService.Grant] {
        var rng = makeRandom()
        var paid: [ShopService.Grant] = []
        update { player in
            paid = QuestService.claimAllFeats(player: &player, rng: &rng)
        }
        return paid
    }

    /// Claims every finished step of the Counsel's current tier and then
    /// the tier's prize they open (W2.12).
    func claimAllCounsel() -> [ShopService.Grant] {
        var rng = makeRandom()
        var paid: [ShopService.Grant] = []
        update { player in
            paid = QuestService.claimAllCounsel(player: &player, rng: &rng)
        }
        return paid
    }

    /// Rewards waiting to be claimed, for the badge beside the wallet. The
    /// Counsel counts here too: a road nobody is told about is a road nobody
    /// walks.
    var claimableRewards: Int {
        QuestService.claimableCount(player: player) + CounselService.claimableCount(player: player)
    }

    // MARK: - The first hour

    // MARK: - Athena's Counsel

    /// What she has already said. A lesson is read once and stays read: the
    /// library replays it as often as the player likes without writing again.
    func hasReadLesson(_ id: String) -> Bool {
        player.lessonsRead?.contains(id) ?? false
    }

    /// The lesson she should be giving, or nil for silence.
    var currentLesson: Lesson? {
        LessonBook.current(for: player, seen: Set(player.lessonsRead ?? []))
    }

    func markLessonRead(_ id: String) {
        guard !hasReadLesson(id) else { return }
        update { player in
            var read = player.lessonsRead ?? []
            read.append(id)
            player.lessonsRead = read
        }
    }

    /// Skip: the opening stops now, carets and all. Its lessons are marked
    /// read so the library keeps every one of them, and the pop-ins carry on
    /// — she is the manual, not a cutscene.
    func silenceOpening() {
        update { player in
            var read = Set(player.lessonsRead ?? [])
            read.formUnion(LessonBook.opening.map(\.id))
            read.insert(LessonBook.openingSkipped)
            player.lessonsRead = Array(read).sorted()
        }
    }

    func hasSeenChapterIntro(_ chapterID: String) -> Bool {
        player.seenChapterIntros?.contains(chapterID) ?? false
    }

    func markChapterIntroSeen(_ chapterID: String) {
        guard !hasSeenChapterIntro(chapterID) else { return }
        update { player in
            var seen = player.seenChapterIntros ?? []
            seen.append(chapterID)
            player.seenChapterIntros = seen
        }
    }

    // MARK: - Battle plumbing

    func startCampaignBattle(stage: Stage) -> BattleEngine? {
        attempt { player in
            try CampaignService.startBattle(stage: stage, player: &player, seed: self.nextSeed())
        }
    }

    func finishCampaignBattle(stage: Stage, result: BattleResult) -> StageOutcome {
        var rng = makeRandom()
        var outcome: StageOutcome?
        let levelBefore = player.level
        let before = player
        update { player in
            outcome = CampaignService.settle(
                stage: stage, result: result, player: &player, rng: &rng
            )
        }
        noteLevelUp(from: levelBefore)
        noteClear(stage: stage, before: before)
        noteShrines(after: stage, result: result)   // Hidden Shrines: GameStore+Shrines.swift, Docs/SHRINES.md
        return outcome ?? StageOutcome(
            result: result, stars: 0, drachma: 0, playerExperience: 0, unitExperience: 0,
            relicsEarned: [], essencesEarned: [:], scrollsEarned: [:], divinityEarned: 0,
            isFirstClear: false, leveledUnits: [:]
        )
    }

    /// Leaves the island a level-up to show when the level has risen since
    /// `before` (Docs/FEEL.md W1.6). Several before a visit — an auto-repeat,
    /// a sweep of twenty — are ONE celebration from the first level to the
    /// last, the way the battle shows one combined beat.
    private func noteLevelUp(from before: Int) {
        guard player.level > before else { return }
        pendingLevelCelebration = LevelCelebration(from: pendingLevelCelebration?.from ?? before, to: player.level)
    }

    /// The island's claim on the level-up waiting for it: returned once and
    /// forgotten, so the ring bursts on one visit and never again.
    func takeLevelCelebration() -> LevelCelebration? {
        guard let pending = pendingLevelCelebration else { return nil }
        pendingLevelCelebration = nil
        return pending
    }

    // MARK: - The map plays the clear (Docs/FEEL.md W2.5)

    /// Leaves the chapter map what this run changed on its road
    /// (`StageClear.between`): nothing for a repeat or a loss, the first
    /// run's before and the last run's after across an auto-repeat of one
    /// stage, and the next chapter's city for the world road when the road's
    /// end on Normal opened it.
    private func noteClear(stage: Stage, before: Player) {
        clearSerial += 1
        guard let clear = StageClear.between(before: before, after: player, stage: stage, serial: clearSerial) else { return }
        if let pending = lastClear, pending.stageID == clear.stageID {
            lastClear = pending.merged(with: clear)
        } else {
            lastClear = clear
            unsealedClear = nil
        }
        if let city = clear.chapterOpened {
            pendingCityIgnition = city
        }
    }

    /// The map's ribbon has landed: the tier the clear opened comes unsealed
    /// on the strip's chips, its lock falling.
    func unsealClearTier(_ serial: Int) {
        guard lastClear?.serial == serial else { return }
        unsealedClear = serial
    }

    /// The map has played the clear, or left before it could finish: it is
    /// never played again.
    func finishClearBeat(_ serial: Int) {
        guard let pending = lastClear, pending.serial == serial else { return }
        lastClear = nil
        unsealedClear = nil
    }

    /// The world road's claim on the city waiting to light: returned once
    /// and forgotten.
    func takeCityIgnition() -> String? {
        guard let city = pendingCityIgnition else { return nil }
        pendingCityIgnition = nil
        return city
    }

    /// Clears a mastered stage `runs` times without a battle, and hands back
    /// the whole haul as one outcome.
    ///
    /// The gates are checked here rather than trusted from the button, because
    /// a sweep spends energy and a screen that has gone stale must not be able
    /// to spend it. Each run goes through `CampaignService.settle`, the same
    /// path a fought run takes, so the drops, the quests, the levels and the
    /// tower's milestones are identical to sitting through twenty fights.
    ///
    /// Nil when the stage is not sweepable at all; a short haul when the
    /// energy ran out partway, which the receipt says out loud.
    /// The Festival's gift of the day (`EventCalendar.claimGift`): the
    /// grants paid, or nil when there is none today or it is claimed.
    func claimEventGift() -> [ShopService.Grant]? {
        var rng = makeRandom()
        var paid: [ShopService.Grant]?
        attempt { player in
            paid = try EventCalendar.claimGift(player: &player, rng: &rng)
        }
        return paid
    }

    func sweep(stage: Stage, runs: Int) -> SweepReceipt? {
        guard SweepService.canSweep(stage, player: player) else { return nil }
        var rng = makeRandom()
        var receipt: SweepReceipt?
        let levelBefore = player.level
        let before = player
        defer {
            noteLevelUp(from: levelBefore)
            // A sweep runs a stage already at three stars, so its map has
            // nothing new to play — but it comes through the same door as a
            // fought run, so the two can never disagree (W2.5).
            noteClear(stage: stage, before: before)
        }
        update { player in
            var outcomes: [StageOutcome] = []
            var energySpent = 0
            for _ in 0..<max(1, runs) {
                do {
                    energySpent += try CampaignService.spendSweptRun(stage: stage, player: &player)   // event price
                } catch {
                    break
                }
                let result = SweepService.masteredResult(for: stage, seed: rng.next())
                outcomes.append(
                    CampaignService.settle(stage: stage, result: result, player: &player, rng: &rng)
                )
                // A swept run finds a Hidden Shrine as a fought win does
                // (Docs/SHRINES.md): the two pay the same.
                _ = ShrineService.noteClear(stage: stage, result: result, player: &player, rng: &rng)
            }
            receipt = SweepReceipt(
                stage: stage,
                runs: outcomes.count,
                requested: max(1, runs),
                energySpent: energySpent,
                outcome: SweepService.total(outcomes, stage: stage)
            )
        }
        return receipt
    }

    /// Pays a tribute chest once; nil when it is not earned or was claimed.
    func claimTribute(_ tribute: Tribute, chapter: Chapter) -> TributeService.Receipt? {
        var rng = makeRandom()
        var receipt: TributeService.Receipt?
        update { player in
            receipt = TributeService.claim(tribute, chapter: chapter, player: &player, rng: &rng)
        }
        return receipt
    }

    // MARK: - The Endless Tower

    /// Spends the energy for the next floor and builds its engine. Nil, with
    /// the reason shown, when the tower is climbed, the energy is short or the
    /// campaign team is empty.
    ///
    /// Deliberately not `startCampaignBattle`: `CampaignService.startBattle`
    /// gates a stage on `campaignProgress`, and the tower gates on its own mark
    /// in `player.tower` instead. The clear comes back through
    /// `finishCampaignBattle`, which is where the mark moves.
    func startTowerBattle() -> BattleEngine? {
        attempt { player in
            try TowerService.startBattle(player: &player, seed: self.nextSeed())
        }
    }

    // MARK: - Raids

    /// A raid is a `Stage` like any other, but it is not on the campaign map
    /// and `CampaignService.startBattle` cannot hand the boss its mechanics — a
    /// raid started that way fights as a plain statblock, with no barrier, no
    /// adds and no rotating weakness. So it spends its energy here and builds
    /// its engine through the raid factory, which is the one entry point that
    /// passes the profiles to `BattleEngine`.
    func startRaid(_ raid: RaidEncounter) -> BattleEngine? {
        attempt { player -> BattleEngine in
            guard player.wallet.energy >= raid.stage.energyCost else {
                throw CampaignService.CampaignError.notEnoughEnergy(needed: raid.stage.energyCost)
            }
            let team = CampaignService.resolveTeam(player.campaignTeam, player: player)
            guard !team.isEmpty else { throw CampaignService.CampaignError.emptyTeam }
            player.wallet.energy -= raid.stage.energyCost
            return StageDatabase.raidEngine(
                for: raid.stage, playerTeam: team, seed: self.nextSeed()
            )
        }
    }

    /// The rewards path is the campaign's: `applyRewards` stamps
    /// `campaignProgress[stage.chapterID]`, which for a raid stage is the
    /// raid's own id, so a first clear pays exactly once.
    @discardableResult
    func finishRaid(_ raid: RaidEncounter, result: BattleResult) -> StageOutcome {
        finishCampaignBattle(stage: raid.stage, result: result)
    }

    /// For a list screen: whether the raid has ever been beaten.
    func hasCleared(_ raid: RaidEncounter) -> Bool {
        (player.campaignProgress[raid.id] ?? 0) >= 1
    }

    func startArenaBattle(against opponent: ArenaOpponent) -> BattleEngine? {
        attempt { player in
            try ArenaService.startAttack(against: opponent, player: &player, seed: self.nextSeed())
        }
    }

    func finishArenaBattle(result: BattleResult, opponent: ArenaOpponent) -> (pointsDelta: Int, laurels: Int) {
        var outcome: (Int, Int) = (0, 0)
        update { player in
            outcome = ArenaService.applyResult(result, against: opponent, player: &player)
            QuestService.record(.arenaBattle(won: result.outcome == .victory), player: &player)
        }
        return outcome
    }

    var arenaPool: [ArenaOpponent] {
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        return ArenaService.pool(for: player.arena, day: day)
            .filter { !player.arena.defeatedOpponentIDs.contains($0.id) }
    }

    // MARK: - Allies (the social layer, 2026-09-17)

    /// Friends, mail, guilds and the boards: CloudKit when the build is
    /// entitled and the device has an account, the seeded offline world
    /// otherwise (`SocialService`, Docs/SOCIAL.md).
    let social = SocialService()

    /// What a mail or a greeting paid, taken into the save.
    @discardableResult
    func receive(_ grants: [ShopService.Grant]) -> [ShopService.Grant] {
        var rng = makeRandom()
        var paid: [ShopService.Grant] = []
        update { player in
            for grant in grants {
                paid += ShopService.grant(grant, to: &player, rng: &rng)
            }
        }
        return paid
    }

    /// A guild war attack on a rival's defence: the engine, or nil when the
    /// offence team is empty.
    func startWarAttack(_ target: WarTarget) -> BattleEngine? {
        social.warBattle(against: target, player: player, seed: nextSeed())
    }

    /// The attack reported to the war (the points land on the guild's
    /// week); the reckoning has already shown what a win was worth.
    func finishWarAttack(_ target: WarTarget, result: BattleResult) {
        Task { @MainActor in
            _ = await social.reportWarAttack(against: target, result: result)
        }
    }

    #if DEBUG
    /// A roster for the screenshot tour: one of each family so the collection,
    /// the training hall and the battle have something to show. Idempotent —
    /// a second launch of the tour finds the units already there.
    func grantTourRoster() {
        update { player in
            let wanted = ["anubis_ember", "anubis_tide", "sekhmet_umbra", "zeus_ember",
                          "shabti_gale", "shabti_gale", "shabti_umbra", "shabti_ember"]
            for id in wanted {
                guard let blueprint = UnitDatabase.blueprint(id) else { continue }
                let owned = player.units.filter { $0.blueprintID == id }.count
                let alreadyWanted = wanted.filter { $0 == id }.count
                guard owned < alreadyWanted else { continue }
                var unit = Unit(blueprint: blueprint, level: id.hasPrefix("shabti") ? 1 : 12)
                unit.acquiredFrom = "tour"
                player.units.append(unit)
            }
            // The arena squad (run 216): four more gods at level 40, fielded
            // as the arena's offence and defence ONLY, so the campaign team
            // and every battle frame keep their level-12 three. The standing
            // below (1,860, the Oracle) fields challengers at level 26–29 with
            // 3★ relics, 10.6k–14.4k power; against the level-12 team every
            // challenger was rose and the lobby read as a broken matchmaker.
            // At 40 (×2.15 the level-12 stats) the squad stands near 12–13k,
            // inside the pool, so the three rows can read green, cream and
            // rose. Tagged `tour-arena`, and the Hall of Ka's tour steps pass
            // over them, so the feed and awaken frames keep their units.
            let arenaSquad = ["ares_ember", "thoth_tide", "perseus_gale", "heracles_umbra"]
            for id in arenaSquad where !player.units.contains(where: { $0.blueprintID == id }) {
                guard let blueprint = UnitDatabase.blueprint(id) else { continue }
                var unit = Unit(blueprint: blueprint, level: 40)
                unit.acquiredFrom = "tour-arena"
                player.units.append(unit)
            }
            // One common at its level cap (3★, level 35) with the four
            // Shabtis as its fodder, so tour step 3's `evolve` ledger shows a
            // unit READY to evolve — the pips, MAX and a live Evolve — where
            // it fell back to a level-12 Zeus with the requirement unmet.
            if !player.units.contains(where: { $0.blueprintID == "shabti_tide" }),
               let blueprint = UnitDatabase.blueprint("shabti_tide") {
                var unit = Unit(blueprint: blueprint, level: ProgressionService.maxLevel(stars: blueprint.naturalStars))
                unit.acquiredFrom = "tour"
                player.units.append(unit)
            }
            // One awakened unit, so the tour's collection, detail and battle
            // frames show the awakened card, name and look: the STARTER,
            // whichever family and element that is (`UnitDatabase.starter`;
            // keyed on "anubis_umbra" until 2026-09-18, the day after the
            // starter became the fire Anubis, which left the tour with no
            // awakened unit, a level-1 campaign team and a 1v4 arena defeat
            // in run 185's frames), levelled with the rest of the roster.
            if let starter = player.units.firstIndex(where: { $0.blueprintID == UnitDatabase.starter.id }) {
                player.units[starter].isAwakened = true
                player.units[starter].level = max(player.units[starter].level, 12)
                // Its regalia at III, so the tour's sheet (step 46) shows a
                // ladder part-climbed.
                player.units[starter].regaliaLevel = 3
            }
            player.wallet.drachma = max(player.wallet.drachma, 200_000)
            player.wallet.energy = max(player.wallet.energy, 40)
            // Fifteen of every essence, whatever the recipe asks, so tour
            // step 43 photographs the Awaken panel with its bill met and the
            // button live rather than three red rows. Idempotent: a save
            // that has more keeps it.
            for id in EssenceCatalog.names.keys {
                player.essences[id] = max(player.essences[id] ?? 0, 15)
            }
            // Two pieces on the sand, so the island's frame shows the
            // decorations: a brazier burning west of the circle, the sphinx
            // east of it. Once, so a run of the tour that moved them keeps
            // its own arrangement.
            if player.decorationsOwned == nil {
                player.decorationsOwned = ["brazier", "sphinx"]
                player.islandDecor = ["west": "brazier", "east": "sphinx"]
            }
            // A relic bag worth photographing: the inventory's sets, the
            // efficiency dials and a few upgrades.
            if player.relics.count < 12 {
                var rng = SeededRandom(seed: 99)
                // One of every quality, so the rims and the coloured names
                // are all in the frame.
                let bag: [(grade: Int, quality: RelicQuality, level: Int)] = [
                    (4, .magic, 3), (5, .rare, 3), (5, .hero, 6), (6, .legend, 9), (6, .hero, 12), (6, .normal, 0),
                ]
                for entry in bag {
                    var relic = RelicService.generate(grade: entry.grade, quality: entry.quality, rng: &rng)
                    for _ in 0..<entry.level { RelicService.upgradeOnce(&relic, rng: &rng) }
                    player.relics.append(relic)
                }
            }
            // One relic left mid-choice, so tour step 37 photographs the two
            // candidates rather than a power-up panel with nothing waiting.
            //
            // The SECOND-best relic, deliberately: step 19 opens the best one
            // (`TourView.bestRelic`) to photograph the power-up panel, and a
            // pending choice blocks that panel — seeding the best one would
            // have quietly replaced an existing frame with this one.
            //
            // Only relics still climbing are ranked, and only while no relic
            // has a choice waiting: the save persists between the tour's
            // launches, and once the +15 relic below existed it ranked first
            // and the pending roll landed on a THIRD relic — the one step 19
            // opens, which then photographed "TAKE A ROLL FIRST" in place of
            // its power-up panel (runs 158 and 159).
            let ranked = player.relics.indices.filter { !player.relics[$0].isMaxLevel }.sorted {
                (player.relics[$0].grade, player.relics[$0].level)
                    > (player.relics[$1].grade, player.relics[$1].level)
            }
            if ranked.count > 1, !player.relics.contains(where: { $0.hasPendingRoll }) {
                player.relics[ranked[1]].pendingRoll = 0xC0FFEE1234
            }
            // A 6★ Legend at +15, ready to be awakened, for tour step 40;
            // appended AFTER the ranking above so it does not become the
            // second-best relic the pending roll was just seeded on, and
            // skipped by `TourView.bestRelic`, which prefers a relic with
            // levels still to gain. Fury is an ember set, so the serpent's
            // aether below is the fair colour.
            if !player.relics.contains(where: { $0.grade == 6 && $0.isMaxLevel }) {
                var rng = SeededRandom(seed: 1_040)
                var relic = RelicService.generate(grade: 6, slot: 4, set: .fury, quality: .legend, rng: &rng)
                for _ in 0..<15 { RelicService.upgradeOnce(&relic, rng: &rng) }
                player.relics.append(relic)
            }
            // Whetstones and gems, so the stone sheet has something to spend.
            for stone in RelicStone.all where RelicService.stoneCount(stone, player: player) < 3 {
                RelicService.addStones(stone.id, 3, player: &player)
            }
            // Zeus wears what is free, so the sheet's ring, the collection's
            // slot grid and the picker's "Now" photograph stone tiles rather
            // than six empty pluses.
            if let zeus = player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }), zeus.equippedRelics.isEmpty {
                RelicService.autoEquip(unitID: zeus.id, player: &player)
            }
            // A road walked part way, so the chapter map photographs its
            // three tribute chests in their three states: the road's earned,
            // the gate's shut, the judgment far off, with pips under the
            // first three medallions.
            player.campaignProgress["duat_1"] = max(player.campaignProgress["duat_1"] ?? 0, 3)
            // The Vault walked to B6 and the Hall of Embers to B2, so the
            // dungeon rooms (tour steps 10 and 16, and their relaunches)
            // photograph a floor rail in all three states — cleared with its
            // pips, the current floor (B7, B3) and the locks beyond — where
            // every frame through run 211 showed one open floor over a column
            // of locks (2026-09-22, phase B). B1 at three stars is the floor
            // the `-mastered` frame opens on for the room's Sweep. It moves
            // the island's Labyrinth bubble and the Vault's card to B6/10.
            player.campaignProgress["lab_colossus"] = max(player.campaignProgress["lab_colossus"] ?? 0, 6)
            player.campaignProgress["hall_ember"] = max(player.campaignProgress["hall_ember"] ?? 0, 2)
            var stars = player.stageStars ?? [:]
            let pipsWalked: [(String, Int)] = [
                ("duat_1_1", 3), ("duat_1_2", 3), ("duat_1_3", 2),
                ("lab_colossus_1", 3), ("lab_colossus_2", 3), ("lab_colossus_3", 3),
                ("lab_colossus_4", 2), ("lab_colossus_5", 3), ("lab_colossus_6", 1),
                ("hall_ember_1", 3), ("hall_ember_2", 2),
            ]
            for (stageID, pips) in pipsWalked {
                stars[stageID] = max(stars[stageID] ?? 0, pips)
            }
            player.stageStars = stars
            player.wallet.add(.pantheonic, 10)
            // Mileage partway up the Duat banner: enough for a 4★ (61) and
            // not for a 5★ (153), so the exchange photographs both states
            // rather than a board of identical "NOT YET" tiles.
            player.summonMileage = ["duat_opens": 118]
            // The opening selector is SPENT on the tour's save. It is a
            // veteran's save, and an unspent selector opens itself the first
            // time the summon screen appears — which would put the gift sheet
            // over tour step 4's summoning room. Step 36 presents it directly.
            player.selectorClaimed = true
            // The serpent's raid graded once, so the Raids wing's card
            // photographs the stamp and the mark to beat, and aether in hand
            // for its count.
            // Enough ember aether for one awakening at the fair price with
            // some over, so the Raids wing's count and the awakening panel
            // both photograph a real number.
            player.raidGrades = ["raid_apep": RaidGrade.s.rawValue]
            player.aether = ["aether_ember": 74, "aether_pure": 21, "aether_tide": 9]
            // Boons, so the socket, the picker and the three doors all
            // photograph: a 6★ Bane of Tide pushed twice in Zeus's socket
            // (the detail step's unit, so the ring's centre shows one), a 5★
            // Ward of Ember loose in the bag, and one 5★ cache still shut,
            // its three doors fixed by the seed for tour step 41.
            if (player.boons ?? []).isEmpty {
                var bane = Boon(kind: BoonKind(.bane, element: .tide), grade: 6, magnitude: 0.183)
                bane.pushes = 2
                let ward = Boon(kind: BoonKind(.ward, element: .ember), grade: 5, magnitude: 0.121)
                player.boons = [bane, ward]
                if let zeus = player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }) {
                    try? BoonService.equip(boonID: bane.id, unitID: zeus.id, player: &player)
                }
            }
            if (player.boonCaches ?? []).isEmpty {
                BoonService.addCache(BoonCache(grade: 5, seed: 0xB0051, source: "Titan"), player: &player)
            }
            for id in ["essence_magic_mid", "essence_magic_high", "essence_umbra_mid", "essence_umbra_high"] {
                player.essences[id, default: 0] += 12
            }
            // The battle shows one of each family: the starter plus Sekhmet and Zeus.
            let team = [UnitDatabase.starter.id, "sekhmet_umbra", "zeus_ember"].compactMap { id in
                player.units.first { $0.blueprintID == id }?.id
            }
            if team.count == 3 {
                player.campaignTeam = TeamPreset(name: "Campaign", unitIDs: team)
            }
            // The arena step fights a full four: the level-40 squad seeded
            // above (run 216), a fair match for the standing's challengers.
            // It was the campaign three plus the water Anubis at level 12,
            // which every challenger outgunned by two to one.
            let offence = arenaSquad.compactMap { id in
                player.units.first { $0.blueprintID == id }?.id
            }
            if offence.count == 4 {
                player.arenaOffenseTeam = TeamPreset(name: "Arena Offense", unitIDs: offence)
            }
            // A full defence and a standing halfway up the ladder,
            // so the arena's lobby (tour step 7) photographs what it is built
            // to show: the Oracle's crest in its colour, the meter part way to
            // Champion, a record, the attacks short of full with their refill
            // clock running, and four faces on the defence. Run 211's frame
            // was a fresh account — Initiate, 0–0, one defender, 10/10 — which
            // exercised none of it (2026-09-22, phase B). The standing is
            // seeded once, on a record no fight has touched, so a tour whose
            // arena step fought keeps what it earned. It changes the pool the
            // arena fight (step 8) draws from, since the pool is seeded by
            // points, the island's arena bubble (7 attacks, not 10), and any
            // board that reads the player's arena points.
            // The same squad, led by Thoth: the defence and the offence rows
            // of the lobby read one level, as a player's do.
            let defence = ["thoth_tide", "ares_ember", "perseus_gale", "heracles_umbra"].compactMap { id in
                player.units.first { $0.blueprintID == id }?.id
            }
            if defence.count == 4 {
                player.arenaDefenseTeam = TeamPreset(name: "Arena Defense", unitIDs: defence)
            }
            if player.arena.wins == 0 && player.arena.points == 1_000 {
                player.arena.points = 1_860
                player.arena.highestPoints = 1_905
                player.arena.wins = 23
                player.arena.losses = 9
                player.arena.attacksRemaining = 7
                player.arena.lastRefresh = Date().addingTimeInterval(-9 * 60)
            }
            // Laurels in hand, so the lobby's Exchange leads to something a
            // 23-win record could buy.
            player.wallet.laurels = max(player.wallet.laurels, 1_240)
        }
    }

    /// `-tour-map-clear` (Docs/FEEL.md W2.5): the clear the chapter map plays
    /// for the CI. `boss: true` is the Duat's boss felled for the first time
    /// with three stars — the medallion turning gold, the stars stamping,
    /// the gate's chest jumping, CHAPTER CONQUERED and Hard's seal breaking —
    /// over `ChapterMapView.tourClearWalk`'s copy of the player; `false` is
    /// its third stage cleared with two, the leader walking on to the fourth
    /// and its lock breaking, the road's chest jumping, over the tour's own
    /// save (which stands exactly there). Nothing here is saved.
    func seedTourClear(boss: Bool) {
        guard let road = StageDatabase.chapter("duat_1"), road.stages.count >= 4 else { return }
        clearSerial += 1
        unsealedClear = nil
        if boss {
            let last: Int = road.stages.count - 1
            lastClear = StageClear(
                serial: clearSerial, stageID: road.stages[last].id, chapterID: road.id, stageIndex: last,
                firstClear: true, starsBefore: 0, starsAfter: 3, chestsEarned: [.boss],
                conquered: true, tierOpened: .hard,
                chapterOpened: StageDatabase.chapters.count > 1 ? StageDatabase.chapters[1].id : nil
            )
        } else {
            lastClear = StageClear(
                serial: clearSerial, stageID: road.stages[2].id, chapterID: road.id, stageIndex: 2,
                firstClear: true, starsBefore: 0, starsAfter: 2, chestsEarned: [.third],
                conquered: false, tierOpened: nil, chapterOpened: nil
            )
        }
    }

    /// `-tour-road-ignite` (W2.5): the world road lights the Duat's second
    /// city, as it does after the first chapter's boss falls on Normal.
    func seedTourIgnition() {
        guard StageDatabase.chapters.count > 1 else { return }
        pendingCityIgnition = StageDatabase.chapters[1].id
    }

    /// `-tour-missions-ready` (Docs/FEEL.md W2.12): the Daily list the CI
    /// photographs, the same every run whatever the tour's earlier steps
    /// counted — two missions ready at the head of the list with CLAIM ALL
    /// over them, and the other six claimed: the COMPLETED group under them,
    /// its rows wearing the DONE seal within the frame (with fewer claimed
    /// the group stands below the fold), and the tribute's pills six gold
    /// with a tick and two ringed ready.
    func seedTourMissions() {
        update { player in
            QuestService.refreshDay(player: &player)
            var quests: QuestProgress = player.quests ?? QuestProgress()
            var counters: [String: Int] = [:]
            for mission in QuestService.missions {
                counters[mission.id] = mission.goal
            }
            quests.counters = counters
            let ready: Set<String> = ["summon", "power_up"]
            quests.claimed = Set(QuestService.missions.map(\.id)).subtracting(ready)
            player.quests = quests
        }
    }
    #endif
}

/// A demigod level-up the island has yet to show (`GameStore
/// .pendingLevelCelebration`, Docs/FEEL.md W1.6): the level the header last
/// showed and the level it rolls to.
struct LevelCelebration: Equatable, Sendable {
    let from: Int
    let to: Int
}
