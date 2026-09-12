import Foundation

/// Generates, upgrades and equips relics.
///
/// Relic rolls are the long-term grind, so the numbers here matter more than
/// almost anything else in the game. They are all in one place and all driven by
/// the seeded RNG, which means a drop table change can be regression-tested.
enum RelicService {

    // MARK: - Drop generation

    /// Main-stat value at level 0 for a given grade. Multiplied ~3x by +15.
    static func mainStatValue(kind: StatKind, grade: Int) -> Double {
        let gradeScale = 1.0 + Double(max(1, grade) - 1) * 0.32
        switch kind {
        case .hpFlat: return (180 * gradeScale).rounded()
        case .atkFlat: return (12 * gradeScale).rounded()
        case .defFlat: return (12 * gradeScale).rounded()
        case .hpPercent, .atkPercent, .defPercent: return 0.05 * gradeScale
        case .spd: return (5 * gradeScale).rounded()
        case .critRate: return 0.04 * gradeScale
        case .critDamage: return 0.05 * gradeScale
        case .accuracy: return 0.04 * gradeScale
        case .resistance: return 0.04 * gradeScale
        }
    }

    /// One roll of a sub stat at a given grade.
    static func subStatRoll(kind: StatKind, grade: Int, rng: inout SeededRandom) -> Double {
        let value = subStatBase(kind: kind, grade: grade) * rng.double(in: 0.75...1.25)
        switch kind {
        case .hpFlat, .atkFlat, .defFlat, .spd: return value.rounded()
        default: return value
        }
    }

    /// The middle of a sub stat roll at a grade; a roll is this times
    /// 0.75...1.25, and the top of that range is what `efficiency` measures
    /// a relic against.
    static func subStatBase(kind: StatKind, grade: Int) -> Double {
        let gradeScale = 1.0 + Double(max(1, grade) - 1) * 0.22
        switch kind {
        case .hpFlat: return 95 * gradeScale
        case .atkFlat: return 7 * gradeScale
        case .defFlat: return 7 * gradeScale
        case .hpPercent, .atkPercent, .defPercent: return 0.03 * gradeScale
        case .spd: return 3 * gradeScale
        case .critRate: return 0.025 * gradeScale
        case .critDamage: return 0.035 * gradeScale
        case .accuracy: return 0.03 * gradeScale
        case .resistance: return 0.03 * gradeScale
        }
    }

    static let subStatPool: [StatKind] = [
        .hpFlat, .hpPercent, .atkFlat, .atkPercent, .defFlat, .defPercent,
        .spd, .critRate, .critDamage, .accuracy, .resistance
    ]

    /// Rolls a fresh relic. Higher grades start with more sub stats, which is
    /// the real difference between a 4★ and a 6★ drop.
    static func generate(
        grade: Int,
        slot: Int? = nil,
        set: RelicSet? = nil,
        quality: RelicQuality? = nil,
        qualityFloor: RelicQuality = .normal,
        rng: inout SeededRandom
    ) -> Relic {
        let clampedGrade = max(1, min(6, grade))
        let chosenSlot = slot ?? rng.int(in: 1...6)
        let chosenSet = set ?? rng.pickMutating(RelicSet.allCases) ?? .fury

        let mainKind: StatKind = Relic.fixedMainStat(forSlot: chosenSlot)
            ?? rng.pickMutating(Relic.allowedMainStats(forSlot: chosenSlot))
            ?? .atkPercent
        let main = StatModifier(mainKind, mainStatValue(kind: mainKind, grade: clampedGrade))

        // The quality is the number of subs it drops with — rolled by grade
        // unless the caller names it, never below the floor a Hell tier or a
        // raid sets — and never duplicates the main. This is the genre's
        // rarity: the sub count used to follow the grade, so every 6★ was a
        // Legend and there was nothing to hunt for.
        let rolledQuality: RelicQuality
        if let quality {
            rolledQuality = quality
        } else {
            rolledQuality = rollQuality(grade: clampedGrade, floor: qualityFloor, rng: &rng)
        }
        var available = subStatPool.filter { $0 != mainKind }
        var subs: [StatModifier] = []
        for _ in 0..<rolledQuality.subStatCount {
            guard let kind = rng.pickMutating(available) else { break }
            available.removeAll { $0 == kind }
            subs.append(StatModifier(kind, subStatRoll(kind: kind, grade: clampedGrade, rng: &rng)))
        }

        var relic = Relic(set: chosenSet, slot: chosenSlot, grade: clampedGrade, mainStat: main, subStats: subs)
        relic.quality = rolledQuality
        return relic
    }

    /// A drop's quality, by the grade's odds (`RelicQuality.weights`), and
    /// never below `floor`.
    static func rollQuality(grade: Int, floor: RelicQuality = .normal, rng: inout SeededRandom) -> RelicQuality {
        let weights = RelicQuality.weights(forGrade: grade)
        let total = weights.reduce(0, +)
        var pick = rng.int(in: 0...(max(1, total) - 1))
        var chosen = RelicQuality.legend
        for (index, weight) in weights.enumerated() {
            if pick < weight {
                chosen = RelicQuality(rawValue: index) ?? .normal
                break
            }
            pick -= weight
        }
        return max(chosen, floor)
    }

    /// A full six-piece loadout, used to kit out arena opponents and the
    /// starter account without hand-authoring inventory.
    static func generateLoadout(
        grade: Int,
        primarySet: RelicSet,
        secondarySet: RelicSet,
        upgradeLevel: Int,
        quality: RelicQuality? = nil,
        rng: inout SeededRandom
    ) -> [Relic] {
        (1...6).map { slot in
            let set: RelicSet = slot <= primarySet.piecesRequired ? primarySet : secondarySet
            var relic = generate(grade: grade, slot: slot, set: set, quality: quality, rng: &rng)
            for _ in 0..<upgradeLevel {
                upgradeOnce(&relic, rng: &rng)
            }
            return relic
        }
    }

    // MARK: - Upgrading

    static func upgradeCost(grade: Int, level: Int) -> Int {
        let base = 100 * grade * grade
        return base + level * base / 3
    }

