import Foundation

/// The event calendar: what the game doubles today, read off the clock.
///
/// The genre runs a calendar — a double-reward weekend on a rotating
/// dungeon, a 2× experience day, half-energy days, a special login week —
/// and the calendar is the reason to open the app today rather than
/// Saturday. This game has no server, so the calendar is BAKED IN and
/// DETERMINISTIC FROM THE DATE: the weekdays are a fixed rota, the weekend's
/// headline rotates by the ISO week, every fourth week is the Festival with
/// a gift a day, and the only thing the save holds is which gifts were
/// claimed (`Player.eventGiftsClaimed`). `Docs/EVENTS.md` has the options
/// and the choice; `tools/balance.py --events` measures the week.
///
/// The clock is the player's own calendar day, read through an ISO-8601
/// calendar (Monday first), because every other daily thing in the game —
/// the missions, the login streak, the arena's refresh — keeps his day too.
/// `calendar` is the one place that is decided.

/// The numbers. Mirrored in `tools/balance.py` as `EVENTS`; change both.
enum EventTuning {
    /// Monday: every settled clear's drachma.
    static let drachma = 2.0
    /// Tuesday: unit and summoner experience on every clear.
    static let experience = 2.0
    /// Wednesday: a campaign stage's energy, rounded up (3 → 2, 4 → 2, 6 → 3).
    static let energy = 0.5
    /// Thursday: arena laurels, won or lost.
    static let laurels = 2.0
    /// The weekend's Hall: every essence roll that hits pays this many times
    /// the amount. An amount, not a chance — Mid essence already drops at
    /// 100% from B5, so a doubled chance would double nothing.
    static let essence = 2
    /// The weekend's Labyrinth: the relic roll is made this many times. A
    /// level drops a relic on EVERY run, so "double chance" would be nothing
    /// and "two relics" is what the genre's Reward ×2 means.
    static let relicRolls = 2
}

/// What an event changes. The payloads say WHERE: the Hall of this element,
/// this Labyrinth.
enum EventKind: Hashable, Sendable {
    case doubleDrachma
    case doubleExperience
    case halfEnergyCampaign
    case arenaLaurelsBoost
    case doubleEssence(Element)
    case doubleRelics(labyrinth: String)
    /// The Festival's daily gift.
    case loginGift

    /// A stable key: ids, the balance mirror, the tour.
    var key: String {
        switch self {
        case .doubleDrachma: return "drachma"
        case .doubleExperience: return "experience"
        case .halfEnergyCampaign: return "energy"
        case .arenaLaurelsBoost: return "laurels"
        case .doubleEssence(let element): return "essence_\(element.rawValue)"
        case .doubleRelics(let labyrinth): return "relics_\(labyrinth)"
        case .loginGift: return "gift"
        }
    }

    /// The constant the kind applies while it is on; 1 for the gift.
    var multiplier: Double {
        switch self {
        case .doubleDrachma: return EventTuning.drachma
        case .doubleExperience: return EventTuning.experience
        case .halfEnergyCampaign: return EventTuning.energy
        case .arenaLaurelsBoost: return EventTuning.laurels
        case .doubleEssence: return Double(EventTuning.essence)
        case .doubleRelics: return Double(EventTuning.relicRolls)
        case .loginGift: return 1
        }
    }

    /// "2×", "½", "Gift": what a badge prints beside the glyph.
    var multiplierLabel: String {
        switch self {
        case .halfEnergyCampaign: return EventTuning.energy == 0.5 ? "½" : "×\(EventTuning.energy)"
        case .loginGift: return "Gift"
        default:
            let value = multiplier
            return value == value.rounded() ? "\(Int(value))×" : String(format: "%.1f×", value)
        }
    }

