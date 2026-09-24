import XCTest
@testable import Pantheon

/// Wave 2's battle half, batch B (Docs/FEEL.md W2.2, W2.18, W2.22, W2.24,
/// W2.26): the reward box's tiers and its clock, the trauma shake's bounds,
/// the statuses that land, the pre-draw under the stage card and the frame
/// meter's sums. Every one is a pure function, pinned here so a change to a
/// number fails loudly instead of drifting.
final class BattleFeelTests: XCTestCase {

    private let tolerance: Double = 1e-9

    // MARK: - W2.2 The reward box by rarity

    func testASpoilsTierComesFromWhatItIs() {
        XCTAssertEqual(RewardTier.of(key: "drachma", relic: nil, stars: nil), .plain)
        XCTAssertEqual(RewardTier.of(key: "unit_exp", relic: nil, stars: nil), .plain)
        XCTAssertEqual(RewardTier.of(key: "divinity", relic: nil, stars: nil), .rare, "the premium currency glows")
        XCTAssertEqual(RewardTier.of(key: "scroll_light_dark", relic: nil, stars: nil), .legend)
        XCTAssertEqual(RewardTier.of(key: "scroll_divine", relic: nil, stars: nil), .epic)
        XCTAssertEqual(RewardTier.of(key: "scroll_unknown", relic: nil, stars: nil), .plain)
        XCTAssertEqual(RewardTier.of(key: "scroll_ember", relic: nil, stars: nil), .rare)
        XCTAssertEqual(RewardTier.of(key: "awakening_cache_tide", relic: nil, stars: nil), .epic)
        XCTAssertEqual(RewardTier.of(key: "boon_cache_6", relic: nil, stars: 6), .epic)
        XCTAssertEqual(RewardTier.of(key: "boon_cache_5", relic: nil, stars: 5), .rare)
        XCTAssertEqual(RewardTier.of(key: Aether.pure, relic: nil, stars: nil), .epic)
        XCTAssertEqual(RewardTier.of(key: "essence_ember_high", relic: nil, stars: nil), .rare)
        XCTAssertEqual(RewardTier.of(key: "essence_ember_mid", relic: nil, stars: nil), .plain)
    }

    func testARelicsTierIsItsQuality() {
        XCTAssertEqual(RewardTier.of(quality: .normal), .plain)
        XCTAssertEqual(RewardTier.of(quality: .magic), .plain)
        XCTAssertEqual(RewardTier.of(quality: .rare), .rare)
        XCTAssertEqual(RewardTier.of(quality: .hero), .epic)
        XCTAssertEqual(RewardTier.of(quality: .legend), .legend)
        XCTAssertLessThan(RewardTier.plain, RewardTier.rare)
        XCTAssertLessThan(RewardTier.epic, RewardTier.legend)
    }

    func testTheShelfLandsPlainFirstAndTheBestLast() {
        let loot: [BattleSummary.Loot] = [
            .init(glyph: "sparkles", title: "Divinity", amount: "+15", tint: .marble, key: "divinity"),
            .init(glyph: "circle", title: "Drachma", amount: "+1,240", tint: .gold, key: "drachma"),
            .init(glyph: "scroll", title: "Light & Dark", amount: "+1", tint: .scroll(.lightDark), key: "scroll_light_dark"),
            .init(glyph: "drop", title: "Mid Ember Essence", amount: "+3", tint: .element(.ember), key: "essence_ember_mid"),
            .init(glyph: "scroll", title: "Divine", amount: "+1", tint: .scroll(.divine), key: "scroll_divine"),
        ]
        let ordered = SpoilsShelf.ordered(loot, capacity: 12)
        let titles: [String] = ordered.map { $0.title }
        XCTAssertEqual(titles, ["Drachma", "Mid Ember Essence", "Divinity", "Divine", "Light & Dark"],
                       "plain first in the order they were won, the legend last")
        let tiers = SpoilsShelf.tiers(loot, capacity: 12)
        XCTAssertEqual(tiers, [.plain, .plain, .rare, .epic, .legend])
    }

    func testAScrollWithNoKeyIsKnownByItsTint() {
        let repeatScroll = BattleSummary.Loot(glyph: "scroll", title: "Light & Dark", amount: "+1", tint: .scroll(.lightDark))
        XCTAssertEqual(SpoilsShelf.tier(of: repeatScroll), .legend, "an auto-repeat's summary carries no key")
    }