    // MARK: - Power-up

    /// The chance an attempt at reaching a level succeeds: sure to +3, then
    /// falling a step a level to 40% at +15 — the genre's rune power-up,
    /// where the last few levels are the expensive ones. A failed attempt
    /// costs the drachma and keeps the level. (Indexed by level - 1.)
    static let powerUpChances: [Double] = [
        1.0, 1.0, 1.0, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40,
    ]

    static func successChance(toLevel level: Int) -> Double {
        guard level >= 1 else { return 1 }
        return powerUpChances[min(level, powerUpChances.count) - 1]
    }

    /// Whether reaching a level rolls a sub stat: +3, +6, +9 and +12 do;
    /// +15 only lifts the main stat.
    static func levelRollsSubStat(_ level: Int) -> Bool {
        level % 3 == 0 && level <= 12
    }

    /// What a +3/+6/+9/+12 did to the sub stats.
    struct SubStatChange: Equatable, Sendable {
        var kind: StatKind
        /// Zero for a sub stat that was just added.
        var before: Double
        var after: Double
        var isNew: Bool
    }

    /// One attempt, as the power-up screen shows it.
    struct PowerUpOutcome: Equatable, Sendable {
        var succeeded: Bool
        /// The relic's level after the attempt.
        var level: Int
        var cost: Int
        var chance: Double
        var subStatChange: SubStatChange?
    }

    /// One guaranteed +1. At +3, +6, +9 and +12 a sub stat is added while
    /// there are fewer than four, else an existing one grows — which is
    /// where the grind's variance lives. +15 rolls nothing.
    @discardableResult
    static func upgradeOnce(_ relic: inout Relic, rng: inout SeededRandom) -> SubStatChange? {
        guard !relic.isMaxLevel else { return nil }
        relic.level += 1

        guard levelRollsSubStat(relic.level) else { return nil }

        if relic.subStats.count < 4 {
            let available = subStatPool.filter { kind in
                kind != relic.mainStat.kind && !relic.subStats.contains(where: { $0.kind == kind })
            }
            if let kind = rng.pickMutating(available) {
                let value = subStatRoll(kind: kind, grade: relic.grade, rng: &rng)
                relic.subStats.append(StatModifier(kind, value))
                return SubStatChange(kind: kind, before: 0, after: value, isNew: true)
            }
        }

        guard !relic.subStats.isEmpty else { return nil }
        let index = rng.int(in: 0...(relic.subStats.count - 1))
        let before = relic.subStats[index].value
        let bump = subStatRoll(kind: relic.subStats[index].kind, grade: relic.grade, rng: &rng)
        relic.subStats[index].value += bump
        return SubStatChange(
            kind: relic.subStats[index].kind, before: before, after: relic.subStats[index].value, isNew: false
        )
    }

    enum RelicError: Error, LocalizedError {
        case notEnoughDrachma(needed: Int)
        case maxLevel
        case slotMismatch

        var errorDescription: String? {
            switch self {
            case .notEnoughDrachma(let needed): return "Upgrading costs \(needed) drachma."
            case .maxLevel: return "This relic is already +15."
            case .slotMismatch: return "That relic does not fit this slot."
            }
        }
    }

    /// One paid attempt: the drachma goes either way, the level only on a
    /// success.
    @discardableResult
    static func upgrade(
        _ relic: inout Relic,
        wallet: inout Wallet,
        rng: inout SeededRandom
    ) throws -> PowerUpOutcome {
        guard !relic.isMaxLevel else { throw RelicError.maxLevel }
        let cost = upgradeCost(grade: relic.grade, level: relic.level)
        guard wallet.drachma >= cost else { throw RelicError.notEnoughDrachma(needed: cost) }
        wallet.drachma -= cost
        let chance = successChance(toLevel: relic.level + 1)
        guard rng.chance(chance) else {
            return PowerUpOutcome(succeeded: false, level: relic.level, cost: cost, chance: chance, subStatChange: nil)
        }
        let change = upgradeOnce(&relic, rng: &rng)
        return PowerUpOutcome(succeeded: true, level: relic.level, cost: cost, chance: chance, subStatChange: change)
    }

    // MARK: - Selling, reappraisal, efficiency

    enum ManageError: Error, LocalizedError {
        case locked
        case tooLowToReappraise
        case notEnoughDrachma(needed: Int)

        var errorDescription: String? {
            switch self {
            case .locked: return "That relic is locked. Unlock it first."
            case .tooLowToReappraise: return "A relic can be reappraised from +\(RelicService.reappraisalMinimumLevel)."
            case .notEnoughDrachma(let needed): return "That costs \(needed) drachma."
            }
        }
    }

    /// What a relic fetches: a floor set by its grade, plus a third of what
    /// its upgrades cost, so selling a +12 is not throwing the drachma away.
    static func sellValue(_ relic: Relic) -> Int {
        // A quality step is worth a fifth more: the genre prices a Legend
        // above a Normal of the same grade, and a drop screen that sells the
        // Normals needs the difference to show.
        let base = 300 * relic.grade * relic.grade * (5 + relic.resolvedQuality.rawValue) / 5
        let invested = (0..<relic.level).reduce(0) { $0 + upgradeCost(grade: relic.grade, level: $1) }
        return base + invested / 3
    }

    /// Sells relics, taking each off its wearer first. A locked relic stops
    /// the whole sale rather than being skipped quietly.
    @discardableResult
    static func sell(relicIDs: [UUID], player: inout Player) throws -> Int {
        for id in relicIDs {
            if let relic = player.relics.first(where: { $0.id == id }), relic.isLocked {
                throw ManageError.locked
            }
        }
        var total = 0
        for id in relicIDs {
            guard let relic = player.relics.first(where: { $0.id == id }) else { continue }
            if let wearer = relic.equippedBy {
                unequip(slot: relic.slot, from: wearer, player: &player)
            }
            total += sellValue(relic)
            player.relics.removeAll { $0.id == id }
        }
        player.wallet.drachma += total
        return total
    }

    static let reappraisalMinimumLevel = 9

    static func reappraisalCost(_ relic: Relic) -> Int {
        2 * upgradeCost(grade: relic.grade, level: reappraisalMinimumLevel)
    }

