import Foundation

// MARK: - The Draft Arena (2026-09-23; Docs/DRAFT.md)
//
// Summoners War's World Arena draft, fought offline against a demigod the
// game plays. Each side drafts FIVE from its own box in the genre's
// 1-2-2-2-2-1 snake — one pick, then two each way, then one — each side
// strikes one of the other's five, each crowns a leader from the four it has
// left, and the fours fight in the arena's mode. The rating is Elo over five
// crowns of the Panhellenic games, the paid bouts and the weekly chest are
// laurels and scrolls, and DRAFT.md has the research, the options, the
// choice and every number (pinned in `DraftTests`; `tools/balance.py` does
// not mirror them yet).

/// Whose pick, whose ban.
enum DraftSide: String, Codable, Sendable {
    case player
    case rival

    var other: DraftSide { self == .player ? .rival : .player }
}

// MARK: - The crowns

/// The Draft Arena's ranks: the crowns of the four Panhellenic games, and the
/// PERIODONIKES — the athlete who had won all four, the circuit's victor. The
/// fifth rank is a title, not a crown. Never "Demigod": that is the player's
/// own noun (`ArenaTests.testNoRankWearsThePlayersNoun`).
///
/// A tier is derived from `DraftRecord.rating` and never stored.
enum DraftTier: Int, Codable, CaseIterable, Identifiable, Sendable {
    case nemean = 0
    case isthmian
    case pythian
    case olympic
    case periodonikes

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .nemean: return "Nemean"
        case .isthmian: return "Isthmian"
        case .pythian: return "Pythian"
        case .olympic: return "Olympic"
        case .periodonikes: return "Periodonikes"
        }
    }

    /// What the games crowned a victor with.
    var crown: String {
        switch self {
        case .nemean: return "Crown of wild celery"
        case .isthmian: return "Crown of pine"
        case .pythian: return "Crown of laurel"
        case .olympic: return "Crown of olive"
        case .periodonikes: return "Victor of all four games"
        }
    }

    /// The rating that enters the tier, and the floor a loss cannot take the
    /// rating under within an Olympiad (the arena's rule, and Summoners
    /// War's for its lower grades).
    var threshold: Int {
        switch self {
        case .nemean: return 0
        case .isthmian: return 1_100
        case .pythian: return 1_250
        case .olympic: return 1_450
        case .periodonikes: return 1_700
        }
    }

    /// Light enough to read on the dark well and on glass.
    var accentHex: String {
        switch self {
        case .nemean: return "#8FBF6A"
        case .isthmian: return "#4FB3AE"
        case .pythian: return "#79A6EA"
        case .olympic: return "#E8B04F"
        case .periodonikes: return "#EE6F62"
        }
    }

    var numeral: String {
        switch self {
        case .nemean: return "I"
        case .isthmian: return "II"
        case .pythian: return "III"
        case .olympic: return "IV"
        case .periodonikes: return "V"
        }
    }

    /// Laurels a WON paid bout pays here: 15, 20, 25, 30, 35. A draft bout is
    /// two to three arena attacks' time, and five a day pay (`DraftService
    /// .paidBoutsPerDay`), so a week of it pays about 70% of a week of ten
    /// arena attacks a day at the peer arena tier (DRAFT.md, *The purse*).
    var laurelsForWin: Int { 15 + 5 * rawValue }

    /// How strong the rival's box is against the player's own best five:
    /// 0.8 of it on the first crown, level on the laurel, 1.2 on the last.
    /// The rating finds where a demigod's drafting holds its own.
    var rivalStrength: Double { 0.80 + 0.10 * Double(rawValue) }

    /// The arena tier a standing here is weighed against in the purse's
    /// arithmetic (`DraftService.arenaWeeklyLaurels`): index for index.
    var arenaPeer: ArenaTier { ArenaTier(rawValue: rawValue) ?? .initiate }

    /// The week's chest when this is the crown a finished week closed on.
    var chest: DraftChest {
        switch self {
        case .nemean:
            return DraftChest(tier: self, laurels: 60, scrolls: [DraftScroll(scroll: .mystical, count: 1)])
        case .isthmian:
            return DraftChest(tier: self, laurels: 100, scrolls: [DraftScroll(scroll: .pantheonic, count: 1)])
        case .pythian:
            return DraftChest(tier: self, laurels: 150, scrolls: [
                DraftScroll(scroll: .pantheonic, count: 1), DraftScroll(scroll: .mystical, count: 1),
            ])
        case .olympic:
            return DraftChest(tier: self, laurels: 220, scrolls: [DraftScroll(scroll: .pantheonic, count: 2)])
        case .periodonikes:
            return DraftChest(tier: self, laurels: 300, scrolls: [
                DraftScroll(scroll: .pantheonic, count: 1), DraftScroll(scroll: .lightDark, count: 1),
            ])
        }
    }

    var next: DraftTier? { DraftTier(rawValue: rawValue + 1) }

    static func tier(forRating rating: Int) -> DraftTier {
        allCases.last(where: { rating >= $0.threshold }) ?? .nemean
    }
}

/// Some scrolls in a chest.
struct DraftScroll: Equatable, Sendable {
    var scroll: ScrollType
    var count: Int
}

/// What a finished week pays for the crown it closed on.
struct DraftChest: Equatable, Sendable {
    var tier: DraftTier
    var laurels: Int
    var scrolls: [DraftScroll]
}

