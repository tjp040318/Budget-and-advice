import XCTest
import SceneKit
import SwiftUI
@testable import Pantheon

/// The summon's Wave 2 (2026-09-24, Docs/FEEL.md): the figure's entrance
/// (W2.4), the carved name card (W2.13), the Skip that never swallows a 5★
/// (W2.23) and the sound that climbs with the grade (W2.7) — their pure
/// parts, which a CI frame cannot show. Every figure an assert compares is
/// hoisted into a typed `let` first (CLAUDE.md: an assert's parentheses
/// stay free of arithmetic).
final class SummonRevealFeelTests: XCTestCase {

    // MARK: - W2.4 The entrance

    /// Each of the motion palette's three victory presets is found by the
    /// length SceneKit reports for it (run 246's console: 1.90, 3.93, 3.87).
    func testEachPresetIsFoundByItsLength() {
        let cheer: RevealEntranceCut = RevealEntrance.cut(forClipLength: 1.90)
        let victory: RevealEntranceCut = RevealEntrance.cut(forClipLength: 3.9333)
        let pound: RevealEntranceCut = RevealEntrance.cut(forClipLength: 3.8667)
        let nearVictory: RevealEntranceCut = RevealEntrance.cut(forClipLength: 3.92)
        XCTAssertEqual(cheer, RevealEntrance.cheer)
        XCTAssertEqual(victory, RevealEntrance.victory)
        XCTAssertEqual(pound, RevealEntrance.chestPound)
        XCTAssertEqual(nearVictory, RevealEntrance.victory)
    }

    /// The shipped clips of three families, one per preset, are read as
    /// their preset: if SceneKit ever reports a clip's length another way,
    /// this fails before the reveal plays the wrong seconds of it.
    func testTheShippedVictoriesAreReadAsTheirPresets() throws {
        let families: [(asset: String, preset: RevealEntranceCut)] = [
            ("sekhmet", RevealEntrance.cheer),
            ("ares", RevealEntrance.victory),
            ("anubis", RevealEntrance.chestPound),
        ]
        for family in families {
            let clip = try XCTUnwrap(ModelLibrary.shared.animation(.victory, for: family.asset),
                                     "\(family.asset) ships a victory clip")
            let length: TimeInterval = clip.duration
            let cut: RevealEntranceCut = RevealEntrance.cut(forClipLength: length)
            XCTAssertEqual(cut, family.preset, "\(family.asset)'s victory is \(length) s")
        }
    }

    /// Every preset's window starts before its high point, which comes
    /// before it lets go, and the blend back into the idle ends inside the
    /// clip.
    func testEveryWindowFitsItsClip() {
        for preset in RevealEntrance.presets {
            let cut: RevealEntranceCut = preset.cut
            let blendEnds: TimeInterval = cut.end + RevealEntrance.blendOut
            let clipEnds: TimeInterval = preset.length + 0.001
            XCTAssertLessThan(cut.start, cut.apex, cut.preset)
            XCTAssertLessThan(cut.apex, cut.end, cut.preset)
            XCTAssertLessThanOrEqual(blendEnds, clipEnds, "\(cut.preset): the blend into the idle runs past the clip")
        }
    }

    /// A clip no preset made still gets a high point inside its window.
    func testAnUnmeasuredClipHasAHighPointInsideIt() {
        let lengths: [TimeInterval] = [0.6, 1.2, 2.5, 5.0, 9.0]
        for length in lengths {
            let cut: RevealEntranceCut = RevealEntrance.cut(forClipLength: length)
            XCTAssertEqual(cut.preset, "unmeasured")
            XCTAssertGreaterThan(cut.apex, 0)
            XCTAssertLessThan(cut.apex, cut.end, "a \(length) s clip")
        }
    }

