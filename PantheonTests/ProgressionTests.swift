import XCTest
@testable import Pantheon

/// Progression and economy rules. These are the numbers a player will notice
/// changing, so they are pinned rather than left to drift.
final class ProgressionTests: XCTestCase {

    func testStarGradeScalesStatsButNotSpeed() {
        let blueprint = UnitDatabase.starter
        let low = ProgressionService.baseStats(
            for: Unit(blueprint: blueprint, level: 1, stars: 3), blueprint: blueprint
        )
        let high = ProgressionService.baseStats(
            for: Unit(blueprint: blueprint, level: 1, stars: 6), blueprint: blueprint
        )

        XCTAssertGreaterThan(high.hp, low.hp)
        XCTAssertGreaterThan(high.atk, low.atk)
        // Speed is flat by design: it is what lets a low-grade support stay
        // relevant next to a maxed god.
        XCTAssertEqual(high.spd, low.spd)
    }

    func testMaxLevelFollowsGrade() {
        XCTAssertEqual(ProgressionService.maxLevel(stars: 1), 15)
        XCTAssertEqual(ProgressionService.maxLevel(stars: 6), 65)
    }

    func testExperienceCannotPushPastGradeCap() {
        var unit = Unit(blueprint: UnitDatabase.starter, level: 1, stars: 3)
        ProgressionService.grantExperience(10_000_000, to: &unit)
        XCTAssertEqual(unit.level, ProgressionService.maxLevel(stars: 3))
        XCTAssertEqual(unit.experience, 0)
    }

    func testEvolutionRequiresMaxLevelAndFodder() {
        var unit = Unit(blueprint: UnitDatabase.starter, level: 1, stars: 5)
        var wallet = Wallet()
        // A 5★ → 6★ evolution costs 150,000 drachma, more than a fresh
        // wallet holds; the test is about level and fodder, so fund it.
        wallet.drachma = 500_000
        XCTAssertThrowsError(try ProgressionService.evolve(&unit, fodder: [], wallet: &wallet))

        unit.level = ProgressionService.maxLevel(stars: 5)
        XCTAssertThrowsError(try ProgressionService.evolve(&unit, fodder: [], wallet: &wallet))

        let fodder = (0..<5).map { _ in Unit(blueprint: UnitDatabase.starter, level: 1, stars: 5) }
        XCTAssertNoThrow(try ProgressionService.evolve(&unit, fodder: fodder, wallet: &wallet))
        XCTAssertEqual(unit.stars, 6)
        XCTAssertEqual(unit.level, 1)
    }

    func testRelicPercentagesApplyToBaseNotToFlats() {
        let blueprint = UnitDatabase.starter
        let unit = Unit(blueprint: blueprint, level: 40, stars: 6)
        let base = ProgressionService.baseStats(for: unit, blueprint: blueprint)

        let flatOnly = Relic(
            set: .fury, slot: 1, grade: 6,
            mainStat: StatModifier(.atkFlat, 500), subStats: []
        )
        // Deliberately a different set from the flat piece, so that no set
        // bonus completes and the test measures only the two main stats.
        let percentOnly = Relic(
            set: .zephyr, slot: 2, grade: 6,
            mainStat: StatModifier(.atkPercent, 0.50), subStats: []
        )

        let both = ProgressionService.resolve(unit, blueprint: blueprint, equipped: [flatOnly, percentOnly])
        // 50% of base ATK, plus the flat 500 (at +0 the main stat multiplier is 1x).
        let expected = base.atk + base.atk * 0.50 + 500
        XCTAssertEqual(both.stats.atk, expected.rounded(), accuracy: 2.0)
    }

    func testCompletedSetGrantsItsBonusOnce() {
        let blueprint = UnitDatabase.starter
        let unit = Unit(blueprint: blueprint, level: 40, stars: 6)
        let base = ProgressionService.baseStats(for: unit, blueprint: blueprint)

        // Two Fury pieces complete the set; a third does not double it.
        let pieces = (1...3).map { slot in
            Relic(
                set: .fury, slot: slot, grade: 6,
                mainStat: StatModifier(Relic.fixedMainStat(forSlot: slot) ?? .atkPercent, 0),
                subStats: []
            )
        }
        let resolved = ProgressionService.resolve(unit, blueprint: blueprint, equipped: pieces)
        XCTAssertEqual(resolved.stats.atk, (base.atk * 1.35).rounded(), accuracy: 2.0)
    }

