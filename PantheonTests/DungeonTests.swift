import XCTest
@testable import Pantheon

/// The Halls of Essence: five floors per element, every floor a real fight
/// with a real boss, every clear paying the element's own essence.
final class DungeonTests: XCTestCase {

    func testEveryHallHasFiveFloorsOfRealEnemies() {
        XCTAssertEqual(DungeonDatabase.halls.count, Element.allCases.count)
        for hall in DungeonDatabase.halls {
            XCTAssertEqual(hall.floors.count, DungeonDatabase.floorCount, hall.id)
            for floor in hall.floors {
                XCTAssertEqual(floor.enemies.count, 4, floor.id)
                XCTAssertTrue(floor.isBoss, floor.id)
                for spawn in floor.enemies {
                    XCTAssertNotNil(UnitDatabase.blueprint(spawn.blueprintID), "\(floor.id) references \(spawn.blueprintID)")
                    XCTAssertFalse(UnitDatabase.summonPool.contains(spawn.blueprintID), "\(spawn.blueprintID) is summonable and fights in a hall")
                }
                XCTAssertEqual(StageDatabase.buildEnemies(for: floor).count, 4, floor.id)
            }
        }
    }

    func testFloorsClimbAndPayTheirElement() {
        for hall in DungeonDatabase.halls {
            let floors = hall.floors
            for (index, floor) in floors.enumerated() where index > 0 {
                let previous = floors[index - 1]
                XCTAssertGreaterThan(floor.recommendedPower, previous.recommendedPower, floor.id)
                XCTAssertGreaterThanOrEqual(floor.rewards.relicGrade, previous.rewards.relicGrade, floor.id)
                XCTAssertGreaterThan(floor.energyCost, previous.energyCost, floor.id)
            }
            let essence = "essence_\(hall.element.rawValue)_mid"
            for floor in floors {
                XCTAssertNotNil(floor.rewards.essenceChances[essence], "\(floor.id) does not drop \(essence)")
            }
            XCTAssertEqual(floors.last?.rewards.relicGrade, 6)
        }
    }

    func testFloorsOpenInOrderAndStayRepeatable() {
        guard let hall = DungeonDatabase.hall("hall_ember") else { return XCTFail("no ember hall") }
        var player = NewGame.create().player
        let first = hall.floors[0]
        let second = hall.floors[1]
        XCTAssertTrue(CampaignService.isUnlocked(first, player: player))
        XCTAssertFalse(CampaignService.isUnlocked(second, player: player))

        var rng = SeededRandom(seed: 3)
        let win = BattleResult(outcome: .victory, turnsTaken: 9, survivorFraction: 1, totalDamageDealt: 1, totalDamageTaken: 0, seed: 1)
        let firstClear = CampaignService.applyRewards(stage: first, result: win, player: &player, rng: &rng)
        XCTAssertTrue(firstClear.isFirstClear)
        XCTAssertEqual(firstClear.divinityEarned, first.rewards.firstClearDivinity)
        XCTAssertTrue(CampaignService.isUnlocked(second, player: player))

        // A second clear still pays drachma and experience, and no divinity.
        let again = CampaignService.applyRewards(stage: first, result: win, player: &player, rng: &rng)
        XCTAssertFalse(again.isFirstClear)
        XCTAssertEqual(again.divinityEarned, 0)
        XCTAssertGreaterThan(again.drachma, 0)
    }

    func testStageLookupFindsFloors() {
        XCTAssertNotNil(StageDatabase.stage("hall_tide_3"))
        XCTAssertTrue(StageDatabase.allStages.contains(where: { $0.chapterID == "hall_umbra" }))
    }

    // MARK: - The Labyrinth

