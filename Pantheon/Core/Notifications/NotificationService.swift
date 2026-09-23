import Foundation
import UIKit
import UserNotifications

/// The three reminders a player can ask for on Settings → Notifications
/// (`Docs/SETTINGS.md` §1). Each is a switch kept on the phone, in
/// `UserDefaults` under `notifications.<raw value>`, never in the save: the
/// reminders belong to the device, as its sound and graphics do.
enum ReminderKind: String, CaseIterable {
    case energyFull
    case dailyReset
    case eventDays

    var defaultsKey: String { "notifications." + rawValue }

    var title: String {
        switch self {
        case .energyFull: return "Energy full"
        case .dailyReset: return "Daily reset"
        case .eventDays: return "Event days"
        }
    }

    var caption: String {
        switch self {
        case .energyFull: return "When your energy is back to full."
        case .dailyReset: return "New missions and the daily offering, in the morning."
        case .eventDays: return "The morning an event begins: Double Drachma, the weekend's Hall."
        }
    }
}

/// One notification the planner wants delivered.
struct PlannedReminder: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
    /// Passive (the morning line): into the list without lighting the screen
    /// or making a sound. Active (energy full): an ordinary alert.
    let isPassive: Bool
    let thread: String
}

/// What to send and when, from the save and the clock — no framework, so
/// every rule here is tested (`PantheonTests/NotificationTests.swift`).
///
/// At most one reminder when energy fills and one each morning; nothing
/// between 22:00 and 08:00 (a reminder that would land there is held to
/// 08:00, still true then, and folded into the morning line when it lands on
/// it); the next three mornings only, so a player who stops opening the game
/// hears three times and then nothing.
enum NotificationPlanner {
    /// One energy every five minutes, counted from `Wallet.lastEnergyTick`
    /// — the rule `GameStore.refreshTimedResources` applies.
    /// `NotificationTests` pins the two together; change both.
    static let energyInterval: TimeInterval = 5 * 60
    /// Energy that fills within this long of the app closing is not worth a
    /// notification: the player has only just put the phone down.
    static let minimumLead: TimeInterval = 10 * 60
    /// The quiet night, and the hour the morning line arrives.
    static let quietFromHour = 22
    static let morningHour = 8
    /// How many mornings ahead are scheduled.
    static let morningsAhead = 3
    /// An energy reminder this close before a morning line rides in it.
    static let foldWindow: TimeInterval = 30 * 60
    /// Energy under this has "run out": an ordinary campaign stage costs 4
    /// (`StageDatabase`), and the first time it happens the game offers the
    /// energy reminder (`NotificationService.noteEnergy`).
    static let runOutBelow = 4

    static let energyID = "pantheon.energy"
    static let morningPrefix = "pantheon.morning."
    static let energyThread = "pantheon.energy"
    static let morningThread = "pantheon.morning"

    static let newDayTitle = "A new day on the island"
    static let resetLine = "New missions are up and the daily offering is back at the bazaar."
    static let giftLine = "Today's Festival gift is waiting."
    static let energyFoldLine = "Your energy is full."

    // MARK: - The clocks

    /// The moment energy reaches its maximum, or nil when it is already
    /// there (or would be by now).
    static func energyFullDate(wallet: Wallet, now: Date) -> Date? {
        guard wallet.energy < wallet.maxEnergy else { return nil }
        let missing = Double(wallet.maxEnergy - wallet.energy)
        let full = wallet.lastEnergyTick.addingTimeInterval(missing * energyInterval)
        return full > now ? full : nil
    }

