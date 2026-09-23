import Foundation

/// Anonymous play data (2026-09-23; `Docs/ANALYTICS.md`). The owner: "Yes,
/// anonymous only" — no names, no emails, nothing a row could be traced back
/// to a player by. This file is the closed vocabulary of what may leave the
/// phone and the pure functions that turn the game's own records into it; the
/// runtime (the queue, the batches, the sessions) is `AnalyticsService`.
///
/// Nothing here is isolated to an actor and nothing here keeps state, so the
/// hook in `QuestService.record` and the tests call every function from plain
/// code.
enum Analytics {
    /// The Settings switch, "Share anonymous play data" (the Support board on
    /// More). On unless the player turns it off, as the owner chose.
    static let shareKey = "analytics.share"

    /// The words under the switch: the whole list of what is sent.
    static let disclosure = "Sends a random number for this install, the app version and what happens in play: sessions, stages won or lost, summons, upgrades, purchases, the tutorial's steps. Never your name, Apple ID or Player ID."

    /// Events one install may queue in a UTC day; a session's start and end
    /// are never held to it. The server keeps at most 500 (the migration's
    /// trigger), so a phone whose clock is odd is still bounded.
    static let dailyCap = 400
    /// Events that make a batch worth sending at once; the rest go on the way
    /// to the background.
    static let batchSize = 20
    /// Rows in one request.
    static let maxRowsPerRequest = 100
    /// Rows kept waiting at most, on the phone and on its disk; the oldest go
    /// first when the backend has been out of reach that long.
    static let queueLimit = 500
    /// An install's number lives thirteen months and is then made again, never
    /// extended by use — the lifetime the CNIL allows an audience-measurement
    /// identifier without consent (`Docs/ANALYTICS.md` §3).
    static let installLifetime: TimeInterval = 395 * 86_400
    /// A session longer than this is a phone left on the table.
    static let longestSession = 6 * 3_600
    /// Minutes are counted to thirty days and no further.
    static let longestMinutes = 43_200

    // MARK: - Where it may run

    /// Never under the CI tour (`-tour`), never inside the unit tests' host
    /// app — a test run would otherwise count as an install on the live
    /// project every push — and never in an Xcode preview.
    static func isPermitted(arguments: [String], environment: [String: String]) -> Bool {
        !arguments.contains("-tour")
            && environment["XCTestConfigurationFilePath"] == nil
            && environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil
    }

    /// This process: the rule above, and XCTest not loaded into it. Read
    /// once — a process's arguments never change, and the game's hook asks
    /// on every record.
    static let permittedHere: Bool =
        Analytics.isPermitted(arguments: ProcessInfo.processInfo.arguments,
                              environment: ProcessInfo.processInfo.environment)
        && NSClassFromString("XCTestCase") == nil

