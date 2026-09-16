import Foundation

/// Boons: the earned socket at the centre of the relic ring (`Docs/PLAN.md`,
/// *Boons — the earned socket*). A cache drops from the hardest content and
/// opens as a choice of THREE kinds; the one taken rolls its magnitude, and
/// a push — drachma and the Titans' aether — rolls a bump as a choice of two
/// through the same `pendingRoll` mechanic every relic roll uses, five at
/// most, each one lifting the floor. Every number here is mirrored in
/// `tools/balance.py` (`BOONS`, `BOON_PUSH`; `--boons` measures the kinds).
enum BoonService {

    // MARK: - The numbers

    static let maxPushes = 5
    /// A push lifts the magnitude by this much of the grade's base, rolled
    /// 0.5–1.5× as a choice of two: five pushes average +40% of the base.
    static let pushStep = 0.08
    /// A fresh boon's roll against its grade's base.
    static let rollRange: ClosedRange<Double> = 0.75...1.25
    static let pushRollRange: ClosedRange<Double> = 0.5...1.5
    /// How many kinds a cache offers.
    static let cacheOffers = 3
    /// A push's price: drachma by the boon's grade, and aether — four of the
    /// boon's colour, or two pure for a kind of no colour.
    static let pushDrachma: [Int: Int] = [4: 8_000, 5: 16_000, 6: 30_000]
    static let pushAether = 4
    static let pushPureAether = 2

    /// What a cache's grade is worth against a 6★.
    static func gradeScale(_ grade: Int) -> Double {
        switch grade {
        case ...4: return 0.6
        case 5: return 0.8
        default: return 1.0
        }
    }

    /// The magnitude a kind rolls around at a grade.
    static func base(_ kind: BoonKind, grade: Int) -> Double {
        kind.family.base * gradeScale(grade)
    }

    /// Where a fresh boon of a kind and grade can land: the range a cache's
    /// door prints.
    static func rollSpan(_ kind: BoonKind, grade: Int) -> ClosedRange<Double> {
        let middle = base(kind, grade: grade)
        return (middle * rollRange.lowerBound)...(middle * rollRange.upperBound)
    }

    enum BoonError: Error, LocalizedError, Equatable {
        case gone
        case noSuchOffer
        case choiceWaiting
        case fullyPushed
        case locked
        case notEnoughDrachma(needed: Int)
        case notEnoughAether(id: String, needed: Int, held: Int)

        var errorDescription: String? {
            switch self {
            case .gone: return "That boon is no longer in your collection."
            case .noSuchOffer: return "That is not one of the cache's three."
            case .choiceWaiting: return "Take one of the two pushes on this boon first."
            case .fullyPushed: return "This boon has taken all \(BoonService.maxPushes) of its pushes."
            case .locked: return "A locked boon is never sold."
            case .notEnoughDrachma(let needed): return "A push costs \(needed) drachma."
            case .notEnoughAether(let id, let needed, let held):
                return "A push needs \(needed) \(Aether.name(for: id)); you hold \(held)."
            }
        }
    }

    // MARK: - Caches: the three doors

    static func addCache(_ cache: BoonCache, player: inout Player) {
        var caches = player.boonCaches ?? []
        caches.append(cache)
        player.boonCaches = caches
    }

    /// The three kinds a cache offers, derived from its seed: three
    /// different families, a Bane or a Ward in a colour of the seed's
    /// choosing. Pure — the same cache offers the same three every time it
    /// is looked at, which is what makes closing the sheet safe.
    static func offers(for cache: BoonCache) -> [BoonKind] {
        var rng = SeededRandom(seed: cache.seed)
        var families = BoonFamily.allCases
        var kinds: [BoonKind] = []
        for _ in 0..<cacheOffers {
            guard let family = rng.pickMutating(families) else { break }
            families.removeAll { $0 == family }
            let element = family.isElemental ? rng.pickMutating(Element.allCases) : nil
            kinds.append(BoonKind(family, element: element))
        }
        return kinds
    }

