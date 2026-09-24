import XCTest
import SwiftUI
@testable import Pantheon

/// The numbers behind the beats drawn over the fight (Docs/FEEL.md W2.1,
/// W2.8–W2.11): when an ultimate owns the screen and for how long at each
/// speed, the band's wipe and the field's shade, a CI frame's hold, the
/// spotlight's shares and its clock, a wave's stamp and its walkers, a
/// death's soul light and a boss's roar. Every one is a pure function in
/// FieldBeats.swift, pinned here beside the scene and the view that read it.
final class FieldBeatsTests: XCTestCase {

    private let tolerance: Double = 1e-9

    // MARK: - The ultimate's splash (W2.1)

    func testTheSplashPlaysByThePlayersChoice() {
        XCTAssertTrue(UltimateSplash.plays(.always, castBefore: false))
        XCTAssertTrue(UltimateSplash.plays(.always, castBefore: true))
        XCTAssertTrue(UltimateSplash.plays(.first, castBefore: false))
        XCTAssertFalse(UltimateSplash.plays(.first, castBefore: true), "First each fight: once for each unit")
        XCTAssertFalse(UltimateSplash.plays(.off, castBefore: false))
    }

    func testTheSplashIsOnUnlessThePlayerChoseOtherwise() {
        let suite = "FieldBeatsTests.splash"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("no defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        let unset: SplashChoice = UltimateSplash.choice(in: defaults)
        XCTAssertEqual(unset, .always, "a player who never opened Settings sees every splash")
        defaults.set(SplashChoice.off.rawValue, forKey: UltimateSplash.key)
        let off: SplashChoice = UltimateSplash.choice(in: defaults)
        XCTAssertEqual(off, .off)
        defaults.set(SplashChoice.first.rawValue, forKey: UltimateSplash.key)
        let first: SplashChoice = UltimateSplash.choice(in: defaults)
        XCTAssertEqual(first, .first)
        defaults.set("sometimes", forKey: UltimateSplash.key)
        let garbled: SplashChoice = UltimateSplash.choice(in: defaults)
        XCTAssertEqual(garbled, .always, "a value this build does not know reads as the default")
        defaults.removePersistentDomain(forName: suite)
    }

    func testTheSplashIsNinetyHundredthsHalvedAtDoubleAndANameFlashAtTriple() {
        let full: TimeInterval = UltimateSplash.duration(of: UltimateSplash.form(speed: 1))
        let brisk: TimeInterval = UltimateSplash.duration(of: UltimateSplash.form(speed: 2))
        let flash: TimeInterval = UltimateSplash.duration(of: UltimateSplash.form(speed: 3))
        let half: TimeInterval = full / 2
        XCTAssertEqual(full, 0.9, accuracy: tolerance)
        XCTAssertEqual(brisk, half, accuracy: tolerance, "×2 halves it, as it halves every beat")
        XCTAssertEqual(flash, 0.3, accuracy: tolerance)
        XCTAssertEqual(UltimateSplash.form(speed: 3), .flash, "×3 keeps the name alone")
    }

    func testTheNameLandsAThirdOfTheWayInAndNotBefore() {
        let lands: TimeInterval = UltimateSplash.landing(of: .full)
        let expected: TimeInterval = 0.9 * 0.34
        let before: Double = UltimateSplash.nameIn(at: 0.33)
        let after: Double = UltimateSplash.nameIn(at: 0.5)
        XCTAssertEqual(lands, expected, accuracy: tolerance)
        XCTAssertEqual(before, 0, accuracy: tolerance)
        XCTAssertEqual(after, 1, accuracy: tolerance)
    }

    func testTheBandWipesInHoldsAndWipesOut() {
        let start: Double = UltimateSplash.sweep(at: 0)
        let held: Double = UltimateSplash.sweep(at: 0.5)
        let gone: Double = UltimateSplash.sweep(at: 1)
        XCTAssertEqual(start, 0, accuracy: tolerance)
        XCTAssertEqual(held, 1, accuracy: tolerance)
        XCTAssertEqual(gone, 2, accuracy: tolerance)
    }

    func testTheBandsShapeIsNothingWholeThenNothing() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let middle = CGPoint(x: 50, y: 25)
        let coming = SplashBand(progress: 0, slant: 10).path(in: rect)
        let whole = SplashBand(progress: 1, slant: 10).path(in: rect)
        let going = SplashBand(progress: 2, slant: 10).path(in: rect)
        XCTAssertFalse(coming.contains(middle))
        XCTAssertTrue(whole.contains(middle))
        XCTAssertTrue(whole.contains(CGPoint(x: 1, y: 1)), "whole, it covers the band to its corners")
        XCTAssertTrue(whole.contains(CGPoint(x: 99, y: 49)))
        XCTAssertFalse(going.contains(middle))
    }

