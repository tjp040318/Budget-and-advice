import XCTest
@testable import Pantheon

/// Boons: the earned socket. These pin the loop — a cache's three doors are
/// three different families and the same three every time, the kind chosen
/// rolls within its range, a push is a choice of two that only lifts, one
/// socket holds one boon — and every one of the engine's hooks, read off the
/// damage a real fight deals with and without the boon on the same seed.
/// The size of each kind is measured in `tools/balance.py --boons`.
final class BoonTests: XCTestCase {

    // MARK: - Helpers

    private func fighter(_ id: String, level: Int, stars: Int, boon: Boon? = nil) -> ResolvedUnit {
        let blueprint = UnitDatabase.blueprint(id)!
        let unit = Unit(blueprint: blueprint, level: level, stars: stars)
        return ProgressionService.resolve(unit, blueprint: blueprint, equipped: [], boon: boon)
    }

    private func boon(_ family: BoonFamily, _ element: Element? = nil, magnitude: Double? = nil) -> Boon {
        Boon(kind: BoonKind(family, element: element), grade: 6, magnitude: magnitude ?? family.base)
    }

    /// One of the attacker's hits on the target, with both fighters' health
    /// before it landed: what a boon's multiplier is read off.
    private struct Hit {
        var amount: Double
        var targetHealthBefore: Double
        var attackerHealthBefore: Double
    }

    private struct Fight {
        var hits: [Hit]
        var events: [BattleEvent]
        var attackerID: UUID
        var targetID: UUID
        var attackerMax: Double
        var targetMax: Double
    }

    /// A one-on-one on auto from `start()`, the attacker's hits picked out.
    private func fight(_ attacker: ResolvedUnit, _ target: ResolvedUnit, seed: UInt64 = 5) -> Fight {
        let engine = BattleEngine(playerTeam: [attacker], opponentTeam: [target], mode: .simulation, seed: seed)
        engine.autoBattle = true
        let attackerID = engine.team(.player).first!.id
        let targetID = engine.team(.opponent).first!.id
        let attackerMax = engine.team(.player).first!.maxHealth
        let targetMax = engine.team(.opponent).first!.maxHealth
        let events = engine.start()
        var targetHealth = targetMax
        var attackerHealth = attackerMax
        var hits: [Hit] = []
        for event in events {
            switch event {
            case .damage(let source, let victim, let amount, _, _, _, let remaining, _, _):
                if source == attackerID && victim == targetID {
                    hits.append(Hit(amount: amount, targetHealthBefore: targetHealth, attackerHealthBefore: attackerHealth))
                }
                if victim == targetID { targetHealth = remaining }
                if victim == attackerID { attackerHealth = remaining }
            case .healed(_, let victim, _, let remaining):
                if victim == targetID { targetHealth = remaining }
                if victim == attackerID { attackerHealth = remaining }
            default:
                break
            }
        }
        return Fight(hits: hits, events: events, attackerID: attackerID, targetID: targetID,
                     attackerMax: attackerMax, targetMax: targetMax)
    }

    // MARK: - The cache's three doors

    func testACacheOffersThreeDifferentFamiliesAndTheSameThreeEveryTime() {
        let cache = BoonCache(grade: 6, seed: 42)
        let doors = BoonService.offers(for: cache)
        XCTAssertEqual(doors.count, BoonService.cacheOffers)
        XCTAssertEqual(Set(doors.map(\.family)).count, 3, "three different families")
        XCTAssertEqual(doors, BoonService.offers(for: cache), "derived from the seed: the same three on every look")
        for kind in doors {
            XCTAssertEqual(kind.element != nil, kind.family.isElemental, "a Bane or a Ward has a colour; nothing else does")
        }
        // Over many caches every family turns up, and every colour of Bane.
        var families = Set<BoonFamily>()
        var baneColours = Set<Element>()
        for seed in 0..<400 {
            for kind in BoonService.offers(for: BoonCache(grade: 5, seed: UInt64(seed))) {
                families.insert(kind.family)
                if kind.family == .bane, let element = kind.element { baneColours.insert(element) }
            }
        }
        XCTAssertEqual(families, Set(BoonFamily.allCases))
        XCTAssertEqual(baneColours, Set(Element.allCases))
        XCTAssertEqual(BoonKind.all.count, 17, "five Banes, five Wards, seven of no colour")
    }

