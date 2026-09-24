import Foundation

/// A summoning banner. Banners are data so a live-ops calendar is a JSON file
/// rather than a build.
struct Banner: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var scroll: ScrollType
    /// Blueprint ids eligible on this banner. Empty means "everything summonable".
    var pool: [String]
    /// Ids at double weight within their grade.
    var featured: [String]
    /// Summons after which a 5★ is guaranteed. Nil disables hard pity.
    var legendaryPity: Int?
    /// Summons after which a 4★-or-better is guaranteed.
    var rarePity: Int?
    /// Splash art asset name.
    var artName: String
    var pantheon: Pantheon?

    static let standard = Banner(
        id: "standard",
        title: "The Endless Scroll",
        subtitle: "Every soul of every pantheon, in fire, in water and in wind.",
        scroll: .mystical,
        pool: [],
        featured: [],
        legendaryPity: nil,
        rarePity: 20,
        artName: "banner_standard",
        pantheon: nil
    )

    /// The one rule of the pools: Radiance and Umbra are the Light & Dark
    /// scroll's ALONE. Every other banner's pool and featured list is built
    /// through here, `SummonService.eligibleIDs` runs every draw through it
    /// again, and the selector, the mileage board and the night market read
    /// what it made — so nothing but that scroll can hand one over.
    ///
    /// The owner, 2026-09-17, with the Fuse board offering a 5★ light Ares
    /// and a 5★ dark Horus: "we should NEVER offer a 5 star Light or dark mon
    /// like this. it should ONLY be availble at like a 1% or less rate
    /// through the LD scrolls (like summoners war). They are PREMIUM PREMIUM
    /// mons that need to be better than the rest". Summoners War's Light &
    /// Dark scroll is the only road to its light and dark monsters, at 0.5%
    /// for a 5★ with no guarantee; this is that.
    ///
    /// `UnitDatabase.summonPool` stays the FULL summonable set — the codex,
    /// the collection and the art gate read it — and the filter is at the
    /// banners. The premium itself is `UnitDatabase.lightDarkPremium`.
    static func excludingLightDark(_ ids: [String]) -> [String] {
        ids.filter { !(UnitDatabase.blueprint($0)?.element.isLightOrDark ?? false) }
    }

    /// Every summonable of one pantheon in fire, water and wind, for a banner
    /// that promises it.
    static func pool(of pantheon: Pantheon) -> [String] {
        excludingLightDark(UnitDatabase.summonPool.filter { UnitDatabase.blueprint($0)?.pantheon == pantheon })
    }

    /// A pantheon banner's featured family: the god in his three summonable
    /// elements. His Radiance and his Umbra are not on the banner at all.
    static func featuredFamily(_ prefix: String) -> [String] {
        excludingLightDark(UnitDatabase.summonPool.filter { $0.hasPrefix(prefix) })
    }

    /// The launch banner: Egypt only. The pool is the whole Egyptian roster, so
    /// a common roll lands on a Shabti, a rare one on an Anubis and a legendary
    /// on Sekhmet or Thoth, and the Anubis family is featured at double weight
    /// within its grade. A pantheon banner that handed out the other pantheon's
    /// commons was the "the Greek banner is all Anubis" complaint.
    static let duatOpens = Banner(
        id: "duat_opens",
        title: "The Duat Opens",
        subtitle: "The scales are unattended. Egypt answers the circle — Anubis first, in fire, in water and in wind.",
        scroll: .pantheonic,
        pool: pool(of: .egyptian),
        featured: featuredFamily("anubis_"),
        legendaryPity: 90,
        rarePity: 12,
        artName: "banner_duat_opens",
        pantheon: .egyptian
    )

    /// The Greek banner: Greece only. Zeus is featured in fire, water and
    /// wind; the rest of Olympus — Ares, the heroes, the creatures and the
    /// hoplite — fills the grades beneath and beside him. It is offered once
    /// at least one Greek unit has its portraits in the bundle.
    static let olympusStirs = Banner(
        id: "olympus_stirs",
        title: "Olympus Stirs",
        subtitle: "The sky opens over Greece. Gods, heroes and the creatures of the old country answer — Zeus first, in fire, in water and in wind.",
        scroll: .pantheonic,
        pool: pool(of: .greek),
        featured: featuredFamily("zeus_"),
        legendaryPity: 90,
        rarePity: 10,
        artName: "banner_olympus_stirs",
        pantheon: .greek
    )

    /// The Norse banner: Yggdrasil only. Odin is featured in fire, water and
    /// wind; Thor, Freya and Loki share his grade, the Æsir and the giant's
    /// daughter fill the one beneath, and the barrow-dead, the trolls, the
    /// valkyries and the dwarves are its commons. Offered once a Norse unit
    /// has cards.
    static let ravensGather = Banner(
        id: "ravens_gather",
        title: "The Ravens Gather",
        subtitle: "Two ravens leave the tree at dawn. Yggdrasil answers the circle — Odin first, in fire, in water and in wind.",
        scroll: .pantheonic,
        pool: pool(of: .norse),
        featured: featuredFamily("odin_"),
        legendaryPity: 90,
        rarePity: 10,
        artName: "banner_ravens_gather",
        pantheon: .norse
    )

    /// The Roman banner: the Seven Hills only. Mars is featured in fire,
    /// water and wind; Minerva shares his grade, the gods of the Forum fill
    /// the one beneath, and the centurion, the gladiator and the Vestal are
    /// its commons. Offered once a Roman unit has cards (batch 4).
    static let eagleRises = Banner(
        id: "eagle_rises",
        title: "The Eagle Rises",
        subtitle: "The standards go up on the Capitol. Rome answers the circle — Mars first, in fire, in water and in wind.",
        scroll: .pantheonic,
        pool: pool(of: .roman),
        featured: featuredFamily("mars_"),
        legendaryPity: 90,
        rarePity: 10,
        artName: "banner_eagle_rises",
        pantheon: .roman
    )

    /// The Chinese banner: the Jade Court only. The Monkey King is featured
    /// in fire, water and wind; the Azure Dragon shares his grade, the court
    /// fills the one beneath, and the fox, the hopping dead and the clay
    /// soldier are its commons. Offered once a Jade Court unit has cards.
    static let jadeCourtOpens = Banner(
        id: "jade_court_opens",
        title: "The Jade Court Opens",
        subtitle: "The gates of Heaven stand open and the Monkey King is first through them. The Jade Court answers the circle — Sun Wukong in fire, in water and in wind.",
        scroll: .pantheonic,
        pool: pool(of: .chinese),
        featured: featuredFamily("sun_wukong_"),
        legendaryPity: 90,
        rarePity: 10,
        artName: "banner_jade_court",
        pantheon: .chinese
    )

    /// The summon pool filtered by a rule, in fire, water and wind: what the
    /// scroll banners are made of.
    static func pool(where keep: (UnitBlueprint) -> Bool) -> [String] {
        excludingLightDark(UnitDatabase.summonPool.filter { id in UnitDatabase.blueprint(id).map(keep) ?? false })
    }

    /// The Light & Dark scroll's pool: every Radiance and Umbra unit of every
    /// pantheon, which is every one there is. The only pool in the game
    /// built without `excludingLightDark`.
    static let lightDarkPool: [String] =
        UnitDatabase.summonPool.filter { UnitDatabase.blueprint($0)?.element.isLightOrDark ?? false }

    /// The scroll banners, the way the genre sells them: the scroll is the
    /// rule. Each spends its own scroll and draws from the slice of the
    /// roster its name promises, with pity counters of its own.
    static let unknownScroll = Banner(
        id: "unknown_scroll",
        title: "Unknown Scroll",
        subtitle: "The commons of every pantheon: the 3★ tier, cheap and plentiful, the Hall of Ka's bread.",
        scroll: .unknown,
        pool: pool(where: { $0.naturalStars == 3 }),
        featured: [],
        legendaryPity: nil,
        rarePity: nil,
        artName: "banner_unknown",
        pantheon: nil
    )

    static let divineScroll = Banner(
        id: "divine_scroll",
        title: "Divine Scroll",
        subtitle: "Never less than a 4★, from every pantheon, in fire, water and wind. The surest scroll there is.",
        scroll: .divine,
        pool: pool(where: { $0.naturalStars >= 4 }),
        featured: [],
        legendaryPity: 40,
        rarePity: nil,
        artName: "banner_divine",
        pantheon: nil
    )

    /// The premium banner, and the only road to the premium units: every
    /// Radiance and Umbra of every pantheon, at the scroll's 0.8% for a 5★,
    /// with NO hard pity and so no soft pity either — `SummonService.single`
    /// keys both off `legendaryPity`, and nil switches both off. The 4★
    /// guarantee stays: fifteen scrolls (6,750 divinity) without a 4★ Light
    /// or Dark would be a drought with nothing at the end of it. Summoners
    /// War's L&D scroll has no pity at all; Epic Seven's Moonlight summon is
    /// 0.5% at 5★ on its own currency with a 200-pull counter; this sits
    /// between them with mileage (`MileageService`) as the floor —
    /// `Docs/PLAN.md`, *Light and Dark are the premium*.
    static let lightAndDark = Banner(
        id: "light_dark_scroll",
        title: "Light & Dark",
        subtitle: "Only the sun's and the night's: every Radiance and Umbra unit of every pantheon, and the only scroll that gives them.",
        scroll: .lightDark,
        pool: lightDarkPool,
        featured: [],
        legendaryPity: nil,
        rarePity: 15,
        artName: "banner_light_dark",
        pantheon: nil
    )

    static let emberScroll = Banner(
        id: "ember_scroll",
        title: "Fire Scroll",
        subtitle: "Every Fire unit of every pantheon, and nothing else.",
        scroll: .ember,
        pool: pool(where: { $0.element == .ember }),
        featured: [],
        legendaryPity: 120,
        rarePity: 15,
        artName: "banner_fire",
        pantheon: nil
    )

    static let tideScroll = Banner(
        id: "tide_scroll",
        title: "Water Scroll",
        subtitle: "Every Water unit of every pantheon, and nothing else.",
        scroll: .tide,
        pool: pool(where: { $0.element == .tide }),
        featured: [],
        legendaryPity: 120,
        rarePity: 15,
        artName: "banner_water",
        pantheon: nil
    )

    static let galeScroll = Banner(
        id: "gale_scroll",
        title: "Wind Scroll",
        subtitle: "Every Wind unit of every pantheon, and nothing else.",
        scroll: .gale,
        pool: pool(where: { $0.element == .gale }),
        featured: [],
        legendaryPity: 120,
        rarePity: 15,
        artName: "banner_wind",
        pantheon: nil
    )

    /// The summon screen's first row: a banner per live pantheon, each
    /// offered once its pool has a unit with cards in the bundle
    /// (`hasShippedArt`), so Rome and the Jade Court appear the morning
    /// their first family's five cards land.
    static var pantheonBanners: [Banner] {
        [duatOpens]
            + (olympusStirs.pool.isEmpty ? [] : [olympusStirs])
            + (ravensGather.pool.isEmpty ? [] : [ravensGather])
            + (eagleRises.pool.isEmpty ? [] : [eagleRises])
            + (jadeCourtOpens.pool.isEmpty ? [] : [jadeCourtOpens])
    }

    /// The second row: the scrolls, each its own slice of the roster. The
    /// Endless Scroll is everyone and is always there.
    static var scrollBanners: [Banner] {
        [standard] + [unknownScroll, divineScroll, lightAndDark, emberScroll, tideScroll, galeScroll].filter { !$0.pool.isEmpty }
    }

    static var all: [Banner] { pantheonBanners + scrollBanners }
}

