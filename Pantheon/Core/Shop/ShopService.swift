import Foundation

/// The bazaar: what a player can buy with what the game itself pays out.
/// There is no real-money purchase anywhere in this file or this game; every
/// price is in divinity, drachma or laurels, and the daily offering is free.
enum ShopService {

    enum Currency: String, Sendable {
        case divinity, drachma, laurels, free

        var displayName: String {
            switch self {
            case .divinity: return "divinity"
            case .drachma: return "drachma"
            case .laurels: return "laurels"
            case .free: return "free"
            }
        }

        var icon: String {
            switch self {
            case .divinity: return "sparkles"
            case .drachma: return "circle.hexagongrid.fill"
            case .laurels: return "laurel.leading"
            case .free: return "gift.fill"
            }
        }
    }

    struct Price: Equatable, Sendable {
        var currency: Currency
        var amount: Int

        static let free = Price(currency: .free, amount: 0)
    }

    /// What buying an item puts in the account.
    enum Grant: Equatable, Sendable {
        case scrolls(ScrollType, Int)
        case energy(Int)
        /// Back to the cap, or no change if already over it.
        case energyRefill
        case drachma(Int)
        case divinity(Int)
        case relic(grade: Int)
        case essences(String, Int)
        /// Whetstones or gems by `RelicStone.id`.
        case stones(String, Int)
        /// A boon cache of a grade (`BoonCache`): the Tower's milestones and
        /// the Judgment on Hell pay one in the bundle.
        case boonCache(grade: Int)
        /// A named family, by blueprint id. Only the Night Market pays in
        /// this: a duplicate becomes a skill-up, exactly as a summon's does,
        /// so a second copy is never clutter.
        case unit(String)
        case bundle([Grant])
    }

    /// Free packs for testing, and the one switch that removes them.
    ///
    /// The owner asked for "packs for free for now to test": there is no way
    /// to earn a hundred summons quickly, and a roster of seventy-nine
    /// families cannot be judged on nine units. Every item in the `testing`
    /// section costs nothing and can be taken as often as he likes.
    ///
    /// Set this to `false` and the section disappears along with its items —
    /// that is the whole removal. Nothing else in the game refers to them.
    static let testingPacksEnabled = true

    /// Every essence in the catalogue, `count` of each: the three tiers of
    /// the five elements and of Magic, eighteen grants.
    static func everyEssence(_ count: Int) -> [Grant] {
        var grants: [Grant] = []
        for element in Element.allCases {
            for tier in ["low", "mid", "high"] {
                grants.append(.essences("essence_\(element.rawValue)_\(tier)", count))
            }
        }
        for tier in ["low", "mid", "high"] {
            grants.append(.essences("essence_magic_\(tier)", count))
        }
        return grants
    }

    /// One awakening in a box: exactly what `UnitDatabase.awakeningCost`
    /// asks of the element at the 5★ recipe — the dearest bill, so the box
    /// covers a 4★'s as well with essence over. The caches exist so an
    /// awakening can be tested without a week of Halls (2026-09-11), and
    /// they READ the recipe rather than restate it: when the ladder moved
    /// the numbers on 2026-09-17 the boxes moved with it, and the subtitle
    /// (`awakeningCacheSubtitle`) is written off the same lines.
    static func awakeningCache(_ element: Element) -> [Grant] {
        awakeningBill(element).map { Grant.essences($0.id, $0.count) }
    }

    /// "Everything one fire awakening asks for at the 5★ recipe: 15 Mid
    /// Ember Essence, 10 High Ember Essence, 10 Mid Magic Essence and 5 High
    /// Magic Essence. A 4★ asks for less and keeps the rest." The bill in
    /// words, so the shelf can never promise a recipe the dais no longer asks.
    static func awakeningCacheSubtitle(_ element: Element, word: String) -> String {
        let lines = awakeningBill(element).map { "\($0.count) \(EssenceCatalog.name(for: $0.id))" }
        let listed: String
        if lines.count > 1 {
            listed = lines.dropLast().joined(separator: ", ") + " and " + lines[lines.count - 1]
        } else {
            listed = lines.joined()
        }
        return "Everything one \(word) awakening asks for at the 5★ recipe: \(listed). A 4★ asks for less and keeps the rest."
    }

