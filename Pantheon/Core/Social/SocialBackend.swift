import Foundation

/// The social layer's contract (`Docs/SOCIAL.md`): friends, an inbox, a guild
/// with an asynchronous war, and two leaderboards. Everything is a record
/// somebody writes and somebody else reads later — no chat, no live PvP —
/// which is what lets `CloudKitSocialBackend` do it on the public database
/// with no server, and what lets `LocalSocialBackend` fake all of it in
/// memory for CI, the tests and a device with no iCloud account.
///
/// Every value here is `Codable` so the same shape goes over the wire, into
/// `UserDefaults` and into a test, and `Sendable` because the backends run
/// off the main actor and hand their results to `SocialService` on it.
protocol SocialBackend: AnyObject, Sendable {
    /// "CloudKit" or "Offline", for the strip.
    var name: String { get }

    /// Whether this backend can be used right now, with the notice to show
    /// when it cannot. Cheap enough to ask on every refresh.
    func availability() async -> SocialAvailability

    // Profile
    func myProfile() async throws -> SocialProfile?
    /// Stores the player's profile under the backend's own identity and
    /// returns it with that identity stamped in (`id`).
    func publish(profile: SocialProfile) async throws -> SocialProfile
    func search(name: String) async throws -> [SocialProfile]

    // Friends
    func friends() async throws -> [Friendship]
    /// Requests waiting on the player: incoming and still pending.
    func friendRequests() async throws -> [FriendRequest]
    func sendFriendRequest(to profileID: String) async throws -> FriendRequest
    func respond(request: FriendRequest, accept: Bool) async throws

    // Mail
    func mail() async throws -> [Mail]
    func send(mail: Mail) async throws
    /// Marks the mail claimed and returns what it carried. A second claim
    /// throws `SocialError.conflict`; it never pays twice.
    func claim(mail: Mail) async throws -> [ShopService.Grant]

    // Guild
    func guild() async throws -> Guild?
    func findGuilds(name: String) async throws -> [Guild]
    func createGuild(name: String, crest: String) async throws -> Guild
    func joinGuild(id: String) async throws -> Guild
    func leaveGuild() async throws
    func guildMembers() async throws -> [GuildMember]
    func postToBoard(text: String) async throws -> BoardPost
    func board() async throws -> [BoardPost]

    // The war
    /// This week's war as the guild tab shows it, or nil with no guild or
    /// no rival. `warTargets()` and `warStandings()` read off it.
    func war() async throws -> GuildWar?
    func reportWarAttack(result: WarAttackResult) async throws -> WarStanding

    // Ranks
    func leaderboard(kind: LeaderboardKind) async throws -> [LeaderboardEntry]
}

extension SocialBackend {
    func warTargets() async throws -> [WarTarget] {
        try await war()?.targets ?? []
    }

    func warStandings() async throws -> [WarStanding] {
        try await war()?.standings ?? []
    }
}

// MARK: - Availability and errors

/// What the screens say about the backend under them.
enum SocialAvailability: Equatable, Sendable {
    case checking
    case online
    /// Cannot be used, with the one-line notice the screens wear.
    case offline(String)

    var notice: String? {
        if case .offline(let text) = self { return text }
        return nil
    }

    var isOnline: Bool { self == .online }

    /// The notices, in one place so the screens and the tests agree.
    static let noAccount = "Offline: sign in to iCloud in Settings to see other demigods."
    static let notEntitled = "Offline: this build is not signed for iCloud; showing the practice roster."
    static let restricted = "Offline: iCloud is restricted on this device; showing the practice roster."
    static let unreachable = "Offline: iCloud could not be reached; showing the practice roster."
}

