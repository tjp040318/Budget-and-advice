import XCTest
import SwiftUI
@testable import Pantheon

/// The ten-pull as one ceremony (Docs/FEEL.md W2.3) and the one continuous
/// shot into the reveal (W2.14): which cards stop the board, which pull the
/// ten's one charge climbs to, the Skip that reads landings only, the
/// summary's line, a board that fits every phone without a scroll, and a
/// scroll that lands exactly where the reveal draws it. The pure parts a CI
/// frame cannot show. Every figure an assert compares is hoisted into a
/// typed `let` first (CLAUDE.md: an assert's parentheses stay free of
/// arithmetic).
final class SummonBoardTests: XCTestCase {

    // MARK: - Fixtures

    /// A pull of `stars`, new or not, from the pool's forms of that grade;
    /// `lightDark` picks a Light or Dark form, or never one.
    private func pull(_ stars: Int, new: Bool = false, nth: Int = 0, lightDark: Bool = false) throws -> SummonResult {
        let pool: [UnitBlueprint] = UnitDatabase.summonPool
            .compactMap { UnitDatabase.blueprint($0) }
            .filter { $0.naturalStars == stars && $0.element.isLightOrDark == lightDark }
        let blueprint = try XCTUnwrap(pool.isEmpty ? nil : pool[nth % pool.count], "a \(stars)★ in the pool")
        return SummonResult(unit: Unit(blueprint: blueprint), blueprint: blueprint, stars: stars,
                            isNew: new, isFeatured: false, fromPity: false)
    }

    /// The reveal tests' ten: 3★, 3★, a 4★ duplicate, 3★, a NEW 5★, 3★, a
    /// NEW 4★, 3★, 3★, a 4★ duplicate.
    private func tenPull() throws -> [SummonResult] {
        [try pull(3), try pull(3, nth: 1), try pull(4), try pull(3, nth: 2), try pull(5, new: true),
         try pull(3, nth: 3), try pull(4, new: true, nth: 1), try pull(3, nth: 4), try pull(3, nth: 5),
         try pull(4, nth: 2)]
    }

    private func commons(_ count: Int) throws -> [SummonResult] {
        try (0..<count).map { try pull(3, nth: $0) }
    }

    // MARK: - Which cards stop the board

    /// A 4★ or better, or a unit never owned, lands with a flare and lifts
    /// off for its reveal; a 3★ duplicate only turns.
    func testFeaturedCardsAreFourStarsUpAndNewUnits() throws {
        let common: SummonResult = try pull(3)
        let newCommon: SummonResult = try pull(3, new: true)
        let rare: SummonResult = try pull(4)
        let legend: SummonResult = try pull(5)
        XCTAssertFalse(SummonBoard.isFeatured(common))
        XCTAssertTrue(SummonBoard.isFeatured(newCommon))
        XCTAssertTrue(SummonBoard.isFeatured(rare))
        XCTAssertTrue(SummonBoard.isFeatured(legend))
    }

    /// The one charge climbs to the best grade in the ten; among equals a
    /// Light or Dark form (its charge parts at the top of the ladder), then
    /// a new one, then the earliest.
    func testTheTensChargeClimbsToItsBestPull() throws {
        let ten: [SummonResult] = try tenPull()
        let best: Int? = SummonBoard.headline(of: ten)
        XCTAssertEqual(best, 4, "the 5★")

        let rares: [SummonResult] = [try pull(4), try pull(4, new: true, nth: 1), try pull(3)]
        let newFirst: Int? = SummonBoard.headline(of: rares)
        XCTAssertEqual(newFirst, 1, "a new 4★ outranks an owned one")

        let legends: [SummonResult] = [try pull(5, new: true), try pull(5, lightDark: true)]
        let parts: Int? = SummonBoard.headline(of: legends)
        XCTAssertEqual(parts, 1, "a Light or Dark 5★ is the charge that parts")

        let twins: [SummonResult] = [try pull(3), try pull(3, nth: 1)]
        let earliest: Int? = SummonBoard.headline(of: twins)
        XCTAssertEqual(earliest, 0)

        let none: Int? = SummonBoard.headline(of: [])
        XCTAssertNil(none)
    }

