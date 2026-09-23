import Foundation

/// The Night Market: a stall whose stock ROLLS, and the drachma sink the game
/// was missing.
///
/// The owner asked for it — "we should have a 'magic shop' too right?" — and
/// named it: "I like night market."
///
/// **What it is copying, and what it is not.** Summoners War's Magic Shop is a
/// building with four to twelve sell slots whose stock rolls, refreshes on a
/// timer, and can be refreshed early for crystals. That paid refresh is the
/// engine of the whole thing: players grind mana and re-roll hunting a
/// Mystical Scroll. Three things here are deliberately NOT theirs:
///
/// - **Slots are earned by level, never bought.** Their shop sells slots for
///   crystals. This game sells nothing for real money, so a slot is a level.
/// - **No five-star unit is ever on the shelf.** Their shop sells nat 3★ and,
///   rarely, nat 4★ monsters — never a nat 5★ — and that is the line that
///   keeps the gacha worth pulling. A guaranteed 5★ for coin would end the
///   summon screen.
/// - **A sold slot stays on the shelf, crossed out.** Theirs empties. A player
///   should be able to see what the roll gave them and what they took.
///
/// **The shelf is a seed, not a list.** `Player.nightMarket` saves the seed,
/// the hour it was rolled and the level it was rolled at; `stalls(for:)`
/// derives the same six to ten wares from it every time. A saved LIST would
/// put a relic in a second place — the loadouts already taught this project
/// that a relic must live in exactly one — and would grow the save by a
/// relic's worth of stats per slot per hour.
enum NightMarketService {

    // MARK: - The shape of the stall

    /// Six slots to start with, ten by level 40. Never bought.
    static func slotCount(forLevel level: Int) -> Int {
        switch level {
        case ..<10: return 6
        case ..<20: return 7
        case ..<30: return 8
        case ..<40: return 9
        default: return 10
        }
    }

    /// How long a roll stands before the market refreshes itself for nothing.
    /// An hour, on the same clock the energy tick already runs on.
    static let window: TimeInterval = 60 * 60

    /// What the nth paid re-roll of the day costs in divinity. It climbs, and
    /// it resets with the day, so a player with a full purse cannot simply
    /// spin the shelf until a Divine Scroll falls out.
    static let rerollPrices: [Int] = [30, 45, 70, 105, 155, 230, 345, 500]

    static func rerollPrice(afterRerolls taken: Int) -> Int {
        rerollPrices[max(0, min(rerollPrices.count - 1, taken))]
    }

    // MARK: - A ware on the shelf

    struct Stall: Identifiable, Sendable {
        /// The slot's place on the shelf, which is also its id in the save.
        var slot: Int
        var title: String
        var subtitle: String
        var price: ShopService.Price
        var grant: ShopService.Grant
        /// Drawn at a slot the player has already emptied.
        var isSoldOut: Bool = false

        var id: Int { slot }
    }

    /// How many more draws a slot gets when it rolls a ware the shelf already
    /// shows. The likeliest wares a shelf could already hold are about half
    /// of every draw at any level, so twenty-four twins in a row is rarer
    /// than one shelf in a million (`balance.py --shop` asserts it), and the
    /// loop always ends. Mirrored as `MARKET_TWIN_REDRAWS`.
    static let twinRedraws = 24

    /// The whole shelf, derived from the saved roll. Empty when the player has
    /// never opened the market — `GameStore` rolls one the first time.
    ///
    /// One of each (2026-09-23): a slot that rolls a ware already on the
    /// shelf — the same grant, so the same relic grade, the same energy, the
    /// same count of the same scroll — draws again from the same stream, so
    /// the shelf is still a pure function of its seed. Run 221's shelf
    /// offered +20 energy for 18,000 twice and run 220's three identical 3★
    /// relics, which a relic's own roll at the purchase makes the same
    /// ware: a shelf of twins reads as placeholder data, and no shop in the
    /// genre shows one. A shelf with no twin derives exactly as it did.
    static func stalls(for player: Player) -> [Stall] {
        guard let stock = player.nightMarket else { return [] }
        var rng = SeededRandom(seed: stock.seed)
        let count = slotCount(forLevel: stock.level)
        var shelf: [Stall] = []
        for slot in 0..<count {
            var stall = ware(slot: slot, level: stock.level, rng: &rng)
            var redraws = 0
            while redraws < twinRedraws, shelf.contains(where: { $0.grant == stall.grant }) {
                stall = ware(slot: slot, level: stock.level, rng: &rng)
                redraws += 1
            }
            stall.isSoldOut = stock.bought.contains(slot)
            shelf.append(stall)
        }
        return shelf
    }

