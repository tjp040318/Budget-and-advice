import XCTest
@testable import Pantheon

/// When a clip's blows land and how long it is played for (`ClipTimings`,
/// Docs/PLAN.md *Skills that look like themselves*): the table read from
/// its JSON, the contract (the clip's own length, sped up to its kind's
/// ceiling and never slowed), and where each hit of a cast lands (the
/// clip's own contacts, the last of them, or a flurry after them). Every
/// case is read off a table parsed from a string here, or off an asset the
/// bundle's table will never hold, so the tests stand as the tool fills the
/// real one. Every figure an assert compares is hoisted into a typed `let`
/// first (CLAUDE.md).
final class ClipTimingTests: XCTestCase {

    private let tolerance: Double = 1e-9

    /// An asset no table will ever time.
    private let nobody = "clip_timing_tests_nobody"

    /// A table as `tools/skill_moves.py timings` writes one, with the faults
    /// the reader must survive: contacts out of order and out of the clip,
    /// an entry with no length, a row that is not a row, an entry with no
    /// contacts.
    private let sample = """
    {"version": 1,
     "assets": {"horus": {"attack_basic": {"seconds": 1.73, "contacts": [0.62, 0.41]},
                          "skill_x4": {"seconds": 2.9, "contacts": [0.18, 0.37, 0.55, 0.74]},
                          "ultimate": {"seconds": 0, "contacts": [0.5]},
                          "cast_release": {"seconds": 2.1, "contacts": [1.4, -0.2]}},
                "zeus": "not a row",
                "anubis": {"attack_heavy": {"seconds": 5.0}}}}
    """

    private func sampleTable() -> [String: [String: ClipTiming]] {
        ClipTimings.parse(Data(sample.utf8))
    }

    private func entry(_ asset: String, _ clip: AnimationClip) throws -> ClipTiming {
        try XCTUnwrap(sampleTable()[asset]?[clip.rawValue], "\(asset) \(clip.rawValue) is in the sample")
    }

    /// Whether two lists of fractions are alike to within `tolerance`, one
    /// by one. The caller asserts it, so a failure is reported on its line.
    private func alike(_ actual: [Double], _ expected: [Double]) -> Bool {
        guard actual.count == expected.count else { return false }
        for (got, wanted) in zip(actual, expected) where abs(got - wanted) > tolerance {
            return false
        }
        return true
    }

    // MARK: - The table

    func testParseReadsTheLengthAndTheContactsInOrder() throws {
        let basic = try entry("horus", .attackBasic)
        let seconds: Double = basic.seconds
        let basicContacts: [Double] = [0.41, 0.62]
        XCTAssertEqual(seconds, 1.73, accuracy: tolerance)
        XCTAssertTrue(alike(basic.contacts, basicContacts), "\(basic.contacts)")
        let fourCuts = try entry("horus", .skillX4)
        let fourContacts: [Double] = [0.18, 0.37, 0.55, 0.74]
        XCTAssertTrue(alike(fourCuts.contacts, fourContacts), "\(fourCuts.contacts)")
    }

    func testParseKeepsTheRestOfAnAssetWhenOneEntryIsBad() throws {
        let table = sampleTable()
        let horusClips: Int = table["horus"]?.count ?? 0
        XCTAssertEqual(horusClips, 3, "the ultimate with no length is dropped, the other three kept")
        XCTAssertNil(table["horus"]?[AnimationClip.ultimate.rawValue])
        XCTAssertNil(table["zeus"], "a row that is not a row is skipped")
        let noContacts = try entry("anubis", .attackHeavy)
        XCTAssertTrue(noContacts.contacts.isEmpty, "an entry may measure no contacts")
    }

    func testParseClampsContactsIntoTheClip() throws {
        let rite = try entry("horus", .castRelease)
        let clamped: [Double] = [0, 1]
        XCTAssertTrue(alike(rite.contacts, clamped), "\(rite.contacts)")
    }