    /// The switch, read where it is kept; absent is on.
    static func isSharing(_ defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: shareKey) as? Bool) ?? true
    }

    /// The cheap test the game's hook makes before it translates anything:
    /// allowed here, a backend to send to (`Backend.plist` filled), the switch on.
    static func mayCollect() -> Bool {
        permittedHere && BackendConfig.shared != nil && isSharing(UserDefaults.standard)
    }

    // MARK: - Tokens: the only text that leaves the phone

    /// A game id or an enum's raw value as a token: lowercase ASCII letters,
    /// digits and single underscores, at most forty — so a value can name a
    /// stage or a step and can never carry a sentence, a name or an address.
    /// `duat_1_5` is itself; `Buy NOW!!` is `buy_now`.
    static func token(_ raw: String) -> String {
        var out = ""
        var length = 0
        var pendingSeparator = false
        for scalar in raw.lowercased().unicodeScalars {
            let value = scalar.value
            let isLetter = value >= 97 && value <= 122
            let isDigit = value >= 48 && value <= 57
            guard isLetter || isDigit else {
                pendingSeparator = length > 0
                continue
            }
            if pendingSeparator {
                guard length < 39 else { break }
                out.append("_")
                length += 1
                pendingSeparator = false
            }
            guard length < 40 else { break }
            out.unicodeScalars.append(scalar)
            length += 1
        }
        return out.isEmpty ? "none" : out
    }

    /// An App Store product id as a token, without the app's own prefix:
    /// `com.pantheon.game.divinity.phial` is `divinity_phial`.
    static func productToken(_ productID: String) -> String {
        let prefix = "com.pantheon.game."
        let tail = productID.hasPrefix(prefix) ? String(productID.dropFirst(prefix.count)) : productID
        return token(tail)
    }

    /// A property's key: a token that starts with a letter, at most 24.
    static func propertyKey(_ raw: String) -> String {
        var key = token(raw)
        if let first = key.unicodeScalars.first, first.value >= 48, first.value <= 57 {
            key = "k_" + key
        }
        return String(key.prefix(24))
    }

    /// `1.2+57` from the bundle: the marketing version and the build.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "0"
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        return versionToken("\(version)+\(build)")
    }

    /// Digits, letters, `.`, `+`, `_` and `-`, at most 32: what the table's
    /// check on `app_version` accepts.
    static func versionToken(_ raw: String) -> String {
        var out = ""
        var length = 0
        for scalar in raw.unicodeScalars {
            let value = scalar.value
            let keep = (value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
                || value == 46 || value == 43 || value == 95 || value == 45
            guard keep else { continue }
            guard length < 32 else { break }
            out.unicodeScalars.append(scalar)
            length += 1
        }
        return out.isEmpty ? "0" : out
    }

    /// A build run out of Xcode says so, and the views read release builds
    /// only; TestFlight and the App Store are both release.
    static var channel: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    // MARK: - Clocks

    /// The UTC day number, which the daily cap counts by, as the server does.
    static func utcDay(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// Whole calendar days between two moments on the phone's own calendar:
    /// the `d` of a session, the install's day 0, 1, 2 ….
    static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: end)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    static func minutes(from start: Date, to end: Date) -> Int {
        let whole = Int((end.timeIntervalSince(start) / 60).rounded(.down))
        return min(longestMinutes, max(0, whole))
    }

    /// Two significant figures, so a team's power says its size and not the
    /// team: 12,345 is 12,000 and 987 is 990.
    static func roughly(_ value: Int) -> Int {
        guard value >= 100 else { return max(0, value) }
        var scale = 1
        while value / scale >= 100 { scale *= 10 }
        let lead = (Double(value) / Double(scale)).rounded()
        return Int(lead) * scale
    }

    // MARK: - A stage's run

    /// How a settled run ended, or nil for a SWEPT one. A sweep is paid
    /// through the same `CampaignService.settle` as a fight, with
    /// `SweepService.masteredResult` — a victory in which nothing was dealt or
    /// taken — and a forfeit is `BattleViewModel.forfeit()`'s defeat with the
    /// same zeros; a real fight always deals and takes damage.
    /// `AnalyticsTests` pins both shapes.
    static func verdict(of result: BattleResult) -> String? {
        let untouched = result.totalDamageDealt == 0 && result.totalDamageTaken == 0
        switch result.outcome {
        case .victory: return untouched ? nil : "won"
        case .defeat: return untouched ? "forfeit" : "lost"
        case .draw: return "draw"
        }
    }

    /// Which part of the game a stage belongs to.
    static func kind(of stage: Stage) -> String {
        if DungeonDatabase.isTowerFloor(stage) { return "tower" }
        if DungeonDatabase.hall(containing: stage) != nil { return "hall" }
        if DungeonDatabase.labyrinth(containing: stage) != nil { return "labyrinth" }
        if StageDatabase.raid(stage.chapterID) != nil { return "raid" }
        if StageDatabase.chapterOrder(of: stage.chapterID) > 0 { return "campaign" }
        return "other"
    }

    /// A fought run as the `stages` view reads it; nil for a swept one. The
    /// team is the campaign team that fought (every PvE fight takes it), its
    /// power rounded, and its share of the stage's recommended power to the
    /// nearest ten per cent — the number that says whether a stage is as hard
    /// as its recommendation claims.
    static func report(stage: Stage, result: BattleResult, stars: Int, firstClear: Bool,
                       player: Player, now: Date) -> StageReport? {
        guard let verdict = verdict(of: result) else { return nil }
        let split = CampaignDifficulty.split(stage.id)
        let power = SweepService.teamPower(player)
        let recommended = max(1, stage.recommendedPower)
        let tenths = (Double(power) / Double(recommended) * 10).rounded()
        let percent = min(500, max(0, Int(tenths) * 10))
        return StageReport(
            stage: token(split.base),
            tier: split.difficulty.rawValue,
            kind: kind(of: stage),
            chapter: StageDatabase.chapterOrder(of: stage.chapterID),
            index: max(0, stage.index),
            result: verdict,
            turns: min(999, max(0, result.turnsTaken)),
            stars: min(3, max(0, stars)),
            powerPercent: percent,
            teamPower: roughly(power),
            energy: EventCalendar.energyCost(for: stage, at: now),
            firstClear: firstClear
        )
    }

    // MARK: - The game's records, translated

    /// What one of `QuestService`'s records becomes: an event, a count added
    /// to the session, or nothing. The things a player does by the hundred —
    /// power-ups, relic upgrades, swept runs, energy — are counted and sent
    /// once, in the session's end; the things that say where he is are sent
    /// as they happen. Every case is listed, so a new record is a decision
    /// here and not a silent gap.
    static func translate(_ event: QuestService.Event, player: Player, now: Date) -> AnalyticsNote {
        var note = AnalyticsNote()
        switch event {
        case .stageCleared, .hallFloorCleared:
            // The settled run says it, with the losses as well.
            break
        case .stageSettled(let stage, let result, let stars, let firstClear):
            if let report = report(stage: stage, result: result, stars: stars, firstClear: firstClear,
                                   player: player, now: now) {
                note.event = .stageResult(report)
            } else {
                note.tally.sweptRuns = 1
            }
        case .arenaBattle(let won):
            note.event = .arena(won: won)
        case .summoned(let count, let bestStars):
            note.event = .summon(count: count, bestStars: bestStars)
        case .relicUpgraded(let level):
            note.tally.relicUpgrades = 1
            if level >= 15 { note.tally.relicsAtFifteen = 1 }
        case .unitPoweredUp:
            note.tally.powerUps = 1
        case .unitEvolved(let stars):
            note.event = .evolve(stars: stars)
        case .unitAwakened:
            note.event = .awaken
        case .unitFused:
            note.event = .fuse
        case .dailyOfferingClaimed:
            note.tally.offeringsClaimed = 1
        case .energySpent(let amount):
            note.tally.energySpent = max(0, amount)
        }
        return note
    }

    // MARK: - The first hour

    /// Athena's opening, in her order (`LessonBook.opening`); a step is
    /// reported the first time the save shows it read. `AnalyticsTests` pins
    /// the list to the book, so a new lesson is a failing test, not a hole
    /// in the funnel.
    static let lessonSteps: [FunnelStep] = [.welcome, .firstFight, .firstSummon, .firstRelic, .firstPowerUp, .farewell]

    /// The steps of the first hour this save has done, read off what it owns
    /// and has cleared. The fight and the summon are `FirstHourStep`'s own
    /// tests; the equip and the power-up are stricter than the guide's,
    /// which stand down when there is nothing to do (a new save's one unit
    /// counts as "dressed" there) — here they mean the player did it.
    static func stepsDone(by player: Player) -> Set<FunnelStep> {
        var done = Set<FunnelStep>()
        let read = Set(player.lessonsRead ?? [])
        for step in lessonSteps where read.contains(step.rawValue) {
            done.insert(step)
        }
        if read.contains(LessonBook.openingSkipped) { done.insert(.skipped) }
        if FirstHourStep.fight.isDone(for: player) { done.insert(.fightDone) }
        if FirstHourStep.summon.isDone(for: player) { done.insert(.summonDone) }
        let dressed = player.units.filter { !$0.equippedRelics.isEmpty }.count
        if dressed >= 2 { done.insert(.equipDone) }
        if (player.lifetimeCounters?["power_ups"] ?? 0) > 0 { done.insert(.powerUpDone) }
        return done
    }

    /// The steps to send now, in the funnel's order: done and not yet sent. A
    /// skip is sent alone — the lessons it marked read were never given — and
    /// the caller then counts everything done as sent.
    static func funnelNews(done: Set<FunnelStep>, sent: Set<FunnelStep>) -> [FunnelStep] {
        let skipping = done.contains(.skipped)
        return FunnelStep.allCases.filter { step in
            done.contains(step) && !sent.contains(step) && !(skipping && lessonSteps.contains(step))
        }
    }

    /// The wallet's movement between two moments: what went out and what
    /// came in, whatever moved it (a summon, the bazaar, a clear, a sale).
    static func flow(from before: AnalyticsSnapshot, to after: AnalyticsSnapshot) -> AnalyticsTally {
        var tally = AnalyticsTally()
        let divinity = after.divinity - before.divinity
        let drachma = after.drachma - before.drachma
        if divinity < 0 { tally.divinitySpent = -divinity } else { tally.divinityEarned = divinity }
        if drachma < 0 { tally.drachmaSpent = -drachma } else { tally.drachmaEarned = drachma }
        return tally
    }

    // MARK: - The request

    /// The rows as the JSON array PostgREST inserts in one statement. Every
    /// key is a property key and every text a token, again, whatever the
    /// caller built — the server strips anything else a third time.
    static func body(rows: [AnalyticsRow], channel: String) throws -> Data {
        let objects: [[String: Any]] = rows.map { row -> [String: Any] in
            var props: [String: Any] = [:]
            for (key, value) in row.props {
                props[propertyKey(key)] = value.json
            }
            return [
                "install_id": row.installID,
                "name": token(row.name),
                "props": props,
                "app_version": versionToken(row.appVersion),
                "channel": channel,
                "occurred_at": SupabaseSaveStore.iso(row.occurredAt),
            ]
        }
        return try JSONSerialization.data(withJSONObject: objects)
    }

    /// One insert of rows, with the anon key and NOTHING else: never a
    /// player's session, so no request carries an event and an account
    /// together. `return=minimal` because the table is insert-only — there
    /// is nothing a phone may read back.
    static func request(config: BackendConfig, body: Data) -> URLRequest {
        var request = SupabaseClient.request(config: config, method: "POST", path: "rest/v1/events", query: [],
                                             body: body, bearer: nil, headers: ["Prefer": "return=minimal"])
        request.timeoutInterval = 20
        return request
    }

    /// What an answer means for the batch: sent, refused for good (a row the
    /// table rejects will be rejected every time, so it is dropped), or to be
    /// tried again later.
    static func disposition(ofStatus status: Int) -> AnalyticsUpload {
        if (200..<300).contains(status) { return .sent }
        if [400, 409, 413, 422].contains(status) { return .refused }
        return .retry
    }
}