// MARK: - The save

/// The player's standing in the Draft Arena: `Player.draft`, Optional on the
/// player. Every field has a default and this version writes them all; a
/// field added after this one must be Optional, the house rule.
struct DraftRecord: Codable, Equatable, Sendable {
    var rating: Int = DraftService.startingRating
    var highestRating: Int = DraftService.startingRating
    var wins: Int = 0
    var losses: Int = 0
    /// Bouts fought, ever: the placement's larger swing reads it, and the
    /// waiting rival's seed moves with it (`DraftService.sessionSeed`).
    var bouts: Int = 0
    /// The calendar day `paidToday` counts (`EventCalendar.dayKey`).
    var dayKey: String = ""
    var paidToday: Int = 0
    /// The week (`EventCalendar.weekIndex`) `boutsThisWeek` counts; nil until
    /// the record is first brought up to date.
    var week: Int? = nil
    var boutsThisWeek: Int = 0
    /// A finished week's chest waiting to be claimed: the crown it pays and
    /// the week it was earned in. One waits at most; a later week's better
    /// crown replaces a worse one, never the other way.
    var chestTier: Int? = nil
    var chestWeek: Int? = nil

    var tier: DraftTier { DraftTier.tier(forRating: rating) }
    var pendingChest: DraftChest? { chestTier.flatMap { DraftTier(rawValue: $0) }?.chest }
}

// MARK: - The draft

/// A demigod the game plays: a name, a rating, and the box it drafts from,
/// built at the player's own strength and leaned on by the player's crown.
struct DraftRival: Sendable {
    var name: String
    var rating: Int
    /// `ArenaService`'s recipe strength the box was built at (level, grade,
    /// relics, skills, awakening), found to match the player's best five.
    var strength: Double
    var box: [ResolvedUnit]

    var tier: DraftTier { DraftTier.tier(forRating: rating) }
}

/// Why the rival took, struck or crowned a unit — the heuristic in words.
enum DraftReason: Equatable, Sendable {
    /// Its element beats these of the other side's picks.
    case counters([String])
    /// The side had no one who heals.
    case healer
    /// The side had no one to stand in front.
    case tank
    /// The strongest left, or the other side's strongest.
    case strongest
    /// The leader skill that covers the most of the four.
    case leader
}

/// One of the ten picks, in the order they were made.
struct DraftPick: Identifiable, Equatable, Sendable {
    var order: Int
    var side: DraftSide
    var unitID: UUID
    var reason: DraftReason? = nil

    var id: Int { order }
}

/// A decision of the heuristic: the unit and why.
struct DraftChoice: Equatable, Sendable {
    var unitID: UUID
    var reason: DraftReason
}

enum DraftPhase: Equatable, Sendable {
    /// The coin is in the air.
    case toss
    /// The ten picks.
    case picking
    /// Each side strikes one of the other's five.
    case banning
    /// Each side crowns one of its four; then the fight.
    case leaders
}

/// The CI tour's three frames of a board mid-draft (`DraftService
/// .scriptedSession`): two picks each with the player's turn open, the ban
/// phase with a strike waiting, and the leaders with both bans landed.
enum DraftTourStage: String, CaseIterable, Sendable {
    case picks
    case bans
    case leaders
}

/// One draft from the toss to the crowns. A value: the board holds it and
/// every step returns a new one, so a test can play a draft through without a
/// screen and the tour can stop one anywhere.
struct DraftSession: Sendable {
    let seed: UInt64
    let firstPicker: DraftSide
    /// The player's units, strongest first.
    let playerBox: [ResolvedUnit]
    let rival: DraftRival

    private(set) var phase: DraftPhase = .toss
    private(set) var picks: [DraftPick] = []
    /// The rival unit the player strikes.
    private(set) var playerBan: UUID? = nil
    /// The player's unit the rival strikes. SEALED the moment the tenth pick
    /// lands, from the ten picks alone, so it can never read the player's —
    /// the genre's bans are simultaneous.
    private(set) var rivalBan: UUID? = nil
    private(set) var rivalBanReason: DraftReason? = nil
    private(set) var playerLeader: UUID? = nil
    private(set) var rivalLeader: UUID? = nil

    init(seed: UInt64, firstPicker: DraftSide, playerBox: [ResolvedUnit], rival: DraftRival) {
        self.seed = seed
        self.firstPicker = firstPicker
        self.playerBox = playerBox
        self.rival = rival
    }

    /// Who makes each of the ten picks: 1-2-2-2-2-1 from the coin's winner.
    var order: [DraftSide] { DraftService.pickOrder(first: firstPicker) }

    /// The side on the clock while the picks are open.
    var sideToPick: DraftSide? {
        guard phase == .picking, picks.count < order.count else { return nil }
        return order[picks.count]
    }

    /// How many picks the side on the clock still has in this turn.
    var picksLeftInTurn: Int {
        guard let side = sideToPick else { return 0 }
        let sides = order
        var count = 0
        var index = picks.count
        while index < sides.count, sides[index] == side {
            count += 1
            index += 1
        }
        return count
    }

    func box(_ side: DraftSide) -> [ResolvedUnit] { side == .player ? playerBox : rival.box }