    /// Rerolls every sub stat from scratch, keeping the main stat, the level,
    /// the set and the slot: the genre's second chance for a well-upgraded
    /// relic whose rolls went the wrong way. Every third level past the subs
    /// the relic started with is rolled in again as a bump.
    static func reappraise(_ relic: inout Relic, wallet: inout Wallet, rng: inout SeededRandom) throws {
        guard relic.level >= reappraisalMinimumLevel else { throw ManageError.tooLowToReappraise }
        let cost = reappraisalCost(relic)
        guard wallet.drachma >= cost else { throw ManageError.notEnoughDrachma(needed: cost) }
        wallet.drachma -= cost

        // From the quality it dropped with, then the level's rolls replayed
        // — a new sub while under four, then one grows — so the result has
        // the shape a fresh relic of that quality has at that level. The
        // honing and the gem went with the old subs.
        let quality = relic.resolvedQuality
        var available = subStatPool.filter { $0 != relic.mainStat.kind }
        var subs: [StatModifier] = []
        for _ in 0..<quality.subStatCount {
            guard let kind = rng.pickMutating(available) else { break }
            available.removeAll { $0 == kind }
            subs.append(StatModifier(kind, subStatRoll(kind: kind, grade: relic.grade, rng: &rng)))
        }
        for _ in 0..<(min(relic.level, 12) / 3) {
            if subs.count < 4, let kind = rng.pickMutating(available) {
                available.removeAll { $0 == kind }
                subs.append(StatModifier(kind, subStatRoll(kind: kind, grade: relic.grade, rng: &rng)))
            } else if !subs.isEmpty {
                let index = rng.int(in: 0...(subs.count - 1))
                subs[index].value += subStatRoll(kind: subs[index].kind, grade: relic.grade, rng: &rng)
            }
        }
        relic.subStats = subs
        relic.quality = quality
        relic.honed = nil
        relic.gemmed = nil
    }

    /// How close a relic is to the best its grade, slot and level could have
    /// rolled for a role, 0...1: the main stat as it is, four sub stats of
    /// the kinds the role wants most at the top of their range, and every
    /// third level a bump on the best of them. The number the inventory
    /// sorts by, and what a 100% means on the dial.
    static func efficiency(_ relic: Relic, for role: CombatRole) -> Double {
        let mainKind = relic.mainStat.kind
        func best(_ kind: StatKind) -> Double {
            weight(kind, for: role) * normalized(StatModifier(kind, subStatBase(kind: kind, grade: relic.grade) * 1.25))
        }
        let top = subStatPool.filter { $0 != mainKind }.sorted { best($0) > best($1) }.prefix(4)
        var ceiling = weight(mainKind, for: role) * normalized(relic.effectiveMainStat)
        for kind in top { ceiling += best(kind) }
        if let first = top.first { ceiling += Double(relic.level / 3) * best(first) }
        guard ceiling > 0 else { return 0 }
        return max(0, min(1, score(relic, for: role) / ceiling))
    }

    // MARK: - Equipping

    /// Equips a relic, unequipping whatever held that slot and whoever held the
    /// relic. Both sides of the swap are updated so the save can never end up
    /// with a relic equipped twice.
    static func equip(relicID: UUID, on unitID: UUID, player: inout Player) throws {
        guard let relicIndex = player.relics.firstIndex(where: { $0.id == relicID }),
              let unitIndex = player.units.firstIndex(where: { $0.id == unitID }) else { return }
        let slot = player.relics[relicIndex].slot

        // Take it off its previous owner.
        if let previousOwner = player.relics[relicIndex].equippedBy,
           let previousIndex = player.units.firstIndex(where: { $0.id == previousOwner }) {
            player.units[previousIndex].equippedRelics[slot] = nil
        }

        // Take off whatever is currently in that slot.
        if let displacedID = player.units[unitIndex].equippedRelics[slot],
           let displacedIndex = player.relics.firstIndex(where: { $0.id == displacedID }) {
            player.relics[displacedIndex].equippedBy = nil
        }

        player.units[unitIndex].equippedRelics[slot] = relicID
        player.relics[relicIndex].equippedBy = unitID
    }

    static func unequip(slot: Int, from unitID: UUID, player: inout Player) {
        guard let unitIndex = player.units.firstIndex(where: { $0.id == unitID }),
              let relicID = player.units[unitIndex].equippedRelics[slot] else { return }
        player.units[unitIndex].equippedRelics[slot] = nil
        if let relicIndex = player.relics.firstIndex(where: { $0.id == relicID }) {
            player.relics[relicIndex].equippedBy = nil
        }
    }

    /// Best-effort auto-equip: fills empty slots with the highest-scoring
    /// unequipped relic for the unit's role.
    static func autoEquip(unitID: UUID, player: inout Player) {
        guard let unitIndex = player.units.firstIndex(where: { $0.id == unitID }),
              let blueprint = UnitDatabase.blueprint(player.units[unitIndex].blueprintID) else { return }

        for slot in 1...6 where player.units[unitIndex].equippedRelics[slot] == nil {
            let candidates = player.relics.filter { $0.slot == slot && $0.equippedBy == nil }
            guard let best = candidates.max(by: {
                score($0, for: blueprint.role) < score($1, for: blueprint.role)
            }) else { continue }
            try? equip(relicID: best.id, on: unitID, player: &player)
        }
    }

    /// How much a relic is worth to a given role. Used by auto-equip and by the
    /// inventory's "recommended" sort.
    static func score(_ relic: Relic, for role: CombatRole) -> Double {
        relic.allStats.reduce(0) { total, modifier in
            total + weight(modifier.kind, for: role) * normalized(modifier)
        }
    }

    private static func normalized(_ modifier: StatModifier) -> Double {
        switch modifier.kind {
        case .hpFlat: return modifier.value / 180
        case .atkFlat, .defFlat: return modifier.value / 12
        case .spd: return modifier.value / 2
        default: return modifier.value * 100 / 5
        }
    }