/// Every event name that may leave the phone; a row's `name` is one of these
/// raw values and nothing else.
enum AnalyticsEventName: String, CaseIterable, Sendable {
    case firstOpen = "first_open"
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case funnel
    case stageResult = "stage_result"
    case summon
    case arena
    case evolve
    case awaken
    case fuse
    case levelUp = "level_up"
    case purchase
}

/// A step of the first hour, sent once per install, in this order. The
/// lessons' raw values are their ids in `LessonBook.opening`.
enum FunnelStep: String, CaseIterable, Sendable {
    case accountGuest = "account_guest"
    case accountApple = "account_apple"
    case welcome
    case firstFight = "first_fight"
    case fightDone = "fight_done"
    case firstSummon = "first_summon"
    case summonDone = "summon_done"
    case firstRelic = "first_relic"
    case equipDone = "equip_done"
    case firstPowerUp = "first_powerup"
    case powerUpDone = "power_up_done"
    case farewell
    case skipped
}

/// One property's value: a whole number, or a token (`Analytics.token`).
enum AnalyticsValue: Equatable, Sendable, Codable {
    case int(Int)
    case token(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            self = .int(number)
        } else {
            self = .token(Analytics.token(try container.decode(String.self)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let number): try container.encode(number)
        case .token(let text): try container.encode(Analytics.token(text))
        }
    }

