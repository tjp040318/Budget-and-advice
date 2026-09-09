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
}
