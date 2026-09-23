import Foundation

// MARK: - The Codex (2026-09-23; Docs/CODEX.md)
//
// The collection book: every family of every live pantheon, each in its five
// element forms and, where the family has one, each form's awakened face —
// 830 pages on the roster of 2026-09-23. The genre's version is Summoners
// War's Monster Collection and Epic Seven's Hero Collection: everything in
// the game listed, what the player has owned lit, the rest in shadow, and a
// small reward for every new page. Docs/CODEX.md has the options that were
// weighed and the measurements the table below rests on.
//
// Nothing here is a second record of what the player owns. `Player.codex`
// has held every blueprint id ever owned since the first build (the summon,
// the mileage, the selector, the fusion, the Night Market and the starter all
// write it), so a base form's page is lit by that, by a unit in the roster
// (the tour's seed never wrote the codex) and by its own claim. An awakened
// face has no such record — an awakening writes nothing but the unit — so it
// is lit by an awakened unit in the roster or by its claim: once taken, a
// page stays lit even after the unit that earned it is fed away. The ONE new
// save field is the claims (`Player.codexClaims`).

/// Which face of a form a page records: the form as summoned, or awakened.
enum CodexFormKind: String, Codable, CaseIterable, Sendable {
    case base
    case awakened
}

/// One page of the book: a form of a family, in one of its two faces.
struct CodexEntry: Identifiable, Hashable, Sendable {
    let blueprintID: String
    let kind: CodexFormKind
    let familyKey: String
    let pantheon: Pantheon
    /// The family's natural grade, which prices the page.
    let stars: Int
    let element: Element

    /// The page's claim id: `form:<blueprint id>` or `awakened:<blueprint id>`.
    var id: String { CodexService.claimID(for: blueprintID, kind: kind) }

    var blueprint: UnitBlueprint? { UnitDatabase.blueprint(blueprintID) }
}

/// A family's row in the book: its forms by element.
struct CodexFamily: Identifiable, Sendable {
    let key: String
    /// The family's name as every form carries it ("Anubis").
    let name: String
    let pantheon: Pantheon
    let stars: Int
    /// Its job on the field, shared by its five forms ("Attacker").
    let role: CombatRole
    /// The family's collectible forms by element — all five on today's
    /// roster, fusion prizes included.
    let forms: [Element: String]
    /// Whether the family's forms have an awakened face: every 4★ and 5★.
    let awakenable: Bool

    var id: String { key }

    /// The page for one element and face, or nil when the family has none
    /// (a 3★ has no awakened face).
    func entry(_ element: Element, _ kind: CodexFormKind) -> CodexEntry? {
        guard let blueprintID = forms[element] else { return nil }
        if kind == .awakened, UnitDatabase.blueprint(blueprintID)?.awakening == nil { return nil }
        return CodexEntry(blueprintID: blueprintID, kind: kind, familyKey: key,
                          pantheon: pantheon, stars: stars, element: element)
    }

    /// Every page of the family: the five forms, then their awakened faces.
    var entries: [CodexEntry] {
        CodexFormKind.allCases.flatMap { kind in Element.allCases.compactMap { entry($0, kind) } }
    }
}

/// A pantheon's completion prizes, at a share of its pages recorded.
enum CodexTier: Int, CaseIterable, Identifiable, Sendable {
    case quarter = 25
    case half = 50
    case threeQuarters = 75
    case whole = 100

    var id: Int { rawValue }
}

/// Where a page — or a pantheon's tier — stands: not yet recorded (a tier
/// not yet reached), recorded with its reward waiting, or claimed.
enum CodexStanding: Sendable {
    case unrecorded
    case ready
    case claimed
}

/// How much of a pantheon, or of the whole book, is recorded.
struct CodexProgress: Equatable, Sendable {
    let recorded: Int
    let total: Int

    var fraction: Double { total > 0 ? Double(recorded) / Double(total) : 0 }
    /// Whole percent, rounded down: a tier is reached on the count, never on
    /// this.
    var percent: Int { total > 0 ? recorded * 100 / total : 0 }
}

/// What claiming one page pays, split so the page can say why: the form's
/// own reward, and the family's first when no page of the family has been
/// claimed yet. Paid as ONE grant of divinity.
struct CodexReward: Equatable, Sendable {
    let entry: Int
    let familyFirst: Int