/// The outcome of a single summon.
struct SummonResult: Identifiable, Sendable {
    var id = UUID()
    var unit: Unit
    var blueprint: UnitBlueprint
    var stars: Int
    var isNew: Bool
    var isFeatured: Bool
    /// True when hard pity, not luck, produced this result. The reveal screen
    /// says so — hiding it is the kind of thing players find out anyway.
    var fromPity: Bool
    /// The Hall of Ka reuses the reveal for an awakening: the unit's awakened
    /// form comes in on the beam under its new name.
    var isAwakening: Bool = false
    /// What this pull did as a DUPLICATE (2026-09-24): the skill that rose
    /// on the copy already owned, or that none could (`SummonSkillUp`). Nil
    /// for a new unit, and for a path that did not record it; the reveal
    /// then names no skill-up it cannot vouch for.
    var skillUp: SummonSkillUp? = nil
    /// What this pull's Codex page pays when it is claimed, for a form NEW
    /// to the book (`SummonService.codexPay`). Nil when there is no page to
    /// claim.
    var codexDivinity: Int? = nil
}

/// What a duplicate did to the copy already owned (2026-09-24, Docs/FEEL.md
/// W1.5). The reveal said "one skill levelled up" of every duplicate, even
/// when every skill was already at its cap, because the answer of
/// `ProgressionService.applySkillUp` was thrown away where it was made
/// (`_ =`). It is kept now, from that one call: which skill rose and to
/// what, or that none could.
enum SummonSkillUp: Equatable, Sendable {
    /// The skill at `skill` in the blueprint's kit rose from `from` to `to`.
    case levelled(skill: Int, from: Int, to: Int)
    /// Every skill was already at its cap. Nothing rose; the copy is food
    /// for the family's Regalia in the Hall of Ka.
    case maxed
}