    private static func weight(_ kind: StatKind, for role: CombatRole) -> Double {
        switch role {
        case .attacker:
            switch kind {
            case .atkPercent, .atkFlat: return 1.4
            case .critRate: return 1.6
            case .critDamage: return 1.5
            case .spd: return 1.3
            default: return 0.3
            }
        case .controller:
            switch kind {
            case .spd: return 1.8
            case .accuracy: return 1.6
            case .hpPercent, .hpFlat: return 1.0
            default: return 0.4
            }
        case .support:
            switch kind {
            case .spd: return 1.7
            case .hpPercent, .hpFlat: return 1.2
            case .resistance: return 1.1
            default: return 0.4
            }
        case .defender:
            switch kind {
            case .defPercent, .defFlat: return 1.6
            case .hpPercent, .hpFlat: return 1.1
            case .spd: return 1.0
            default: return 0.4
            }
        case .hpTank:
            switch kind {
            case .hpPercent, .hpFlat: return 1.7
            case .defPercent, .defFlat: return 1.0
            case .spd: return 1.0
            default: return 0.4
            }
        }
    }

    // MARK: - Loadouts

    /// How many named loadouts one unit may keep.
    ///
    /// Four, because the optimiser solves for four goals and a loadout is
    /// named after the goal that built it — there is no fifth thing to save.
    /// It also keeps the save honest: a loadout is a name and six ids, and a
    /// collection reaches a few hundred units.
    static let loadoutsPerUnit = 4

    /// What a unit is wearing now, as a loadout under `name`.
    static func captureLoadout(named name: String, for unitID: UUID, player: Player) -> RelicLoadout? {
        guard let unit = player.unit(unitID) else { return nil }
        return RelicLoadout(unitID: unitID, name: name, relicIDs: unit.equippedRelics)
    }

    /// Every loadout saved against one unit, in the order they were saved.
    static func loadouts(for unitID: UUID, in all: [RelicLoadout]) -> [RelicLoadout] {
        all.filter { $0.unitID == unitID }
    }

    /// Saves a loadout, replacing the unit's loadout of the same name if it
    /// has one. False when the unit already keeps `loadoutsPerUnit` under
    /// other names: the caller says so, rather than the save quietly dropping
    /// the oldest, which is how a player loses the set they spent an evening
    /// building.
    @discardableResult
    static func saveLoadout(_ loadout: RelicLoadout, into all: inout [RelicLoadout]) -> Bool {
        if let index = all.firstIndex(where: { $0.unitID == loadout.unitID && $0.name == loadout.name }) {
            var replacement = loadout
            // Keep the old id: the chips in the loadout bar are identified by
            // it, so replacing a loadout in place should not animate as a
            // delete and an insert.
            replacement.id = all[index].id
            all[index] = replacement
            return true
        }
        guard loadouts(for: loadout.unitID, in: all).count < loadoutsPerUnit else { return false }
        all.append(loadout)
        return true
    }

    static func removeLoadout(_ loadoutID: UUID, from all: inout [RelicLoadout]) {
        all.removeAll { $0.id == loadoutID }
    }

    /// Puts a loadout on, and returns how many slots it filled.
    ///
    /// A slot the loadout names is equipped, taking the relic off whoever
    /// wears it — exactly what the picker's "Take and equip" does. A slot it
    /// does not name is emptied, because a loadout is a whole set of six and
    /// not a patch over what is already there: applying the tank set has to
    /// take the damage set's sixth relic off, or the two sets bleed into one
    /// another and the loadout stops meaning anything. A relic that has been
    /// sold since simply leaves its slot empty.
    @discardableResult
    static func applyLoadout(relicIDs: [Int: UUID], to unitID: UUID, player: inout Player) -> Int {
        var equipped = 0
        for slot in 1...6 {
            guard let relicID = relicIDs[slot],
                  player.relics.contains(where: { $0.id == relicID && $0.slot == slot }) else {
                unequip(slot: slot, from: unitID, player: &player)
                continue
            }
            try? equip(relicID: relicID, on: unitID, player: &player)
            equipped += 1
        }
        return equipped
    }

    // MARK: - The optimiser

