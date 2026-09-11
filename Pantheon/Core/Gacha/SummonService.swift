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
        subtitle: "Every soul the summoning circle has ever known.",
        scroll: .mystical,
        pool: [],
        featured: [],
        legendaryPity: nil,
        rarePity: 20,
        artName: "banner_standard",
        pantheon: nil
    )

    /// Every summonable of one pantheon, for a banner that promises it.
    static func pool(of pantheon: Pantheon) -> [String] {
        UnitDatabase.summonPool.filter { UnitDatabase.blueprint($0)?.pantheon == pantheon }
    }

    /// The launch banner: Egypt only. The pool is the whole Egyptian roster, so
    /// a common roll lands on a Shabti, a rare one on an Anubis and a legendary
    /// on Sekhmet or Thoth, and the Anubis family is featured at double weight
    /// within its grade. A pantheon banner that handed out the other pantheon's
    /// commons was the "the Greek banner is all Anubis" complaint.
    static let duatOpens = Banner(
        id: "duat_opens",
        title: "The Duat Opens",
        subtitle: "The scales are unattended. Egypt answers the circle — Anubis first, in fire, in water, in wind, in light and in shadow.",
        scroll: .pantheonic,
        pool: pool(of: .egyptian),
        featured: UnitDatabase.summonPool.filter { $0.hasPrefix("anubis_") },
        legendaryPity: 90,
        rarePity: 12,
        artName: "banner_duat_opens",
        pantheon: .egyptian
    )

    /// The Greek banner: Greece only. Zeus is featured in all five elements;
    /// the rest of Olympus — Ares, the heroes, the creatures and the hoplite —
    /// fills the grades beneath and beside him. It is offered once at least
    /// one Greek unit has its portraits in the bundle.
    static let olympusStirs = Banner(
        id: "olympus_stirs",
        title: "Olympus Stirs",
        subtitle: "The sky opens over Greece. Gods, heroes and the creatures of the old country answer — Zeus first, in every element.",
        scroll: .pantheonic,
        pool: pool(of: .greek),
        featured: UnitDatabase.summonPool.filter { $0.hasPrefix("zeus_") },
        legendaryPity: 90,
        rarePity: 10,
        artName: "banner_olympus_stirs",
        pantheon: .greek
    )

    /// The Norse banner: Yggdrasil only. Odin is featured in every element;
    /// Thor, Freya and Loki share his grade, the Æsir and the giant's daughter
    /// fill the one beneath, and the barrow-dead, the trolls, the valkyries
    /// and the dwarves are its commons. Offered once a Norse unit has cards.
    static let ravensGather = Banner(
        id: "ravens_gather",
        title: "The Ravens Gather",
        subtitle: "Two ravens leave the tree at dawn. Yggdrasil answers the circle — Odin first, in every element.",
        scroll: .pantheonic,
        pool: pool(of: .norse),
        featured: UnitDatabase.summonPool.filter { $0.hasPrefix("odin_") },
        legendaryPity: 90,
        rarePity: 10,
        artName: "banner_ravens_gather",
        pantheon: .norse
    )

    /// The Roman banner: the Seven Hills only. Mars is featured in every
    /// element; Minerva shares his grade, the gods of the Forum fill the one
    /// beneath, and the centurion, the gladiator and the Vestal are its
    /// commons. Offered once a Roman unit has cards (batch 4).
    static let eagleRises = Banner(
        id: "eagle_rises",
        title: "The Eagle Rises",
        subtitle: "The standards go up on the Capitol. Rome answers the circle — Mars first, in every element.",
        scroll: .pantheonic,
        pool: pool(of: .roman),
        featured: UnitDatabase.summonPool.filter { $0.hasPrefix("mars_") },
        legendaryPity: 90,
        rarePity: 10,
        artName: "banner_eagle_rises",
        pantheon: .roman
    )

    /// The Chinese banner: the Jade Court only. The Monkey King is featured
    /// in every element; the Azure Dragon shares his grade, the court fills
    /// the one beneath, and the fox, the hopping dead and the clay soldier
    /// are its commons. Offered once a Jade Court unit has cards.
    static let jadeCourtOpens = Banner(
        id: "jade_court_opens",
        title: "The Jade Court Opens",
        subtitle: "The gates of Heaven stand open and the Monkey King is first through them. The Jade Court answers the circle — Sun Wukong in every element.",
        scroll: .pantheonic,
        pool: pool(of: .chinese),
        featured: UnitDatabase.summonPool.filter { $0.hasPrefix("sun_wukong_") },
        legendaryPity: 90,
        rarePity: 10,
        artName: "banner_jade_court",
        pantheon: .chinese
    )

    /// The summon pool filtered by a rule: what the scroll banners are made of.
    static func pool(where keep: (UnitBlueprint) -> Bool) -> [String] {
        UnitDatabase.summonPool.filter { id in UnitDatabase.blueprint(id).map(keep) ?? false }
    }

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
        subtitle: "Never less than a 4★, from every pantheon. The rarest scroll there is.",
        scroll: .divine,
        pool: pool(where: { $0.naturalStars >= 4 }),
        featured: [],
        legendaryPity: 40,
        rarePity: nil,
        artName: "banner_divine",
        pantheon: nil
    )

    static let lightAndDark = Banner(
        id: "light_dark_scroll",
        title: "Light & Dark",
        subtitle: "Only the sun's and the night's: every Radiance and Umbra unit of every pantheon.",
        scroll: .lightDark,
        pool: pool(where: { $0.element == .radiance || $0.element == .umbra }),
        featured: [],
        legendaryPity: 120,
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

        for _ in 0..<count {
            let result = single(banner: banner, pity: &pity, player: &player, rng: &rng)
            results.append(result)
        }

        player.summonPity[banner.id] = pity
        player.totalSummons += count
        return results
    }

    private static func single(
        banner: Banner,
        pity: inout PityState,
        player: inout Player,
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
        player.codex.insert(blueprint.id)

        var unit = Unit(blueprint: blueprint)
        unit.acquiredFrom = banner.id

        // A duplicate becomes a skill-up rather than clutter.
        if !isNew, let existingIndex = player.units.firstIndex(where: { $0.blueprintID == blueprint.id }) {
            _ = ProgressionService.applySkillUp(to: &player.units[existingIndex], using: &rng)
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
            fromPity: fromPity
        )
    }

    private static func rollStars(scroll: ScrollType, rng: inout SeededRandom) -> Int {
        let entries = scroll.odds.map { (value: $0.key, weight: $0.value) }
            .sorted { $0.value < $1.value }
        return rng.pickWeighted(entries) ?? 3
    }

    /// How much rarer a Light or Dark unit is than the same grade in fire,
    /// water or wind, inside a pool that holds all five.
    ///
    /// The owner: "Summon rates for LD 4 and 5 star need to be turned down. I
    /// want those to be the strongest and coolest to collect." Every unit of a
    /// grade used to be equally likely, and with five elements that made two
    /// of every five pulls of a grade Light or Dark — forty per cent. Nothing
    /// a player sees two-fifths of the time is a trophy.
    ///
    /// At 0.12, a five-star roll lands Light or Dark about seven per cent of
    /// the time rather than forty, so on a pantheon scroll's 3% five-star rate
    /// that is roughly one pull in four hundred and fifty. At 0.25 a four-star
    /// is about fourteen per cent. Three-star commons are untouched: the Hall
    /// of Ka needs its fodder in every element, and the owner asked for four
    /// and five.
    ///
    /// The Light & Dark scroll is deliberately NOT special-cased. Its pool is
    /// nothing but Radiance and Umbra, so a factor applied to every candidate
    /// alike cancels out and the scroll keeps the rate it always had. That is
    /// the point of it: it becomes the only reliable road to these units
    /// rather than one road among five.
    static let lightDarkWeight: [Int: Double] = [4: 0.25, 5: 0.12]

    /// One weight, used everywhere a unit is drawn, so no path can quietly
    /// ignore it. The featured family is doubled as before; a Light or Dark
    /// unit of a gated grade is cut by the table above. Both apply at once:
    /// the featured god's dark form is twice as likely as another dark unit
    /// and still far rarer than his fire form, which is exactly the shape
    /// wanted.
    static func weight(of blueprint: UnitBlueprint, on banner: Banner) -> Double {
        var weight = banner.featured.contains(blueprint.id) ? 2.0 : 1.0
        if blueprint.element == .radiance || blueprint.element == .umbra {
            weight *= lightDarkWeight[blueprint.naturalStars] ?? 1.0
        }
        return weight
    }

    /// Picks a unit of the given grade, honouring the featured double-weight,
    /// the Light and Dark discount, and the 50/50-then-guaranteed rule on the
    /// featured slot.
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
            // WEIGHTED, not uniform. A banner features a god in all five of
            // his elements, so an even draw here handed out his Radiance and
            // his Umbra two times in five — the featured slot was the widest
            // hole in the discount, and the one a player uses most.
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

    private static func eligibleIDs(for banner: Banner) -> [String] {
        banner.pool.isEmpty ? UnitDatabase.summonPool : banner.pool
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

    /// What share of this grade's rolls comes out Radiance or Umbra, and what
    /// that is of every pull. A discount the player cannot see is worse than a
    /// generous rate: he would only ever learn it by pulling for a week and
    /// feeling cheated. The table says the number.
    ///
    /// Computed from the same weights the roll uses, so the two cannot drift.
    /// The featured double is left out of it — a banner doubles a god in all
    /// five of his elements at once, so it very nearly cancels — which makes
    /// this the honest shape of the rate rather than a figure to the last
    /// decimal.
    var lightDarkShare: Double {
        let factor = SummonService.lightDarkWeight[stars] ?? 1.0
        var lightDark = 0.0
        var rest = 0.0
        for unit in units {
            if unit.element == .radiance || unit.element == .umbra {
                lightDark += factor
            } else {
                rest += 1
            }
        }
        let total = lightDark + rest
        return total > 0 ? lightDark / total : 0
    }

    /// Nil when this grade is not discounted, or when the pool is all one
    /// side of the line — the Light & Dark scroll, where every unit is
    /// Radiance or Umbra and the share is a meaningless 100%.
    var lightDarkLine: String? {
        guard SummonService.lightDarkWeight[stars] != nil else { return nil }
        let share = lightDarkShare
        guard share > 0, share < 0.999 else { return nil }
        return String(format: "Light & Dark %.0f%% of these · %.3f%% a pull",
                      share * 100, share * chance * 100)
    }
}