    func testTheFieldDarkensFiftyFivePercentUnderTheBand() {
        let middle: Double = UltimateSplash.shade(at: 0.5, form: .full)
        let first: Double = UltimateSplash.shade(at: 0, form: .full)
        let last: Double = UltimateSplash.shade(at: 1, form: .full)
        XCTAssertEqual(middle, 0.55, accuracy: tolerance)
        XCTAssertEqual(first, 0, accuracy: tolerance)
        XCTAssertEqual(last, 0, accuracy: tolerance)
    }

    func testAHeldBeatStandsStillForItsFrameAndThenRunsOn() {
        let plain: TimeInterval = FieldClock.time(elapsed: 0.7, holdAt: 0.45, frozenFor: 0)
        let during: TimeInterval = FieldClock.time(elapsed: 5, holdAt: 0.45, frozenFor: 16)
        let after: TimeInterval = FieldClock.time(elapsed: 16.7, holdAt: 0.45, frozenFor: 16)
        XCTAssertEqual(plain, 0.7, accuracy: tolerance, "no hold: the clock is the clock")
        XCTAssertEqual(during, 0.45, accuracy: tolerance)
        XCTAssertEqual(after, 0.7, accuracy: 1e-9)
    }

    // MARK: - The spotlight (W2.9)

    func testTheUltimatesSpotlightDimsTheSetAndKeepsTheFiguresLit() {
        let full = Spotlight.shares(for: .ultimate, level: 1)
        let stone: Double = Double(full.setLights)
        let painting: Double = Double(full.backdrop)
        let colour: Double = Double(full.desaturation)
        let figuresKey: Double = Double(full.key + full.figureKey)
        XCTAssertEqual(stone, 0.35, accuracy: 1e-6, "the set's lights fall to 35%")
        XCTAssertEqual(painting, 0.45, accuracy: 1e-6, "the painting to 0.45")
        XCTAssertEqual(colour, 0.35, accuracy: 1e-6, "the colour 0.35 down")
        XCTAssertEqual(figuresKey, 1, accuracy: 1e-6, "the figures keep the key's whole light")
    }

    func testAtRestTheSpotlightChangesNothing() {
        let rest = Spotlight.shares(for: .ultimate, level: 0)
        let entrance = Spotlight.shares(for: .bossEntrance, level: 0)
        XCTAssertEqual(rest, Spotlight.rest)
        XCTAssertEqual(entrance, Spotlight.rest)
        XCTAssertLessThan(Spotlight.backdropRest, 1, "armed off 1, so a dim never builds a shader mid-fight")
    }

    func testTheBossEntranceDimsTheKeyFortyPercentAndNothingElse() {
        let full = Spotlight.shares(for: .bossEntrance, level: 1)
        let key: Double = Double(full.key)
        let stone: Double = Double(full.setLights)
        let colour: Double = Double(full.desaturation)
        XCTAssertEqual(key, 0.6, accuracy: 1e-6)
        XCTAssertEqual(stone, 1, accuracy: 1e-6)
        XCTAssertEqual(colour, 0, accuracy: 1e-6)
    }