/// Runs the gacha.
///
/// Rates live on `ScrollType`, pity lives on the `Banner`, and the seeded RNG
/// makes the whole thing reproducible. Nothing here reads the clock, so a
/// summon can be replayed exactly for support tickets or for tests.
enum SummonService {

    enum SummonError: Error, LocalizedError {
        case noScrolls(ScrollType)
        case emptyPool

        var errorDescription: String? {
            switch self {
            case .noScrolls(let scroll): return "You have no \(scroll.displayName)s."
            case .emptyPool: return "This banner has nothing to summon right now."
            }
        }
    }

    /// Performs `count` summons against a banner, spending scrolls and updating
    /// pity. Mutates the player directly so the caller cannot forget to save.
    static func summon(
        banner: Banner,
        count: Int,
        player: inout Player,
        rng: inout SeededRandom
    ) throws -> [SummonResult] {
        guard player.wallet.count(of: banner.scroll) >= count else {
            throw SummonError.noScrolls(banner.scroll)
        }
        guard !eligibleIDs(for: banner).isEmpty else { throw SummonError.emptyPool }

        _ = player.wallet.consume(banner.scroll, count)
        var pity = player.summonPity[banner.id] ?? PityState()
        var results: [SummonResult] = []
        // The families whose first-claim bonus a new page of THIS summon has
        // already been promised (`codexPay`), so ten pages add up to what
        // claiming them pays.
        var promised: Set<String> = []

        for _ in 0..<count {
            let result = single(banner: banner, pity: &pity, player: &player, promised: &promised, rng: &rng)
            results.append(result)
        }

        player.summonPity[banner.id] = pity
        player.totalSummons += count
        // A point a pull, whatever the pull gave. Paid here rather than in
        // `GameStore` so no path that spends a scroll can forget it.
        MileageService.earn(count, on: banner, player: &player)
        return results
    }

