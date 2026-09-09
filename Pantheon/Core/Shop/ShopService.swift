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
        case relic(grade: Int)
        case essences(String, Int)
        case bundle([Grant])
    }

    enum Section: String, CaseIterable, Identifiable, Sendable {
        case daily = "Daily"
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

        Item(id: "relic_laurels_6", title: "Champion's relic, 6★", subtitle: "One random 6★ relic, for arena laurels.",
             icon: "shield.lefthalf.filled", price: Price(currency: .laurels, amount: 300),
             grant: .relic(grade: 6), section: .laurels),
    ]

    static func item(_ id: String) -> Item? { items.first(where: { $0.id == id }) }

    static func items(in section: Section) -> [Item] { items.filter { $0.section == section } }

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
        case .relic(let grade): return "\(grade)★ relic"
        case .essences(let id, let count): return "\(EssenceCatalog.name(for: id)) ×\(count)"
        case .bundle(let parts): return parts.map(describe).joined(separator: ", ")
        }
    }
}