    /// When the free refresh is due.
    static func refreshesAt(_ stock: NightMarketStock) -> Date {
        stock.rolledAt.addingTimeInterval(window)
    }

    static func isStale(_ stock: NightMarketStock, now: Date = Date()) -> Bool {
        now >= refreshesAt(stock)
    }

    /// Paid re-rolls already taken today. A roll taken on another day does not
    /// count against this one.
    static func rerollsToday(_ stock: NightMarketStock, now: Date = Date()) -> Int {
        guard let day = stock.rerollDay, Calendar.current.isDate(day, inSameDayAs: now) else { return 0 }
        return stock.paidRerolls
    }

    // MARK: - Rolling

    /// A fresh shelf. `paid` marks it as a re-roll the player bought, which is
    /// what makes the next one dearer.
    static func roll(player: inout Player, paid: Bool, now: Date = Date()) {
        let taken = player.nightMarket.map { rerollsToday($0, now: now) } ?? 0
        var stock = NightMarketStock(
            seed: UInt64.random(in: 1...UInt64.max),
            rolledAt: now,
            level: max(1, player.level)
        )
        if paid {
            stock.paidRerolls = taken + 1
            stock.rerollDay = now
        } else if let day = player.nightMarket?.rerollDay,
                  Calendar.current.isDate(day, inSameDayAs: now) {
            // A free refresh in the middle of a day keeps the day's tally, or
            // waiting out the hour would make every re-roll cost the first
            // price again.
            stock.paidRerolls = taken
            stock.rerollDay = day
        }
        player.nightMarket = stock
    }

    /// Rolls a shelf if there has never been one, or if this one has expired.
    /// Called on the same tick that restores energy.
    @discardableResult
    static func refreshIfNeeded(player: inout Player, now: Date = Date()) -> Bool {
        if let stock = player.nightMarket, !isStale(stock, now: now) { return false }
        roll(player: &player, paid: false, now: now)
        return true
    }

    // MARK: - Buying

    enum MarketError: Error, LocalizedError {
        case noStock
        case soldOut
        case cannotAfford(ShopService.Price)

        var errorDescription: String? {
            switch self {
            case .noStock: return "The market has not opened yet."
            case .soldOut: return "That one is gone. The shelf turns over on the hour."
            case .cannotAfford(let price):
                return "That costs \(price.amount) \(price.currency.displayName)."
            }
        }
    }

    /// Pays for one slot and puts it in the account. The slot stays on the
    /// shelf, crossed out, until the market turns over.
    @discardableResult
    static func buy(
        slot: Int,
        player: inout Player,
        rng: inout SeededRandom
    ) throws -> [ShopService.Grant] {
        guard player.nightMarket != nil else { throw MarketError.noStock }
        guard let stall = stalls(for: player).first(where: { $0.slot == slot }) else {
            throw MarketError.noStock
        }
        guard !stall.isSoldOut else { throw MarketError.soldOut }
        guard ShopService.canAfford(stall.price, wallet: player.wallet) else {
            throw MarketError.cannotAfford(stall.price)
        }

        switch stall.price.currency {
        case .divinity: player.wallet.divinity -= stall.price.amount
        case .drachma: player.wallet.drachma -= stall.price.amount
        case .laurels: player.wallet.laurels -= stall.price.amount
        case .free: break
        }
        player.nightMarket?.bought.append(slot)
        return ShopService.grant(stall.grant, to: &player, rng: &rng)
    }

    /// Pays for a fresh shelf in divinity.
    static func reroll(player: inout Player, now: Date = Date()) throws {
        let price = ShopService.Price(
            currency: .divinity,
            amount: rerollPrice(afterRerolls: player.nightMarket.map { rerollsToday($0, now: now) } ?? 0)
        )
        guard ShopService.canAfford(price, wallet: player.wallet) else {
            throw MarketError.cannotAfford(price)
        }
        player.wallet.divinity -= price.amount
        roll(player: &player, paid: true, now: now)
    }

    // MARK: - What can be on the shelf

