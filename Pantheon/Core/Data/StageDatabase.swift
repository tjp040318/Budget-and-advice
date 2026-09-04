import Foundation

/// One enemy placement in a stage.
struct EnemySpawn: Codable, Equatable, Sendable {
    var blueprintID: String
    var level: Int
    var stars: Int
    /// Flat multiplier on the spawn's final stats. Bosses use it instead of
    /// absurd levels, so the numbers on screen stay believable.
    var statMultiplier: Double = 1.0
    var awakened: Bool = false
}

/// What clearing a stage pays out.
struct StageRewards: Codable, Equatable, Sendable {
    var drachma: Int
    var playerExperience: Int
    var unitExperience: Int
    /// Chance of a relic drop and the grade it rolls at.
    var relicChance: Double = 0
    var relicGrade: Int = 3
    /// Essence id to chance of dropping.
    var essenceChances: [String: Double] = [:]
    /// Scroll drops by type and chance.
    var scrollChances: [String: Double] = [:]
    /// First-clear only.
    var firstClearDivinity: Int = 0
}

struct Stage: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var chapterID: String
    /// 1-based position within the chapter.
    var index: Int
    var name: String
    var energyCost: Int
    var recommendedPower: Int
    var enemies: [EnemySpawn]
    var rewards: StageRewards
    var environment: BattleEnvironment
    var isBoss: Bool = false
}

struct Chapter: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var pantheon: Pantheon
    var name: String
    var summary: String
    var stages: [Stage]

    var realmName: String { pantheon.realmName }
}

/// The PvE content.
///
/// Chapter 1 is authored by hand because it is the tutorial and the difficulty
/// curve there is a design decision, not a formula. Later chapters are generated
/// from a curve so that adding a pantheon is a table entry rather than 40 stages
/// of typing — see `generatedChapter(_:)`.
enum StageDatabase {

    static let chapters: [Chapter] = [
        duatI,
        generatedChapter(
            id: "duat_2",
            pantheon: .egyptian,
            name: "The Gates of the West",
            summary: "Seven gates, and a name to be spoken at each one. Something has been eating the names.",
            startingLevel: 30,
            stageCount: 10,
            environment: .hallOfTwoTruths,
            roster: ["shabti", "serpopard", "sun_scarab", "sandstone_sentinel", "ammit"],
            bossID: "ammit"
        )
    ]

    static func chapter(_ id: String) -> Chapter? { chapters.first(where: { $0.id == id }) }

    static func stage(_ id: String) -> Stage? {
        chapters.lazy.flatMap(\.stages).first(where: { $0.id == id })
    }

    static var allStages: [Stage] { chapters.flatMap(\.stages) }

    // MARK: - Chapter 1, hand-authored
    //
    // Every level, count and reward below came out of tools/balance.py, which
    // plays each stage a few hundred times against the team the player is
    // actually expected to have. The shape it enforces: each stage demands
    // exactly one more thing than the last — a second body, then a third, then
    // a fourth — and levels rise monotonically so the board reads honestly.
    //
    // Measured win rates, by team:
    //             1x lv1   2x lv15   3x lv25   4x lv35
    //   1-1        100%      100%      100%      100%
    //   1-2         23%      100%      100%      100%
    //   1-3          0%      100%      100%      100%
    //   1-4          0%        0%      100%      100%
    //   1-5          0%        0%        0%      100%

