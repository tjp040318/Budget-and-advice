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

    /// A symbol per set, for the places that still draw a glyph rather than
    /// the emblem (the missions list, a fallback when the art is missing).
    var glyph: String {
        switch self {
        case .fury: return "flame.fill"
        case .aegis: return "shield.fill"
        case .bulwark: return "heart.fill"
        case .zephyr: return "wind"
        case .thunder: return "bolt.fill"
        case .ruin: return "burst.fill"
        case .oracle: return "eye.fill"
        case .wards: return "circle.hexagongrid.fill"
        case .ichor: return "drop.fill"
        case .wrath: return "tornado"
        case .styx: return "waveform.path"
        case .chains: return "link"
        case .fates: return "sparkles"
        case .nemesis: return "arrow.up.heart.fill"
        case .titanfall: return "mountain.2.fill"
        case .vigil: return "arrow.uturn.backward"
        }
    }

    /// The set's emblem as it is engraved on the stones: a bundle template
    /// image (`relic_emblem_<set>`, white on clear, tinted by the app) drawn
    /// by `tools/relic_art.py`, for chips and lists.
    var emblemImageName: String { "relic_emblem_\(rawValue)" }

    /// The stone's colour, as the art tool paints it, for the places that
    /// tint something by set (a glow behind the card). Kept in step with
    /// `SETS` in `tools/relic_art.py` by hand.
    var stoneHex: String {
        switch self {
        case .fury: return "#B8323A"
        case .aegis: return "#3D5A8A"
        case .bulwark: return "#3E7A4A"
        case .zephyr: return "#3A9BA6"
        case .thunder: return "#D08A1E"
        case .ruin: return "#6E2A5A"
        case .oracle: return "#6B4FB0"
        case .wards: return "#35437A"
        case .ichor: return "#8E3A1E"
        case .wrath: return "#A0306E"
        case .styx: return "#23414A"
        case .chains: return "#55606B"
        case .fates: return "#C9CCD3"
        case .nemesis: return "#7A2E2E"
        case .titanfall: return "#7A5A3A"
        case .vigil: return "#7C6428"
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
        // SPD is a flat kind everywhere else, so the modifier's own text
        // printed the set's quarter as "SPD +0" on the reference sheet;
        // the bonus is applied as a percent of base speed
        // (`ProgressionService.resolve`, `speedIsPercent`).
        case .zephyr: return "SPD +25%"
        default: return statBonus?.displayText ?? ""
        }
    }
}

/// How many sub stats a relic dropped with — the genre's rune rarity, named
/// its way (Normal, Magic, Rare, Hero, Legend) so a player who knows the
/// genre reads it at once. It colours the rim and the name; the grade, the
/// stars, is a separate thing, and a 6★ Normal is the trash the genre sells
/// on the drop screen. The count IS the quality: a Normal has no sub stat
/// until +3 adds one, and every quality reaches four by +12.
enum RelicQuality: Int, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    case normal = 0, magic, rare, hero, legend

    var id: Int { rawValue }
    var subStatCount: Int { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .magic: return "Magic"
        case .rare: return "Rare"
        case .hero: return "Hero"
        case .legend: return "Legend"
        }
    }

    static func < (a: RelicQuality, b: RelicQuality) -> Bool { a.rawValue < b.rawValue }

    /// Drop odds by grade, in percent, Normal through Legend. A 6★ is a
    /// Legend one time in eight — higher than the genre's top dungeon (about
    /// one in twenty, as remembered), because nothing here is paced by a
    /// cash shop. Mirrored in `tools/balance.py` as `QUALITY_WEIGHTS`.
    static func weights(forGrade grade: Int) -> [Int] {
        switch max(1, min(6, grade)) {
        case 1, 2: return [45, 35, 15, 5, 0]
        case 3: return [30, 35, 22, 10, 3]
        case 4: return [18, 32, 28, 15, 7]
        case 5: return [10, 26, 32, 21, 11]
        default: return [6, 22, 34, 26, 12]
        }
    }
}

