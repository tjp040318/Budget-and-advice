import Foundation

/// The Halls of Essence: one hall per element, five floors each, a boss on
/// every floor, open every day and cleared as often as the energy holds. This
/// is where the awakening essences come from — the campaign drops magic
/// essences, the halls drop the element's own — and where the relics worth
/// keeping start to appear, because the floor sets the grade.
///
/// A floor is a `Stage` whose chapter is the hall, so the campaign's plumbing
/// (`CampaignService.startBattle`, `applyRewards`, the briefing, the battle
/// screen, auto-repeat) runs a floor with no special case: a hall's progress
/// lives in `campaignProgress` under the hall's id, the next floor opens when
/// the one before it falls, and every clear pays — only the divinity is
/// first-clear.
enum DungeonDatabase {

    struct Hall: Identifiable, Sendable {
        var id: String
        var element: Element
        var name: String
        var summary: String
        var environment: BattleEnvironment
        var chapter: Chapter

        var floors: [Stage] { chapter.stages }
    }

    static let floorCount = 5

    static let halls: [Hall] = [
        hall(
            id: "hall_ember", element: .ember, name: "Hall of Embers",
            summary: "A furnace with a floor. The heat comes up through the stone and the things that live in it do not mind.",
            environment: .duatGate,
            roster: ["enemy_cyclops", "enemy_berserker", "sandstone_sentinel"],
            bossID: "apep"
        ),
        hall(
            id: "hall_tide", element: .tide, name: "Hall of Tides",
            summary: "The sea comes in under the door twice a day. What it leaves behind has teeth.",
            environment: .aegeanCliffs,
            roster: ["enemy_frost_troll", "enemy_frost_troll", "enemy_amazon"],
            bossID: "boss_hydra"
        ),
        hall(
            id: "hall_gale", element: .gale, name: "Hall of Gales",
            summary: "The wind never stops in here, and it carries the giants' winter down from the roof.",
            environment: .midgardFjord,
            roster: ["serpopard", "enemy_amazon", "enemy_valkyrie"],
            bossID: "boss_jotunn"
        ),
        hall(
            id: "hall_radiance", element: .radiance, name: "Hall of Radiance",
            summary: "No shadow anywhere. The choosers of the slain patrol it, and they choose.",
            environment: .olympusGate,
            roster: ["sun_scarab", "enemy_medusa", "enemy_valkyrie"],
            bossID: "enemy_valkyrie"
        ),
        hall(
            id: "hall_umbra", element: .umbra, name: "Hall of Shadows",
            summary: "The lamps are painted on. The devourer waits at the bottom, and she has never once been full.",
            environment: .serpentDeep,
            roster: ["enemy_draugr", "enemy_minotaur", "shabti"],
            bossID: "ammit"
        ),
    ]

    static func hall(_ id: String) -> Hall? { halls.first(where: { $0.id == id }) }

    // MARK: - The Labyrinth: the relic dungeons

    /// A relic dungeon: ten levels, each one battle of three waves that ends
    /// at the boss, and a relic of the dungeon's own sets at the end of every
    /// run. This is the genre's Cairos — the place the relic hunt lives — and
    /// the reason to keep a team levelled after the story is done.
    struct Labyrinth: Identifiable, Sendable {
        var id: String
        var name: String
        var summary: String
        var environment: BattleEnvironment
        /// The sets this dungeon drops; the other dungeons drop the others.
        var sets: [RelicSet]
        var bossID: String
        var chapter: Chapter

        var levels: [Stage] { chapter.stages }
    }

    static let levelCount = 10

    static let labyrinths: [Labyrinth] = [
        labyrinth(
            id: "lab_colossus", name: "Vault of the Colossus",
            summary: "A statue the size of a temple, and it is awake. The sentinels that guard the stairs are its children, and it does not spare them.",
            environment: .colossusVault,
            sets: [.fury, .aegis, .bulwark, .zephyr, .fates, .vigil],
            roster: ["sandstone_sentinel", "shabti", "sun_scarab"],
            bossID: "boss_colossus"
        ),
        labyrinth(
            id: "lab_hydra", name: "Lair of the Hydra",
            summary: "Nine heads, and every one of them remembers Heracles. The marsh water is warm, which is the wrong kind of sign.",
            environment: .hydraLair,
            sets: [.thunder, .ruin, .wrath, .ichor, .titanfall, .chains],
            roster: ["enemy_medusa", "serpopard", "enemy_amazon"],
            bossID: "boss_hydra"
        ),
        labyrinth(
            id: "lab_necropolis", name: "Necropolis of the Unwrapped King",
            summary: "The dead are filed in here by the weight of their hearts. The king at the bottom was never weighed: he unwrapped himself, and the devourer prowls the halls on his behalf.",
            environment: .necropolis,
            sets: [.oracle, .wards, .styx, .nemesis, .chains, .bulwark],
            roster: ["shabti", "ammit", "serpopard"],
            bossID: "boss_unwrapped_king"
        ),
    ]