    /// What the JSON body carries.
    var json: Any {
        switch self {
        case .int(let number): return number
        case .token(let text): return Analytics.token(text)
        }
    }
}

/// A fought run of a stage (`Analytics.report`).
struct StageReport: Equatable, Sendable {
    /// The stage's id without its tier, as a token: `duat_1_5`.
    var stage: String
    /// `normal`, `hard` or `hell`.
    var tier: String
    /// `campaign`, `hall`, `labyrinth`, `tower`, `raid` or `other`.
    var kind: String
    /// The chapter's place on the road, 1-based; 0 off the campaign.
    var chapter: Int
    /// The stage's place in its chapter, 1-based.
    var index: Int
    /// `won`, `lost`, `forfeit` or `draw`.
    var result: String
    var turns: Int
    var stars: Int
    /// The team's power as a share of the recommended power, to the nearest ten.
    var powerPercent: Int
    /// The team's power to two significant figures.
    var teamPower: Int
    /// The energy the run was charged.
    var energy: Int
    var firstClear: Bool

    var properties: [String: AnalyticsValue] {
        [
            "stage": .token(stage),
            "tier": .token(tier),
            "kind": .token(kind),
            "chapter": .int(chapter),
            "index": .int(index),
            "result": .token(result),
            "turns": .int(turns),
            "stars": .int(stars),
            "power_pct": .int(powerPercent),
            "power": .int(teamPower),
            "energy": .int(energy),
            "first": .int(firstClear ? 1 : 0),
        ]
    }
}

