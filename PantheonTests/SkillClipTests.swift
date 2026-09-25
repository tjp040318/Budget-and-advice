import XCTest
@testable import Pantheon

/// Which clip a skill plays (Docs/PLAN.md *Skills that look like
/// themselves*): the rule by the skill's shape (`AnimationClip.forSkill`),
/// the real kits read through it (`Skill.presentedClip`), the engine putting
/// it on every cast, and the chain a family without the clip falls down
/// (`ModelLibrary.resolvedClip`). Every value an assert compares is hoisted
/// into a typed `let` first (CLAUDE.md: an assert's parentheses stay free of
/// arithmetic).
final class SkillClipTests: XCTestCase {

    private let tolerance: Double = 1e-9

    // MARK: - The rule

    /// The first skill is the family's signature basic and the third its
    /// signature ultimate, whatever they do.
    func testTheBasicAndTheThirdSkillAreTheSignatures() {
        let twoCutBasic: AnimationClip = AnimationClip.forSkill(slot: 0, hits: 2, target: .singleEnemy, isRite: false)
        let lineBasic: AnimationClip = AnimationClip.forSkill(slot: 0, hits: 1, target: .allEnemies, isRite: false)
        let third: AnimationClip = AnimationClip.forSkill(slot: 2, hits: 1, target: .allEnemies, isRite: false)
        let thirdFlurry: AnimationClip = AnimationClip.forSkill(slot: 2, hits: 5, target: .singleEnemy, isRite: false)
        let thirdRite: AnimationClip = AnimationClip.forSkill(slot: 2, hits: 0, target: .allAllies, isRite: true)
        let fourth: AnimationClip = AnimationClip.forSkill(slot: 3, hits: 1, target: .singleEnemy, isRite: false)
        XCTAssertEqual(twoCutBasic, .attackBasic, "a duelist's two cuts are in its basic's contacts")
        XCTAssertEqual(lineBasic, .attackBasic)
        XCTAssertEqual(third, .ultimate)
        XCTAssertEqual(thirdFlurry, .ultimate)
        XCTAssertEqual(thirdRite, .ultimate, "the third skill is the signature, a rite or a blow")
        XCTAssertEqual(fourth, .ultimate)
    }