    /// The hold at the flash: 70 ms, and 110 ms for a 5★.
    func testTheHoldIsLongerForAFiveStar() {
        let five: TimeInterval = RevealEntrance.hold(stars: 5)
        let four: TimeInterval = RevealEntrance.hold(stars: 4)
        let three: TimeInterval = RevealEntrance.hold(stars: 3)
        XCTAssertEqual(five, 0.11, accuracy: 1e-9)
        XCTAssertEqual(four, 0.07, accuracy: 1e-9)
        XCTAssertEqual(three, 0.07, accuracy: 1e-9)
    }

    /// The camera's kick comes home on a spring: from 0 to exactly 1, past
    /// 1 by a few per cent on the way.
    func testTheKickSpringsHomeWithASmallOvershoot() {
        let start: Float = RevealEntrance.kickReturn(0)
        let end: Float = RevealEntrance.kickReturn(1)
        XCTAssertEqual(start, 0, accuracy: 1e-5)
        XCTAssertEqual(end, 1, accuracy: 1e-5)
        var peak: Float = 0
        for step in 0...100 {
            let progress: Float = Float(step) / 100
            let value: Float = RevealEntrance.kickReturn(progress)
            peak = max(peak, value)
        }
        XCTAssertGreaterThan(peak, 1.02)
        XCTAssertLessThan(peak, 1.1)
    }

    // MARK: - W2.13 The carved name card

    /// A 5★'s five stars land one after another inside a second of the
    /// card's arrival; a Quick 3★'s inside a third of one.
    func testTheStarsLandInOrder() {
        let timing = RevealCardTiming.standard(stars: 5)
        var last: Double = 0
        for index in 0..<5 {
            let landing: Double = timing.landing(index)
            XCTAssertGreaterThan(landing, last, "star \(index)")
            last = landing
        }
        XCTAssertLessThan(last, 1.0)
        let quick = RevealCardTiming.quick(stars: 3)
        let quickLast: Double = quick.landing(2)
        XCTAssertLessThan(quickLast, 0.3)
    }

    /// A star stamps in from 2.2 times its size to its own, or from 1.25
    /// under Reduce Motion, and has not begun before its turn.
    func testAStarStampsDownToItsSize() {
        let from: Double = RevealCardTiming.stampScale(0, calm: false)
        let to: Double = RevealCardTiming.stampScale(1, calm: false)
        let calmFrom: Double = RevealCardTiming.stampScale(0, calm: true)
        let calmTo: Double = RevealCardTiming.stampScale(1, calm: true)
        let notYet: Double = RevealCardTiming.standard(stars: 3).progress(of: 2, at: 0)
        XCTAssertEqual(from, 2.2, accuracy: 1e-9)
        XCTAssertEqual(to, 1.0, accuracy: 1e-9)
        XCTAssertEqual(calmFrom, 1.25, accuracy: 1e-9)
        XCTAssertEqual(calmTo, 1.0, accuracy: 1e-9)
        XCTAssertEqual(notYet, 0, accuracy: 1e-9)
    }

    /// The name landing sets the naming timeline off and leaves the
    /// arrival's alone, so no star is cut short by the pose's high point.
    func testTheNameLandingNeverRestartsTheStars() {
        let arrived: RevealCardBeat = .arrived(7)
        let named: RevealCardBeat = .named(7)
        let complete: RevealCardBeat = .complete(7)
        XCTAssertEqual(arrived.arrival, named.arrival)
        XCTAssertEqual(arrived.naming, RevealCardBeat.hidden)
        XCTAssertEqual(named.naming, RevealCardBeat.named(7))
        XCTAssertEqual(complete.arrival, RevealCardBeat.complete(7))
        XCTAssertEqual(complete.naming, RevealCardBeat.complete(7))
    }