/// What a session adds up rather than sends one by one, and sends in its end.
struct AnalyticsTally: Equatable, Sendable {
    var powerUps = 0
    var relicUpgrades = 0
    var relicsAtFifteen = 0
    var sweptRuns = 0
    var energySpent = 0
    var offeringsClaimed = 0
    var divinitySpent = 0
    var divinityEarned = 0
    var drachmaSpent = 0
    var drachmaEarned = 0

    var isEmpty: Bool { self == AnalyticsTally() }

    mutating func add(_ other: AnalyticsTally) {
        powerUps += other.powerUps
        relicUpgrades += other.relicUpgrades
        relicsAtFifteen += other.relicsAtFifteen
        sweptRuns += other.sweptRuns
        energySpent += other.energySpent
        offeringsClaimed += other.offeringsClaimed
        divinitySpent += other.divinitySpent
        divinityEarned += other.divinityEarned
        drachmaSpent += other.drachmaSpent
        drachmaEarned += other.drachmaEarned
    }

    var properties: [String: AnalyticsValue] {
        [
            "power_ups": .int(powerUps),
            "relic_ups": .int(relicUpgrades),
            "relic_15": .int(relicsAtFifteen),
            "sweeps": .int(sweptRuns),
            "energy": .int(energySpent),
            "offerings": .int(offeringsClaimed),
            "divinity_spent": .int(divinitySpent),
            "divinity_earned": .int(divinityEarned),
            "drachma_spent": .int(drachmaSpent),
            "drachma_earned": .int(drachmaEarned),
        ]
    }
}

/// Everything that may leave the phone, typed: a call site can only build one
/// of these, never a name or a sentence of its own.
enum AnalyticsEvent: Equatable, Sendable {
    /// The first launch of this install (not of a phone that already held a
    /// save when this version arrived).
    case firstOpen
    /// The app came to the front: days since the first open on the phone's
    /// calendar, the session's number, a cold launch or a return, and minutes
    /// since the last session ended (nil for the first).
    case sessionStart(daysSinceInstall: Int, session: Int, cold: Bool, gapMinutes: Int?)
    /// The app went to the back: seconds in front, and the session's counts.
    case sessionEnd(seconds: Int, tally: AnalyticsTally)
    /// A step of the first hour, and minutes since the first open.
    case funnel(FunnelStep, minutes: Int)
    case stageResult(StageReport)
    case summon(count: Int, bestStars: Int)
    case arena(won: Bool)
    case evolve(stars: Int)
    case awaken
    case fuse
    /// A demigod level not reached before on this install.
    case levelUp(level: Int)
    /// A real-money purchase paid into the save, by its product
    /// (`Analytics.productToken`: `divinity_phial`). The watcher sends it
    /// when the save's treasury gains a paid entry — never the transaction's
    /// id, which is Apple's and could be matched to a receipt.
    case purchase(product: String)