    func testTheSpotlightComesInHoldsAndGoesOverFourTenthsAfterTheBlow() {
        var timeline = SpotlightTimeline(look: .ultimate, began: 100, attack: 0.18, longest: 6, release: 0.4)
        let start: Double = timeline.level(at: 100)
        let held: Double = timeline.level(at: 101)
        XCTAssertEqual(start, 0, accuracy: tolerance)
        XCTAssertEqual(held, 1, accuracy: tolerance)
        timeline.releasedAt = 101.5
        let halfway: Double = timeline.level(at: 101.7)
        let gone: Double = timeline.level(at: 102)
        XCTAssertEqual(halfway, 0.5, accuracy: 1e-9)
        XCTAssertEqual(gone, 0, accuracy: tolerance)
        XCTAssertFalse(timeline.isOver(at: 101.8))
        XCTAssertTrue(timeline.isOver(at: 102))
    }

    func testALostReleaseNeverLeavesTheSetDark() {
        let timeline = SpotlightTimeline(look: .ultimate, began: 0, attack: 0.18, longest: Spotlight.longest,
                                         release: Spotlight.releaseAfterBlow)
        let late: Double = timeline.level(at: 7)
        XCTAssertTrue(timeline.isOver(at: 7))
        XCTAssertEqual(late, 0, accuracy: tolerance)
    }

    func testTheBraziersReadTheDim() {
        let dimmer = SetLightDimmer()
        let rest: Double = dimmer.level
        dimmer.level = 0.35
        let dimmed: Double = dimmer.level
        XCTAssertEqual(rest, 1, accuracy: tolerance)
        XCTAssertEqual(dimmed, 0.35, accuracy: tolerance)
    }

    // MARK: - A wave walking on (W2.10)

    func testAWaveIsNamedAndTheLastIsTheFinalWave() {
        let second = WaveStampCue(serial: 1, wave: 2, count: 3, duration: 1.3, frozenFor: 0)
        let third = WaveStampCue(serial: 2, wave: 3, count: 3, duration: 1.3, frozenFor: 0)
        XCTAssertEqual(second.word, "WAVE 2")
        XCTAssertFalse(second.isFinal)
        XCTAssertEqual(third.word, "FINAL WAVE")
        XCTAssertTrue(third.isFinal)
    }

    func testTheStampIsHalfAsLongFastAndOnlyTheStampPlaysAtTriple() {
        let single: TimeInterval = WaveStamp.length(speed: 1)
        let triple: TimeInterval = WaveStamp.length(speed: 3)
        let half: TimeInterval = single / 2
        XCTAssertEqual(triple, half, accuracy: tolerance)
        XCTAssertTrue(WalkOn.walks(hasClip: true, speed: 1))
        XCTAssertTrue(WalkOn.walks(hasClip: true, speed: 2))
        XCTAssertFalse(WalkOn.walks(hasClip: true, speed: 3), "at ×3 only the stamp plays")
        XCTAssertFalse(WalkOn.walks(hasClip: false, speed: 1), "a rig with no walk glides on as before")
    }

    func testAnArrivalWalksAtTheStrideOfItsHeight() {
        let hero: TimeInterval = WalkOn.duration(distance: 2, height: 1.9)
        let expected: TimeInterval = 2 / 1.05
        let tall: TimeInterval = WalkOn.duration(distance: 2, height: 2.85)
        XCTAssertEqual(hero, expected, accuracy: 1e-9, "the island's own stroll for a hero's height")
        XCTAssertLessThan(tall, hero, "a longer stride covers the two metres sooner")
    }

    func testOnlyANewWaveWithNoBossIsStamped() {
        XCTAssertTrue(WaveStamp.stamps(wave: 2, onField: 1, bossArrives: false), "WAVE 2")
        XCTAssertTrue(WaveStamp.stamps(wave: 3, onField: 2, bossArrives: false), "FINAL WAVE")
        XCTAssertFalse(WaveStamp.stamps(wave: 3, onField: 2, bossArrives: true),
                       "a boss's wave is announced by its entrance")
        XCTAssertFalse(WaveStamp.stamps(wave: 1, onField: 1, bossArrives: false),
                       "a raid's guard coming back is no new wave (it was stamped FINAL WAVE)")
        XCTAssertFalse(WaveStamp.stamps(wave: 3, onField: 3, bossArrives: false),
                       "nor is a guard called on the last wave")
    }