    func testOpeningACacheRollsTheChosenKindWithinItsRangeAndSpendsTheCache() throws {
        var player = Player()
        let cache = BoonCache(grade: 6, seed: 7, source: "Titan")
        BoonService.addCache(cache, player: &player)
        let doors = BoonService.offers(for: cache)
        var rng = SeededRandom(seed: 3)
        let boon = try BoonService.open(cacheID: cache.id, choice: 1, player: &player, rng: &rng)
        XCTAssertEqual(boon.kind, doors[1])
        XCTAssertEqual(boon.grade, 6)
        let span = BoonService.rollSpan(boon.kind, grade: 6)
        XCTAssertGreaterThanOrEqual(boon.magnitude, span.lowerBound - 1e-9)
        XCTAssertLessThanOrEqual(boon.magnitude, span.upperBound + 1e-9)
        XCTAssertEqual(boon.pushes, 0)
        XCTAssertEqual(player.boonCaches?.count, 0)
        XCTAssertEqual(player.boons?.count, 1)
        XCTAssertThrowsError(try BoonService.open(cacheID: cache.id, choice: 0, player: &player, rng: &rng), "spent")
        // A door that is not one of the three.
        let second = BoonCache(grade: 5, seed: 8)
        BoonService.addCache(second, player: &player)
        XCTAssertThrowsError(try BoonService.open(cacheID: second.id, choice: 3, player: &player, rng: &rng))
        XCTAssertEqual(player.boonCaches?.count, 1, "a refused door spends nothing")
    }

    func testAGradeScalesTheBaseAndEveryKindHasOne() {
        let kind = BoonKind(.giantSlayer)
        XCTAssertEqual(BoonService.base(kind, grade: 6), BoonFamily.giantSlayer.base, accuracy: 1e-9)
        XCTAssertLessThan(BoonService.base(kind, grade: 5), BoonService.base(kind, grade: 6))
        XCTAssertLessThan(BoonService.base(kind, grade: 4), BoonService.base(kind, grade: 5))
        for family in BoonFamily.allCases {
            XCTAssertGreaterThan(family.base, 0, family.rawValue)
            XCTAssertLessThan(family.base, 0.5, "\(family.rawValue): a line, not a second character")
        }
        // The words print the number the engine uses.
        XCTAssertEqual(BoonKind(.bane, element: .tide).line(0.183), "+18.3% damage against Tide")
        XCTAssertEqual(BoonKind(.ward, element: .ember).shortLine(0.12), "−12% from Ember")
        XCTAssertEqual(BoonKind(.swiftFooted).line(0.30), "+30 attack bar when the battle begins")
        XCTAssertEqual(BoonKind(.giantSlayer).displayName, "Giant-slayer")
        XCTAssertEqual(BoonKind(.bane).element, nil, "a Bane with no colour named is still a Bane, of no colour")
    }

    // MARK: - Pushes

