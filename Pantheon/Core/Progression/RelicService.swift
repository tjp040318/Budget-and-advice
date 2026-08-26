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
        let gradeScale = 1.0 + Double(max(1, grade) - 1) * 0.22
        let jitter = rng.double(in: 0.75...1.25)
        switch kind {
        case .hpFlat: return (95 * gradeScale * jitter).rounded()
        case .atkFlat: return (7 * gradeScale * jitter).rounded()
        case .defFlat: return (7 * gradeScale * jitter).rounded()
        case .hpPercent, .atkPercent, .defPercent: return 0.03 * gradeScale * jitter
        case .spd: return (3 * gradeScale * jitter).rounded()
        case .critRate: return 0.025 * gradeScale * jitter
        case .critDamage: return 0.035 * gradeScale * jitter
        case .accuracy: return 0.03 * gradeScale * jitter
        case .resistance: return 0.03 * gradeScale * jitter
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
        rng: inout SeededRandom
    ) -> Relic {
        let clampedGrade = max(1, min(6, grade))
        let chosenSlot = slot ?? rng.int(in: 1...6)
        let chosenSet = set ?? rng.pickMutating(RelicSet.allCases) ?? .fury

        let mainKind: StatKind = Relic.fixedMainStat(forSlot: chosenSlot)
            ?? rng.pickMutating(Relic.allowedMainStats(forSlot: chosenSlot))
            ?? .atkPercent
        let main = StatModifier(mainKind, mainStatValue(kind: mainKind, grade: clampedGrade))

        // 4★ drops start with 1-2 subs, 6★ with 2-4. Never duplicates the main.
        let subCount = max(1, min(4, clampedGrade - 2 + rng.int(in: 0...1)))
        var available = subStatPool.filter { $0 != mainKind }
        var subs: [StatModifier] = []
        for _ in 0..<subCount {
            guard let kind = rng.pickMutating(available) else { break }
            available.removeAll { $0 == kind }
            subs.append(StatModifier(kind, subStatRoll(kind: kind, grade: clampedGrade, rng: &rng)))
        }

        return Relic(set: chosenSet, slot: chosenSlot, grade: clampedGrade, mainStat: main, subStats: subs)
    }

    /// A full six-piece loadout, used to kit out arena opponents and the
    /// starter account without hand-authoring inventory.
    static func generateLoadout(
        grade: Int,
        primarySet: RelicSet,
        secondarySet: RelicSet,
        upgradeLevel: Int,
        rng: inout SeededRandom
    ) -> [Relic] {
        (1...6).map { slot in
            let set: RelicSet = slot <= primarySet.piecesRequired ? primarySet : secondarySet
            var relic = generate(grade: grade, slot: slot, set: set, rng: &rng)
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

    /// One +1. Every fourth level rolls a new sub stat or improves an existing
    /// one, which is where the grind's variance lives.
    static func upgradeOnce(_ relic: inout Relic, rng: inout SeededRandom) {
        guard !relic.isMaxLevel else { return }
        relic.level += 1

        guard relic.level % 3 == 0 else { return }

        if relic.subStats.count < 4 {
            let available = subStatPool.filter { kind in
                kind != relic.mainStat.kind && !relic.subStats.contains(where: { $0.kind == kind })
            }
            if let kind = rng.pickMutating(available) {
                relic.subStats.append(
                    StatModifier(kind, subStatRoll(kind: kind, grade: relic.grade, rng: &rng))
                )
                return
            }
        }

        guard !relic.subStats.isEmpty else { return }
        let index = rng.int(in: 0...(relic.subStats.count - 1))
        let bump = subStatRoll(kind: relic.subStats[index].kind, grade: relic.grade, rng: &rng)
        relic.subStats[index].value += bump
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

    static func upgrade(
        _ relic: inout Relic,
        wallet: inout Wallet,
        rng: inout SeededRandom
    ) throws {
        guard !relic.isMaxLevel else { throw RelicError.maxLevel }
        let cost = upgradeCost(grade: relic.grade, level: relic.level)
        guard wallet.drachma >= cost else { throw RelicError.notEnoughDrachma(needed: cost) }
        wallet.drachma -= cost
        upgradeOnce(&relic, rng: &rng)
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
}