    static func labyrinth(_ id: String) -> Labyrinth? { labyrinths.first(where: { $0.id == id }) }

    /// The dungeon a stage belongs to, if it is a level of one.
    static func labyrinth(containing stage: Stage) -> Labyrinth? { labyrinth(stage.chapterID) }

    static var allLevels: [Stage] { labyrinths.flatMap(\.levels) }

    /// The grade of the relic a level drops, and of the mobs that guard it:
    /// 3★ on B1–3, 4★ on B4–6, 5★ on B7–9 and 6★ on B10, the genre's ladder.
    static func labyrinthGrade(level: Int) -> Int { min(6, 3 + (level - 1) / 3) }

    /// Ten levels, each three waves: two of the roster's mobs and then the
    /// boss with two more, at a grade that climbs with the level and a
    /// multiplier that tightens the top. The numbers are in
    /// `tools/balance.py` (`LABYRINTHS`): B1 for a levelled 3★ team fresh
    /// from chapter one, B4 for 4★s with relics, B7 for 5★s, B10 for a
    /// maxed 6★ team. A run always drops a relic of the dungeon's sets.
    static func labyrinth(
        id: String, name: String, summary: String, environment: BattleEnvironment,
        sets: [RelicSet], roster: [String], bossID: String
    ) -> Labyrinth {
        var stages: [Stage] = []
        for level in 1...levelCount {
            let enemyLevel = 10 + level * 4
            let stars = labyrinthGrade(level: level)
            let difficulty = 0.70 + Double(level) * 0.08
            let wave: (Int) -> [EnemySpawn] = { offset in
                (0..<3).map { slot in
                    EnemySpawn(
                        blueprintID: roster[(level + offset + slot) % roster.count],
                        level: enemyLevel, stars: stars, statMultiplier: difficulty
                    )
                }
            }
            let bossNatural = UnitDatabase.blueprint(bossID)?.naturalStars ?? stars
            let boss = EnemySpawn(
                blueprintID: bossID, level: enemyLevel, stars: max(stars, bossNatural),
                statMultiplier: difficulty * 1.6
            )
            let bossWave = [boss] + Array(wave(2).prefix(2))
            stages.append(Stage(
                id: "\(id)_\(level)",
                chapterID: id,
                index: level,
                name: "\(name) B\(level)",
                energyCost: 6 + level / 4,
                recommendedPower: Int(2_200 * pow(1.34, Double(level - 1))),
                enemies: wave(0),
                rewards: StageRewards(
                    drachma: 500 + level * 250,
                    playerExperience: 30 + level * 10,
                    unitExperience: 200 + level * 100,
                    relicChance: 1.0,
                    relicGrade: stars,
                    relicSets: sets,
                    // A trickle of whetstones from B7, a Hero one from B10:
                    // the raids are the source, the Labyrinth a taste.
                    stoneChances: level >= 10 ? ["whetstone_rare": 0.25, "whetstone_hero": 0.10]
                        : (level >= 7 ? ["whetstone_rare": 0.25] : nil),
                    scrollChances: level >= 7 ? [ScrollType.mystical.rawValue: 0.08] : [:],
                    firstClearDivinity: 20
                ),
                environment: environment,
                isBoss: true,
                laterWaves: [wave(1), bossWave]
            ))
        }
        let chapter = Chapter(id: id, pantheon: environment.pantheon, name: name, summary: summary, stages: stages)
        return Labyrinth(
            id: id, name: name, summary: summary, environment: environment,
            sets: sets, bossID: bossID, chapter: chapter
        )
    }

    /// The scroll a hall drops: its element's, or the light & dark scroll
    /// for the two that have no scroll of their own.
    static func scroll(for element: Element) -> ScrollType {
        switch element {
        case .ember: return .ember
        case .tide: return .tide
        case .gale: return .gale
        case .radiance, .umbra: return .lightDark
        }
    }

