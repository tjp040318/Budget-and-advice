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
    /// Raid mechanics this spawn fights with — a barrier, a guard it calls, an
    /// enrage clock, a rotating weakness. Nil everywhere else, which is what
    /// keeps every ordinary fight in the game exactly as it was.
    var raid: RaidBossProfile? = nil
}

/// What clearing a stage pays out.
struct StageRewards: Codable, Equatable, Sendable {
    var drachma: Int
    var playerExperience: Int
    var unitExperience: Int
    /// Chance of a relic drop and the grade it rolls at.
    var relicChance: Double = 0
    var relicGrade: Int = 3
    /// When set, a dropped relic is one of these sets: a dungeon's own.
    var relicSets: [RelicSet]? = nil
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
    /// Waves after the first, for a dungeon run that is one battle of
    /// several; empty for a stage that is one fight.
    var laterWaves: [[EnemySpawn]] = []
}

struct Chapter: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var pantheon: Pantheon
    var name: String
    var summary: String
    /// The story, shown once over the chapter's own painting the first time the
    /// player walks into it (`ChapterIntroCard` on the island). `summary` is the
    /// line the map carries every time; this is the longer version, about forty
    /// words, and it is the only place the campaign explains what is wrong.
    /// Empty means no card, which is what the Labyrinth's chapters get.
    var intro: String = ""
    /// What the chapter's boss says as its stage opens, in the same cut-in band
    /// an ultimate uses. One line — it plays over the fight starting, not
    /// instead of it.
    var bossLine: String = ""
    /// Who says it: the blueprint whose card and element the cut-in wears. The
    /// boss is not always the last spawn in the list (Apep is third of four in
    /// `duat_1_5`), so it is named here rather than guessed at.
    var bossBlueprintID: String = ""
    var stages: [Stage]

    var realmName: String { pantheon.realmName }
}