    func testTheStampLandsFromTheRightAndLeavesToTheLeft() {
        let entering: Double = WaveStamp.travel(at: 0)
        let landed: Double = WaveStamp.travel(at: WaveStamp.landsAt)
        let leaving: Double = WaveStamp.travel(at: 1)
        XCTAssertGreaterThan(entering, 0)
        XCTAssertEqual(landed, 0, accuracy: tolerance)
        XCTAssertLessThan(leaving, 0)
    }

    // MARK: - The boss's line (W2.10, W2.11)

    /// Every chapter's boss says its line as it walks on — on the final wave,
    /// after that wave's stamp — however many mobs of its kind came before
    /// it: Ammit, the cyclops, the medusa, the berserker, the frost troll,
    /// the centurion and the fox spirit all walk on early as mobs, and the
    /// first of them used to say the boss's line for it, over its wave's
    /// stamp.
    func testEveryChaptersBossSpeaksOnTheWaveItWalksOnWith() {
        var checked = 0
        for chapter in StageDatabase.chapters where !chapter.bossLine.isEmpty && !chapter.bossBlueprintID.isEmpty {
            guard let stage = chapter.stages.last(where: { $0.isBoss }) else { continue }
            let finalWave: Int = 1 + stage.laterWaves.count
            let spoken: Int = stage.speakerWave(of: chapter.bossBlueprintID)
            XCTAssertEqual(spoken, finalWave, "\(chapter.id): the boss speaks as it arrives")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no chapter has a boss's line to check")
    }

    func testAMobOfTheBossesKindDoesNotSpeakForIt() throws {
        let chapter = try XCTUnwrap(StageDatabase.chapters.first(where: { !$0.bossBlueprintID.isEmpty }))
        var stage = try XCTUnwrap(chapter.stages.last(where: { $0.isBoss }))
        let first = try XCTUnwrap(stage.enemies.first)
        stage.enemies[0] = EnemySpawn(blueprintID: chapter.bossBlueprintID, level: first.level, stars: first.stars)
        let finalWave: Int = 1 + stage.laterWaves.count
        let spoken: Int = stage.speakerWave(of: chapter.bossBlueprintID)
        let nobody: Int = stage.speakerWave(of: "no_such_blueprint")
        XCTAssertEqual(spoken, finalWave, "the first wave's mob of its kind does not speak for the boss")
        XCTAssertEqual(nobody, 1)
    }

    func testATitanSpeaksAsItsRaidOpens() {
        for encounter in StageDatabase.raids {
            guard let titan = encounter.stage.enemies.first(where: { $0.raid != nil }) else { continue }
            let spoken: Int = encounter.stage.speakerWave(of: titan.blueprintID)
            XCTAssertEqual(spoken, 1, encounter.id)
        }
    }

    // MARK: - Leaving the field (W2.8) and the boss's entrance (W2.11)

    func testTheSoulLightRisesOnlyWhereMotionIsWelcome() {
        XCTAssertTrue(Dissolve.showsSoulLight(speed: 1, calm: false))
        XCTAssertTrue(Dissolve.showsSoulLight(speed: 2, calm: false))
        XCTAssertFalse(Dissolve.showsSoulLight(speed: 1, calm: true), "never under Reduce Motion")
        XCTAssertFalse(Dissolve.showsSoulLight(speed: 3, calm: false), "never at ×3")
    }

    func testTheBossRoarsHalfWayThroughItsEntrance() {
        let half: TimeInterval = BossEntrance.length / 2
        XCTAssertEqual(BossEntrance.length, 2.4, accuracy: tolerance)
        XCTAssertEqual(BossEntrance.roarAt, half, accuracy: tolerance)
    }
}