    func testAPushCostsDrachmaAndAetherAndOpensAChoiceOfTwoThatOnlyLifts() throws {
        var player = Player()
        player.wallet.drachma = 100_000
        Aether.add(Aether.id(for: .tide), 10, player: &player)
        let boon = Boon(kind: BoonKind(.bane, element: .tide), grade: 6, magnitude: 0.16)
        player.boons = [boon]
        let cost = BoonService.pushCost(for: boon)
        XCTAssertEqual(cost.aetherID, "aether_tide", "a Bane of Tide pushes with the Titans' tide aether")
        XCTAssertEqual(cost.aether, BoonService.pushAether)
        XCTAssertEqual(cost.drachma, BoonService.pushDrachma[6])
        XCTAssertNil(BoonService.pushError(boon, player: player))

        var rng = SeededRandom(seed: 9)
        let pushed = try BoonService.push(boonID: boon.id, player: &player, rng: &rng)
        XCTAssertTrue(pushed.hasPendingRoll)
        XCTAssertEqual(pushed.magnitude, boon.magnitude, "nothing moves until the player chooses")
        XCTAssertEqual(player.wallet.drachma, 100_000 - cost.drachma)
        XCTAssertEqual(Aether.count("aether_tide", player: player), 10 - cost.aether)

        let offers = BoonService.pushCandidates(for: pushed)
        XCTAssertEqual(offers.count, 2)
        XCTAssertEqual(offers, BoonService.pushCandidates(for: pushed), "the same pair on every look")
        let step = BoonService.base(boon.kind, grade: 6) * BoonService.pushStep
        for offer in offers {
            XCTAssertGreaterThanOrEqual(offer.bump, step * BoonService.pushRollRange.lowerBound - 1e-9)
            XCTAssertLessThanOrEqual(offer.bump, step * BoonService.pushRollRange.upperBound + 1e-9)
            XCTAssertEqual(offer.after, pushed.magnitude + offer.bump, accuracy: 1e-9)
        }
        XCTAssertEqual(BoonService.pushError(pushed, player: player), .choiceWaiting, "a second push waits on the first")

        var taken = pushed
        XCTAssertNotNil(BoonService.takePush(&taken, candidate: 0))
        XCTAssertEqual(taken.pushes, 1)
        XCTAssertFalse(taken.hasPendingRoll)
        XCTAssertEqual(taken.magnitude, offers[0].after, accuracy: 1e-9)
        XCTAssertGreaterThan(taken.magnitude, boon.magnitude, "a push only ever lifts")
        XCTAssertNil(BoonService.takePush(&taken, candidate: 0), "nothing waiting")

        taken.pushes = BoonService.maxPushes
        XCTAssertTrue(taken.isFullyPushed)
        XCTAssertEqual(BoonService.pushError(taken, player: player), .fullyPushed)
    }

    func testAKindOfNoColourPushesWithPureAetherAndTheRefusalsName() {
        var player = Player()
        player.wallet.drachma = 100_000
        let boon = Boon(kind: BoonKind(.giantSlayer), grade: 5, magnitude: 0.14)
        let cost = BoonService.pushCost(for: boon)
        XCTAssertEqual(cost.aetherID, Aether.pure)
        XCTAssertEqual(cost.aether, BoonService.pushPureAether)
        XCTAssertEqual(cost.drachma, BoonService.pushDrachma[5])
        XCTAssertEqual(
            BoonService.pushError(boon, player: player),
            .notEnoughAether(id: Aether.pure, needed: BoonService.pushPureAether, held: 0)
        )
        player.wallet.drachma = 0
        XCTAssertEqual(BoonService.pushError(boon, player: player), .notEnoughDrachma(needed: cost.drachma))
    }

    // MARK: - The socket