    /// An awakened title of the form "Name, Epithet" is carved as the name
    /// with the rest over it; the second line names the pantheon.
    func testAnAwakenedTitleSplitsIntoNameAndEyebrow() throws {
        let pool: [UnitBlueprint] = UnitDatabase.summonPool.compactMap { UnitDatabase.blueprint($0) }
        let blueprint = try XCTUnwrap(pool.first { ($0.awakening?.awakenedName ?? "").contains(", ") },
                                      "some awakened title is \"Name, Epithet\"")
        var result = SummonResult(unit: Unit(blueprint: blueprint), blueprint: blueprint,
                                  stars: blueprint.naturalStars, isNew: false, isFeatured: false, fromPity: false)
        result.isAwakening = true
        let names = RevealNameCard.names(for: result)
        let line: String = RevealNameCard.secondLine(for: result)
        XCTAssertFalse(names.main.contains(","), names.main)
        XCTAssertNotNil(names.eyebrow)
        XCTAssertTrue(line.contains(blueprint.pantheon.displayName), line)
    }

    /// The light across the name is a band whose stops never run backwards
    /// and never leave the name, from before it to past it.
    func testTheSweepStopsStayInOrder() {
        for step in 0...20 {
            let sweep: Double = Double(step) / 20
            let stops: [Gradient.Stop] = RevealNameCard.sweepStops(sweep)
            let locations: [CGFloat] = stops.map { $0.location }
            let sorted: [CGFloat] = locations.sorted()
            XCTAssertEqual(locations, sorted, "sweep \(sweep)")
            XCTAssertGreaterThanOrEqual(locations.first ?? -1, 0)
            XCTAssertLessThanOrEqual(locations.last ?? 2, 1)
        }
    }

    /// The card's column starts past the middle, clear of the figure. On the
    /// main actor: both numbers are statics of a view (a `View` and a
    /// `UIViewRepresentable`, main-actor isolated in the iOS 18 SDK).
    @MainActor
    func testTheCardStandsInTheRightFortyFivePerCent() {
        let edge: CGFloat = RevealNameCard.clearOfFigure
        let figure: CGFloat = SummonStageView.figureLine
        let gap: CGFloat = edge - figure
        XCTAssertGreaterThanOrEqual(edge, 0.55)
        XCTAssertGreaterThan(gap, 0.25)
    }

    // MARK: - W2.23 Skip that never swallows a 5★

    /// A pull of `stars`, new or not, from the pool's forms of that grade.
    private func pull(_ stars: Int, new: Bool = false, nth: Int = 0) throws -> SummonResult {
        let pool: [UnitBlueprint] = UnitDatabase.summonPool
            .compactMap { UnitDatabase.blueprint($0) }
            .filter { $0.naturalStars == stars }
        let blueprint = try XCTUnwrap(pool.isEmpty ? nil : pool[nth % pool.count], "a \(stars)★ in the pool")
        return SummonResult(unit: Unit(blueprint: blueprint), blueprint: blueprint, stars: stars,
                            isNew: new, isFeatured: false, fromPity: false)
    }

    /// A ten-pull: 3★, 3★, 4★ duplicate, 3★, the 5★, 3★, a NEW 4★, then
    /// three more commons.
    private func tenPull() throws -> [SummonResult] {
        [try pull(3), try pull(3, nth: 1), try pull(4), try pull(3, nth: 2), try pull(5, new: true),
         try pull(3, nth: 3), try pull(4, new: true, nth: 1), try pull(3, nth: 4), try pull(3, nth: 5),
         try pull(4, nth: 2)]
    }