    /// Opens a cache on one of its doors: the boon, its magnitude rolled
    /// within `rollRange` of the grade's base, goes in the bag and the cache
    /// is gone.
    @discardableResult
    static func open(
        cacheID: UUID, choice: Int, player: inout Player, rng: inout SeededRandom
    ) throws -> Boon {
        var caches = player.boonCaches ?? []
        guard let index = caches.firstIndex(where: { $0.id == cacheID }) else { throw BoonError.gone }
        let doors = offers(for: caches[index])
        guard doors.indices.contains(choice) else { throw BoonError.noSuchOffer }
        let kind = doors[choice]
        let grade = caches[index].grade
        let boon = Boon(kind: kind, grade: grade, magnitude: base(kind, grade: grade) * rng.double(in: rollRange))
        caches.remove(at: index)
        player.boonCaches = caches
        var boons = player.boons ?? []
        boons.append(boon)
        player.boons = boons
        return boon
    }

    // MARK: - Pushes: a choice of two

    struct PushCost: Equatable, Sendable {
        var drachma: Int
        var aetherID: String
        var aether: Int
    }

    static func pushCost(for boon: Boon) -> PushCost {
        PushCost(
            drachma: pushDrachma[boon.grade] ?? pushDrachma[6] ?? 30_000,
            aetherID: boon.kind.aetherID,
            aether: boon.kind.element == nil ? pushPureAether : pushAether
        )
    }

    /// Why a push cannot be paid for right now, or nil when it can.
    static func pushError(_ boon: Boon, player: Player) -> BoonError? {
        if boon.hasPendingRoll { return .choiceWaiting }
        if boon.isFullyPushed { return .fullyPushed }
        let cost = pushCost(for: boon)
        if player.wallet.drachma < cost.drachma { return .notEnoughDrachma(needed: cost.drachma) }
        let held = Aether.count(cost.aetherID, player: player)
        if held < cost.aether { return .notEnoughAether(id: cost.aetherID, needed: cost.aether, held: held) }
        return nil
    }

    /// Pays for a push and opens its choice of two (`pendingRoll`). The
    /// magnitude does not move until the player takes one.
    @discardableResult
    static func push(boonID: UUID, player: inout Player, rng: inout SeededRandom) throws -> Boon {
        var boons = player.boons ?? []
        guard let index = boons.firstIndex(where: { $0.id == boonID }) else { throw BoonError.gone }
        if let error = pushError(boons[index], player: player) { throw error }
        let cost = pushCost(for: boons[index])
        player.wallet.drachma -= cost.drachma
        var aether = player.aether ?? [:]
        aether[cost.aetherID] = max(0, (aether[cost.aetherID] ?? 0) - cost.aether)
        player.aether = aether
        boons[index].pendingRoll = rng.next()
        player.boons = boons
        return boons[index]
    }

    struct PushCandidate: Identifiable, Equatable, Sendable {
        /// 0 or 1 — which of the pair, and what `takePush` is called with.
        var id: Int
        var bump: Double
        var after: Double
    }

    /// The two bumps on offer, derived from the boon's own pending seed:
    /// each `pushStep` of the grade's base, rolled within `pushRollRange`.
    static func pushCandidates(for boon: Boon) -> [PushCandidate] {
        guard let seed = boon.pendingRoll else { return [] }
        var rng = SeededRandom(seed: seed)
        let step = base(boon.kind, grade: boon.grade) * pushStep
        var offers: [PushCandidate] = []
        for index in 0..<2 {
            let bump = step * rng.double(in: pushRollRange)
            offers.append(PushCandidate(id: index, bump: bump, after: boon.magnitude + bump))
        }
        return offers
    }

    /// Spends the pending push on one of the two. Nil when there is no
    /// choice waiting or the id is not one of the pair — a stale screen,
    /// not an error worth showing.
    @discardableResult
    static func takePush(_ boon: inout Boon, candidate id: Int) -> Double? {
        guard let pick = pushCandidates(for: boon).first(where: { $0.id == id }) else { return nil }
        boon.magnitude = pick.after
        boon.pushes += 1
        boon.pendingRoll = nil
        return pick.bump
    }

    // MARK: - The socket

