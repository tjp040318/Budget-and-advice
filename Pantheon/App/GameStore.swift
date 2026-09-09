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

        // Missions roll over at midnight and the login streak advances.
        let questsBefore = copy.quests
        let streakBefore = copy.loginStreak
        QuestService.refreshDay(player: &copy, now: now)
        if copy.quests != questsBefore || copy.loginStreak != streakBefore { changed = true }

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
        if let results, !results.isEmpty {
            update { player in
                QuestService.record(.summoned(count: results.count, bestStars: results.map(\.stars).max() ?? 3), player: &player)
            }
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
            // of its experience, the way the genre does it.
            let duplicates = fodder.filter { $0.blueprintID == player.units[index].blueprintID }.count
            for _ in 0..<duplicates {
                _ = ProgressionService.applySkillUp(to: &player.units[index], using: &rng)
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
            QuestService.record(.relicUpgraded(level: relic.level), player: &player)
        }
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

    /// Rewards waiting to be claimed, for the badge beside the wallet.
    var claimableRewards: Int { QuestService.claimableCount(player: player) }

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
            if result.outcome == .victory {
                let event: QuestService.Event = DungeonDatabase.hall(containing: stage) != nil
                    ? .hallFloorCleared(stage)
                    : .stageCleared(stage)
                QuestService.record(event, player: &player)
            }
            QuestService.record(.energySpent(stage.energyCost), player: &player)
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
            QuestService.record(.arenaBattle(won: result.outcome == .victory), player: &player)
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
            // One awakened unit, so the tour's collection, detail and battle
            // frames show the awakened card, name and look.
            if let starter = player.units.firstIndex(where: { $0.blueprintID == "anubis_umbra" }) {
                player.units[starter].isAwakened = true
            }
            player.wallet.drachma = max(player.wallet.drachma, 200_000)
            player.wallet.energy = max(player.wallet.energy, 40)
            // A relic bag worth photographing: the inventory's sets, the
            // efficiency dials and a few upgrades.
            if player.relics.count < 12 {
                var rng = SeededRandom(seed: 99)
                for grade in [4, 5, 5, 6, 6, 6] {
                    var relic = RelicService.generate(grade: grade, rng: &rng)
                    for _ in 0..<(grade == 6 ? 9 : 3) { RelicService.upgradeOnce(&relic, rng: &rng) }
                    player.relics.append(relic)
                }
            }
            player.wallet.add(.pantheonic, 10)
            for id in ["essence_magic_mid", "essence_magic_high", "essence_umbra_mid", "essence_umbra_high"] {
                player.essences[id, default: 0] += 12
            }
            // The battle shows one of each family: the starter plus Sekhmet and Zeus.
            let team = ["anubis_umbra", "sekhmet_umbra", "zeus_ember"].compactMap { id in
                player.units.first { $0.blueprintID == id }?.id
            }
            if team.count == 3 {
                player.campaignTeam = TeamPreset(name: "Campaign", unitIDs: team)
            }
            // The arena step fights a full four, so the offence team is the
            // three plus a second Anubis rather than the starter alone.
            let offence = ["anubis_umbra", "sekhmet_umbra", "zeus_ember", "anubis_ember"].compactMap { id in
                player.units.first { $0.blueprintID == id }?.id
            }
            if offence.count == 4 {
                player.arenaOffenseTeam = TeamPreset(name: "Arena Offense", unitIDs: offence)
            }
        }
    }
    #endif
}