    func testAwakeningConsumesEssenceExactlyOnce() {
        var unit = Unit(blueprint: UnitDatabase.starter, level: 1, stars: 5)
        var essences = UnitDatabase.starter.awakening!.essenceCost

        XCTAssertNoThrow(try ProgressionService.awaken(&unit, essences: &essences))
        XCTAssertTrue(unit.isAwakened)
        XCTAssertTrue(essences.values.allSatisfy { $0 == 0 })
        XCTAssertThrowsError(try ProgressionService.awaken(&unit, essences: &essences))
    }

    // MARK: - Fusion
    //
    // The recipe table is thirty blueprint ids typed by hand, and a wrong one
    // shows up in the game only as a corner that can never be filled — no
    // crash, no log line, just a hexagram nobody can finish. Nothing else in
    // the project reads that table mechanically, and there is no compiler in
    // the environment it was written in.

    func testEveryFusionRecipeNamesUnitsThatExist() {
        XCTAssertEqual(
            FusionService.brokenReferences, [],
            "the fusion table names blueprint ids nothing answers to"
        )
    }

    func testFusionPrizesAreNotSummonable() {
        XCTAssertEqual(FusionService.fusionOnlyIDs.count, FusionService.recipes.count,
                       "two recipes promise the same unit")
        for recipe in FusionService.recipes {
            // The whole bargain. A prize a scroll can also hand over turns
            // four raised units and up to 120,000 drachma into a tax.
            XCTAssertFalse(
                UnitDatabase.summonPool.contains(recipe.resultID),
                "\(recipe.name) promises \(recipe.resultID), which the gacha still gives out"
            )
            XCTAssertTrue(recipe.isExclusive, "\(recipe.name) says so on screen, too")
        }
    }

    func testEveryFusionCornerIsAProjectAndNotAnImpossibility() throws {
        for recipe in FusionService.recipes {
            XCTAssertEqual(recipe.ingredients.count, 4, "\(recipe.name) is not a hexagram")
            var named = Set<String>()
            for ingredient in recipe.ingredients {
                let blueprint = try XCTUnwrap(
                    UnitDatabase.blueprint(ingredient.blueprintID), ingredient.blueprintID
                )
                // The panel keys its corner tiles by blueprint id, so a
                // repeat would collapse two corners into one row.
                XCTAssertTrue(
                    named.insert(ingredient.blueprintID).inserted,
                    "\(recipe.name) names \(ingredient.blueprintID) twice"
                )
                XCTAssertGreaterThanOrEqual(
                    ingredient.stars, blueprint.naturalStars,
                    "\(ingredient.blueprintID) is asked for below the grade it summons at"
                )
                XCTAssertLessThanOrEqual(
                    ingredient.level, ProgressionService.maxLevel(stars: ingredient.stars),
                    "\(ingredient.blueprintID) is asked for above the level cap of \(ingredient.stars)★"
                )
            }
        }
    }

    func testFusionSpendsExactlyTheFourCornersAndTheDrachma() throws {
        let recipe = FusionService.recipes[0]
        var player = Player()
        player.wallet.drachma = recipe.drachmaCost

        for ingredient in recipe.ingredients {
            let blueprint = try XCTUnwrap(UnitDatabase.blueprint(ingredient.blueprintID))
            player.units.append(
                Unit(blueprint: blueprint, level: ingredient.level, stars: ingredient.stars)
            )
        }
        // Somebody the recipe never named, to prove fusion eats what it named
        // and not what it found.
        let corners = Set(recipe.ingredients.map { $0.blueprintID })
        let other = try XCTUnwrap(UnitDatabase.all.first { !corners.contains($0.id) })
        let bystander = Unit(blueprint: other, level: 1, stars: 6)
        player.units.append(bystander)

        let plan = FusionService.plan(for: recipe, player: player)
        XCTAssertTrue(plan.canFuse, plan.blocker ?? "no reason given")

        let created = try FusionService.fuse(recipe, player: &player)

        XCTAssertEqual(created.blueprintID, recipe.resultID)
        XCTAssertEqual(created.acquiredFrom, "fusion")
        // The Hall of Ka still has something to sell afterwards.
        XCTAssertFalse(created.isAwakened)
        XCTAssertEqual(created.level, 1)
        XCTAssertEqual(player.wallet.drachma, 0)
        XCTAssertEqual(player.units.count, 2)
        XCTAssertTrue(player.units.contains { $0.id == bystander.id })
        XCTAssertTrue(player.codex.contains(recipe.resultID))
    }

