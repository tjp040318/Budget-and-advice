import XCTest
import SwiftUI
@testable import Pantheon

/// The relic kit's pure half (2026-09-24, the builders' spec §7, lane 0):
/// the roll marks read off a relic's values, the rosette's geometry, the
/// tile's stars, every set's short line, a draft's change count, and the
/// "fill empty slots" preview. Arithmetic is hoisted into typed lets and the
/// asserts compare names (CLAUDE.md: forty asserts with arithmetic inside
/// cost the test target four minutes of type-checking).
final class RelicKitTests: XCTestCase {

    // MARK: - The roll estimator

    /// One relic and the rolls each of its subs has actually taken.
    private struct Tracked {
        let relic: Relic
        let rolls: [Int]
    }

    /// 400 6★ relics, the five qualities in turn, taken to +12 with every
    /// sub's rolls counted off the `SubStatChange` each level reports: a new
    /// sub starts at one, a grown one gains one.
    private func trackedRelics() -> [Tracked] {
        var rng = SeededRandom(seed: 7)
        let qualities: [RelicQuality] = RelicQuality.allCases
        var built: [Tracked] = []
        for index in 0..<400 {
            let quality: RelicQuality = qualities[index % qualities.count]
            var relic = RelicService.generate(grade: 6, quality: quality, rng: &rng)
            var rolls: [Int] = relic.subStats.map { _ in 1 }
            for _ in 0..<12 {
                guard let change = RelicService.upgradeOnce(&relic, rng: &rng) else { continue }
                if change.isNew {
                    rolls.append(1)
                } else if let grown = relic.subStats.firstIndex(where: { $0.kind == change.kind }) {
                    rolls[grown] += 1
                }
            }
            built.append(Tracked(relic: relic, rolls: rolls))
        }
        return built
    }

    /// Read off the values, the counts match the tracked rolls on at least
    /// 396 of 400 relics and on every Rare or lower, and always add up to
    /// the relic's drops plus its roll levels. (A Python port of this exact
    /// sequence reads all 400; over 200 other seeds the worst is 398.)
    func testRollCountsReadTheTrackedRolls() {
        let relics: [Tracked] = trackedRelics()
        var exact = 0
        for entry in relics {
            let read: [Int?] = RelicReading.rollCounts(entry.relic)
            let tracked: [Int?] = entry.rolls.map { Optional($0) }
            if read == tracked {
                exact += 1
            }
            let quality: RelicQuality = entry.relic.resolvedQuality
            if quality <= .rare {
                XCTAssertEqual(read, tracked, "a \(quality.displayName) relic is read exactly")
            }
            let readSum: Int = read.compactMap { $0 }.reduce(0, +)
            let trackedSum: Int = entry.rolls.reduce(0, +)
            let events: Int = quality.subStatCount + entry.relic.level / 3
            XCTAssertEqual(trackedSum, events, "the tracked rolls are the drops and the levels")
            XCTAssertEqual(readSum, events, "the read counts add up to the drops and the levels")
        }
        XCTAssertGreaterThanOrEqual(exact, 396, "at least 396 of 400 relics are read exactly")
    }

    /// A gem took an unknown number of rolls with it: that sub has no count,
    /// and every other sub keeps one.
    func testAGemmedSubHasNoCount() throws {
        var rng = SeededRandom(seed: 3)
        var relic = RelicService.generate(grade: 6, quality: .legend, rng: &rng)
        for _ in 0..<12 {
            RelicService.upgradeOnce(&relic, rng: &rng)
        }
        relic.gemmed = 1
        let counts: [Int?] = RelicReading.rollCounts(relic)
        let subs: Int = relic.subStats.count
        XCTAssertEqual(counts.count, subs)
        XCTAssertNil(counts[1], "the gemmed sub draws no marks")
        for (index, count) in counts.enumerated() where index != 1 {
            XCTAssertNotNil(count, "sub \(index) keeps its count")
        }
    }