    func testALongHaulKeepsTheTwelveBest() {
        var loot: [BattleSummary.Loot] = []
        for index in 0..<13 {
            loot.append(.init(glyph: "circle", title: "Drachma \(index)", amount: "+1", tint: .gold, key: "drachma"))
        }
        loot.append(.init(glyph: "scroll", title: "Light & Dark", amount: "+1", tint: .scroll(.lightDark), key: "scroll_light_dark"))
        let shelf = SpoilsShelf.ordered(loot, capacity: 12)
        XCTAssertEqual(shelf.count, 12)
        XCTAssertEqual(shelf.last?.title, "Light & Dark", "the legend is never the one left in the inventory")
    }

    func testEachTileLandsOnItsOwnBeat() {
        let tiers: [RewardTier] = [.plain, .plain, .epic, .legend]
        let landings = SpoilsTimeline.delays(for: tiers)
        let second: TimeInterval = SpoilsTimeline.step
        let epic: TimeInterval = second + SpoilsTimeline.step + SpoilsTimeline.epicPause
        let legend: TimeInterval = epic + SpoilsTimeline.step + SpoilsTimeline.legendPause
        let settled: TimeInterval = legend + SpoilsTimeline.legendLanding
        XCTAssertEqual(landings.count, 4)
        XCTAssertEqual(landings[0], 0, accuracy: tolerance)
        XCTAssertEqual(landings[1], second, accuracy: tolerance)
        XCTAssertEqual(landings[2], epic, accuracy: tolerance, "an epic after a short pause")
        XCTAssertEqual(landings[3], legend, accuracy: tolerance, "the row stops before a legend")
        XCTAssertEqual(SpoilsTimeline.length(of: tiers), settled, accuracy: tolerance)
        XCTAssertEqual(SpoilsTimeline.legendPause, 0.35, accuracy: tolerance, "the spec's 0.35 s stop")
    }

    func testTheChestRattlesThreeTimesBeforeItsLid() {
        XCTAssertEqual(ChestTiming.rattles.count, 3)
        let last: TimeInterval = ChestTiming.rattles.last ?? 0
        let lastEnds: TimeInterval = last + ChestTiming.rattleLength
        XCTAssertLessThanOrEqual(lastEnds, ChestTiming.lid, "the lid goes after the last rattle")
        let swings = ChestTiming.rattleSwing
        XCTAssertEqual(swings.count, 3)
        XCTAssertLessThan(swings[0], swings[1], "each rattle harder")
        XCTAssertLessThan(swings[1], swings[2])
        XCTAssertLessThan(ChestTiming.lidTime(calm: true), ChestTiming.lidTime(calm: false), "no rattles under Reduce Motion")
    }

    func testAChestThatDoesNotRattleOpensAsItAlwaysDid() {
        // The tribute card's chest: its grants are listed as it is claimed,
        // and it has none of the rattles' sounds.
        let light: TimeInterval = ChestTiming.plainLid + ChestTiming.beamAfterLid
        XCTAssertEqual(ChestTiming.plainLid, 0.32, accuracy: tolerance, "the lid a third of a second in, as before W2.2")
        XCTAssertEqual(light, 0.5, accuracy: tolerance, "and its light half a second in")
        XCTAssertLessThan(ChestTiming.plainLid, ChestTiming.lid)
    }

    // MARK: - W2.18 The trauma shake