/// The campaign's three tiers of every chapter, the genre's way: Normal is
/// the authored chapter; Hard and Hell are the same stages a grade higher, a
/// few levels higher and under a flat stat multiplier, paying more and
/// dropping better relics. The owner: "normal --> hard --> god level (each
/// one gives you better quality relics/prizes) but gets harder."
///
/// A tier is DERIVED, never authored: `Stage.at(_:)` and `Chapter.at(_:)`
/// copy the Normal chapter and suffix every id (`duat_1_5@hard`,
/// `duat_1@hell`). Progress is a dictionary keyed by chapter id, so each
/// tier keeps its own high-water mark in the save with no new field, and
/// every lookup that starts from an id (`StageDatabase.stage`, `chapter`,
/// `CampaignService.isUnlocked`) reads the suffix back off it with
/// `split(_:)`. Hard opens when Normal's boss falls, Hell when Hard's does.
/// The curve is mirrored in `tools/balance.py` (`DIFFICULTIES`, `--tiers`);
/// change it in both.
enum CampaignDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal, hard, hell

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .hard: return "Hard"
        case .hell: return "Hell"
        }
    }

    /// The id suffix a tier's chapters and stages carry; Normal carries none.
    var suffix: String { self == .normal ? "" : "@\(rawValue)" }

    /// The tier that has to be cleared to its boss before this one opens.
    var easier: CampaignDifficulty? {
        switch self {
        case .normal: return nil
        case .hard: return .normal
        case .hell: return .hard
        }
    }

    /// Grades added to every spawn, capped at 6★.
    var starBonus: Int {
        switch self {
        case .normal: return 0
        case .hard: return 1
        case .hell: return 2
        }
    }

    /// On every spawn's level, capped at 60 so the numbers on screen stay in
    /// the range the player's own units use; the grade and the multiplier
    /// carry the rest of the difficulty.
    var levelScale: Double {
        switch self {
        case .normal: return 1.0
        case .hard: return 1.15
        case .hell: return 1.25
        }
    }

    /// Flat, on top of the level and the grade, multiplied into the spawn's
    /// own `statMultiplier` (a boss keeps its ×1.4 on top of this).
    var statScale: Double {
        switch self {
        case .normal: return 1.0
        case .hard: return 1.2
        case .hell: return 1.5
        }
    }

    /// Drachma, experience and the first clear's divinity.
    var rewardScale: Double {
        switch self {
        case .normal: return 1.0
        case .hard: return 1.7
        case .hell: return 2.6
        }
    }

    /// A relic from a Hard stage is at least 5★, from Hell 6★ — the whole
    /// reason to come back.
    var relicGradeFloor: Int {
        switch self {
        case .normal: return 0
        case .hard: return 5
        case .hell: return 6
        }
    }

    /// Every Hard stage drops a relic at least this often, every Hell stage
    /// more; a stage that already drops more often keeps its own chance,
    /// scaled.
    var relicChanceFloor: Double {
        switch self {
        case .normal: return 0
        case .hard: return 0.30
        case .hell: return 0.45
        }
    }

    /// On relic, essence and scroll chances.
    var dropScale: Double {
        switch self {
        case .normal: return 1.0
        case .hard: return 1.4
        case .hell: return 1.8
        }
    }

    var energyExtra: Int {
        switch self {
        case .normal: return 0
        case .hard: return 2
        case .hell: return 4
        }
    }

    /// On the recommended power the briefing shows.
    var powerScale: Double {
        switch self {
        case .normal: return 1.0
        case .hard: return 1.9
        case .hell: return 3.2
        }
    }

    var accentHex: String {
        switch self {
        case .normal: return "#4E8A72"
        case .hard: return "#C8425A"
        case .hell: return "#9B6BFF"
        }
    }

    var glyph: String {
        switch self {
        case .normal: return "leaf.fill"
        case .hard: return "flame.fill"
        case .hell: return "bolt.fill"
        }
    }

    /// The Normal id and the tier an id carries.
    static func split(_ id: String) -> (base: String, difficulty: CampaignDifficulty) {
        for tier in allCases where tier != .normal && id.hasSuffix(tier.suffix) {
            return (String(id.dropLast(tier.suffix.count)), tier)
        }
        return (id, .normal)
    }

    func scale(_ spawn: EnemySpawn) -> EnemySpawn {
        guard self != .normal else { return spawn }
        var copy = spawn
        copy.stars = min(6, spawn.stars + starBonus)
        copy.level = min(60, Int((Double(spawn.level) * levelScale).rounded()))
        copy.statMultiplier = spawn.statMultiplier * statScale
        return copy
    }

    func scale(_ rewards: StageRewards) -> StageRewards {
        guard self != .normal else { return rewards }
        var copy = rewards
        copy.drachma = Int(Double(rewards.drachma) * rewardScale)
        copy.playerExperience = Int(Double(rewards.playerExperience) * rewardScale)
        copy.unitExperience = Int(Double(rewards.unitExperience) * rewardScale)
        copy.relicChance = min(1, max(relicChanceFloor, rewards.relicChance * dropScale))
        copy.relicGrade = max(rewards.relicGrade, relicGradeFloor)
        copy.essenceChances = rewards.essenceChances.mapValues { min(1, $0 * dropScale) }
        copy.scrollChances = rewards.scrollChances.mapValues { min(1, $0 * dropScale) }
        copy.firstClearDivinity = Int(Double(rewards.firstClearDivinity) * rewardScale)
        return copy
    }
}

extension Stage {
    /// The tier this stage is, read off its id.
    var difficulty: CampaignDifficulty { CampaignDifficulty.split(id).difficulty }

    /// This stage at a tier. Only a Normal stage is scaled; a stage already
    /// at a tier is handed back as it is, so nothing can be scaled twice.
    func at(_ tier: CampaignDifficulty) -> Stage {
        guard tier != .normal, difficulty == .normal else { return self }
        var copy = self
        copy.id = id + tier.suffix
        copy.chapterID = chapterID + tier.suffix
        copy.name = "\(name) · \(tier.displayName)"
        copy.energyCost = energyCost + tier.energyExtra
        copy.recommendedPower = Int(Double(recommendedPower) * tier.powerScale)
        copy.enemies = enemies.map { tier.scale($0) }
        copy.laterWaves = laterWaves.map { wave in wave.map { tier.scale($0) } }
        copy.rewards = tier.scale(rewards)
        return copy
    }
}

extension Chapter {
    var difficulty: CampaignDifficulty { CampaignDifficulty.split(id).difficulty }