    func unit(_ id: UUID) -> ResolvedUnit? {
        playerBox.first(where: { $0.id == id }) ?? rival.box.first(where: { $0.id == id })
    }

    /// A side's picks, in the order they were made.
    func picked(_ side: DraftSide) -> [ResolvedUnit] {
        let pool = box(side)
        return picks.filter { $0.side == side }.compactMap { pick in pool.first(where: { $0.id == pick.unitID }) }
    }

    func pick(of unitID: UUID) -> DraftPick? { picks.first(where: { $0.unitID == unitID }) }

    func isPicked(_ unitID: UUID) -> Bool { picks.contains(where: { $0.unitID == unitID }) }

    /// Whether `side` may take the unit: its own, not taken, and no unit of
    /// the same monster already on that side — Summoners War's rule; two
    /// elements of one family are two monsters.
    func canPick(_ unitID: UUID, for side: DraftSide) -> Bool {
        guard let candidate = box(side).first(where: { $0.id == unitID }), !isPicked(unitID) else { return false }
        return !picked(side).contains(where: { $0.blueprint.id == candidate.blueprint.id })
    }

    /// The unit of `side` the other side struck, once it is known.
    func struck(_ side: DraftSide) -> UUID? {
        side == .player ? rivalBan : playerBan
    }

    /// A side's picks less the one struck: the four that fight.
    func survivors(_ side: DraftSide) -> [ResolvedUnit] {
        let out = phase == .leaders ? struck(side) : nil
        return picked(side).filter { $0.id != out }
    }

    func leader(_ side: DraftSide) -> UUID? { side == .player ? playerLeader : rivalLeader }

    /// The four that fight, the crowned one first: `BattleEngine.buildSide`
    /// reads the leader off the first place.
    func lineup(_ side: DraftSide) -> [ResolvedUnit] {
        var four = survivors(side)
        guard let crowned = leader(side), let index = four.firstIndex(where: { $0.id == crowned }) else { return four }
        let chosen = four.remove(at: index)
        four.insert(chosen, at: 0)
        return four
    }

    /// Everything a fight needs: both bans in, both leaders crowned.
    var isReady: Bool {
        phase == .leaders && playerLeader != nil && rivalLeader != nil
            && survivors(.player).count == DraftService.fightSize
            && survivors(.rival).count == DraftService.fightSize
    }

    /// The coin has landed; the first pick is open.
    mutating func beginPicking() {
        if phase == .toss { phase = .picking }
    }

    /// One pick for the side on the clock. False when the unit cannot be
    /// taken. The tenth seals the rival's ban.
    @discardableResult
    mutating func pick(_ unitID: UUID, reason: DraftReason? = nil) -> Bool {
        guard let side = sideToPick, canPick(unitID, for: side) else { return false }
        picks.append(DraftPick(order: picks.count, side: side, unitID: unitID, reason: reason))
        if picks.count == order.count {
            phase = .banning
            if let sealed = DraftService.banChoice(against: .player, in: self) {
                rivalBan = sealed.unitID
                rivalBanReason = sealed.reason
            }
        }
        return true
    }

    /// The rival's next pick, by its heuristic; nil when it is not on the
    /// clock.
    @discardableResult
    mutating func rivalPicks() -> DraftPick? {
        guard sideToPick == .rival, let choice = DraftService.choice(for: .rival, in: self) else { return nil }
        guard pick(choice.unitID, reason: choice.reason) else { return nil }
        return picks.last
    }

    /// The player strikes one of the rival's five: both bans land together,
    /// the rival crowns its leader and the player's is suggested.
    @discardableResult
    mutating func ban(_ rivalUnitID: UUID) -> Bool {
        guard phase == .banning, picked(.rival).contains(where: { $0.id == rivalUnitID }) else { return false }
        playerBan = rivalUnitID
        phase = .leaders
        rivalLeader = DraftService.leaderChoice(for: survivors(.rival))?.unitID
        playerLeader = DraftService.leaderChoice(for: survivors(.player))?.unitID
        return true
    }

    /// The player crowns one of his four.
    @discardableResult
    mutating func crown(_ unitID: UUID) -> Bool {
        guard phase == .leaders, survivors(.player).contains(where: { $0.id == unitID }) else { return false }
        playerLeader = unitID
        return true
    }
}

/// A drafted fight, as `BattleContext.draft` carries it: both fours in their
/// order and what the settle and the reckoning read.
struct DraftBout: Identifiable, Sendable {
    let id: String
    let rivalName: String
    let rivalRating: Int
    let playerTeam: [ResolvedUnit]
    let rivalTeam: [ResolvedUnit]
    /// Names, for the words after the fight.
    let playerBanned: String?
    let rivalBanned: String?
}

/// What a settled bout did to the record and the wallet.
struct DraftSettlement: Equatable, Sendable {
    var outcome: BattleOutcome
    var ratingBefore: Int
    var ratingAfter: Int
    var laurels: Int
    var tierBefore: DraftTier
    var tierAfter: DraftTier
    /// Paid bouts still to come today after this one.
    var paidBoutsLeft: Int

    var ratingDelta: Int { ratingAfter - ratingBefore }
    var promoted: Bool { tierAfter.rawValue > tierBefore.rawValue }
}

// MARK: - The rules

enum DraftService {

    // MARK: The shape of a draft