    /// What a solve is aiming at.
    ///
    /// Four goals rather than a weighting the player tunes: a slider per stat
    /// is a spreadsheet, and each of these is a sentence the game already
    /// says somewhere — the card's power, how much punishment a unit takes,
    /// what it hits for, and who moves first.
    enum OptimiserGoal: String, CaseIterable, Identifiable, Sendable {
        case power, effectiveHealth, damage, speed

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .power: return "Power"
            case .effectiveHealth: return "Health"
            case .damage: return "Damage"
            case .speed: return "Speed"
            }
        }

        /// The line under the title, so four words are not a riddle.
        var summary: String {
            switch self {
            case .power: return "the card's own number — offence, bulk and tempo together"
            case .effectiveHealth: return "how much damage it takes to kill, HP through the defence curve"
            case .damage: return "what one hit lands for, crits included"
            case .speed: return "who moves first, with power as the tie-break"
            }
        }

        var glyph: String {
            switch self {
            case .power: return "bolt.fill"
            case .effectiveHealth: return "heart.fill"
            case .damage: return "flame.fill"
            case .speed: return "hare.fill"
            }
        }

        /// One row of `effectSetValue`'s table, so that table can read as a
        /// table instead of as four nested switches.
        func weigh(power: Double, health: Double, damage: Double, speed: Double) -> Double {
            switch self {
            case .power: return power
            case .effectiveHealth: return health
            case .damage: return damage
            case .speed: return speed
            }
        }
    }

    /// The relic half of `ProgressionService.resolve`, as twelve running
    /// totals.
    ///
    /// The second stage scores tens of thousands of complete loadouts, and
    /// resolving one properly rebuilds the unit's skills as well — most of
    /// the cost of `resolve`, and nothing the optimiser reads. So a relic is
    /// reduced to this once and a whole loadout is twelve additions.
    ///
    /// It mirrors `resolve`'s accumulate step exactly: flats stay flat,
    /// percentages apply to the base and never to relic flats, and a relic's
    /// SPD is flat where Zephyr's is a percentage. The two are kept in step
    /// by hand — if the resolution rules move, move them here.
    struct StatBundle: Equatable, Sendable {
        var hpFlat: Double = 0
        var atkFlat: Double = 0
        var defFlat: Double = 0
        var spdFlat: Double = 0
        var critRate: Double = 0
        var critDamage: Double = 0
        var accuracy: Double = 0
        var resistance: Double = 0
        var hpPercent: Double = 0
        var atkPercent: Double = 0
        var defPercent: Double = 0
        var spdPercent: Double = 0

        static func + (lhs: StatBundle, rhs: StatBundle) -> StatBundle {
            var sum = lhs
            sum.hpFlat += rhs.hpFlat
            sum.atkFlat += rhs.atkFlat
            sum.defFlat += rhs.defFlat
            sum.spdFlat += rhs.spdFlat
            sum.critRate += rhs.critRate
            sum.critDamage += rhs.critDamage
            sum.accuracy += rhs.accuracy
            sum.resistance += rhs.resistance
            sum.hpPercent += rhs.hpPercent
            sum.atkPercent += rhs.atkPercent
            sum.defPercent += rhs.defPercent
            sum.spdPercent += rhs.spdPercent
            return sum
        }
    }

    /// A solved loadout: the relics, what they scored, and what the search
    /// cost. The last two are what the screen's footer prints, and what a
    /// regression test would assert on.
    struct OptimisedLoadout: Sendable {
        var goal: OptimiserGoal
        var relics: [Relic]
        var score: Double
        var candidatesConsidered: Int
        var loadoutsSearched: Int

        /// The shape `applyLoadout` and `RelicLoadout` want.
        var relicIDs: [Int: UUID] {
            var ids: [Int: UUID] = [:]
            for relic in relics { ids[relic.slot] = relic.id }
            return ids
        }
    }

    /// How many relics per slot reach the second stage.
    ///
    /// The second stage is the cross product of the six shortlists, so it
    /// scores at most K^6 loadouts: 4^6 is 4,096, 6^6 is 46,656, 8^6 is
    /// 262,144. Six, and the number is measured rather than guessed — the
    /// solver was ported to Python and run over a synthetic 200-relic account
    /// at K = 4, 6, 8 and 10, and every K from 4 up returned the identical six
    /// relics for all four goals. Six leaves a margin over the point where the
    /// answer stopped changing without paying 8's five times the work for it.
    /// Below the sixth-best relic in a slot the sub stats are noise; what
    /// actually decides a build is the sets, and those are served by promoting
    /// a best-of-set relic into every shortlist rather than by making the
    /// shortlists longer.
    ///
    /// The cost is bounded by that 46,656 whatever the inventory holds — 600
    /// relics search no more loadouts than 200 do, only the shortlisting
    /// widens — and a leaf is twelve additions, a sixteen-entry set tally and
    /// one score. That is milliseconds in a release build and well inside a
    /// frame even in the debug build the CI tour photographs.
    static let shortlistPerSlot = 6

    /// How many sets get a guaranteed place in every slot's shortlist.
    ///
    /// A shortlist ranked on stats alone would never offer four pieces of one
    /// four-piece set, so a solver built on it answers with six mismatched
    /// relics every time. In the Python run above, turning promotion off cost
    /// 1% of the best score at the damage goal, 5% at power and 16% at speed —
    /// a whole Zephyr — which is the difference between a solver worth opening
    /// and a list of the six shiniest relics. Three covers the shapes a build
    /// takes (one four-piece and one two-piece, or three two-pieces), and each
    /// promotion costs a place that would have gone to a better-rolled relic.
    static let promotedSetCount = 3

    /// What a solve may draw on: the relics the unit already wears, plus the
    /// relics nobody wears.
    ///
    /// A relic on another unit is never proposed. The optimiser would
    /// otherwise strip the second team to dress the first, which is a thing
    /// the player has to choose to do, one relic at a time, in the picker.
    /// `isLocked` guards against selling and not against equipping, so a
    /// locked free relic is fair game.
    static func optimiserCandidates(for unitID: UUID, in relics: [Relic]) -> [Relic] {
        relics.filter { $0.equippedBy == nil || $0.equippedBy == unitID }
    }

    /// Adds one modifier to a bundle, by `ProgressionService.resolve`'s rules.
    static func fold(_ modifier: StatModifier, into bundle: inout StatBundle, speedIsPercent: Bool) {
        switch modifier.kind {
        case .hpFlat: bundle.hpFlat += modifier.value
        case .atkFlat: bundle.atkFlat += modifier.value
        case .defFlat: bundle.defFlat += modifier.value
        case .hpPercent: bundle.hpPercent += modifier.value
        case .atkPercent: bundle.atkPercent += modifier.value
        case .defPercent: bundle.defPercent += modifier.value
        case .spd:
            if speedIsPercent {
                bundle.spdPercent += modifier.value
            } else {
                bundle.spdFlat += modifier.value
            }
        case .critRate: bundle.critRate += modifier.value
        case .critDamage: bundle.critDamage += modifier.value
        case .accuracy: bundle.accuracy += modifier.value
        case .resistance: bundle.resistance += modifier.value
        }
    }

    /// One relic reduced to its twelve numbers, main stat at its level plus
    /// every sub stat.
    static func statBundle(of relic: Relic) -> StatBundle {
        var bundle = StatBundle()
        for modifier in relic.allStats {
            fold(modifier, into: &bundle, speedIsPercent: false)
        }
        return bundle
    }

    /// Base stats plus a bundle, by `resolve`'s step three: percentages apply
    /// to the base, never to the flats a relic added.
    static func finalStats(base: Stats, bundle: StatBundle) -> Stats {
        var final = base
        final.hp += bundle.hpFlat + base.hp * bundle.hpPercent
        final.atk += bundle.atkFlat + base.atk * bundle.atkPercent
        final.def += bundle.defFlat + base.def * bundle.defPercent
        final.spd += bundle.spdFlat + base.spd * bundle.spdPercent
        final.critRate += bundle.critRate
        final.critDamage += bundle.critDamage
        final.accuracy += bundle.accuracy
        final.resistance += bundle.resistance
        return final.clamped()
    }

    /// `ResolvedUnit.power`'s formula, on bare stats and without the rounding.
    ///
    /// Unit.swift computes it on a resolved unit and returns an Int; the
    /// solver needs it on a `Stats` it never resolved, and needs the
    /// fraction, because the speed goal uses it as a tie-break. The two are
    /// the same three lines and are kept in step by hand: change
    /// `ResolvedUnit.power` and change this.
    static func powerScore(_ stats: Stats) -> Double {
        let offense = stats.atk * (1 + stats.critRate * stats.critDamage)
        let survivability = stats.hp * (1 + stats.def / 1000)
        let tempo = stats.spd / 100
        return (offense * 1.6 + survivability * 0.22) * tempo
    }

    /// What a set of final stats is worth to a goal. Higher is better; the
    /// units differ per goal, so nothing ever compares two goals' scores.
    static func goalScore(_ stats: Stats, for goal: OptimiserGoal) -> Double {
        switch goal {
        case .power:
            return powerScore(stats)
        case .effectiveHealth:
            // HP through the same defence curve the battle uses, so the number
            // means "damage taken to die" rather than "HP, and some DEF".
            // `mitigation` is the fraction of a hit that gets through.
            return stats.hp / max(0.000_001, DamageCalculator.mitigation(defense: stats.def, ignore: 0))
        case .damage:
            // One hit, crits included. The skill multiplier, the element
            // matchup and the target's defence are the same for every loadout
            // being compared, so none of them can change the ranking.
            return stats.atk * (1 + stats.critRate * stats.critDamage)
        case .speed:
            // SPD is a whole number after `clamped()`, so the integer part is
            // the goal and the fraction is a tie-break: between two loadouts
            // that both reach 180 SPD, take the stronger one. The tie-break is
            // capped so it can never carry into the next point of speed.
            return stats.spd + min(powerScore(stats), 9_999_999) / 10_000_000
        }
    }

    /// What one completed four-piece effect set is worth, as a multiplier on
    /// a goal's score.
    ///
    /// The two-piece stat sets need nothing here: their bonus is a
    /// `StatModifier` and goes through the same arithmetic as a sub stat. The
    /// effect sets move no stat at all, so a solver that only reads `Stats`
    /// values them at zero and would never build Titanfall or Wrath on an
    /// attacker — which is the wrong answer, and the reason this table
    /// exists. The numbers are the solver's own judgement and deliberately
    /// modest: the largest is Titanfall's, the one effect whose own words are
    /// a damage multiplier. They are not battle numbers, nothing else reads
    /// them, and a set effect can never outweigh a large stat gap.
    static func effectSetValue(_ relicSet: RelicSet, for goal: OptimiserGoal) -> Double {
        switch relicSet {
        // "+30% damage but cannot be healed": the damage is literal, and the
        // clause is a real cost to a build that means to stay standing.
        case .titanfall: return goal.weigh(power: 1.12, health: 0.90, damage: 1.30, speed: 1.00)
        // A 22% chance of another turn is close to a fifth more attacks.
        case .wrath: return goal.weigh(power: 1.10, health: 1.00, damage: 1.18, speed: 1.06)
        // A quarter of the attack bar every turn is tempo, not damage.
        case .ichor: return goal.weigh(power: 1.06, health: 1.00, damage: 1.06, speed: 1.10)
        case .nemesis: return goal.weigh(power: 1.04, health: 1.02, damage: 1.02, speed: 1.06)
        // Both of these buy survival rather than stats, and only Styx needs
        // the unit to be dealing damage in the first place.
        case .styx: return goal.weigh(power: 1.05, health: 1.12, damage: 1.00, speed: 1.00)
        case .fates: return goal.weigh(power: 1.04, health: 1.10, damage: 1.00, speed: 1.00)
        case .vigil: return goal.weigh(power: 1.05, health: 1.04, damage: 1.06, speed: 1.00)
        case .chains: return goal.weigh(power: 1.02, health: 1.02, damage: 1.00, speed: 1.02)
        default: return 1.0
        }
    }

    /// One candidate as the search needs it: no `Relic`, because the inner
    /// loop touches these tens of thousands of times and a `Relic` carries an
    /// array of sub stats that would be retained and released at every step.
    private struct SolveCandidate {
        var bundle: StatBundle
        var setIndex: Int
        var isWorn: Bool
        var relicID: UUID
        var score: Double
    }

    /// The best six relics the player owns for one unit under one goal.
    ///
    /// Two stages, because brute force is out of the question: two hundred
    /// relics is about thirty-three a slot, and 33^6 is 1.3 billion loadouts.
    /// Stage one scores every candidate on its own and keeps
    /// `shortlistPerSlot` of them per slot, plus the best piece of each
    /// promoted set. Stage two walks the cross product of the six shortlists
    /// and scores complete loadouts with the set bonuses in — which is the
    /// only place a set can be scored, since it is a property of the six and
    /// of no one relic.
    ///
    /// Deterministic: candidates rank by score and then by id, so the same
    /// inventory and the same goal give the same six every time. A tie is
    /// broken towards what the unit already wears, so the screen does not
    /// propose shuffling four relics for nothing.
    static func optimise(unitID: UUID, goal: OptimiserGoal, player: Player) -> OptimisedLoadout? {
        guard let unit = player.unit(unitID),
              let blueprint = UnitDatabase.blueprint(unit.blueprintID) else { return nil }

        let base = ProgressionService.baseStats(for: unit, blueprint: blueprint)
        let candidates = optimiserCandidates(for: unitID, in: player.relics)
        guard !candidates.isEmpty else { return nil }

        let allSets = RelicSet.allCases
        var indexOfSet: [RelicSet: Int] = [:]
        for (index, relicSet) in allSets.enumerated() { indexOfSet[relicSet] = index }

        // Stage one, part one: which sets are worth building around. A set is
        // measured on the unit's bare stats, which is enough to rank them —
        // 35% ATK is worth more to an attacker than 20% resistance whatever
        // else it ends up wearing.
        let bare = goalScore(finalStats(base: base, bundle: StatBundle()), for: goal)
        var setValues: [(relicSet: RelicSet, value: Double)] = []
        for relicSet in allSets {
            // Only a set the inventory can actually finish: four pieces of
            // Ichor spread over three slots is three pieces.
            var slots: Set<Int> = []
            for relic in candidates where relic.set == relicSet { slots.insert(relic.slot) }
            guard slots.count >= relicSet.piecesRequired else { continue }

            if let bonus = relicSet.statBonus {
                var bundle = StatBundle()
                fold(bonus, into: &bundle, speedIsPercent: true)
                let value = goalScore(finalStats(base: base, bundle: bundle), for: goal) - bare
                setValues.append((relicSet: relicSet, value: value))
            } else {
                setValues.append((relicSet: relicSet, value: bare * (effectSetValue(relicSet, for: goal) - 1)))
            }
        }
        setValues.sort { first, second in
            if first.value != second.value { return first.value > second.value }
            return first.relicSet.rawValue < second.relicSet.rawValue
        }
        let promoted = setValues.prefix(promotedSetCount).map { $0.relicSet }

        // Stage one, part two: the shortlists.
        var shortlists: [[SolveCandidate]] = []
        for slot in 1...6 {
            var ranked: [SolveCandidate] = []
            for relic in candidates where relic.slot == slot {
                let bundle = statBundle(of: relic)
                ranked.append(SolveCandidate(
                    bundle: bundle,
                    setIndex: indexOfSet[relic.set] ?? 0,
                    isWorn: relic.equippedBy == unitID,
                    relicID: relic.id,
                    score: goalScore(finalStats(base: base, bundle: bundle), for: goal)
                ))
            }
            guard !ranked.isEmpty else { continue }
            ranked.sort { first, second in
                if first.score != second.score { return first.score > second.score }
                // The id is the tie-break, and it is what makes the whole solve
                // repeatable: two equally good relics must always sort the same
                // way round.
                return first.relicID.uuidString < second.relicID.uuidString
            }

            var chosen: [SolveCandidate] = []
            var taken: Set<UUID> = []
            for relicSet in promoted {
                guard let index = indexOfSet[relicSet],
                      let best = ranked.first(where: { $0.setIndex == index }),
                      !taken.contains(best.relicID) else { continue }
                chosen.append(best)
                taken.insert(best.relicID)
            }
            for candidate in ranked where chosen.count < shortlistPerSlot {
                guard !taken.contains(candidate.relicID) else { continue }
                chosen.append(candidate)
                taken.insert(candidate.relicID)
            }
            shortlists.append(chosen)
        }
        guard !shortlists.isEmpty else { return nil }

        // Stage two: the cross product, scored whole. The set tally and the
        // running totals are carried down the recursion and undone on the way
        // back up, so a leaf costs one score rather than a rebuild.
        var setCounts = [Int](repeating: 0, count: allSets.count)
        var picks = [Int](repeating: 0, count: shortlists.count)
        var bestPicks: [Int]?
        var bestScore = -Double.greatestFiniteMagnitude
        var bestWorn = -1
        var searched = 0

        func search(_ index: Int, _ bundle: StatBundle, _ worn: Int) {
            guard index < shortlists.count else {
                searched += 1
                var loadout = bundle
                var multiplier = 1.0
                for (setIndex, count) in setCounts.enumerated() where count > 0 {
                    let relicSet = allSets[setIndex]
                    let completions = count / relicSet.piecesRequired
                    guard completions > 0 else { continue }
                    for _ in 0..<completions {
                        if let bonus = relicSet.statBonus {
                            fold(bonus, into: &loadout, speedIsPercent: true)
                        } else {
                            multiplier *= effectSetValue(relicSet, for: goal)
                        }
                    }
                }
                let score = goalScore(finalStats(base: base, bundle: loadout), for: goal) * multiplier
                let epsilon = max(abs(bestScore), 1) * 1e-9
                if score > bestScore + epsilon || (score > bestScore - epsilon && worn > bestWorn) {
                    bestScore = score
                    bestWorn = worn
                    bestPicks = picks
                }
                return
            }
            for candidateIndex in shortlists[index].indices {
                picks[index] = candidateIndex
                setCounts[shortlists[index][candidateIndex].setIndex] += 1
                search(
                    index + 1,
                    bundle + shortlists[index][candidateIndex].bundle,
                    worn + (shortlists[index][candidateIndex].isWorn ? 1 : 0)
                )
                setCounts[shortlists[index][candidateIndex].setIndex] -= 1
            }
        }
        search(0, StatBundle(), 0)

        guard let bestPicks else { return nil }
        var relics: [Relic] = []
        for (index, pick) in bestPicks.enumerated() {
            if let relic = player.relic(shortlists[index][pick].relicID) { relics.append(relic) }
        }
        return OptimisedLoadout(
            goal: goal,
            relics: relics.sorted { $0.slot < $1.slot },
            score: bestScore,
            candidatesConsidered: candidates.count,
            loadoutsSearched: searched
        )
    }
}

