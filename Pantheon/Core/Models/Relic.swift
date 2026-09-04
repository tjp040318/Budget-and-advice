import Foundation

/// Equipment sets. Two-piece sets are stat sets; four-piece sets are effects.
/// Mirrors the rune economy the genre runs on: six slots, sets stack, and the
/// hunt for a good roll is the endgame.
enum RelicSet: String, Codable, CaseIterable, Identifiable, Sendable {
    // 2-piece stat sets
    case fury          // ATK +35%
    case aegis         // DEF +35%
    case bulwark       // HP +35%
    case zephyr        // SPD +25%
    case thunder       // CRIT Rate +30%
    case ruin          // CRIT DMG +40%
    case oracle        // Accuracy +20%
    case wards         // Resistance +20%

    // 4-piece effect sets
    case ichor         // Fills 25% attack bar on turn start
    case wrath         // 22% chance for an extra turn after acting
    case styx          // Heals 35% of damage dealt
    case chains        // 25% chance to Slow on hit
    case fates         // Starts with a shield worth 15% of max HP for 3 turns
    case nemesis       // Fills attack bar as health is lost
    case titanfall     // +30% damage but cannot be healed
    case vigil         // 15% chance to counterattack

    var id: String { rawValue }

    var piecesRequired: Int {
        switch self {
        case .fury, .aegis, .bulwark, .zephyr, .thunder, .ruin, .oracle, .wards:
            return 2
        default:
            return 4
        }
    }

    var displayName: String {
        switch self {
        case .fury: return "Fury"
        case .aegis: return "Aegis"
        case .bulwark: return "Bulwark"
        case .zephyr: return "Zephyr"
        case .thunder: return "Thunder"
        case .ruin: return "Ruin"
        case .oracle: return "Oracle"
        case .wards: return "Wards"
        case .ichor: return "Ichor"
        case .wrath: return "Wrath"
        case .styx: return "Styx"
        case .chains: return "Chains"
        case .fates: return "Fates"
        case .nemesis: return "Nemesis"
        case .titanfall: return "Titanfall"
        case .vigil: return "Vigil"
        }
    }

    /// Flat stat granted per completed set. Effect sets return nil.
    var statBonus: StatModifier? {
        switch self {
        case .fury: return StatModifier(.atkPercent, 0.35)
        case .aegis: return StatModifier(.defPercent, 0.35)
        case .bulwark: return StatModifier(.hpPercent, 0.35)
        case .zephyr: return StatModifier(.spd, 0.25)
        case .thunder: return StatModifier(.critRate, 0.30)
        case .ruin: return StatModifier(.critDamage, 0.40)
        case .oracle: return StatModifier(.accuracy, 0.20)
        case .wards: return StatModifier(.resistance, 0.20)
        default: return nil
        }
    }

    var effectDescription: String {
        switch self {
        case .ichor: return "Fills 25% of the attack bar at the start of each turn."
        case .wrath: return "22% chance to take another turn immediately after acting."
        case .styx: return "Recovers HP equal to 35% of the damage dealt."
        case .chains: return "25% chance to Slow the target for 2 turns on hit."
        case .fates: return "Begins each battle with a Shield worth 15% of max HP for 3 turns."
        case .nemesis: return "Fills 4% of the attack bar for every 7% of HP lost."
        case .titanfall: return "Deals 30% more damage but cannot recover HP."
        case .vigil: return "15% chance to counterattack when hit."
        default: return statBonus?.displayText ?? ""
        }
    }
}

/// A single equippable relic.
struct Relic: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var set: RelicSet
    /// 1...6. Odd slots have fixed flat main stats; even slots are free.
    var slot: Int
    /// 1...6 stars. Higher grade means bigger main stat and better roll ceilings.
    var grade: Int
    var level: Int = 0

    var mainStat: StatModifier
    var subStats: [StatModifier]

    /// Set by `RelicService` when the relic is equipped, so the inventory can
    /// show what is in use without scanning the whole collection.
    var equippedBy: UUID?
    var isLocked: Bool = false

    var maxLevel: Int { 15 }
    var isMaxLevel: Bool { level >= maxLevel }

    /// Main stat value at the current level. Grows linearly to roughly 3x its
    /// starting value at +15, which is what makes upgrading worth the currency.
    var effectiveMainStat: StatModifier {
        let growth = 1.0 + (Double(level) / Double(maxLevel)) * 2.0
        return StatModifier(mainStat.kind, mainStat.value * growth)
    }

    var allStats: [StatModifier] { [effectiveMainStat] + subStats }

    /// Slots 1, 3 and 5 always carry the same flat main stat in this game, which
    /// gives every build the same floor and makes the even slots the decision.
    static func fixedMainStat(forSlot slot: Int) -> StatKind? {
        switch slot {
        case 1: return .atkFlat
        case 3: return .defFlat
        case 5: return .hpFlat
        default: return nil
        }
    }

    /// Main stats a free slot is allowed to roll.
    static func allowedMainStats(forSlot slot: Int) -> [StatKind] {
        switch slot {
        case 2: return [.atkPercent, .defPercent, .hpPercent, .spd]
        case 4: return [.atkPercent, .defPercent, .hpPercent, .critRate, .critDamage]
        case 6: return [.atkPercent, .defPercent, .hpPercent, .accuracy, .resistance]
        default: return [fixedMainStat(forSlot: slot)].compactMap { $0 }
        }
    }
}