    /// The kinds of ware, and how often each turns up. The unit is the rare
    /// row — the one that makes a player look, which is exactly what the
    /// genre's monster row is for.
    enum Kind: String, CaseIterable, Sendable {
        case relic, scroll, essence, stone, energy, unit

        var weight: Double {
            switch self {
            case .relic: return 28
            case .scroll: return 24
            case .essence: return 16
            case .stone: return 12
            case .energy: return 12
            case .unit: return 8
            }
        }
    }

    private static func ware(slot: Int, level: Int, rng: inout SeededRandom) -> Stall {
        let kind = rng.pickWeighted(Kind.allCases.map { (value: $0, weight: $0.weight) }) ?? .relic
        switch kind {
        case .relic: return relicStall(slot: slot, level: level, rng: &rng)
        case .scroll: return scrollStall(slot: slot, rng: &rng)
        case .essence: return essenceStall(slot: slot, rng: &rng)
        case .stone: return stoneStall(slot: slot, level: level, rng: &rng)
        case .energy: return energyStall(slot: slot, rng: &rng)
        case .unit: return unitStall(slot: slot, level: level, rng: &rng)
        }
    }

    /// A relic of a grade the player can actually use: never more than two
    /// grades above where the campaign is paying out at that level.
    private static func relicStall(slot: Int, level: Int, rng: inout SeededRandom) -> Stall {
        let ceiling = max(3, min(6, 3 + level / 12))
        let grade = rng.int(in: max(3, ceiling - 1)...ceiling)
        let price = ShopService.Price(currency: .drachma, amount: relicPrice(grade: grade))
        return Stall(
            slot: slot,
            title: "\(grade)★ relic",
            subtitle: "One relic, rolled: any set, any slot.",
            price: price,
            grant: .relic(grade: grade)
        )
    }

    static func relicPrice(grade: Int) -> Int {
        switch grade {
        case 6: return 90_000
        case 5: return 45_000
        case 4: return 22_000
        default: return 10_000
        }
    }

    private static func scrollStall(slot: Int, rng: inout SeededRandom) -> Stall {
        // Labelled, because `pickWeighted` takes `[(value:weight:)]` and every
        // other caller in the game spells the labels out.
        let scroll = rng.pickWeighted([
            (value: ScrollType.unknown, weight: 26.0),
            (value: ScrollType.mystical, weight: 24.0),
            (value: ScrollType.ember, weight: 10.0),
            (value: ScrollType.tide, weight: 10.0),
            (value: ScrollType.gale, weight: 10.0),
            (value: ScrollType.pantheonic, weight: 12.0),
            (value: ScrollType.lightDark, weight: 5.0),
            (value: ScrollType.divine, weight: 3.0),
        ]) ?? .mystical
        let count = scroll == .unknown || scroll == .mystical ? rng.int(in: 1...3) : 1
        return Stall(
            slot: slot,
            title: count > 1 ? "\(scroll.displayName) ×\(count)" : scroll.displayName,
            subtitle: "Tonight's stock. Gone on the hour.",
            price: scrollPrice(scroll, count: count),
            grant: .scrolls(scroll, count)
        )
    }

    /// The bazaar's own shelf prices, discounted a third because the market
    /// only ever offers what it happens to roll — a discount on a thing you
    /// cannot choose is the whole appeal, and it is not a way to buy the
    /// bazaar out, since the shelf turns over.
    static func scrollPrice(_ scroll: ScrollType, count: Int) -> ShopService.Price {
        switch scroll {
        case .unknown: return ShopService.Price(currency: .drachma, amount: 3_400 * count)
        case .mystical: return ShopService.Price(currency: .drachma, amount: 28_000 * count)
        case .ember, .tide, .gale: return ShopService.Price(currency: .divinity, amount: 135 * count)
        case .pantheonic: return ShopService.Price(currency: .divinity, amount: 70 * count)
        case .lightDark: return ShopService.Price(currency: .divinity, amount: 320 * count)
        case .divine: return ShopService.Price(currency: .divinity, amount: 430 * count)
        }
    }

    private static let marketEssences = [
        "essence_magic_low", "essence_magic_mid", "essence_magic_high",
        "essence_ember_mid", "essence_tide_mid", "essence_gale_mid",
        "essence_radiance_mid", "essence_umbra_mid",
    ]