    /// The first figure the board will stand on the beam is the one the
    /// summon room warms; a ten of owned commons mounts no stage at all.
    func testTheRoomWarmsTheBoardsFirstFigure() throws {
        let ten: [SummonResult] = try tenPull()
        let next: Int? = SummonBoard.nextFeatured(from: 0, in: ten)
        let afterIt: Int? = SummonBoard.nextFeatured(from: 3, in: ten)
        let pastTheLast: Int? = SummonBoard.nextFeatured(from: 10, in: ten)
        XCTAssertEqual(next, 2)
        XCTAssertEqual(afterIt, 4)
        XCTAssertNil(pastTheLast)

        let warmed: UUID? = SummonBoard.firstStage(in: ten)?.id
        XCTAssertEqual(warmed, ten[2].id)

        let single: [SummonResult] = [try pull(3)]
        let singleWarmed: UUID? = SummonBoard.firstStage(in: single)?.id
        XCTAssertEqual(singleWarmed, single[0].id, "a single warms its own figure")

        let plain: [SummonResult] = try commons(10)
        XCTAssertNil(SummonBoard.firstStage(in: plain))
    }

    // MARK: - Skip on the board (W2.23 kept)

    /// Skip on the board runs to the first card worth seeing — a 5★, or a
    /// new 4★ — never past it, and a 4★ duplicate is not a stop.
    func testTheBoardsSkipStopsOnlyForPullsWorthSeeing() throws {
        let ten: [SummonResult] = try tenPull()
        let fromTheDeal: Int? = RevealSkip.boardStop(in: ten, from: 0)
        let afterTheFive: Int? = RevealSkip.boardStop(in: ten, from: 5)
        let afterTheNew: Int? = RevealSkip.boardStop(in: ten, from: 7)
        XCTAssertEqual(fromTheDeal, 4)
        XCTAssertEqual(afterTheFive, 6)
        XCTAssertNil(afterTheNew)

        let opening: RevealSkipLabel = RevealSkip.boardLabel(in: ten, from: 0, queue: [])
        let waiting: RevealSkipLabel = RevealSkip.boardLabel(in: ten, from: 5, queue: [4])
        let onward: RevealSkipLabel = RevealSkip.boardLabel(in: ten, from: 5, queue: [])
        let done: RevealSkipLabel = RevealSkip.boardLabel(in: ten, from: 7, queue: [])
        XCTAssertEqual(opening, RevealSkipLabel.to(stars: 5, new: false))
        XCTAssertEqual(waiting, RevealSkipLabel.to(stars: 5, new: false), "the 5★ up and waiting to lift")
        XCTAssertEqual(onward, RevealSkipLabel.to(stars: 4, new: true))
        XCTAssertEqual(done, RevealSkipLabel.skip)
    }

    /// The words change only when a card LANDS: from the deal to the stop's
    /// own landing they say the same, so no turn's first frame tells what
    /// the card will be (W1.5). Each featured card joins the queue as it
    /// lands, as the board keeps it while it stands stopped.
    func testTheBoardsWordsChangeOnlyAtALanding() throws {
        let ten: [SummonResult] = try tenPull()
        let atTheDeal: RevealSkipLabel = RevealSkip.boardLabel(in: ten, from: 0, queue: [])
        for landed in 0...5 {
            let queue: [Int] = (0..<landed).filter { SummonBoard.isFeatured(ten[$0]) }
            let words: RevealSkipLabel = RevealSkip.boardLabel(in: ten, from: landed, queue: queue)
            XCTAssertEqual(words, atTheDeal, "\(landed) cards landed")
        }
    }

    /// The words name the card a press lifts (review, 2026-09-24): with a
    /// duplicate 4★ at the head of the queue and the 5★ waiting behind it —
    /// the CI's own ten, whose 5★ was mid-turn when the board stopped on the
    /// 4★ — Skip lifts the 5★, and the words say "Skip to ★★★★★" from the
    /// 4★'s landing to the lift, never the new 4★ still face down after it.
    func testTheBoardsWordsNameTheCardSkipLifts() throws {
        let ten: [SummonResult] = try tenPull()
        let queue: [Int] = [2, 4]
        let lifted: Int? = RevealSkip.boardWaiting(in: ten, queue: queue)
        XCTAssertEqual(lifted, 4, "the 5★ behind the duplicate 4★")

        let words: RevealSkipLabel = RevealSkip.boardLabel(in: ten, from: 6, queue: queue)
        let atTheFour: RevealSkipLabel = RevealSkip.boardLabel(in: ten, from: 3, queue: [2])
        XCTAssertEqual(words, RevealSkipLabel.to(stars: 5, new: false))
        XCTAssertEqual(atTheFour, words, "the same words from the 4★'s landing to the lift")

        let duplicates: Int? = RevealSkip.boardWaiting(in: ten, queue: [2, 9])
        XCTAssertNil(duplicates, "a duplicate 4★ is never a skip's stop")
        let empty: Int? = RevealSkip.boardWaiting(in: ten, queue: [])
        XCTAssertNil(empty)
    }