    /// The hall a stage belongs to, if it is a floor of one.
    static func hall(containing stage: Stage) -> Hall? { hall(stage.chapterID) }

    static var allFloors: [Stage] { halls.flatMap(\.floors) }

    // MARK: - Building a hall

    /// Five floors that climb from a 4★ warm-up to a 6★ wall. The grade of
    /// the mobs rises with the floor rather than their level, the way the
    /// genre does it, and a chapter-wide multiplier tightens the top floors;
    /// the boss keeps its own grade when that is higher and stands at x1.4.
    /// The numbers are in `tools/balance.py` (`HALLS`) and were tuned
    /// there: floor 1 for a levelled 4★ team, floor 3 for 5★s with relics,
    /// floor 5 for a maxed 6★ team.
    static func hall(
        id: String, element: Element, name: String, summary: String,
        environment: BattleEnvironment, roster: [String], bossID: String
    ) -> Hall {
        var stages: [Stage] = []
        for floor in 1...floorCount {
            let level = 20 + floor * 8
            let stars = min(6, 3 + floor)
            let difficulty = 0.75 + Double(floor) * 0.10
            var enemies: [EnemySpawn] = []
            for slot in 0..<3 {
                let blueprintID = roster[(floor + slot) % roster.count]
                enemies.append(EnemySpawn(blueprintID: blueprintID, level: level, stars: stars, statMultiplier: difficulty))
            }
            let bossNatural = UnitDatabase.blueprint(bossID)?.naturalStars ?? stars
            enemies.append(EnemySpawn(
                blueprintID: bossID, level: level, stars: max(stars, bossNatural),
                statMultiplier: difficulty * 1.4
            ))

            let essence = "essence_\(element.rawValue)_mid"
            let high = "essence_\(element.rawValue)_high"
            stages.append(Stage(
                id: "\(id)_\(floor)",
                chapterID: id,
                index: floor,
                name: "\(name) B\(floor)",
                energyCost: 5 + floor,
                recommendedPower: Int(3_000 * pow(1.65, Double(floor - 1))),
                enemies: enemies,
                rewards: StageRewards(
                    drachma: 800 + floor * 300,
                    playerExperience: 40 + floor * 12,
                    unitExperience: 300 + floor * 120,
                    relicChance: min(1.0, 0.5 + Double(floor) * 0.1),
                    relicGrade: min(6, 2 + floor),
                    essenceChances: [essence: min(1.0, 0.5 + Double(floor) * 0.1), high: Double(floor) * 0.1],
                    scrollChances: [scroll(for: element).rawValue: 0.12],
                    firstClearDivinity: 30
                ),
                environment: environment,
                isBoss: true
            ))
        }
        let chapter = Chapter(id: id, pantheon: environment.pantheon, name: name, summary: summary, stages: stages)
        return Hall(id: id, element: element, name: name, summary: summary, environment: environment, chapter: chapter)
    }
}

// MARK: - The Endless Tower
//
// What there is to do once the campaign is finished: a hundred floors of one
// battle each, climbed once. Progress is a high-water mark — the tower resumes
// at the floor above the highest cleared, it never starts over — so a floor is
// fought exactly once and every floor has to be a gate rather than a grind.
// That is the difference from the Labyrinth, which is farmed: there the level
// is a difficulty dial the player picks, here it is a ladder the player is
// pushed up, and the reward for a floor is paid on the clear that opens the
// next one.
//
// The curve is `python3 tools/balance.py --tower`, and the measurements it
// prints are the reason for every constant below. Change one here and change
// it there.
extension DungeonDatabase {

    /// Ten floors that share a place, a roster and the warden who holds the
    /// tenth. Five of them, cycled twice up the hundred floors: the second lap
    /// fields the same five wardens fifty floors of difficulty later, which is
    /// the genre's way of making a hundred floors out of five sets of art.
    struct TowerTier: Sendable {
        var name: String
        var environment: BattleEnvironment
        /// Three families, cycled into the floor's three slots.
        var roster: [String]
        var wardenID: String
    }

    /// The tower's floors live in `campaignProgress` under this id, the way a
    /// hall's and a dungeon's do, so the campaign's reward path treats a floor
    /// as a stage with no special case. It is deliberately not a `Chapter`:
    /// nothing should be able to walk a hundred floors out of the campaign map.
    static let towerChapterID = "tower"
    static let towerFloors = 100
    /// The floors that pay something worth climbing for.
    static let towerMilestones = [10, 25, 50, 75, 100]