    /// Five a side, drafted from each side's own box.
    static let picksPerSide = 5
    /// And four fight, the arena's team.
    static let fightSize = ArenaService.teamSize
    /// One pick, then two each way, then one: Summoners War's World Arena and
    /// Epic Seven's both.
    static let turnSizes = [1, 2, 2, 2, 2, 1]
    /// The rival's box: enough to answer a need and to counter.
    static let boxSize = 14
    /// At most this many light or dark forms in a rival's box: they are the
    /// Light & Dark scroll's premium (`Element.isLightOrDark`).
    static let lightDarkCap = 2

    static func pickOrder(first: DraftSide) -> [DraftSide] {
        var order: [DraftSide] = []
        var side = first
        for size in turnSizes {
            order += Array(repeating: side, count: size)
            side = side.other
        }
        return order
    }

    // MARK: The rating (Elo)

    /// Where a demigod starts: Summoners War's 1,000 victory points.
    static let startingRating = 1_000
    /// The swing of an even bout: ±16 at equal ratings.
    static let standardK = 32
    /// The first bouts swing wider, so a demigod finds his crown quickly.
    static let placementK = 48
    static let placementBouts = 10
    /// An Olympiad: the ladder's season, in weeks. At its turn the rating is
    /// pulled halfway back to the start (`seasonReset`).
    static let seasonWeeks = 4

    static func expectedScore(rating: Int, against rival: Int) -> Double {
        let gap = Double(rival - rating) / 400
        return 1 / (1 + pow(10, gap))
    }

    /// Elo's step, rounded, never nothing for a win or a loss.
    static func ratingDelta(score: Double, rating: Int, rivalRating: Int, k: Int) -> Int {
        let expected = expectedScore(rating: rating, against: rivalRating)
        let raw = Double(k) * (score - expected)
        let step = Int(raw.rounded())
        if score >= 1 { return max(1, step) }
        if score <= 0 { return min(-1, step) }
        return step
    }

    static func season(ofWeek week: Int) -> Int {
        EventCalendar.floorDivide(week, seasonWeeks)
    }

    /// Halfway back to the start, never under it.
    static func seasonReset(_ rating: Int) -> Int {
        startingRating + max(0, rating - startingRating) / 2
    }

    // MARK: The purse

    /// The first five bouts of a day pay laurels; every bout moves the rating
    /// and counts toward the week's chest.
    static let paidBoutsPerDay = 5
    /// A lost paid bout pays this (the arena pays three).
    static let laurelsForLoss = 5
    /// A week pays its chest when this many bouts were fought in it.
    static let chestMinimumBouts = 3
    /// The arena's pay for a lost attack: a literal in
    /// `ArenaService.applyResult`, mirrored here for the purse's arithmetic
    /// and pinned against it in `DraftTests`.
    static let arenaLaurelsForLoss = 3

    /// A week of paid draft bouts at `winRate`, the chest included, in
    /// laurels: what DRAFT.md's purse table prints. Events are left out; the
    /// arena doubles on Thursday as the draft does.
    static func weeklyLaurels(tier: DraftTier, winRate: Double) -> Int {
        let perBout = winRate * Double(tier.laurelsForWin) + (1 - winRate) * Double(laurelsForLoss)
        let bouts = Double(paidBoutsPerDay * 7)
        return Int((perBout * bouts).rounded()) + tier.chest.laurels
    }

    /// The same week with the chest's scrolls priced at the laurel exchange.
    static func weeklyValue(tier: DraftTier, winRate: Double) -> Int {
        let scrolls = tier.chest.scrolls.reduce(0) { $0 + laurelValue(of: $1.scroll) * $1.count }
        return weeklyLaurels(tier: tier, winRate: winRate) + scrolls
    }

    /// A week of arena attacks at `winRate`, `attacksPerDay` a day.
    static func arenaWeeklyLaurels(tier: ArenaTier, winRate: Double, attacksPerDay: Int) -> Int {
        let perFight = winRate * Double(ArenaService.laurelsForWin(tier: tier)) + (1 - winRate) * Double(arenaLaurelsForLoss)
        let fights = Double(attacksPerDay * 7)
        return Int((perFight * fights).rounded())
    }

    /// A scroll's worth in laurels: the exchange's own price where it sells
    /// one (a Pantheon Scroll 150, Light & Dark 250), else its divinity
    /// price at the exchange's rate for a Pantheon Scroll.
    static func laurelValue(of scroll: ScrollType) -> Int {
        let exchange = ShopService.items.first { item in
            item.section == .laurels && item.price.currency == .laurels && item.grant == .scrolls(scroll, 1)
        }
        if let exchange { return exchange.price.amount }
        let pantheonLaurels = ShopService.items.first { item in
            item.section == .laurels && item.grant == .scrolls(.pantheonic, 1)
        }?.price.amount ?? 150
        let pantheonDivinity = ScrollType.pantheonic.divinityPrice ?? 100
        let divinity = scroll.divinityPrice ?? 0
        return divinity * pantheonLaurels / max(1, pantheonDivinity)
    }

    // MARK: Bringing a record up to date