    /// The 5★ recipe of an element as (id, count) lines in reading order:
    /// the element's essence before Magic, Low before Mid before High.
    private static func awakeningBill(_ element: Element) -> [(id: String, count: Int)] {
        let tiers = ["low", "mid", "high"]
        func rank(_ id: String) -> Int {
            let tier = tiers.firstIndex { id.hasSuffix("_\($0)") } ?? tiers.count
            return (id.hasPrefix("essence_magic_") ? 10 : 0) + tier
        }
        return UnitDatabase.awakeningCost(element: element, naturalStars: 5)
            .map { (id: $0.key, count: $0.value) }
            .sorted { rank($0.id) < rank($1.id) }
    }

    enum Section: String, CaseIterable, Identifiable, Sendable {
        case daily = "Daily"
        /// The rolled shelf. Its wares are not in `items` — they are derived
        /// from the save's seed by `NightMarketService`.
        case nightMarket = "Night Market"
        case testing = "Testing"
        case scrolls = "Scrolls"
        case energy = "Energy"
        case relics = "Relics"
        case essences = "Essences"
        case laurels = "Laurel exchange"

        var id: String { rawValue }
    }

    struct Item: Identifiable, Sendable {
        var id: String
        var title: String
        var subtitle: String
        var icon: String
        var price: Price
        var grant: Grant
        var section: Section
        /// Claimable once a calendar day.
        var isDaily: Bool = false
    }