    private static func single(
        banner: Banner,
        pity: inout PityState,
        player: inout Player,
        promised: inout Set<String>,
        rng: inout SeededRandom
    ) -> SummonResult {
        pity.totalPulls += 1
        pity.sinceLegendary += 1
        pity.sinceRare += 1

        var fromPity = false
        var stars: Int

        if let cap = banner.legendaryPity, pity.sinceLegendary >= cap {
            stars = 5
            fromPity = true
        } else if let cap = banner.rarePity, pity.sinceRare >= cap {
            stars = max(4, rollStars(scroll: banner.scroll, rng: &rng))
            fromPity = stars == 4
        } else {
            stars = rollStars(scroll: banner.scroll, rng: &rng)
        }

        // Soft pity: the 5★ rate climbs steeply over the last quarter of the
        // counter, so the guaranteed pull is rarely the one that delivers.
        if stars < 5, let cap = banner.legendaryPity {
            let softStart = Int(Double(cap) * 0.75)
            if pity.sinceLegendary > softStart {
                let steps = Double(pity.sinceLegendary - softStart)
                if rng.chance(min(0.9, steps * 0.06)) { stars = 5 }
            }
        }

        if stars >= 5 { pity.sinceLegendary = 0 }
        if stars >= 4 { pity.sinceRare = 0 }

        let blueprint = pick(stars: stars, banner: banner, pity: &pity, rng: &rng)
        let isNew = !player.codex.contains(blueprint.id)
        let pagePay: Int? = isNew ? codexPay(for: blueprint.id, player: player, promised: &promised) : nil
        player.codex.insert(blueprint.id)

        var unit = Unit(blueprint: blueprint)
        unit.acquiredFrom = banner.id

        // A duplicate becomes a skill-up rather than clutter, and the reveal
        // is told what it did.
        var skillUp: SummonSkillUp?
        if !isNew, let existingIndex = player.units.firstIndex(where: { $0.blueprintID == blueprint.id }) {
            skillUp = duplicateSkillUp(on: existingIndex, player: &player, rng: &rng)
        }
        player.units.append(unit)

        // The stars shown are the unit's own, not the grade that was rolled:
        // a common roll that fell up to a 4★ Anubis is a 4★ Anubis.
        return SummonResult(
            unit: unit,
            blueprint: blueprint,
            stars: unit.stars,
            isNew: isNew,
            isFeatured: banner.featured.contains(blueprint.id),
            fromPity: fromPity,
            skillUp: skillUp,
            codexDivinity: pagePay
        )
    }