/// A named set of six relics saved against one unit.
///
/// Ids, not relics: a loadout is a bookmark into the inventory, so selling a
/// relic cannot leave a stale copy of it in the save, and applying a loadout
/// whose relic has been sold since simply leaves that slot empty.
struct RelicLoadout: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var unitID: UUID
    /// The goal that built it — "Power", "Damage" — which is also what the
    /// chip says. There is no keyboard anywhere in this game, so a loadout
    /// takes the name of the goal rather than one the player types.
    var name: String
    /// Relic ids by slot (1...6), the same shape as `Unit.equippedRelics`. A
    /// slot with no entry is a slot this loadout leaves empty.
    var relicIDs: [Int: UUID]
}

// MARK: - Whetstones and gems

extension RelicService {
    enum StoneError: Error, LocalizedError {
        case noStone(RelicStone)
        case notEnoughDrachma(needed: Int)
        case noSuchSubStat
        case anotherSubIsGemmed(index: Int)
        case kindNotAllowed

        var errorDescription: String? {
            switch self {
            case .noStone(let stone): return "You have no \(stone.displayName). Raids drop them."
            case .notEnoughDrachma(let needed): return "That costs \(needed) drachma."
            case .noSuchSubStat: return "That relic has no sub stat there."
            case .anotherSubIsGemmed(let index):
                return "Sub stat \(index + 1) already carries this relic's gem; a relic holds one."
            case .kindNotAllowed: return "A gem cannot repeat the main stat or another sub stat."
            }
        }
    }