    /// From the first pull, Skip goes to the 5★ and says so; on the 5★'s
    /// charge it goes to its flash; after it, on to the new 4★; after that,
    /// the summary.
    func testSkipStopsAtEveryPullWorthSeeing() throws {
        let results = try tenPull()
        let fromFirst: RevealSkipTarget = RevealSkip.target(in: results, at: 0, landed: false)
        let fromFirstLanded: RevealSkipTarget = RevealSkip.target(in: results, at: 0, landed: true)
        let onFiveCharging: RevealSkipTarget = RevealSkip.target(in: results, at: 4, landed: false)
        let afterFive: RevealSkipTarget = RevealSkip.target(in: results, at: 4, landed: true)
        let afterNew: RevealSkipTarget = RevealSkip.target(in: results, at: 6, landed: true)
        XCTAssertEqual(fromFirst, RevealSkipTarget.pull(4))
        XCTAssertEqual(fromFirstLanded, RevealSkipTarget.pull(4))
        XCTAssertEqual(onFiveCharging, RevealSkipTarget.land)
        XCTAssertEqual(afterFive, RevealSkipTarget.pull(6))
        XCTAssertEqual(afterNew, RevealSkipTarget.summary)
        let label: RevealSkipLabel = RevealSkip.label(in: results, for: fromFirst, at: 0)
        let newLabel: RevealSkipLabel = RevealSkip.label(in: results, for: afterFive, at: 4)
        XCTAssertEqual(label, RevealSkipLabel.to(stars: 5, new: false))
        XCTAssertEqual(newLabel, RevealSkipLabel.to(stars: 4, new: true))
    }

    /// A new 4★ BEFORE a 5★ is a stop on the way, never skipped past.
    func testANewFourStarBeforeTheFiveIsAStopToo() throws {
        let results = [try pull(3), try pull(4, new: true), try pull(3, nth: 1), try pull(5)]
        let first: RevealSkipTarget = RevealSkip.target(in: results, at: 0, landed: true)
        let second: RevealSkipTarget = RevealSkip.target(in: results, at: 1, landed: true)
        XCTAssertEqual(first, RevealSkipTarget.pull(1))
        XCTAssertEqual(second, RevealSkipTarget.pull(3))
    }

    /// A single's Skip never names its own pull: "Skip to ★★★★★" on the
    /// first frame of a single's charge would be its grade before the
    /// ladder's first rung (W1.5). A tap on it still lands a 5★'s flash
    /// rather than skipping past it.
    func testASinglesSkipNeverTellsItsGrade() throws {
        let singles: [SummonResult] = [try pull(5), try pull(5, new: true), try pull(4, new: true),
                                       try pull(4), try pull(3), try pull(3, new: true)]
        for single in singles {
            let results: [SummonResult] = [single]
            let target: RevealSkipTarget = RevealSkip.target(in: results, at: 0, landed: false)
            let label: RevealSkipLabel = RevealSkip.label(in: results, for: target, at: 0)
            XCTAssertEqual(label, RevealSkipLabel.skip, "a single \(single.stars)★, new: \(single.isNew)")
        }
        let five: [SummonResult] = [try pull(5)]
        let fiveTarget: RevealSkipTarget = RevealSkip.target(in: five, at: 0, landed: false)
        XCTAssertEqual(fiveTarget, RevealSkipTarget.land, "a tap on a single 5★'s Skip lands its flash")
    }

    /// In a pull of several the words change only when a pull LANDS: every
    /// charge opens on exactly the words the last pull's landing left up,
    /// so no charge's first frame says whether it is the stop. (Plain Skip
    /// on the stop's own charge would say it: the words would change there
    /// and nowhere else.)
    func testAPullOfSeveralChangesItsWordsOnlyAtALanding() throws {
        let fixtures: [[SummonResult]] = [
            try tenPull(),
            [try pull(3), try pull(4, new: true), try pull(3, nth: 1), try pull(5)],
        ]
        for results in fixtures {
            for index in 1..<results.count {
                let before: RevealSkipTarget = RevealSkip.target(in: results, at: index - 1, landed: true)
                let opening: RevealSkipTarget = RevealSkip.target(in: results, at: index, landed: false)
                let left: RevealSkipLabel = RevealSkip.label(in: results, for: before, at: index - 1)
                let shown: RevealSkipLabel = RevealSkip.label(in: results, for: opening, at: index)
                let place: Int = index + 1
                let count: Int = results.count
                XCTAssertEqual(shown, left, "pull \(place) of \(count)'s charge")
            }
        }
    }