    /// A new day refills the paid bouts; a new week banks the finished week's
    /// chest (three bouts or more) and starts the count again; a new Olympiad
    /// pulls the rating halfway back. True when anything changed.
    @discardableResult
    static func rollOver(_ record: inout DraftRecord, now: Date) -> Bool {
        var changed = false
        let today = EventCalendar.dayKey(now)
        if record.dayKey != today {
            record.dayKey = today
            record.paidToday = 0
            changed = true
        }
        let week = EventCalendar.weekIndex(at: now)
        guard let recorded = record.week else {
            record.week = week
            return true
        }
        guard week > recorded else { return changed }
        if record.boutsThisWeek >= chestMinimumBouts {
            // Tiers never fall within an Olympiad, so the crown a week closed
            // on is the best it reached.
            let earned = record.tier.rawValue
            if earned >= (record.chestTier ?? -1) {
                record.chestTier = earned
                record.chestWeek = recorded
            }
        }
        record.boutsThisWeek = 0
        if season(ofWeek: week) > season(ofWeek: recorded) {
            record.rating = seasonReset(record.rating)
        }
        record.week = week
        return true
    }

    // MARK: Settling a bout

    /// A fought bout into the record: Elo against the rival's rating (the
    /// placement's wider swing for the first ten), the tier's floor, the day's
    /// paid bouts (Thursday's Double Laurels as the arena has it), and the
    /// week's count. `now` is the calendar's; a test pins it.
    @discardableResult
    static func applyResult(_ result: BattleResult, bout: DraftBout, player: inout Player, now: Date = Date()) -> DraftSettlement {
        var record = player.draft ?? DraftRecord()
        rollOver(&record, now: now)
        let before = record.rating
        let tierBefore = record.tier
        let score: Double
        switch result.outcome {
        case .victory: score = 1
        case .draw: score = 0.5
        case .defeat: score = 0
        }
        let k = record.bouts < placementBouts ? placementK : standardK
        let step = ratingDelta(score: score, rating: before, rivalRating: bout.rivalRating, k: k)
        record.rating = max(tierBefore.threshold, before + step)
        record.highestRating = max(record.highestRating, record.rating)
        record.bouts += 1
        record.boutsThisWeek += 1
        if result.outcome == .victory {
            record.wins += 1
        } else {
            record.losses += 1
        }
        var laurels = 0
        if record.paidToday < paidBoutsPerDay {
            record.paidToday += 1
            let base = result.outcome == .victory ? record.tier.laurelsForWin : laurelsForLoss
            laurels = Int(Double(base) * EventCalendar.multiplier(for: .arenaLaurelsBoost, at: now))
            player.wallet.laurels += laurels
        }
        player.draft = record
        return DraftSettlement(
            outcome: result.outcome,
            ratingBefore: before,
            ratingAfter: record.rating,
            laurels: laurels,
            tierBefore: tierBefore,
            tierAfter: record.tier,
            paidBoutsLeft: max(0, paidBoutsPerDay - record.paidToday)
        )
    }

    /// Pays the chest that waits, once; nil when none does.
    @discardableResult
    static func claimChest(player: inout Player, now: Date = Date()) -> DraftChest? {
        var record = player.draft ?? DraftRecord()
        rollOver(&record, now: now)
        guard let chest = record.pendingChest else {
            player.draft = record
            return nil
        }
        record.chestTier = nil
        record.chestWeek = nil
        player.wallet.laurels += chest.laurels
        for part in chest.scrolls {
            player.wallet.add(part.scroll, part.count)
        }
        player.draft = record
        return chest
    }

    // MARK: Building a draft

    /// The rival waits for the demigod until he fights it: the seed is the
    /// save's lineage, the bouts fought and the week, so leaving the board and
    /// coming back finds the same coin and the same box.
    static func sessionSeed(player: Player, now: Date = Date()) -> UInt64 {
        let record = player.draft ?? DraftRecord()
        let lineage = UInt64(bitPattern: Int64(player.createdAt.timeIntervalSince1970.rounded()))
        let week = UInt64(bitPattern: Int64(EventCalendar.weekIndex(at: now)))
        let bouts = UInt64(max(0, record.bouts))
        return lineage &* 0x9E37_79B9_7F4A_7C15 &+ bouts &* 0xD6E8_FEB8_6659_FD93 &+ week &* 0xA24B_AED4_963E_E407 &+ 0x5EED
    }

    /// The player's units as the board shows them: resolved, strongest first.
    static func playerBox(_ player: Player) -> [ResolvedUnit] {
        player.units
            .compactMap { ProgressionService.resolve($0, relics: player.relics, boons: player.boons ?? []) }
            .sorted { first, second in
                first.power != second.power ? first.power > second.power : first.id.uuidString < second.id.uuidString
            }
    }

    /// Distinct monsters in a box: a draft needs five.
    static func distinctMonsters(_ box: [ResolvedUnit]) -> Int {
        Set(box.map { $0.blueprint.id }).count
    }

    static func canDraft(_ player: Player) -> Bool {
        Set(player.units.map(\.blueprintID)).count >= picksPerSide
    }