    var name: AnalyticsEventName {
        switch self {
        case .firstOpen: return .firstOpen
        case .sessionStart: return .sessionStart
        case .sessionEnd: return .sessionEnd
        case .funnel: return .funnel
        case .stageResult: return .stageResult
        case .summon: return .summon
        case .arena: return .arena
        case .evolve: return .evolve
        case .awaken: return .awaken
        case .fuse: return .fuse
        case .levelUp: return .levelUp
        case .purchase: return .purchase
        }
    }

    /// A session's start and end are never held to the daily cap — without
    /// them the day's other rows cannot be read — and nor is a purchase.
    var bypassesDailyCap: Bool {
        switch self {
        case .sessionStart, .sessionEnd, .purchase: return true
        default: return false
        }
    }

    var properties: [String: AnalyticsValue] {
        switch self {
        case .firstOpen, .awaken, .fuse:
            return [:]
        case .sessionStart(let days, let session, let cold, let gap):
            var props: [String: AnalyticsValue] = [
                "d": .int(days),
                "n": .int(session),
                "cold": .int(cold ? 1 : 0),
            ]
            if let gap { props["gap_min"] = .int(gap) }
            return props
        case .sessionEnd(let seconds, let tally):
            var props = tally.properties
            props["seconds"] = .int(seconds)
            return props
        case .funnel(let step, let minutes):
            return ["step": .token(step.rawValue), "minutes": .int(minutes)]
        case .stageResult(let report):
            return report.properties
        case .summon(let count, let bestStars):
            return ["count": .int(count), "best": .int(bestStars)]
        case .arena(let won):
            return ["won": .int(won ? 1 : 0)]
        case .evolve(let stars):
            return ["stars": .int(stars)]
        case .levelUp(let level):
            return ["level": .int(level)]
        case .purchase(let product):
            return ["product": .token(product)]
        }
    }
}

/// What one of the game's records became (`Analytics.translate`).
struct AnalyticsNote: Equatable, Sendable {
    var event: AnalyticsEvent?
    var tally = AnalyticsTally()

    var isEmpty: Bool { event == nil && tally.isEmpty }
}

/// One row waiting to be sent, as it will be sent. Kept on the phone's disk
/// only when the app went to the background before it could go.
struct AnalyticsRow: Codable, Equatable, Sendable {
    /// The queue's own counter, never sent: what a finished request removes.
    var seq: Int
    /// The install's number when the row was made.
    var installID: String
    var name: String
    var props: [String: AnalyticsValue]
    var appVersion: String
    var occurredAt: Date
}

/// What the save looks like to the watcher: the few things it compares.
struct AnalyticsSnapshot: Equatable, Sendable {
    var level: Int
    var divinity: Int
    var drachma: Int
    var steps: Set<FunnelStep>
    /// The products of the purchases paid into this save, oldest first
    /// (`Player.treasury`, `Docs/STORE.md`); a restored Blessing is not a
    /// purchase made here. The ledger only ever grows — a refund marks its
    /// entry, it does not remove it — so the new ones are the tail.
    var purchases: [String]

    init(_ player: Player) {
        level = player.level
        divinity = player.wallet.divinity
        drachma = player.wallet.drachma
        steps = Analytics.stepsDone(by: player)
        purchases = (player.treasury?.entries ?? []).filter { !$0.restored }.map(\.productID)
    }
}

/// An answer's meaning for its batch (`Analytics.disposition`).
enum AnalyticsUpload: Equatable, Sendable {
    case sent
    case refused
    case retry
}