    static let items: [Item] = [
        // ---- Free, repeatable, and only while `testingPacksEnabled` is true.
        Item(id: "test_scrolls", title: "A fistful of scrolls",
             subtitle: "Twenty mystical, ten pantheonic and five divine. Free, as often as you like.",
             icon: "scroll.fill", price: .free,
             grant: .bundle([.scrolls(.mystical, 20), .scrolls(.pantheonic, 10), .scrolls(.divine, 5)]),
             section: .testing),
        Item(id: "test_elemental_scrolls", title: "Every elemental scroll",
             subtitle: "Ten each of fire, water and wind, and five light and dark.",
             icon: "sparkles", price: .free,
             grant: .bundle([.scrolls(.ember, 10), .scrolls(.tide, 10), .scrolls(.gale, 10),
                             .scrolls(.lightDark, 5), .scrolls(.unknown, 20)]),
             section: .testing),
        Item(id: "test_purse", title: "A full purse",
             subtitle: "Half a million drachma and two thousand divinity.",
             icon: "circle.hexagongrid.fill", price: .free,
             grant: .bundle([.drachma(500_000), .divinity(2_000)]),
             section: .testing),
        Item(id: "test_energy", title: "Energy to burn",
             subtitle: "A full refill, and enough to clear a chapter in one sitting.",
             icon: "bolt.fill", price: .free,
             grant: .bundle([.energyRefill, .energy(200)]),
             section: .testing),
        // Every essence there is — Low, Mid and High of the five elements and
        // of Magic, sixty each — so any awakening in the game can be tested
        // from one tap (the owner, 2026-09-17: "a pack of ALL essence for
        // ALL types"). It was the five Mids, twenty magic Mid and ten magic
        // High: two awakenings' worth of magic High, and none of the Low
        // and High the campaign and the Halls drop.
        Item(id: "test_essences", title: "Every essence",
             subtitle: "Sixty of every essence: Low, Mid and High of all five elements and of Magic. Enough to awaken a whole roster; free, as often as you like.",
             icon: "drop.triangle.fill", price: .free,
             grant: .bundle(ShopService.everyEssence(60)),
             section: .testing),
        Item(id: "test_relics", title: "A crate of relics",
             subtitle: "Six of the highest grade, to see what a built unit looks like.",
             icon: "shield.lefthalf.filled", price: .free,
             grant: .bundle([.relic(grade: 6), .relic(grade: 6), .relic(grade: 6),
                             .relic(grade: 6), .relic(grade: 6), .relic(grade: 6)]),
             section: .testing),
        Item(id: "test_stones", title: "The stonecutter's crate",
             subtitle: "Ten whetstones and ten gems of every tier, to hone and gem a relic without a raid.",
             icon: "diamond.fill", price: .free,
             grant: .bundle([.stones("whetstone_rare", 10), .stones("whetstone_hero", 10), .stones("whetstone_legend", 10),
                             .stones("gem_rare", 10), .stones("gem_hero", 10), .stones("gem_legend", 10)]),
             section: .testing),

        Item(id: "daily_offering", title: "Daily offering",
             subtitle: "A mystical scroll, 2,000 drachma and 10 energy. Free, once a day.",
             icon: "gift.fill", price: .free,
             grant: .bundle([.scrolls(.mystical, 1), .drachma(2_000), .energy(10)]),
             section: .daily, isDaily: true),

        Item(id: "scroll_mystical", title: "Mystical Scroll", subtitle: "One common summon.",
             icon: "scroll.fill", price: Price(currency: .divinity, amount: 75),
             grant: .scrolls(.mystical, 1), section: .scrolls),
        Item(id: "scroll_mystical_10", title: "Ten Mystical Scrolls", subtitle: "Ten summons for the price of nine.",
             icon: "scroll.fill", price: Price(currency: .divinity, amount: 675),
             grant: .scrolls(.mystical, 10), section: .scrolls),
        Item(id: "scroll_pantheonic", title: "Pantheon Scroll", subtitle: "A summon from one pantheon's banner.",
             icon: "scroll.fill", price: Price(currency: .divinity, amount: 100),
             grant: .scrolls(.pantheonic, 1), section: .scrolls),
        Item(id: "scroll_unknown", title: "Unknown Scroll", subtitle: "The commons of every pantheon, 3★ only. Drachma, not divinity.",
             icon: "questionmark.circle.fill", price: Price(currency: .drachma, amount: 5_000),
             grant: .scrolls(.unknown, 1), section: .scrolls),
        Item(id: "scroll_unknown_10", title: "Ten Unknown Scrolls", subtitle: "Ten commons for the price of nine.",
             icon: "questionmark.circle.fill", price: Price(currency: .drachma, amount: 45_000),
             grant: .scrolls(.unknown, 10), section: .scrolls),
        Item(id: "scroll_divine", title: "Divine Scroll", subtitle: "Never less than a 4★. 12% chance of a 5★.",
             icon: "crown.fill", price: Price(currency: .divinity, amount: 600),
             grant: .scrolls(.divine, 1), section: .scrolls),
        Item(id: "scroll_light_dark", title: "Light & Dark Scroll", subtitle: "Only Radiance and Umbra units, of every pantheon.",
             icon: "circle.lefthalf.filled", price: Price(currency: .divinity, amount: 450),
             grant: .scrolls(.lightDark, 1), section: .scrolls),
        Item(id: "scroll_fire", title: "Fire Scroll", subtitle: "Only Fire units, of every pantheon.",
             icon: "flame.fill", price: Price(currency: .divinity, amount: 200),
             grant: .scrolls(.ember, 1), section: .scrolls),
        Item(id: "scroll_water", title: "Water Scroll", subtitle: "Only Water units, of every pantheon.",
             icon: "drop.fill", price: Price(currency: .divinity, amount: 200),
             grant: .scrolls(.tide, 1), section: .scrolls),
        Item(id: "scroll_wind", title: "Wind Scroll", subtitle: "Only Wind units, of every pantheon.",
             icon: "wind", price: Price(currency: .divinity, amount: 200),
             grant: .scrolls(.gale, 1), section: .scrolls),

        Item(id: "energy_30", title: "Energy ×30", subtitle: "Thirty energy, over the cap if need be.",
             icon: "bolt.fill", price: Price(currency: .divinity, amount: 30),
             grant: .energy(30), section: .energy),
        Item(id: "energy_refill", title: "Full refill", subtitle: "Back to the cap.",
             icon: "bolt.circle.fill", price: Price(currency: .divinity, amount: 60),
             grant: .energyRefill, section: .energy),

        Item(id: "relic_pack_4", title: "Relic pack, 4★", subtitle: "One random 4★ relic, any set, any slot.",
             icon: "shield.lefthalf.filled", price: Price(currency: .drachma, amount: 25_000),
             grant: .relic(grade: 4), section: .relics),
        Item(id: "relic_pack_5", title: "Relic pack, 5★", subtitle: "One random 5★ relic, any set, any slot.",
             icon: "shield.lefthalf.filled", price: Price(currency: .divinity, amount: 150),
             grant: .relic(grade: 5), section: .relics),

        Item(id: "essence_magic_mid_5", title: "Mid Magic Essence ×5", subtitle: "The common awakening material.",
             icon: "drop.triangle.fill", price: Price(currency: .drachma, amount: 15_000),
             grant: .essences("essence_magic_mid", 5), section: .essences),
        Item(id: "essence_magic_high_2", title: "High Magic Essence ×2", subtitle: "The rare awakening material.",
             icon: "drop.triangle.fill", price: Price(currency: .divinity, amount: 80),
             grant: .essences("essence_magic_high", 2), section: .essences),
        // One awakening in a box, read off the recipe itself at the 5★ grade
        // (`awakeningCache`): the element's Mid and High and the Magic Mid and
        // High in the counts `UnitDatabase.awakeningCost` asks, the subtitle
        // written off the same lines; a 4★ needs less of each and keeps the
        // rest. The Testing stall's `test_essences` pack is the other road.
        Item(id: "awakening_cache_ember", title: "Cache of Embers", subtitle: ShopService.awakeningCacheSubtitle(.ember, word: "fire"),
             icon: "flame.fill", price: Price(currency: .drachma, amount: 60_000),
             grant: .bundle(ShopService.awakeningCache(.ember)),
             section: .essences),
        Item(id: "awakening_cache_tide", title: "Cache of the Tide", subtitle: ShopService.awakeningCacheSubtitle(.tide, word: "water"),
             icon: "drop.fill", price: Price(currency: .drachma, amount: 60_000),
             grant: .bundle(ShopService.awakeningCache(.tide)),
             section: .essences),
        Item(id: "awakening_cache_gale", title: "Cache of the Gale", subtitle: ShopService.awakeningCacheSubtitle(.gale, word: "wind"),
             icon: "wind", price: Price(currency: .drachma, amount: 60_000),
             grant: .bundle(ShopService.awakeningCache(.gale)),
             section: .essences),
        Item(id: "awakening_cache_radiance", title: "Cache of Radiance", subtitle: ShopService.awakeningCacheSubtitle(.radiance, word: "light"),
             icon: "sun.max.fill", price: Price(currency: .divinity, amount: 300),
             grant: .bundle(ShopService.awakeningCache(.radiance)),
             section: .essences),
        Item(id: "awakening_cache_umbra", title: "Cache of Umbra", subtitle: ShopService.awakeningCacheSubtitle(.umbra, word: "dark"),
             icon: "moon.fill", price: Price(currency: .divinity, amount: 300),
             grant: .bundle(ShopService.awakeningCache(.umbra)),
             section: .essences),

        Item(id: "relic_laurels_6", title: "Champion's relic, 6★", subtitle: "One random 6★ relic, for arena laurels.",
             icon: "shield.lefthalf.filled", price: Price(currency: .laurels, amount: 300),
             grant: .relic(grade: 6), section: .laurels),
        Item(id: "gem_laurels_legend", title: "Legend Gem", subtitle: "Replaces one sub stat with a stat of your choosing, at the top range.",
             icon: "diamond.fill", price: Price(currency: .laurels, amount: 400),
             grant: .stones("gem_legend", 1), section: .laurels),
        Item(id: "whetstone_laurels_legend", title: "Legend Whetstone", subtitle: "Hones one sub stat by the top range.",
             icon: "seal.fill", price: Price(currency: .laurels, amount: 250),
             grant: .stones("whetstone_legend", 1), section: .laurels),
        Item(id: "scroll_laurels_pantheonic", title: "Pantheon Scroll", subtitle: "A banner summon, for arena laurels.",
             icon: "sparkles", price: Price(currency: .laurels, amount: 150),
             grant: .scrolls(.pantheonic, 1), section: .laurels),
        Item(id: "scroll_laurels_light_dark", title: "Light & Dark Scroll", subtitle: "The sun's and the night's, for arena laurels.",
             icon: "circle.lefthalf.filled", price: Price(currency: .laurels, amount: 250),
             grant: .scrolls(.lightDark, 1), section: .laurels),
    ]