    /// Nothing worth seeing left: Skip is plain Skip, to the summary.
    func testAPullOfCommonsSkipsToTheSummary() throws {
        let results = [try pull(3), try pull(3, nth: 1), try pull(4)]
        let target: RevealSkipTarget = RevealSkip.target(in: results, at: 0, landed: false)
        let label: RevealSkipLabel = RevealSkip.label(in: results, for: target, at: 0)
        XCTAssertEqual(target, RevealSkipTarget.summary)
        XCTAssertEqual(label, RevealSkipLabel.skip)
    }

    /// Quick summons plays a 3★ as a flash, never a 4★, a 5★ or an
    /// awakening, and nothing at all while it is off.
    func testQuickSummonsIsForThreeStarsOnly() throws {
        let common = try pull(3)
        let rare = try pull(4)
        let legend = try pull(5)
        var awakening = try pull(3)
        awakening.isAwakening = true
        XCTAssertTrue(RevealSkip.playsQuick(common, quick: true))
        XCTAssertFalse(RevealSkip.playsQuick(common, quick: false))
        XCTAssertFalse(RevealSkip.playsQuick(rare, quick: true))
        XCTAssertFalse(RevealSkip.playsQuick(legend, quick: true))
        XCTAssertFalse(RevealSkip.playsQuick(awakening, quick: true))
    }

    // MARK: - W2.7 Sound that climbs with the grade

    /// The rise rings for a 4★ or better and the tell for a 5★ alone,
    /// each read off the pull's stars; the Light & Dark layer off the scroll
    /// spent; and the charge's first frame sounds the same for every grade.
    func testTheTellReadsTheStarsAndNothingLooser() {
        var scrolls: [ScrollType?] = [nil]
        scrolls.append(contentsOf: ScrollType.allCases.map { Optional($0) })
        for stars in 1...6 {
            for scroll in scrolls {
                let stems: [ChargeLadder.Stem] = ChargeLadder.stems(stars: stars, scroll: scroll)
                let sounds: [AudioLibrary.Sound] = stems.map { $0.sound }
                let wantsRise: Bool = stars >= 4
                let wantsTell: Bool = stars >= 5
                let wantsLightDark: Bool = scroll == .lightDark
                XCTAssertEqual(sounds.contains(.summonChargeRise), wantsRise, "\(stars)★")
                XCTAssertEqual(sounds.contains(.summonChargeTell), wantsTell, "\(stars)★")
                XCTAssertEqual(sounds.contains(.summonChargeLightDark), wantsLightDark, "\(String(describing: scroll))")
                let opening: [AudioLibrary.Sound] = stems.filter { $0.at <= 0 }.map { $0.sound }
                let commonOpening: [AudioLibrary.Sound] = ChargeLadder.stems(stars: 3, scroll: scroll)
                    .filter { $0.at <= 0 }.map { $0.sound }
                XCTAssertEqual(opening, commonOpening, "a \(stars)★'s first frame sounds like a 3★'s")
            }
        }
    }

    /// The rise stands on the violet rung and the tell on the gold one.
    func testTheStemsStandOnTheirRungs() throws {
        let stems: [ChargeLadder.Stem] = ChargeLadder.stems(stars: 5, scroll: nil)
        let rise = try XCTUnwrap(stems.first { $0.sound == .summonChargeRise })
        let tell = try XCTUnwrap(stems.first { $0.sound == .summonChargeTell })
        XCTAssertEqual(rise.at, ChargeLadder.violetAt, accuracy: 1e-9)
        XCTAssertEqual(tell.at, ChargeLadder.goldAt, accuracy: 1e-9)
    }

    /// The burst climbs with the grade.
    func testTheBurstClimbsWithTheGrade() {
        let two: AudioLibrary.Sound = AudioLibrary.Sound.burst(forStars: 2)
        let three: AudioLibrary.Sound = AudioLibrary.Sound.burst(forStars: 3)
        let four: AudioLibrary.Sound = AudioLibrary.Sound.burst(forStars: 4)
        let five: AudioLibrary.Sound = AudioLibrary.Sound.burst(forStars: 5)
        let six: AudioLibrary.Sound = AudioLibrary.Sound.burst(forStars: 6)
        XCTAssertEqual(two, .summonBurst3)
        XCTAssertEqual(three, .summonBurst3)
        XCTAssertEqual(four, .summonBurst4)
        XCTAssertEqual(five, .summonBurst5)
        XCTAssertEqual(six, .summonBurst5)
    }