    var total: Int { entry + familyFirst }
    var grants: [ShopService.Grant] { total > 0 ? [.divinity(total)] : [] }
}

/// One road to a form, for the page's "Where to get it".
struct CodexSource: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    /// A painted item (`item_<key>`) for the row's disc, or nil for the glyph.
    let itemKey: String?
    let glyph: String
}

/// One line of an awakening's bill: an essence and how many.
struct CodexEssence: Identifiable, Sendable {
    let id: String
    let count: Int
}

/// What the book knows of one save: which forms are recorded, which awakened
/// faces are, and what has been claimed. Built once per screen pass from the
/// `Player` (`CodexService.ledger(for:)`) and read for every page.
struct CodexLedger: Sendable {
    /// Blueprint ids whose form is recorded.
    let recorded: Set<String>
    /// Blueprint ids whose awakened face is recorded.
    let awakened: Set<String>
    let claims: Set<String>

    func isRecorded(_ entry: CodexEntry) -> Bool {
        switch entry.kind {
        case .base: return recorded.contains(entry.blueprintID)
        case .awakened: return awakened.contains(entry.blueprintID)
        }
    }

    func isClaimed(_ claimID: String) -> Bool { claims.contains(claimID) }

    func standing(_ entry: CodexEntry) -> CodexStanding {
        if claims.contains(entry.id) { return .claimed }
        return isRecorded(entry) ? .ready : .unrecorded
    }
}

enum CodexError: Error, LocalizedError, Equatable {
    case unknownEntry
    case notRecorded
    case alreadyClaimed
    case tierNotReached(needed: Int)

    var errorDescription: String? {
        switch self {
        case .unknownEntry: return "That page is not in the Codex."
        case .notRecorded: return "Record that form first: summon it, fuse it or awaken it."
        case .alreadyClaimed: return "Already claimed."
        case .tierNotReached(let needed): return "Record \(needed) more to reach it."
        }
    }
}

/// The book: its pages, what a save has recorded, what each page pays, and
/// where each form comes from.
enum CodexService {

    // MARK: - The table
    //
    // Measured in Docs/CODEX.md against what the rest of the game pays: a
    // first month of play records about 116 forms of 55 families and the
    // book pays about 1,540 divinity-equivalent for it, 6% of that month's
    // income; a first year about 6,700, 2.3% (`tools/codex_calib.py`, which
    // mirrors this table). Pinned by `CodexTests.testTheRewardTableIsPinned`
    // — change a number here, in the tool, in Docs/CODEX.md and in that test
    // together.

    /// Divinity for recording a form, by the family's natural grade.
    static let formDivinity: [Int: Int] = [3: 5, 4: 10, 5: 25]
    /// Divinity for recording an awakened face — more than the form itself,
    /// because an awakening is work (twenty Hall runs for a 5★'s bill) where
    /// a summon is luck.
    static let awakenedDivinity: [Int: Int] = [4: 20, 5: 40]
    /// Divinity for the first page of a family ever claimed, on top of that
    /// page's own: a new character is worth more than a new colour of one.
    static let familyFirstDivinity: [Int: Int] = [3: 5, 4: 20, 5: 50]
    /// Radiance and Umbra pages pay this many times over: the premium pair
    /// (`Element.isLightOrDark`), drawn by the Light & Dark scroll alone.
    /// The family's first is never doubled.
    static let premiumMultiple = 2

    /// A pantheon's completion prize at a tier.
    static func prize(for tier: CodexTier) -> [ShopService.Grant] {
        switch tier {
        case .quarter: return [.scrolls(.pantheonic, 1), .divinity(100)]
        case .half: return [.scrolls(.divine, 1)]
        case .threeQuarters: return [.scrolls(.lightDark, 1), .divinity(300)]
        case .whole: return [.scrolls(.lightDark, 3), .divinity(1_000)]
        }
    }

    /// The prize in words, for the tier's marker.
    static func prizeWords(for tier: CodexTier) -> String {
        switch tier {
        case .quarter: return "a Pantheon Scroll and 100 divinity"
        case .half: return "a Divine Scroll"
        case .threeQuarters: return "a Light & Dark Scroll and 300 divinity"
        case .whole: return "three Light & Dark Scrolls and 1,000 divinity"
        }
    }