    /// A duplicate's skill-up on the copy already owned at `index`, and what
    /// it did (2026-09-24). Every path that hands over a unit a player may
    /// already hold — a scroll, the mileage, a shrine — makes this ONE call,
    /// and the answer is read off it: the skill `applySkillUp` chose and the
    /// levels either side of its step, never rolled again or guessed. `nil`
    /// from `applySkillUp` for a blueprint the tables know means no skill
    /// had room to rise.
    static func duplicateSkillUp(on index: Int, player: inout Player, rng: inout SeededRandom) -> SummonSkillUp? {
        guard player.units.indices.contains(index) else { return nil }
        let before: [Int] = player.units[index].skillLevels
        guard let skill = ProgressionService.applySkillUp(to: &player.units[index], using: &rng) else {
            let known = UnitDatabase.blueprint(player.units[index].blueprintID) != nil
            return known ? .maxed : nil
        }
        let after: [Int] = player.units[index].skillLevels
        // `applySkillUp` pads a short list with 1s before it steps.
        let from: Int = before.indices.contains(skill) ? before[skill] : 1
        let to: Int = after.indices.contains(skill) ? after[skill] : from
        return .levelled(skill: skill, from: from, to: to)
    }

    /// What claiming a NEW form's Codex page will pay, exactly as
    /// `CodexService.claim` pays it (2026-09-24): the page's own divinity,
    /// and the family's first on top only for the family's FIRST page — none
    /// of it claimed, no OTHER page of it already in the book, and no
    /// earlier pull of the same summon promised it (`promised`). The first
    /// page claimed takes the family's first whichever it is, so what the
    /// pages promise adds up to what claiming them pays across separate
    /// summons too. It was the family's claim alone at first, and `promised`
    /// lives for one call: a fire Anubis left unclaimed and a water Anubis
    /// the next day both promised the first, which is paid once (review,
    /// 2026-09-24). A page recorded before this pull and still unclaimed —
    /// a unit owned from before the Codex — keeps the first, so a new page
    /// never promises more than it pays. Nil for a form with no page, or a
    /// page already claimed. Read before anything is claimed; a summon
    /// claims nothing.
    static func codexPay(for blueprintID: String, player: Player, promised: inout Set<String>) -> Int? {
        let pageID = CodexService.claimID(for: blueprintID, kind: .base)
        guard let page = CodexService.entry(id: pageID) else { return nil }
        let claims: Set<String> = player.codexClaims ?? []
        guard !claims.contains(pageID) else { return nil }
        let own: Int = CodexService.entryDivinity(page)
        let familyClaim = CodexService.familyClaimID(page.familyKey)
        let book = CodexService.ledger(for: player)
        let siblings: [CodexEntry] = CodexService.family(key: page.familyKey)?.entries ?? []
        let familyRecorded: Bool = siblings.contains { $0.id != pageID && book.isRecorded($0) }
        guard !claims.contains(familyClaim), !familyRecorded, !promised.contains(page.familyKey) else { return own }
        promised.insert(page.familyKey)
        let first: Int = CodexService.familyFirstBonus(stars: page.stars)
        return own + first
    }

