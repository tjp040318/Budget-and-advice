import Foundation

/// The floor under bad luck: a point for every summon, and a unit the player
/// NAMES once he has enough of them.
///
/// **Why the game needs it.** 2026 is being called the guaranteed-banner era
/// — selector tickets, sparks, guaranteed rate-ups and "pick any unit"
/// anniversary tickets went from goodwill gestures to table stakes. Blue
/// Archive runs a Recruitment Point per pull with 200 points buying the
/// featured character outright; Epic Seven's Mystic counter carries between
/// banners without expiring; Genshin's Epitomized Path lets a player commit
/// to one of two weapons. Pity already stops a drought; mileage is what
/// stops the WRONG FIVE STAR, which is the complaint a hard pity cannot
/// answer.
///
/// **Per banner, not one pool.** Blue Archive's points expire with the
/// banner and Epic Seven's do not, and the difference is that Blue Archive
/// runs limited banners. Every banner here is PERMANENT, so points can be
/// per-banner and still never be lost — and a banner's points buying a unit
/// from that banner's own pool is the whole idea. One global pool would let
/// a player farm the cheap Unknown Scroll and cash out a 5★ god, which is
/// the exchange this is meant to be a floor under, not a shortcut around.
///
/// **And that is why the price is in DIVINITY, converted to pulls.** A pull
/// is not one price across the game: a Pantheon Scroll is 100 divinity in
/// the bazaar and a Divine Scroll is 600. A flat "150 points" would mean
/// 15,000 divinity of pantheon pulls or 90,000 of divine ones for the same
/// unit. So each grade has a divinity target and the price in points is that
/// target divided by what a pull of THIS banner's scroll costs, which lands
/// the pantheon banner on the genre's own numbers — 150, 60 and 20 — and
/// scales the rest honestly.
enum MileageService {

    /// The price has TWO floors, and it needs both.
    ///
    /// The first cut priced a unit at a flat divinity target divided by what a
    /// pull costs — 15,000 divinity for any 5★ — which lands the pantheon
    /// banner on the genre's own 150 and is plainly right there. Then
    /// `balance.py --mileage` reported the ratio it exists to report: on the
    /// **Divine Scroll** that price was 0.62 of what the hard pity costs, and
    /// on **Light & Dark** 0.28. On those banners mileage would not have been
    /// a floor under bad luck, it would have been the fast road, and the pity
    /// counter beside it would have meant nothing.
    ///
    /// The cause is that the divinity target is flat while the hard pity is
    /// not: a Divine Scroll guarantees a 5★ in 40 pulls because its 5★ rate
    /// is 12%, and Light & Dark takes 120. So the price is anchored to the
    /// BANNER'S OWN counter — 1.7 times whatever that banner's guarantee
    /// costs — and the divinity target is kept as a second floor underneath
    /// it, for the two banners that have no hard pity at all.
    ///
    /// `max` of the two, so a unit is never cheaper than 1.7 guarantees AND
    /// never cheaper than its worth in divinity.
    static let divinityTarget: [Int: Int] = [3: 2_000, 4: 6_000, 5: 15_000]

    /// How much dearer naming the unit you want is than letting the counter
    /// hand you a random one. Under 1.0 mileage replaces pity; far over it,
    /// nobody ever reaches it.
    static let pityMultiple = 1.7

    /// What a grade is worth against the banner's best. Proportional to the
    /// divinity targets above, so the three prices keep their shape on every
    /// banner rather than each being anchored separately.
    static let gradeShare: [Int: Double] = [5: 1.0, 4: 0.40, 3: 0.135]

    /// What one pull of a banner is worth. The Unknown Scroll is not sold for
    /// divinity at all — it is drachma, in the bazaar — so it is valued at
    /// the cheapest thing that is, which makes its commons dear in points and
    /// cheap in effort, exactly as they should be.
    static func pullValue(_ scroll: ScrollType) -> Int {
        scroll.divinityPrice ?? 25
    }

    /// The number of pulls the price is anchored to: the banner's hard pity
    /// where it has one, and otherwise the pulls it takes on average to reach
    /// the best grade the banner can give.
    static func anchorPulls(for banner: Banner) -> Int {
        if let pity = banner.legendaryPity { return pity }
        let odds = banner.scroll.odds
        let best = odds.keys.max() ?? 3
        let chance = max(0.0001, odds[best] ?? 1.0)
        return max(1, Int((1.0 / chance).rounded()))
    }

    /// Points needed for one unit of a grade on a banner. Never less than
    /// ten, so no banner can hand out a unit for a handful of pulls.
    static func price(stars: Int, on banner: Banner) -> Int {
        let anchored = Double(anchorPulls(for: banner)) * pityMultiple * (gradeShare[stars] ?? 1.0)
        let target = Double(divinityTarget[stars] ?? 15_000) / Double(pullValue(banner.scroll))
        return max(10, Int(max(anchored, target).rounded()))
    }

    /// Points in hand on a banner.
    static func points(on banner: Banner, player: Player) -> Int {
        player.summonMileage?[banner.id] ?? 0
    }

    /// Earned on every summon, whatever it gave. Called from `SummonService`
    /// so no path that spends a scroll can forget to pay the point.
    static func earn(_ count: Int, on banner: Banner, player: inout Player) {
        var ledger = player.summonMileage ?? [:]
        ledger[banner.id, default: 0] += count
        player.summonMileage = ledger
    }

