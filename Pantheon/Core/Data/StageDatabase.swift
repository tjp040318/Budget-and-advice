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
        olympusI,
        generatedChapter(
            id: "olympus_2",
            pantheon: .greek,
            name: "The Long Descent",
            summary: "Something climbed out of Tartarus while the gods were arguing.",
            startingLevel: 12,
            stageCount: 10,
            environment: .tartarusGate,
            roster: ["shade_tartarus", "harpy", "cerberus", "bronze_automaton"],
            bossID: "cerberus"
        )
    ]

    static func chapter(_ id: String) -> Chapter? { chapters.first(where: { $0.id == id }) }

    static func stage(_ id: String) -> Stage? {
        chapters.lazy.flatMap(\.stages).first(where: { $0.id == id })
    }

    static var allStages: [Stage] { chapters.flatMap(\.stages) }

    // MARK: - Chapter 1, hand-authored

    private static let olympusI = Chapter(
        id: "olympus_1",
        pantheon: .greek,
        name: "The Sky Answers",
        summary: """
        The circle is lit and something enormous is listening. Take the mountain \
        path, find out what has been let loose on it, and hold the summit.
        """,
        stages: [
            Stage(
                id: "olympus_1_1",
                chapterID: "olympus_1",
                index: 1,
                name: "The Broken Path",
                energyCost: 3,
                recommendedPower: 1_200,
                enemies: [
                    EnemySpawn(blueprintID: "shade_tartarus", level: 3, stars: 2),
                    EnemySpawn(blueprintID: "shade_tartarus", level: 3, stars: 2)
                ],
                rewards: StageRewards(
                    drachma: 700, playerExperience: 30, unitExperience: 240,
                    relicChance: 0.35, relicGrade: 2,
                    firstClearDivinity: 30
                ),
                environment: .olympusPeak
            ),
            Stage(
                id: "olympus_1_2",
                chapterID: "olympus_1",
                index: 2,
                name: "Wind Off the Ridge",
                energyCost: 3,
                recommendedPower: 1_800,
                enemies: [
                    EnemySpawn(blueprintID: "harpy", level: 5, stars: 3),
                    EnemySpawn(blueprintID: "shade_tartarus", level: 5, stars: 2),
                    EnemySpawn(blueprintID: "harpy", level: 5, stars: 3)
                ],
                rewards: StageRewards(
                    drachma: 950, playerExperience: 40, unitExperience: 330,
                    relicChance: 0.40, relicGrade: 2,
                    scrollChances: [ScrollType.mystical.rawValue: 0.20],
                    firstClearDivinity: 30
                ),
                environment: .olympusPeak
            ),
            Stage(
                id: "olympus_1_3",
                chapterID: "olympus_1",
                index: 3,
                name: "The Dry Spring",
                energyCost: 4,
                recommendedPower: 2_600,
                enemies: [
                    EnemySpawn(blueprintID: "naiad", level: 8, stars: 3),
                    EnemySpawn(blueprintID: "harpy", level: 8, stars: 3),
                    EnemySpawn(blueprintID: "naiad", level: 8, stars: 3)
                ],
                rewards: StageRewards(
                    drachma: 1_200, playerExperience: 55, unitExperience: 430,
                    relicChance: 0.45, relicGrade: 3,
                    essenceChances: ["essence_magic_low": 0.35],
                    firstClearDivinity: 30
                ),
                environment: .marbleCourt
            ),
            Stage(
                id: "olympus_1_4",
                chapterID: "olympus_1",
                index: 4,
                name: "Forge-Sentinels",
                energyCost: 4,
                recommendedPower: 3_400,
                enemies: [
                    EnemySpawn(blueprintID: "bronze_automaton", level: 11, stars: 3),
                    EnemySpawn(blueprintID: "bronze_automaton", level: 11, stars: 3),
                    EnemySpawn(blueprintID: "harpy", level: 11, stars: 3)
                ],
                rewards: StageRewards(
                    drachma: 1_500, playerExperience: 70, unitExperience: 540,
                    relicChance: 0.50, relicGrade: 3,
                    essenceChances: ["essence_magic_low": 0.35, "essence_radiance_low": 0.20],
                    firstClearDivinity: 30
                ),
                environment: .marbleCourt
            ),
            Stage(
                id: "olympus_1_5",
                chapterID: "olympus_1",
                index: 5,
                name: "The Summit Holds",
                energyCost: 6,
                recommendedPower: 5_200,
                enemies: [
                    EnemySpawn(blueprintID: "bronze_automaton", level: 15, stars: 3),
                    EnemySpawn(blueprintID: "cerberus", level: 15, stars: 4),
                    EnemySpawn(blueprintID: "menoetius", level: 16, stars: 5, statMultiplier: 1.25),
                    EnemySpawn(blueprintID: "cerberus", level: 15, stars: 4)
                ],
                rewards: StageRewards(
                    drachma: 3_000, playerExperience: 140, unitExperience: 900,
                    relicChance: 1.0, relicGrade: 4,
                    essenceChances: [
                        "essence_magic_mid": 0.50,
                        "essence_radiance_mid": 0.35
                    ],
                    scrollChances: [ScrollType.pantheonic.rawValue: 0.50],
                    firstClearDivinity: 100
                ),
                environment: .stormAltar,
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