    func testParseRefusesALaterVersionAndAnythingThatIsNotATable() {
        let later = ClipTimings.parse(Data(#"{"version": 2, "assets": {"horus": {"attack_basic": {"seconds": 1.2, "contacts": [0.4]}}}}"#.utf8))
        let garbage = ClipTimings.parse(Data("not json".utf8))
        let noAssets = ClipTimings.parse(Data(#"{"version": 1}"#.utf8))
        let empty = ClipTimings.parse(Data(#"{"version": 1, "assets": {}}"#.utf8))
        XCTAssertTrue(later.isEmpty, "a later version's fields may mean something else")
        XCTAssertTrue(garbage.isEmpty)
        XCTAssertTrue(noAssets.isEmpty)
        XCTAssertTrue(empty.isEmpty)
    }

    /// The bundle carries the table, and whatever the tool has written into
    /// it names real clips, each with a length and its contacts inside the
    /// clip, in order — read off the RAW file, since the reader clamps a
    /// contact into the clip and would hide a tool that wrote frames or
    /// seconds — and every entry written is an entry read.
    func testTheBundledTableIsWellFormed() throws {
        let found = Bundle.main.url(forResource: "clip_timings", withExtension: "json", subdirectory: ModelLibrary.modelDirectory)
            ?? Bundle.main.url(forResource: "clip_timings", withExtension: "json")
        let url = try XCTUnwrap(found, "clip_timings.json is in the app")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let root = try XCTUnwrap(object as? [String: Any], "the table is a JSON object")
        let version: Int = (root["version"] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(version, ClipTimings.formatVersion)
        let assets = try XCTUnwrap(root["assets"] as? [String: Any], "the table has its assets")
        var written = 0
        for (asset, row) in assets {
            let clips = try XCTUnwrap(row as? [String: Any], "\(asset) is a row of clips")
            for (name, value) in clips {
                written += 1
                let label = "\(asset) \(name)"
                XCTAssertNotNil(AnimationClip(rawValue: name), "\(label) is not a clip")
                let fields = try XCTUnwrap(value as? [String: Any], label)
                let seconds: Double = (fields["seconds"] as? NSNumber)?.doubleValue ?? 0
                XCTAssertGreaterThan(seconds, 0, label)
                let listed: [Any] = (fields["contacts"] as? [Any]) ?? []
                let contacts: [Double] = listed.compactMap { ($0 as? NSNumber)?.doubleValue }
                let ordered: [Double] = contacts.sorted()
                XCTAssertFalse(contacts.isEmpty, "\(label) has no contacts")
                XCTAssertEqual(contacts, ordered, "\(label): its contacts are out of order")
                for contact in contacts {
                    XCTAssertGreaterThanOrEqual(contact, 0, label)
                    XCTAssertLessThanOrEqual(contact, 1, "\(label): a contact is a share of the clip, not a frame")
                }
            }
        }
        let read: Int = ClipTimings.table.values.reduce(0) { $0 + $1.count }
        XCTAssertEqual(read, written, "every entry the tool wrote is read")
    }

    // MARK: - The contract

    func testAClipUnderItsCeilingPlaysAtItsOwnLength() {
        let short = ClipTiming(seconds: 1.2, contacts: [0.4])
        let basic: Double = ClipTimings.playedLength(of: short, clip: .attackBasic)
        let threeCuts = ClipTiming(seconds: 2.3, contacts: [0.2, 0.5, 0.8])
        let flurry: Double = ClipTimings.playedLength(of: threeCuts, clip: .skillX3)
        XCTAssertEqual(basic, 1.2, accuracy: tolerance, "never slowed to fill its ceiling")
        XCTAssertEqual(flurry, 2.3, accuracy: tolerance)
    }

    func testAClipOverItsCeilingIsSpedUpToIt() {
        let cases: [(clip: AnimationClip, seconds: Double, ceiling: Double)] = [
            (.attackBasic, 2.9, 2.0),
            (.attackHeavy, 2.4, 2.0),
            (.skillX2, 2.9, 2.4),
            (.skillX3, 3.3, 2.8),
            (.skillX4, 3.8, 3.2),
            (.skillX5, 4.2, 3.6),
            (.skillArea, 2.9, 2.6),
            (.castRelease, 3.2, 2.8),
            (.ultimate, 4.0, 3.4),
        ]
        for item in cases {
            let long = ClipTiming(seconds: item.seconds, contacts: [0.5])
            let played: Double = ClipTimings.playedLength(of: long, clip: item.clip)
            XCTAssertEqual(played, item.ceiling, accuracy: tolerance, item.clip.rawValue)
        }
    }

    /// Past twice its ceiling a clip cannot be played in it — the rate
    /// stops at 2x — so its contract is half its length.
    func testAClipOverTwiceItsCeilingTakesHalfItsLength() {
        let long = ClipTiming(seconds: 4.0, contacts: [0.5])
        let played: Double = ClipTimings.playedLength(of: long, clip: .attackBasic)
        let half: Double = 4.0 / ClipTimings.fastest
        XCTAssertEqual(played, half, accuracy: tolerance)
    }

    func testAClipWithNoEntryKeepsItsFallbackDuration() {
        let heavy: Double = ClipTimings.playedLength(of: nil, clip: .attackHeavy)
        let rite: Double = ClipTimings.playedLength(of: nil, clip: .castRelease)
        let fiveShots: Double = ClipTimings.playedLength(of: nil, clip: .skillX5)
        let bundled: Double = ClipTimings.contract(asset: nobody, clip: .ultimate)
        XCTAssertEqual(heavy, 1.7, accuracy: tolerance)
        XCTAssertEqual(rite, 2.2, accuracy: tolerance)
        XCTAssertEqual(fiveShots, 3.2, accuracy: tolerance)
        XCTAssertEqual(bundled, 2.4, accuracy: tolerance)
    }

    /// A clip the fight does not time by its contacts keeps its old length
    /// even with an entry: a flinch is still played in half a second.
    func testAClipWithNoCeilingKeepsItsFallbackEvenWithAnEntry() {
        let flinch = ClipTiming(seconds: 1.0, contacts: [0.3])
        let played: Double = ClipTimings.playedLength(of: flinch, clip: .hitReact)
        XCTAssertEqual(played, 0.5, accuracy: tolerance)
    }

    /// No clip's fallback runs past its ceiling, so an unmeasured clip is
    /// never played slower than a measured one could be.
    func testEveryFallbackFitsUnderItsCeiling() {
        for clip in AnimationClip.allCases {
            guard let cap = ClipTimings.ceiling(for: clip) else { continue }
            let fallback: Double = clip.fallbackDuration
            XCTAssertLessThanOrEqual(fallback, cap, clip.rawValue)
        }
    }

    // MARK: - The hits

    func testAsManyContactsAsHitsAreTheClipsOwn() throws {
        let fourCuts = try entry("horus", .skillX4)
        let hits = ClipTimings.strikeFractions(of: fourCuts, asset: "horus", clip: .skillX4, hits: 4)
        let own: [Double] = [0.18, 0.37, 0.55, 0.74]
        XCTAssertTrue(alike(hits, own), "\(hits)")
    }

    /// More strikes in the clip than hits in the skill: the last of them,
    /// the biggest blow last.
    func testMoreContactsThanHitsTakeTheLast() throws {
        let fourCuts = try entry("horus", .skillX4)
        let two = ClipTimings.strikeFractions(of: fourCuts, asset: "horus", clip: .skillX4, hits: 2)
        let one = ClipTimings.strikeFractions(of: fourCuts, asset: "horus", clip: .skillX4, hits: 1)
        let lastTwo: [Double] = [0.55, 0.74]
        let lastOne: [Double] = [0.74]
        XCTAssertTrue(alike(two, lastTwo), "\(two)")
        XCTAssertTrue(alike(one, lastOne), "\(one)")
    }

    /// Fewer strikes than hits: the rest follow the last contact 0.13 s of
    /// the contract apart. The basic here is 1.73 s, under its 2.0 s
    /// ceiling, so it plays at its own length and 0.13 s is 0.0751 of it.
    func testFewerContactsThanHitsFollowTheLastOne() throws {
        let basic = try entry("horus", .attackBasic)
        let hits = ClipTimings.strikeFractions(of: basic, asset: "horus", clip: .attackBasic, hits: 4)
        let step: Double = 0.13 / 1.73
        let third: Double = 0.62 + step
        let fourth: Double = 0.62 + 2 * step
        let spread: [Double] = [0.41, 0.62, third, fourth]
        XCTAssertTrue(alike(hits, spread), "\(hits)")
    }

    /// A flurry that would run past 95% of the contract is drawn closer
    /// instead, in order, the last of it on 0.95.
    func testASpreadNeverRunsPastNinetyFivePercent() {
        let late = ClipTiming(seconds: 1.0, contacts: [0.9])
        let hits = ClipTimings.strikeFractions(of: late, asset: nobody, clip: .attackHeavy, hits: 5)
        let drawnIn: [Double] = [0.9, 0.9125, 0.925, 0.9375, 0.95]
        XCTAssertTrue(alike(hits, drawnIn), "\(hits)")
        for (earlier, later) in zip(hits, hits.dropFirst()) {
            XCTAssertLessThan(earlier, later)
        }
        let last: Double = hits.last ?? 0
        let latest: Double = ClipTimings.latestSpread + tolerance
        XCTAssertLessThanOrEqual(last, latest)
    }

    /// With no entry, every clip strikes where the fight struck before the
    /// table: basic 0.42, heavy 0.55, rite 0.60, ultimate 0.62; the line's
    /// blow as the heavy.
    func testAClipWithNoEntryStrikesOnTheOldNumbers() {
        let basic = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .attackBasic, hits: 1)
        let heavy = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .attackHeavy, hits: 1)
        let rite = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .castRelease, hits: 1)
        let ultimate = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .ultimate, hits: 1)
        let area = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .skillArea, hits: 1)
        let bundled = ClipTimings.hitFractions(asset: nobody, clip: .attackBasic, hits: 1)
        let basicAt: [Double] = [0.42]
        let heavyAt: [Double] = [0.55]
        let riteAt: [Double] = [0.60]
        let ultimateAt: [Double] = [0.62]
        XCTAssertTrue(alike(basic, basicAt), "\(basic)")
        XCTAssertTrue(alike(heavy, heavyAt), "\(heavy)")
        XCTAssertTrue(alike(rite, riteAt), "\(rite)")
        XCTAssertTrue(alike(ultimate, ultimateAt), "\(ultimate)")
        XCTAssertTrue(alike(area, heavyAt), "\(area)")
        XCTAssertTrue(alike(bundled, basicAt), "\(bundled)")
    }

    /// The five gods keep the blows read off their bespoke clips, awakened
    /// or not; their rite, no longer the heavy clip, has its own 0.60.
    func testTheGodsKeepTheirBespokeContacts() throws {
        let zeusUltimate = ClipTimings.strikeFractions(of: nil, asset: "zeus", clip: .ultimate, hits: 1)
        let awakenedUltimate = ClipTimings.strikeFractions(of: nil, asset: "zeus_awakened", clip: .ultimate, hits: 1)
        let anubisBasic = ClipTimings.strikeFractions(of: nil, asset: "anubis", clip: .attackBasic, hits: 1)
        let thothHeavy = ClipTimings.strikeFractions(of: nil, asset: "thoth", clip: .attackHeavy, hits: 1)
        let zeusRite = ClipTimings.strikeFractions(of: nil, asset: "zeus", clip: .castRelease, hits: 1)
        let hurl: [Double] = [0.78]
        let jackalsDue: [Double] = [0.38]
        let thothBlow: [Double] = [0.60]
        let riteRelease: [Double] = [0.60]
        XCTAssertTrue(alike(zeusUltimate, hurl), "\(zeusUltimate)")
        XCTAssertTrue(alike(awakenedUltimate, hurl), "\(awakenedUltimate)")
        XCTAssertTrue(alike(anubisBasic, jackalsDue), "\(anubisBasic)")
        XCTAssertTrue(alike(thothHeavy, thothBlow), "\(thothHeavy)")
        XCTAssertTrue(alike(zeusRite, riteRelease), "\(zeusRite)")
        // An entry that measured nothing still reads the god's row.
        let measuredNothing = try entry("anubis", .attackHeavy)
        let anubisHeavy = ClipTimings.strikeFractions(of: measuredNothing, asset: "anubis", clip: .attackHeavy, hits: 1)
        let anubisBlow: [Double] = [0.50]
        XCTAssertTrue(alike(anubisHeavy, anubisBlow), "\(anubisHeavy)")
    }

    /// A shape with no entry strikes at the middles of equal slices of its
    /// clip's middle 60%.
    func testAShapeWithNoEntryStrikesAcrossTheMiddleOfItsClip() {
        let two = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .skillX2, hits: 2)
        let three = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .skillX3, hits: 3)
        let five = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .skillX5, hits: 5)
        let twoAt: [Double] = [0.35, 0.65]
        let threeAt: [Double] = [0.3, 0.5, 0.7]
        let fiveAt: [Double] = [0.26, 0.38, 0.5, 0.62, 0.74]
        XCTAssertTrue(alike(two, twoAt), "\(two)")
        XCTAssertTrue(alike(three, threeAt), "\(three)")
        XCTAssertTrue(alike(five, fiveAt), "\(five)")
    }

    /// The heavy blow standing in for a three-strike shape: the blow, then
    /// the two hits it does not show 0.13 s apart over its 1.7 s.
    func testAHeavyBlowStandingInForAFlurry() {
        let hits = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .attackHeavy, hits: 3)
        let step: Double = 0.13 / 1.7
        let second: Double = 0.55 + step
        let third: Double = 0.55 + 2 * step
        let flurry: [Double] = [0.55, second, third]
        XCTAssertTrue(alike(hits, flurry), "\(hits)")
    }

    func testNoHitsAreNoFractions() {
        let none = ClipTimings.strikeFractions(of: nil, asset: nobody, clip: .attackHeavy, hits: 0)
        XCTAssertTrue(none.isEmpty)
    }
}