    /// A new draft: the player's box, a rival built at his strength and
    /// leaned on by his crown, and the coin. Nil when the player owns fewer
    /// than five different monsters.
    static func makeSession(player: Player, seed: UInt64, firstPicker forced: DraftSide? = nil) -> DraftSession? {
        let box = playerBox(player)
        guard distinctMonsters(box) >= picksPerSide else { return nil }
        let record = player.draft ?? DraftRecord()
        var rng = SeededRandom(seed: seed)
        let boxSeed = rng.next()
        let target = topFivePower(bestOfEachMonster(box)) * record.tier.rivalStrength
        let found = strength(forTarget: target, seed: boxSeed)
        let units = rivalBox(strength: found, seed: boxSeed)
        let name = rng.pickMutating(rivalNames) ?? "Rival"
        let rating = max(800, record.rating + rng.int(in: -50...50))
        let coin: DraftSide = rng.chance(0.5) ? .player : .rival
        let rival = DraftRival(name: name, rating: rating, strength: found, box: units)
        return DraftSession(seed: seed, firstPicker: forced ?? coin, playerBox: box, rival: rival)
    }

    /// The CI tour's board, stopped where `stage` asks, on a fixed seed with
    /// the player picking first; the player's picks are the heuristic's own
    /// choice for him.
    static func scriptedSession(player: Player, stage: DraftTourStage) -> DraftSession? {
        guard var session = makeSession(player: player, seed: tourSeed, firstPicker: .player) else { return nil }
        session.beginPicking()
        let stopAt = stage == .picks ? 4 : pickOrder(first: .player).count
        while session.picks.count < stopAt, let side = session.sideToPick {
            guard let made = choice(for: side, in: session) else { break }
            let reason: DraftReason? = side == .rival ? made.reason : nil
            if !session.pick(made.unitID, reason: reason) { break }
        }
        if stage == .leaders, let strike = banChoice(against: .rival, in: session) {
            session.ban(strike.unitID)
        }
        return session
    }

    static let tourSeed: UInt64 = 0xD4AF_2026

    /// The fight a finished draft makes; nil until it is ready.
    static func bout(from session: DraftSession) -> DraftBout? {
        guard session.isReady else { return nil }
        let banned = session.playerBan.flatMap { id in session.rival.box.first(where: { $0.id == id }) }
        let struck = session.rivalBan.flatMap { id in session.playerBox.first(where: { $0.id == id }) }
        return DraftBout(
            id: "\(session.seed)",
            rivalName: session.rival.name,
            rivalRating: session.rival.rating,
            playerTeam: session.lineup(.player),
            rivalTeam: session.lineup(.rival),
            playerBanned: banned?.name,
            rivalBanned: struck?.name
        )
    }

    /// Names for the demigods the game plays. Not the arena's challengers'.
    private static let rivalNames = [
        "Theron", "Kallisto", "Demetrios", "Ianthe", "Lykon", "Myrrine",
        "Phoibos", "Thaleia", "Xenia", "Aristaios", "Chrysa", "Evandros",
        "Nikias", "Korinna", "Timon", "Melanthe",
    ]

    // MARK: The rival's box

    /// Everything the rival may own: the summon pool less anything the
    /// battle would stage as a boss (a primordial, or three metres tall).
    static func rivalCandidates() -> [UnitBlueprint] {
        UnitDatabase.summonPool
            .compactMap { UnitDatabase.blueprint($0) }
            .filter { $0.archetype != .primordial && $0.model.height < 3.0 }
    }

    /// `ArenaService.generateTeam`'s recipe at strength `strength`: the level,
    /// grade, relic grade and level, skill levels, awakening and relic sets a
    /// challenger of that `normalized` gets. Below 0 the level keeps falling,
    /// to level 1 at about −0.31, so a young box meets a rival its own size.
    static func rivalUnit(_ blueprint: UnitBlueprint, strength: Double, rng: inout SeededRandom) -> ResolvedUnit {
        let n = min(1, max(-0.32, strength))
        let lifted = max(0, n)
        let level = max(1, Int(15 + n * 45))
        let stars = min(6, 3 + Int(lifted * 3))
        let relicGrade = min(6, 3 + Int(lifted * 3))
        let relicLevel = Int(lifted * 15)
        let unitStars = min(6, max(blueprint.naturalStars, stars))
        var unit = Unit(
            blueprint: blueprint,
            level: min(ProgressionService.maxLevel(stars: unitStars), level),
            stars: unitStars,
            awakened: lifted > 0.4 && blueprint.awakening != nil
        )
        unit.skillLevels = blueprint.skills.map { _ in max(1, Int(lifted * 5)) }
        let primary: RelicSet = blueprint.role == .attacker ? .fury : .bulwark
        let secondary: RelicSet = blueprint.role == .attacker ? .ruin : .aegis
        let relics = RelicService.generateLoadout(
            grade: relicGrade,
            primarySet: primary,
            secondarySet: secondary,
            upgradeLevel: relicLevel,
            rng: &rng
        )
        return ProgressionService.resolve(unit, blueprint: blueprint, equipped: relics)
    }