    func testLabyrinthsHaveTenLevelsOfThreeWavesEndingAtTheBoss() {
        XCTAssertEqual(DungeonDatabase.labyrinths.count, 3)
        for labyrinth in DungeonDatabase.labyrinths {
            XCTAssertEqual(labyrinth.levels.count, DungeonDatabase.levelCount, labyrinth.id)
            for level in labyrinth.levels {
                XCTAssertEqual(level.laterWaves.count, 2, level.id)
                XCTAssertEqual(level.laterWaves.last?.first?.blueprintID, labyrinth.bossID, level.id)
                XCTAssertEqual(level.rewards.relicChance, 1.0, level.id)
                XCTAssertEqual(level.rewards.relicSets, labyrinth.sets, level.id)
                XCTAssertTrue(level.isBoss, level.id)
                for spawn in level.enemies + level.laterWaves.flatMap({ $0 }) {
                    XCTAssertNotNil(UnitDatabase.blueprint(spawn.blueprintID), "\(level.id) references \(spawn.blueprintID)")
                    XCTAssertFalse(UnitDatabase.summonPool.contains(spawn.blueprintID), "\(spawn.blueprintID) is summonable and guards a dungeon")
                }
            }
            XCTAssertEqual(labyrinth.levels.first?.rewards.relicGrade, 3, labyrinth.id)
            XCTAssertEqual(labyrinth.levels.last?.rewards.relicGrade, 6, labyrinth.id)
            for (index, level) in labyrinth.levels.enumerated() where index > 0 {
                let previous = labyrinth.levels[index - 1]
                XCTAssertGreaterThan(level.recommendedPower, previous.recommendedPower, level.id)
                XCTAssertGreaterThanOrEqual(level.rewards.relicGrade, previous.rewards.relicGrade, level.id)
            }
        }
        // Every set drops somewhere.
        XCTAssertEqual(Set(DungeonDatabase.labyrinths.flatMap(\.sets)), Set(RelicSet.allCases))
        XCTAssertNotNil(StageDatabase.stage("lab_hydra_10"))
    }

    func testARunAlwaysDropsARelicOfTheDungeonsSets() {
        guard let labyrinth = DungeonDatabase.labyrinth("lab_hydra") else { return XCTFail("no hydra lair") }
        var player = NewGame.create().player
        var rng = SeededRandom(seed: 11)
        let win = BattleResult(outcome: .victory, turnsTaken: 20, survivorFraction: 1, totalDamageDealt: 1, totalDamageTaken: 0, seed: 1)
        let first = labyrinth.levels[0]
        for _ in 0..<12 {
            let outcome = CampaignService.applyRewards(stage: first, result: win, player: &player, rng: &rng)
            XCTAssertEqual(outcome.relicsEarned.count, 1)
            for relic in outcome.relicsEarned {
                XCTAssertTrue(labyrinth.sets.contains(relic.set), "\(relic.set) is not one of the Hydra's sets")
                XCTAssertEqual(relic.grade, 3)
            }
        }
        XCTAssertTrue(CampaignService.isUnlocked(labyrinth.levels[1], player: player))
        XCTAssertFalse(CampaignService.isUnlocked(labyrinth.levels[2], player: player))
    }

    func testWavesFollowOneAnotherAndOnlyTheLastEndsTheBattle() {
        let team = StageDatabase.buildEnemies(spawns: (0..<3).map { _ in
            EnemySpawn(blueprintID: "sekhmet_ember", level: 40, stars: 6, statMultiplier: 3.0)
        })
        func mob(_ count: Int) -> [ResolvedUnit] {
            StageDatabase.buildEnemies(spawns: (0..<count).map { _ in
                EnemySpawn(blueprintID: "shabti", level: 5, stars: 3, statMultiplier: 0.5)
            })
        }
        XCTAssertEqual(team.count, 3)
        let engine = BattleEngine(
            playerTeam: team, opponentTeam: mob(2), mode: .simulation, seed: 5, laterWaves: [mob(2), mob(1)]
        )
        engine.autoBattle = true
        let events = engine.start()

        var waves: [Int] = []
        var endedAt: Int?
        var firstWaveAt: Int?
        for (index, event) in events.enumerated() {
            if case .waveStarted(let wave, let count, let opponents) = event {
                waves.append(wave)
                XCTAssertEqual(count, 3)
                XCTAssertFalse(opponents.isEmpty)
                if firstWaveAt == nil { firstWaveAt = index }
            }
            if case .battleEnded = event { endedAt = index }
        }
        XCTAssertEqual(waves, [2, 3])
        XCTAssertEqual(engine.waveIndex, 3)
        XCTAssertEqual(engine.waveCount, 3)
        XCTAssertEqual(engine.result?.outcome, .victory)
        XCTAssertEqual(engine.team(.opponent).count, 5, "every wave's units stay on the roll")
        XCTAssertNotNil(endedAt)
        XCTAssertNotNil(firstWaveAt)
        if let endedAt, let firstWaveAt {
            XCTAssertGreaterThan(endedAt, firstWaveAt, "the battle ended before the second wave came on")
        }
        // The simulate helper takes the same waves.
        let result = BattleEngine.simulate(playerTeam: team, opponentTeam: mob(2), seed: 6, laterWaves: [mob(2)])
        XCTAssertEqual(result.outcome, .victory)
    }