    func testTheShakeIsTraumaSquaredAndTheRollStaysSmall() {
        let rollLimit: Float = 2.2 * .pi / 180
        XCTAssertLessThanOrEqual(CameraShake.maxRoll, rollLimit, "the owner has twice turned down a slanted camera")
        let still = CameraShake.offsets(trauma: 0, at: 3.3)
        XCTAssertEqual(still.shake, 0)
        XCTAssertEqual(still.roll, 0)
        let half = CameraShake.offsets(trauma: 0.5, at: 3.3)
        XCTAssertEqual(half.shake, 0.25, accuracy: 1e-6)
        let yawLimit: Float = CameraShake.maxYaw
        let shiftLimit: Float = CameraShake.maxShift
        for step in 0..<400 {
            let clock: Double = Double(step) * 0.173
            let full = CameraShake.offsets(trauma: 1, at: clock)
            let roll: Float = abs(full.roll)
            let yaw: Float = abs(full.yaw)
            let pitch: Float = abs(full.pitch)
            let right: Float = abs(full.right)
            let up: Float = abs(full.up)
            XCTAssertLessThanOrEqual(roll, rollLimit)
            XCTAssertLessThanOrEqual(yaw, yawLimit)
            XCTAssertLessThanOrEqual(pitch, CameraShake.maxPitch)
            XCTAssertLessThanOrEqual(right, shiftLimit)
            XCTAssertLessThanOrEqual(up, shiftLimit)
        }
    }

    func testTheNoiseIsSmoothAndBounded() {
        var previous: Double = CameraShake.noise(0)
        for step in 1...2_000 {
            let x: Double = Double(step) * 0.01
            let value: Double = CameraShake.noise(x)
            let jump: Double = abs(value - previous)
            XCTAssertLessThanOrEqual(abs(value), 1)
            XCTAssertLessThan(jump, 0.2, "a hundredth of a cell never jumps: the shake has no corners")
            previous = value
        }
        XCTAssertEqual(CameraShake.noise(7), 0, accuracy: 1e-9, "gradient noise is zero on the lattice")
    }

    func testTheKickGoesOutAndComesHome() {
        XCTAssertEqual(CameraShake.kickEnvelope(0), 0, accuracy: 1e-6)
        XCTAssertEqual(CameraShake.kickEnvelope(CameraShake.kickOut), 1, accuracy: 1e-6)
        XCTAssertEqual(CameraShake.kickEnvelope(CameraShake.kickLength), 0, accuracy: 1e-6)
        XCTAssertEqual(CameraShake.kickEnvelope(-1), 0)
        let normal: Float = Juice.kick(for: .normal, speed: 1)
        let lethal: Float = Juice.kick(for: .lethal, speed: 1)
        XCTAssertEqual(normal, 0.04, accuracy: 1e-6, "4 cm for an ordinary blow")
        XCTAssertEqual(lethal, 0.06, accuracy: 1e-6, "6 cm for a kill")
    }

    func testTraumaGrowsWithTheBlow() {
        let normal: Float = Juice.trauma(for: .normal, speed: 1)
        let heavy: Float = Juice.trauma(for: .heavy, speed: 1)
        let critical: Float = Juice.trauma(for: .critical, speed: 1)
        let lethal: Float = Juice.trauma(for: .lethal, speed: 1)
        XCTAssertEqual(normal, 0.18, accuracy: 1e-6, "the spec's 0.18 for a normal hit")
        XCTAssertLessThan(normal, heavy)
        XCTAssertLessThan(heavy, critical)
        XCTAssertLessThan(critical, lethal)
        XCTAssertLessThanOrEqual(BossEntrance.roarTrauma, 0.8, "up to 0.8 for a boss's landing")
        XCTAssertGreaterThan(BossEntrance.roarTrauma, lethal)
    }

    // MARK: - W2.22 Statuses that land

    func testAUnitThatCannotActWearsItsMark() {
        XCTAssertEqual(HeadMarkKind.of([.stun]), .stars)
        XCTAssertEqual(HeadMarkKind.of([.sleep]), .sleep)
        XCTAssertEqual(HeadMarkKind.of([.sleep, .freeze, .stun]), .frost, "a freeze's frost over the rest")
        XCTAssertEqual(HeadMarkKind.of([.stun, .sleep]), .stars)
        XCTAssertNil(HeadMarkKind.of([.attackUp, .burn]))
        XCTAssertNil(HeadMarkKind.of([]))
    }