    // MARK: - The rosette

    /// Seven pointy-top hexagons edge to edge never overlap: every two
    /// centres, the Boon's included, stand at least √3·R apart.
    @MainActor
    func testTheRosetteHexagonsNeverOverlap() {
        let sizes: [(radius: CGFloat, gap: CGFloat)] = [(28, 3), (19, 2), (12, 2)]
        for size in sizes {
            let slots: [CGPoint] = (1...6).map { RelicRosette.offset(of: $0, radius: size.radius, gap: size.gap) }
            let centres: [CGPoint] = slots + [CGPoint.zero]
            let least: CGFloat = size.radius * CGFloat(3).squareRoot()
            for first in centres.indices {
                for second in centres.indices where second > first {
                    let dx: CGFloat = centres[first].x - centres[second].x
                    let dy: CGFloat = centres[first].y - centres[second].y
                    let apart: CGFloat = (dx * dx + dy * dy).squareRoot()
                    let clear: Bool = apart >= least - 0.001
                    XCTAssertTrue(clear, "R \(size.radius): centres \(first) and \(second) are \(apart) apart")
                }
            }
        }
    }

    /// Slot 1 at eleven o'clock, then clockwise in reading order.
    @MainActor
    func testTheSlotsRunClockwiseFromElevenOClock() {
        let one: CGPoint = RelicRosette.offset(of: 1, radius: 28, gap: 3)
        let two: CGPoint = RelicRosette.offset(of: 2, radius: 28, gap: 3)
        let three: CGPoint = RelicRosette.offset(of: 3, radius: 28, gap: 3)
        let six: CGPoint = RelicRosette.offset(of: 6, radius: 28, gap: 3)
        XCTAssertLessThan(one.x, 0, "slot 1 stands left of centre")
        XCTAssertLessThan(one.y, 0, "slot 1 stands above centre")
        XCTAssertGreaterThan(two.x, 0, "slot 2 stands right of centre, above")
        XCTAssertEqual(three.y, 0, accuracy: 0.001)
        XCTAssertGreaterThan(three.x, 0, "slot 3 is at three o'clock")
        XCTAssertLessThan(six.x, 0, "slot 6 is at nine o'clock")
    }

    /// The frame is `2d + √3·R` by `√3·d + 2R`, with `d = √3·R + gap`. The
    /// spec's table printed 146.4 for the unit sheet's height; its own
    /// formula gives 145.2 (5R + √3·gap), which is what is asserted.
    @MainActor
    func testTheRosetteFramesMatchTheirSizes() {
        let unitSheet: CGSize = RelicRosette.frameSize(radius: 28, gap: 3)
        let plate: CGSize = RelicRosette.frameSize(radius: 19, gap: 2)
        let filter: CGSize = RelicRosette.frameSize(radius: 12, gap: 2)
        XCTAssertEqual(unitSheet.width, 151.5, accuracy: 0.1)
        XCTAssertEqual(unitSheet.height, 145.2, accuracy: 0.1)
        XCTAssertEqual(plate.width, 102.7, accuracy: 0.1)
        XCTAssertEqual(plate.height, 98.4, accuracy: 0.1)
        XCTAssertEqual(filter.width, 66.4, accuracy: 0.1)
        XCTAssertEqual(filter.height, 63.5, accuracy: 0.1)
    }

    // MARK: - The tile

    /// Six packed stars never run past the tile's side at any size. On the
    /// main actor: both numbers are statics of views.
    @MainActor
    func testSixStarsFitEveryTile() {
        for size in RelicTileSize.allCases {
            let point: CGFloat = RelicTile.starPoint(for: size)
            let row: CGFloat = point * 6 * StarRow.packedAdvance
            let side: CGFloat = size.side
            let fits: Bool = row <= side + 0.001
            XCTAssertTrue(fits, "six stars at \(point) points span \(row) of a \(side)-point tile")
        }
    }

