import Foundation

/// One resolved strike, before it is applied to the target.
struct HitResult: Sendable {
    var rawDamage: Double
    var isCritical: Bool
    var isGlancing: Bool
    var matchup: Element.Matchup
}

/// The single place damage is computed.
///
/// The shape is the genre standard: a multiplier off one stat, softened by a
/// defence curve, then multiplied by the element matchup and the crit roll.
/// Keeping it in one pure function means the tooltip in the collection screen
/// and the number that lands in battle can never disagree.
enum DamageCalculator {

    /// Defence softening constant. Higher makes DEF weaker across the board.
    static let defenseConstant: Double = 1000
    static let defenseWeight: Double = 3.5

    /// Damage taken by a glancing hit, and the crit floor it forces.
    static let glancingMultiplier: Double = 0.70

    /// Random spread applied to every hit, so identical strikes are not identical.
    static let variance: ClosedRange<Double> = 0.95...1.05

    static func mitigation(defense: Double, ignore: Double) -> Double {
        let effective = max(0, defense * (1 - max(0, min(1, ignore))))
        return defenseConstant / (defenseConstant + effective * defenseWeight)
    }

    static func resolve(
        attacker: Combatant,
        defender: Combatant,
        spec: DamageSpec,
        rng: inout SeededRandom
    ) -> HitResult {
        let attackerStats = attacker.currentStats
        let defenderStats = defender.currentStats
        let matchup = attacker.element.matchup(against: defender.element)

        // Base: the scaling stat times the skill multiplier, plus conditional bonuses.
        var base = attacker.scalingValue(for: spec.scaling) * spec.multiplier
        if spec.bonusPerTargetDebuff > 0 {
            base *= 1 + spec.bonusPerTargetDebuff * Double(defender.debuffCount)
        }
        if spec.bonusPerMissingHealth > 0 {
            base *= 1 + spec.bonusPerMissingHealth * defender.missingHealthFraction
        }

        // Defence.
        base *= mitigation(defense: defenderStats.def, ignore: spec.defenseIgnore)

        // Element.
        base *= matchup.damageMultiplier

        // Glancing is rolled first: a glancing hit can never crit.
        var isGlancing = false
        if matchup.glancingChance > 0, rng.chance(matchup.glancingChance) {
            isGlancing = true
        }
        if attacker.has(.glancing), rng.chance(0.50) {
            isGlancing = true
        }

        var isCritical = false
        if !isGlancing {
            if spec.alwaysCrits {
                isCritical = true
            } else {
                let rate = attackerStats.critRate + matchup.bonusCritRate
                isCritical = rng.chance(rate)
            }
        }

        if isCritical {
            base *= 1 + attackerStats.critDamage
        } else if isGlancing {
            base *= glancingMultiplier
        }

        base *= attacker.outgoingDamageMultiplier
        base *= defender.incomingDamageMultiplier
        base *= rng.double(in: variance)

        return HitResult(
            rawDamage: max(1, base),
            isCritical: isCritical,
            isGlancing: isGlancing,
            matchup: matchup
        )
    }

    /// Whether a debuff lands. Skill chance first, then a resistance check that
    /// accuracy eats into. A 15% floor means nothing is ever fully immune by stats.
    static func landsDebuff(
        chance: Double,
        attacker: Combatant,
        defender: Combatant,
        rng: inout SeededRandom
    ) -> Bool {
        guard rng.chance(chance) else { return false }
        if defender.has(.immunity) { return false }
        let resistance = max(0.15, defender.currentStats.resistance - attacker.currentStats.accuracy)
        return !rng.chance(resistance)
    }

    /// Preview damage for the collection screen: no RNG, average roll, neutral
    /// element, no crit. Gives players a stable number to compare builds with.
    static func previewDamage(
        attackStat: Double,
        spec: DamageSpec,
        againstDefense: Double = 800
    ) -> Double {
        let base = attackStat * spec.multiplier * Double(max(1, spec.hits))
        return (base * mitigation(defense: againstDefense, ignore: spec.defenseIgnore)).rounded()
    }
}