    private static let duatI = Chapter(
        id: "duat_1",
        pantheon: .egyptian,
        name: "The Weighing of the Heart",
        summary: """
        The hall is open and the scales are unattended. Something has come up \
        through the reed beds that was never weighed, and it is walking west \
        against the current of the dead.
        """,
        stages: [
            Stage(
                id: "duat_1_1",
                chapterID: "duat_1",
                index: 1,
                name: "The First Gate",
                energyCost: 3,
                recommendedPower: 400,
                enemies: [
                    EnemySpawn(blueprintID: "shabti", level: 5, stars: 2),
                    EnemySpawn(blueprintID: "shabti", level: 5, stars: 2)
                ],
                rewards: StageRewards(
                    drachma: 700, playerExperience: 30, unitExperience: 240,
                    relicChance: 0.35, relicGrade: 2,
                    firstClearDivinity: 30
                ),
                environment: .duatGate
            ),
            Stage(
                id: "duat_1_2",
                chapterID: "duat_1",
                index: 2,
                name: "Reed Fields",
                energyCost: 3,
                recommendedPower: 800,
                enemies: [
                    EnemySpawn(blueprintID: "shabti", level: 8, stars: 2),
                    EnemySpawn(blueprintID: "serpopard", level: 8, stars: 3)
                ],
                rewards: StageRewards(
                    drachma: 950, playerExperience: 40, unitExperience: 330,
                    relicChance: 0.40, relicGrade: 2,
                    scrollChances: [ScrollType.mystical.rawValue: 0.25],
                    firstClearDivinity: 30
                ),
                environment: .reedFields
            ),
            Stage(
                id: "duat_1_3",
                chapterID: "duat_1",
                index: 3,
                name: "Scarab Court",
                energyCost: 4,
                recommendedPower: 1_800,
                enemies: [
                    EnemySpawn(blueprintID: "serpopard", level: 14, stars: 3),
                    EnemySpawn(blueprintID: "sun_scarab", level: 14, stars: 3),
                    EnemySpawn(blueprintID: "shabti", level: 14, stars: 2)
                ],
                rewards: StageRewards(
                    drachma: 1_200, playerExperience: 55, unitExperience: 430,
                    relicChance: 0.45, relicGrade: 3,
                    essenceChances: ["essence_magic_low": 0.35],
                    firstClearDivinity: 30
                ),
                environment: .reedFields
            ),
            Stage(
                id: "duat_1_4",
                chapterID: "duat_1",
                index: 4,
                name: "Hall of Sentinels",
                energyCost: 4,
                recommendedPower: 3_600,
                enemies: [
                    EnemySpawn(blueprintID: "sandstone_sentinel", level: 20, stars: 3),
                    EnemySpawn(blueprintID: "serpopard", level: 20, stars: 3),
                    EnemySpawn(blueprintID: "sun_scarab", level: 20, stars: 3),
                    EnemySpawn(blueprintID: "ammit", level: 20, stars: 4)
                ],
                rewards: StageRewards(
                    drachma: 1_500, playerExperience: 70, unitExperience: 540,
                    relicChance: 0.50, relicGrade: 3,
                    essenceChances: ["essence_magic_low": 0.35, "essence_umbra_low": 0.20],
                    firstClearDivinity: 30
                ),
                environment: .hallOfTwoTruths
            ),
            Stage(
                id: "duat_1_5",
                chapterID: "duat_1",
                index: 5,
                name: "Coils of Apep",
                energyCost: 6,
                recommendedPower: 7_000,
                enemies: [
                    EnemySpawn(blueprintID: "sandstone_sentinel", level: 26, stars: 3),
                    EnemySpawn(blueprintID: "serpopard", level: 26, stars: 3),
                    EnemySpawn(blueprintID: "apep", level: 28, stars: 5, statMultiplier: 1.42),
                    EnemySpawn(blueprintID: "ammit", level: 26, stars: 4)
                ],
                rewards: StageRewards(
                    drachma: 3_000, playerExperience: 140, unitExperience: 900,
                    relicChance: 1.0, relicGrade: 4,
                    essenceChances: [
                        "essence_magic_mid": 0.50,
                        "essence_umbra_mid": 0.35
                    ],
                    scrollChances: [ScrollType.pantheonic.rawValue: 0.50],
                    firstClearDivinity: 100
                ),
                environment: .serpentDeep,
                isBoss: true
            )
        ]
    )

    // MARK: - Generated chapters

    /// Builds a chapter from a difficulty curve. Every stage after the first
    /// gains roughly 18% power, and the last one is a boss with a stat bump.
    static func generatedChapter(
        id: String,
        pantheon: Pantheon,
        name: String,
        summary: String,
        startingLevel: Int,
        stageCount: Int,
        environment: BattleEnvironment,
        roster: [String],
        bossID: String
    ) -> Chapter {
        var stages: [Stage] = []
        for index in 1...stageCount {
            let isBoss = index == stageCount
            let level = startingLevel + (index - 1) * 3
            let power = Int(Double(2_500) * pow(1.18, Double(index - 1)))

            var enemies: [EnemySpawn] = []
            let count = isBoss ? 4 : min(4, 2 + index / 3)
            for slot in 0..<count {
                // Rotate through the roster so consecutive stages are not
                // identical, and drop the boss into the last slot of a boss stage.
                let blueprintID = (isBoss && slot == count - 1)
                    ? bossID
                    : roster[(index + slot) % roster.count]
                let stars = UnitDatabase.blueprint(blueprintID)?.naturalStars ?? 3
                enemies.append(EnemySpawn(
                    blueprintID: blueprintID,
                    level: level,
                    stars: stars,
                    statMultiplier: isBoss && slot == count - 1 ? 1.4 : 1.0
                ))
            }

            stages.append(Stage(
                id: "\(id)_\(index)",
                chapterID: id,
                index: index,
                name: isBoss ? "\(name) — Confrontation" : "\(name) \(index)",
                energyCost: isBoss ? 6 : 4,
                recommendedPower: power,
                enemies: enemies,
                rewards: StageRewards(
                    drachma: 900 + index * 220,
                    playerExperience: 45 + index * 10,
                    unitExperience: 380 + index * 70,
                    relicChance: isBoss ? 1.0 : 0.45,
                    relicGrade: isBoss ? 4 : 3,
                    essenceChances: ["essence_magic_mid": isBoss ? 0.6 : 0.2],
                    scrollChances: isBoss ? [ScrollType.mystical.rawValue: 0.6] : [:],
                    firstClearDivinity: isBoss ? 60 : 20
                ),
                environment: environment,
                isBoss: isBoss
            ))
        }

        return Chapter(id: id, pantheon: pantheon, name: name, summary: summary, stages: stages)
    }

    /// Builds fightable units for a stage's enemy list.
    static func buildEnemies(for stage: Stage) -> [ResolvedUnit] {
        stage.enemies.compactMap { spawn in
            guard let blueprint = UnitDatabase.blueprint(spawn.blueprintID) else { return nil }
            var unit = Unit(blueprint: blueprint, level: spawn.level, stars: spawn.stars, awakened: spawn.awakened)
            unit.skillLevels = blueprint.skills.map { _ in max(1, spawn.level / 6) }
            var resolved = ProgressionService.resolve(unit, blueprint: blueprint, equipped: [])
            if spawn.statMultiplier != 1.0 {
                var stats = resolved.stats
                stats.hp *= spawn.statMultiplier
                stats.atk *= spawn.statMultiplier
                stats.def *= spawn.statMultiplier
                resolved.stats = stats.clamped()
            }
            return resolved
        }
    }
}