    func testOneSocketOneBoonAndItMovesBetweenUnits() throws {
        var player = Player()
        let anubis = Unit(blueprint: UnitDatabase.blueprint("anubis_umbra")!)
        let sekhmet = Unit(blueprint: UnitDatabase.blueprint("sekhmet_ember")!)
        player.units = [anubis, sekhmet]
        let bane = Boon(kind: BoonKind(.bane, element: .tide), grade: 6, magnitude: 0.16)
        let ward = Boon(kind: BoonKind(.ward, element: .ember), grade: 5, magnitude: 0.12)
        player.boons = [bane, ward]

        try BoonService.equip(boonID: bane.id, unitID: anubis.id, player: &player)
        XCTAssertEqual(player.unit(anubis.id)?.boonID, bane.id)
        XCTAssertEqual(player.boons?.first(where: { $0.id == bane.id })?.equippedBy, anubis.id)
        XCTAssertEqual(BoonService.worn(by: player.unit(anubis.id)!, player: player)?.id, bane.id)

        // A second boon on the same unit replaces the first.
        try BoonService.equip(boonID: ward.id, unitID: anubis.id, player: &player)
        XCTAssertEqual(player.unit(anubis.id)?.boonID, ward.id)
        XCTAssertNil(player.boons?.first(where: { $0.id == bane.id })?.equippedBy)

        // The same boon on another unit leaves the first.
        try BoonService.equip(boonID: ward.id, unitID: sekhmet.id, player: &player)
        XCTAssertNil(player.unit(anubis.id)?.boonID)
        XCTAssertEqual(player.unit(sekhmet.id)?.boonID, ward.id)

        // It rides into the resolved unit and nowhere into its stats.
        let bare = ProgressionService.resolve(player.unit(sekhmet.id)!, relics: [], boons: [])
        let socketed = ProgressionService.resolve(player.unit(sekhmet.id)!, relics: [], boons: player.boons ?? [])
        XCTAssertEqual(socketed?.boon?.id, ward.id)
        XCTAssertNil(bare?.boon)
        XCTAssertEqual(socketed?.power, bare?.power, "a boon changes no stat")

        BoonService.unequip(unitID: sekhmet.id, player: &player)
        XCTAssertNil(player.unit(sekhmet.id)?.boonID)
        XCTAssertNil(player.boons?.first(where: { $0.id == ward.id })?.equippedBy)

        // Selling takes it out of the socket; a locked one stops the sale.
        try BoonService.equip(boonID: ward.id, unitID: sekhmet.id, player: &player)
        player.boons?[0].isLocked = true
        XCTAssertThrowsError(try BoonService.sell(boonIDs: [bane.id, ward.id], player: &player))
        XCTAssertEqual(player.boons?.count, 2, "a locked boon stops the whole sale")
        let drachmaBefore = player.wallet.drachma
        let paid = try BoonService.sell(boonIDs: [ward.id], player: &player)
        XCTAssertEqual(paid, BoonService.sellValue(ward))
        XCTAssertEqual(player.wallet.drachma, drachmaBefore + paid)
        XCTAssertNil(player.unit(sekhmet.id)?.boonID)
        XCTAssertEqual(player.boons?.count, 1)
    }

    func testTheFitPrefersTheRolesLinesAndABetterRoll() {
        let bane = Boon(kind: BoonKind(.bane, element: .tide), grade: 6, magnitude: 0.16)
        let ward = Boon(kind: BoonKind(.ward, element: .tide), grade: 6, magnitude: 0.16)
        XCTAssertGreaterThan(BoonService.fit(bane, for: .attacker), BoonService.fit(ward, for: .attacker))
        XCTAssertGreaterThan(BoonService.fit(ward, for: .defender), BoonService.fit(bane, for: .defender))
        var better = bane
        better.magnitude = 0.20
        XCTAssertGreaterThan(BoonService.fit(better, for: .attacker), BoonService.fit(bane, for: .attacker))
        for role in CombatRole.allCases {
            for family in BoonFamily.allCases {
                XCTAssertGreaterThan(BoonService.roleWeight(family, role: role), 0, "nothing is worth nothing to anyone")
            }
        }
    }

    // MARK: - The engine's hooks

