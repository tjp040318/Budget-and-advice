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

    /// When the bazaar's daily offering was last claimed. Optional so a save
    /// written before the shop existed still decodes; a missing key is nil.
    var lastDailyPackClaim: Date? = nil
    /// Today's missions, the lifetime counters the feats read, the feats
    /// claimed and the login streak. Optional for the same reason.
    var quests: QuestProgress? = nil
    var lifetimeCounters: [String: Int]? = nil
    var featsClaimed: Set<String>? = nil
    /// Athena's Counsel: the step ids and tier-prize ids already collected.
    /// Optional, like every field added since the first.
    var counselClaimed: Set<String>? = nil
    var loginStreak: LoginStreak? = nil

    /// How far up the Endless Tower the player has been, and which milestones
    /// have been paid. Optional for the reason the four above are: a save
    /// written before the tower existed has no key here, and the synthesised
    /// decoder tolerates a missing optional key and nothing else.
    var tower: TowerProgress? = nil
    /// Named six-relic loadouts, saved against a unit. Ids rather than relics,
    /// so a relic sold since cannot leave a stale copy of itself in the save.
    var relicLoadouts: [RelicLoadout]? = nil
    /// Whetstones and gems by `RelicStone.id` ("whetstone_hero"). Optional
    /// for the reason the fields above are.
    var relicStones: [String: Int]? = nil
    /// RETIRED (2026-09-16), and kept only because saves carry it: how far
    /// the island's own guided opening got before Athena replaced it. Nothing
    /// writes or reads it now — `lessonsRead` below is the record.
    var firstHourStep: String? = nil
    /// Chapter ids whose intro card has been shown, so it is shown once.
    var seenChapterIntros: [String]? = nil
    /// The Night Market's rolled shelf: a seed, the hour it was rolled and
    /// the slots already emptied. Optional, like every field added since the
    /// first; nil simply means the market has not opened yet.
    var nightMarket: NightMarketStock? = nil
    /// The best star rating per stage id (a tier's suffix included): the
    /// map's pips, and the realm's judgment wants every stage at three.
    /// Optional, like every save field added since the first.
    var stageStars: [String: Int]? = nil
    /// Tribute ids claimed (`Tribute.id`: chapter id with its tier, and the
    /// milestone), so a chest pays once.
    var tributesClaimed: [String]? = nil
    /// Lesson ids Athena has given (`LessonBook`), plus the sentinel
    /// `LessonBook.openingSkipped` if the player skipped the opening. Every
    /// one of them stays readable in the library for ever. Optional, like
    /// every save field added since the first.
    var lessonsRead: [String]? = nil
    /// Mileage points per banner id: one for every summon made on that banner,
    /// spent on a unit of the player's own choosing from that banner's pool
    /// (`MileageService`). Optional, like every save field added since the
    /// first.
    var summonMileage: [String: Int]? = nil
    /// True once the opening selector has been spent — the one 4★ a new
    /// summoner picks for himself. Optional, so a save written before it
    /// existed decodes; nil and false both mean "still owed".
    var selectorClaimed: Bool? = nil
    /// The Titans' aether by id (`Aether`: `aether_ember` … `aether_pure`),
    /// paid by a raid's grade and spent on a relic's awakening. Optional,
    /// like every save field added since the first.
    var aether: [String: Int]? = nil
    /// The best `RaidGrade` earned per raid id, as its raw value ("ss"): the
    /// mark the raid's card names to beat. Optional for the same reason.
    var raidGrades: [String: String]? = nil

    func unit(_ id: UUID) -> Unit? { units.first(where: { $0.id == id }) }
    func relic(_ id: UUID) -> Relic? { relics.first(where: { $0.id == id }) }

    var experienceToNextLevel: Int { 250 + level * 180 }
}