    /// The grade a table is read at: the roster runs 3★ to 5★.
    private static func grade(_ stars: Int) -> Int { min(5, max(3, stars)) }

    /// What one page's own reward is, in divinity.
    static func entryDivinity(_ entry: CodexEntry) -> Int {
        let table = entry.kind == .base ? formDivinity : awakenedDivinity
        let plain = table[grade(entry.stars)] ?? 0
        return entry.element.isLightOrDark ? plain * premiumMultiple : plain
    }

    /// The family's first, in divinity.
    static func familyFirstBonus(stars: Int) -> Int {
        familyFirstDivinity[grade(stars)] ?? 0
    }

    // MARK: - Claim ids

    static let formPrefix = "form:"
    static let awakenedPrefix = "awakened:"

    static func claimID(for blueprintID: String, kind: CodexFormKind) -> String {
        (kind == .base ? formPrefix : awakenedPrefix) + blueprintID
    }

    static func familyClaimID(_ familyKey: String) -> String { "family:\(familyKey)" }

    static func tierClaimID(_ tier: CodexTier, of pantheon: Pantheon) -> String {
        "tier:\(pantheon.rawValue):\(tier.rawValue)"
    }

    // MARK: - The book

    /// Every family with a collectible form — the gacha's pool and the
    /// fusion prizes (`UnitDatabase.collectiblePool`, the list the More
    /// screen's codex count has always read) — the rarest first, then by
    /// name. A family joins the book the moment its cards ship, as it joins
    /// the pool.
    static let families: [CodexFamily] = {
        var grouped: [String: [UnitBlueprint]] = [:]
        var order: [String] = []
        for id in UnitDatabase.collectiblePool {
            guard let blueprint = UnitDatabase.blueprint(id) else { continue }
            let key = RegaliaService.familyKey(of: id)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(blueprint)
        }
        var built: [CodexFamily] = []
        for key in order {
            guard let forms = grouped[key], let head = forms.first else { continue }
            var byElement: [Element: String] = [:]
            for form in forms where byElement[form.element] == nil {
                byElement[form.element] = form.id
            }
            built.append(CodexFamily(
                key: key,
                name: head.name,
                pantheon: head.pantheon,
                stars: head.naturalStars,
                role: head.role,
                forms: byElement,
                awakenable: forms.contains { $0.awakening != nil }
            ))
        }
        return built.sorted { left, right in
            left.stars != right.stars ? left.stars > right.stars : left.name < right.name
        }
    }()

    /// Every page, family by family.
    static let entries: [CodexEntry] = families.flatMap(\.entries)