    private static func rollStars(scroll: ScrollType, rng: inout SeededRandom) -> Int {
        let entries = scroll.odds.map { (value: $0.key, weight: $0.value) }
            .sorted { $0.value < $1.value }
        return rng.pickWeighted(entries) ?? 3
    }

    /// One weight, used everywhere a unit is drawn, so no path can quietly
    /// ignore it: the featured family at double, and nothing else.
    ///
    /// There WAS a second rule here. From 2026-09-10 a Light or Dark unit
    /// was cut to 0.25 (4★) or 0.12 (5★) of its grade's weight inside a pool
    /// that held all five elements (`lightDarkWeight`; the owner: "Summon
    /// rates for LD 4 and 5 star need to be turned down"), which made a 5★
    /// dark god one pantheon pull in four hundred and fifty rather than one
    /// in eighty. It went with the pools that needed it: since 2026-09-17 no
    /// pool but the Light & Dark scroll's holds a Radiance or Umbra unit at
    /// all (`Banner.excludingLightDark`), so a discount would have nothing
    /// left to discount, and that scroll's own pool is all one side of the
    /// line, where a factor on every candidate alike cancels out.
    static func weight(of blueprint: UnitBlueprint, on banner: Banner) -> Double {
        banner.featured.contains(blueprint.id) ? 2.0 : 1.0
    }