    // MARK: - Sets

    /// Every set has a short line, and every percentage in it is in the
    /// set's own description, so the two cannot drift apart.
    func testEverySetHasAShortLineTrueToItsEffect() {
        for relicSet in RelicSet.allCases {
            let line: String = RelicReading.shortEffect(relicSet)
            let described: String = relicSet.effectDescription
            let percentages: [String] = Self.percentages(in: line)
            XCTAssertFalse(line.isEmpty, "\(relicSet.displayName) has a short line")
            XCTAssertFalse(percentages.isEmpty, "\(relicSet.displayName)'s line carries its number")
            for percent in percentages {
                let found: Bool = described.contains(percent)
                XCTAssertTrue(found, "\(relicSet.displayName)'s \(percent) is in \"\(described)\"")
            }
        }
    }

    /// "Bar +4% per 7% lost" → ["4%", "7%"].
    private static func percentages(in line: String) -> [String] {
        var found: [String] = []
        var digits = ""
        for character in line {
            if character.isASCII && character.isNumber {
                digits.append(character)
                continue
            }
            if character == "%" && !digits.isEmpty {
                found.append(digits + "%")
            }
            digits = ""
        }
        return found
    }

    // MARK: - Builds

    /// A draft counts the slots whose relic differs, emptied and filled
    /// slots included.
    func testADraftCountsTheSlotsItChanges() {
        let ids: [UUID] = (0..<8).map { _ in UUID() }
        let now: [Int: UUID] = [1: ids[0], 2: ids[1], 3: ids[2], 5: ids[3]]
        let unchanged: Int = RelicReading.draftChanges(now: now, then: now)
        XCTAssertEqual(unchanged, 0)

        var swapped = now
        swapped[2] = ids[4]
        let oneSwap: Int = RelicReading.draftChanges(now: now, then: swapped)
        XCTAssertEqual(oneSwap, 1)

        var reworked = now
        reworked[3] = nil
        reworked[6] = ids[5]
        reworked[1] = ids[6]
        let three: Int = RelicReading.draftChanges(now: now, then: reworked)
        XCTAssertEqual(three, 3, "an emptied slot, a filled one and a swapped one")
    }

    /// "Fill empty slots" is today's Auto-equip computed on a copy: the same
    /// build, a worn slot kept, another unit's relic never taken, and the
    /// player itself untouched.
    func testFillEmptyIsAutoEquipOnACopy() throws {
        var rng = SeededRandom(seed: 21)
        var player = Player()
        let blueprint = UnitDatabase.starter
        let unit = Unit(blueprint: blueprint)
        let other = Unit(blueprint: blueprint)
        player.units = [unit, other]
        for slot in 1...6 {
            for _ in 0..<3 {
                player.relics.append(RelicService.generate(grade: 5, slot: slot, rng: &rng))
            }
        }
        let wornHere = try XCTUnwrap(player.relics.first { $0.slot == 1 })
        try RelicService.equip(relicID: wornHere.id, on: unit.id, player: &player)
        let wornThere = try XCTUnwrap(player.relics.first { $0.slot == 2 })
        try RelicService.equip(relicID: wornThere.id, on: other.id, player: &player)

        let preview: [Int: UUID] = RelicReading.fillEmpty(unitID: unit.id, player: player)
        var copy = player
        RelicService.autoEquip(unitID: unit.id, player: &copy)
        let applied: [Int: UUID] = copy.unit(unit.id)?.equippedRelics ?? [:]
        XCTAssertEqual(preview, applied, "the preview is what Auto-equip leaves")

        let filled: Int = preview.count
        XCTAssertEqual(filled, 6, "every slot has a free relic to take")
        XCTAssertEqual(preview[1], wornHere.id, "a worn slot keeps its relic")
        XCTAssertNotEqual(preview[2], wornThere.id, "another unit's relic is never taken")
        let untouched: Int = player.unit(unit.id)?.equippedRelics.count ?? 0
        XCTAssertEqual(untouched, 1, "the player itself is not changed")
    }