    /// The five tiers, in the order they are climbed. Their rosters were
    /// levelled against one another — about 1,200 points of base health each —
    /// so that a floor's difficulty comes from the curve and not from which
    /// tier it happens to land in; the Coil is a little the hardest of the
    /// five, which is why it holds floors 41-50 and 91-100, the two walls.
    ///
    /// The floor shows its opposition before the energy is spent, so sixteen
    /// of the twenty ids below are ones the bundle already has a card for.
    /// The four that are not — the frost troll, the valkyrie and the Hydra
    /// and Jötunn wardens — are the Norse tier, and they are the same four
    /// the Yggdrasil chapters and the Halls already field; until their cards
    /// are painted `UnitCard` draws its element-coloured monogram, which is
    /// the same thing that screen shows today.
    static let towerTiers: [TowerTier] = [
        TowerTier(
            name: "The Sand Stair", environment: .colossusVault,
            roster: ["sandstone_sentinel", "horus_radiance", "sun_scarab"],
            wardenID: "boss_colossus"
        ),
        TowerTier(
            name: "The Marsh Landing", environment: .hydraLair,
            roster: ["heracles_tide", "hoplite_radiance", "harpy_tide"],
            wardenID: "boss_hydra"
        ),
        TowerTier(
            name: "The Frozen Gallery", environment: .jotunheimHall,
            roster: ["heimdall_tide", "enemy_frost_troll", "enemy_valkyrie"],
            wardenID: "boss_jotunn"
        ),
        TowerTier(
            name: "The Weighing Floor", environment: .necropolis,
            roster: ["ammit", "sekhmet_umbra", "shabti_umbra"],
            wardenID: "boss_unwrapped_king"
        ),
        TowerTier(
            name: "The Coil", environment: .serpentDeep,
            roster: ["anubis_umbra", "ares_ember", "zeus_ember"],
            wardenID: "apep"
        ),
    ]

    static func towerTier(floor: Int) -> TowerTier {
        towerTiers[((max(1, floor) - 1) / 10) % towerTiers.count]
    }

    /// Level 20 at the door and 70 at the top: half a level a floor. A 6★ maxes
    /// at 65, so the last ten floors field levels no summoner can reach — which
    /// is the only place in the game that happens, and it is the top of the
    /// tower.
    static func towerLevel(floor: Int) -> Int { 20 + floor / 2 }

    /// The grade climbs a star every twenty floors, the way the later chapters
    /// field the same creatures at a higher grade rather than at absurd levels.
    static func towerGrade(floor: Int) -> Int { min(6, 3 + (floor - 1) / 20) }

    /// The flat multiplier on top: 0.81 on the first floor, 1.90 on the
    /// hundredth. The grade steps are cliffs and this is the slope between
    /// them.
    static func towerDifficulty(floor: Int) -> Double { 0.80 + Double(floor) * 0.011 }

    /// Every tenth floor is the tier's warden with two adds.
    static func isTowerBossFloor(_ floor: Int) -> Bool { floor % 10 == 0 }

    static func isTowerFloor(_ stage: Stage) -> Bool { stage.chapterID == towerChapterID }

    /// The scroll a warden drops: mystical to floor 39, the pantheon scroll to
    /// 79, divine above that. Ten scrolls for the whole climb.
    static func towerScroll(floor: Int) -> ScrollType? {
        guard isTowerBossFloor(floor) else { return nil }
        if floor >= 80 { return .divine }
        if floor >= 40 { return .pantheonic }
        return .mystical
    }