    var title: String {
        switch self {
        case .doubleDrachma: return "Double Drachma"
        case .doubleExperience: return "Double Experience"
        case .halfEnergyCampaign: return "Half-Energy Campaign"
        case .arenaLaurelsBoost: return "Double Laurels"
        case .doubleEssence(let element): return "\(EventKind.hallName(element)) ×\(EventTuning.essence)"
        case .doubleRelics(let labyrinth): return "\(EventKind.labyrinthName(labyrinth)) ×\(EventTuning.relicRolls)"
        case .loginGift: return "Festival of the Gods"
        }
    }

    var blurb: String {
        switch self {
        case .doubleDrachma:
            return "Every stage clear pays twice the drachma, fought or swept."
        case .doubleExperience:
            return "Your units and your demigod level gain twice the experience from every clear."
        case .halfEnergyCampaign:
            return "Campaign stages cost half their energy, rounded up. The Halls, the Labyrinth and the Tower keep their price."
        case .arenaLaurelsBoost:
            return "Arena battles pay twice the laurels, won or lost."
        case .doubleEssence(let element):
            return "\(EventKind.hallName(element)) drops twice the essence on every floor, this weekend only."
        case .doubleRelics(let labyrinth):
            return "Every level of \(EventKind.labyrinthName(labyrinth)) drops two relics instead of one, this weekend only."
        case .loginGift:
            return "A gift every day this week. Come back each day and claim it — a missed day is missed."
        }
    }

    /// An SF Symbol, the way `Element.glyph` and a mission's icon are.
    var glyph: String {
        switch self {
        case .doubleDrachma: return "circle.hexagongrid.fill"
        case .doubleExperience: return "arrow.up.circle.fill"
        case .halfEnergyCampaign: return "bolt.fill"
        case .arenaLaurelsBoost: return "laurel.leading"
        case .doubleEssence(let element): return element.glyph
        case .doubleRelics: return "hexagon.fill"
        case .loginGift: return "gift.fill"
        }
    }

    /// The colour, as a hex the UI turns into a `Color` (`GameEvent.color`),
    /// the way `Element.accentHex` is kept out of the UI layer.
    var accentHex: String {
        switch self {
        case .doubleDrachma: return "#B08A2E"          // Theme.gold
        case .doubleExperience: return "#4E8A72"       // Theme.verdigris
        case .halfEnergyCampaign: return "#2F7F6E"     // Theme.info
        case .arenaLaurelsBoost: return "#6B8F4E"      // Theme.laurel
        case .doubleEssence(let element): return element.accentHex
        case .doubleRelics: return "#8C6D22"           // Theme.goldDim
        case .loginGift: return "#B08A2E"
        }
    }

    static func hallName(_ element: Element) -> String {
        DungeonDatabase.halls.first(where: { $0.element == element })?.name ?? "Hall of \(element.displayName)"
    }

    static func labyrinthName(_ id: String) -> String {
        DungeonDatabase.labyrinth(id)?.name ?? "the Labyrinth"
    }
}

/// One event on the calendar: what it is and when. Built from the date and
/// never stored.
struct GameEvent: Identifiable, Equatable, Sendable {
    let kind: EventKind
    let title: String
    let blurb: String
    let start: Date
    let end: Date
    let glyph: String
    let accentHex: String
    /// "Monday", "Fri – Sun", "All week": the card's own words for its span.
    let when: String

    var id: String { "\(kind.key)@\(Int(start.timeIntervalSince1970))" }

    func isActive(at date: Date) -> Bool { start <= date && date < end }

    var multiplierLabel: String { kind.multiplierLabel }
}

/// The calendar's multipliers for one stage on one date, resolved once by
/// `CampaignService.settle` and handed to `applyRewards`, which never reads
/// a clock itself — so every test that asserts a payout stays deterministic
/// whatever day CI runs on.
struct EventBoosts: Equatable, Sendable {
    var drachma: Double = 1
    var experience: Double = 1
    var essence: Int = 1
    var relicRolls: Int = 1

    /// No event: every multiplier 1.
    static let flat = EventBoosts()