    // MARK: - The summary

    /// "1 ★★★★★ · 3 ★★★★ · 2 new": the grades from 4★ up, best first, and
    /// how many are new.
    func testTheTallyCountsFourStarsUpAndNewUnits() throws {
        let ten: [SummonResult] = try tenPull()
        let tally: SummonTally = SummonBoard.tally(ten)
        let expected: [SummonTallyEntry] = [SummonTallyEntry(stars: 5, count: 1), SummonTallyEntry(stars: 4, count: 3)]
        XCTAssertEqual(tally.entries, expected)
        XCTAssertEqual(tally.newCount, 2)
        XCTAssertEqual(tally.total, 10)
        let line: String = SummonBoard.tallyLine(tally)
        XCTAssertEqual(line, "1 ★★★★★ · 3 ★★★★ · 2 new")
    }

    /// A ten of commons still says what it was: the best grade alone.
    func testATenOfCommonsTalliesItsBestGrade() throws {
        let plain: [SummonResult] = try commons(10)
        let tally: SummonTally = SummonBoard.tally(plain)
        let line: String = SummonBoard.tallyLine(tally)
        XCTAssertEqual(line, "10 ★★★")
    }

    /// "Summon ×10 again" spends scrolls in hand and nothing else.
    func testSummonAgainNeedsTheScrollsInHand() {
        let enough = SummonAgainOffer(count: 10, scroll: .mystical, held: 23, pity: nil, action: {})
        let short = SummonAgainOffer(count: 10, scroll: .mystical, held: 7, pity: nil, action: {})
        XCTAssertTrue(enough.affordable)
        XCTAssertEqual(enough.short, 0)
        XCTAssertFalse(short.affordable)
        XCTAssertEqual(short.short, 3)
    }

    // MARK: - The board's clock

    /// Cards turn left to right 90 ms apart, never before the run's first.
    func testCardsTurnNinetyMillisecondsApart() {
        let fourth: TimeInterval = SummonBoard.flipDelay(of: 3, from: 0)
        let first: TimeInterval = SummonBoard.flipDelay(of: 5, from: 5)
        let behind: TimeInterval = SummonBoard.flipDelay(of: 2, from: 5)
        XCTAssertEqual(SummonBoard.flipSpacing, 0.09, accuracy: 1e-9)
        XCTAssertEqual(fourth, 0.27, accuracy: 1e-9)
        XCTAssertEqual(first, 0, accuracy: 1e-9)
        XCTAssertEqual(behind, 0, accuracy: 1e-9)
    }

    /// A card is face down until its run reaches it, landed a turn after,
    /// and flares only once it has a landing.
    func testACardsLookIsItsClock() {
        // Near the reference date, where a Date keeps its fractions to the
        // femtosecond rather than the tenth of a microsecond.
        let dealt = Date(timeIntervalSinceReferenceDate: 0)
        var clock = SummonBoardClock(dealtAt: dealt)
        let start: Date = dealt.addingTimeInterval(0.5)
        clock.flips[0] = start
        let halfway: Date = start.addingTimeInterval(SummonBoard.flipLength / 2)
        let after: Date = start.addingTimeInterval(SummonBoard.flipLength + 0.01)
        let unturned: Double = clock.turned(1, at: after)
        let half: Double = clock.turned(0, at: halfway)
        let whole: Double = clock.turned(0, at: after)
        XCTAssertEqual(unturned, 0, accuracy: 1e-9)
        XCTAssertEqual(half, 0.5, accuracy: 1e-9)
        XCTAssertEqual(whole, 1, accuracy: 1e-9)
        XCTAssertFalse(clock.isLanded(0, at: halfway))
        XCTAssertTrue(clock.isLanded(0, at: after))
        XCTAssertNil(clock.flare(0, at: after), "no flare without a landing")
        clock.flares[0] = after
        let flareNow: Double = clock.flare(0, at: after) ?? -1
        XCTAssertEqual(flareNow, 0, accuracy: 1e-9)
    }

    // MARK: - A board that always fits