    /// The rival's fourteen: two who heal and two who stand in front first,
    /// so the heuristic can answer a need, then the rest of a shuffled pool,
    /// at most two light or dark. Each unit rolls on its own stream, so the
    /// same seed gives the same box at every strength and only the numbers
    /// move — which is what lets `strength(forTarget:seed:)` search it.
    static func rivalBox(strength: Double, seed: UInt64, size: Int = boxSize) -> [ResolvedUnit] {
        var rng = SeededRandom(seed: seed)
        let pool = rng.shuffled(rivalCandidates())
        var chosen: [UnitBlueprint] = []
        func admit(_ blueprint: UnitBlueprint) -> Bool {
            guard chosen.count < size, !chosen.contains(where: { $0.id == blueprint.id }) else { return false }
            if blueprint.element.isLightOrDark,
               chosen.filter({ $0.element.isLightOrDark }).count >= lightDarkCap {
                return false
            }
            chosen.append(blueprint)
            return true
        }
        var healers = 0
        for blueprint in pool where healers < 2 && heals(blueprint.skills) {
            if admit(blueprint) { healers += 1 }
        }
        var tanks = 0
        for blueprint in pool where tanks < 2 && isTank(blueprint.role) {
            if admit(blueprint) { tanks += 1 }
        }
        for blueprint in pool where chosen.count < size {
            _ = admit(blueprint)
        }
        var units: [ResolvedUnit] = []
        for (index, blueprint) in chosen.enumerated() {
            var stream = SeededRandom(seed: seed &+ UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15)
            units.append(rivalUnit(blueprint, strength: strength, rng: &stream))
        }
        return units
    }

    /// The strength whose box's best five stand, on average, at `target`
    /// power a unit. A bisection over the recipe on the one seed: the power
    /// climbs with the strength everywhere but the odd relic roll.
    static func strength(forTarget target: Double, seed: UInt64) -> Double {
        let floor = -0.32
        guard target > 0 else { return floor }
        if topFivePower(rivalBox(strength: 1, seed: seed)) <= target { return 1 }
        if topFivePower(rivalBox(strength: floor, seed: seed)) >= target { return floor }
        var low = floor
        var high = 1.0
        for _ in 0..<strengthSearchSteps {
            let middle = (low + high) / 2
            if topFivePower(rivalBox(strength: middle, seed: seed)) < target {
                low = middle
            } else {
                high = middle
            }
        }
        return (low + high) / 2
    }

    static let strengthSearchSteps = 7

    /// The mean power of a box's five strongest.
    static func topFivePower(_ units: [ResolvedUnit]) -> Double {
        let best = units.map(\.power).sorted(by: >).prefix(picksPerSide)
        guard !best.isEmpty else { return 0 }
        let total = best.reduce(0, +)
        return Double(total) / Double(best.count)
    }

    /// The strongest unit of each monster in a box: a draft takes one of each.
    static func bestOfEachMonster(_ box: [ResolvedUnit]) -> [ResolvedUnit] {
        var best: [String: ResolvedUnit] = [:]
        for unit in box {
            if let held = best[unit.blueprint.id], held.power >= unit.power { continue }
            best[unit.blueprint.id] = unit
        }
        return Array(best.values)
    }

    // MARK: What a unit is

    /// Heals the team or raises the fallen.
    static func heals(_ skills: [Skill]) -> Bool {
        skills.contains { skill in
            skill.utilities.contains { utility in
                switch utility {
                case .healTargetMaxHealth(_, let target), .healFromAttack(_, let target):
                    return reachesAllies(target)
                case .revive:
                    return true
                default:
                    return false
                }
            }
        }
    }

    static func heals(_ unit: ResolvedUnit) -> Bool { heals(unit.skills) }

    private static func reachesAllies(_ target: TargetSelector) -> Bool {
        switch target {
        case .allAllies, .lowestHealthAlly, .singleAlly, .otherAllies: return true
        default: return false
        }
    }

    static func isTank(_ role: CombatRole) -> Bool { role == .defender || role == .hpTank }

    static func isTank(_ unit: ResolvedUnit) -> Bool { isTank(unit.role) }

    /// `attacker` hits `defender` with the element's advantage.
    static func counters(_ attacker: Element, _ defender: Element) -> Bool {
        attacker.matchup(against: defender) == .advantage
    }

    /// The unit's leader skill, when it works in the arena.
    static func arenaLeaderSkill(_ unit: ResolvedUnit) -> LeaderSkill? {
        guard let skill = unit.blueprint.leaderSkill, skill.appliesInArena else { return nil }
        return skill
    }

    // MARK: The rival's mind

    // The heuristic, in one sentence each (DRAFT.md, *The rival's mind*):
    // a pick is worth its power against the strongest left, plus 0.30 for
    // each of the other side's picks its element beats and less 0.18 for
    // each that beats it, plus 0.45 for the first healer and 0.35 for the
    // first tank once the side has a pick, less 0.25 for a third of one role,
    // plus 0.10 for a leader skill that would reach three of the side. A ban
    // strikes the other side's biggest threat: power, 0.25 for each of the
    // striking side's picks it beats, 0.20 for an only healer. A leader is
    // the skill that reaches the most of the four at the largest bonus.

    static let counterWeight = 0.30
    static let counteredWeight = 0.18
    static let healerNeed = 0.45
    static let tankNeed = 0.35
    static let crowdPenalty = 0.25
    static let leaderWeight = 0.10
    static let threatCounterWeight = 0.25
    static let threatHealerWeight = 0.20