    /// One floor as a `Stage`, so `CampaignService` runs it, `BattleView`
    /// fights it and `StageBriefingView`'s plumbing shows it with no special
    /// case. Three mobs on an ordinary floor; on a boss floor the warden at
    /// x1.8 with two of them — x1.8 rather than the Labyrinth's x1.6 because
    /// the warden stands with two adds instead of three and the multiplier
    /// has to carry the missing body.
    ///
    /// Measured (`--tower`): floor 1 falls to the team that just cleared the
    /// campaign, floor 10 to four 4★s at level 35, floor 50 to a maxed 6★
    /// team (a 5★ team with relics takes it a third of the time), floor 75 to
    /// maxed 6★s and floor 100 to a maxed team of gods about two runs in three.
    static func towerFloor(_ floor: Int) -> Stage {
        let floor = min(max(1, floor), towerFloors)
        let tier = towerTier(floor: floor)
        let level = towerLevel(floor: floor)
        let stars = towerGrade(floor: floor)
        let difficulty = towerDifficulty(floor: floor)
        let mobs: [EnemySpawn] = (0..<3).map { slot in
            EnemySpawn(
                blueprintID: tier.roster[(floor + slot) % tier.roster.count],
                level: level, stars: stars, statMultiplier: difficulty
            )
        }
        var enemies = mobs
        if isTowerBossFloor(floor) {
            // The warden keeps its own grade when that is higher, so a 5★
            // primordial does not arrive as a 3★ on floor 10.
            let natural = UnitDatabase.blueprint(tier.wardenID)?.naturalStars ?? stars
            let warden = EnemySpawn(
                blueprintID: tier.wardenID, level: level, stars: max(stars, natural),
                statMultiplier: difficulty * 1.8
            )
            enemies = [warden] + Array(mobs.prefix(2))
        }
        var scrolls: [String: Double] = [:]
        if let scroll = towerScroll(floor: floor) { scrolls[scroll.rawValue] = 1.0 }
        return Stage(
            id: "\(towerChapterID)_\(floor)",
            chapterID: towerChapterID,
            index: floor,
            name: "Floor \(floor) · \(tier.name)",
            energyCost: 6 + floor / 20,
            recommendedPower: 2_800 + floor * 550,
            enemies: enemies,
            rewards: StageRewards(
                drachma: 800 + floor * 200,
                playerExperience: 30 + floor * 3,
                unitExperience: 250 + floor * 50,
                // A relic every fifth floor, at the floor's own grade, and no
                // set restriction: the tower is not a relic dungeon, it is
                // where a relic dungeon's rewards are spent.
                relicChance: floor % 5 == 0 ? 1.0 : 0.0,
                relicGrade: stars,
                scrollChances: scrolls,
                // Paid on the clear that opens the next floor, which for a
                // tower floor is the only clear there will ever be.
                firstClearDivinity: isTowerBossFloor(floor) ? 40 : 10
            ),
            environment: tier.environment,
            isBoss: isTowerBossFloor(floor)
        )
    }

    /// The next floor worth stopping at, given how far the player has climbed.
    static func towerMilestone(after clearedFloor: Int) -> Int? {
        towerMilestones.first(where: { $0 > clearedFloor })
    }

    /// What a milestone pays. These are the reason to keep climbing after the
    /// floors themselves stop being a challenge: the hundredth floor alone is
    /// worth two and a half divine summons and a pair of 6★ relics.
    static func towerMilestoneReward(floor: Int) -> ShopService.Grant? {
        switch floor {
        case 10:
            return .bundle([.divinity(150), .scrolls(.mystical, 2), .drachma(20_000)])
        case 25:
            return .bundle([.divinity(300), .scrolls(.pantheonic, 2), .relic(grade: 4)])
        case 50:
            return .bundle([.divinity(600), .scrolls(.divine, 1), .relic(grade: 5), .drachma(100_000), .stones("whetstone_legend", 1)])
        case 75:
            return .bundle([.divinity(900), .scrolls(.divine, 2), .relic(grade: 6), .stones("gem_hero", 1)])
        case 100:
            return .bundle([.divinity(1_500), .scrolls(.divine, 3), .relic(grade: 6), .relic(grade: 6), .stones("gem_legend", 1)])
        default:
            return nil
        }
    }
}

// MARK: - The tower's record in the save

/// How far up the tower the player has been, and which milestones have been
/// paid. Optional in `Player` (`Player.tower`), like `lastDailyPackClaim`: the
/// synthesised decoder tolerates a missing optional key and nothing else, so a
/// save written before the tower existed still loads.
///
/// `highestFloorCleared` is a high-water mark and only ever goes up. The
/// campaign's reward path also stamps `campaignProgress["tower"]` on a first
/// clear, in the same transaction, and that stamp is what makes a floor's
/// divinity pay once; this is what the tower itself reads.
struct TowerProgress: Codable, Equatable, Sendable {
    var highestFloorCleared: Int = 0
    /// Milestone floors already paid, so a milestone cannot be collected twice
    /// however the high-water mark is later touched.
    var milestonesClaimed: [Int] = []
}

// MARK: - Climbing the tower