    /// One honing: what was rolled, and the bonus before and after (the
    /// better of the two is kept, so `after` never falls).
    struct HoneOutcome: Equatable, Sendable {
        var kind: StatKind
        var rolled: Double
        var before: Double
        var after: Double
        var improved: Bool { after > before }
    }

    struct GemOutcome: Equatable, Sendable {
        var before: StatModifier
        var after: StatModifier
    }

    static func stoneCount(_ stone: RelicStone, player: Player) -> Int {
        player.relicStones?[stone.id] ?? 0
    }

    static func addStones(_ id: String, _ count: Int, player: inout Player) {
        var stones = player.relicStones ?? [:]
        stones[id, default: 0] += count
        player.relicStones = stones
    }

    private static func spend(_ stone: RelicStone, player: inout Player) {
        var stones = player.relicStones ?? [:]
        let left = max(0, (stones[stone.id] ?? 0) - 1)
        stones[stone.id] = left == 0 ? nil : left
        player.relicStones = stones.isEmpty ? nil : stones
    }

    /// Flats and speed are whole numbers, percentages a tenth of a percent.
    private static func settle(_ kind: StatKind, _ value: Double) -> Double {
        kind.isPercentage ? (value * 1000).rounded() / 1000 : value.rounded()
    }

    /// The span a stone gives a kind, for the screen's "SPD +3.8–5.7": the
    /// tier's fraction of a 6★ sub roll's base.
    static func stoneSpan(_ stone: RelicStone, kind: StatKind) -> ClosedRange<Double> {
        let base = subStatBase(kind: kind, grade: 6)
        return settle(kind, base * stone.range.lowerBound)...settle(kind, base * stone.range.upperBound)
    }

