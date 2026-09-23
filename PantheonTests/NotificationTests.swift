import XCTest
import UserNotifications
@testable import Pantheon

/// The reminders (`Docs/SETTINGS.md` §1): the energy clock pinned to the
/// store's own, the quiet night, the three mornings, the one line a morning
/// and the energy reminder folded into it, and the request iOS is handed.
/// Nothing here asks iOS anything: the planner is pure, and the request is a
/// plain value object.
final class NotificationTests: XCTestCase {
    private var folder: URL!
    private var previousBase: URL?

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotificationTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        previousBase = SaveStore.baseURL
        SaveStore.baseURL = folder
    }

    override func tearDown() {
        SaveStore.baseURL = previousBase
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private var calendar: Calendar { Calendar.current }

    /// A local date, built through the calendar the planner uses, so every
    /// test holds in any time zone.
    private func local(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func wallet(energy: Int, maximum: Int = 80, tick: Date) -> Wallet {
        var wallet = Wallet()
        wallet.energy = energy
        wallet.maxEnergy = maximum
        wallet.lastEnergyTick = tick
        return wallet
    }

    private func player(energy: Int, tick: Date) -> Player {
        var player = NewGame.create().player
        player.wallet = wallet(energy: energy, tick: tick)
        return player
    }

    // MARK: - The energy clock

    /// The planner's five minutes a point are `GameStore.refreshTimedResources`'s:
    /// a second before the named minute the store is one short, on it full.
    @MainActor
    func testEnergyFillsOnTheStoresOwnClock() {
        let start = Date()
        var game = NewGame.create()
        game.player.wallet = wallet(energy: 70, tick: start)
        let expected = start.addingTimeInterval(10 * NotificationPlanner.energyInterval)
        XCTAssertEqual(NotificationPlanner.energyFullDate(wallet: game.player.wallet, now: start), expected)

        let store = GameStore(save: game, account: Account.guest(), cloudSave: nil)
        let secondBefore = expected.addingTimeInterval(-1)
        store.refreshTimedResources(now: secondBefore)
        XCTAssertEqual(store.player.wallet.energy, 79, "one short a second before the reminder")
        store.refreshTimedResources(now: expected)
        XCTAssertEqual(store.player.wallet.energy, 80, "full on the minute the reminder names")
        store.retire()
    }

    func testNoEnergyReminderWhenFullOrTooSoon() {
        let now = local(22, 12)
        XCTAssertNil(NotificationPlanner.energyFullDate(wallet: wallet(energy: 80, tick: now), now: now), "already full")
        let staleTick = now.addingTimeInterval(-86_400)
        XCTAssertNil(NotificationPlanner.energyFullDate(wallet: wallet(energy: 10, tick: staleTick), now: now),
                     "a day of refills since the last tick: full already")

        // One point short: full in five minutes, under the ten-minute lead.
        let soon = NotificationPlanner.plan(player: player(energy: 79, tick: now), enabled: [.energyFull], now: now)
        XCTAssertTrue(soon.isEmpty, "the player has only just put the phone down")

        let later = NotificationPlanner.plan(player: player(energy: 70, tick: now), enabled: [.energyFull], now: now)
        XCTAssertEqual(later.count, 1)
        XCTAssertEqual(later.first?.id, NotificationPlanner.energyID)
        XCTAssertEqual(later.first?.isPassive, false, "energy full is an ordinary alert")
    }

    // MARK: - Quiet nights and mornings

    func testNothingArrivesAtNight() {
        let eight = NotificationPlanner.morningHour
        let nextMorning = local(23, eight)
        XCTAssertEqual(NotificationPlanner.outOfQuietHours(local(22, 23, 30), calendar: calendar), nextMorning, "late evening: the next morning")
        XCTAssertEqual(NotificationPlanner.outOfQuietHours(local(22, NotificationPlanner.quietFromHour), calendar: calendar), nextMorning)
        XCTAssertEqual(NotificationPlanner.outOfQuietHours(local(23, 3), calendar: calendar), nextMorning, "small hours: that morning")
        let afternoon = local(22, 14, 20)
        XCTAssertEqual(NotificationPlanner.outOfQuietHours(afternoon, calendar: calendar), afternoon, "the day is untouched")
        XCTAssertEqual(NotificationPlanner.outOfQuietHours(nextMorning, calendar: calendar), nextMorning)
    }

    func testTheMorningsAreTheNextThreeAtEight() {
        let expected = [local(23, 8), local(24, 8), local(25, 8)]
        XCTAssertEqual(NotificationPlanner.mornings(after: local(22, 15), count: 3, calendar: calendar), expected)
        XCTAssertEqual(NotificationPlanner.mornings(after: local(22, 3), count: 3, calendar: calendar), expected,
                       "after midnight the day has already turned over: the next morning is tomorrow's")
    }

    // MARK: - The morning line

    func testTheMorningLineCarriesTheResetAndTheDaysEvent() {
        let now = local(20, 15)
        let plan = NotificationPlanner.plan(player: player(energy: 80, tick: now), enabled: [.dailyReset, .eventDays], now: now)
        XCTAssertEqual(plan.count, NotificationPlanner.morningsAhead, "one line a morning, three mornings")
        for reminder in plan {
            XCTAssertTrue(reminder.isPassive, "the morning line never lights the screen")
            XCTAssertTrue(reminder.body.contains(NotificationPlanner.resetLine))
            XCTAssertEqual(calendar.component(.hour, from: reminder.fireDate), NotificationPlanner.morningHour)
            let starting = NotificationPlanner.eventsStarting(on: reminder.fireDate, calendar: calendar)
            if let first = starting.first {
                XCTAssertEqual(reminder.title, NotificationPlanner.headline(for: first, calendar: calendar))
                XCTAssertTrue(reminder.body.contains(first.blurb))
            } else {
                XCTAssertEqual(reminder.title, NotificationPlanner.newDayTitle)
            }
        }
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count, "one identifier a morning")
    }

    /// With only the events switch on, a morning where nothing begins and no
    /// Festival gift waits has no line at all — whatever the rota says.
    func testTheEventsSwitchAloneIsSilentOnAnEmptyMorning() {
        for day in 20...27 {
            let now = local(day, 15)
            let plan = NotificationPlanner.plan(player: player(energy: 80, tick: now), enabled: [.eventDays], now: now)
            let planned = Set(plan.map(\.fireDate))
            for morning in NotificationPlanner.mornings(after: now, count: NotificationPlanner.morningsAhead, calendar: calendar) {
                let begins = !NotificationPlanner.eventsStarting(on: morning, calendar: calendar).isEmpty
                let gift = EventCalendar.gift(at: morning) != nil
                let expected: Bool = begins || gift
                let isPlanned: Bool = planned.contains(morning)
                XCTAssertEqual(isPlanned, expected, "day \(day), morning \(morning)")
            }
        }
    }

    /// Energy that fills at night is held to the morning — and, when the
    /// morning line is on, rides in it instead of arriving beside it.
    func testEnergyHeldToTheMorningRidesInTheMorningLine() {
        let now = local(22, 20)
        let evening = player(energy: 40, tick: now)   // 40 points: 3 h 20 m, so 23:20
        let alone = NotificationPlanner.plan(player: evening, enabled: [.energyFull], now: now)
        XCTAssertEqual(alone.count, 1)
        XCTAssertEqual(alone.first?.fireDate, local(23, 8), "held from 23:20 to 08:00")
        XCTAssertEqual(alone.first?.id, NotificationPlanner.energyID)

        let together = NotificationPlanner.plan(player: evening, enabled: [.energyFull, .dailyReset], now: now)
        XCTAssertFalse(together.contains { $0.id == NotificationPlanner.energyID }, "no second notification at 08:00")
        let first = together.first
        XCTAssertEqual(first?.fireDate, local(23, 8))
        XCTAssertEqual(first?.body.hasPrefix(NotificationPlanner.energyFoldLine), true)
        XCTAssertEqual(together.count, NotificationPlanner.morningsAhead)
    }

    func testNeverMoreThanTwoInADay() {
        let now = local(22, 10)
        let plan = NotificationPlanner.plan(player: player(energy: 0, tick: now),
                                            enabled: Set(ReminderKind.allCases), now: now)
        XCTAssertEqual(plan.first?.id, NotificationPlanner.energyID, "0 to 80 takes 6 h 40 m: 16:40 today")
        XCTAssertEqual(plan.first?.fireDate, local(22, 16, 40))
        var perDay: [String: Int] = [:]
        for reminder in plan { perDay[EventCalendar.dayKey(reminder.fireDate), default: 0] += 1 }
        let busiest = perDay.values.max() ?? 0
        XCTAssertLessThanOrEqual(busiest, 2)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted(), "in the order they arrive")
    }

    func testNothingIsPlannedWithEverySwitchOff() {
        let now = local(22, 10)
        XCTAssertTrue(NotificationPlanner.plan(player: player(energy: 0, tick: now), enabled: [], now: now).isEmpty)
    }

    // MARK: - What iOS is handed

    func testTheRequestIsOneCalendarTriggerOnTheMinute() throws {
        let fire = local(24, 8)
        let reminder = PlannedReminder(id: "pantheon.morning.test", title: "A title", body: "A body",
                                       fireDate: fire, isPassive: true, thread: NotificationPlanner.morningThread)
        let request = NotificationPlanner.request(for: reminder, calendar: calendar)
        XCTAssertEqual(request.identifier, "pantheon.morning.test")
        XCTAssertEqual(request.content.title, "A title")
        XCTAssertEqual(request.content.body, "A body")
        XCTAssertEqual(request.content.threadIdentifier, NotificationPlanner.morningThread)
        XCTAssertEqual(request.content.interruptionLevel, .passive)
        XCTAssertNil(request.content.sound, "a passive line makes no sound")
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        let when = calendar.date(from: trigger.dateComponents)
        XCTAssertEqual(when, fire)
    }

    func testTheSwitchesAreThePhonesAndOffUntilTurnedOn() {
        XCTAssertEqual(ReminderKind.energyFull.defaultsKey, "notifications.energyFull")
        XCTAssertEqual(Set(ReminderKind.allCases.map(\.defaultsKey)).count, ReminderKind.allCases.count)
        XCTAssertEqual(NotificationPlanner.runOutBelow, 4, "an ordinary campaign stage's price: under it, energy has run out")
    }
}
