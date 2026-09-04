import Foundation

/// The immutable definition of a summonable character.
///
/// Blueprints are content, not state: they live in `UnitDatabase` and are never
/// mutated. A player's copy of Anubis is a `Unit` pointing at this by `id`.
struct UnitBlueprint: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    /// Sub-title on the card: "God of Sky and Thunder".
    var epithet: String
    var pantheon: Pantheon
    var element: Element
    var archetype: Archetype
    var role: CombatRole

    /// Star grade as summoned. Awakening and evolution raise the effective grade
    /// but never this number — it is what the gacha rolls against.
    var naturalStars: Int

    /// Stats at level 1 of the unit's natural star grade.
    var baseStats: Stats
    /// Stats gained per level. Multiplied by the star grade in `ProgressionService`.
    var growthPerLevel: Stats

    var skills: [Skill]
    var leaderSkill: LeaderSkill?

    /// Second-form name and stat/skill bonuses unlocked by awakening.
    var awakening: Awakening?

    var model: ModelSpec
    var lore: String

    /// Skills at the given levels, with awakening bonuses folded in.
    ///
    /// Skill slots stay stable: a locked awakening skill is dropped from the end
    /// of the array, never from the middle, so slot 0 is always the basic attack
    /// and the battle HUD can index straight into the result.
    func resolvedSkills(levels: [Int], awakened: Bool) -> [Skill] {
        var resolved = skills.enumerated().map { index, skill -> Skill in
            let level = index < levels.count ? levels[index] : 1
            return skill.leveled(to: level)
        }
        if awakened, let awakening {
            awakening.applySkillChanges(to: &resolved)
        } else {
            resolved.removeAll { $0.requiresAwakening }
        }
        return resolved
    }

    var activeSkills: [Skill] { skills.filter { !$0.isPassive } }
    var passiveSkill: Skill? { skills.first(where: { $0.isPassive }) }
}

/// The awakened form of a unit: a new name, a stat bump, and usually one skill
/// change or an unlocked passive.
struct Awakening: Codable, Equatable, Sendable {
    var awakenedName: String
    var bonusDescription: String
    var statBonus: Stats
    /// Skill id -> replacement skill. Used to add a stun, drop a cooldown, or
    /// unlock the passive entirely.
    var skillOverrides: [String: Skill]
    /// Awakening materials required, by essence id, with counts.
    var essenceCost: [String: Int]

    func applySkillChanges(to skills: inout [Skill]) {
        for index in skills.indices {
            if let replacement = skillOverrides[skills[index].id] {
                // Preserve the level-derived multipliers already applied, then
                // layer the awakened definition's changes on top.
                var merged = replacement
                merged.slot = skills[index].slot
                skills[index] = merged
            }
        }
    }
}