    static func stoneRoll(_ stone: RelicStone, kind: StatKind, rng: inout SeededRandom) -> Double {
        settle(kind, subStatBase(kind: kind, grade: 6) * rng.double(in: stone.range))
    }

    /// The kinds a gem may put in the sub stat at `index`: the pool less the
    /// main stat and the other subs.
    static func gemKinds(for relic: Relic, replacing index: Int) -> [StatKind] {
        let taken = Set(relic.subStats.enumerated().filter { $0.offset != index }.map { $0.element.kind })
        return subStatPool.filter { $0 != relic.mainStat.kind && !taken.contains($0) }
    }

    /// Hones the sub stat at `index` with a whetstone of `tier`: the stone
    /// and the drachma are spent, the better of the old bonus and the roll
    /// is kept.
    static func hone(
        relicID: UUID, subStat index: Int, tier: RelicStone.Tier,
        player: inout Player, rng: inout SeededRandom
    ) throws -> HoneOutcome {
        guard let relicIndex = player.relics.firstIndex(where: { $0.id == relicID }),
              player.relics[relicIndex].subStats.indices.contains(index) else {
            throw StoneError.noSuchSubStat
        }
        let stone = RelicStone(kind: .whetstone, tier: tier)
        guard stoneCount(stone, player: player) > 0 else { throw StoneError.noStone(stone) }
        guard player.wallet.drachma >= stone.cost else { throw StoneError.notEnoughDrachma(needed: stone.cost) }

        var relic = player.relics[relicIndex]
        let kind = relic.subStats[index].kind
        let rolled = stoneRoll(stone, kind: kind, rng: &rng)
        let before = relic.honedBonus(at: index)
        var honed = relic.honed ?? [:]
        honed[index] = max(before, rolled)
        relic.honed = honed
        player.relics[relicIndex] = relic
        player.wallet.drachma -= stone.cost
        spend(stone, player: &player)
        return HoneOutcome(kind: kind, rolled: rolled, before: before, after: max(before, rolled))
    }

    /// Replaces the sub stat at `index` with `kind` at a gem of `tier`'s
    /// roll. One gemmed sub per relic: the same index may be gemmed again,
    /// another may not. The honing on that sub goes with it.
    static func engrave(
        relicID: UUID, subStat index: Int, with kind: StatKind, tier: RelicStone.Tier,
        player: inout Player, rng: inout SeededRandom
    ) throws -> GemOutcome {
        guard let relicIndex = player.relics.firstIndex(where: { $0.id == relicID }),
              player.relics[relicIndex].subStats.indices.contains(index) else {
            throw StoneError.noSuchSubStat
        }
        var relic = player.relics[relicIndex]
        if let gemmed = relic.gemmed, gemmed != index { throw StoneError.anotherSubIsGemmed(index: gemmed) }
        guard gemKinds(for: relic, replacing: index).contains(kind) else { throw StoneError.kindNotAllowed }
        let stone = RelicStone(kind: .gem, tier: tier)
        guard stoneCount(stone, player: player) > 0 else { throw StoneError.noStone(stone) }
        guard player.wallet.drachma >= stone.cost else { throw StoneError.notEnoughDrachma(needed: stone.cost) }

        let before = relic.subStats[index]
        let after = StatModifier(kind, stoneRoll(stone, kind: kind, rng: &rng))
        relic.subStats[index] = after
        relic.gemmed = index
        if var honed = relic.honed {
            honed[index] = nil
            relic.honed = honed.isEmpty ? nil : honed
        }
        player.relics[relicIndex] = relic
        player.wallet.drachma -= stone.cost
        spend(stone, player: &player)
        return GemOutcome(before: before, after: after)
    }

    /// Every slot emptied. Free, on purpose: the genre charges for removal
    /// and its players resent it, and the owner never asked for the fee.
    static func unequipAll(unitID: UUID, player: inout Player) {
        guard let unitIndex = player.units.firstIndex(where: { $0.id == unitID }) else { return }
        for slot in Array(player.units[unitIndex].equippedRelics.keys) {
            unequip(slot: slot, from: unitID, player: &player)
        }
    }
}