    func testAPushFloatsAChipAndARelicsTopUpDoesNot() {
        let pushedBack: Int? = BarPush.chipPercent(delta: -0.5, ichorTopUp: false, nemesisGain: false)
        XCTAssertEqual(pushedBack, -50, "a skill's push back reads")
        let hastened: Int? = BarPush.chipPercent(delta: 0.25, ichorTopUp: false, nemesisGain: false)
        XCTAssertEqual(hastened, 25)
        let ichor: Int? = BarPush.chipPercent(delta: 0.25, ichorTopUp: true, nemesisGain: false)
        XCTAssertNil(ichor, "Ichor's top-up as its wearer's turn opens moves the bar alone")
        let nemesis: Int? = BarPush.chipPercent(delta: 0.04, ichorTopUp: false, nemesisGain: true)
        XCTAssertNil(nemesis, "and Nemesis's on every blow its wearer takes")
        let fallAfterHit: Int? = BarPush.chipPercent(delta: -0.3, ichorTopUp: false, nemesisGain: true)
        XCTAssertEqual(fallAfterHit, -30, "a top-up only gives: a fall straight after a hit is the skill's push")
        let crumb: Int? = BarPush.chipPercent(delta: 0.004, ichorTopUp: false, nemesisGain: false)
        XCTAssertNil(crumb, "a change under half a percent floats nothing")
    }

    // MARK: - W2.24 The way into a fight

    func testThePlanDrawsEveryEffectOnce() {
        let fighters: [PlannedFighter] = [
            PlannedFighter(element: .ember, melee: true, boss: false, auraHex: "#FF8040",
                           effects: ["impact_generic", "lioness_rake", "wrath_of_the_eye"]),
            PlannedFighter(element: .tide, melee: false, boss: false, auraHex: "#40A0FF",
                           effects: ["impact_generic", "thunderbolt"]),
            PlannedFighter(element: .tide, melee: false, boss: false, auraHex: "#40A0FF", effects: ["thunderbolt"]),
            PlannedFighter(element: .umbra, melee: false, boss: true, laterWave: true, auraHex: "#8040FF",
                           effects: ["impact_generic"]),
        ]
        let plan = EffectPlan.of(fighters)
        let names: [String] = plan.effects.map { $0.name }
        XCTAssertEqual(Set(names).count, names.count, "each effect once")
        XCTAssertTrue(names.contains("impact_ember"))
        XCTAssertTrue(names.contains("impact_tide"))
        XCTAssertTrue(names.contains("impact_umbra"), "a boss's hit in its element")
        XCTAssertFalse(names.contains("impact_generic"), "a skill with no effect lands in its caster's element")
        XCTAssertTrue(names.contains("wrath_of_the_eye"))
        XCTAssertTrue(names.contains("slash"), "a melee caster's slash")
        XCTAssertTrue(names.contains("shockwave"), "and the ground under its heavy blow")
        for always in EffectPlan.always {
            XCTAssertTrue(names.contains(always.name))
        }
        XCTAssertEqual(plan.projectiles, [.tide], "one projectile per ranged element; a boss throws none")
        XCTAssertTrue(plan.closes)
        XCTAssertTrue(plan.boss)
        XCTAssertTrue(plan.laterBoss)
    }

    func testThePredrawStepsThroughTheLightCountsThenRetires() {
        let steps = PredrawStep.steps(laterBoss: false)
        XCTAssertEqual(steps, [.lights(1), .lights(2), .lights(3), .retire])
        let bossSteps = PredrawStep.steps(laterBoss: true)
        XCTAssertEqual(bossSteps.last, .retire)
        XCTAssertTrue(bossSteps.contains(.spot(withFlash: false)))
        XCTAssertTrue(bossSteps.contains(.spot(withFlash: true)))
        XCTAssertNil(PredrawStep.step(afterFrame: 1, laterBoss: false), "the effects are drawn alone first")
        XCTAssertEqual(PredrawStep.step(afterFrame: 2, laterBoss: false), .lights(1))
        XCTAssertNil(PredrawStep.step(afterFrame: 3, laterBoss: false))
        XCTAssertEqual(PredrawStep.step(afterFrame: 8, laterBoss: false), .retire)
        XCTAssertNil(PredrawStep.step(afterFrame: 10, laterBoss: false))
        let frames: Int = PredrawStep.frames(laterBoss: false)
        let retireFrame: Int = PredrawStep.framesEach * steps.count
        XCTAssertGreaterThan(frames, retireFrame, "the stage is shown only after the holder is off")
    }