    /// This chapter at a tier: the same road, every stage scaled, no intro
    /// card (the story was told at Normal).
    func at(_ tier: CampaignDifficulty) -> Chapter {
        guard tier != .normal, difficulty == .normal else { return self }
        var copy = self
        copy.id = id + tier.suffix
        copy.intro = ""
        copy.stages = stages.map { $0.at(tier) }
        return copy
    }
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
            intro: """
            Each gate opens to its own name and to nothing else, and the names \
            are written down in one place only. Somebody has been at that scroll \
            with their teeth. Four gates have gone quiet, and the guides have \
            stopped walking the western road at all.
            """,
            bossLine: "Say your name. You cannot — I ate it at the fourth gate, and I am still hungry.",
            startingLevel: 30,
            stageCount: 10,
            environment: .hallOfTwoTruths,
            roster: ["shabti", "serpopard", "sun_scarab", "sandstone_sentinel", "ammit"],
            bossID: "ammit"
        ),
        // Greece: three chapters up the mountain, along the coast and into
        // the marsh, each with its own creatures and a boss at the end.
        generatedChapter(
            id: "olympus_1",
            pantheon: .greek,
            name: "The Gate of Olympus",
            summary: "The mountain's gate stands open and unguarded. What came down the steps was not sent by the gods.",
            intro: """
            The gate on the mountain has stood open a whole season and nobody \
            above has come down to shut it. What walks out of it at night comes \
            from the cellars under the throne room, where the gods put the things \
            they could not bring themselves to kill.
            """,
            bossLine: "I forged the bolt that put them on that mountain. They gave me a cellar for it.",
            startingLevel: 30,
            stageCount: 10,
            environment: .olympusGate,
            roster: ["enemy_amazon", "enemy_cyclops", "enemy_minotaur", "enemy_medusa"],
            bossID: "enemy_cyclops",
            levelStep: 2,
            powerScale: 2.2,
            enemyStars: 4,
            difficulty: 1.0
        ),
        generatedChapter(
            id: "olympus_2",
            pantheon: .greek,
            name: "The Aegean Cliffs",
            summary: "Every ship that rounds the cape is found on the rocks by morning, and the crews are not.",
            intro: """
            Eleven ships this year, all on the same reef, all with the sail still \
            set and the steering oar lashed straight. There are no bodies in the \
            water and none on the sand. The wreckers who work this coast have \
            moved inland and will not say why.
            """,
            bossLine: "Look at me. They all do, once.",
            startingLevel: 34,
            stageCount: 10,
            environment: .aegeanCliffs,
            roster: ["enemy_medusa", "enemy_amazon", "enemy_minotaur", "enemy_cyclops"],
            bossID: "enemy_medusa",
            levelStep: 2,
            powerScale: 3.2,
            enemyStars: 4,
            difficulty: 1.25
        ),
        generatedChapter(
            id: "olympus_3",
            pantheon: .greek,
            name: "The Marsh of Lerna",
            summary: "Heracles cut the heads off once. The marsh has had a long time to grow them back.",
            intro: """
            Heracles burned the stumps so the heads could not come back, and for \
            a few hundred years that held. The marsh has been patient since. The \
            cattle stopped going missing last spring, which the villages took for \
            good news until they counted the cattle.
            """,
            bossLine: "He came with a torch and a nephew to carry it. What have you brought?",
            startingLevel: 38,
            stageCount: 10,
            environment: .lernaMarsh,
            roster: ["enemy_minotaur", "enemy_medusa", "enemy_cyclops", "enemy_amazon"],
            bossID: "boss_hydra",
            levelStep: 2,
            powerScale: 4.4,
            enemyStars: 4,
            difficulty: 1.5
        ),
        // The Norse realms: the fjord road, the roots of the tree and the
        // giants' hall.
        generatedChapter(
            id: "yggdrasil_1",
            pantheon: .norse,
            name: "The Midgard Fjord",
            summary: "The longships have stopped coming home. Something on the fjord road is choosing the slain before the valkyries can.",
            intro: """
            Six longships out and none back, and the fjord has given up nothing — \
            no oars, no bodies, no wreck on the shingle. The valkyries still come \
            down for the slain along this water. They are arriving to find the \
            slain already taken.
            """,
            bossLine: "The choosers were slow. I have been picking the dead myself since midwinter.",
            startingLevel: 40,
            stageCount: 10,
            environment: .midgardFjord,
            roster: ["enemy_draugr", "enemy_berserker", "enemy_valkyrie", "enemy_frost_troll"],
            bossID: "enemy_berserker",
            levelStep: 2,
            powerScale: 6.0,
            enemyStars: 5,
            difficulty: 1.2
        ),
        generatedChapter(
            id: "yggdrasil_2",
            pantheon: .norse,
            name: "The Roots of Yggdrasil",
            summary: "Below the tree, where the serpent gnaws, the barrow-dead are climbing toward the light.",
            intro: """
            The serpent has gnawed this root since before there were seasons and \
            the wood has gone soft all the way through. What was buried under it \
            finds the way up easy now, and climbs toward the light in a steady \
            line, all night, without hurrying.
            """,
            bossLine: "No sun has come down here in a hundred winters. Do not bring one now.",
            startingLevel: 44,
            stageCount: 10,
            environment: .yggdrasilRoots,
            roster: ["enemy_valkyrie", "enemy_frost_troll", "enemy_draugr", "enemy_berserker"],
            bossID: "enemy_frost_troll",
            levelStep: 2,
            powerScale: 8.0,
            enemyStars: 5,
            difficulty: 1.45
        ),
        generatedChapter(
            id: "yggdrasil_3",
            pantheon: .norse,
            name: "The Hall of Jötunheim",
            summary: "The giants have crowned a king under the ice, and he has sent for the hammer.",
            intro: """
            The giants went a long age without a king. They have dug the last one \
            out from under the glacier and put the crown back on him, and his \
            first order was a demand for the hammer that killed him. Nothing has \
            come back from the hall that was asked.
            """,
            bossLine: "Send the hammer, or send the one who carries it. Both arrive in pieces.",
            startingLevel: 48,
            stageCount: 10,
            environment: .jotunheimHall,
            roster: ["enemy_frost_troll", "enemy_draugr", "enemy_berserker", "enemy_valkyrie"],
            bossID: "boss_jotunn",
            levelStep: 2,
            powerScale: 10.5,
            enemyStars: 5,
            difficulty: 1.7
        )
    ]

    /// By id, at whichever tier the id carries.
    static func chapter(_ id: String) -> Chapter? {
        let (base, tier) = CampaignDifficulty.split(id)
        return chapters.first(where: { $0.id == base })?.at(tier)
    }

    static func stage(_ id: String) -> Stage? {
        let (base, tier) = CampaignDifficulty.split(id)
        return allStages.first(where: { $0.id == base })?.at(tier)
    }

    /// Every fightable stage: the chapters', the Halls of Essence's floors,
    /// the Labyrinth's levels and the raids.
    static var allStages: [Stage] {
        chapters.flatMap(\.stages) + DungeonDatabase.allFloors + DungeonDatabase.allLevels + raidStages
    }

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
        intro: """
        The scales in the Hall of Two Truths have stood untended for nine days. \
        Nothing has been weighed, so nothing has been let through, and the dead \
        are stacking up along the reed road like grain sacks at a shut gate. \
        Someone has to go and see who is at the far end of it.
        """,
        bossLine: "The sun comes down this hole every night. It has never once climbed out alone.",
        bossBlueprintID: "apep",
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
                    scrollChances: [ScrollType.unknown.rawValue: 0.2],
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
                    scrollChances: [ScrollType.unknown.rawValue: 0.2],
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
                    scrollChances: [ScrollType.unknown.rawValue: 0.2],
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
        intro: String = "",
        bossLine: String = "",
        startingLevel: Int,
        stageCount: Int,
        environment: BattleEnvironment,
        roster: [String],
        bossID: String,
        levelStep: Int = 3,
        powerScale: Double = 1.0,
        essence: String = "essence_magic_mid",
        enemyStars: Int? = nil,
        difficulty: Double = 1.0
    ) -> Chapter {
        var stages: [Stage] = []
        for index in 1...stageCount {
            let isBoss = index == stageCount
            let level = startingLevel + (index - 1) * levelStep
            let power = Int(Double(2_500) * powerScale * pow(1.18, Double(index - 1)))

            var enemies: [EnemySpawn] = []
            let count = isBoss ? 4 : min(4, 2 + index / 3)
            for slot in 0..<count {
                // Rotate through the roster so consecutive stages are not
                // identical, and drop the boss into the last slot of a boss stage.
                let blueprintID = (isBoss && slot == count - 1)
                    ? bossID
                    : roster[(index + slot) % roster.count]
                // Later chapters field the same creatures at a higher grade,
                // the way the genre does, rather than at absurd levels; the
                // boss keeps its own grade when that is higher.
                let natural = UnitDatabase.blueprint(blueprintID)?.naturalStars ?? 3
                let isTheBoss = isBoss && slot == count - 1
                let stars = isTheBoss ? max(enemyStars ?? natural, natural) : (enemyStars ?? natural)
                enemies.append(EnemySpawn(
                    blueprintID: blueprintID,
                    level: level,
                    stars: stars,
                    statMultiplier: difficulty * (isTheBoss ? 1.4 : 1.0)
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
                    essenceChances: [essence: isBoss ? 0.6 : 0.2],
                    scrollChances: isBoss
                        ? [ScrollType.mystical.rawValue: 0.6, ScrollType.pantheonic.rawValue: 0.15]
                        : [ScrollType.unknown.rawValue: 0.15, ScrollType.mystical.rawValue: 0.05],
                    firstClearDivinity: isBoss ? 60 : 20
                ),
                environment: environment,
                isBoss: isBoss
            ))
        }

        // The boss is the last slot of the last stage, so the cut-in's speaker
        // is `bossID` and not a guess made later from the spawn list.
        return Chapter(
            id: id, pantheon: pantheon, name: name, summary: summary,
            intro: intro, bossLine: bossLine, bossBlueprintID: bossID, stages: stages
        )
    }

    /// Builds fightable units for a stage's enemy list.
    static func buildEnemies(for stage: Stage) -> [ResolvedUnit] {
        buildEnemies(spawns: stage.enemies)
    }

    /// One wave's spawns as fighting units.
    static func buildEnemies(spawns: [EnemySpawn]) -> [ResolvedUnit] {
        spawns.compactMap { spawn in
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

    // MARK: - Raids
    //
    // Two encounters where the boss is a fight rather than a statblock. Every
    // mechanic lives on the boss's own `EnemySpawn` (`RaidBossProfile`), so
    // nothing here touches a campaign stage, a hall floor or a Labyrinth level:
    // a spawn with no profile is the enemy the engine has always built.
    //
    // A raid is a `Stage` like everything else, so the campaign's plumbing runs
    // it unchanged — `CampaignService.applyRewards` pays it, and its clear is
    // recorded in `campaignProgress` under the raid's id. It is deliberately
    // NOT in `chapters`: it must not appear on the campaign map or count
    // towards a realm's completion.
    //
    // WHERE THE NUMBERS COME FROM. `tools/balance.py` has no raid model yet —
    // it cannot simulate a barrier, a drain, an enrage or a rotating weakness —
    // so these were measured with a throwaway probe built on its engine, which
    // stands the barrier in as extra health on the boss and puts both minions
    // on the field from the first turn. Win rate and median turn count over 60
    // seeded fights, against the ladders `balance.py` uses for chapters:
    //
    //                          4★ lv35   5★ lv40+r   6★ lv55 max   gods lv60
    //   Apep, barrier once         0%         0%        100%/121t   100%/44t
    //   Apep, barrier x3           0%         0%         32%/150t   100%/51t
    //   Jötunn, barrier once       0%         0%         13%/150t   100%/51t
    //   Jötunn, barrier x3         0%         0%          0%/150t   100%/57t
    //
    // Read: a raid needs a real team, not four levelled duplicates — the same
    // team clears Labyrinth B10 at 100% in 121-145 turns. The probe leaves the
    // drain out, so a real fight runs longer than those turn counts, which is
    // why the enrage sits at 65 and 60 rather than at the medians. Anything
    // changed here should be re-probed, and the probe belongs in balance.py the
    // next time somebody touches it.

    static let raids: [RaidEncounter] = [
        RaidEncounter(
            id: "raid_apep",
            name: "The Serpent That Swallows the Sun",
            summary: """
            It has swallowed the disc again, and the scarabs are carrying \
            what is left of the daylight down its throat. Break the night off \
            its back before the coils close, and be quick: every turn this \
            takes, there is less of the world left to come back to.
            """,
            bossLine: "I have swallowed the disc. Fight by whatever light you brought with you.",
            environment: .serpentDeep,
            stage: Stage(
                id: "raid_apep_1",
                chapterID: "raid_apep",
                index: 1,
                name: "The Serpent That Swallows the Sun",
                energyCost: 12,
                recommendedPower: 36_000,
                enemies: [
                    EnemySpawn(
                        blueprintID: "apep", level: 60, stars: 6, statMultiplier: 2.0,
                        raid: RaidBossProfile(
                            // A seventh of its health in scale, back three
                            // boss turns after it goes. That is the fight's
                            // rhythm: burst it off in a few turns, take the
                            // stun window, hit the health underneath, do it
                            // again. Any thicker and the barrier IS the fight.
                            barrierFraction: 0.12,
                            barrierRegenTurns: 5,
                            barrierStunTurns: 1,
                            barrierName: "Scales of Night",
                            // Two scarabs every third boss turn. Left alone
                            // they carry 3.5% of the serpent's health back to
                            // it each, per boss turn: about half of what a
                            // team that can clear this is dealing, so the
                            // guard has to be answered but a slow answer is
                            // not instantly fatal.
                            adds: [
                                EnemySpawn(blueprintID: "sun_scarab", level: 55, stars: 5, statMultiplier: 1.1),
                                EnemySpawn(blueprintID: "sun_scarab", level: 55, stars: 5, statMultiplier: 1.1)
                            ],
                            addInterval: 4,
                            addDrain: 0.022,
                            summonName: "Calls the Swarm",
                            drainName: "Swallows the Disc",
                            // A team of gods puts this fight down in 44-51
                            // turns and a team of levelled duplicates takes
                            // 120 or more (measured with the probe in the
                            // report — `balance.py` has no raid model yet).
                            // Turn 65 is the line between them: the good team
                            // never sees it, the slow one is killed by it
                            // instead of drawing at the 150-turn cap.
                            enrageTurn: 65,
                            enrageMultiplier: 1.8,
                            enrageInterval: 12,
                            // Ember, so Tide already has the wheel on it; the
                            // rotation moves the opening on, and a team that
                            // brought only one element spends two thirds of
                            // the fight at three quarters damage.
                            weaknesses: [.tide, .gale, .umbra],
                            weaknessInterval: 3,
                            weaknessMultiplier: 1.7,
                            offElementMultiplier: 0.75
                        )
                    )
                ],
                rewards: StageRewards(
                    drachma: 12_000, playerExperience: 300, unitExperience: 2_400,
                    relicChance: 1.0, relicGrade: 6,
                    // The offensive half of the sets: what a raid team is
                    // short of once the Labyrinth has paid out its own.
                    relicSets: [.fury, .ruin, .thunder, .styx, .nemesis, .wrath],
                    essenceChances: ["essence_ember_high": 0.8, "essence_magic_high": 0.5],
                    scrollChances: [ScrollType.pantheonic.rawValue: 0.5, ScrollType.divine.rawValue: 0.12],
                    firstClearDivinity: 300
                ),
                environment: .serpentDeep,
                isBoss: true
            )
        ),
        RaidEncounter(
            id: "raid_jotunn",
            name: "The King Under the Ice",
            summary: """
            He has not moved since the last winter and the glacier has grown \
            over him like a shell. What comes out of it when the shell cracks \
            has been waiting a very long time for someone to come down here.
            """,
            bossLine: "The ice took a hundred winters to close over me. You have until it finishes cracking.",
            environment: .jotunheimHall,
            stage: Stage(
                id: "raid_jotunn_1",
                chapterID: "raid_jotunn",
                index: 1,
                name: "The King Under the Ice",
                energyCost: 12,
                recommendedPower: 45_000,
                enemies: [
                    EnemySpawn(
                        blueprintID: "boss_jotunn", level: 60, stars: 6, statMultiplier: 1.85,
                        raid: RaidBossProfile(
                            // A thicker shell than the serpent's and slower to
                            // come back: this is the defensive raid, and the
                            // whole fight is fought in the windows.
                            barrierFraction: 0.14,
                            barrierRegenTurns: 5,
                            barrierStunTurns: 1,
                            barrierName: "Rime Shell",
                            adds: [
                                EnemySpawn(blueprintID: "enemy_frost_troll", level: 55, stars: 5, statMultiplier: 0.8),
                                EnemySpawn(blueprintID: "enemy_frost_troll", level: 55, stars: 5, statMultiplier: 0.8)
                            ],
                            addInterval: 6,
                            addDrain: 0.035,
                            summonName: "Calls the Trolls",
                            drainName: "Drinks the Cold",
                            // Sooner and harder than the serpent's: nothing
                            // short of a real team beats him at all, and the
                            // probe puts that team at 51-57 turns. Turn 60
                            // leaves it one step of room and no more.
                            enrageTurn: 60,
                            enrageMultiplier: 1.9,
                            enrageInterval: 10,
                            // Two elements, rotating twice as fast. Gale, so
                            // Ember has the wheel on him half the time and
                            // nothing has it the other half.
                            weaknesses: [.ember, .radiance],
                            weaknessInterval: 2,
                            weaknessMultiplier: 1.7,
                            offElementMultiplier: 0.75
                        )
                    )
                ],
                rewards: StageRewards(
                    drachma: 15_000, playerExperience: 340, unitExperience: 2_800,
                    relicChance: 1.0, relicGrade: 6,
                    // The defensive half, and the two that keep a raid team
                    // standing through an enrage.
                    relicSets: [.aegis, .bulwark, .wards, .vigil, .fates, .ichor],
                    essenceChances: ["essence_gale_high": 0.8, "essence_magic_high": 0.5],
                    scrollChances: [ScrollType.pantheonic.rawValue: 0.5, ScrollType.divine.rawValue: 0.15],
                    firstClearDivinity: 300
                ),
                environment: .jotunheimHall,
                isBoss: true
            )
        )
    ]

    static func raid(_ id: String) -> RaidEncounter? { raids.first(where: { $0.id == id }) }

    /// The raid a stage belongs to, if it is one.
    static func raid(containing stage: Stage) -> RaidEncounter? { raid(stage.chapterID) }

    static var raidStages: [Stage] { raids.map(\.stage) }

    /// The raid profiles of a stage's enemies, keyed by their index in the
    /// team `buildEnemies` returns. Counted the same way `buildEnemies` counts
    /// — a spawn whose blueprint has gone missing is dropped from both — so
    /// the engine's boss index can never point at the wrong combatant.
    static func raidProfiles(for stage: Stage) -> [Int: RaidBossProfile] {
        var profiles: [Int: RaidBossProfile] = [:]
        var index = 0
        for spawn in stage.enemies {
            guard UnitDatabase.blueprint(spawn.blueprintID) != nil else { continue }
            if let profile = spawn.raid { profiles[index] = profile }
            index += 1
        }
        return profiles
    }

    /// The engine for a raid. The same build as `CampaignService.startBattle`
    /// with the boss's mechanics handed in; the caller still spends the energy.
    static func raidEngine(for stage: Stage, playerTeam: [ResolvedUnit], seed: UInt64) -> BattleEngine {
        BattleEngine(
            playerTeam: playerTeam,
            opponentTeam: buildEnemies(for: stage),
            mode: .campaign,
            seed: seed,
            laterWaves: stage.laterWaves.map { buildEnemies(spawns: $0) },
            raidBosses: raidProfiles(for: stage)
        )
    }

    // MARK: - Boss lines

    /// What the boss of this stage says as the fight opens, or nil when the
    /// stage has nobody to say it.
    ///
    /// Only a chapter's boss stage and a raid have a line: the Labyrinth's
    /// bosses are fought ten times over for relics and a line that plays on
    /// every run is a line the player learns to skip. A chapter whose text has
    /// not been written yet returns nil rather than an empty band.
    static func bossLine(for stage: Stage) -> BossLine? {
        guard stage.isBoss else { return nil }
        // The locals are not called `chapter` and `raid`: both are also the
        // names of the lookups on this enum, and a shadowed function is a trap
        // for the next person to edit this.
        if let owner = chapter(stage.chapterID),
           !owner.bossLine.isEmpty, !owner.bossBlueprintID.isEmpty {
            return BossLine(blueprintID: owner.bossBlueprintID, line: owner.bossLine)
        }
        if let encounter = raid(stage.chapterID), !encounter.bossLine.isEmpty,
           // The speaker is the spawn carrying the mechanics, which is the one
           // the health bar at the top of the screen belongs to.
           let speaker = encounter.stage.enemies.first(where: { $0.raid != nil })?.blueprintID {
            return BossLine(blueprintID: speaker, line: encounter.bossLine)
        }
        return nil
    }
}

// MARK: - Boss lines

/// One line of a boss's, and who says it.
///
/// The cut-in the ultimates use wants a card, a name, an accent colour and some
/// words; everything but the words comes off the blueprint, so this carries the
/// id rather than four resolved fields that would go stale with the roster.
struct BossLine: Equatable, Sendable {
    var blueprintID: String
    var line: String
}

// MARK: - Raid mechanics

/// What makes a raid boss a fight instead of a large statblock.
///
/// Every field is off by default, so a spawn that carries a profile at all is
/// opting in to exactly the mechanics it names. The engine reads this and
/// nothing else: there is no raid flag on `Stage`, and an ordinary boss is
/// unaffected because it simply has no profile.
struct RaidBossProfile: Codable, Equatable, Sendable {

    // MARK: The barrier

    /// Size of the absorbing barrier as a fraction of the boss's own max
    /// health. 0 means no barrier. It soaks before health and before any
    /// shield cast on the boss, because it is the bar the player is aiming at.
    var barrierFraction: Double = 0
    /// Boss turns between the barrier breaking and coming back at full.
    var barrierRegenTurns: Int = 3
    /// Turns the boss loses when it breaks. This is the reward for the burst:
    /// it is applied straight, not rolled against the boss's resistance.
    var barrierStunTurns: Int = 1
    /// Shown over the boss when it is raised, shattered and restored.
    var barrierName: String = "Barrier"

    // MARK: The guard

    /// The minions the boss calls. Empty means it fights alone.
    var adds: [EnemySpawn] = []
    /// Boss turns between summons. It only tops the guard back up to
    /// `adds.count`, so the field cannot fill with minions while the player
    /// ignores them — but each one left alive keeps feeding the boss.
    var addInterval: Int = 3
    /// Fraction of the boss's max health each living minion feeds it at the
    /// start of every boss turn. This is the reason to kill them.
    var addDrain: Double = 0.05
    var summonName: String = "Calls its guard"
    var drainName: String = "Drinks from the guard"

    // MARK: The enrage clock

    /// Battle turn the boss's damage jumps on. 0 means it never enrages.
    var enrageTurn: Int = 0
    /// Multiplier on everything the boss deals, compounding once per stack.
    var enrageMultiplier: Double = 1.0
    /// Battle turns between further stacks after the first. 0 means one step
    /// and no more.
    var enrageInterval: Int = 0

    // MARK: The rotating weakness

    /// The elements the boss is open to, in the order it rotates through them.
    /// Empty means the element wheel is the whole story, as everywhere else.
    var weaknesses: [Element] = []
    /// Boss turns each weakness stands for.
    var weaknessInterval: Int = 3
    /// Damage multiplier for an attacker of the element that is up.
    var weaknessMultiplier: Double = 1.7
    /// And for everything else. Below 1 this is what punishes a team built
    /// out of one element: it is off-element for most of the rotation.
    var offElementMultiplier: Double = 1.0
}

/// One raid: a boss, its mechanics and the painting to fight it in front of.
struct RaidEncounter: Identifiable, Sendable {
    var id: String
    var name: String
    var summary: String
    /// What the boss says as the fight opens, like a chapter's. A raid is the
    /// biggest fight in the game and it would be the only boss in it with
    /// nothing to say.
    var bossLine: String = ""
    var environment: BattleEnvironment
    var stage: Stage

    /// The boss's mechanics, for a briefing screen that wants to say what the
    /// player is walking into.
    var profile: RaidBossProfile? { stage.enemies.compactMap(\.raid).first }

    /// The elements the boss opens itself to, in rotation order.
    var weaknesses: [Element] { profile?.weaknesses ?? [] }
}