    var isAny: Bool { drachma != 1 || experience != 1 || essence != 1 || relicRolls != 1 }
}

enum EventCalendar {

    // MARK: - The rota's shape (mirrored in `tools/balance.py`)

    /// Monday is 0. The weekend headline runs from this day to the week's end.
    static let weekendStart = 4
    /// The weekday rota, Monday first; its count is `weekendStart`.
    static let weekdayRota: [EventKind] = [.doubleDrachma, .doubleExperience, .halfEnergyCampaign, .arenaLaurelsBoost]
    /// Every Nth week the weekend's headline is a Labyrinth instead of a Hall.
    static let labyrinthEvery = 4
    /// Every Nth week is the Festival: a gift a day.
    static let festivalEvery = 4

    /// The Festival's seven gifts, Monday to Sunday. About 890
    /// divinity-equivalent at the bazaar's rates — nine pantheon summons once
    /// every four weeks, against the ordinary login week's 473 (`balance.py
    /// --events` prints both).
    static let festivalGifts: [ShopService.Grant] = [
        .drachma(15_000),
        .scrolls(.mystical, 2),
        .energy(40),
        .divinity(100),
        .scrolls(.pantheonic, 1),
        .relic(grade: 5),
        .bundle([.scrolls(.pantheonic, 2), .divinity(100)]),
    ]

    // MARK: - The clock