    // MARK: - The Endless Tower

    /// A tower floor is built on demand and is deliberately NOT in
    /// `StageDatabase.allStages` (a hundred `Stage`s on every read of a
    /// computed property), so `testEveryStageReferencesRealBlueprints` never
    /// sees one. `buildEnemies` drops an unknown blueprint id silently, which
    /// would leave a floor short a body or a warden floor with no warden, so
    /// the whole hundred is walked here instead.
    func testEveryTowerFloorReferencesRealBlueprints() {
        for floor in 1...DungeonDatabase.towerFloors {
            let stage = DungeonDatabase.towerFloor(floor)
            XCTAssertEqual(stage.chapterID, DungeonDatabase.towerChapterID, stage.id)
            XCTAssertEqual(stage.index, floor, stage.id)
            XCTAssertEqual(stage.enemies.count, 3, stage.id)
            for spawn in stage.enemies {
                XCTAssertNotNil(
                    UnitDatabase.blueprint(spawn.blueprintID),
                    "\(stage.id) references unknown unit \(spawn.blueprintID)"
                )
            }
            XCTAssertEqual(
                StageDatabase.buildEnemies(for: stage).count, stage.enemies.count,
                "\(stage.id) lost a body to an unknown blueprint"
            )
            XCTAssertEqual(stage.isBoss, floor % 10 == 0, stage.id)
        }
    }

    /// The curve only ever climbs, and every tenth floor is a warden that is
    /// no weaker than its own natural grade.
    func testTheTowerClimbsAndNeverSlipsBack() {
        var previousLevel = 0
        var previousGrade = 0
        for floor in 1...DungeonDatabase.towerFloors {
            let level = DungeonDatabase.towerLevel(floor: floor)
            let grade = DungeonDatabase.towerGrade(floor: floor)
            XCTAssertGreaterThanOrEqual(level, previousLevel, "floor \(floor)")
            XCTAssertGreaterThanOrEqual(grade, previousGrade, "floor \(floor)")
            XCTAssertLessThanOrEqual(grade, 6, "floor \(floor)")
            previousLevel = level
            previousGrade = grade

            let stage = DungeonDatabase.towerFloor(floor)
            if DungeonDatabase.isTowerBossFloor(floor) {
                let warden = stage.enemies[0]
                let natural = UnitDatabase.blueprint(warden.blueprintID)?.naturalStars ?? 0
                XCTAssertGreaterThanOrEqual(warden.stars, natural, stage.id)
                XCTAssertNotNil(DungeonDatabase.towerScroll(floor: floor), stage.id)
            } else {
                XCTAssertNil(DungeonDatabase.towerScroll(floor: floor), stage.id)
            }
        }
        XCTAssertEqual(DungeonDatabase.towerLevel(floor: 1), 20)
        XCTAssertEqual(DungeonDatabase.towerLevel(floor: DungeonDatabase.towerFloors), 70)
    }

    /// Asking for a floor outside the tower still hands back a real floor
    /// rather than trapping on an out-of-range tier.
    func testAFloorOutsideTheTowerIsClamped() {
        XCTAssertEqual(DungeonDatabase.towerFloor(0).index, 1)
        XCTAssertEqual(DungeonDatabase.towerFloor(-5).index, 1)
        XCTAssertEqual(DungeonDatabase.towerFloor(999).index, DungeonDatabase.towerFloors)
    }