    /// Picks a unit of the given grade, honouring the featured double-weight
    /// and the 50/50-then-guaranteed rule on the featured slot.
    private static func pick(
        stars: Int,
        banner: Banner,
        pity: inout PityState,
        rng: inout SeededRandom
    ) -> UnitBlueprint {
        let candidates = eligible(for: banner).filter { $0.naturalStars == stars }
        guard !candidates.isEmpty else {
            // Nothing of this grade on the banner. Fall to the nearest grade
            // below it — or the lowest grade above when there is nothing
            // below — and roll WITHIN that grade with the featured weighting,
            // rather than failing a summon the player has already paid for.
            // The old fallback returned the first unit in list order, which
            // on a roster with no 3★ units made every common pull the same
            // fire Anubis.
            let pool = eligible(for: banner)
            let grade = pool.filter { $0.naturalStars <= stars }.map(\.naturalStars).max()
                ?? pool.map(\.naturalStars).min()
            guard let grade else { return UnitDatabase.starter }
            let fallback = pool.filter { $0.naturalStars == grade }
            let weighted = fallback.map { (value: $0, weight: weight(of: $0, on: banner)) }
            return rng.pickWeighted(weighted) ?? fallback[0]
        }

        let featuredHere = candidates.filter { banner.featured.contains($0.id) }

        if stars >= 5, !featuredHere.isEmpty {
            // Drawn through `weight(of:on:)` like every other candidate, so
            // there is one place a rule about who comes out lives. (It was
            // uniform once, and when a banner featured a god in all five of
            // his elements that handed out his Radiance and his Umbra two
            // times in five — the widest hole in the discount of the day.)
            let featuredWeighted = featuredHere.map { (value: $0, weight: weight(of: $0, on: banner)) }
            if pity.featuredGuaranteed {
                pity.featuredGuaranteed = false
                return rng.pickWeighted(featuredWeighted) ?? featuredHere[0]
            }
            if rng.chance(0.5) {
                return rng.pickWeighted(featuredWeighted) ?? featuredHere[0]
            }
            let others = candidates.filter { !banner.featured.contains($0.id) }
            if others.isEmpty {
                // Only the featured unit exists at this grade; the 50/50 is moot.
                return featuredHere[0]
            }
            pity.featuredGuaranteed = true
            let otherWeighted = others.map { (value: $0, weight: weight(of: $0, on: banner)) }
            return rng.pickWeighted(otherWeighted) ?? others[0]
        }

        let weighted = candidates.map { (value: $0, weight: weight(of: $0, on: banner)) }
        return rng.pickWeighted(weighted) ?? candidates[0]
    }

    /// What a banner can draw. The Light & Dark rule is applied HERE as well
    /// as when the pools were built: a banner that spends any scroll but the
    /// Light & Dark one never sees a Radiance or Umbra id, whatever its pool
    /// says — so the draw, the odds table, the mileage board and the
    /// selector, which all read `eligible(for:)`, cannot disagree.
    private static func eligibleIDs(for banner: Banner) -> [String] {
        let ids = banner.pool.isEmpty ? UnitDatabase.summonPool : banner.pool
        return banner.scroll == .lightDark ? ids : Banner.excludingLightDark(ids)
    }

    static func eligible(for banner: Banner) -> [UnitBlueprint] {
        eligibleIDs(for: banner).compactMap { UnitDatabase.blueprint($0) }
    }

    /// Displayed odds, so the summon screen can show a real rate table.
    static func oddsTable(for banner: Banner) -> [BannerOdds] {
        let pool = eligible(for: banner)
        return banner.scroll.odds
            .sorted { $0.key > $1.key }
            .map { stars, chance in
                BannerOdds(stars: stars, chance: chance, units: pool.filter { $0.naturalStars == stars })
            }
    }
}

/// One row of a published rate table.
struct BannerOdds: Identifiable, Sendable {
    var stars: Int
    var chance: Double
    var units: [UnitBlueprint]

    var id: Int { stars }

    /// What share of this grade's pool is Radiance or Umbra. Since 2026-09-17
    /// that is all of it on the Light & Dark scroll and none of it anywhere
    /// else (`Banner.excludingLightDark`), so the line below never prints —
    /// and that is the reason to keep it: the rate table reads it, and the
    /// day a Radiance or Umbra unit leaks into another banner's pool the
    /// table says so in violet, under the grade's odds, rather than hiding
    /// a rate the player cannot work out from the names in front of him.
    /// (Until then it was the discount's own line — "Light & Dark 7% of
    /// these · 0.2% a pull" — from the weights the roll used.)
    var lightDarkShare: Double {
        guard !units.isEmpty else { return 0 }
        let lightDark = units.filter { $0.element.isLightOrDark }.count
        return Double(lightDark) / Double(units.count)
    }

    /// Nil when the pool is all one side of the line, which every pool now is.
    var lightDarkLine: String? {
        let share = lightDarkShare
        guard share > 0, share < 0.999 else { return nil }
        return String(format: "Light & Dark %.0f%% of these · %.3f%% a pull",
                      share * 100, share * chance * 100)
    }
}