    /// Two rows of five with their names, between Skip's band and the foot,
    /// inside the safe area on the CI's phone, an SE and a 13 mini — the
    /// spec's 96-point cards on the CI's phone — and never a scroll.
    func testTheBoardFitsEveryPhone() {
        let phones: [(name: String, size: CGSize, insets: EdgeInsets)] = [
            ("CI phone 852 × 393", CGSize(width: 852, height: 393), EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)),
            ("iPhone SE 667 × 375", CGSize(width: 667, height: 375), EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)),
            ("iPhone 13 mini 812 × 375", CGSize(width: 812, height: 375), EdgeInsets(top: 0, leading: 50, bottom: 21, trailing: 50)),
        ]
        for phone in phones {
            let layout: SummonBoardLayout = SummonBoardLayout.make(count: 10, size: phone.size, insets: phone.insets)
            let leftEdge: CGFloat = phone.insets.leading
            let rightEdge: CGFloat = phone.size.width - phone.insets.trailing
            let footEdge: CGFloat = phone.size.height - phone.insets.bottom
            XCTAssertEqual(layout.slots.count, 10, phone.name)
            XCTAssertGreaterThanOrEqual(layout.card, 90, phone.name)
            XCTAssertLessThanOrEqual(layout.card, SummonBoardLayout.largest, phone.name)
            XCTAssertLessThanOrEqual(layout.footer.maxY, footEdge, phone.name)
            for (place, slot) in layout.slots.enumerated() {
                let nameFoot: CGFloat = slot.maxY + SummonBoardLayout.nameHeight
                XCTAssertGreaterThanOrEqual(slot.minX, leftEdge, "\(phone.name), card \(place)")
                XCTAssertLessThanOrEqual(slot.maxX, rightEdge, "\(phone.name), card \(place)")
                XCTAssertGreaterThanOrEqual(slot.minY, SummonBoardLayout.top, "\(phone.name), card \(place): under Skip")
                XCTAssertLessThanOrEqual(nameFoot, layout.footer.minY, "\(phone.name), card \(place): its name on the foot")
            }
            // Neighbours in a row and the two rows never touch.
            let leastGap: CGFloat = SummonBoardLayout.gapX - 0.001
            for place in 0..<4 {
                let gap: CGFloat = layout.slots[place + 1].minX - layout.slots[place].maxX
                XCTAssertGreaterThanOrEqual(gap, leastGap, phone.name)
            }
            let firstRowFoot: CGFloat = layout.slots[0].maxY + SummonBoardLayout.nameHeight
            let secondRowTop: CGFloat = layout.slots[5].minY
            XCTAssertGreaterThan(secondRowTop, firstRowFoot, phone.name)
        }
        let ci: SummonBoardLayout = SummonBoardLayout.make(
            count: 10, size: CGSize(width: 852, height: 393),
            insets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        )
        XCTAssertEqual(ci.card, 96, accuracy: 1e-9, "the spec's 96-point cards on the CI's phone")
    }

    /// A pull of fewer than ten — a five from the mileage board, say —
    /// centres its one row.
    func testAShortPullCentresItsRow() {
        let size = CGSize(width: 852, height: 393)
        let insets = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        let layout: SummonBoardLayout = SummonBoardLayout.make(count: 3, size: size, insets: insets)
        let rowMiddle: CGFloat = (layout.slots[0].minX + layout.slots[2].maxX) / 2
        let screenMiddle: CGFloat = size.width / 2
        XCTAssertEqual(rowMiddle, screenMiddle, accuracy: 0.5)
        XCTAssertEqual(layout.slots[0].minY, layout.slots[2].minY, accuracy: 1e-9)
    }

    // MARK: - One continuous shot (W2.14)

    /// The room's scroll ends its flight on exactly the square, the tilt and
    /// the place the reveal's first frame draws its scroll at — the middle
    /// for a ten, the figure's line for a single — and lifts off the ring
    /// before it travels.
    func testTheFlightEndsWhereTheRevealDrawsItsScroll() {
        let size = CGSize(width: 852, height: 393)
        let landing: CGRect = RevealGeometry.openingScroll(pulls: 10, in: size)
        let ring = CGRect(x: 160, y: 170, width: 70, height: 70)
        let began = Date(timeIntervalSinceReferenceDate: 0)
        let shot = SummonShot(serial: 1, scroll: .mystical, pulls: 10, from: ring, to: landing,
                              fromTilt: 0, toTilt: RevealGeometry.scrollTilt,
                              fromLight: ChargeRGB.white, toLight: ChargeLadder.ground, began: began)
        let start: SummonShot.Pose = shot.pose(progress: 0)
        let middle: SummonShot.Pose = shot.pose(progress: 0.5)
        let end: SummonShot.Pose = shot.pose(progress: 1)
        let landed: SummonShot.Pose = shot.pose(at: began.addingTimeInterval(SummonShot.length + 0.01))

        let ringX: CGFloat = ring.midX
        let ringY: CGFloat = ring.midY
        let landingX: CGFloat = landing.midX
        let landingY: CGFloat = landing.midY
        let landingSide: CGFloat = landing.width
        let straightMiddle: CGFloat = (ringY + landingY) / 2
        XCTAssertEqual(start.centre.x, ringX, accuracy: 1e-6)
        XCTAssertEqual(start.centre.y, ringY, accuracy: 1e-6)
        XCTAssertEqual(end.centre.x, landingX, accuracy: 1e-6)
        XCTAssertEqual(end.centre.y, landingY, accuracy: 1e-6)
        XCTAssertEqual(end.side, landingSide, accuracy: 1e-6)
        XCTAssertEqual(end.tilt, RevealGeometry.scrollTilt, accuracy: 1e-9)
        XCTAssertEqual(landed, end, "the flight lands on its own clock")
        XCTAssertLessThan(middle.centre.y, straightMiddle, "it lifts off the ring before it travels")

        let boardX: CGFloat = size.width * RevealGeometry.boardLine
        let figureX: CGFloat = size.width * RevealGeometry.figureLine
        let heartY: CGFloat = size.height * RevealGeometry.heart
        let side: CGFloat = size.height * RevealGeometry.scrollSide
        let single: CGRect = RevealGeometry.openingScroll(pulls: 1, in: size)
        let singleX: CGFloat = single.midX
        let singleY: CGFloat = single.midY
        XCTAssertEqual(landingX, boardX, accuracy: 1e-6)
        XCTAssertEqual(landingY, heartY, accuracy: 1e-6)
        XCTAssertEqual(landingSide, side, accuracy: 1e-6)
        XCTAssertEqual(singleX, figureX, accuracy: 1e-6)
        XCTAssertEqual(singleY, heartY, accuracy: 1e-6)
    }

    /// The flight is eased at both ends and short: with the room's 0.35 s
    /// wind-up it is over inside a second.
    func testTheFlightIsEasedAndShort() {
        let opening: CGFloat = SummonShot.progress(elapsed: 0)
        let halfway: CGFloat = SummonShot.progress(elapsed: SummonShot.length / 2)
        let early: CGFloat = SummonShot.progress(elapsed: SummonShot.length / 10)
        let over: CGFloat = SummonShot.progress(elapsed: SummonShot.length)
        let long: CGFloat = SummonShot.progress(elapsed: 5)
        let windUpAndFlight: TimeInterval = 0.35 + SummonShot.length
        XCTAssertEqual(opening, 0, accuracy: 1e-9)
        XCTAssertEqual(halfway, 0.5, accuracy: 1e-6)
        XCTAssertLessThan(early, 0.05, "it leaves the ring gently")
        XCTAssertEqual(over, 1, accuracy: 1e-9)
        XCTAssertEqual(long, 1, accuracy: 1e-9)
        XCTAssertLessThan(windUpAndFlight, 1)
    }

    /// The reveal's charge comes up round the scroll it was handed over
    /// 0.3 s, eased, and is whole from then on.
    func testTheChargeComesUpRoundAHandedScroll() {
        let first: CGFloat = RevealGeometry.handoff(ambient: 0)
        let half: CGFloat = RevealGeometry.handoff(ambient: RevealGeometry.handoffSpan / 2)
        let whole: CGFloat = RevealGeometry.handoff(ambient: RevealGeometry.handoffSpan)
        let later: CGFloat = RevealGeometry.handoff(ambient: 4)
        XCTAssertEqual(first, 0, accuracy: 1e-9)
        XCTAssertEqual(half, 0.5, accuracy: 1e-9)
        XCTAssertEqual(whole, 1, accuracy: 1e-9)
        XCTAssertEqual(later, 1, accuracy: 1e-9)
    }

    /// A featured card lifts off its slot and arrives on the beam at 1.45×
    /// its size — at once under Reduce Motion.
    func testALiftedCardArrivesWhereTheFigureStands() {
        let slot = CGRect(x: 300, y: 100, width: 96, height: 96)
        let beam = CGPoint(x: 221, y: 196)
        let arrived: RevealLiftPose = RevealLift.pose(from: slot, to: beam, progress: 1)
        let leaving: RevealLiftPose = RevealLift.pose(from: slot, to: beam, progress: 0)
        let calm: CGFloat = RevealLift.progress(elapsed: 0, calm: true)
        let grown: CGFloat = slot.width * RevealLift.growth
        let slotX: CGFloat = slot.midX
        XCTAssertEqual(arrived.centre.x, beam.x, accuracy: 1e-6)
        XCTAssertEqual(arrived.centre.y, beam.y, accuracy: 1e-6)
        XCTAssertEqual(arrived.side, grown, accuracy: 1e-6)
        XCTAssertEqual(leaving.centre.x, slotX, accuracy: 1e-6)
        XCTAssertEqual(calm, 1, accuracy: 1e-9)
    }
}