    /// What one candidate is worth to `side`, and the reason it would say.
    static func pickScore(_ unit: ResolvedUnit, mine: [ResolvedUnit], theirs: [ResolvedUnit], strongest: Int) -> (score: Double, reason: DraftReason) {
        let power = Double(unit.power) / Double(max(1, strongest))
        let beats = theirs.filter { counters(unit.element, $0.element) }
        let beatenBy = theirs.filter { counters($0.element, unit.element) }
        let counterPart = counterWeight * Double(beats.count) - counteredWeight * Double(beatenBy.count)
        var need = 0.0
        var needReason: DraftReason?
        if !mine.isEmpty {
            if heals(unit), !mine.contains(where: { heals($0) }) {
                need = healerNeed
                needReason = .healer
            } else if isTank(unit), !mine.contains(where: { isTank($0) }) {
                need = tankNeed
                needReason = .tank
            }
        }
        var score = power + counterPart + need
        if mine.filter({ $0.role == unit.role }).count >= 2 {
            score -= crowdPenalty
        }
        if let skill = arenaLeaderSkill(unit) {
            let reached = (mine + [unit]).filter { skill.applies(to: $0.blueprint) }.count
            if reached >= 3 { score += leaderWeight }
        }
        let reason: DraftReason
        if !beats.isEmpty, counterPart >= need, counterPart > 0 {
            reason = .counters(beats.map { captionName($0) })
        } else if let needReason {
            reason = needReason
        } else {
            reason = .strongest
        }
        return (score, reason)
    }

    /// The heuristic's pick for `side`; nil when nothing can be taken.
    static func choice(for side: DraftSide, in session: DraftSession) -> DraftChoice? {
        let candidates = session.box(side).filter { session.canPick($0.id, for: side) }
        guard !candidates.isEmpty else { return nil }
        let mine = session.picked(side)
        let theirs = session.picked(side.other)
        let strongest = candidates.map(\.power).max() ?? 1
        var best: DraftChoice?
        var bestScore = -Double.infinity
        for unit in candidates {
            let scored = pickScore(unit, mine: mine, theirs: theirs, strongest: strongest)
            if scored.score > bestScore + 1e-9 {
                bestScore = scored.score
                best = DraftChoice(unitID: unit.id, reason: scored.reason)
            }
        }
        return best
    }

    /// How much of a threat one of `victim`'s five is to the other side.
    static func threat(_ unit: ResolvedUnit, allies: [ResolvedUnit], foes: [ResolvedUnit], strongest: Int) -> (score: Double, reason: DraftReason) {
        let power = Double(unit.power) / Double(max(1, strongest))
        let beats = foes.filter { counters(unit.element, $0.element) }
        let onlyHealer = heals(unit) && allies.filter({ heals($0) }).count == 1
        var score = power + threatCounterWeight * Double(beats.count)
        if onlyHealer { score += threatHealerWeight }
        let reason: DraftReason
        if beats.count >= 2 {
            reason = .counters(beats.map { captionName($0) })
        } else if onlyHealer {
            reason = .healer
        } else {
            reason = .strongest
        }
        return (score, reason)
    }

    /// The unit of `victim`'s five the other side should strike. The rival
    /// strikes the player's with it; the board lights the player's best
    /// strike with the same sum.
    static func banChoice(against victim: DraftSide, in session: DraftSession) -> DraftChoice? {
        let targets = session.picked(victim)
        guard !targets.isEmpty else { return nil }
        let foes = session.picked(victim.other)
        let strongest = targets.map(\.power).max() ?? 1
        var best: DraftChoice?
        var bestScore = -Double.infinity
        for unit in targets {
            let scored = threat(unit, allies: targets, foes: foes, strongest: strongest)
            if scored.score > bestScore + 1e-9 {
                bestScore = scored.score
                best = DraftChoice(unitID: unit.id, reason: scored.reason)
            }
        }
        return best
    }

    /// The four's leader: the arena leader skill that reaches the most of
    /// them at the largest bonus, else the strongest.
    static func leaderChoice(for team: [ResolvedUnit]) -> DraftChoice? {
        guard !team.isEmpty else { return nil }
        var best: ResolvedUnit?
        var bestValue = 0.0
        for unit in team {
            guard let skill = arenaLeaderSkill(unit) else { continue }
            let reached = team.filter { skill.applies(to: $0.blueprint) }.count
            let value = Double(reached) * skill.amount
            if value > bestValue + 1e-9 {
                bestValue = value
                best = unit
            }
        }
        if let best { return DraftChoice(unitID: best.id, reason: .leader) }
        guard let strongest = team.max(by: { $0.power < $1.power }) else { return nil }
        return DraftChoice(unitID: strongest.id, reason: .strongest)
    }

    /// The name before its epithet — "Ares", not "Ares, Bane of Cities" —
    /// as the cards print it.
    static func captionName(_ unit: ResolvedUnit) -> String {
        unit.name.split(separator: ",", maxSplits: 1).first.map { String($0) } ?? unit.name
    }
}

// MARK: - Roles on the board

/// The board's four role filters: the combat roles with the two that stand in
/// front (a defender and a vanguard) as one.
enum DraftRole: String, CaseIterable, Identifiable, Sendable {
    case attacker
    case tank
    case support
    case controller

    var id: String { rawValue }

    init(_ role: CombatRole) {
        switch role {
        case .attacker: self = .attacker
        case .defender, .hpTank: self = .tank
        case .support: self = .support
        case .controller: self = .controller
        }
    }

    var displayName: String {
        switch self {
        case .attacker: return "Attacker"
        case .tank: return "Tank"
        case .support: return "Support"
        case .controller: return "Controller"
        }
    }

    var glyph: String {
        switch self {
        case .attacker: return "bolt.fill"
        case .tank: return "shield.fill"
        case .support: return "cross.fill"
        case .controller: return "hourglass"
        }
    }
}
