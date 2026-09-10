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

    // MARK: - The Endless Tower's record

    func testTowerProgressRoundTripsThroughJSON() throws {
        var save = NewGame.create()
        save.player.tower = TowerProgress(highestFloorCleared: 63, milestonesClaimed: [10, 25, 50])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(SaveGame.self, from: try encoder.encode(save))

        XCTAssertEqual(restored.player.tower?.highestFloorCleared, 63)
        XCTAssertEqual(restored.player.tower?.milestonesClaimed, [10, 25, 50])
        XCTAssertEqual(TowerService.clearedFloor(player: restored.player), 63)
        XCTAssertEqual(TowerService.nextFloor(player: restored.player), 64)
        XCTAssertEqual(TowerService.nextMilestone(player: restored.player), 75)
    }

    /// The reason `Player.tower` is Optional. A save written before the tower
    /// existed has no key at all — the synthesised encoder writes nothing for a
    /// nil Optional, so a fresh save's JSON is byte-for-byte what the old build
    /// wrote — and the synthesised decoder tolerates exactly that and nothing
    /// else. A non-optional field here would wipe every existing save.
    func testASaveWrittenBeforeTheTowerStillDecodes() throws {
        let save = NewGame.create()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(save)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.isEmpty)
        XCTAssertFalse(
            json.contains("\"tower\""),
            "a save with no tower progress must not write a tower key"
        )

        let restored = try decoder.decode(SaveGame.self, from: data)
        XCTAssertNil(restored.player.tower)
        XCTAssertEqual(TowerService.clearedFloor(player: restored.player), 0)
        XCTAssertEqual(TowerService.nextFloor(player: restored.player), 1)
    }

    // MARK: - Relic loadouts

    /// `[Int: UUID]` is the one shape in the save whose keys are not strings.
    /// `Unit.equippedRelics` already proves it round-trips, but a loadout is
    /// the same dictionary one level deeper — inside an element of an optional
    /// array — so the six ids are checked back out the other side rather than
    /// assumed.
    func testRelicLoadoutsRoundTripThroughJSON() throws {
        var save = NewGame.create()
        let starter = save.player.units[0]
        let kept = try XCTUnwrap(
            RelicService.captureLoadout(named: "Power", for: starter.id, player: save.player)
        )
        save.player.relicLoadouts = [kept]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(SaveGame.self, from: try encoder.encode(save))
        let loadout = try XCTUnwrap(restored.player.relicLoadouts?.first)

        XCTAssertEqual(loadout.id, kept.id)
        XCTAssertEqual(loadout.name, "Power")
        XCTAssertEqual(loadout.unitID, starter.id)
        XCTAssertEqual(loadout.relicIDs.count, 6)
        XCTAssertEqual(loadout.relicIDs, starter.equippedRelics)
        XCTAssertEqual(
            RelicService.loadouts(for: starter.id, in: restored.player.relicLoadouts ?? []).count,
            1
        )
    }

    /// The reason `Player.relicLoadouts` is Optional, and the counterpart of
    /// the tower's test above: a save written before the optimiser shipped has
    /// no key at all, and the synthesised decoder tolerates exactly that.
    func testASaveWrittenBeforeLoadoutsStillDecodes() throws {
        let save = NewGame.create()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(save)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.isEmpty)
        XCTAssertFalse(
            json.contains("\"relicLoadouts\""),
            "a save with no kept loadouts must not write a relicLoadouts key"
        )

        let restored = try decoder.decode(SaveGame.self, from: data)
        XCTAssertNil(restored.player.relicLoadouts)
        XCTAssertTrue(
            RelicService.loadouts(
                for: restored.player.units[0].id,
                in: restored.player.relicLoadouts ?? []
            ).isEmpty
        )
    }

    // MARK: - The guided opening

    /// The two fields the first hour writes. `firstHourStep` is stored as a raw
    /// string rather than the enum so that a step renamed or dropped later
    /// cannot make an existing save undecodable — the round trip proves the
    /// value and the chapter list both survive.
    func testTheFirstHourRecordRoundTripsThroughJSON() throws {
        var save = NewGame.create()
        save.player.firstHourStep = FirstHourStep.powerUp.rawValue
        save.player.seenChapterIntros = ["duat_1", "olympus_1"]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(SaveGame.self, from: try encoder.encode(save))

        XCTAssertEqual(restored.player.firstHourStep, "powerUp")
        XCTAssertEqual(FirstHourStep(rawValue: restored.player.firstHourStep ?? ""), FirstHourStep.powerUp)
        XCTAssertEqual(restored.player.seenChapterIntros, ["duat_1", "olympus_1"])
    }

    /// The reason both fields are Optional, and the counterpart of the tower's
    /// and the loadouts' tests above: a save written before the guide existed
    /// has no key at all, and a veteran's save must land on the step it has
    /// actually reached rather than restarting them at the beginning.
    func testASaveWrittenBeforeTheGuideStillDecodes() throws {
        let save = NewGame.create()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(save)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.isEmpty)
        XCTAssertFalse(
            json.contains("\"firstHourStep\""),
            "a save that has not started the guide must not write a firstHourStep key"
        )
        XCTAssertFalse(
            json.contains("\"seenChapterIntros\""),
            "a save that has seen no intro must not write a seenChapterIntros key"
        )

        let restored = try decoder.decode(SaveGame.self, from: data)
        XCTAssertNil(restored.player.firstHourStep)
        XCTAssertNil(restored.player.seenChapterIntros)
        XCTAssertEqual(FirstHourStep.current(for: restored.player), FirstHourStep.summon)
    }

    /// The whole point of the guide: the step is worked out from the save, so
    /// no screen has to remember to advance a counter. This walks a new account
    /// through the four and off the end, including the two judgement calls —
    /// the equip step stands down while there is no spare relic to teach with,
    /// and comes back the moment one drops.
    func testTheGuidedOpeningIsDerivedFromTheSaveAlone() throws {
        var player = NewGame.create().player
        var rng = SeededRandom(seed: 11)
        XCTAssertEqual(FirstHourStep.current(for: player), FirstHourStep.summon)

        // Summoned somebody. The new god is bare, but every relic a new save
        // owns is already on the starter, so there is nothing to dress them in.
        player.totalSummons = 1
        let second = Unit(blueprint: UnitDatabase.anubisEmber, level: 1, stars: 4)
        player.units.append(second)
        XCTAssertEqual(FirstHourStep.current(for: player), FirstHourStep.fight)

        player.campaignProgress["duat_1"] = 1
        XCTAssertEqual(
            FirstHourStep.current(for: player), FirstHourStep.powerUp,
            "with no spare relic the equip step must stand down rather than point at nothing"
        )

        // A relic drops: the pointer goes back to the slot it teaches.
        let spare = RelicService.generate(grade: 3, slot: 1, rng: &rng)
        player.relics.append(spare)
        XCTAssertEqual(FirstHourStep.current(for: player), FirstHourStep.equip)

        try RelicService.equip(relicID: spare.id, on: second.id, player: &player)
        XCTAssertEqual(FirstHourStep.current(for: player), FirstHourStep.powerUp)

        player.lifetimeCounters = ["power_ups": 1]
        XCTAssertNil(
            FirstHourStep.current(for: player),
            "all four done means there is nothing left to point at"
        )
    }

    // MARK: - Boss lines

    /// A typo in `bossBlueprintID` costs nothing at build time and silently
    /// swallows the line at run time, so the ids are checked here. So is the
    /// rule that decides where a line plays: a chapter's boss stage and a raid,
    /// and nowhere else — the Labyrinth's bosses are fought ten times over.
    func testEveryBossLineNamesARealBlueprintAndPlaysOnlyOnItsBossStage() throws {
        for chapter in StageDatabase.chapters {
            XCTAssertFalse(chapter.intro.isEmpty, "\(chapter.id) has no intro card text")
            XCTAssertFalse(chapter.bossLine.isEmpty, "\(chapter.id) boss says nothing")
            XCTAssertNotNil(
                UnitDatabase.blueprint(chapter.bossBlueprintID),
                "\(chapter.id) boss line is said by unknown unit \(chapter.bossBlueprintID)"
            )
            guard let boss = chapter.stages.first(where: { $0.isBoss }) else {
                XCTFail("\(chapter.id) has a boss line and no boss stage")
                continue
            }
            let spoken = try XCTUnwrap(
                StageDatabase.bossLine(for: boss),
                "\(boss.id) is a boss stage whose chapter has a line and it says nothing"
            )
            XCTAssertEqual(spoken.line, chapter.bossLine)
            XCTAssertEqual(spoken.blueprintID, chapter.bossBlueprintID)
            for quiet in chapter.stages where !quiet.isBoss {
                XCTAssertNil(StageDatabase.bossLine(for: quiet), "\(quiet.id) speaks a boss line")
            }
        }

        for raid in StageDatabase.raids {
            let spoken = try XCTUnwrap(
                StageDatabase.bossLine(for: raid.stage),
                "\(raid.id) is the biggest fight in the game and its boss says nothing"
            )
            XCTAssertEqual(spoken.line, raid.bossLine)
            XCTAssertNotNil(
                UnitDatabase.blueprint(spoken.blueprintID),
                "\(raid.id) boss line is said by unknown unit \(spoken.blueprintID)"
            )
        }

        for level in DungeonDatabase.allLevels + DungeonDatabase.allFloors {
            XCTAssertNil(
                StageDatabase.bossLine(for: level),
                "\(level.id) is ground ten times over and must stay silent"
            )
        }
    }
}