    func testTheCardHoldsItsFloorAndDissolvesFasterAtSpeed() {
        XCTAssertEqual(StageCardTiming.minimumHold, 0.6, accuracy: tolerance, "the spec's 0.6 s floor")
        let normal: TimeInterval = StageCardTiming.dissolve(speed: 1, calm: false)
        let fast: TimeInterval = StageCardTiming.dissolve(speed: 3, calm: false)
        let calm: TimeInterval = StageCardTiming.dissolve(speed: 1, calm: true)
        XCTAssertLessThan(fast, normal)
        XCTAssertLessThan(calm, normal)
        XCTAssertLessThan(StageCardTiming.buildDelay, StageCardTiming.minimumHold)
    }

    func testTheWayOutNeverClosesBeforeItsCardHasArrived() {
        for calm in [false, true] {
            let wait: TimeInterval = StageCardTiming.leaveWait(calm: calm)
            let arrival: TimeInterval = StageCardTiming.arrivalOut(calm: calm)
            let shade: TimeInterval = StageCardTiming.plateDelay + StageCardTiming.shadeFade
            XCTAssertGreaterThan(wait, arrival, "the card has faded up before the cover closes")
            XCTAssertGreaterThanOrEqual(wait, shade, "and its shade with it")
        }
        let calmWait: TimeInterval = StageCardTiming.leaveWait(calm: true)
        let calmPlate: TimeInterval = StageCardTiming.plateDelay + StageCardTiming.plateCalmFade
        let fullWait: TimeInterval = StageCardTiming.leaveWait(calm: false)
        XCTAssertGreaterThanOrEqual(calmWait, calmPlate, "the plate's own fade under Reduce Motion")
        XCTAssertLessThan(calmWait, fullWait, "and a shorter way out than the full one")
    }

    // MARK: - W2.26 Frame pacing

    func testAFrameFallsInItsHalfMillisecondBucket() {
        XCTAssertEqual(FrameMeter.bucket(for: 0.0167), 33)
        XCTAssertEqual(FrameMeter.bucket(for: 0), 0)
        let last: Int = FrameMeter.bucketCount - 1
        XCTAssertEqual(FrameMeter.bucket(for: 5), last, "the last bucket holds every long frame")
    }

    func testThePercentilesReadOffTheHistogram() {
        var counts = [UInt32](repeating: 0, count: FrameMeter.bucketCount)
        counts[33] = 90
        counts[100] = 10
        let p50: Double = FrameMeter.percentile(0.5, of: counts)
        let p95: Double = FrameMeter.percentile(0.95, of: counts)
        let smooth: Double = 33.5 * FrameMeter.bucketWidth
        let hitch: Double = 100.5 * FrameMeter.bucketWidth
        XCTAssertEqual(p50, smooth, accuracy: tolerance)
        XCTAssertEqual(p95, hitch, accuracy: tolerance)
        let empty = [UInt32](repeating: 0, count: FrameMeter.bucketCount)
        XCTAssertEqual(FrameMeter.percentile(0.99, of: empty), 0)
    }

    func testTheMeterCountsFramesAndLeavesOutPauses() {
        let meter = FrameMeter(name: "battle")
        var time: TimeInterval = 100
        meter.record(at: time)
        for _ in 0..<60 {
            time += 1.0 / 60.0
            meter.record(at: time)
        }
        time += 0.05
        meter.record(at: time)
        time += 10
        meter.record(at: time)
        let line: String = meter.report(final: true) ?? ""
        XCTAssertTrue(line.hasPrefix("[Frames] battle p50 16."), line)
        XCTAssertTrue(line.contains("1 over 33 ms of 61"), "the ten-second gap is a pause, not a frame: \(line)")
        XCTAssertTrue(line.hasSuffix("(the stage gone)"))
    }

    func testTheIslandDrawsFasterUnderAFinger() {
        XCTAssertEqual(IslandSceneView.framesPerSecond(interacting: false, choice: .standard), 30)
        XCTAssertEqual(IslandSceneView.framesPerSecond(interacting: true, choice: .standard), 60)
        XCTAssertEqual(IslandSceneView.framesPerSecond(interacting: true, choice: .promotion), 120)
        XCTAssertEqual(IslandSceneView.framesPerSecond(interacting: false, choice: .promotion), 30)
        XCTAssertEqual(IslandSceneView.framesPerSecond(interacting: true, choice: .battery), 30, "a player's cap holds")
    }
}
