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

    static let all: [Banner] = [duatOpens] + (olympusStirs.pool.isEmpty ? [] : [olympusStirs]) + [standard]
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

    /// Picks a unit of the given grade, honouring the featured double-weight and
    /// the 50/50-then-guaranteed rule on the featured slot.
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
            let weighted = fallback.map { blueprint -> (value: UnitBlueprint, weight: Double) in
                (blueprint, banner.featured.contains(blueprint.id) ? 2.0 : 1.0)
            }
            return rng.pickWeighted(weighted) ?? fallback[0]
        }

        let featuredHere = candidates.filter { banner.featured.contains($0.id) }

        if stars >= 5, !featuredHere.isEmpty {
            if pity.featuredGuaranteed {
                pity.featuredGuaranteed = false
                return rng.pickMutating(featuredHere) ?? featuredHere[0]
            }
            if rng.chance(0.5) {
                return rng.pickMutating(featuredHere) ?? featuredHere[0]
            }
            let others = candidates.filter { !banner.featured.contains($0.id) }
            if others.isEmpty {
                // Only the featured unit exists at this grade; the 50/50 is moot.
                return featuredHere[0]
            }
            pity.featuredGuaranteed = true
            return rng.pickMutating(others) ?? others[0]
        }

        let weighted = candidates.map { blueprint -> (value: UnitBlueprint, weight: Double) in
            (blueprint, banner.featured.contains(blueprint.id) ? 2.0 : 1.0)
        }
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
}