    /// Puts a boon in a unit's socket. The unit's old boon comes out and the
    /// boon's old wearer loses it: one socket, one boon.
    static func equip(boonID: UUID, unitID: UUID, player: inout Player) throws {
        var boons = player.boons ?? []
        guard let boonIndex = boons.firstIndex(where: { $0.id == boonID }),
              let unitIndex = player.units.firstIndex(where: { $0.id == unitID }) else { throw BoonError.gone }
        if let worn = player.units[unitIndex].boonID, let wornIndex = boons.firstIndex(where: { $0.id == worn }) {
            boons[wornIndex].equippedBy = nil
        }
        if let wearer = boons[boonIndex].equippedBy,
           let wearerIndex = player.units.firstIndex(where: { $0.id == wearer }) {
            player.units[wearerIndex].boonID = nil
        }
        boons[boonIndex].equippedBy = unitID
        player.units[unitIndex].boonID = boonID
        player.boons = boons
    }

    static func unequip(unitID: UUID, player: inout Player) {
        guard let unitIndex = player.units.firstIndex(where: { $0.id == unitID }),
              let boonID = player.units[unitIndex].boonID else { return }
        player.units[unitIndex].boonID = nil
        var boons = player.boons ?? []
        if let index = boons.firstIndex(where: { $0.id == boonID }) {
            boons[index].equippedBy = nil
            player.boons = boons
        }
    }

    /// The boon in a unit's socket, if any.
    static func worn(by unit: Unit, player: Player) -> Boon? {
        unit.boonID.flatMap { id in player.boons?.first(where: { $0.id == id }) }
    }

    // MARK: - Selling

    /// What a boon fetches: a floor by its grade, and a third of what its
    /// pushes cost.
    static func sellValue(_ boon: Boon) -> Int {
        400 * boon.grade * boon.grade + boon.pushes * ((pushDrachma[boon.grade] ?? 30_000) / 3)
    }

    /// Sells boons, taking each out of its socket first. A locked boon
    /// stops the whole sale rather than being skipped quietly.
    @discardableResult
    static func sell(boonIDs: [UUID], player: inout Player) throws -> Int {
        var boons = player.boons ?? []
        for id in boonIDs where boons.first(where: { $0.id == id })?.isLocked == true {
            throw BoonError.locked
        }
        var total = 0
        for id in boonIDs {
            guard let index = boons.firstIndex(where: { $0.id == id }) else { continue }
            if let wearer = boons[index].equippedBy,
               let unitIndex = player.units.firstIndex(where: { $0.id == wearer }) {
                player.units[unitIndex].boonID = nil
            }
            total += sellValue(boons[index])
            boons.remove(at: index)
        }
        player.boons = boons
        player.wallet.drachma += total
        return total
    }

    // MARK: - Fit

    /// How well a boon suits a role, for the picker's best-fit-first order:
    /// the kind's weight for the role times the roll's quality.
    static func fit(_ boon: Boon, for role: CombatRole) -> Double {
        roleWeight(boon.kind.family, role: role) * max(0.01, boon.quality)
    }

    /// An attacker wants the damage lines, a wall the wards and the heals,
    /// a support the head start; nothing is worth nothing to anyone.
    static func roleWeight(_ family: BoonFamily, role: CombatRole) -> Double {
        switch role {
        case .attacker:
            switch family {
            case .bane, .giantSlayer: return 1.0
            case .firstBlood, .executioner: return 0.9
            case .lastStand, .swiftFooted: return 0.7
            case .hydrasBlood: return 0.6
            case .ward, .unfading: return 0.4
            }
        case .defender, .hpTank:
            switch family {
            case .ward, .unfading: return 1.0
            case .hydrasBlood: return 0.8
            case .lastStand: return 0.6
            case .bane, .giantSlayer, .firstBlood, .executioner, .swiftFooted: return 0.4
            }
        case .support:
            switch family {
            case .swiftFooted: return 1.0
            case .unfading: return 0.9
            case .ward: return 0.8
            case .hydrasBlood: return 0.5
            case .bane, .giantSlayer, .firstBlood, .lastStand, .executioner: return 0.4
            }
        case .controller:
            switch family {
            case .swiftFooted: return 1.0
            case .firstBlood: return 0.9
            case .bane: return 0.7
            case .ward: return 0.6
            case .giantSlayer, .lastStand, .executioner, .unfading, .hydrasBlood: return 0.5
            }
        }
    }
}