/// The tower's rules: which floor is next, what a climb costs, and what a
/// clear is worth. The floor itself pays through `CampaignService.applyRewards`
/// like any other stage — `recordClear` only moves the mark and settles the
/// milestone, which is the part no stage can express.
enum TowerService {

    enum ClimbError: Error, LocalizedError {
        case notEnoughEnergy(needed: Int)
        case emptyTeam
        case summited

        var errorDescription: String? {
            switch self {
            case .notEnoughEnergy(let needed): return "This floor costs \(needed) energy."
            case .emptyTeam: return "Pick at least one unit for your team."
            case .summited: return "The tower is climbed. There is nothing above the hundredth floor."
            }
        }
    }

    static func clearedFloor(player: Player) -> Int {
        player.tower?.highestFloorCleared ?? 0
    }

    /// The floor the player would fight next, or nil once the tower is
    /// climbed. This is the whole of "a run resumes from the highest floor
    /// reached": there is no run state to keep, only the mark.
    static func nextFloor(player: Player) -> Int? {
        let cleared = clearedFloor(player: player)
        return cleared >= DungeonDatabase.towerFloors ? nil : cleared + 1
    }

    static func nextStage(player: Player) -> Stage? {
        nextFloor(player: player).map { DungeonDatabase.towerFloor($0) }
    }

    static func nextMilestone(player: Player) -> Int? {
        DungeonDatabase.towerMilestone(after: clearedFloor(player: player))
    }

    /// Spends the energy and builds the engine for the next floor. The caller
    /// drives it and hands the result back through `recordClear`, exactly as
    /// the campaign does — a tower floor is a campaign battle everywhere
    /// except here.
    static func startBattle(player: inout Player, seed: UInt64) throws -> BattleEngine {
        guard let stage = nextStage(player: player) else { throw ClimbError.summited }
        guard player.wallet.energy >= stage.energyCost else {
            throw ClimbError.notEnoughEnergy(needed: stage.energyCost)
        }
        let team = CampaignService.resolveTeam(player.campaignTeam, player: player)
        guard !team.isEmpty else { throw ClimbError.emptyTeam }

        player.wallet.energy -= stage.energyCost
        return BattleEngine(
            playerTeam: team,
            opponentTeam: StageDatabase.buildEnemies(for: stage),
            mode: .campaign,
            seed: seed
        )
    }

    /// Moves the high-water mark and pays the milestone, if the clear crossed
    /// one. Called after `CampaignService.applyRewards` has paid the floor
    /// itself, with that call's outcome: the milestone is folded into it, so
    /// the result screen shows the floor and the milestone on one receipt
    /// instead of the milestone arriving silently in the wallet. A defeat, a
    /// floor already below the mark, or a stage that is not a tower floor all
    /// do nothing.
    @discardableResult
    static func recordClear(
        stage: Stage,
        result: BattleResult,
        outcome: inout StageOutcome,
        player: inout Player,
        rng: inout SeededRandom
    ) -> [ShopService.Grant] {
        guard DungeonDatabase.isTowerFloor(stage), result.outcome == .victory else { return [] }
        var progress = player.tower ?? TowerProgress()
        guard stage.index > progress.highestFloorCleared else { return [] }
        progress.highestFloorCleared = stage.index
        defer { player.tower = progress }

        guard let reward = DungeonDatabase.towerMilestoneReward(floor: stage.index),
              !progress.milestonesClaimed.contains(stage.index) else { return [] }
        progress.milestonesClaimed.append(stage.index)

        // A relic grant makes the relic inside `ShopService.grant` and hands
        // back only its grade, so the ones it appended are taken off the end
        // of the bag to name them on the receipt.
        let relicsBefore = player.relics.count
        let granted = ShopService.grant(reward, to: &player, rng: &rng)
        outcome.relicsEarned.append(contentsOf: player.relics[relicsBefore...])
        for grant in granted {
            switch grant {
            case .drachma(let amount): outcome.drachma += amount
            case .divinity(let amount): outcome.divinityEarned += amount
            case .scrolls(let scroll, let count): outcome.scrollsEarned[scroll.rawValue, default: 0] += count
            case .essences(let id, let count): outcome.essencesEarned[id, default: 0] += count
            case .stones(let id, let count): outcome.stonesEarned[id, default: 0] += count
            // The relics are already on the receipt, and the tower pays no
            // energy; `.bundle` cannot appear because `grant` flattens it.
            case .relic, .energy, .energyRefill, .bundle: break
            }
        }
        return granted
    }
}
