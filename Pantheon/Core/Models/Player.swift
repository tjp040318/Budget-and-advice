import Foundation

/// Soft and hard currencies plus summoning materials.
struct Wallet: Codable, Equatable, Sendable {
    /// Hard currency. Bought, or earned slowly from first-clears.
    var divinity: Int = 750
    /// Soft currency, used for relic upgrades and levelling fodder.
    var drachma: Int = 60_000
    /// Arena currency.
    var laurels: Int = 0
    /// Energy for campaign stages.
    var energy: Int = 80
    var maxEnergy: Int = 80
    var lastEnergyTick: Date = Date()

    /// Summoning scrolls by type.
    var scrolls: [String: Int] = [
        ScrollType.mystical.rawValue: 5,
        ScrollType.pantheonic.rawValue: 2,
        ScrollType.divine.rawValue: 0
    ]

    func count(of scroll: ScrollType) -> Int { scrolls[scroll.rawValue] ?? 0 }

    mutating func add(_ scroll: ScrollType, _ amount: Int) {
        scrolls[scroll.rawValue, default: 0] += amount
    }

    @discardableResult
    mutating func consume(_ scroll: ScrollType, _ amount: Int) -> Bool {
        guard count(of: scroll) >= amount else { return false }
        scrolls[scroll.rawValue] = count(of: scroll) - amount
        return true
    }
}

/// Named saved teams. Slot 0 of `unitIDs` is the leader.
struct TeamPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var unitIDs: [UUID]

    var leaderID: UUID? { unitIDs.first }
}

/// The complete player save. One of these is the whole game state; everything
/// else is derived. `SaveGame` encodes it verbatim.
struct Player: Codable, Equatable, Sendable {
    var displayName: String = "Summoner"
    var level: Int = 1
    var experience: Int = 0
    var wallet = Wallet()

    var units: [Unit] = []
    var relics: [Relic] = []
    /// Awakening essences by id, e.g. `essence_radiance_mid`.
    var essences: [String: Int] = [:]

    var campaignTeam: TeamPreset = TeamPreset(name: "Campaign", unitIDs: [])
    var arenaOffenseTeam: TeamPreset = TeamPreset(name: "Arena Offense", unitIDs: [])
    var arenaDefenseTeam: TeamPreset = TeamPreset(name: "Arena Defense", unitIDs: [])
    var savedTeams: [TeamPreset] = []

    /// Highest stage cleared per chapter id.
    var campaignProgress: [String: Int] = [:]
    var arena = ArenaRecord()

    /// Pity counters keyed by banner id.
    var summonPity: [String: PityState] = [:]
    var totalSummons: Int = 0
    /// Blueprint ids ever owned, for the codex.
    var codex: Set<String> = []

    var createdAt: Date = Date()
    var lastSeenAt: Date = Date()

    func unit(_ id: UUID) -> Unit? { units.first(where: { $0.id == id }) }
    func relic(_ id: UUID) -> Relic? { relics.first(where: { $0.id == id }) }

    var experienceToNextLevel: Int { 250 + level * 180 }
}