/// Every failure a backend can hand the screen, with a plain sentence.
enum SocialError: Error, LocalizedError, Equatable, Sendable {
    case offline(String)
    case notEntitled
    case network
    case notFound(String)
    case conflict(String)
    case permission
    case rateLimited
    case quota
    case invalid(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .offline(let notice): return notice
        case .notEntitled: return SocialAvailability.notEntitled
        case .network: return "No connection. Try again when you are back online."
        case .notFound(let what): return "\(what) could not be found."
        case .conflict(let what): return what
        case .permission: return "iCloud refused the change. The record type's security role needs write access (Docs/SOCIAL.md)."
        case .rateLimited: return "Too many requests at once. Wait a moment and try again."
        case .quota: return "iCloud storage is full for this account."
        case .invalid(let what): return what
        case .unknown(let what): return what
        }
    }

    var message: String { errorDescription ?? "Something went wrong." }
}

// MARK: - The defence snapshot

/// One unit of a defence team as it travels: enough to draw its card and to
/// FIGHT it on another player's phone. The stats are the RESOLVED ones —
/// after relics, sets and awakening, the eight numbers `Combatant.init`
/// reads off a `ResolvedUnit` — so the fight needs neither the relics nor
/// the roll; the completed sets ride along by name so Vigil still counters
/// and Wrath still takes its extra turn, and the boon in the socket rides
/// along whole because the engine reads it at its hooks.
struct TeamSnapshotUnit: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// The blueprint id — the family key with its element, `anubis_ember`.
    var family: String
    var name: String
    var level: Int
    var stars: Int
    var element: Element
    var awakened: Bool
    var portrait: String
    var stats: Stats
    var skillLevels: [Int]
    /// `RelicSet.rawValue` → how many times the set is completed.
    var sets: [String: Int]
    var boon: Boon?
    var power: Int

    static func snapshot(of unit: ResolvedUnit) -> TeamSnapshotUnit {
        var sets: [String: Int] = [:]
        for active in unit.activeRelicSets {
            sets[active.set.rawValue] = active.completions
        }
        return TeamSnapshotUnit(
            id: unit.unit.id.uuidString,
            family: unit.blueprint.id,
            name: unit.name,
            level: unit.level,
            stars: unit.stars,
            element: unit.element,
            awakened: unit.unit.isAwakened,
            portrait: unit.blueprint.model.portraitName(awakened: unit.unit.isAwakened),
            stats: unit.stats,
            skillLevels: unit.unit.skillLevels,
            sets: sets,
            boon: unit.boon,
            power: unit.power
        )
    }

    /// The unit as this build can fight it: the blueprint at the recorded
    /// level and grade, stat-less carrier relics for the recorded sets so
    /// `activeRelicSets` still lights them, and the recorded stats written
    /// over the resolve. Nil for a family this build does not know.
    func resolved() -> ResolvedUnit? {
        guard let blueprint = UnitDatabase.blueprint(family) else { return nil }
        var unit = Unit(blueprint: blueprint, level: max(1, level), stars: max(1, min(6, stars)), awakened: awakened)
        unit.skillLevels = blueprint.skills.indices.map { index in
            index < skillLevels.count ? max(1, skillLevels[index]) : 1
        }
        var carriers: [Relic] = []
        for (raw, completions) in sets.sorted(by: { $0.key < $1.key }) {
            guard let set = RelicSet(rawValue: raw), completions > 0 else { continue }
            let pieces = completions * set.piecesRequired
            for _ in 0..<pieces where carriers.count < 6 {
                carriers.append(
                    Relic(set: set, slot: carriers.count + 1, grade: max(1, min(6, stars)),
                          mainStat: StatModifier(.hpFlat, 0), subStats: [])
                )
            }
        }
        var result = ProgressionService.resolve(unit, blueprint: blueprint, equipped: carriers, boon: boon)
        result.stats = stats.clamped()
        return result
    }
}

// MARK: - Profiles and friends