    static func item(_ id: String) -> Item? { items.first(where: { $0.id == id }) }

    static func items(in section: Section) -> [Item] {
        guard section != .testing || testingPacksEnabled else { return [] }
        return items.filter { $0.section == section }
    }

    /// The sections a shop screen should show. Hides Testing in one place
    /// rather than in every caller.
    static var visibleSections: [Section] {
        Section.allCases.filter { $0 != .testing || testingPacksEnabled }
    }

    enum ShopError: Error, LocalizedError {
        case cannotAfford(Price)
        case alreadyClaimedToday

        var errorDescription: String? {
            switch self {
            case .cannotAfford(let price):
                return "That costs \(price.amount) \(price.currency.displayName)."
            case .alreadyClaimedToday:
                return "Today's offering is already claimed. Come back tomorrow."
            }
        }
    }

    static func canAfford(_ price: Price, wallet: Wallet) -> Bool {
        switch price.currency {
        case .divinity: return wallet.divinity >= price.amount
        case .drachma: return wallet.drachma >= price.amount
        case .laurels: return wallet.laurels >= price.amount
        case .free: return true
        }
    }

    /// The daily offering is claimable once per calendar day, in the
    /// player's own calendar.
    static func isDailyAvailable(player: Player, now: Date = Date()) -> Bool {
        guard let last = player.lastDailyPackClaim else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }

