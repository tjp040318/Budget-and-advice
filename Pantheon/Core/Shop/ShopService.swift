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

    enum Section: String, CaseIterable, Identifiable, Sendable {
        case daily = "Daily"
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
        Item(id: "test_essences", title: "Every essence",
             subtitle: "Twenty of each element's essence, twenty mid and ten high magic essence: enough to awaken a team.",
             icon: "drop.triangle.fill", price: .free,
             grant: .bundle([.essences("essence_ember_mid", 20), .essences("essence_tide_mid", 20),
                             .essences("essence_gale_mid", 20), .essences("essence_radiance_mid", 20),
                             .essences("essence_umbra_mid", 20), .essences("essence_magic_mid", 20),
                             .essences("essence_magic_high", 10)]),
             section: .testing),
        Item(id: "test_relics", title: "A crate of relics",
             subtitle: "Six of the highest grade, to see what a built unit looks like.",
             icon: "shield.lefthalf.filled", price: .free,
             grant: .bundle([.relic(grade: 6), .relic(grade: 6), .relic(grade: 6),
                             .relic(grade: 6), .relic(grade: 6), .relic(grade: 6)]),
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
        // One awakening in a box: a 5★'s bill of its element's essence and the
        // magic ones (`UnitDatabase.family`: 15 element, 10 mid magic, 5 high).
        Item(id: "awakening_cache_ember", title: "Cache of Embers", subtitle: "Everything one fire awakening asks for.",
             icon: "flame.fill", price: Price(currency: .drachma, amount: 60_000),
             grant: .bundle([.essences("essence_ember_mid", 15), .essences("essence_magic_mid", 10), .essences("essence_magic_high", 5)]),
             section: .essences),
        Item(id: "awakening_cache_tide", title: "Cache of the Tide", subtitle: "Everything one water awakening asks for.",
             icon: "drop.fill", price: Price(currency: .drachma, amount: 60_000),
             grant: .bundle([.essences("essence_tide_mid", 15), .essences("essence_magic_mid", 10), .essences("essence_magic_high", 5)]),
             section: .essences),
        Item(id: "awakening_cache_gale", title: "Cache of the Gale", subtitle: "Everything one wind awakening asks for.",
             icon: "wind", price: Price(currency: .drachma, amount: 60_000),
             grant: .bundle([.essences("essence_gale_mid", 15), .essences("essence_magic_mid", 10), .essences("essence_magic_high", 5)]),
             section: .essences),
        Item(id: "awakening_cache_radiance", title: "Cache of Radiance", subtitle: "Everything one light awakening asks for.",
             icon: "sun.max.fill", price: Price(currency: .divinity, amount: 300),
             grant: .bundle([.essences("essence_radiance_mid", 15), .essences("essence_magic_mid", 10), .essences("essence_magic_high", 5)]),
             section: .essences),
        Item(id: "awakening_cache_umbra", title: "Cache of Umbra", subtitle: "Everything one dark awakening asks for.",
             icon: "moon.fill", price: Price(currency: .divinity, amount: 300),
             grant: .bundle([.essences("essence_umbra_mid", 15), .essences("essence_magic_mid", 10), .essences("essence_magic_high", 5)]),
             section: .essences),

        Item(id: "relic_laurels_6", title: "Champion's relic, 6★", subtitle: "One random 6★ relic, for arena laurels.",
             icon: "shield.lefthalf.filled", price: Price(currency: .laurels, amount: 300),
             grant: .relic(grade: 6), section: .laurels),
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
        case .bundle(let parts): return parts.map(describe).joined(separator: ", ")
        }
    }
}