    private static let entriesByID: [String: CodexEntry] =
        Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    private static let familiesByKey: [String: CodexFamily] =
        Dictionary(families.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    /// The live pantheons that have a page, in `Pantheon.live`'s order.
    static let pantheons: [Pantheon] = Pantheon.live.filter { pantheon in
        families.contains { $0.pantheon == pantheon }
    }

    static func entry(id: String) -> CodexEntry? { entriesByID[id] }

    static func family(key: String) -> CodexFamily? { familiesByKey[key] }

    /// A pantheon's families, in the book's order: its table's rows.
    static func familyRows(of pantheon: Pantheon) -> [CodexFamily] {
        families.filter { $0.pantheon == pantheon }
    }

    /// A pantheon's pages, or the whole book's for nil.
    static func pages(of pantheon: Pantheon?) -> [CodexEntry] {
        guard let pantheon else { return entries }
        return entries.filter { $0.pantheon == pantheon }
    }

    // MARK: - Reading a save

    /// What a save has recorded and claimed.
    static func ledger(for player: Player) -> CodexLedger {
        let claims = player.codexClaims ?? []
        var recorded = player.codex
        var awakened: Set<String> = []
        for unit in player.units {
            recorded.insert(unit.blueprintID)
            if unit.isAwakened { awakened.insert(unit.blueprintID) }
        }
        for claim in claims {
            if claim.hasPrefix(formPrefix) {
                recorded.insert(String(claim.dropFirst(formPrefix.count)))
            } else if claim.hasPrefix(awakenedPrefix) {
                awakened.insert(String(claim.dropFirst(awakenedPrefix.count)))
            }
        }
        // An awakened face is a form the player has held.
        recorded.formUnion(awakened)
        return CodexLedger(recorded: recorded, awakened: awakened, claims: claims)
    }

    /// What claiming a page would pay now.
    static func reward(for entry: CodexEntry, ledger: CodexLedger) -> CodexReward {
        let first = ledger.isClaimed(familyClaimID(entry.familyKey)) ? 0 : familyFirstBonus(stars: entry.stars)
        return CodexReward(entry: entryDivinity(entry), familyFirst: first)
    }

    /// A pantheon's pages recorded, or the whole book's for nil.
    static func progress(of pantheon: Pantheon?, ledger: CodexLedger) -> CodexProgress {
        let shelf = pages(of: pantheon)
        let lit = shelf.filter { ledger.isRecorded($0) }.count
        return CodexProgress(recorded: lit, total: shelf.count)
    }

    /// The pages a tier asks for: its share of the pantheon, rounded up, so
    /// 25% of 85 is 22 and 100% is every page.
    static func target(for tier: CodexTier, total: Int) -> Int {
        (total * tier.rawValue + 99) / 100
    }

    /// How many more pages the tier wants; 0 once it is reached.
    static func recordsNeeded(for tier: CodexTier, of pantheon: Pantheon, ledger: CodexLedger) -> Int {
        let reading = progress(of: pantheon, ledger: ledger)
        return max(0, target(for: tier, total: reading.total) - reading.recorded)
    }

    /// Where a pantheon's tier stands: reached on the pages RECORDED, whether
    /// or not their own rewards have been taken — the genre's completion
    /// share is of the collection, not of the claims.
    static func tierStanding(_ tier: CodexTier, of pantheon: Pantheon, ledger: CodexLedger) -> CodexStanding {
        if ledger.isClaimed(tierClaimID(tier, of: pantheon)) { return .claimed }
        return recordsNeeded(for: tier, of: pantheon, ledger: ledger) == 0 ? .ready : .unrecorded
    }

    /// Pages and tiers waiting to be claimed, in a pantheon or the whole book.
    static func readyCount(of pantheon: Pantheon?, ledger: CodexLedger) -> Int {
        let waitingPages = pages(of: pantheon).filter { ledger.standing($0) == .ready }.count
        let scope = pantheon.map { [$0] } ?? pantheons
        var waitingTiers = 0
        for place in scope {
            waitingTiers += CodexTier.allCases.filter { tierStanding($0, of: place, ledger: ledger) == .ready }.count
        }
        return waitingPages + waitingTiers
    }

    /// Everything waiting in the book, for a badge.
    static func readyCount(player: Player) -> Int {
        readyCount(of: nil, ledger: ledger(for: player))
    }

    // MARK: - Claiming

    /// Claims one page: its own reward and, the first time a page of its
    /// family is taken, the family's first — paid together as divinity
    /// through the game's one grant path (`ShopService.grant`).
    @discardableResult
    static func claim(_ entryID: String, player: inout Player, rng: inout SeededRandom) throws -> [ShopService.Grant] {
        guard let page = entry(id: entryID) else { throw CodexError.unknownEntry }
        let book = ledger(for: player)
        guard !book.isClaimed(page.id) else { throw CodexError.alreadyClaimed }
        guard book.isRecorded(page) else { throw CodexError.notRecorded }
        let payout = reward(for: page, ledger: book)
        var claims = player.codexClaims ?? []
        claims.insert(page.id)
        claims.insert(familyClaimID(page.familyKey))
        player.codexClaims = claims
        var paid: [ShopService.Grant] = []
        for grant in payout.grants {
            paid += ShopService.grant(grant, to: &player, rng: &rng)
        }
        return paid
    }

    /// Claims a pantheon's tier once its share of pages is recorded.
    @discardableResult
    static func claimTier(_ tier: CodexTier, of pantheon: Pantheon,
                          player: inout Player, rng: inout SeededRandom) throws -> [ShopService.Grant] {
        let book = ledger(for: player)
        let tierID = tierClaimID(tier, of: pantheon)
        guard !book.isClaimed(tierID) else { throw CodexError.alreadyClaimed }
        let needed = recordsNeeded(for: tier, of: pantheon, ledger: book)
        guard needed == 0 else { throw CodexError.tierNotReached(needed: needed) }
        var claims = player.codexClaims ?? []
        claims.insert(tierID)
        player.codexClaims = claims
        var paid: [ShopService.Grant] = []
        for grant in prize(for: tier) {
            paid += ShopService.grant(grant, to: &player, rng: &rng)
        }
        return paid
    }

    /// Claims every page and tier waiting, in a pantheon or the whole book,
    /// and returns what it paid merged into one receipt. Pays exactly what
    /// the same claims one at a time in the book's order would
    /// (`CodexTests.testClaimAllPaysWhatTheClaimsOneByOneWould`), without
    /// reading the save again for each of eight hundred pages.
    @discardableResult
    static func claimAll(of pantheon: Pantheon? = nil, player: inout Player, rng: inout SeededRandom) -> [ShopService.Grant] {
        let book = ledger(for: player)
        var claims = player.codexClaims ?? []
        var divinity = 0
        for page in pages(of: pantheon) where book.isRecorded(page) && !claims.contains(page.id) {
            divinity += entryDivinity(page)
            let family = familyClaimID(page.familyKey)
            if !claims.contains(family) {
                divinity += familyFirstBonus(stars: page.stars)
                claims.insert(family)
            }
            claims.insert(page.id)
        }
        var grants: [ShopService.Grant] = divinity > 0 ? [.divinity(divinity)] : []
        // A tier is reached on the pages recorded, which claiming does not
        // change, so the ledger read before the pages were taken still holds.
        let scope = pantheon.map { [$0] } ?? pantheons
        for place in scope {
            for tier in CodexTier.allCases where tierStanding(tier, of: place, ledger: book) == .ready {
                claims.insert(tierClaimID(tier, of: place))
                grants += prize(for: tier)
            }
        }
        player.codexClaims = claims
        var paid: [ShopService.Grant] = []
        for grant in grants {
            paid += ShopService.grant(grant, to: &player, rng: &rng)
        }
        return merged(paid)
    }

    /// Grants folded for a receipt: every divinity grant into one, every
    /// scroll of a kind into one, anything else as it came.
    static func merged(_ grants: [ShopService.Grant]) -> [ShopService.Grant] {
        var divinity = 0
        var scrolls: [ScrollType: Int] = [:]
        var rest: [ShopService.Grant] = []
        for grant in grants {
            switch grant {
            case .divinity(let amount):
                divinity += amount
            case .scrolls(let scroll, let count):
                scrolls[scroll, default: 0] += count
            default:
                rest.append(grant)
            }
        }
        var folded: [ShopService.Grant] = divinity > 0 ? [.divinity(divinity)] : []
        for scroll in ScrollType.allCases {
            if let count = scrolls[scroll], count > 0 {
                folded.append(.scrolls(scroll, count))
            }
        }
        return folded + rest
    }

    // MARK: - Where a form comes from

    /// Every road to a page's form, read off the systems themselves so the
    /// page can never promise what the game no longer gives: the banners
    /// whose pool draws it (`SummonService.eligible(for:)`, which keeps the
    /// Light & Dark rule — a Radiance or Umbra form lists that scroll alone),
    /// with the grade's rate and the mileage price there; a fusion recipe;
    /// the Night Market's rare row; the opening selector while it is owed;
    /// the starter. An awakened page leads with the awakening and its bill,
    /// then the form's own roads.
    static func sources(for entry: CodexEntry, player: Player) -> [CodexSource] {
        guard let blueprint = entry.blueprint else { return [] }
        var roads: [CodexSource] = []
        if entry.kind == .awakened {
            let bill = essenceBill(for: blueprint)
            let words = bill.map { "\($0.count) \(EssenceCatalog.name(for: $0.id))" }
            roads.append(CodexSource(
                id: "awakening",
                title: "Awakening",
                detail: "Awaken this form in the Hall of Ka: " + listed(words) + ".",
                itemKey: "awakening_cache_\(blueprint.element.rawValue)",
                glyph: "sun.max.fill"
            ))
        }
        if blueprint.id == UnitDatabase.starter.id {
            roads.append(CodexSource(
                id: "starter",
                title: "The first companion",
                detail: "Every demigod begins the game with this one.",
                itemKey: nil,
                glyph: "person.crop.circle.badge.checkmark"
            ))
        }
        if SelectorService.isOwed(player), SelectorService.candidates().contains(where: { $0.id == blueprint.id }) {
            roads.append(CodexSource(
                id: "selector",
                title: "The opening gift",
                detail: "One of the five 4★s a new demigod names for himself, and still yours to take.",
                itemKey: nil,
                glyph: "gift.fill"
            ))
        }
        for banner in Banner.all where SummonService.eligible(for: banner).contains(where: { $0.id == blueprint.id }) {
            roads.append(bannerSource(banner, blueprint: blueprint))
        }
        if let recipe = FusionService.recipes.first(where: { $0.resultID == blueprint.id }) {
            let corners = recipe.ingredients.map { "\($0.title) \($0.requirement)" }
            roads.append(CodexSource(
                id: "fusion_\(recipe.id)",
                title: recipe.name,
                detail: "Fused in the Hall of Ka from " + listed(corners)
                    + ", and \(recipe.drachmaCost.formatted()) drachma. No scroll gives it.",
                itemKey: nil,
                glyph: "hexagon.fill"
            ))
        }
        if NightMarketService.marketUnits(stars: blueprint.naturalStars).contains(blueprint.id) {
            roads.append(CodexSource(
                id: "night_market",
                title: "Night Market",
                detail: blueprint.naturalStars >= 4
                    ? "Now and then on the rare row, from demigod level 12, for drachma."
                    : "Now and then on the rare row, for drachma.",
                itemKey: "chest_gold",
                glyph: "moon.stars.fill"
            ))
        }
        return roads
    }

    /// A banner as a road: its scroll, the grade's rate on it, whether the
    /// form is featured, and what naming it on the banner's exchange costs.
    private static func bannerSource(_ banner: Banner, blueprint: UnitBlueprint) -> CodexSource {
        let stars = blueprint.naturalStars
        var parts = ["\(stars)★ at \(percentText(banner.scroll.odds[stars] ?? 0)) a pull"]
        if banner.featured.contains(blueprint.id) { parts.append("featured") }
        parts.append("\(MileageService.price(stars: stars, on: banner)) mileage")
        return CodexSource(
            id: "banner_\(banner.id)",
            title: banner.title,
            detail: parts.joined(separator: " · "),
            itemKey: "scroll_\(banner.scroll.rawValue)",
            glyph: banner.scroll.glyph
        )
    }

    /// An awakening's bill in reading order: the element's essence before
    /// Magic, Low before Mid before High.
    static func essenceBill(for blueprint: UnitBlueprint) -> [CodexEssence] {
        let tiers = ["low", "mid", "high"]
        func rank(_ id: String) -> Int {
            let tier = tiers.firstIndex { id.hasSuffix("_\($0)") } ?? tiers.count
            return (id.hasPrefix("essence_magic_") ? 10 : 0) + tier
        }
        let bill = blueprint.awakening?.essenceCost ?? [:]
        return bill
            .map { CodexEssence(id: $0.key, count: $0.value) }
            .sorted { rank($0.id) < rank($1.id) }
    }

    /// "3%", "1.5%", "0.8%": a rate as the rate table prints it.
    static func percentText(_ rate: Double) -> String {
        let percent = rate * 100
        if abs(percent - percent.rounded()) < 0.05 { return "\(Int(percent.rounded()))%" }
        return String(format: "%.1f%%", percent)
    }

    /// "a, b and c".
    private static func listed(_ words: [String]) -> String {
        guard words.count > 1 else { return words.joined() }
        return words.dropLast().joined(separator: ", ") + " and " + words[words.count - 1]
    }

    // MARK: - Names

    /// A form's full name: "Anubis of the Burning Sands", "Anubis, Guardian
    /// of the Scales", or the awakened name.
    static func formName(for entry: CodexEntry) -> String {
        guard let blueprint = entry.blueprint else { return entry.blueprintID }
        if entry.kind == .awakened, let awakening = blueprint.awakening {
            return awakening.awakenedName
        }
        let epithet = blueprint.epithet
        guard !epithet.isEmpty else { return blueprint.name }
        return epithet.hasPrefix("of ") ? "\(blueprint.name) \(epithet)" : "\(blueprint.name), \(epithet)"
    }
}
