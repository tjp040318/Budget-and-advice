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

    /// The ladder's INTENT (Docs/PLAN.md, *Essence tiers*, 2026-09-17): the
    /// tier an awakening spends climbs with the family's NATURAL grade, so
    /// the Hall floor a player farms follows the unit on the dais. A 3★
    /// spends the element's Low and never its High, a 5★ its High and never
    /// its Low, a 4★ sits between, Magic essence rides alongside at every
    /// grade, and every line names a real essence. The counts are
    /// `balance.py --essences`'s to measure (`recipe_shipped`), not this
    /// test's to pin.
    func testAwakeningRecipeClimbsTheEssenceLadder() {
        for element in Element.allCases {
            let low = "essence_\(element.rawValue)_low"
            let high = "essence_\(element.rawValue)_high"
            let common = UnitDatabase.awakeningCost(element: element, naturalStars: 3)
            let hero = UnitDatabase.awakeningCost(element: element, naturalStars: 4)
            let legend = UnitDatabase.awakeningCost(element: element, naturalStars: 5)

            XCTAssertNotNil(common[low], "\(element.rawValue): a 3★ awakens on the first floors' Low")
            XCTAssertNil(common[high], "\(element.rawValue): a 3★ never asks for the High only B5 farms")
            XCTAssertNotNil(legend[high], "\(element.rawValue): a 5★ is awakened on B5's High")
            XCTAssertNil(legend[low], "\(element.rawValue): a 5★ has no use for Low")
            XCTAssertNotNil(hero[high], "\(element.rawValue): a 4★ spends the Mid floors' tier and some High")
            XCTAssertNil(hero[low], "\(element.rawValue): a 4★ is past the Low floors")

            // The High climbs with the grade: a 5★ asks more of it than a 4★.
            let heroHigh: Int = hero[high] ?? 0
            let legendHigh: Int = legend[high] ?? 0
            XCTAssertLessThan(heroHigh, legendHigh, element.rawValue)

            for recipe in [common, hero, legend] {
                let magic = recipe.keys.filter { $0.hasPrefix("essence_magic_") }
                XCTAssertFalse(magic.isEmpty, "\(element.rawValue): Magic essence at every grade")
                for (id, count) in recipe {
                    XCTAssertNotNil(EssenceCatalog.names[id], "\(id) is not in the catalogue")
                    XCTAssertGreaterThan(count, 0, id)
                }
            }
        }
    }

    /// ONE recipe feeds every blueprint: the seven hand-written families and
    /// the table's rows all read `UnitDatabase.awakeningCost` off their
    /// element and natural grade, so no family can carry a bill of its own
    /// (Anubis, a natural 4★, paid a 5★'s for a week before the ladder).
    func testEveryAwakeningReadsTheOneRecipe() {
        var awakenable = 0
        for blueprint in UnitDatabase.all {
            guard let awakening = blueprint.awakening else { continue }
            awakenable += 1
            let expected = UnitDatabase.awakeningCost(element: blueprint.element, naturalStars: blueprint.naturalStars)
            XCTAssertEqual(awakening.essenceCost, expected, blueprint.id)
        }
        XCTAssertGreaterThan(awakenable, 0, "nothing in the roster awakens")
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

    /// The owner, 2026-09-17, of the board offering a 5★ light Ares and a
    /// 5★ dark Horus: the premium is the Light & Dark scroll's alone. A
    /// hexagram's prize is a fire, water or wind 5★, one family per prize,
    /// and no corner asks for a premium form or another hexagram's prize.
    func testFusionPrizesAndCornersAreNeverLightOrDark() throws {
        var families: Set<String> = []
        for recipe in FusionService.recipes {
            let result = try XCTUnwrap(recipe.result, recipe.resultID)
            XCTAssertFalse(result.element.isLightOrDark, "\(recipe.name) hands over a premium form")
            XCTAssertEqual(result.naturalStars, 5, "\(recipe.name): a hexagram's prize is a 5★ god")
            XCTAssertTrue(families.insert(SelectorService.familyID(of: result)).inserted,
                          "\(recipe.name) promises a family another hexagram already gives")
            for ingredient in recipe.ingredients {
                let corner = try XCTUnwrap(ingredient.blueprint, ingredient.blueprintID)
                XCTAssertFalse(corner.element.isLightOrDark, "\(recipe.name) eats a premium form")
                XCTAssertFalse(FusionService.isFusionOnly(ingredient.blueprintID),
                               "\(recipe.name) asks for another hexagram's prize")
            }
        }
    }

    // MARK: - The Light and Dark premium (2026-09-17)

    /// The registry lifts a light or dark form's attack, health and defence
    /// by `lightDarkPremium` over what its builder wrote — once, on the way
    /// in — and touches nothing else: speed and the rates stay, a fire form
    /// is the builder's numbers as written, and the starter is the
    /// registered FIRE Anubis with no premium on him — a light or dark
    /// form is never given away (2026-09-17, evening). A premium, not a
    /// grade.
    func testRadianceAndUmbraFormsCarryThePremiumAndNothingElseDoes() throws {
        let premium: Double = UnitDatabase.lightDarkPremium
        XCTAssertGreaterThan(premium, 1.0)
        XCTAssertLessThan(premium, 1.20, "a premium, not a grade: a 5★ over a 4★ is 1.3 on every stat")

        let built = UnitDatabase.anubisUmbra
        let shipped = try XCTUnwrap(UnitDatabase.blueprint(built.id))
        let hpDue: Double = built.baseStats.hp * premium
        let atkDue: Double = built.baseStats.atk * premium
        let defDue: Double = built.baseStats.def * premium
        XCTAssertEqual(shipped.baseStats.hp, hpDue, accuracy: 1e-9)
        XCTAssertEqual(shipped.baseStats.atk, atkDue, accuracy: 1e-9)
        XCTAssertEqual(shipped.baseStats.def, defDue, accuracy: 1e-9)
        XCTAssertEqual(shipped.baseStats.spd, built.baseStats.spd, accuracy: 1e-9, "speed is not in the premium")
        XCTAssertEqual(shipped.baseStats.critRate, built.baseStats.critRate, accuracy: 1e-9)
        XCTAssertEqual(shipped.baseStats.resistance, built.baseStats.resistance, accuracy: 1e-9)
        XCTAssertEqual(shipped.skills.map(\.id), built.skills.map(\.id), "the premium is stats, not skills")

        let ember = UnitDatabase.anubisEmber
        let shippedEmber = try XCTUnwrap(UnitDatabase.blueprint(ember.id))
        XCTAssertEqual(shippedEmber.baseStats, ember.baseStats, "a fire form is the builder's numbers as written")
        XCTAssertEqual(UnitDatabase.starter.id, ember.id, "the starter is the fire Anubis, never a light or dark form")
        XCTAssertFalse(UnitDatabase.starter.element.isLightOrDark, "a premium unit is never handed out on day one")
        XCTAssertEqual(UnitDatabase.starter.baseStats, shippedEmber.baseStats, "the starter is the registered form")

        // A table family the same way: the row's lean, lifted for the light
        // and the dark forms only, the awakening's bonus with it.
        let row = try XCTUnwrap(UnitDatabase.familyRows.first { $0.key == "horus" })
        let umbraLean = UnitDatabase.lean(row, .umbra)
        let umbraHealthDue: Double = umbraLean.hp.rounded() * premium
        let umbraBonusDue: Double = (umbraLean.hp * 0.08).rounded() * premium
        let horusUmbra = try XCTUnwrap(UnitDatabase.blueprint("horus_umbra"))
        XCTAssertEqual(horusUmbra.baseStats.hp, umbraHealthDue, accuracy: 1e-9)
        XCTAssertEqual(horusUmbra.awakening?.statBonus.hp ?? 0, umbraBonusDue, accuracy: 1e-9)
        let emberLean = UnitDatabase.lean(row, .ember)
        let emberAttackDue: Double = emberLean.atk.rounded()
        let horusEmber = try XCTUnwrap(UnitDatabase.blueprint("horus_ember"))
        XCTAssertEqual(horusEmber.baseStats.atk, emberAttackDue, accuracy: 1e-9)

        // Every registered light or dark form is dearer than the fire form of
        // its family in health and attack together, and never by a grade.
        for blueprint in UnitDatabase.roster where blueprint.element.isLightOrDark {
            let family = SelectorService.familyID(of: blueprint)
            guard let fire = UnitDatabase.blueprint("\(family)_ember") else { continue }
            let mine: Double = blueprint.baseStats.hp + blueprint.baseStats.atk * 10
            let theirs: Double = fire.baseStats.hp + fire.baseStats.atk * 10
            XCTAssertGreaterThan(mine, theirs, "\(blueprint.id) is no better than \(fire.id)")
            XCTAssertLessThan(mine, theirs * 1.25, "\(blueprint.id) is a grade over \(fire.id), not a premium")
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

/// The end of a fight, the player's side (Docs/FEEL.md W1.6, W1.7): a clear
/// says what demigod levels it raised, the level-up beat prints what the
/// settle paid and names what the level opened, the island is left one
/// celebration however many clears raised it, and a plate's gold EXP bar
/// reads the unit's own experience.
final class LevelUpTests: XCTestCase {

    private func win() -> BattleResult {
        BattleResult(outcome: .victory, turnsTaken: 9, survivorFraction: 1, totalDamageDealt: 1, totalDamageTaken: 0, seed: 1)
    }

    /// One experience short of the next level, the first gate's 30 cross it:
    /// the outcome says one level and names the level reached, the bar is
    /// two longer and full, and the divinity the beat prints for the level
    /// is exactly what the settle paid for it beside the first clear's own.
    func testAWinThatLevelsTheDemigodSaysSoAndPaysTheLevel() throws {
        let stage = try XCTUnwrap(StageDatabase.stage("duat_1_1"))
        var player = NewGame.create().player
        player.experience = max(0, player.experienceToNextLevel - 1)
        let levelBefore: Int = player.level
        let barBefore: Int = player.wallet.maxEnergy
        let divinityBefore: Int = player.wallet.divinity
        var rng = SeededRandom(seed: 5)

        let outcome = CampaignService.applyRewards(stage: stage, result: win(), player: &player, rng: &rng)
        let levelAfter: Int = levelBefore + 1
        let barAfter: Int = barBefore + CampaignService.maxEnergyPerLevel
        XCTAssertEqual(outcome.playerLevelsGained, 1)
        XCTAssertEqual(outcome.newPlayerLevel, levelAfter)
        XCTAssertEqual(player.level, levelAfter)
        XCTAssertEqual(player.wallet.maxEnergy, barAfter)
        XCTAssertEqual(player.wallet.energy, player.wallet.maxEnergy, "a level-up fills the bar")

        let levelUp = PlayerLevelUp.between(levelBefore, outcome.newPlayerLevel, maxEnergy: player.wallet.maxEnergy)
        XCTAssertEqual(levelUp.levelsGained, 1)
        XCTAssertEqual(levelUp.maxEnergyGained, CampaignService.maxEnergyPerLevel)
        let paid: Int = player.wallet.divinity - divinityBefore
        let paidForTheLevel: Int = paid - stage.rewards.firstClearDivinity
        XCTAssertEqual(levelUp.divinity, paidForTheLevel, "the beat prints the divinity the settle paid for the level")

        // The next clear raises nothing, and still names the level it leaves.
        let again = CampaignService.applyRewards(stage: stage, result: win(), player: &player, rng: &rng)
        XCTAssertEqual(again.playerLevelsGained, 0)
        XCTAssertEqual(again.newPlayerLevel, player.level)
        // A loss pays nothing and names no level.
        let loss = BattleResult(outcome: .defeat, turnsTaken: 9, survivorFraction: 0, totalDamageDealt: 1, totalDamageTaken: 1, seed: 1)
        let lost = CampaignService.applyRewards(stage: stage, result: loss, player: &player, rng: &rng)
        XCTAssertEqual(lost.playerLevelsGained, 0)
        XCTAssertEqual(lost.newPlayerLevel, 0)
    }

    /// A level names what it opens: the sphinx on the level that sells it,
    /// the Hall of Ka's next tier on the level that raises it — and a span
    /// of no levels names nothing.
    func testALevelNamesWhatItOpens() throws {
        let sphinx = try XCTUnwrap(IslandDatabase.decoration("sphinx"))
        let sphinxEve: Int = sphinx.unlockLevel - 1
        let sold = LevelUnlock.between(sphinxEve, sphinx.unlockLevel)
        let sphinxNamed: Bool = sold.contains { $0.value == sphinx.title && $0.art == sphinx.thumbnail }
        XCTAssertTrue(sphinxNamed, "the sphinx is named, with its thumbnail, on the level that sells it")

        let hall = try XCTUnwrap(IslandDatabase.landmarks.first { $0.id == "hall" })
        let tierLevel = try XCTUnwrap(hall.upgradeLevels.first)
        let tierEve: Int = tierLevel - 1
        let grown = LevelUnlock.between(tierEve, tierLevel)
        let hallNamed: Bool = grown.contains { $0.label == hall.title }
        XCTAssertTrue(hallNamed, "the Hall of Ka's tier is named on the level it grows")

        let noLevels = LevelUnlock.between(tierLevel, tierLevel)
        XCTAssertTrue(noLevels.isEmpty, "no level, nothing opened")
        let soldEarlier: Bool = sphinx.unlockLevel <= tierEve
        let namedAgain: Bool = grown.contains { $0.value == sphinx.title }
        if soldEarlier {
            XCTAssertFalse(namedAgain, "a decoration sold on an earlier level is not named again")
        }
    }

    /// The island is left ONE celebration: from the level it last showed to
    /// the level now, merged across every clear before its visit, and taken
    /// once.
    @MainActor
    func testALevelUpWaitsForTheIslandOnceAndMergesAcrossClears() throws {
        let stage = try XCTUnwrap(StageDatabase.stage("duat_1_1"))
        var game = NewGame.create()
        game.player.experience = max(0, game.player.experienceToNextLevel - 1)
        let startLevel: Int = game.player.level
        let store = GameStore(save: game, account: Account.guest(), cloudSave: nil)
        defer { store.retire() }
        XCTAssertNil(store.pendingLevelCelebration)

        _ = store.finishCampaignBattle(stage: stage, result: win())
        let first = try XCTUnwrap(store.pendingLevelCelebration)
        XCTAssertEqual(first.from, startLevel)
        XCTAssertEqual(first.to, store.player.level)

        // A second level before the island is visited.
        store.update { player in
            player.experience = max(0, player.experienceToNextLevel - 1)
        }
        _ = store.finishCampaignBattle(stage: stage, result: win())
        let merged = try XCTUnwrap(store.takeLevelCelebration())
        let twoUp: Int = startLevel + 2
        XCTAssertEqual(merged.from, startLevel, "one celebration, from the first level")
        XCTAssertEqual(merged.to, twoUp, "to the last")
        XCTAssertNil(store.takeLevelCelebration(), "the island takes it once")
    }

    /// A plate's gold bar reads the unit's own experience: empty at the start
    /// of a level, half at half, full at its grade's cap (where experience is
    /// zeroed); a fight's gain runs bar to bar with the levels between.
    func testTheEXPBarReadsTheUnitsOwnExperience() {
        let blueprint = UnitDatabase.starter
        var unit = Unit(blueprint: blueprint, level: 5, stars: 3)
        let needed = ProgressionService.experienceForNextLevel(level: 5, stars: 3)
        let empty: Double = BattleSummary.experienceShare(of: unit)
        XCTAssertEqual(empty, 0, accuracy: 1e-9)

        unit.experience = needed / 2
        let half: Double = BattleSummary.experienceShare(of: unit)
        let expectedHalf: Double = Double(needed / 2) / Double(needed)
        XCTAssertEqual(half, expectedHalf, accuracy: 1e-9)

        var capped = Unit(blueprint: blueprint, level: 1, stars: 3)
        ProgressionService.grantExperience(10_000_000, to: &capped)
        let full: Double = BattleSummary.experienceShare(of: capped)
        XCTAssertEqual(full, 1, accuracy: 1e-9)

        var after = unit
        ProgressionService.grantExperience(needed, to: &after)
        let gain = BattleSummary.experienceGain(before: unit, after: after)
        let afterShare: Double = BattleSummary.experienceShare(of: after)
        XCTAssertEqual(gain.levelsGained, 1)
        XCTAssertEqual(gain.from, half, accuracy: 1e-9)
        XCTAssertEqual(gain.to, afterShare, accuracy: 1e-9)
    }
}
