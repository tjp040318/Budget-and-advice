import Foundation

/// Turns saved `Unit`s into fightable `ResolvedUnit`s, and owns every rule about
/// levelling, evolving, awakening and skilling up.
///
/// Nothing else in the game is allowed to compute a final stat. If a number
/// shows up in the UI and in battle, it came from `resolve(_:in:)`.
enum ProgressionService {

    // MARK: - Scaling curves

    /// Stat multiplier by star grade. 1.35 per star is the whole curve: a 6★ is
    /// 4.48x a 1★, which is what makes a farmed 3★ genuinely usable and a 6★
    /// genuinely worth the cost.
    static func gradeMultiplier(stars: Int) -> Double {
        pow(1.35, Double(max(1, stars) - 1))
    }

    /// Stat multiplier by level. Linear so the level-up screen reads honestly.
    static func levelMultiplier(level: Int) -> Double {
        1 + 0.075 * Double(max(1, level) - 1)
    }

    static func maxLevel(stars: Int) -> Int { stars * 10 + 5 }

    /// XP needed to go from `level` to `level + 1`.
    static func experienceForNextLevel(level: Int, stars: Int) -> Int {
        let base = 120 + level * 95
        return Int(Double(base) * (1 + Double(stars) * 0.22))
    }

    // MARK: - Resolution

    /// Base stats before any equipment: grade, level and awakening only.
    static func baseStats(for unit: Unit, blueprint: UnitBlueprint) -> Stats {
        let grade = gradeMultiplier(stars: unit.stars)
        let levelScale = levelMultiplier(level: unit.level)
        let scale = grade * levelScale

        var stats = Stats(
            hp: blueprint.baseStats.hp * scale,
            atk: blueprint.baseStats.atk * scale,
            def: blueprint.baseStats.def * scale,
            // Speed and the rate stats do not scale. That is what makes a fast
            // 3★ support relevant next to a slow 5★ god.
            spd: blueprint.baseStats.spd,
            critRate: blueprint.baseStats.critRate,
            critDamage: blueprint.baseStats.critDamage,
            accuracy: blueprint.baseStats.accuracy,
            resistance: blueprint.baseStats.resistance
        )

        if unit.isAwakened, let awakening = blueprint.awakening {
            stats += awakening.statBonus
        }
        return stats
    }

    /// Joins a unit to its blueprint and equipped relics and computes finals.
    static func resolve(_ unit: Unit, relics allRelics: [Relic]) -> ResolvedUnit? {
        guard let blueprint = UnitDatabase.blueprint(unit.blueprintID) else { return nil }
        let equipped = unit.equippedRelics.values.compactMap { id in
            allRelics.first(where: { $0.id == id })
        }
        return resolve(unit, blueprint: blueprint, equipped: equipped)
    }

    static func resolve(_ unit: Unit, blueprint: UnitBlueprint, equipped: [Relic]) -> ResolvedUnit {
        let base = baseStats(for: unit, blueprint: blueprint)
        var flat = Stats.zero
        var percent: [StatKind: Double] = [:]

        // 1. Relic main stats and sub stats.
        for relic in equipped {
            for modifier in relic.allStats {
                accumulate(modifier, flat: &flat, percent: &percent, speedIsPercent: false)
            }
        }

        // 2. Completed set bonuses, once per completed set.
        var tally: [RelicSet: Int] = [:]
        for relic in equipped { tally[relic.set, default: 0] += 1 }
        for (set, count) in tally {
            let completions = count / set.piecesRequired
            guard completions > 0, let bonus = set.statBonus else { continue }
            for _ in 0..<completions {
                accumulate(bonus, flat: &flat, percent: &percent, speedIsPercent: true)
            }
        }

        // 3. Percentages always apply to the *base*, never to relic flats. That
        //    keeps "+35% ATK" meaning the same thing on every build.
        var final = base
        final.hp += flat.hp + base.hp * (percent[.hpPercent] ?? 0)
        final.atk += flat.atk + base.atk * (percent[.atkPercent] ?? 0)
        final.def += flat.def + base.def * (percent[.defPercent] ?? 0)
        final.spd += flat.spd + base.spd * (percent[.spd] ?? 0)
        final.critRate += flat.critRate
        final.critDamage += flat.critDamage
        final.accuracy += flat.accuracy
        final.resistance += flat.resistance

        let skills = blueprint.resolvedSkills(levels: unit.skillLevels, awakened: unit.isAwakened)

        return ResolvedUnit(
            unit: unit,
            blueprint: blueprint,
            relics: equipped,
            stats: final.clamped(),
            skills: skills
        )
    }

    private static func accumulate(
        _ modifier: StatModifier,
        flat: inout Stats,
        percent: inout [StatKind: Double],
        speedIsPercent: Bool
    ) {
        switch modifier.kind {
        case .hpFlat: flat.hp += modifier.value
        case .atkFlat: flat.atk += modifier.value
        case .defFlat: flat.def += modifier.value
        case .hpPercent, .atkPercent, .defPercent:
            percent[modifier.kind, default: 0] += modifier.value
        case .spd:
            if speedIsPercent {
                percent[.spd, default: 0] += modifier.value
            } else {
                flat.spd += modifier.value
            }
        case .critRate: flat.critRate += modifier.value
        case .critDamage: flat.critDamage += modifier.value
        case .accuracy: flat.accuracy += modifier.value
        case .resistance: flat.resistance += modifier.value
        }
    }

    // MARK: - Levelling