    private static func essenceStall(slot: Int, rng: inout SeededRandom) -> Stall {
        let id = rng.pickMutating(marketEssences) ?? "essence_magic_mid"
        let count = rng.int(in: 2...6)
        let each = id.hasSuffix("_high") ? 9_000 : (id.hasSuffix("_low") ? 1_800 : 4_200)
        return Stall(
            slot: slot,
            title: "\(EssenceCatalog.name(for: id)) ×\(count)",
            subtitle: "What an awakening asks for, without the hall.",
            price: ShopService.Price(currency: .drachma, amount: each * count),
            grant: .essences(id, count)
        )
    }

    private static func stoneStall(slot: Int, level: Int, rng: inout SeededRandom) -> Stall {
        let tiers = level >= 30 ? ["rare", "hero", "legend"] : (level >= 15 ? ["rare", "hero"] : ["rare"])
        let tier = rng.pickMutating(tiers) ?? "rare"
        let kind = rng.chance(0.5) ? "whetstone" : "gem"
        let id = "\(kind)_\(tier)"
        let price = stonePrice(tier: tier)
        return Stall(
            slot: slot,
            title: RelicStone.from(id: id)?.displayName ?? id,
            subtitle: kind == "gem"
                ? "Replaces one sub stat with a stat of your choosing."
                : "Hones one sub stat, apart from the roll.",
            price: price,
            grant: .stones(id, 1)
        )
    }

    static func stonePrice(tier: String) -> ShopService.Price {
        switch tier {
        case "legend": return ShopService.Price(currency: .divinity, amount: 220)
        case "hero": return ShopService.Price(currency: .divinity, amount: 90)
        default: return ShopService.Price(currency: .drachma, amount: 30_000)
        }
    }

    private static func energyStall(slot: Int, rng: inout SeededRandom) -> Stall {
        let amount = rng.pickMutating([20, 30, 50]) ?? 30
        return Stall(
            slot: slot,
            title: "Energy ×\(amount)",
            subtitle: "Drachma for energy, which the bazaar will not do.",
            price: ShopService.Price(currency: .drachma, amount: amount * 900),
            grant: .energy(amount)
        )
    }

    /// The rare row. Three stars mostly, four rarely, and never five: the
    /// genre's own line, and the one that keeps the summon screen worth
    /// opening.
    private static func unitStall(slot: Int, level: Int, rng: inout SeededRandom) -> Stall {
        let wantsFour = level >= 12 && rng.chance(0.28)
        let stars = wantsFour ? 4 : 3
        let pool = marketUnits(stars: stars)
        guard let id = rng.pickMutating(pool), let blueprint = UnitDatabase.blueprint(id) else {
            // Nothing of that grade has cards yet: a scroll instead, so a slot
            // is never blank.
            return scrollStall(slot: slot, rng: &rng)
        }
        return Stall(
            slot: slot,
            title: blueprint.name,
            subtitle: "\(stars)★ \(blueprint.element.displayName) · \(blueprint.epithet)",
            price: ShopService.Price(currency: .drachma, amount: stars == 4 ? 250_000 : 40_000),
            grant: .unit(blueprint.id)
        )
    }

    /// Only families whose cards are in the bundle, so the shelf can never
    /// offer a god with no portrait — the same gate the gacha uses — and
    /// never a Radiance or an Umbra, which are the Light & Dark scroll's
    /// alone (`Banner.excludingLightDark`, 2026-09-17): a 4★ dark god for
    /// 250,000 drachma would have been a second road to the premium.
    static func marketUnits(stars: Int) -> [String] {
        Banner.excludingLightDark(UnitDatabase.summonPool).filter { id in
            guard let blueprint = UnitDatabase.blueprint(id) else { return false }
            return blueprint.naturalStars == stars && blueprint.hasShippedArt
        }
    }
}

/// The rolled shelf, in the save. Optional, like every field added since the
/// first: a non-optional one would wipe every existing save.
struct NightMarketStock: Codable, Equatable, Sendable {
    /// What the shelf is derived from. A list of wares would put a relic in a
    /// second place; a seed cannot go stale.
    var seed: UInt64
    var rolledAt: Date
    /// The summoner level the roll was made at, so levelling up in the middle
    /// of an hour cannot change what is on the shelf under the player's hand.
    var level: Int
    /// Slots already emptied. They stay on the shelf, crossed out.
    var bought: [Int] = []
    /// Paid re-rolls taken on `rerollDay`, which is what makes the next one
    /// dearer. Both reset with the day.
    var paidRerolls: Int = 0
    var rerollDay: Date?
}