    /// The second skill plays its shape: a rite is a rite, a blow on the
    /// whole line is an area blow, two to five strikes are that many, and
    /// one strike is the heavy blow.
    func testTheSecondSkillPlaysItsShape() {
        let heal: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 0, target: .allAllies, isRite: true)
        let curse: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 0, target: .allEnemies, isRite: true)
        let sweep: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 1, target: .allEnemies, isRite: false)
        let sweepTwice: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 2, target: .allEnemies, isRite: false)
        let blow: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 1, target: .singleEnemy, isRite: false)
        let noHits: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 0, target: .singleEnemy, isRite: false)
        let two: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 2, target: .singleEnemy, isRite: false)
        let three: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 3, target: .singleEnemy, isRite: false)
        let four: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 4, target: .lowestHealthEnemy, isRite: false)
        let five: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 5, target: .singleEnemy, isRite: false)
        let seven: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 7, target: .singleEnemy, isRite: false)
        let randomThree: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 3, target: .randomEnemies(count: 3), isRite: false)
        let randomOne: AnimationClip = AnimationClip.forSkill(slot: 1, hits: 1, target: .randomEnemies(count: 2), isRite: false)
        XCTAssertEqual(heal, .castRelease)
        XCTAssertEqual(curse, .castRelease, "a rite on the enemy line is still a rite: no damage, no blow")
        XCTAssertEqual(sweep, .skillArea)
        XCTAssertEqual(sweepTwice, .skillArea, "the line is one blow over the row, however many times it lands")
        XCTAssertEqual(blow, .attackHeavy)
        XCTAssertEqual(noHits, .attackHeavy, "a damage spec of no hits still lands once")
        XCTAssertEqual(two, .skillX2)
        XCTAssertEqual(three, .skillX3)
        XCTAssertEqual(four, .skillX4)
        XCTAssertEqual(five, .skillX5)
        XCTAssertEqual(seven, .skillX5, "more than five strikes are the five-strike shape")
        XCTAssertEqual(randomThree, .skillX3, "random targets strike their count like any other")
        XCTAssertEqual(randomOne, .attackHeavy)
    }

    // MARK: - The real kits

    /// A skill of a real blueprint, by its slot.
    private func skill(_ blueprintID: String, slot: Int) throws -> Skill {
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint(blueprintID), "\(blueprintID) is in the registry")
        return try XCTUnwrap(blueprint.skills.first { $0.slot == slot && !$0.isPassive },
                             "\(blueprintID) has an active skill in slot \(slot)")
    }

    /// The table families' second and third skills, read as the battle
    /// reads them: the kit keeps its stored clip, and the cast plays the
    /// shape.
    func testTheKitsSkillsPlayTheirShapes() throws {
        // A duelist's gale form: Four Cuts.
        let fourCuts = try skill("horus_gale", slot: 1)
        let fourCutsStored: AnimationClip = fourCuts.animation
        let fourCutsPlayed: AnimationClip = fourCuts.presentedClip
        XCTAssertEqual(fourCutsStored, .attackHeavy, "the data is unchanged")
        XCTAssertEqual(fourCutsPlayed, .skillX4)

        // An oracle's line.
        let line: AnimationClip = try skill("hathor_ember", slot: 1).presentedClip
        XCTAssertEqual(line, .skillArea)

        // A healer's heal, and the same healer's dark form, which strikes.
        let heal = try skill("isis_tide", slot: 1)
        let healPlayed: AnimationClip = heal.presentedClip
        let darkStrike: AnimationClip = try skill("isis_umbra", slot: 1).presentedClip
        XCTAssertNil(heal.damage)
        XCTAssertEqual(healPlayed, .castRelease)
        XCTAssertEqual(darkStrike, .attackHeavy, "a blow that heals the team is still a blow")

        // A guardian's shield wall.
        let wall: AnimationClip = try skill("athena_tide", slot: 1).presentedClip
        XCTAssertEqual(wall, .castRelease)

        // A striker: two blows, one crushing blow, and the third.
        let twoBlows: AnimationClip = try skill("thor_ember", slot: 1).presentedClip
        let crushing: AnimationClip = try skill("thor_tide", slot: 1).presentedClip
        let strikerThird: AnimationClip = try skill("thor_ember", slot: 2).presentedClip
        XCTAssertEqual(twoBlows, .skillX2)
        XCTAssertEqual(crushing, .attackHeavy)
        XCTAssertEqual(strikerThird, .ultimate)

        // A marksman: three shots and five at random, two at one enemy.
        let threeShots: AnimationClip = try skill("artemis_tide", slot: 1).presentedClip
        let fiveShots: AnimationClip = try skill("artemis_gale", slot: 1).presentedClip
        let twoShots: AnimationClip = try skill("artemis_ember", slot: 1).presentedClip
        XCTAssertEqual(threeShots, .skillX3)
        XCTAssertEqual(fiveShots, .skillX5)
        XCTAssertEqual(twoShots, .skillX2)

        // A healer's third skill is a rite and still the signature.
        let healerThird: AnimationClip = try skill("isis_ember", slot: 2).presentedClip
        XCTAssertEqual(healerThird, .ultimate)
    }

    /// Every kit's second skill in every element plays the shape its words
    /// describe (`UnitDatabase.elementalSkill`, one family per kit), and
    /// every third skill the ultimate.
    func testEveryKitsSecondSkillPlaysItsShapeInEveryElement() throws {
        // Ember, tide, gale, radiance, umbra: `Element.allCases`' order.
        let kits: [(family: String, kit: String, secondSkills: [AnimationClip])] = [
            ("thor", "striker", [.skillX2, .attackHeavy, .skillX3, .attackHeavy, .attackHeavy]),
            ("horus", "duelist", [.attackHeavy, .skillX2, .skillX4, .attackHeavy, .attackHeavy]),
            ("artemis", "marksman", [.skillX2, .skillX3, .skillX5, .attackHeavy, .attackHeavy]),
            ("poseidon", "bruiser", [.attackHeavy, .skillArea, .attackHeavy, .attackHeavy, .attackHeavy]),
            ("athena", "warden", [.attackHeavy, .castRelease, .castRelease, .castRelease, .attackHeavy]),
            ("isis", "healer", [.castRelease, .castRelease, .castRelease, .castRelease, .attackHeavy]),
            ("hathor", "oracle", [.skillArea, .skillArea, .skillArea, .skillArea, .skillArea]),
            ("hades", "trickster", [.attackHeavy, .attackHeavy, .attackHeavy, .attackHeavy, .attackHeavy]),
        ]
        for row in kits {
            for (element, expected) in zip(Element.allCases, row.secondSkills) {
                let id = "\(row.family)_\(element.rawValue)"
                let second: AnimationClip = try skill(id, slot: 1).presentedClip
                let third: AnimationClip = try skill(id, slot: 2).presentedClip
                XCTAssertEqual(second, expected, "\(row.kit) \(id)")
                XCTAssertEqual(third, .ultimate, "\(row.kit) \(id)")
            }
        }
    }

    /// Every summonable form's every active skill plays a clip of its slot:
    /// the basic its own, the third the ultimate, and the second never either
    /// of those — a rite always the rite, a blow never the rite.
    func testEveryRosterSkillPlaysAClipOfItsSlot() {
        var secondSkills = 0
        for blueprint in UnitDatabase.roster {
            for skill in blueprint.skills where !skill.isPassive {
                let played: AnimationClip = skill.presentedClip
                let label = "\(blueprint.id) slot \(skill.slot) \(skill.name)"
                if skill.slot == 0 {
                    XCTAssertEqual(played, .attackBasic, label)
                } else if skill.slot >= 2 {
                    XCTAssertEqual(played, .ultimate, label)
                } else {
                    secondSkills += 1
                    XCTAssertNotEqual(played, .attackBasic, label)
                    XCTAssertNotEqual(played, .ultimate, label)
                    let isRite: Bool = skill.damage == nil
                    let playsTheRite: Bool = played == .castRelease
                    XCTAssertEqual(playsTheRite, isRite, label)
                }
            }
        }
        XCTAssertGreaterThan(secondSkills, 100, "the roster's second skills were all read")
    }

    // MARK: - The engine

    private func unit(_ blueprintID: String, level: Int = 40, stars: Int = 6) throws -> ResolvedUnit {
        let blueprint = try XCTUnwrap(UnitDatabase.blueprint(blueprintID), "\(blueprintID) is in the registry")
        let unit = Unit(blueprint: blueprint, level: level, stars: stars, awakened: false)
        return ProgressionService.resolve(unit, blueprint: blueprint, equipped: [])
    }

    /// The clip the engine put on the first cast by `actor` in `events`.
    private func castClip(by actor: UUID, in events: [BattleEvent]) -> AnimationClip? {
        for event in events {
            if case .skillCast(let caster, _, _, _, _, let animation, _) = event, caster == actor {
                return animation
            }
        }
        return nil
    }

    /// The engine's cast carries the shape, not the stored clip: Horus's
    /// Four Cuts is cast as four strikes, and Isis's heal as the rite.
    func testTheEngineCastsTheSkillsShape() throws {
        let horus = try unit("horus_gale")
        let wall = try unit("sandstone_sentinel")
        let duel = BattleEngine(playerTeam: [horus], opponentTeam: [wall], mode: .campaign, seed: 5)
        _ = duel.start()
        let horusID = try XCTUnwrap(duel.awaitingActor, "Horus is the one unit the player moves")
        let cuts = duel.submit(BattleAction(actorID: horusID, skillSlot: 1, targetID: nil))
        let cutsClip: AnimationClip? = castClip(by: horusID, in: cuts)
        XCTAssertEqual(cutsClip, .skillX4)

        let isis = try unit("isis_tide")
        let isisWall = try unit("sandstone_sentinel")
        let rite = BattleEngine(playerTeam: [isis], opponentTeam: [isisWall], mode: .campaign, seed: 9)
        _ = rite.start()
        let isisID = try XCTUnwrap(rite.awaitingActor, "Isis is the one unit the player moves")
        let heal = rite.submit(BattleAction(actorID: isisID, skillSlot: 1, targetID: nil))
        let healClip: AnimationClip? = castClip(by: isisID, in: heal)
        XCTAssertEqual(healClip, .castRelease)
    }

    // MARK: - The shapes as clips

    /// The shapes are files of their own named for their shape, and the
    /// battle's contract gives a strike 0.4 s more.
    func testTheShapesAreFilesOfTheirOwn() {
        let names: [String] = [AnimationClip.skillX2, .skillX3, .skillX4, .skillX5, .skillArea].map(\.rawValue)
        XCTAssertEqual(names, ["skill_x2", "skill_x3", "skill_x4", "skill_x5", "skill_area"])
        let strikes: [Int] = [AnimationClip.skillX2, .skillX3, .skillX4, .skillX5, .skillArea, .attackHeavy].map(\.strikeCount)
        XCTAssertEqual(strikes, [2, 3, 4, 5, 1, 1])

        let x2: TimeInterval = AnimationClip.skillX2.fallbackDuration
        let x3: TimeInterval = AnimationClip.skillX3.fallbackDuration
        let x4: TimeInterval = AnimationClip.skillX4.fallbackDuration
        let x5: TimeInterval = AnimationClip.skillX5.fallbackDuration
        let area: TimeInterval = AnimationClip.skillArea.fallbackDuration
        let rite: TimeInterval = AnimationClip.castRelease.fallbackDuration
        let heavy: TimeInterval = AnimationClip.attackHeavy.fallbackDuration
        XCTAssertEqual(x2, 2.0, accuracy: tolerance)
        XCTAssertEqual(x3, 2.4, accuracy: tolerance)
        XCTAssertEqual(x4, 2.8, accuracy: tolerance)
        XCTAssertEqual(x5, 3.2, accuracy: tolerance)
        XCTAssertEqual(area, 2.2, accuracy: tolerance)
        XCTAssertEqual(rite, 2.2, accuracy: tolerance)
        XCTAssertEqual(heavy, 1.7, accuracy: tolerance, "the heavy blow keeps its time")
    }

    /// The shapes and the rite are only ever files of their own, so a
    /// family without one never has its mesh opened to look; the battle
    /// still warms and plays them, which only the stages' two are left out
    /// of.
    func testTheSkillClipsAreNeverLookedForInsideTheMesh() {
        let ownFile: [AnimationClip] = [.skillX2, .skillX3, .skillX4, .skillX5, .skillArea, .castRelease, .idleAlt, .idleBreak]
        for clip in ownFile {
            XCTAssertTrue(clip.onlyInOwnFile, clip.rawValue)
        }
        let inTheMesh: [AnimationClip] = [.attackBasic, .attackHeavy, .ultimate, .idle, .idleCombat, .hitReact, .death, .victory, .walk]
        for clip in inTheMesh {
            XCTAssertFalse(clip.onlyInOwnFile, clip.rawValue)
        }
        let warmed: [AnimationClip] = [.skillX2, .skillX3, .skillX4, .skillX5, .skillArea, .castRelease]
        for clip in warmed {
            XCTAssertFalse(clip.shipsAsItsOwnFile, "\(clip.rawValue) is warmed and played by the battle")
        }
        for clip in AnimationClip.allCases where clip.shipsAsItsOwnFile {
            XCTAssertTrue(clip.onlyInOwnFile, "\(clip.rawValue): a stage-only clip is never searched for in the mesh")
        }
    }

    /// A shape falls back to the heavy blow; the rite never falls back to a
    /// blow; nothing else falls back at all.
    func testTheFallbackChain() {
        let shapes: [AnimationClip] = [.skillX2, .skillX3, .skillX4, .skillX5, .skillArea]
        for shape in shapes {
            let fallback: AnimationClip? = shape.fallbackClip
            XCTAssertEqual(fallback, .attackHeavy, shape.rawValue)
        }
        let standalone: [AnimationClip] = [.castRelease, .attackBasic, .attackHeavy, .ultimate, .hitReact, .death, .idle]
        for clip in standalone {
            let fallback: AnimationClip? = clip.fallbackClip
            XCTAssertNil(fallback, clip.rawValue)
        }
    }

    // MARK: - The chain on the bundle

    /// A family that ships its heavy blow and not a shape plays the heavy
    /// blow for it; one that ships the shape plays the shape. Written both
    /// ways so it stays true as the shapes ship. And resolving twice is
    /// resolving once, so the battle may hand `UnitNode.play` the clip it
    /// asked for or the one it resolved.
    func testAShapeTheFamilyDidNotShipPlaysItsHeavyBlow() {
        let library = ModelLibrary.shared
        let shapes: [AnimationClip] = [.skillX2, .skillX3, .skillX4, .skillX5, .skillArea]
        for asset in ["ares", "horus", "thor", "artemis", "hathor"] {
            XCTAssertTrue(library.hasClipFile(.attackHeavy, for: asset), "\(asset) ships a heavy blow")
            for shape in shapes {
                let resolved: AnimationClip = library.resolvedClip(shape, for: asset)
                let ships: Bool = library.hasClipFile(shape, for: asset)
                let expected: AnimationClip = ships ? shape : .attackHeavy
                let again: AnimationClip = library.resolvedClip(resolved, for: asset)
                XCTAssertEqual(resolved, expected, "\(asset) \(shape.rawValue)")
                XCTAssertEqual(again, resolved, "\(asset) \(shape.rawValue) resolves to itself")
            }
        }
    }

    /// The rite never becomes a blow: a family without it keeps the rite,
    /// which plays as procedural motion.
    func testTheRiteNeverFallsBackToABlow() {
        let library = ModelLibrary.shared
        for asset in ["isis", "hathor", "zeus", "athena"] {
            let resolved: AnimationClip = library.resolvedClip(.castRelease, for: asset)
            XCTAssertEqual(resolved, .castRelease, asset)
        }
    }

    /// With neither the shape nor a heavy blow the shape stands — the
    /// procedural flurry, timed by the same numbers the battle presents the
    /// hits on — and asking again gives the same answer from the miss
    /// remembered the first time.
    func testAFamilyWithNeitherClipKeepsTheShape() {
        let library = ModelLibrary.shared
        let nobody = "skill_clip_tests_nobody"
        let first: AnimationClip = library.resolvedClip(.skillX3, for: nobody)
        let again: AnimationClip = library.resolvedClip(.skillX3, for: nobody)
        let area: AnimationClip = library.resolvedClip(.skillArea, for: nobody)
        XCTAssertEqual(first, .skillX3)
        XCTAssertEqual(again, .skillX3)
        XCTAssertEqual(area, .skillArea)
        XCTAssertNil(library.animation(.skillX3, for: nobody))
    }

    /// A clip with no fallback is itself, shipped or not.
    func testAClipWithoutAFallbackIsItself() {
        let library = ModelLibrary.shared
        let clips: [AnimationClip] = [.attackBasic, .attackHeavy, .ultimate, .castRelease, .hitReact, .idleCombat]
        for clip in clips {
            let resolved: AnimationClip = library.resolvedClip(clip, for: "ares")
            XCTAssertEqual(resolved, clip, clip.rawValue)
        }
    }
}