    /// Feeds experience into a unit, levelling as far as the grade allows.
    /// Returns the number of levels gained.
    @discardableResult
    static func grantExperience(_ amount: Int, to unit: inout Unit) -> Int {
        guard amount > 0 else { return 0 }
        let cap = maxLevel(stars: unit.stars)
        guard unit.level < cap else { return 0 }

        unit.experience += amount
        var gained = 0
        while unit.level < cap {
            let needed = experienceForNextLevel(level: unit.level, stars: unit.stars)
            guard unit.experience >= needed else { break }
            unit.experience -= needed
            unit.level += 1
            gained += 1
        }
        if unit.level >= cap { unit.experience = 0 }
        return gained
    }

    /// XP a unit is worth when fed to another unit.
    static func feedValue(of unit: Unit) -> Int {
        let gradeWorth = Int(pow(2.1, Double(unit.stars)) * 130)
        let levelWorth = (unit.level - 1) * 60 * unit.stars
        return gradeWorth + levelWorth
    }

    // MARK: - Evolution

    /// Cost in same-grade fodder units to evolve. Classic ladder: one per star.
    static func evolutionFodderRequired(currentStars: Int) -> Int { currentStars }

    static func drachmaCostToEvolve(currentStars: Int) -> Int {
        [0, 3_000, 8_000, 20_000, 60_000, 150_000][min(currentStars, 5)]
    }

    enum EvolutionError: Error, LocalizedError {
        case notMaxLevel
        case alreadyMaxGrade
        case notEnoughFodder(needed: Int, have: Int)
        case notEnoughDrachma(needed: Int)

        var errorDescription: String? {
            switch self {
            case .notMaxLevel: return "This unit must be at max level to evolve."
            case .alreadyMaxGrade: return "This unit is already 6★."
            case .notEnoughFodder(let needed, let have):
                return "Evolution needs \(needed) fodder units of the same grade — you selected \(have)."
            case .notEnoughDrachma(let needed):
                return "Evolution costs \(needed) drachma."
            }
        }
    }

    /// Raises the star grade, resetting to level 1 as the genre expects.
    static func evolve(_ unit: inout Unit, fodder: [Unit], wallet: inout Wallet) throws {
        guard unit.stars < 6 else { throw EvolutionError.alreadyMaxGrade }
        guard unit.level >= maxLevel(stars: unit.stars) else { throw EvolutionError.notMaxLevel }

        let needed = evolutionFodderRequired(currentStars: unit.stars)
        let valid = fodder.filter { $0.stars == unit.stars && $0.id != unit.id && !$0.isLocked }
        guard valid.count >= needed else {
            throw EvolutionError.notEnoughFodder(needed: needed, have: valid.count)
        }

        let cost = drachmaCostToEvolve(currentStars: unit.stars)
        guard wallet.drachma >= cost else { throw EvolutionError.notEnoughDrachma(needed: cost) }

        wallet.drachma -= cost
        unit.stars += 1
        unit.level = 1
        unit.experience = 0
    }

    // MARK: - Awakening

    enum AwakeningError: Error, LocalizedError {
        case notAwakenable
        case alreadyAwakened
        case missingEssence(id: String, needed: Int, have: Int)

        var errorDescription: String? {
            switch self {
            case .notAwakenable: return "This unit has no awakened form."
            case .alreadyAwakened: return "This unit is already awakened."
            case .missingEssence(let id, let needed, let have):
                return "Needs \(needed)x \(EssenceCatalog.name(for: id)) — you have \(have)."
            }
        }
    }

    static func awaken(_ unit: inout Unit, essences: inout [String: Int]) throws {
        guard let blueprint = UnitDatabase.blueprint(unit.blueprintID),
              let awakening = blueprint.awakening else { throw AwakeningError.notAwakenable }
        guard !unit.isAwakened else { throw AwakeningError.alreadyAwakened }

        for (id, needed) in awakening.essenceCost {
            let have = essences[id] ?? 0
            guard have >= needed else {
                throw AwakeningError.missingEssence(id: id, needed: needed, have: have)
            }
        }
        for (id, needed) in awakening.essenceCost {
            essences[id, default: 0] -= needed
        }
        unit.isAwakened = true
        // Awakening can add a skill slot (the passive); keep levels in step.
        while unit.skillLevels.count < blueprint.skills.count {
            unit.skillLevels.append(1)
        }
    }

    // MARK: - Skill-ups

    /// Feeding a duplicate raises one random un-maxed skill.
    @discardableResult
    static func applySkillUp(to unit: inout Unit, using rng: inout SeededRandom) -> Int? {
        guard let blueprint = UnitDatabase.blueprint(unit.blueprintID) else { return nil }
        while unit.skillLevels.count < blueprint.skills.count { unit.skillLevels.append(1) }

        let upgradable = blueprint.skills.indices.filter { index in
            let maxLevel = blueprint.skills[index].maxSkillLevel
            return unit.skillLevels[index] < maxLevel
        }
        guard let choice = rng.pickMutating(upgradable) else { return nil }
        unit.skillLevels[choice] += 1
        return choice
    }
}

/// Names for awakening materials. Kept separate so the awakening screen can list
/// requirements without the blueprint knowing about UI strings.
enum EssenceCatalog {
    static let names: [String: String] = [
        "essence_radiance_low": "Low Radiance Essence",
        "essence_radiance_mid": "Mid Radiance Essence",
        "essence_radiance_high": "High Radiance Essence",
        "essence_umbra_low": "Low Umbra Essence",
        "essence_umbra_mid": "Mid Umbra Essence",
        "essence_umbra_high": "High Umbra Essence",
        "essence_ember_mid": "Mid Ember Essence",
        "essence_tide_mid": "Mid Tide Essence",
        "essence_gale_mid": "Mid Gale Essence",
        "essence_magic_low": "Low Magic Essence",
        "essence_magic_mid": "Mid Magic Essence",
        "essence_magic_high": "High Magic Essence"
    ]

    static func name(for id: String) -> String { names[id] ?? id }
}