struct SocialProfile: Codable, Equatable, Identifiable, Sendable {
    /// The backend's identity for the player: the CloudKit user record's
    /// name, or `local_me` offline. Empty until first published.
    var id: String
    var name: String
    var level: Int
    var power: Int
    var arenaPoints: Int
    var guildID: String? = nil
    var guildName: String? = nil
    /// The arena DEFENCE team, which is what a war attack fights.
    var defence: [TeamSnapshotUnit]
    var updatedAt: Date

    var leader: TeamSnapshotUnit? { defence.first }
    var tier: ArenaTier { ArenaTier.tier(forPoints: arenaPoints) }
    var nameKey: String { SocialProfile.key(name) }

    /// The lowercase, trimmed form every name search runs on: CloudKit's
    /// `BEGINSWITH` is case-sensitive.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum FriendRequestStatus: String, Codable, Sendable {
    case pending
    case accepted
    case declined
}

struct FriendRequest: Codable, Equatable, Identifiable, Sendable {
    /// `req_<from>_<to>`: one request per pair, ever, until it is answered.
    var id: String
    var fromID: String
    var fromName: String
    var toID: String
    var status: FriendRequestStatus
    var sentAt: Date

    static func id(from: String, to: String) -> String { "req_\(from)_\(to)" }
}

struct Friendship: Codable, Equatable, Identifiable, Sendable {
    /// `friend_<a>_<b>` with the two ids sorted, so a pair is one record.
    var id: String
    var members: [String]
    var since: Date
    /// The OTHER member's profile, resolved by the backend when read, so the
    /// rail can draw the friend's leader and power without a second trip.
    var friend: SocialProfile

    static func id(_ a: String, _ b: String) -> String {
        let pair = [a, b].sorted()
        return "friend_\(pair[0])_\(pair[1])"
    }

    func other(than me: String) -> String {
        members.first(where: { $0 != me }) ?? friend.id
    }
}

// MARK: - Mail

struct Mail: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var toID: String
    var fromID: String
    var fromName: String
    var subject: String
    var body: String
    var grants: [ShopService.Grant]
    var claimed: Bool
    var sentAt: Date

    var hasGrants: Bool { !grants.isEmpty }

    /// The greeting a friend's row sends: a few words and a small gift the
    /// genre calls friendship points. Two mystical scrolls a greeting.
    static func greeting(from sender: SocialProfile, to friend: SocialProfile, now: Date = Date()) -> Mail {
        Mail(
            id: "mail_\(UUID().uuidString.lowercased())",
            toID: friend.id,
            fromID: sender.id,
            fromName: sender.name,
            subject: "A greeting from \(sender.name)",
            body: "\(sender.name) sends their regards from the island. May your summons be kind.",
            grants: [.scrolls(.mystical, 2)],
            claimed: false,
            sentAt: now
        )
    }
}

// MARK: - Guilds

enum GuildRole: String, Codable, Sendable {
    case leader
    case member
}

struct Guild: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    /// An SF symbol from `crests`.
    var crest: String
    var leaderID: String
    var memberCount: Int
    /// The season's points (the month's).
    var warPoints: Int
    var season: String
    /// The week the `weekPoints` belong to, and those points.
    var weekKey: String
    var weekPoints: Int
    var createdAt: Date

    var nameKey: String { SocialProfile.key(name) }
    var isFull: Bool { memberCount >= Guild.capacity }

    static let capacity = 20
    static let crests = [
        "laurel.leading", "shield.lefthalf.filled", "bolt.fill", "flame.fill",
        "moon.stars.fill", "sun.max.fill", "crown.fill", "eye.fill",
    ]
}

struct GuildMember: Codable, Equatable, Identifiable, Sendable {
    /// `member_<userID>`: one guild per player.
    var id: String
    var userID: String
    var guildID: String
    var name: String
    var level: Int
    var power: Int
    var role: GuildRole
    var joinedAt: Date
    /// This week's war points, summed from the attacks when read.
    var weekPoints: Int = 0

    static func id(userID: String) -> String { "member_\(userID)" }
}