    /// ISO 8601 — Monday first, whatever the region's setting — in the
    /// player's own time zone. Switching the whole calendar to UTC is one
    /// line here; the tests build their dates through it, so they hold in
    /// any zone.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        calendar.locale = Locale.current
        return calendar
    }

    /// Week 0 starts on Monday 1 January 2024. Counting weeks from here
    /// rather than reading the ISO week NUMBER keeps the headline's cycle
    /// continuous across the year's end, where the number restarts.
    static var epoch: Date {
        calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))
            ?? Date(timeIntervalSince1970: 1_704_067_200)
    }

    /// Monday 0 … Sunday 6.
    static func dayIndex(at date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// Whole weeks since the epoch's Monday; negative before it.
    static func weekIndex(at date: Date) -> Int {
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: epoch, to: day).day ?? 0
        return floorDivide(days, 7)
    }

    /// Monday 00:00 of the week containing the date.
    static func weekStart(at date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -dayIndex(at: date), to: day) ?? day
    }

    /// The date `days` after a day's start, DST-safe.
    static func day(_ days: Int, after start: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86_400)
    }

    /// "2026-09-21": the gift's key, in the calendar's own zone.
    static func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - The rota

    /// Whether the week's weekend is a Labyrinth's rather than a Hall's.
    static func isLabyrinthWeek(_ week: Int) -> Bool {
        let cycle = max(1, labyrinthEvery)
        return positiveModulo(week, cycle) == cycle - 1
    }

    static func isFestivalWeek(_ week: Int) -> Bool {
        let cycle = max(1, festivalEvery)
        return positiveModulo(week, cycle) == cycle - 1
    }

    /// The weekend's headline for a week: a Hall's element cycling through
    /// `Element.allCases` over the Hall weeks, a Labyrinth in the Labyrinth
    /// weeks cycling through `DungeonDatabase.labyrinths`. Consecutive Hall
    /// weeks are consecutive elements, the Labyrinth weeks stepping over
    /// them, so no Hall is skipped and none comes twice in a row.
    static func headline(week: Int) -> EventKind {
        let cycle = max(1, labyrinthEvery)
        if isLabyrinthWeek(week) {
            let labyrinths = DungeonDatabase.labyrinths.map(\.id)
            guard !labyrinths.isEmpty else { return .doubleEssence(.ember) }
            let turn = floorDivide(week, cycle)
            return .doubleRelics(labyrinth: labyrinths[positiveModulo(turn, labyrinths.count)])
        }
        let hallWeeks = week - floorDivide(week, cycle)
        let elements = Element.allCases
        return .doubleEssence(elements[positiveModulo(hallWeeks, elements.count)])
    }

    /// Every event of the week containing the date, in calendar order: the
    /// Festival first when it is one, then Monday to Thursday, then the
    /// weekend's headline. Active and upcoming alike; nothing is filtered.
    static func events(at date: Date = Date()) -> [GameEvent] {
        let week = weekIndex(at: date)
        let monday = weekStart(at: date)
        var events: [GameEvent] = []
        if isFestivalWeek(week) {
            events.append(make(.loginGift, start: monday, end: day(7, after: monday), when: "All week"))
        }
        for (index, kind) in weekdayRota.enumerated() where index < weekendStart {
            events.append(make(kind, start: day(index, after: monday), end: day(index + 1, after: monday), when: weekdayName(index)))
        }
        let span = weekendStart < 6 ? "\(shortWeekdayName(weekendStart)) – \(shortWeekdayName(6))" : shortWeekdayName(6)
        events.append(make(headline(week: week), start: day(weekendStart, after: monday), end: day(7, after: monday), when: span))
        return events
    }

    /// The events on at this moment.
    static func active(at date: Date = Date()) -> [GameEvent] {
        events(at: date).filter { $0.isActive(at: date) }
    }

    /// The rest of this week.
    static func upcoming(at date: Date = Date()) -> [GameEvent] {
        events(at: date).filter { $0.start > date }
    }

    static func isActive(_ kind: EventKind, at date: Date = Date()) -> Bool {
        active(at: date).contains { $0.kind == kind }
    }

    /// The kind's constant while it is on, 1 otherwise.
    static func multiplier(for kind: EventKind, at date: Date = Date()) -> Double {
        isActive(kind, at: date) ? kind.multiplier : 1
    }

    /// The Festival: this week's when it is one, else the next.
    static func nextFestival(after date: Date = Date()) -> GameEvent {
        let week = weekIndex(at: date)
        let monday = weekStart(at: date)
        for offset in 0..<max(1, festivalEvery) where isFestivalWeek(week + offset) {
            let start = day(7 * offset, after: monday)
            return make(.loginGift, start: start, end: day(7, after: start), when: "All week")
        }
        return make(.loginGift, start: monday, end: day(7, after: monday), when: "All week")
    }

    /// Next week's weekend headline, for "next weekend" on the Events screen.
    static func nextHeadline(after date: Date = Date()) -> GameEvent {
        let week = weekIndex(at: date) + 1
        let monday = day(7, after: weekStart(at: date))
        let span = weekendStart < 6 ? "\(shortWeekdayName(weekendStart)) – \(shortWeekdayName(6))" : shortWeekdayName(6)
        return make(headline(week: week), start: day(weekendStart, after: monday), end: day(7, after: monday), when: span)
    }

    // MARK: - What the game pays

    /// A campaign stage's energy on the date: half, rounded up, never under
    /// one, on the half-energy day; the base otherwise. `energyCost(for:at:)`
    /// adds the gate that keeps the Halls, the Labyrinth, the Tower and the
    /// Titans at full price.
    static func energyCost(base: Int, at date: Date = Date()) -> Int {
        guard isActive(.halfEnergyCampaign, at: date) else { return base }
        return max(1, Int((Double(base) * EventTuning.energy).rounded(.up)))
    }

    /// A stage is "campaign" when its chapter is on the road; a tier suffix
    /// (`duat_1@hard`) still counts, a Hall or a Labyrinth level does not.
    static func isCampaignStage(_ stage: Stage) -> Bool {
        StageDatabase.chapterOrder(of: stage.chapterID) > 0
    }

    static func energyCost(for stage: Stage, at date: Date = Date()) -> Int {
        guard isCampaignStage(stage) else { return stage.energyCost }
        return energyCost(base: stage.energyCost, at: date)
    }

    /// The multipliers a clear of this stage takes on this date.
    static func boosts(for stage: Stage, at date: Date = Date()) -> EventBoosts {
        var boosts = EventBoosts()
        boosts.drachma = multiplier(for: .doubleDrachma, at: date)
        boosts.experience = multiplier(for: .doubleExperience, at: date)
        if let hall = DungeonDatabase.hall(containing: stage), isActive(.doubleEssence(hall.element), at: date) {
            boosts.essence = EventTuning.essence
        }
        if let labyrinth = DungeonDatabase.labyrinth(containing: stage),
           isActive(.doubleRelics(labyrinth: labyrinth.id), at: date) {
            boosts.relicRolls = EventTuning.relicRolls
        }
        return boosts
    }

    // MARK: - The Festival's gift

    /// One id per date, so a gift claims once however often the screen opens.
    static func giftID(for date: Date) -> String { "gift_" + dayKey(date) }

    /// The day's gift, or nil outside a Festival week.
    static func gift(at date: Date = Date()) -> ShopService.Grant? {
        guard isFestivalWeek(weekIndex(at: date)), !festivalGifts.isEmpty else { return nil }
        return festivalGifts[min(festivalGifts.count - 1, dayIndex(at: date))]
    }

    static func isGiftClaimed(player: Player, at date: Date = Date()) -> Bool {
        player.eventGiftsClaimed?.contains(giftID(for: date)) ?? false
    }

    /// One when today's gift is unclaimed, for the badge on the island.
    static func claimableCount(player: Player, at date: Date = Date()) -> Int {
        gift(at: date) != nil && !isGiftClaimed(player: player, at: date) ? 1 : 0
    }

    enum EventError: Error, LocalizedError {
        case noGiftToday
        case alreadyClaimed

        var errorDescription: String? {
            switch self {
            case .noGiftToday: return "There is no gift today."
            case .alreadyClaimed: return "Today's gift is already claimed."
            }
        }
    }

    /// Pays the day's gift once. The save keeps only the last few weeks of
    /// ids: a past date can never be claimed again, so nothing older matters.
    @discardableResult
    static func claimGift(player: inout Player, rng: inout SeededRandom, at date: Date = Date()) throws -> [ShopService.Grant] {
        guard let gift = gift(at: date) else { throw EventError.noGiftToday }
        guard !isGiftClaimed(player: player, at: date) else { throw EventError.alreadyClaimed }
        var claimed = player.eventGiftsClaimed ?? []
        claimed.append(giftID(for: date))
        if claimed.count > 28 { claimed.removeFirst(claimed.count - 28) }
        player.eventGiftsClaimed = claimed
        return ShopService.grant(gift, to: &player, rng: &rng)
    }

    // MARK: - Helpers

    private static func make(_ kind: EventKind, start: Date, end: Date, when: String) -> GameEvent {
        GameEvent(
            kind: kind, title: kind.title, blurb: kind.blurb, start: start, end: end,
            glyph: kind.glyph, accentHex: kind.accentHex, when: when
        )
    }

    /// "Monday" for 0 … "Sunday" for 6, in the calendar's locale.
    static func weekdayName(_ index: Int) -> String {
        let symbols = calendar.weekdaySymbols
        guard symbols.count == 7 else { return "Day \(index + 1)" }
        return symbols[(index + 1) % 7]
    }

    static func shortWeekdayName(_ index: Int) -> String {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return "D\(index + 1)" }
        return symbols[(index + 1) % 7]
    }

    /// `a mod n` in 0..<n for a negative `a` as well.
    static func positiveModulo(_ a: Int, _ n: Int) -> Int {
        let n = max(1, n)
        return ((a % n) + n) % n
    }

    /// Division rounded toward minus infinity, so the weeks before the epoch
    /// count down without a doubled week 0.
    static func floorDivide(_ a: Int, _ n: Int) -> Int {
        let n = max(1, n)
        return (a - positiveModulo(a, n)) / n
    }
}