    // MARK: - The other readings

    /// The next sub stat waits on +3 for a fresh Normal, on the card for a
    /// roll owed, on the awakening for a 6★ +15 with four, and on nothing
    /// for a Legend with its four below +15.
    func testTheNextSubStatIsNamed() {
        var rng = SeededRandom(seed: 5)
        var normal = RelicService.generate(grade: 6, quality: .normal, rng: &rng)
        let fresh: NextSubStat? = RelicReading.nextSubStat(normal)
        XCTAssertEqual(fresh, NextSubStat.atLevel(3))

        normal.level = 3
        normal.pendingRoll = 99
        let owed: NextSubStat? = RelicReading.nextSubStat(normal)
        XCTAssertEqual(owed, NextSubStat.waiting)

        var legend = RelicService.generate(grade: 6, quality: .legend, rng: &rng)
        let full: NextSubStat? = RelicReading.nextSubStat(legend)
        XCTAssertNil(full, "four subs below +15: nothing to come")

        legend.level = 15
        let peak: NextSubStat? = RelicReading.nextSubStat(legend)
        XCTAssertEqual(peak, NextSubStat.awaken)

        legend.awakened = true
        legend.pendingRoll = 7
        let fifth: NextSubStat? = RelicReading.nextSubStat(legend)
        XCTAssertEqual(fifth, NextSubStat.waiting)
    }

    /// The peak is the relic's own +15, and the awakened one 1.2 times it
    /// (3.6 over 3.0).
    func testThePeakIsTheRelicsOwnPlusFifteen() {
        var rng = SeededRandom(seed: 9)
        let relic = RelicService.generate(grade: 6, slot: 1, quality: .rare, rng: &rng)
        let ordinary: StatModifier = RelicReading.peakMain(relic, awakened: false)
        let awakened: StatModifier = RelicReading.peakMain(relic, awakened: true)
        let projected: StatModifier = relic.projectedMainStat(atLevel: 15)
        XCTAssertEqual(ordinary, projected, "the ordinary peak is the relic's own +15")
        let ratio: Double = awakened.value / ordinary.value
        XCTAssertEqual(ratio, 1.2, accuracy: 1e-9)
    }

    /// The best fit is the role the relic is most efficient for, and its
    /// value is that efficiency.
    func testTheBestFitIsTheHighestEfficiency() {
        var rng = SeededRandom(seed: 13)
        for _ in 0..<20 {
            let relic = RelicService.generate(grade: 6, rng: &rng)
            let best = RelicReading.bestFit(relic)
            let efficiencies: [Double] = CombatRole.allCases.map { RelicService.efficiency(relic, for: $0) }
            let highest: Double = efficiencies.max() ?? -1
            let own: Double = RelicService.efficiency(relic, for: best.role)
            XCTAssertEqual(best.value, highest)
            XCTAssertEqual(own, highest)
        }
    }

    /// A change reads as the two figures show it: 11.6% → 17.4% prints as
    /// 12% → 17%, so the change is 5%, not the raw 5.8's 6%.
    func testAChangeReadsAsTheFiguresShow() {
        let percent: String = RelicReading.shownChange(.critRate, from: 0.116, to: 0.174)
        XCTAssertEqual(percent, "5%")
        let flat: String = RelicReading.shownChange(.spd, from: 11, to: 15)
        XCTAssertEqual(flat, "4")
    }

    /// The confirmation's title counts in words that agree with the number.
    func testTheConfirmationSaysHowMany() {
        let one: String = RelicConfirm.leaveDraft(changes: 1).title
        let two: String = RelicConfirm.leaveDraft(changes: 2).title
        XCTAssertEqual(one, "1 change not applied")
        XCTAssertEqual(two, "2 changes not applied")
    }
}