    /// Every stem the charge can sound is one the flash fades out, at the
    /// one volume the mix was levelled for (`summon_mix_check`), and every
    /// burst is one the next pull fades.
    func testEveryStemIsOneTheFlashClears() {
        var scrolls: [ScrollType?] = [nil]
        scrolls.append(contentsOf: ScrollType.allCases.map { Optional($0) })
        for stars in 1...6 {
            for scroll in scrolls {
                for stem in ChargeLadder.stems(stars: stars, scroll: scroll) {
                    XCTAssertTrue(ChargeLadder.stemSounds.contains(stem.sound), stem.sound.rawValue)
                    XCTAssertEqual(stem.volume, ChargeLadder.stemVolume, accuracy: 1e-6)
                }
            }
            let burst: AudioLibrary.Sound = AudioLibrary.Sound.burst(forStars: stars)
            XCTAssertTrue(ChargeLadder.burstSounds.contains(burst), burst.rawValue)
        }
    }

    /// The burst starts once the stems have all but gone, and late enough
    /// behind the flash only to read as with it, never ahead of it.
    func testTheBurstLandsAsTheStemsGo() {
        let lead: TimeInterval = ChargeLadder.burstLead
        let fade: TimeInterval = ChargeLadder.stemFade
        let leftAtTheBurst: Double = 1 - lead / fade
        XCTAssertGreaterThan(lead, 0)
        XCTAssertLessThanOrEqual(lead, 0.045)
        XCTAssertLessThanOrEqual(leftAtTheBurst, 0.25)
    }

    /// The stars ring a little softer the bigger the burst under them.
    func testTheStarsGiveWayToABiggerBurst() {
        let three: Float = ChargeLadder.starVolume(stars: 3)
        let four: Float = ChargeLadder.starVolume(stars: 4)
        let five: Float = ChargeLadder.starVolume(stars: 5)
        let six: Float = ChargeLadder.starVolume(stars: 6)
        XCTAssertGreaterThanOrEqual(three, four)
        XCTAssertGreaterThanOrEqual(four, five)
        XCTAssertEqual(six, five, accuracy: 1e-6)
        XCTAssertGreaterThan(five, 0)
        XCTAssertLessThanOrEqual(three, 1)
    }

    /// The stars climb the scale one note a star, the sixth the octave.
    func testTheStarsClimbAScale() {
        let notes: [AudioLibrary.Sound] = (0..<6).map { AudioLibrary.Sound.star($0) }
        let beyond: AudioLibrary.Sound = AudioLibrary.Sound.star(9)
        let before: AudioLibrary.Sound = AudioLibrary.Sound.star(-1)
        XCTAssertEqual(notes, [.star1, .star2, .star3, .star4, .star5, .star6])
        XCTAssertEqual(beyond, .star6)
        XCTAssertEqual(before, .star1)
    }

    /// Every sound the summon plays is in the bundle: a missing file is a
    /// silent pull, never a crash, so this is the check that fails instead.
    func testEverySummonSoundShips() {
        let sounds: [AudioLibrary.Sound] = [
            .summonIgnite, .summonChargeBase, .summonChargeRise, .summonChargeTell, .summonChargeLightDark,
            .summonBurst3, .summonBurst4, .summonBurst5,
            .star1, .star2, .star3, .star4, .star5, .star6,
            .riteAwaken, .riteEvolve, .riteRelicAwaken,
        ]
        for sound in sounds {
            let url: URL? = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Audio")
                ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "wav")
            XCTAssertNotNil(url, "\(sound.rawValue).wav: python3 tools/sfx.py summon --vsco DIR")
        }
    }
}
