import XCTest
@testable import Pantheon

/// Persistence. A save that cannot round-trip is an account that disappears, so
/// the whole player object is exercised rather than a sample of it.
final class SaveGameTests: XCTestCase {

    func testNewGameStartsWithTheStarterEquipped() {
        let save = NewGame.create()
        let player = save.player

        XCTAssertEqual(player.units.count, 1)
        XCTAssertEqual(player.units[0].blueprintID, UnitDatabase.starter.id)
        XCTAssertEqual(player.units[0].stars, UnitDatabase.starter.naturalStars)
        XCTAssertTrue(player.units[0].isLocked)
        XCTAssertEqual(player.relics.count, 6)
        XCTAssertEqual(player.units[0].equippedRelics.count, 6)
        XCTAssertEqual(player.campaignTeam.unitIDs, [player.units[0].id])
    }

    func testPlayerRoundTripsThroughJSON() throws {
        var save = NewGame.create()
        save.player.wallet.divinity = 4_242
        save.player.campaignProgress["duat_1"] = 3
        save.player.arena.points = 2_600
        save.player.essences["essence_radiance_mid"] = 7

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(save)
        let restored = try decoder.decode(SaveGame.self, from: data)

        XCTAssertEqual(restored.player.wallet.divinity, 4_242)
        XCTAssertEqual(restored.player.campaignProgress["duat_1"], 3)
        XCTAssertEqual(restored.player.arena.points, 2_600)
        XCTAssertEqual(restored.player.essences["essence_radiance_mid"], 7)
        XCTAssertEqual(restored.player.units.count, save.player.units.count)
        XCTAssertEqual(restored.player.units[0].id, save.player.units[0].id)
        XCTAssertEqual(restored.version, SaveGame.currentVersion)
    }

    func testEquippingARelicMovesItOffItsPreviousOwner() {
        var player = NewGame.create().player
        let second = Unit(blueprint: UnitDatabase.anubisEmber, level: 1, stars: 4)
        player.units.append(second)

        let relicID = player.relics[0].id
        let slot = player.relics[0].slot
        let originalOwner = player.units[0].id

        try? RelicService.equip(relicID: relicID, on: second.id, player: &player)

        XCTAssertNil(player.units.first(where: { $0.id == originalOwner })?.equippedRelics[slot])
        XCTAssertEqual(player.units.first(where: { $0.id == second.id })?.equippedRelics[slot], relicID)
        XCTAssertEqual(player.relic(relicID)?.equippedBy, second.id)
    }

    func testNoRelicIsEverEquippedTwice() {
        var player = NewGame.create().player
        let extra = Unit(blueprint: UnitDatabase.anubisTide, level: 1, stars: 4)
        player.units.append(extra)

        for relic in player.relics {
            try? RelicService.equip(relicID: relic.id, on: extra.id, player: &player)
        }

        var seen = Set<UUID>()
        for unit in player.units {
            for (_, relicID) in unit.equippedRelics {
                XCTAssertFalse(seen.contains(relicID), "Relic \(relicID) is equipped twice")
                seen.insert(relicID)
            }
        }
    }

    func testCampaignStagesUnlockInOrder() {
        var player = NewGame.create().player
        let chapter = StageDatabase.chapters[0]

        XCTAssertTrue(CampaignService.isUnlocked(chapter.stages[0], player: player))
        XCTAssertFalse(CampaignService.isUnlocked(chapter.stages[1], player: player))

        player.campaignProgress[chapter.id] = 1
        XCTAssertTrue(CampaignService.isUnlocked(chapter.stages[1], player: player))
        XCTAssertFalse(CampaignService.isUnlocked(chapter.stages[2], player: player))
    }

    func testEveryStageReferencesRealBlueprints() {
        for stage in StageDatabase.allStages {
            XCTAssertFalse(stage.enemies.isEmpty, "\(stage.id) has no enemies")
            for spawn in stage.enemies {
                XCTAssertNotNil(
                    UnitDatabase.blueprint(spawn.blueprintID),
                    "\(stage.id) references unknown unit \(spawn.blueprintID)"
                )
            }
            XCTAssertEqual(StageDatabase.buildEnemies(for: stage).count, stage.enemies.count)
        }
    }
}