    func testABaneMultipliesDamageAgainstItsColourAndNothingElse() {
        let plain = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("apep", level: 40, stars: 5))
        let ember = fight(fighter("anubis_umbra", level: 50, stars: 6, boon: boon(.bane, .ember)), fighter("apep", level: 40, stars: 5))
        let tide = fight(fighter("anubis_umbra", level: 50, stars: 6, boon: boon(.bane, .tide)), fighter("apep", level: 40, stars: 5))
        XCTAssertFalse(plain.hits.isEmpty)
        XCTAssertEqual(ember.hits[0].amount / plain.hits[0].amount, 1 + BoonFamily.bane.base, accuracy: 1e-6, "the serpent is ember")
        XCTAssertEqual(tide.hits[0].amount / plain.hits[0].amount, 1, accuracy: 1e-6, "and not tide")
    }

    func testGiantSlayerMultipliesDamageAgainstABossOnly() {
        let plainBoss = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("apep", level: 40, stars: 5))
        let slayerBoss = fight(fighter("anubis_umbra", level: 50, stars: 6, boon: boon(.giantSlayer)), fighter("apep", level: 40, stars: 5))
        XCTAssertEqual(slayerBoss.hits[0].amount / plainBoss.hits[0].amount, 1 + BoonFamily.giantSlayer.base, accuracy: 1e-6)
        let plainGod = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("sekhmet_ember", level: 40, stars: 5))
        let slayerGod = fight(fighter("anubis_umbra", level: 50, stars: 6, boon: boon(.giantSlayer)), fighter("sekhmet_ember", level: 40, stars: 5))
        XCTAssertEqual(slayerGod.hits[0].amount / plainGod.hits[0].amount, 1, accuracy: 1e-6, "a god is not a giant")
    }

    func testFirstBloodLastsUntilTheFirstTurnEnds() {
        let plain = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("apep", level: 40, stars: 5))
        let first = fight(fighter("anubis_umbra", level: 50, stars: 6, boon: boon(.firstBlood)), fighter("apep", level: 40, stars: 5))
        XCTAssertEqual(first.hits[0].amount / plain.hits[0].amount, 1 + BoonFamily.firstBlood.base, accuracy: 1e-6)
        let ratios = zip(first.hits, plain.hits).map { $0.amount / $1.amount }
        XCTAssertTrue(ratios.dropFirst().contains { abs($0 - 1) < 1e-6 }, "a later turn's hit is unboosted")
        XCTAssertFalse(ratios.contains { $0 > 1 + BoonFamily.firstBlood.base + 1e-6 })
    }

    func testExecutionerMultipliesDamageAgainstATargetUnderTheLine() throws {
        let plain = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("apep", level: 40, stars: 5))
        let executioner = fight(fighter("anubis_umbra", level: 50, stars: 6, boon: boon(.executioner)), fighter("apep", level: 40, stars: 5))
        let line = BoonFamily.executionerBelow
        let index = try XCTUnwrap(plain.hits.firstIndex(where: {
            $0.targetHealthBefore / plain.targetMax < line && $0.targetHealthBefore > $0.amount * 1.5
        }), "the serpent should be brought under the line by a hit that does not kill it")
        XCTAssertEqual(executioner.hits[index].amount / plain.hits[index].amount, 1 + BoonFamily.executioner.base, accuracy: 1e-6)
        XCTAssertEqual(executioner.hits[0].amount / plain.hits[0].amount, 1, accuracy: 1e-6, "nothing at full health")
    }

    func testLastStandMultipliesDamageWhileTheAttackerIsUnderTheLine() throws {
        // A stronger serpent, so the attacker is worn under the line.
        let plain = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("apep", level: 60, stars: 5))
        let stand = fight(fighter("anubis_umbra", level: 50, stars: 6, boon: boon(.lastStand)), fighter("apep", level: 60, stars: 5))
        let line = BoonFamily.lastStandBelow
        let index = try XCTUnwrap(plain.hits.firstIndex(where: {
            $0.attackerHealthBefore / plain.attackerMax < line && $0.targetHealthBefore > $0.amount * 1.5
        }), "the attacker should be worn under the line while the serpent still stands")
        XCTAssertEqual(stand.hits[index].amount / plain.hits[index].amount, 1 + BoonFamily.lastStand.base, accuracy: 1e-6)
        XCTAssertEqual(stand.hits[0].amount / plain.hits[0].amount, 1, accuracy: 1e-6, "nothing at full health")
    }

    func testAWardOnTheDefenderTakesLessFromItsColourOnly() {
        let plain = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("apep", level: 40, stars: 5))
        let warded = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("apep", level: 40, stars: 5, boon: boon(.ward, .umbra)))
        let wrongColour = fight(fighter("anubis_umbra", level: 50, stars: 6), fighter("apep", level: 40, stars: 5, boon: boon(.ward, .ember)))
        XCTAssertEqual(warded.hits[0].amount / plain.hits[0].amount, 1 - BoonFamily.ward.base, accuracy: 1e-6)
        XCTAssertEqual(wrongColour.hits[0].amount / plain.hits[0].amount, 1, accuracy: 1e-6)
    }

    func testSwiftFootedFillsTheBarBeforeTheFirstTurn() throws {
        let swift = fight(fighter("anubis_umbra", level: 50, stars: 6, boon: boon(.swiftFooted)), fighter("apep", level: 40, stars: 5))
        let firstTurn = try XCTUnwrap(swift.events.firstIndex(where: {
            if case .turnBegan = $0 { return true }
            return false
        }))
        let headStart = swift.events.prefix(firstTurn).firstIndex(where: {
            if case .attackBarChanged(let target, let delta, _) = $0 {
                return target == swift.attackerID && abs(delta - BoonFamily.swiftFooted.base) < 1e-6
            }
            return false
        })
        XCTAssertNotNil(headStart, "the bar moves at the battle's start, before anyone's turn")
        let named = swift.events.prefix(firstTurn).contains {
            if case .passiveTriggered(let actor, let name) = $0 { return actor == swift.attackerID && name == "Swift-footed" }
            return false
        }
        XCTAssertTrue(named, "and the log says who")
    }

    func testUnfadingHealsAtTheStartOfATurnBegunUnderTheLine() {
        let plain = fight(fighter("sekhmet_ember", level: 50, stars: 6), fighter("apep", level: 50, stars: 5))
        let unfading = fight(fighter("sekhmet_ember", level: 50, stars: 6, boon: boon(.unfading)), fighter("apep", level: 50, stars: 5))
        func selfHeals(_ run: Fight) -> [(before: Double, amount: Double)] {
            var health = run.attackerMax
            var heals: [(before: Double, amount: Double)] = []
            for event in run.events {
                switch event {
                case .damage(_, let victim, _, _, _, _, let remaining, _, _):
                    if victim == run.attackerID { health = remaining }
                case .healed(let source, let victim, let amount, let remaining):
                    if victim == run.attackerID {
                        if source == run.attackerID { heals.append((health, amount)) }
                        health = remaining
                    }
                default:
                    break
                }
            }
            return heals
        }
        XCTAssertTrue(selfHeals(plain).isEmpty, "the lioness has no heal of her own")
        let heals = selfHeals(unfading)
        XCTAssertFalse(heals.isEmpty, "worn under half, she heals")
        for heal in heals {
            XCTAssertLessThan(heal.before / unfading.attackerMax, BoonFamily.unfadingBelow)
            XCTAssertLessThanOrEqual(heal.amount, unfading.attackerMax * BoonFamily.unfading.base + 1e-6)
            XCTAssertGreaterThan(heal.amount, 0)
        }
    }

    func testHydrasBloodRecoversAShareOfTheDamageDealt() {
        let plain = fight(fighter("sekhmet_ember", level: 50, stars: 6), fighter("apep", level: 50, stars: 5))
        let hydra = fight(fighter("sekhmet_ember", level: 50, stars: 6, boon: boon(.hydrasBlood)), fighter("apep", level: 50, stars: 5))
        func lifesteal(_ run: Fight) -> [(healed: Double, dealt: Double)] {
            var dealtThisSkill = 0.0
            var heals: [(healed: Double, dealt: Double)] = []
            for event in run.events {
                switch event {
                case .skillCast(let actor, _, _, _, _, _, _):
                    if actor == run.attackerID { dealtThisSkill = 0 }
                case .damage(let source, let victim, let amount, _, _, _, _, _, _):
                    if source == run.attackerID && victim == run.targetID { dealtThisSkill += amount }
                case .healed(let source, let victim, let amount, _):
                    if source == run.attackerID && victim == run.attackerID { heals.append((amount, dealtThisSkill)) }
                default:
                    break
                }
            }
            return heals
        }
        XCTAssertTrue(lifesteal(plain).isEmpty)
        let heals = lifesteal(hydra)
        XCTAssertFalse(heals.isEmpty, "she recovers once she has something to recover")
        for heal in heals {
            XCTAssertGreaterThan(heal.healed, 0)
            XCTAssertLessThanOrEqual(heal.healed, heal.dealt * BoonFamily.hydrasBlood.base + 1e-6, "never more than the share of what the skill dealt")
        }
    }

    func testTheBoonRidesIntoTheCombatant() {
        let worn = boon(.bane, .tide)
        let anubis = fighter("anubis_umbra", level: 30, stars: 5, boon: worn)
        let engine = BattleEngine(playerTeam: [anubis], opponentTeam: [fighter("apep", level: 30, stars: 5)], mode: .simulation, seed: 1)
        XCTAssertEqual(engine.team(.player).first?.boon?.id, worn.id)
        XCTAssertNil(engine.team(.opponent).first?.boon)
        XCTAssertFalse(engine.team(.player).first?.hasActed ?? true)
    }

    // MARK: - Where the caches come from

    func testTheHardestContentLeavesCachesAndNothingElseDoes() throws {
        let vault = try XCTUnwrap(DungeonDatabase.labyrinth("lab_colossus"))
        XCTAssertNil(vault.levels[8].rewards.boonCacheChance)
        XCTAssertEqual(vault.levels[9].rewards.boonCacheChance, DungeonDatabase.labyrinthBoonChance)
        XCTAssertEqual(vault.levels[9].rewards.boonCacheGrade, DungeonDatabase.labyrinthBoonGrade)
        XCTAssertLessThan(DungeonDatabase.labyrinthBoonGrade, RaidGradeService.titanBoonGrade, "the Titans pay the better cache")
        for hall in DungeonDatabase.halls {
            for floor in hall.floors { XCTAssertNil(floor.rewards.boonCacheChance, "\(floor.id): the essence farm never") }
        }
        for chapter in StageDatabase.chapters {
            for stage in chapter.at(.hell).stages { XCTAssertNil(stage.rewards.boonCacheChance, "\(stage.id): a stage never; the Judgment's chest does") }
        }

        XCTAssertEqual(RaidGradeService.boonCacheChance(for: .a), 0)
        XCTAssertEqual(RaidGradeService.boonCacheChance(for: .s), RaidGradeService.titanBoonChance)
        XCTAssertEqual(RaidGradeService.boonCacheChance(for: .sss), RaidGradeService.titanBoonChance)

        // The Tower's milestones from the twenty-fifth floor, at rising grades.
        func cacheGrade(atFloor floor: Int) -> Int? {
            guard case .bundle(let parts)? = DungeonDatabase.towerMilestoneReward(floor: floor) else { return nil }
            for part in parts { if case .boonCache(let grade) = part { return grade } }
            return nil
        }
        XCTAssertNil(cacheGrade(atFloor: 10))
        XCTAssertEqual(cacheGrade(atFloor: 25), 4)
        XCTAssertEqual(cacheGrade(atFloor: 50), 5)
        XCTAssertEqual(cacheGrade(atFloor: 75), 6)
        XCTAssertEqual(cacheGrade(atFloor: 100), 6)

        // The Judgment on Hell, and only there.
        let chapter = try XCTUnwrap(StageDatabase.chapters.first)
        func cacheGrade(_ tier: CampaignDifficulty, _ milestone: TributeMilestone) -> Int? {
            let tribute = TributeService.tributes(for: chapter.at(tier)).first(where: { $0.milestone == milestone })
            for grant in tribute?.grants ?? [] { if case .boonCache(let grade) = grant { return grade } }
            return nil
        }
        XCTAssertEqual(cacheGrade(.hell, .flawless), 6)
        XCTAssertNil(cacheGrade(.hell, .boss))
        XCTAssertNil(cacheGrade(.hard, .flawless))
        XCTAssertNil(cacheGrade(.normal, .flawless))
    }

    func testATitanAtSAndBetterLeavesASixStarCacheOneKillInFour() throws {
        let raid = try XCTUnwrap(StageDatabase.raids.first)
        var caches = 0
        for seed in 0..<120 {
            var player = Player()
            var rng = SeededRandom(seed: UInt64(seed))
            let result = BattleResult(
                outcome: .victory, turnsTaken: 30, survivorFraction: 1,
                totalDamageDealt: 1, totalDamageTaken: 0, seed: 0, raidShare: 1
            )
            let outcome = CampaignService.applyRewards(stage: raid.stage, result: result, player: &player, rng: &rng)
            XCTAssertTrue((outcome.raidGrade ?? .f) >= .s)
            for cache in outcome.boonCachesEarned {
                XCTAssertEqual(cache.grade, RaidGradeService.titanBoonGrade)
                XCTAssertEqual(cache.source, "Titan")
                caches += 1
            }
            XCTAssertEqual(player.boonCaches?.count ?? 0, outcome.boonCachesEarned.count, "what the receipt shows is what the save holds")
        }
        XCTAssertGreaterThan(caches, 12, "one in four of 120, give or take")
        XCTAssertLessThan(caches, 60)

        // A kill too slow for an S leaves none.
        for seed in 0..<60 {
            var player = Player()
            var rng = SeededRandom(seed: UInt64(seed))
            let slow = BattleResult(
                outcome: .victory, turnsTaken: 140, survivorFraction: 1,
                totalDamageDealt: 1, totalDamageTaken: 0, seed: 0, raidShare: 1
            )
            let outcome = CampaignService.applyRewards(stage: raid.stage, result: slow, player: &player, rng: &rng)
            XCTAssertTrue((outcome.raidGrade ?? .sss) < .s)
            XCTAssertTrue(outcome.boonCachesEarned.isEmpty)
        }
    }

    func testAGrantedCacheLandsInTheSave() {
        var player = Player()
        var rng = SeededRandom(seed: 4)
        let granted = ShopService.grant(.bundle([.divinity(10), .boonCache(grade: 5)]), to: &player, rng: &rng)
        XCTAssertEqual(granted.count, 2)
        XCTAssertEqual(player.boonCaches?.count, 1)
        XCTAssertEqual(player.boonCaches?.first?.grade, 5)
        XCTAssertEqual(ItemArt.key(for: .boonCache(grade: 5)), "boon_cache_5")
        XCTAssertEqual(ItemArt.stars(for: .boonCache(grade: 5)), 5)
    }

    // MARK: - The save

    func testTheFieldsAreOptionalSoAnOldSaveDecodes() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var player = Player()
        player.units = [Unit(blueprint: UnitDatabase.blueprint("anubis_umbra")!)]
        let data = try encoder.encode(player)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"boons\""), "an untouched save writes no key")
        XCTAssertFalse(json.contains("\"boonCaches\""))
        XCTAssertFalse(json.contains("\"boonID\""))
        let back = try decoder.decode(Player.self, from: data)
        XCTAssertNil(back.boons)
        XCTAssertNil(back.boonCaches)
        XCTAssertNil(back.units.first?.boonID)

        var socketed = player
        let boon = Boon(kind: BoonKind(.ward, element: .gale), grade: 6, magnitude: 0.17, pushes: 3)
        socketed.boons = [boon]
        try BoonService.equip(boonID: boon.id, unitID: socketed.units[0].id, player: &socketed)
        BoonService.addCache(BoonCache(grade: 6, seed: 99, source: "Titan"), player: &socketed)
        let again = try decoder.decode(Player.self, from: try encoder.encode(socketed))
        XCTAssertEqual(again.boons?.first?.kind, boon.kind)
        XCTAssertEqual(again.boons?.first?.pushes, 3)
        XCTAssertEqual(again.units.first?.boonID, boon.id)
        XCTAssertEqual(again.boonCaches?.first?.seed, 99)
        XCTAssertEqual(BoonService.offers(for: again.boonCaches![0]), BoonService.offers(for: socketed.boonCaches![0]), "the same three doors after a save")
    }
}