    func testFusionNeverEatsALockedUnitOrOneStandingOnATeam() throws {
        let recipe = FusionService.recipes[0]
        var player = Player()
        player.wallet.drachma = recipe.drachmaCost

        for (index, ingredient) in recipe.ingredients.enumerated() {
            let blueprint = try XCTUnwrap(UnitDatabase.blueprint(ingredient.blueprintID))
            var unit = Unit(blueprint: blueprint, level: ingredient.level, stars: ingredient.stars)
            if index == 0 { unit.isLocked = true }
            player.units.append(unit)
        }
        player.campaignTeam.unitIDs = [player.units[1].id]

        let plan = FusionService.plan(for: recipe, player: player)
        XCTAssertFalse(plan.canFuse)
        XCTAssertEqual(plan.missing.count, 2)
        XCTAssertTrue(plan.missing.allSatisfy { $0.shortfall == FusionService.Shortfall.reserved })

        XCTAssertThrowsError(try FusionService.fuse(recipe, player: &player))
        XCTAssertEqual(player.units.count, 4, "a refused fusion consumed a unit anyway")
        XCTAssertEqual(player.wallet.drachma, recipe.drachmaCost, "a refused fusion charged for it")
    }

    func testFusionTakesTheWeakestQualifyingCopy() throws {
        let recipe = FusionService.recipes[0]
        let ingredient = recipe.ingredients[0]
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint(ingredient.blueprintID))

        var player = Player()
        let raised = Unit(
            blueprint: blueprint,
            level: ProgressionService.maxLevel(stars: 6), stars: 6
        )
        let barely = Unit(blueprint: blueprint, level: ingredient.level, stars: ingredient.stars)
        // Strongest first, so passing would mean order and not choice.
        player.units = [raised, barely]

        let slot = try XCTUnwrap(FusionService.plan(for: recipe, player: player).slots.first)
        XCTAssertEqual(slot.unitID, barely.id, "fusion ate the copy the player raised")
    }
}

/// The campaign's tributes: two sets a chapter, three chests a tier, each
/// paid once, the judgment only when every stage holds three stars.
final class TributeTests: XCTestCase {

    func testEveryChapterYieldsAStatSetAndAnEffectSet() {
        var seen: Set<RelicSet> = []
        for chapter in StageDatabase.chapters {
            XCTAssertEqual(chapter.relicSets.count, 2, chapter.id)
            XCTAssertEqual(chapter.relicSets.filter { $0.piecesRequired == 2 }.count, 1, chapter.id)
            for stage in chapter.stages {
                XCTAssertEqual(stage.rewards.relicSets, chapter.relicSets, stage.id)
            }
            seen.formUnion(chapter.relicSets)
        }
        XCTAssertEqual(seen, Set(RelicSet.allCases), "every set is farmed on some road")
    }

    func testTiersKeepTheChapterSets() {
        let chapter = StageDatabase.chapters[0]
        for tier in CampaignDifficulty.allCases {
            let scaled = chapter.at(tier)
            XCTAssertEqual(scaled.relicSets, chapter.relicSets, tier.rawValue)
            XCTAssertEqual(scaled.stages.last?.rewards.relicSets, chapter.relicSets, tier.rawValue)
            XCTAssertEqual(TributeService.tributes(for: scaled).count, 3, tier.rawValue)
        }
    }