struct BoardPost: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var guildID: String
    var authorID: String
    var authorName: String
    var text: String
    var postedAt: Date
}

// MARK: - The war

struct WarTarget: Codable, Equatable, Identifiable, Sendable {
    /// The target's user id.
    var id: String
    var profile: SocialProfile
    var guildID: String
    /// Beaten by THIS player this week: no more points from them.
    var beaten: Bool
    var pointsForWin: Int

    /// The defence as this build can fight it.
    var opponentTeam: [ResolvedUnit] { profile.defence.compactMap { $0.resolved() } }
}

struct WarStanding: Codable, Equatable, Identifiable, Sendable {
    /// The guild id.
    var id: String
    var guildName: String
    var crest: String
    var points: Int
    var wins: Int
    var attacks: Int
    var isMine: Bool
}

/// This week's war as the guild tab shows it.
struct GuildWar: Codable, Equatable, Sendable {
    var week: String
    var opponent: Guild
    var targets: [WarTarget]
    /// The player's guild first.
    var standings: [WarStanding]
    var attacksLeftToday: Int
    var endsAt: Date

    var mine: WarStanding? { standings.first(where: { $0.isMine }) }
    var theirs: WarStanding? { standings.first(where: { !$0.isMine }) }
}

/// What a fought war attack reports.
struct WarAttackResult: Codable, Equatable, Sendable {
    var targetID: String
    var targetName: String
    var targetGuildID: String
    var targetPower: Int
    var won: Bool
    var turns: Int
    var foughtAt: Date

    init(target: WarTarget, result: BattleResult, foughtAt: Date = Date()) {
        self.targetID = target.id
        self.targetName = target.profile.name
        self.targetGuildID = target.guildID
        self.targetPower = target.profile.power
        self.won = result.outcome == .victory
        self.turns = result.turnsTaken
        self.foughtAt = foughtAt
    }
}

// MARK: - Ranks

enum LeaderboardKind: String, CaseIterable, Identifiable, Sendable {
    case arena
    case guild

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arena: return "Arena"
        case .guild: return "Guilds"
        }
    }
}

struct LeaderboardEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var rank: Int
    var name: String
    /// "Lv.12 · 3,210 power" or "5 members".
    var detail: String
    var score: Int
    var crest: String? = nil
    var isMine: Bool
}

// MARK: - The war's rules

/// The numbers and the clock of the guild war (`Docs/SOCIAL.md`, *The war's
/// rules*). Everything is computed on the client from UTC, so two phones in
/// two time zones agree on the week, the day and the season.
enum WarRules {
    static let attacksPerDay = 3
    static let winPoints = 10
    /// Added to a win over a target whose power is above the attacker's.
    static let upsetBonus = 5
    /// How many of the nearest guilds the week's hash chooses among.
    static let nearestCandidates = 3

    /// ISO weeks, in UTC.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// `2026-W38`.
    static func weekKey(for date: Date = Date()) -> String {
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    /// `2026-09-17`.
    static func dayKey(for date: Date = Date()) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// `2026-09`: the season is the month.
    static func seasonKey(for date: Date = Date()) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", year, month)
    }

    /// The moment the week's war closes.
    static func weekEnd(for date: Date = Date()) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.end ?? date
    }

    /// FNV-1a, 64-bit: the same answer on every device for the same text.
    static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        return value
    }

    static func points(won: Bool, attackerPower: Int, targetPower: Int) -> Int {
        guard won else { return 0 }
        return winPoints + (targetPower > attackerPower ? upsetBonus : 0)
    }

    /// The points a guild is paired on: the season's less this week's, so
    /// points scored during the war never re-pair it.
    static func pairingPoints(_ guild: Guild, week: String) -> Int {
        guild.weekKey == week ? guild.warPoints - guild.weekPoints : guild.warPoints
    }

    /// The rival for the week: the three guilds nearest by points, one of
    /// them chosen by the hash of the week and the guild's id. Never the
    /// guild itself; nil when it is the only guild there is.
    static func opponent(for guild: Guild, among guilds: [Guild], week: String) -> Guild? {
        let mine = pairingPoints(guild, week: week)
        let candidates = guilds
            .filter { $0.id != guild.id }
            .sorted { a, b in
                let da = abs(pairingPoints(a, week: week) - mine)
                let db = abs(pairingPoints(b, week: week) - mine)
                return da == db ? a.id < b.id : da < db
            }
        guard !candidates.isEmpty else { return nil }
        let nearest = Array(candidates.prefix(nearestCandidates))
        let pick = Int(hash(week + guild.id) % UInt64(nearest.count))
        return nearest[pick]
    }
}