/// The genre's grindstones and enchanted gems, in three tiers and one kind
/// of each — not one per set, which is the part of that system its players
/// complain about. A whetstone hones one sub stat: a bonus on top of its
/// rolled value, within the tier's range, and honing again keeps the better
/// bonus. A gem replaces one sub stat with a chosen kind at a value in the
/// tier's range; one gemmed sub per relic, the same one may be gemmed again,
/// and a gem clears that sub's honing. Counted in `Player.relicStones` by id.
struct RelicStone: Hashable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case whetstone, gem

        var displayName: String {
            switch self {
            case .whetstone: return "Whetstone"
            case .gem: return "Gem"
            }
        }

        var glyph: String {
            switch self {
            case .whetstone: return "seal.fill"
            case .gem: return "diamond.fill"
            }
        }
    }

    /// The raw values line up with `RelicQuality`, which is what colours a
    /// stone's tile: a Legend gem wears the Legend metal.
    enum Tier: Int, CaseIterable, Comparable, Sendable {
        case rare = 2, hero, legend

        var name: String {
            switch self {
            case .rare: return "rare"
            case .hero: return "hero"
            case .legend: return "legend"
            }
        }

        var displayName: String { quality.displayName }
        var quality: RelicQuality { RelicQuality(rawValue: rawValue) ?? .rare }

        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    var kind: Kind
    var tier: Tier

    var id: String { "\(kind.rawValue)_\(tier.name)" }
    var displayName: String { "\(tier.displayName) \(kind.displayName)" }

    static let all: [RelicStone] = Kind.allCases.flatMap { kind in
        Tier.allCases.map { RelicStone(kind: kind, tier: $0) }
    }

    static func from(id: String) -> RelicStone? {
        all.first(where: { $0.id == id })
    }

    /// What the stone gives, as a fraction of a 6★ sub roll's base
    /// (`RelicService.subStatBase(kind:grade: 6)`, SPD 6.3): a whetstone's
    /// bonus, a gem's new value. A Legend whetstone is SPD +3.8–5.7 and a
    /// Legend gem SPD 7.6–9.5, the genre's +4–5 and 8–10. Mirrored in
    /// `tools/balance.py` as `STONE_RANGES`.
    var range: ClosedRange<Double> {
        switch (kind, tier) {
        case (.whetstone, .rare): return 0.25...0.45
        case (.whetstone, .hero): return 0.40...0.65
        case (.whetstone, .legend): return 0.60...0.90
        case (.gem, .rare): return 0.85...1.05
        case (.gem, .hero): return 1.00...1.25
        case (.gem, .legend): return 1.20...1.50
        }
    }

    /// Drachma per use. Mirrored in `tools/balance.py` as `STONE_COSTS`.
    var cost: Int {
        switch (kind, tier) {
        case (.whetstone, .rare): return 4_000
        case (.whetstone, .hero): return 9_000
        case (.whetstone, .legend): return 16_000
        case (.gem, .rare): return 6_000
        case (.gem, .hero): return 14_000
        case (.gem, .legend): return 24_000
        }
    }

    var summary: String {
        switch kind {
        case .whetstone: return "Hones one sub stat: a bonus on top of its roll. Honing again keeps the better."
        case .gem: return "Replaces one sub stat with a stat of your choosing. One gemmed sub per relic."
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

    /// How many sub stats it dropped with. Optional so a save from before
    /// qualities decodes — the synthesised decoder tolerates a missing
    /// optional key and nothing else — and `resolvedQuality` reads an old
    /// relic's off its subs, its level and the old generator's floor.
    var quality: RelicQuality? = nil
    /// A whetstone's bonus on a sub stat, by index into `subStats`, kept
    /// apart from the rolled value the way the genre shows a grind. Optional
    /// for the same reason.
    var honed: [Int: Double]? = nil
    /// The index of the sub stat a gem replaced, if one has. One per relic.
    var gemmed: Int? = nil

    var maxLevel: Int { 15 }
    var isMaxLevel: Bool { level >= maxLevel }

    /// The quality, for a relic saved before there was one: the subs it has
    /// less the rolls its level has made, and never below the old
    /// generator's floor of `grade - 2` (a 6★ always dropped with four).
    var resolvedQuality: RelicQuality {
        if let quality { return quality }
        let rolls = min(level, 12) / 3
        let estimate = max(subStats.count - rolls, grade - 2, 0)
        return RelicQuality(rawValue: min(4, estimate)) ?? .normal
    }

    /// Main stat value at the current level: linear to +14, then the last
    /// level's jump to 3x the starting value — the genre's +15, which is
    /// what makes the expensive last attempt worth the drachma.
    var effectiveMainStat: StatModifier { projectedMainStat(atLevel: level) }

    /// The main stat at any level, for the card's "at +15" figure — the
    /// number the genre prints beside a rune so a player knows what the
    /// drachma is buying before the first attempt.
    func projectedMainStat(atLevel target: Int) -> StatModifier {
        let clamped = max(0, min(maxLevel, target))
        let growth = clamped >= maxLevel ? 3.0 : 1.0 + (Double(clamped) / Double(maxLevel)) * 1.8
        return StatModifier(mainStat.kind, mainStat.value * growth)
    }

    /// The main stat one level up, for the power-up screen's "→".
    var nextMainStat: StatModifier? {
        guard !isMaxLevel else { return nil }
        var next = self
        next.level += 1
        return next.effectiveMainStat
    }

    /// A whetstone's bonus on the sub stat at `index`, or zero.
    func honedBonus(at index: Int) -> Double {
        honed?[index] ?? 0
    }

    /// The sub stats as they count: the roll plus any honing.
    var effectiveSubStats: [StatModifier] {
        subStats.enumerated().map { index, sub in
            StatModifier(sub.kind, sub.value + honedBonus(at: index))
        }
    }

    var allStats: [StatModifier] { [effectiveMainStat] + effectiveSubStats }

    /// The stone's bundle image, drawn by `tools/relic_art.py`: the one
    /// hexagon in the set's colour with the set's seal engraved. Every slot
    /// wears the same stone — the first cut gave each slot its own
    /// silhouette and the owner called the six shapes weird (2026-09-12) —
    /// so the slot is a number badge (`RelicIcon.showsSlot`) or the socket's
    /// place on the ring.
    var stoneImageName: String { "relic_\(set.rawValue)" }

    /// The quality rim, a template the app tints with the quality's metal.
    static let rimImageName = "relic_rim"

    /// A slot's main stat in a word, for the chips and captions that name a
    /// slot: the odd slots are fixed, the even ones the decision.
    static func slotLabel(forSlot slot: Int) -> String {
        switch slot {
        case 1: return "ATK"
        case 3: return "DEF"
        case 5: return "HP"
        default: return "Free"
        }
    }

    /// "Legend Fury Relic": the name every list, card and drop uses.
    var displayName: String { "\(resolvedQuality.displayName) \(set.displayName) Relic" }

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