    /// What this banner's points can be spent on, dearest first, so the thing
    /// a player is saving for is the first row rather than the last.
    static func catalogue(for banner: Banner) -> [Offer] {
        SummonService.eligible(for: banner)
            .filter(\.hasShippedArt)
            .map { Offer(blueprint: $0, price: price(stars: $0.naturalStars, on: banner)) }
            .sorted { left, right in
                if left.blueprint.naturalStars != right.blueprint.naturalStars {
                    return left.blueprint.naturalStars > right.blueprint.naturalStars
                }
                return left.blueprint.name < right.blueprint.name
            }
    }

    struct Offer: Identifiable, Sendable {
        var blueprint: UnitBlueprint
        var price: Int
        var id: String { blueprint.id }
    }

    enum MileageError: Error, LocalizedError {
        case notEnoughPoints(needed: Int)
        case notOnThisBanner

        var errorDescription: String? {
            switch self {
            case .notEnoughPoints(let needed): return "That costs \(needed) mileage on this banner."
            case .notOnThisBanner: return "That unit is not in this banner's pool."
            }
        }
    }

    /// Spends the points and hands over the unit. A duplicate becomes a
    /// skill-up exactly as a summon's does — this is a summon the player
    /// chose, not a different kind of acquisition.
    @discardableResult
    static func redeem(
        _ offer: Offer,
        on banner: Banner,
        player: inout Player,
        rng: inout SeededRandom
    ) throws -> SummonResult {
        guard SummonService.eligible(for: banner).contains(where: { $0.id == offer.blueprint.id }) else {
            throw MileageError.notOnThisBanner
        }
        let price = price(stars: offer.blueprint.naturalStars, on: banner)
        guard points(on: banner, player: player) >= price else {
            throw MileageError.notEnoughPoints(needed: price)
        }

        var ledger = player.summonMileage ?? [:]
        ledger[banner.id, default: 0] -= price
        player.summonMileage = ledger

        let isNew = !player.codex.contains(offer.blueprint.id)
        player.codex.insert(offer.blueprint.id)

        var unit = Unit(blueprint: offer.blueprint)
        unit.acquiredFrom = banner.id
        if !isNew, let index = player.units.firstIndex(where: { $0.blueprintID == offer.blueprint.id }) {
            _ = ProgressionService.applySkillUp(to: &player.units[index], using: &rng)
        }
        player.units.append(unit)

        return SummonResult(
            unit: unit,
            blueprint: offer.blueprint,
            stars: unit.stars,
            isNew: isNew,
            isFeatured: banner.featured.contains(offer.blueprint.id),
            fromPity: false
        )
    }
}

/// The one 4★ a new summoner picks for himself, before the dice get a vote.
///
/// Epic Seven's **Selective Summon** at account creation is credited as one
/// of its biggest free-to-play improvements, and the 2026 round-up puts the
/// day-one selector on the table-stakes list. The point of it is not the
/// unit — it is that the first thing a player does in a gacha is a CHOICE,
/// so the first face in his collection is one he wanted.
enum SelectorService {

    /// Six candidates, one per element where the roster allows, drawn from
    /// the 4★ tier of the pantheon the game opens in.
    ///
    /// DERIVED rather than a hand-written list, so it cannot name a family
    /// whose cards have not been painted; and sorted by id rather than rolled,
    /// so the six are the same six every launch — a shortlist that changed
    /// under the player between one look and the next would read as a bug.
    static func candidates() -> [UnitBlueprint] {
        let pool = SummonService.eligible(for: Banner.duatOpens)
            .filter { $0.naturalStars == 4 && $0.hasShippedArt }
            .sorted { $0.id < $1.id }

        var seen: Set<Element> = []
        var picked: [UnitBlueprint] = []
        for blueprint in pool where !seen.contains(blueprint.element) {
            seen.insert(blueprint.element)
            picked.append(blueprint)
        }
        // A roster that has fewer than five elements at 4★ falls back to the
        // rest of the tier rather than showing two cards.
        if picked.count < 5 {
            for blueprint in pool where !picked.contains(where: { $0.id == blueprint.id }) {
                picked.append(blueprint)
                if picked.count >= 5 { break }
            }
        }
        return picked
    }

    /// Owed until it is taken, and only while the roster can honour it.
    static func isOwed(_ player: Player) -> Bool {
        (player.selectorClaimed ?? false) == false && !candidates().isEmpty
    }

    /// Hands over the chosen unit and closes the offer for good.
    @discardableResult
    static func claim(_ blueprint: UnitBlueprint, player: inout Player) -> SummonResult? {
        guard isOwed(player) else { return nil }
        guard candidates().contains(where: { $0.id == blueprint.id }) else { return nil }

        let isNew = !player.codex.contains(blueprint.id)
        player.codex.insert(blueprint.id)
        var unit = Unit(blueprint: blueprint)
        unit.acquiredFrom = "selector"
        player.units.append(unit)
        player.selectorClaimed = true

        return SummonResult(
            unit: unit,
            blueprint: blueprint,
            stars: unit.stars,
            isNew: isNew,
            isFeatured: false,
            fromPity: false
        )
    }
}