// MARK: - Grants on the wire

/// `ShopService.Grant` has no `Codable` of its own — nothing needed to store
/// one until a mail carried it. Written by hand because the conformance is
/// added outside the enum's own file, which is where the compiler will not
/// synthesise it. The shape is `{kind, scroll?, amount?, id?, grade?, parts?}`.
extension ShopService.Grant: Codable {
    private enum GrantField: String, CodingKey {
        case kind, scroll, amount, id, grade, parts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: GrantField.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "scrolls":
            let raw = try container.decode(String.self, forKey: .scroll)
            guard let scroll = ScrollType(rawValue: raw) else { throw SocialError.invalid("Unknown scroll \(raw)") }
            self = .scrolls(scroll, try container.decode(Int.self, forKey: .amount))
        case "energy":
            self = .energy(try container.decode(Int.self, forKey: .amount))
        case "energyRefill":
            self = .energyRefill
        case "drachma":
            self = .drachma(try container.decode(Int.self, forKey: .amount))
        case "divinity":
            self = .divinity(try container.decode(Int.self, forKey: .amount))
        case "relic":
            self = .relic(grade: try container.decode(Int.self, forKey: .grade))
        case "essences":
            self = .essences(try container.decode(String.self, forKey: .id), try container.decode(Int.self, forKey: .amount))
        case "stones":
            self = .stones(try container.decode(String.self, forKey: .id), try container.decode(Int.self, forKey: .amount))
        case "boonCache":
            self = .boonCache(grade: try container.decode(Int.self, forKey: .grade))
        case "unit":
            self = .unit(try container.decode(String.self, forKey: .id))
        case "bundle":
            self = .bundle(try container.decode([ShopService.Grant].self, forKey: .parts))
        default:
            throw SocialError.invalid("Unknown grant \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: GrantField.self)
        switch self {
        case .scrolls(let scroll, let amount):
            try container.encode("scrolls", forKey: .kind)
            try container.encode(scroll.rawValue, forKey: .scroll)
            try container.encode(amount, forKey: .amount)
        case .energy(let amount):
            try container.encode("energy", forKey: .kind)
            try container.encode(amount, forKey: .amount)
        case .energyRefill:
            try container.encode("energyRefill", forKey: .kind)
        case .drachma(let amount):
            try container.encode("drachma", forKey: .kind)
            try container.encode(amount, forKey: .amount)
        case .divinity(let amount):
            try container.encode("divinity", forKey: .kind)
            try container.encode(amount, forKey: .amount)
        case .relic(let grade):
            try container.encode("relic", forKey: .kind)
            try container.encode(grade, forKey: .grade)
        case .essences(let id, let amount):
            try container.encode("essences", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(amount, forKey: .amount)
        case .stones(let id, let amount):
            try container.encode("stones", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(amount, forKey: .amount)
        case .boonCache(let grade):
            try container.encode("boonCache", forKey: .kind)
            try container.encode(grade, forKey: .grade)
        case .unit(let id):
            try container.encode("unit", forKey: .kind)
            try container.encode(id, forKey: .id)
        case .bundle(let parts):
            try container.encode("bundle", forKey: .kind)
            try container.encode(parts, forKey: .parts)
        }
    }
}