    func testTributesAreEarnedClaimedOnceAndPayTheChapterSet() {
        let chapter = StageDatabase.chapters[0]
        var player = Player()
        var rng = SeededRandom(seed: 5)
        let tributes = TributeService.tributes(for: chapter)
        let road = tributes[0], gate = tributes[1], judgment = tributes[2]
        XCTAssertEqual(road.milestone, .third)
        XCTAssertEqual(gate.milestone, .boss)
        XCTAssertEqual(judgment.milestone, .flawless)

        XCTAssertFalse(TributeService.isEarned(road, chapter: chapter, player: player))
        XCTAssertNil(TributeService.claim(road, chapter: chapter, player: &player, rng: &rng))

        player.campaignProgress[chapter.id] = 3
        XCTAssertTrue(TributeService.isEarned(road, chapter: chapter, player: player))
        XCTAssertFalse(TributeService.isEarned(gate, chapter: chapter, player: player))
        let divinity = player.wallet.divinity
        let scrolls = player.wallet.scrolls[ScrollType.pantheonic.rawValue] ?? 0
        XCTAssertNotNil(TributeService.claim(road, chapter: chapter, player: &player, rng: &rng))
        XCTAssertEqual(player.wallet.divinity, divinity + 30)
        XCTAssertEqual(player.wallet.scrolls[ScrollType.pantheonic.rawValue] ?? 0, scrolls + 1)
        XCTAssertTrue(TributeService.isClaimed(road, player: player))
        XCTAssertNil(TributeService.claim(road, chapter: chapter, player: &player, rng: &rng), "paid once")

        player.campaignProgress[chapter.id] = chapter.stages.count
        let paid = TributeService.claim(gate, chapter: chapter, player: &player, rng: &rng)
        let relic = try? XCTUnwrap(paid?.relic)
        XCTAssertEqual(relic?.grade, 4)
        XCTAssertEqual(relic?.resolvedQuality, .rare)
        XCTAssertTrue(chapter.relicSets.contains(relic?.set ?? .fury), "the gate pays the chapter's own set")
        XCTAssertTrue(player.relics.contains(where: { $0.id == relic?.id }))

        XCTAssertFalse(TributeService.isEarned(judgment, chapter: chapter, player: player))
        for stage in chapter.stages {
            TributeService.recordStars(stage: stage, stars: 3, player: &player)
        }
        XCTAssertTrue(TributeService.isEarned(judgment, chapter: chapter, player: player))
        XCTAssertEqual(TributeService.unclaimedCount(for: chapter, player: player), 1)
    }

    func testStarsAreAHighWaterMarkPerTier() {
        var player = Player()
        let stage = StageDatabase.chapters[0].stages[0]
        TributeService.recordStars(stage: stage, stars: 2, player: &player)
        TributeService.recordStars(stage: stage, stars: 1, player: &player)
        TributeService.recordStars(stage: stage, stars: 0, player: &player)
        XCTAssertEqual(player.stageStars?[stage.id], 2)
        TributeService.recordStars(stage: stage.at(.hard), stars: 3, player: &player)
        XCTAssertEqual(player.stageStars?[stage.id], 2, "a Hard clear is its own mark")
        XCTAssertEqual(player.stageStars?[stage.at(.hard).id], 3)
    }

    func testPayoutsGrowWithTheTier() {
        for milestone in TributeMilestone.allCases {
            let normal = TributeService.payout(milestone, tier: .normal)
            let hard = TributeService.payout(milestone, tier: .hard)
            let hell = TributeService.payout(milestone, tier: .hell)
            XCTAssertLessThan(normal.divinity, hard.divinity, milestone.rawValue)
            XCTAssertLessThan(hard.divinity, hell.divinity, milestone.rawValue)
            XCTAssertLessThanOrEqual(normal.relicGrade ?? 0, hard.relicGrade ?? 0, milestone.rawValue)
            XCTAssertLessThanOrEqual(hard.relicGrade ?? 0, hell.relicGrade ?? 0, milestone.rawValue)
        }
        XCTAssertEqual(TributeService.payout(.flawless, tier: .hell).relicQuality, .legend)
    }
}