    /// A delivery moved out of the quiet night: from 22:00 to midnight it
    /// goes to the next 08:00, from midnight to 08:00 to that morning's.
    static func outOfQuietHours(_ date: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: date)
        if hour >= morningHour && hour < quietFromHour { return date }
        let dayStart = calendar.startOfDay(for: date)
        let morning = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: dayStart) ?? date
        if hour < morningHour { return morning }
        return calendar.date(byAdding: .day, value: 1, to: morning) ?? morning
    }

    /// 08:00 on each of the next `count` days — the mornings after the next
    /// local midnights, when the missions and the offering have turned over.
    static func mornings(after now: Date, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (1...count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: day)
        }
    }

    /// The events that BEGIN on the day of `date` (a weekday's event, the
    /// weekend's headline on its first day, the Festival on its Monday), in
    /// the calendar's order — the Festival first.
    static func eventsStarting(on date: Date, calendar: Calendar) -> [GameEvent] {
        EventCalendar.events(at: date).filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    /// "Double Drachma today", "Hall of Embers ×2 this weekend", "Festival
    /// of the Gods begins".
    static func headline(for event: GameEvent, calendar: Calendar) -> String {
        if event.kind == .loginGift { return "\(event.title) begins" }
        let days = calendar.dateComponents([.day], from: event.start, to: event.end).day ?? 1
        return days > 1 ? "\(event.title) this weekend" : "\(event.title) today"
    }

    // MARK: - The plan

    /// Everything to schedule as the app goes to the background, in the
    /// order it will arrive.
    static func plan(player: Player, enabled: Set<ReminderKind>, now: Date, calendar: Calendar = .current) -> [PlannedReminder] {
        var energyDate: Date?
        if enabled.contains(.energyFull), let full = energyFullDate(wallet: player.wallet, now: now),
           full.timeIntervalSince(now) >= minimumLead {
            energyDate = outOfQuietHours(full, calendar: calendar)
        }

        var planned: [PlannedReminder] = []
        var energyFolded = false
        if enabled.contains(.dailyReset) || enabled.contains(.eventDays) {
            for morning in mornings(after: now, count: morningsAhead, calendar: calendar) {
                var lines: [String] = []
                var title = newDayTitle
                let starting = eventsStarting(on: morning, calendar: calendar)
                if enabled.contains(.eventDays), let first = starting.first {
                    title = headline(for: first, calendar: calendar)
                    lines.append(first.blurb)
                    if starting.count > 1 { lines.append("Also today: \(starting[1].title).") }
                }
                if enabled.contains(.dailyReset) { lines.append(resetLine) }
                let festivalOpens = starting.contains { $0.kind == .loginGift }
                if EventCalendar.gift(at: morning) != nil, !festivalOpens { lines.append(giftLine) }
                // A Saturday with only the events switch on has nothing new.
                guard !lines.isEmpty else { continue }
                if let energy = energyDate, !energyFolded,
                   energy <= morning, morning.timeIntervalSince(energy) <= foldWindow {
                    lines.insert(energyFoldLine, at: 0)
                    energyFolded = true
                }
                planned.append(PlannedReminder(
                    id: morningPrefix + EventCalendar.dayKey(morning),
                    title: title,
                    body: lines.joined(separator: " "),
                    fireDate: morning,
                    isPassive: true,
                    thread: morningThread
                ))
            }
        }
        if let energy = energyDate, !energyFolded {
            planned.append(PlannedReminder(
                id: energyID,
                title: "Energy restored",
                body: "Your \(player.wallet.maxEnergy) energy is full again. The road ahead is waiting.",
                fireDate: energy,
                isPassive: false,
                thread: energyThread
            ))
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    /// The system's request for a planned reminder: a calendar trigger on
    /// the exact minute, once.
    static func request(for reminder: PlannedReminder, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.threadIdentifier = reminder.thread
        content.interruptionLevel = reminder.isPassive ? .passive : .active
        content.relevanceScore = reminder.isPassive ? 0.3 : 0.7
        if !reminder.isPassive { content.sound = .default }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }
}

/// The reminders on the phone (`Docs/SETTINGS.md` §1): the three switches,
/// iOS's permission, and the scheduling — everything cleared when the game
/// comes back to the foreground and planned afresh from the save when it
/// leaves (`AppSession.sceneWentToBackground`). iOS is asked only when a switch is
/// turned on, or through the one-time card the first time energy runs out —
/// never at launch, and nothing here runs under `-tour`.
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    /// iOS's answer, as the Settings page words it.
    enum Access: Equatable {
        case unknown
        case notAsked
        case allowed
        case denied
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var enabled: Set<ReminderKind>
    /// The card that offers the energy reminder, the first time energy runs
    /// out (`EnergyReminderCard`, laid over the game by `PantheonApp`).
    @Published private(set) var showsEnergyAsk = false

    /// Set once the card has been answered (either way) or can never apply.
    static let energyAskKey = "notifications.energyAskAnswered"

    let isTour: Bool
    private var askPending = false

    init() {
        isTour = ProcessInfo.processInfo.arguments.contains("-tour")
        enabled = Set(ReminderKind.allCases.filter { UserDefaults.standard.bool(forKey: $0.defaultsKey) })
    }

    func isOn(_ kind: ReminderKind) -> Bool { enabled.contains(kind) }

    // MARK: - The switches

    /// A switch on the Settings page. Turning one on asks iOS when it has
    /// never been asked — the moment the player can see why — and a refusal
    /// turns it back off: iOS never asks twice, so the page then offers the
    /// iPhone's own Settings.
    func set(_ kind: ReminderKind, on: Bool) async {
        guard !isTour else { return }
        guard on else {
            store(kind, false)
            return
        }
        store(kind, true)
        var answer = await NotificationService.currentAccess()
        if answer == .notAsked {
            _ = await NotificationService.requestAuthorization()
            answer = await NotificationService.currentAccess()
        }
        access = answer
        if answer != .allowed { store(kind, false) }
    }

    private func store(_ kind: ReminderKind, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: kind.defaultsKey)
        if on { enabled.insert(kind) } else { enabled.remove(kind) }
    }

    /// iOS's current answer, read when the page opens and on every return.
    func refreshAccess() async {
        guard !isTour else {
            access = .notAsked
            return
        }
        access = await NotificationService.currentAccess()
    }

    /// Pantheon's page in the iPhone's Settings app, for a player who said no
    /// to iOS and has changed his mind.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Scheduling

    /// The app is going to the background: whatever is pending is replaced
    /// by the plan for this player, when iOS allows it.
    func schedule(for player: Player?, now: Date = Date()) {
        guard !isTour else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard let player, !enabled.isEmpty else { return }
        let kinds = enabled
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            let plan = NotificationPlanner.plan(player: player, enabled: kinds, now: now)
            for reminder in plan {
                center.add(NotificationPlanner.request(for: reminder)) { error in
                    if let error {
                        NotificationService.log("could not schedule \(reminder.id): \(error.localizedDescription)")
                    }
                }
            }
            NotificationService.log("scheduled \(plan.count) reminder(s)")
        }
    }

    /// The game is back, or the account is gone: nothing stale waits in the
    /// list or on the lock screen.
    func clearAll() {
        guard !isTour else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - The first time energy runs out

    /// The store's energy, watched by `AppSession`. The first time it falls
    /// under an ordinary stage's price, while iOS has never been asked and
    /// the reminder is off, the card is shown — once it is answered, never
    /// again.
    func noteEnergy(_ energy: Int) {
        guard !isTour, !askPending, !showsEnergyAsk, energy < NotificationPlanner.runOutBelow,
              !enabled.contains(.energyFull),
              !UserDefaults.standard.bool(forKey: NotificationService.energyAskKey) else { return }
        askPending = true
        Task {
            let answer = await NotificationService.currentAccess()
            askPending = false
            guard answer == .notAsked else {
                // Already asked, from the Settings page: the question is
                // settled and the card would only repeat it.
                UserDefaults.standard.set(true, forKey: NotificationService.energyAskKey)
                return
            }
            showsEnergyAsk = true
        }
    }

    /// The card's two buttons.
    func answerEnergyAsk(remind: Bool) async {
        showsEnergyAsk = false
        UserDefaults.standard.set(true, forKey: NotificationService.energyAskKey)
        if remind { await set(.energyFull, on: true) }
    }

    // MARK: - iOS

    /// iOS's answer, read off its notification settings.
    nonisolated static func currentAccess() async -> Access {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let answer: Access
                switch settings.authorizationStatus {
                case .notDetermined: answer = .notAsked
                case .denied: answer = .denied
                case .authorized, .provisional, .ephemeral: answer = .allowed
                @unknown default: answer = .unknown
                }
                continuation.resume(returning: answer)
            }
        }
    }

    /// Alerts and sounds; never the badge, which the game does not use.
    nonisolated static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated static func log(_ line: String) {
        let stamped = "[Notifications] \(line)"
        print(stamped)
        DiagnosticsLog.shared.record(stamped)
    }
}
