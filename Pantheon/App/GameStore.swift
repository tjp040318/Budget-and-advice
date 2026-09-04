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

    /// Rolling seed. Every operation that needs randomness takes a fresh stream
    /// from here so two summons in the same second cannot share a result.
    private var seedStream: SeededRandom
    private var saveTask: Task<Void, Never>?
    private var energyTimer: AnyCancellable?

    // MARK: - Lifecycle

    init(save: SaveGame) {
        self.player = save.player
        self.seedStream = SeededRandom(seed: save.rngSeed)
        startEnergyTimer()
        refreshTimedResources()
    }

    static func bootstrap() -> GameStore {
        do {
            if let existing = try SaveStore.load() {
                return GameStore(save: existing)
            }
        } catch {
            // A corrupt save has already been quarantined by the store; start
            // fresh rather than refusing to launch.
            let store = GameStore(save: NewGame.create())
            store.lastError = error.localizedDescription
            return store
        }
        return GameStore(save: NewGame.create())
    }

    /// A fresh random stream for one operation.
    func nextSeed() -> UInt64 { seedStream.next() }

    func makeRandom() -> SeededRandom { seedStream.derive() }

    // MARK: - Saving

    /// Coalesces rapid mutations into one write a moment later.
    func markDirty() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    func saveNow() async {
        isSaving = true
        defer { isSaving = false }
        var snapshot = player
        snapshot.lastSeenAt = Date()
        player = snapshot
        do {
            try SaveStore.save(SaveGame(player: snapshot, rngSeed: seedStream.next()))
        } catch {
            lastError = error.localizedDescription
        }
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

        if changed {
            player = copy
            markDirty()
        }
    }

    // MARK: - Derived views of the roster

    var resolvedUnits: [ResolvedUnit] {
        player.units.compactMap { ProgressionService.resolve($0, relics: player.relics) }
    }

    func resolved(_ unitID: UUID) -> ResolvedUnit? {
        player.unit(unitID).flatMap { ProgressionService.resolve($0, relics: player.relics) }
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
        return results ?? []
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
        update { player in
            guard let index = player.units.firstIndex(where: { $0.id == unitID }) else { return }
            let fodder = player.units.filter { fodderIDs.contains($0.id) && !$0.isLocked }
            let experience = fodder.reduce(0) { $0 + ProgressionService.feedValue(of: $1) }
            let cost = fodder.count * 500
            guard player.wallet.drachma >= cost else { return }
            player.wallet.drachma -= cost
            ProgressionService.grantExperience(experience, to: &player.units[index])
            // Unequip the fodder before it disappears, so relics come back.
            for id in fodderIDs {
                guard let fodderIndex = player.units.firstIndex(where: { $0.id == id }) else { continue }
                for slot in player.units[fodderIndex].equippedRelics.keys {
                    RelicService.unequip(slot: slot, from: id, player: &player)
                }
            }
            player.units.removeAll { fodderIDs.contains($0.id) && !$0.isLocked }
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
            for id in fodderIDs {
                guard let fodderIndex = player.units.firstIndex(where: { $0.id == id }) else { continue }
                for slot in player.units[fodderIndex].equippedRelics.keys {
                    RelicService.unequip(slot: slot, from: id, player: &player)
                }
            }
            player.units.removeAll { fodderIDs.contains($0.id) }
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
        }
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

    func upgradeRelic(_ relicID: UUID) {
        var rng = makeRandom()
        attempt { player in
            guard let index = player.relics.firstIndex(where: { $0.id == relicID }) else { return }
            var relic = player.relics[index]
            var wallet = player.wallet
            try RelicService.upgrade(&relic, wallet: &wallet, rng: &rng)
            player.relics[index] = relic
            player.wallet = wallet
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
        update { player in
            outcome = CampaignService.applyRewards(
                stage: stage, result: result, player: &player, rng: &rng
            )
        }
        return outcome ?? StageOutcome(
            result: result, stars: 0, drachma: 0, playerExperience: 0, unitExperience: 0,
            relicsEarned: [], essencesEarned: [:], scrollsEarned: [:], divinityEarned: 0,
            isFirstClear: false, leveledUnits: [:]
        )
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
        }
        return outcome
    }

    var arenaPool: [ArenaOpponent] {
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        return ArenaService.pool(for: player.arena, day: day)
            .filter { !player.arena.defeatedOpponentIDs.contains($0.id) }
    }

    // MARK: - Debug helpers

    /// Used by the settings screen. Destroys the account, so the caller confirms.
    func resetAccount() {
        SaveStore.deleteSave()
        let fresh = NewGame.create()
        player = fresh.player
        seedStream = SeededRandom(seed: fresh.rngSeed)
        markDirty()
    }
}
