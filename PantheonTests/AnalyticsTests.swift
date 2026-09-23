import XCTest
@testable import Pantheon

/// The anonymous play data (`Docs/ANALYTICS.md`, 2026-09-23): what leaves the
/// phone and what never does, the batches and the daily cap, the tour's and
/// the tests' silence, the switch that forgets the install, the game's
/// records translated, and the first hour read off the save. Nothing here
/// reaches a network — every service is handed a canned transport — and
/// every value it keeps goes to a UserDefaults suite of its own and a
/// temporary save folder.
final class AnalyticsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var folder: URL!
    private var previousBase: URL?

    override func setUp() {
        super.setUp()
        suiteName = "AnalyticsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        previousBase = SaveStore.baseURL
        SaveStore.baseURL = folder
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        SaveStore.baseURL = previousBase
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private static let config = BackendConfig(url: URL(string: "https://example.supabase.co")!, anonKey: "anon-key")

    /// A canned backend: records every request and answers each with the
    /// next status in its list, 201 once the list runs out.
    private actor AnalyticsStub {
        private(set) var requests: [URLRequest] = []
        private var statuses: [Int]

        init(statuses: [Int]) {
            self.statuses = statuses
        }

        func handle(_ request: URLRequest) -> (Data, HTTPURLResponse) {
            requests.append(request)
            let status = statuses.isEmpty ? 201 : statuses.removeFirst()
            let url = request.url ?? URL(string: "https://example.supabase.co")!
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(), response)
        }

        nonisolated var transport: SupabaseClient.Transport {
            { request in await self.handle(request) }
        }
    }

    @MainActor
    private func makeService(statuses: [Int] = [], permitted: Bool = true, batch: Int = 100,
                             cap: Int = 400) -> (AnalyticsService, AnalyticsStub) {
        let stub = AnalyticsStub(statuses: statuses)
        let service = AnalyticsService(config: AnalyticsTests.config, defaults: defaults, transport: stub.transport,
                                       permitted: permitted, batchSize: batch, dailyCap: cap)
        return (service, stub)
    }

    private static func rows(of request: URLRequest) throws -> [[String: Any]] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
    }

    private static func fits(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Where it runs

    /// The CI tour photographs the game every push and the tests run inside
    /// the app: neither may make an install on the live project.
    func testNothingRunsUnderTheTourOrInTheTests() {
        XCTAssertFalse(Analytics.isPermitted(arguments: ["Pantheon", "-tour", "-tour-step", "3"], environment: [:]))
        XCTAssertFalse(Analytics.isPermitted(arguments: ["Pantheon"],
                                             environment: ["XCTestConfigurationFilePath": "/tmp/run.xctestconfiguration"]))
        XCTAssertFalse(Analytics.isPermitted(arguments: ["Pantheon"], environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]))
        XCTAssertTrue(Analytics.isPermitted(arguments: ["Pantheon"], environment: [:]))
        XCTAssertFalse(Analytics.permittedHere, "this process is a test run: the shared service sends nothing")
        XCTAssertFalse(Analytics.mayCollect(), "so the quest hook returns before it translates anything")
    }

    @MainActor
    func testATourServiceQueuesAndSendsNothing() async {
        let (service, stub) = makeService(permitted: false, batch: 1)
        service.start(observingApp: false)
        service.log(.firstOpen, at: Date())
        service.beginSession(at: Date())
        service.noteAccount(apple: false)
        await service.flush(force: true)
        XCTAssertTrue(service.queued.isEmpty)
        let sent = await stub.requests.count
        XCTAssertEqual(sent, 0)
        XCTAssertNil(service.installID, "not even an install number is made")
        XCTAssertNil(defaults.object(forKey: "analytics.firstOpenAt"))
    }

    @MainActor
    func testNoBackendMeansNoCollection() {
        let service = AnalyticsService(config: nil, defaults: defaults, transport: nil, permitted: true)
        service.start(observingApp: false)
        service.log(.firstOpen, at: Date())
        XCTAssertFalse(service.isCollecting, "an empty Backend.plist is the offline game")
        XCTAssertTrue(service.queued.isEmpty)
    }

    // MARK: - Batches

    @MainActor
    func testRowsGoOutAsOneBatchWithTheAnonKeyAlone() async throws {
        let (service, stub) = makeService(batch: 3)
        let now = Date()
        service.log(.firstOpen, at: now)
        service.log(.summon(count: 10, bestStars: 5), at: now)
        XCTAssertNil(service.flushTask, "under a batch, nothing is sent")
        service.log(.arena(won: true), at: now)
        let task = try XCTUnwrap(service.flushTask, "the third event fills the batch")
        await task.value

        let requests = await stub.requests
        XCTAssertEqual(requests.count, 1, "one insert for the whole batch")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/rest/v1/events")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer anon-key",
                       "the anon key and never a player's session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=minimal", "insert-only: nothing is read back")

        let rows = try AnalyticsTests.rows(of: request)
        XCTAssertEqual(rows.map { $0["name"] as? String }, ["first_open", "summon", "arena"])
        let columns = Set(rows[0].keys)
        XCTAssertEqual(columns, ["install_id", "name", "props", "app_version", "channel", "occurred_at"],
                       "no column names a player")
        let install = try XCTUnwrap(rows[0]["install_id"] as? String)
        XCTAssertNotNil(UUID(uuidString: install), "a random number the phone made")
        XCTAssertEqual(install, service.installID)
        let props = try XCTUnwrap(rows[1]["props"] as? [String: Any])
        XCTAssertEqual(props["count"] as? Int, 10)
        XCTAssertEqual(props["best"] as? Int, 5)
        XCTAssertTrue(service.queued.isEmpty, "a sent batch leaves the queue")
    }

    @MainActor
    func testFailuresKeepTheRowsAndARefusedBatchIsDropped() async {
        let (service, stub) = makeService(statuses: [503, 400])
        let now = Date()
        service.log(.awaken, at: now)
        service.log(.fuse, at: now)

        await service.flush(now: now)
        XCTAssertEqual(service.queued.count, 2, "a 503 keeps every row for later")
        await service.flush(now: now)
        let duringBackOff = await stub.requests.count
        XCTAssertEqual(duringBackOff, 1, "inside the back-off nothing is tried")

        await service.flush(force: true, now: now)
        XCTAssertTrue(service.queued.isEmpty, "a 400 is a batch the table will always refuse: dropped, not retried for ever")
        let total = await stub.requests.count
        XCTAssertEqual(total, 2)
    }

    // MARK: - The daily cap

    @MainActor
    func testTheDailyCapHoldsAllButASessionsBookends() {
        let (service, _) = makeService(cap: 5)
        let noon = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<8 { service.log(.awaken, at: noon) }
        XCTAssertEqual(service.queued.count, 5, "the day's allowance, and not one more")
        service.beginSession(at: noon)
        service.endSession(at: noon.addingTimeInterval(60))
        XCTAssertEqual(service.queued.count, 7, "a session's start and end are never capped")
        service.log(.purchase(product: "divinity_phial"), at: noon)
        XCTAssertEqual(service.queued.count, 8, "nor is a purchase")
        let tomorrow = noon.addingTimeInterval(86_400)
        service.log(.awaken, at: tomorrow)
        XCTAssertEqual(service.queued.count, 9, "a new UTC day, a new allowance")
    }

    // MARK: - No free text

    func testNoFreeTextLeavesThePhone() throws {
        let hostile = "Buy NOW!! Mr. Smith <smith@example.com> 🙂 call 555-0100, then read this very long sentence"
        let report = StageReport(stage: hostile, tier: "Hard Mode", kind: "campaign", chapter: 1, index: 5, result: "won",
                                 turns: 12, stars: 3, powerPercent: 110, teamPower: 12_000, energy: 4, firstClear: true)
        var tally = AnalyticsTally()
        tally.divinitySpent = 300
        let events: [AnalyticsEvent] = [
            .firstOpen,
            .sessionStart(daysSinceInstall: 2, session: 7, cold: true, gapMinutes: 30),
            .sessionEnd(seconds: 300, tally: tally),
            .funnel(.firstFight, minutes: 3),
            .stageResult(report),
            .summon(count: 10, bestStars: 5),
            .arena(won: false),
            .evolve(stars: 5),
            .awaken,
            .fuse,
            .levelUp(level: 12),
            .purchase(product: hostile),
        ]
        XCTAssertEqual(Set(events.map(\.name)), Set(AnalyticsEventName.allCases), "every name the list allows is here")

        let install = UUID().uuidString.lowercased()
        let rows = events.enumerated().map { index, event in
            AnalyticsRow(seq: index, installID: install, name: event.name.rawValue, props: event.properties,
                         appVersion: "1.0 (7) beta!", occurredAt: Date())
        }
        let body = try Analytics.body(rows: rows, channel: "release")
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(objects.count, events.count)
        for object in objects {
            let name = try XCTUnwrap(object["name"] as? String)
            XCTAssertTrue(AnalyticsTests.fits(name, "^[a-z][a-z0-9_]{1,31}$"), name)
            let version = try XCTUnwrap(object["app_version"] as? String)
            XCTAssertTrue(AnalyticsTests.fits(version, "^[0-9A-Za-z.+_-]{1,32}$"), version)
            let props = try XCTUnwrap(object["props"] as? [String: Any])
            for (key, value) in props {
                XCTAssertTrue(AnalyticsTests.fits(key, "^[a-z][a-z0-9_]{0,23}$"), key)
                for word in ["player", "account", "user", "email", "name", "apple"] {
                    XCTAssertFalse(key.contains(word), "\(key) names a person")
                }
                if let text = value as? String {
                    XCTAssertTrue(AnalyticsTests.fits(text, "^[a-z0-9_]{1,40}$"), "\(key) = \(text)")
                } else {
                    XCTAssertTrue(value is NSNumber, "\(key) is a number or a token, nothing else")
                }
            }
        }
    }

    func testTokensAreGameIdsNeverSentences() {
        XCTAssertEqual(Analytics.token("duat_1_5"), "duat_1_5")
        XCTAssertEqual(Analytics.token("Buy NOW!!"), "buy_now")
        XCTAssertEqual(Analytics.token("  __hello--world__ "), "hello_world")
        XCTAssertEqual(Analytics.token("🙂"), "none")
        XCTAssertEqual(Analytics.productToken("com.pantheon.game.divinity.phial"), "divinity_phial")
        let long = String(repeating: "abcdefghij", count: 10)
        let length = Analytics.token(long).count
        XCTAssertEqual(length, 40)
        XCTAssertEqual(Analytics.propertyKey("15_relic"), "k_15_relic")
        XCTAssertEqual(Analytics.versionToken("1.2+57"), "1.2+57")
    }

    // MARK: - The game's records

    func testTheGamesRecordsBecomeEventsOrCounts() throws {
        let player = NewGame.create().player
        let now = Date()
        let summon = Analytics.translate(.summoned(count: 10, bestStars: 5), player: player, now: now)
        XCTAssertEqual(summon.event, AnalyticsEvent.summon(count: 10, bestStars: 5))
        let powerUp = Analytics.translate(.unitPoweredUp, player: player, now: now)
        XCTAssertNil(powerUp.event, "the things done by the hundred are counted, not sent one by one")
        XCTAssertEqual(powerUp.tally.powerUps, 1)
        let relic = Analytics.translate(.relicUpgraded(level: 15), player: player, now: now)
        XCTAssertEqual(relic.tally.relicUpgrades, 1)
        XCTAssertEqual(relic.tally.relicsAtFifteen, 1)
        let energy = Analytics.translate(.energySpent(6), player: player, now: now)
        XCTAssertEqual(energy.tally.energySpent, 6)
        let stage = try XCTUnwrap(StageDatabase.chapters.first?.stages.first)
        XCTAssertTrue(Analytics.translate(.stageCleared(stage), player: player, now: now).isEmpty,
                      "the settled run says it, with the losses as well")
        XCTAssertEqual(Analytics.translate(.arenaBattle(won: true), player: player, now: now).event, AnalyticsEvent.arena(won: true))
    }

    /// A sweep is paid through `CampaignService.settle` like a fight, and a
    /// forfeit reaches it as a defeat: the shapes those two hand in are how
    /// they are told apart, so both are pinned here to the code that makes them.
    func testASettledRunIsWonLostForfeitedOrSwept() throws {
        let player = NewGame.create().player
        let now = Date()
        let normal = try XCTUnwrap(StageDatabase.chapters.first?.stages.first { $0.id == "duat_1_5" })
        let stage = normal.at(.hard)

        let swept = SweepService.masteredResult(for: stage, seed: 7)
        XCTAssertNil(Analytics.verdict(of: swept))
        let sweep = Analytics.translate(.stageSettled(stage, swept, stars: 3, firstClear: false), player: player, now: now)
        XCTAssertNil(sweep.event, "a swept run is counted, not reported: it was not a fight")
        XCTAssertEqual(sweep.tally.sweptRuns, 1)

        let won = BattleResult(outcome: .victory, turnsTaken: 14, survivorFraction: 1,
                               totalDamageDealt: 5_000, totalDamageTaken: 800, seed: 1)
        let note = Analytics.translate(.stageSettled(stage, won, stars: 3, firstClear: true), player: player, now: now)
        guard case .stageResult(let report)? = note.event else {
            return XCTFail("a fought win is a stage_result")
        }
        XCTAssertEqual(report.stage, "duat_1_5", "the tier is its own property")
        XCTAssertEqual(report.tier, "hard")
        XCTAssertEqual(report.kind, "campaign")
        XCTAssertEqual(report.chapter, 1)
        XCTAssertEqual(report.index, 5)
        XCTAssertEqual(report.result, "won")
        XCTAssertEqual(report.turns, 14)
        XCTAssertEqual(report.stars, 3)
        XCTAssertTrue(report.firstClear)
        let remainder = report.powerPercent % 10
        XCTAssertEqual(remainder, 0, "the share of the recommended power, to the nearest ten")

        let lost = BattleResult(outcome: .defeat, turnsTaken: 20, survivorFraction: 0,
                                totalDamageDealt: 3_000, totalDamageTaken: 9_000, seed: 2)
        XCTAssertEqual(Analytics.verdict(of: lost), "lost")
        // What `BattleViewModel.forfeit()` hands the settle: nothing dealt, nothing taken.
        let forfeit = BattleResult(outcome: .defeat, turnsTaken: 3, survivorFraction: 0,
                                   totalDamageDealt: 0, totalDamageTaken: 0, seed: 0)
        XCTAssertEqual(Analytics.verdict(of: forfeit), "forfeit")
    }

    func testEveryPlaceHasItsKind() throws {
        let hall = try XCTUnwrap(DungeonDatabase.allFloors.first)
        XCTAssertEqual(Analytics.kind(of: hall), "hall")
        let level = try XCTUnwrap(DungeonDatabase.allLevels.first)
        XCTAssertEqual(Analytics.kind(of: level), "labyrinth")
        XCTAssertEqual(Analytics.kind(of: DungeonDatabase.towerFloor(12)), "tower")
        let raid = try XCTUnwrap(StageDatabase.raidStages.first)
        XCTAssertEqual(Analytics.kind(of: raid), "raid")
        let hell = try XCTUnwrap(StageDatabase.chapters.first?.stages.first).at(.hell)
        XCTAssertEqual(Analytics.kind(of: hell), "campaign")
    }

    // MARK: - The first hour

    func testTheFirstHourIsReadOffTheSave() {
        XCTAssertEqual(Analytics.lessonSteps.map(\.rawValue), LessonBook.opening.map(\.id),
                       "the funnel's lessons are Athena's opening, in her order: a new lesson needs a step")
        var player = NewGame.create().player
        XCTAssertTrue(Analytics.stepsDone(by: player).isEmpty,
                      "a new save has done nothing — not even the equip step the guide stands down on")
        player.lessonsRead = ["welcome", "first_fight"]
        player.campaignProgress["duat_1"] = 1
        let done = Analytics.stepsDone(by: player)
        XCTAssertEqual(done, [.welcome, .firstFight, .fightDone])
        XCTAssertEqual(Analytics.funnelNews(done: done, sent: [.welcome]), [.firstFight, .fightDone])
        let skipping: Set<FunnelStep> = [.welcome, .firstFight, .firstSummon, .firstRelic, .firstPowerUp, .farewell, .skipped]
        XCTAssertEqual(Analytics.funnelNews(done: skipping, sent: [.welcome]), [.skipped],
                       "a skip is sent alone: the lessons it marked read were never given")
    }

    @MainActor
    func testTheWatcherSendsWhatIsNewAndNothingItFoundDone() throws {
        let (service, _) = makeService()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var player = NewGame.create().player
        player.lessonsRead = ["welcome"]
        service.beginSession(at: now)
        service.see(player, at: now)
        XCTAssertEqual(service.queued.map(\.name), ["session_start"], "the save as the store opened it is the baseline")

        player.lessonsRead = ["welcome", "first_fight"]
        player.level += 2
        player.wallet.divinity -= 300
        let entry = TreasuryEntry(transactionID: "2000000000000001", productID: "com.pantheon.game.divinity.phial",
                                  purchasedAt: now, divinity: 60, days: 0, restored: false)
        player.treasury = TreasuryLedger(entries: [entry])
        service.see(player, at: now.addingTimeInterval(60))
        XCTAssertEqual(service.queued.map(\.name), ["session_start", "level_up", "purchase", "funnel"])
        XCTAssertEqual(service.queued[1].props["level"], AnalyticsValue.int(3))
        XCTAssertEqual(service.queued[2].props["product"], AnalyticsValue.token("divinity_phial"),
                       "the product, never Apple's transaction id")
        XCTAssertEqual(service.queued[3].props["step"], AnalyticsValue.token("first_fight"),
                       "welcome was done before the watcher looked: never sent")

        service.see(player, at: now.addingTimeInterval(120))
        XCTAssertEqual(service.queued.count, 4, "the same save again is no news")

        service.endSession(at: now.addingTimeInterval(180))
        let end = try XCTUnwrap(service.queued.last)
        XCTAssertEqual(end.name, "session_end")
        XCTAssertEqual(end.props["divinity_spent"], AnalyticsValue.int(300), "the wallet's movement, in the session's counts")
    }

    @MainActor
    func testTheAccountStepIsSentOnce() {
        let (service, _) = makeService()
        service.noteAccount(apple: false)
        service.noteAccount(apple: true)
        XCTAssertEqual(service.queued.map(\.name), ["funnel"])
        XCTAssertEqual(service.queued.first?.props["step"], AnalyticsValue.token("account_guest"))
    }

    // MARK: - Sessions and first opens

    @MainActor
    func testASessionCarriesItsLengthAndItsCounts() {
        let (service, _) = makeService()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let player = NewGame.create().player
        service.start(observingApp: false, now: start)
        service.beginSession(at: start)
        service.take(Analytics.translate(.unitPoweredUp, player: player, now: start), at: start)
        service.take(Analytics.translate(.energySpent(6), player: player, now: start), at: start)
        service.endSession(at: start.addingTimeInterval(95))

        XCTAssertEqual(service.queued.map(\.name), ["first_open", "session_start", "session_end"])
        let opening = service.queued[1].props
        XCTAssertEqual(opening["cold"], AnalyticsValue.int(1))
        XCTAssertEqual(opening["n"], AnalyticsValue.int(1))
        XCTAssertEqual(opening["d"], AnalyticsValue.int(0))
        XCTAssertNil(opening["gap_min"], "the first session has nothing before it")
        let closing = service.queued[2].props
        XCTAssertEqual(closing["seconds"], AnalyticsValue.int(95))
        XCTAssertEqual(closing["power_ups"], AnalyticsValue.int(1))
        XCTAssertEqual(closing["energy"], AnalyticsValue.int(6))

        service.beginSession(at: start.addingTimeInterval(95 + 600))
        let next = service.queued[3].props
        XCTAssertEqual(next["n"], AnalyticsValue.int(2))
        XCTAssertEqual(next["cold"], AnalyticsValue.int(0))
        XCTAssertEqual(next["gap_min"], AnalyticsValue.int(10))
    }

    @MainActor
    func testAnOldInstallMeetingThisVersionIsNotANewOne() throws {
        let saves = try XCTUnwrap(SaveStore.directory)
        try Data("{}".utf8).write(to: saves.appendingPathComponent("pantheon_save_abc.json"))
        let (service, _) = makeService()
        service.start(observingApp: false)
        XCTAssertTrue(service.queued.isEmpty, "a phone that held a save was installed before today")
        XCTAssertNotNil(defaults.object(forKey: "analytics.firstOpenAt"), "its day 0 is still kept, for the sessions' d")
    }

    @MainActor
    func testAFirstOpenIsSentOnce() {
        let (service, _) = makeService()
        service.start(observingApp: false)
        service.start(observingApp: false)
        XCTAssertEqual(service.queued.map(\.name), ["first_open"])
        let (relaunched, _) = makeService()
        relaunched.start(observingApp: false)
        XCTAssertTrue(relaunched.queued.isEmpty, "the next launch is not a first open")
    }

    // MARK: - The switch and the disk

    @MainActor
    func testTurningSharingOffForgetsTheInstall() throws {
        let (service, _) = makeService()
        service.log(.awaken, at: Date())
        let first = try XCTUnwrap(service.installID)

        defaults.set(false, forKey: Analytics.shareKey)
        service.sharingChanged(false)
        XCTAssertTrue(service.queued.isEmpty, "what waited is forgotten")
        XCTAssertNil(service.installID, "and so is the install's number")
        service.log(.awaken, at: Date())
        XCTAssertTrue(service.queued.isEmpty, "off sends nothing")

        defaults.set(true, forKey: Analytics.shareKey)
        service.sharingChanged(true)
        let second = try XCTUnwrap(service.installID)
        XCTAssertNotEqual(first, second, "a new number: the rows before and after cannot be joined")
        XCTAssertEqual(service.queued.map(\.name), ["session_start"])
    }

    @MainActor
    func testWhatWaitsSurvivesARelaunch() {
        let (service, _) = makeService()
        service.log(.awaken, at: Date())
        service.log(.levelUp(level: 4), at: Date())
        service.persistQueue()
        let (relaunched, _) = makeService()
        XCTAssertEqual(relaunched.queued.map(\.name), ["awaken", "level_up"])
        let (third, _) = makeService()
        XCTAssertTrue(third.queued.isEmpty, "read once: memory holds the rows now, not the disk")
    }

    // MARK: - The paperwork

    func testThePrivacyManifestDeclaresThePlayData() throws {
        let bundle = Bundle(for: AccountService.self)
        let url = try XCTUnwrap(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        func entry(_ name: String) -> [String: Any]? {
            types.first { ($0["NSPrivacyCollectedDataType"] as? String) == name }
        }
        let device = try XCTUnwrap(entry("NSPrivacyCollectedDataTypeDeviceID"), "the install's number is a device-level ID")
        XCTAssertEqual(device["NSPrivacyCollectedDataTypeLinked"] as? Bool, false)
        XCTAssertEqual(device["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(device["NSPrivacyCollectedDataTypePurposes"] as? [String], ["NSPrivacyCollectedDataTypePurposeAnalytics"])
        for name in ["NSPrivacyCollectedDataTypeProductInteraction", "NSPrivacyCollectedDataTypePurchaseHistory"] {
            let purposes = try XCTUnwrap(entry(name)?["NSPrivacyCollectedDataTypePurposes"] as? [String], name)
            XCTAssertTrue(purposes.contains("NSPrivacyCollectedDataTypePurposeAnalytics"), name)
            XCTAssertEqual(entry(name)?["NSPrivacyCollectedDataTypeTracking"] as? Bool, false, name)
        }
    }
}
