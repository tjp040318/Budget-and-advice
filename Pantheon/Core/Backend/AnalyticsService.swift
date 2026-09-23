import Foundation
import Combine
import UIKit

/// Anonymous play data on the phone (2026-09-23; `Docs/ANALYTICS.md`): a
/// random number for this install, a queue in memory, and batches of rows
/// inserted into the Supabase project's `events` table with the anon key —
/// never with a player's sign-in, so no request carries an event and an
/// account together.
///
/// - **Where it runs:** only with `Backend.plist` filled, never under the CI
///   tour or inside the unit tests' host (`Analytics.permittedHere`), and only
///   while the Settings switch is on. Off, it forgets this install's number
///   and whatever was waiting; on again, it makes a new one.
/// - **What it sends:** `AnalyticsEvent`s and nothing else — a closed list of
///   names, numbers, and game ids reduced to tokens.
/// - **When:** a batch of twenty, the way to the background (with a
///   background task, so the upload finishes), and the start of a session
///   when something was left over. What could not be sent on the way out is
///   kept on the phone's disk and sent next time.
/// - **How much:** at most `Analytics.dailyCap` rows an install a UTC day,
///   besides a session's start and end; the server keeps at most 500.
/// - **When it fails:** quietly. One `[Analytics]` line in More →
///   Diagnostics when uploads start failing and one when they recover; the
///   rows wait, the retries back off to fifteen minutes, and a batch the
///   table refuses outright is dropped rather than retried for ever.
///
/// Who feeds it: `QuestService.record` (the one place the game records
/// everything that counts — `record(_:player:now:)` below), the store's
/// `player` (`watch`, from `AppSession.install`: the first hour's steps,
/// level-ups, purchases and the wallet's movements), the two sign-in buttons
/// (`noteAccount`) and the app's own comings and goings (sessions).
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService(config: BackendConfig.shared)

    let config: BackendConfig?
    private let defaults: UserDefaults
    private let transport: SupabaseClient.Transport
    private let permitted: Bool
    private let batchSize: Int
    private let dailyCap: Int
    private let appVersion = Analytics.appVersion

    /// What waits to be sent, oldest first.
    private(set) var queued: [AnalyticsRow] = []
    /// The flush a full batch started; a test awaits it.
    private(set) var flushTask: Task<Void, Never>?
    private var seq = 0
    private var isFlushing = false
    private var retryAt: Date?
    private var failures = 0
    private var failing = false
    private var capNoted = false
    private var started = false

    private var sessionStartedAt: Date?
    private var tally = AnalyticsTally()
    private var coldLaunch = true

    private var lastSnapshot: AnalyticsSnapshot?
    private var playerWatch: AnyCancellable?
    private var appWatch: [AnyCancellable] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// `transport` is the network (a test hands in canned answers);
    /// `permitted` is false under the tour and the tests.
    init(
        config: BackendConfig?,
        defaults: UserDefaults = .standard,
        transport: SupabaseClient.Transport? = nil,
        permitted: Bool = Analytics.permittedHere,
        batchSize: Int = Analytics.batchSize,
        dailyCap: Int = Analytics.dailyCap
    ) {
        self.config = config
        self.defaults = defaults
        self.transport = transport ?? AnalyticsNetwork.transport
        self.permitted = permitted
        self.batchSize = max(1, batchSize)
        self.dailyCap = max(0, dailyCap)
        restoreQueue()
    }

    /// Allowed here, a backend to send to, and the player's switch on.
    var isCollecting: Bool {
        permitted && config != nil && Analytics.isSharing(defaults)
    }

    /// This install's number, when it has one.
    var installID: String? { defaults.string(forKey: AnalyticsKeys.installID) }

    // MARK: - The game's hook

    /// `QuestService.record`'s one line: the record translated, on the main
    /// actor, when collecting — and nothing at all, not even the translation,
    /// when not. Callable from plain code: the quest service is not isolated.
    nonisolated static func record(_ event: QuestService.Event, player: Player, now: Date) {
        guard Analytics.mayCollect() else { return }
        let note = Analytics.translate(event, player: player, now: now)
        guard !note.isEmpty else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                AnalyticsService.shared.take(note, at: now)
            }
        } else {
            Task { @MainActor in
                AnalyticsService.shared.take(note, at: now)
            }
        }
    }

    /// A translated record: its event queued, its counts added to the session.
    func take(_ note: AnalyticsNote, at date: Date) {
        guard isCollecting else { return }
        if let event = note.event { log(event, at: date) }
        if !note.tally.isEmpty { tally.add(note.tally) }
    }

    // MARK: - Launch

    /// Once, at launch (`PantheonApp.init`): the install's first open, and the
    /// app's comings and goings from then on. `observingApp` is false in a test.
    func start(observingApp: Bool = true, now: Date = Date()) {
        guard permitted, config != nil, !started else { return }
        started = true
        if defaults.object(forKey: AnalyticsKeys.firstOpenAt) == nil {
            defaults.set(now, forKey: AnalyticsKeys.firstOpenAt)
            // A phone that already holds a save is an old install meeting
            // this version, not a new one: it is never counted as installed
            // today, so the day's cohort is only the players who are new.
            if isCollecting && !AnalyticsService.phoneHoldsASave() {
                log(.firstOpen, at: now)
            }
        }
        if observingApp { observeApp() }
    }

    private func observeApp() {
        let center = NotificationCenter.default
        appWatch = [
            center.publisher(for: UIApplication.didBecomeActiveNotification)
                .sink { [weak self] _ in self?.appBecameActive() },
            center.publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in self?.appWentToBackground() },
            center.publisher(for: UIApplication.willTerminateNotification)
                .sink { [weak self] _ in self?.appWillTerminate() },
        ]
    }

    /// A save file of any account in the save folder.
    private static func phoneHoldsASave() -> Bool {
        guard let folder = SaveStore.directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return names.contains { $0.hasPrefix("pantheon_save") && $0.hasSuffix(".json") }
    }

    // MARK: - Sessions

    /// The app came to the front. A return from the background inside the
    /// same session is still a new one here; `gap_min` lets a view merge them.
    func beginSession(at now: Date = Date()) {
        guard isCollecting, sessionStartedAt == nil else { return }
        sessionStartedAt = now
        let session = defaults.integer(forKey: AnalyticsKeys.sessions) + 1
        defaults.set(session, forKey: AnalyticsKeys.sessions)
        let firstOpen = (defaults.object(forKey: AnalyticsKeys.firstOpenAt) as? Date) ?? now
        let lastEnd = defaults.object(forKey: AnalyticsKeys.lastSessionEnd) as? Date
        let gap: Int? = lastEnd.map { Analytics.minutes(from: $0, to: now) }
        log(.sessionStart(daysSinceInstall: Analytics.daysBetween(firstOpen, now), session: min(session, 99_999),
                          cold: coldLaunch, gapMinutes: gap), at: now)
        coldLaunch = false
        if !queued.isEmpty { flushSoon() }
    }

    /// The app went to the back: the session's seconds and its counts.
    func endSession(at now: Date = Date()) {
        guard let started = sessionStartedAt else { return }
        sessionStartedAt = nil
        let seconds = min(Analytics.longestSession, max(0, Int(now.timeIntervalSince(started))))
        let counted = tally
        tally = AnalyticsTally()
        defaults.set(now, forKey: AnalyticsKeys.lastSessionEnd)
        log(.sessionEnd(seconds: seconds, tally: counted), at: now)
    }

    private func appBecameActive() {
        beginSession()
        coldLaunch = false
    }

    /// The session ends, the queue goes to disk FIRST (so a phone that
    /// suspends mid-upload loses nothing), then one upload under a background
    /// task, then the disk is brought into line with what is left.
    private func appWentToBackground() {
        endSession()
        persistQueue()
        guard isCollecting, !queued.isEmpty else { return }
        finishBackgroundWork()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Pantheon play data") { [weak self] in
            MainActor.assumeIsolated {
                self?.persistQueue()
                self?.finishBackgroundWork()
            }
        }
        Task { [weak self] in
            await self?.flush(force: true)
            self?.persistQueue()
            self?.finishBackgroundWork()
        }
    }

    private func appWillTerminate() {
        endSession()
        persistQueue()
    }

    private func finishBackgroundWork() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - The store and the sign-in

    /// The store a session just opened (`AppSession.install`). Its first value
    /// is the baseline — whatever the save has already done is not news and
    /// is marked sent without sending — and every change after it is compared
    /// with the one before.
    func watch(_ store: GameStore) {
        lastSnapshot = nil
        guard permitted, config != nil else {
            playerWatch = nil
            return
        }
        playerWatch = store.$player.sink { [weak self] player in
            self?.see(player)
        }
    }

    /// One value of the save: the first hour's steps, a new level, a
    /// purchase, the wallet.
    func see(_ player: Player, at now: Date = Date()) {
        guard isCollecting else {
            lastSnapshot = nil
            return
        }
        let snapshot = AnalyticsSnapshot(player)
        let previous = lastSnapshot
        lastSnapshot = snapshot
        var sent = sentSteps
        guard let previous else {
            sent.formUnion(snapshot.steps)
            sentSteps = sent
            if snapshot.level > sentLevel { sentLevel = snapshot.level }
            return
        }
        let moved = Analytics.flow(from: previous, to: snapshot)
        if !moved.isEmpty { tally.add(moved) }
        if snapshot.level > previous.level, snapshot.level > sentLevel {
            sentLevel = snapshot.level
            log(.levelUp(level: snapshot.level), at: now)
        }
        let bought = snapshot.purchases.count - previous.purchases.count
        if bought > 0 {
            for product in snapshot.purchases.suffix(bought) {
                log(.purchase(product: Analytics.productToken(product)), at: now)
            }
        }
        guard !snapshot.steps.isSubset(of: sent) else { return }
        for step in Analytics.funnelNews(done: snapshot.steps, sent: sent) {
            log(.funnel(step, minutes: minutesSinceFirstOpen(now)), at: now)
        }
        sent.formUnion(snapshot.steps)
        sentSteps = sent
    }

    /// Sign in with Apple or Continue without an account, pressed on the
    /// sign-in screen: the funnel's first step after the first open, once.
    func noteAccount(apple: Bool, at now: Date = Date()) {
        guard isCollecting else { return }
        var sent = sentSteps
        guard !sent.contains(.accountGuest), !sent.contains(.accountApple) else { return }
        let step: FunnelStep = apple ? .accountApple : .accountGuest
        sent.insert(step)
        sentSteps = sent
        log(.funnel(step, minutes: minutesSinceFirstOpen(now)), at: now)
    }

    private func minutesSinceFirstOpen(_ now: Date) -> Int {
        let first = (defaults.object(forKey: AnalyticsKeys.firstOpenAt) as? Date) ?? now
        return Analytics.minutes(from: first, to: now)
    }

    private var sentSteps: Set<FunnelStep> {
        get { Set((defaults.stringArray(forKey: AnalyticsKeys.funnelSent) ?? []).compactMap { FunnelStep(rawValue: $0) }) }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: AnalyticsKeys.funnelSent) }
    }

    private var sentLevel: Int {
        get { defaults.integer(forKey: AnalyticsKeys.levelSent) }
        set { defaults.set(newValue, forKey: AnalyticsKeys.levelSent) }
    }

    // MARK: - The switch

    /// "Share anonymous play data" moved (the Settings board writes the
    /// switch, then calls this). Off: the queue, the session and this
    /// install's number are forgotten, and nothing more is made. On: a new
    /// number and a session from now.
    func sharingChanged(_ on: Bool, at now: Date = Date()) {
        guard permitted, config != nil else { return }
        lastSnapshot = nil
        if on {
            ensureInstall(now: now)
            beginSession(at: now)
        } else {
            queued.removeAll()
            tally = AnalyticsTally()
            sessionStartedAt = nil
            retryAt = nil
            failures = 0
            defaults.removeObject(forKey: AnalyticsKeys.installID)
            defaults.removeObject(forKey: AnalyticsKeys.installBornAt)
            defaults.removeObject(forKey: AnalyticsKeys.queue)
        }
    }

    // MARK: - The queue

    /// One event into the queue under this install's number, stamped with
    /// when it happened.
    func log(_ event: AnalyticsEvent, at date: Date = Date()) {
        guard isCollecting else { return }
        if !event.bypassesDailyCap && !withinDailyCap(at: date) { return }
        let install = ensureInstall(now: date)
        seq += 1
        queued.append(AnalyticsRow(seq: seq, installID: install, name: event.name.rawValue,
                                   props: event.properties, appVersion: appVersion, occurredAt: date))
        if queued.count > Analytics.queueLimit {
            queued.removeFirst(queued.count - Analytics.queueLimit)
        }
        if queued.count >= batchSize { flushSoon() }
    }

    /// This install's number: made on first use, and made again when it is
    /// thirteen months old — never extended by use.
    @discardableResult
    private func ensureInstall(now: Date) -> String {
        if let id = defaults.string(forKey: AnalyticsKeys.installID),
           let born = defaults.object(forKey: AnalyticsKeys.installBornAt) as? Date,
           now.timeIntervalSince(born) < Analytics.installLifetime {
            return id
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: AnalyticsKeys.installID)
        defaults.set(now, forKey: AnalyticsKeys.installBornAt)
        return fresh
    }

    /// The day's allowance, counted by UTC day as the server counts it.
    private func withinDailyCap(at date: Date) -> Bool {
        let day = Analytics.utcDay(date)
        var count = defaults.integer(forKey: AnalyticsKeys.capCount)
        if defaults.integer(forKey: AnalyticsKeys.capDay) != day {
            defaults.set(day, forKey: AnalyticsKeys.capDay)
            count = 0
            capNoted = false
        }
        guard count < dailyCap else {
            if !capNoted {
                capNoted = true
                AnalyticsService.note("today's \(dailyCap) events are sent; the rest of today's are not")
            }
            return false
        }
        defaults.set(count + 1, forKey: AnalyticsKeys.capCount)
        return true
    }

    private func flushSoon() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            await self?.flush()
            self?.flushTask = nil
        }
    }

    /// Sends what waits, a batch at a time, until the queue is empty or the
    /// backend says to wait. `force` ignores the back-off (the way to the
    /// background has one chance).
    func flush(force: Bool = false, now: Date = Date()) async {
        guard isCollecting, let config, !isFlushing, !queued.isEmpty else { return }
        if !force, let retryAt, now < retryAt { return }
        isFlushing = true
        defer { isFlushing = false }
        while !queued.isEmpty {
            let batch = Array(queued.prefix(Analytics.maxRowsPerRequest))
            let sent = Set(batch.map(\.seq))
            guard let body = try? Analytics.body(rows: batch, channel: Analytics.channel) else {
                queued.removeAll { sent.contains($0.seq) }
                continue
            }
            let status: Int
            do {
                let (_, response) = try await transport(Analytics.request(config: config, body: body))
                status = response.statusCode
            } catch {
                failed(error.localizedDescription, now: now)
                return
            }
            switch Analytics.disposition(ofStatus: status) {
            case .sent:
                queued.removeAll { sent.contains($0.seq) }
                recovered()
            case .refused:
                // The backend answered, so the way there is open; these rows
                // are what it will never take.
                queued.removeAll { sent.contains($0.seq) }
                recovered()
                AnalyticsService.note("the backend refused \(batch.count) events (\(status)); they are dropped")
            case .retry:
                failed("the backend answered \(status)", now: now)
                return
            }
        }
    }

    private func failed(_ reason: String, now: Date) {
        failures += 1
        // 15 s, doubling, at most fifteen minutes.
        let doublings = Double(min(failures - 1, 6))
        let backOff: TimeInterval = 15 * pow(2, doublings)
        retryAt = now.addingTimeInterval(min(900, backOff))
        guard !failing else { return }
        failing = true
        AnalyticsService.note("upload failed: \(reason); \(queued.count) events kept for later")
    }

    private func recovered() {
        failures = 0
        retryAt = nil
        guard failing else { return }
        failing = false
        AnalyticsService.note("uploads resumed")
    }

    // MARK: - The disk

    /// What waits, written to the phone for the next launch; nothing when
    /// nothing waits.
    func persistQueue() {
        guard permitted else { return }
        guard !queued.isEmpty, let data = try? JSONEncoder().encode(Array(queued.suffix(Analytics.queueLimit))) else {
            defaults.removeObject(forKey: AnalyticsKeys.queue)
            return
        }
        defaults.set(data, forKey: AnalyticsKeys.queue)
    }

    /// The rows the last launch could not send, back in the queue and off
    /// the disk: memory holds them now, and they are written again only if
    /// they are still waiting on the way out.
    private func restoreQueue() {
        guard permitted, let data = defaults.data(forKey: AnalyticsKeys.queue) else { return }
        defaults.removeObject(forKey: AnalyticsKeys.queue)
        guard let rows = try? JSONDecoder().decode([AnalyticsRow].self, from: data) else { return }
        queued = rows
        seq = rows.map(\.seq).max() ?? 0
    }

    // MARK: - The log

    /// One line, to the console and to More → Diagnostics.
    nonisolated static func note(_ line: String) {
        let stamped = "[Analytics] \(line)"
        print(stamped)
        DiagnosticsLog.shared.record(stamped)
    }
}

/// Where the service keeps its few values on the phone (`UserDefaults`, the
/// app's own: required-reason CA92.1 in the privacy manifest).
private enum AnalyticsKeys {
    static let installID = "analytics.installID"
    static let installBornAt = "analytics.installBornAt"
    static let firstOpenAt = "analytics.firstOpenAt"
    static let sessions = "analytics.sessions"
    static let lastSessionEnd = "analytics.lastSessionEnd"
    static let funnelSent = "analytics.funnelSent"
    static let levelSent = "analytics.levelSent"
    static let capDay = "analytics.capDay"
    static let capCount = "analytics.capCount"
    static let queue = "analytics.queue"
}

/// The network the rows go over: an ephemeral session, so nothing about the
/// uploads — no cookie, no cache — stays on the phone.
private enum AnalyticsNetwork {
    static let session = URLSession(configuration: .ephemeral)

    static let transport: SupabaseClient.Transport = { request in
        let (data, response) = try await AnalyticsNetwork.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.decoding("no HTTP response")
        }
        return (data, http)
    }
}