    /// The mark moves, the milestone pays once, and both land on the receipt
    /// the result panel shows rather than arriving silently in the wallet.
    func testAClearedFloorMovesTheMarkAndPaysItsMilestoneOnce() {
        var player = NewGame.create().player
        var rng = SeededRandom(seed: 11)
        let win = BattleResult(outcome: .victory, turnsTaken: 9, survivorFraction: 1, totalDamageDealt: 1, totalDamageTaken: 0, seed: 1)
        let stage = DungeonDatabase.towerFloor(10)

        var outcome = CampaignService.applyRewards(stage: stage, result: win, player: &player, rng: &rng)
        XCTAssertTrue(outcome.isFirstClear)
        let divinityAfterTheFloor = player.wallet.divinity
        let receiptAfterTheFloor = outcome.divinityEarned
        // Floor 10 is a warden floor, so the floor itself has already paid a
        // mystical scroll; the milestone's two land on top of that one.
        let scrollsAfterTheFloor = outcome.scrollsEarned[ScrollType.mystical.rawValue] ?? 0

        TowerService.recordClear(stage: stage, result: win, outcome: &outcome, player: &player, rng: &rng)

        XCTAssertEqual(player.tower?.highestFloorCleared, 10)
        XCTAssertEqual(player.tower?.milestonesClaimed, [10])
        XCTAssertEqual(TowerService.nextFloor(player: player), 11)
        XCTAssertEqual(TowerService.nextMilestone(player: player), 25)
        // Floor 10 pays 150 divinity, 2 mystical scrolls and 20,000 drachma.
        XCTAssertEqual(player.wallet.divinity, divinityAfterTheFloor + 150)
        XCTAssertEqual(outcome.divinityEarned, receiptAfterTheFloor + 150)
        XCTAssertEqual(outcome.scrollsEarned[ScrollType.mystical.rawValue], scrollsAfterTheFloor + 2)

        // Settling the same floor twice pays nothing more.
        let settled = player.wallet.divinity
        var again = outcome
        TowerService.recordClear(stage: stage, result: win, outcome: &again, player: &player, rng: &rng)
        XCTAssertEqual(player.wallet.divinity, settled)
        XCTAssertEqual(player.tower?.milestonesClaimed, [10])
        XCTAssertEqual(player.tower?.highestFloorCleared, 10)
    }

    /// A lost floor moves nothing, so the climb resumes where it was and the
    /// player fights the same floor again.
    func testALostFloorMovesNothing() {
        var player = NewGame.create().player
        player.tower = TowerProgress(highestFloorCleared: 7, milestonesClaimed: [])
        var rng = SeededRandom(seed: 2)
        let loss = BattleResult(outcome: .defeat, turnsTaken: 12, survivorFraction: 0, totalDamageDealt: 1, totalDamageTaken: 9, seed: 1)
        let stage = DungeonDatabase.towerFloor(8)

        var outcome = CampaignService.applyRewards(stage: stage, result: loss, player: &player, rng: &rng)
        TowerService.recordClear(stage: stage, result: loss, outcome: &outcome, player: &player, rng: &rng)

        XCTAssertEqual(player.tower?.highestFloorCleared, 7)
        XCTAssertEqual(TowerService.nextFloor(player: player), 8)
    }

    /// The hundredth floor is the end of the climb: nothing above it, and
    /// starting a battle there throws rather than handing back floor 101.
    func testTheSummitHasNothingAboveIt() {
        var player = NewGame.create().player
        player.tower = TowerProgress(highestFloorCleared: DungeonDatabase.towerFloors, milestonesClaimed: DungeonDatabase.towerMilestones)

        XCTAssertNil(TowerService.nextFloor(player: player))
        XCTAssertNil(TowerService.nextStage(player: player))
        XCTAssertNil(TowerService.nextMilestone(player: player))
        XCTAssertThrowsError(try TowerService.startBattle(player: &player, seed: 1))
    }

    /// Every milestone the track shows pays something, and no other floor does.
    func testEveryMilestonePaysAndNoOtherFloorDoes() {
        for floor in 1...DungeonDatabase.towerFloors {
            let reward = DungeonDatabase.towerMilestoneReward(floor: floor)
            if DungeonDatabase.towerMilestones.contains(floor) {
                XCTAssertNotNil(reward, "floor \(floor) is a milestone that pays nothing")
            } else {
                XCTAssertNil(reward, "floor \(floor) pays a milestone it should not")
            }
        }
    }
}