    /// Pays and grants. Returns the grants flattened, for the receipt.
    @discardableResult
    static func buy(
        _ item: Item,
        player: inout Player,
        rng: inout SeededRandom,
        now: Date = Date()
    ) throws -> [Grant] {
        if item.isDaily {
            guard isDailyAvailable(player: player, now: now) else { throw ShopError.alreadyClaimedToday }
        }
        guard canAfford(item.price, wallet: player.wallet) else { throw ShopError.cannotAfford(item.price) }

        switch item.price.currency {
        case .divinity: player.wallet.divinity -= item.price.amount
        case .drachma: player.wallet.drachma -= item.price.amount
        case .laurels: player.wallet.laurels -= item.price.amount
        case .free: break
        }
        if item.isDaily { player.lastDailyPackClaim = now }

        var granted: [Grant] = []
        apply(item.grant, to: &player, rng: &rng, into: &granted)
        return granted
    }

    /// Puts a grant in the account and returns it flattened: the receipts of
    /// missions, feats and the login gift as well as purchases.
    @discardableResult
    static func grant(_ grant: Grant, to player: inout Player, rng: inout SeededRandom) -> [Grant] {
        var granted: [Grant] = []
        apply(grant, to: &player, rng: &rng, into: &granted)
        return granted
    }

    private static func apply(_ grant: Grant, to player: inout Player, rng: inout SeededRandom, into granted: inout [Grant]) {
        switch grant {
        case .scrolls(let scroll, let count):
            player.wallet.add(scroll, count)
            granted.append(grant)
        case .energy(let amount):
            player.wallet.energy += amount
            granted.append(grant)
        case .energyRefill:
            player.wallet.energy = max(player.wallet.energy, player.wallet.maxEnergy)
            granted.append(grant)
        case .drachma(let amount):
            player.wallet.drachma += amount
            granted.append(grant)
        case .divinity(let amount):
            player.wallet.divinity += amount
            granted.append(grant)
        case .relic(let grade):
            let relic = RelicService.generate(grade: grade, rng: &rng)
            player.relics.append(relic)
            granted.append(grant)
        case .essences(let id, let count):
            player.essences[id, default: 0] += count
            granted.append(grant)
        case .stones(let id, let count):
            RelicService.addStones(id, count, player: &player)
            granted.append(grant)
        case .boonCache(let grade):
            BoonService.addCache(BoonCache(grade: grade, seed: rng.next(), source: "Chest"), player: &player)
            granted.append(grant)
        case .unit(let blueprintID):
            if let blueprint = UnitDatabase.blueprint(blueprintID) {
                let isNew = !player.codex.contains(blueprint.id)
                player.codex.insert(blueprint.id)
                var unit = Unit(blueprint: blueprint)
                unit.acquiredFrom = "night_market"
                if !isNew, let existing = player.units.firstIndex(where: { $0.blueprintID == blueprint.id }) {
                    _ = ProgressionService.applySkillUp(to: &player.units[existing], using: &rng)
                }
                player.units.append(unit)
                granted.append(grant)
            }
        case .bundle(let parts):
            for part in parts { apply(part, to: &player, rng: &rng, into: &granted) }
        }
    }

    /// One line per grant, for the receipt.
    static func describe(_ grant: Grant) -> String {
        switch grant {
        case .scrolls(let scroll, let count): return "\(scroll.displayName) ×\(count)"
        case .energy(let amount): return "Energy +\(amount)"
        case .energyRefill: return "Energy refilled"
        case .drachma(let amount): return "Drachma +\(amount)"
        case .divinity(let amount): return "Divinity +\(amount)"
        case .relic(let grade): return "\(grade)★ relic"
        case .essences(let id, let count): return "\(EssenceCatalog.name(for: id)) ×\(count)"
        case .stones(let id, let count): return "\(RelicStone.from(id: id)?.displayName ?? id) ×\(count)"
        case .boonCache(let grade): return "\(grade)★ boon cache"
        case .unit(let id): return UnitDatabase.blueprint(id)?.name ?? id
        case .bundle(let parts): return parts.map(describe).joined(separator: ", ")
        }
    }
}
