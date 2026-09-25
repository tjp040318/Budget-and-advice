import Foundation

/// One clip's timing as it shipped: its length, and where in it each strike
/// lands.
///
/// `seconds` is the clip's own length, measured off the shipped file;
/// `contacts` are the fractions of it at which its strikes land, in order —
/// a hand's speed peaking on a blow, an arrow's loose, a cast's thrust. A
/// rite's release, or a cast's, is one contact.
struct ClipTiming: Equatable, Sendable {
    let seconds: Double
    let contacts: [Double]
}

/// When a clip's blows land, and how long it is played for (Docs/PLAN.md
/// *Skills that look like themselves*, 2026-09-25).
///
/// The battle had ONE number per clip — `BattleSceneController`'s
/// `contactFraction`, 0.42 of a basic, 0.55 of a heavy — and a clip's
/// length was its `fallbackDuration` whatever Meshy had made. The first
/// damage event of a cast landed on that number and every later hit 0.30 to
/// 0.55 s after the one before, whatever the body was doing, so a three-hit
/// skill was one swing and three numbers. The genre's rule is that the body
/// strikes as many times as the numbers, where the numbers are; this table
/// is where the numbers are.
///
/// It is `Resources/Models/clip_timings.json`, written by
/// `tools/skill_moves.py timings` from the shipped files, never by hand:
/// `{"version": 1, "assets": {"horus": {"skill_x4": {"seconds": 2.9,
/// "contacts": [0.18, 0.37, 0.55, 0.74]}}}}`, keyed by the asset whose clips
/// play (`UnitNode.clipAsset`) and the clip's raw value. A clip with no entry
/// keeps the old single numbers and the five gods' bespoke rows below, so
/// the fight is timed as it was until the tool has measured it.
///
/// Every function here is pure or reads a table that never changes after it
/// is read, so it is called from the main thread, the warm pass's queue and
/// the renderer's thread alike, with no isolation and no lock.
enum ClipTimings {

    // MARK: - The table

    /// The version of the table's format this reader understands. A table
    /// of a later version is refused whole, since its fields may mean
    /// something else, and every clip falls back to its old timing.
    static let formatVersion = 1

    /// The bundle's table, asset by clip raw value, read the first time any
    /// clip is timed. Swift runs a static's initialiser once, whichever
    /// thread asks first, and nothing writes the table afterwards.
    static let table: [String: [String: ClipTiming]] = {
        let name = "clip_timings"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: ModelLibrary.modelDirectory)
                ?? Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            log("no clip_timings.json in the bundle: every clip keeps its old timing")
            return [:]
        }
        let parsed = parse(data)
        let clips: Int = parsed.values.reduce(0) { $0 + $1.count }
        log("\(clips) clip(s) of \(parsed.count) asset(s) timed from \(url.lastPathComponent)")
        return parsed
    }()

    /// The bundle's entry for one clip of one asset, or nil.
    static func timing(asset: String, clip: AnimationClip) -> ClipTiming? {
        table[asset]?[clip.rawValue]
    }

    /// Parses a table (the tests hand it a string). Tolerant entry by
    /// entry: an entry without a positive length is dropped and the rest of
    /// its asset kept, contacts are clamped into the clip and put in order,
    /// and anything that is not a table at all reads as an empty one. A clip
    /// key is kept as written; one that names no `AnimationClip` is simply
    /// never asked for, and `ClipTimingTests` fails on one in the bundle.
    static func parse(_ data: Data) -> [String: [String: ClipTiming]] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        if let version = (root["version"] as? NSNumber)?.intValue, version > formatVersion {
            log("the table is version \(version); this build reads \(formatVersion) and ignores it")
            return [:]
        }
        guard let assets = root["assets"] as? [String: Any] else { return [:] }
        var parsed: [String: [String: ClipTiming]] = [:]
        for (asset, value) in assets {
            guard let clips = value as? [String: Any] else { continue }
            var row: [String: ClipTiming] = [:]
            for (clip, entry) in clips {
                guard let fields = entry as? [String: Any],
                      let seconds = (fields["seconds"] as? NSNumber)?.doubleValue,
                      seconds.isFinite, seconds > 0 else { continue }
                let listed: [Any] = (fields["contacts"] as? [Any]) ?? []
                let contacts: [Double] = listed
                    .compactMap { ($0 as? NSNumber)?.doubleValue }
                    .filter { $0.isFinite }
                    .map { min(1, max(0, $0)) }
                    .sorted()
                row[clip] = ClipTiming(seconds: seconds, contacts: contacts)
            }
            if !row.isEmpty { parsed[asset] = row }
        }
        return parsed
    }

    // MARK: - The contract

    /// The fastest and the slowest a one-shot clip is played
    /// (`UnitNode.play`): past twice its speed a swing is a flicker, and
    /// under 0.6 of it a mime.
    static let fastest: Double = 2.0
    static let slowest: Double = 0.6

    /// The longest each attack clip may take: a clip longer than this is
    /// sped up to fit it, one shorter plays at its own length. The owner's
    /// Summoners War plays a basic in about a second and a half and an
    /// ultimate in two to three; a clip made from a sentence comes back
    /// anywhere from two seconds to four. The ceilings were set on the
    /// shipped set (2026-09-25): the signature basics are 2.0 and 2.5 s and
    /// the composed flurries 1.9-4.0 s, and none is played more than 1.25x
    /// its own speed (a two-blow basic at 1.6 s ran at 1.56x, a flicker).
    /// Nil for a clip the fight does not
    /// time by its contacts (an idle, a flinch, a death), which keeps its
    /// `fallbackDuration` as it always has.
    static func ceiling(for clip: AnimationClip) -> Double? {
        switch clip {
        case .attackBasic: return 2.0
        case .attackHeavy: return 2.0
        case .skillX2: return 2.4
        case .skillX3: return 2.8
        case .skillX4: return 3.2
        case .skillX5: return 3.6
        case .skillArea: return 2.6
        case .castRelease: return 2.8
        case .ultimate: return 3.4
        default: return nil
        }
    }

    /// The seconds the clip is played in (its contract): the clip's own
    /// length, sped up to its ceiling when longer — basic 2.0, attackHeavy
    /// 2.0, skillX2 2.4, skillX3 2.8, skillX4 3.2, skillX5 3.6, skillArea
    /// 2.6, castRelease 2.8, ultimate 3.4 (`ceiling(for:)`) — and never
    /// slowed; without an entry, the clip's `fallbackDuration`.
    /// `UnitNode.play` retimes the clip to exactly this, so a contact read
    /// here is a contact on screen.
    static func contract(asset: String, clip: AnimationClip) -> Double {
        playedLength(of: timing(asset: asset, clip: clip), clip: clip)
    }

    /// `contract(asset:clip:)` for an entry in hand (nil: no entry). A clip
    /// more than twice its ceiling cannot be played in it — the play rate
    /// stops at `fastest` — so its contract is half its length: the seconds
    /// it really takes, which the hits are timed by.
    static func playedLength(of entry: ClipTiming?, clip: AnimationClip) -> Double {
        guard let entry, let cap = ceiling(for: clip) else { return clip.fallbackDuration }
        if entry.seconds <= cap { return entry.seconds }
        return max(cap, entry.seconds / fastest)
    }

    // MARK: - The hits

    /// A hit the clip does not show follows the one before it by this many
    /// seconds of the contract: a flurry too quick to count, the best a clip
    /// with fewer strikes than the skill has hits can do.
    static let flurryGap: Double = 0.13
    /// No hit the clip does not show lands later than this share of the
    /// contract, so the last of a flurry is still in the follow-through.
    static let latestSpread: Double = 0.95

    /// Where hit k of `hits` lands, as fractions of the contract: the
    /// entry's contacts when there are exactly `hits`; the LAST `hits` when
    /// there are more (a single-target cast of a clip that strikes three
    /// times lands on its final, biggest blow); when fewer, the missing hits
    /// follow the last contact `flurryGap` seconds apart, drawn closer when
    /// that would run past `latestSpread`, never past it; with no entry, the
    /// old single numbers (basic 0.42, heavy 0.55, cast 0.60, ultimate 0.62)
    /// and the five gods' rows. Empty for no hits.
    static func hitFractions(asset: String, clip: AnimationClip, hits: Int) -> [Double] {
        strikeFractions(of: timing(asset: asset, clip: clip), asset: asset, clip: clip, hits: hits)
    }

    /// `hitFractions(asset:clip:hits:)` for an entry in hand (nil: no
    /// entry). An entry that measured no contacts is read as having none of
    /// its own, and takes the clip's stand-ins.
    static func strikeFractions(of entry: ClipTiming?, asset: String, clip: AnimationClip, hits: Int) -> [Double] {
        guard hits > 0 else { return [] }
        let measured: [Double] = entry?.contacts ?? []
        let contacts: [Double] = measured.isEmpty ? standInContacts(asset: asset, clip: clip) : measured
        if contacts.count >= hits { return Array(contacts.suffix(hits)) }
        guard let last = contacts.last else { return [] }
        let length: Double = playedLength(of: entry, clip: clip)
        let missing: Int = hits - contacts.count
        let room: Double = max(0, latestSpread - last)
        let step: Double = min(flurryGap / max(0.05, length), room / Double(missing))
        var fractions: [Double] = contacts
        for extra in 1...missing {
            fractions.append(last + step * Double(extra))
        }
        return fractions
    }

    /// Where a clip with no measured contacts strikes. The five gods'
    /// bespoke clips first (`godsContacts`), for the god and for its
    /// awakened form, which plays the god's clips retargeted. Then the
    /// numbers every clip was timed by before the table existed; a
    /// multi-strike shape, which had none, strikes at the middles of equal
    /// slices of its middle 60%. The rite's release is its own 0.60: it
    /// never plays the heavy clip (`AnimationClip.fallbackClip`), so it no
    /// longer reads the heavy's row.
    static func standInContacts(asset: String, clip: AnimationClip) -> [Double] {
        let family: String = asset.hasSuffix(awakenedSuffix) ? String(asset.dropLast(awakenedSuffix.count)) : asset
        if let bespoke = godsContacts[family]?[clip] { return [bespoke] }
        switch clip {
        case .attackBasic: return [0.42]
        case .attackHeavy, .skillArea: return [0.55]
        case .castRelease: return [0.60]
        case .ultimate: return [0.62]
        case .skillX2, .skillX3, .skillX4, .skillX5:
            let count: Int = clip.strikeCount
            let slice: Double = 0.6 / Double(count)
            return (0..<count).map { (index: Int) -> Double in 0.2 + slice * (Double(index) + 0.5) }
        default: return [0.50]
        }
    }

    /// The five gods' bespoke clips (the fourteen sentences of 2026-09-15),
    /// where each blow was read off the clip's frames (`preview.py
    /// --frame`). They were `BattleSceneController.contactFraction`'s table
    /// until the timings had a table of their own; an entry in
    /// `clip_timings.json` replaces a row.
    private static let godsContacts: [String: [AnimationClip: Double]] = [
        "anubis": [.attackBasic: 0.38, .attackHeavy: 0.50, .ultimate: 0.55],
        "sekhmet": [.attackBasic: 0.45, .attackHeavy: 0.42, .ultimate: 0.45],
        // Zeus's ultimate is the 2026-09-17 take: arms overhead to 0.3, a
        // crouched lunge, the hurl at 0.78.
        "zeus": [.attackBasic: 0.47, .attackHeavy: 0.40, .ultimate: 0.78],
        "ares": [.attackBasic: 0.47, .attackHeavy: 0.50, .ultimate: 0.45],
        "thoth": [.attackBasic: 0.55, .attackHeavy: 0.60, .ultimate: 0.65],
    ]

    /// An awakened form's clips are its own file set (`<asset>_awakened`),
    /// and the gods' awakened forms play their god's motions retargeted.
    private static let awakenedSuffix = "_awakened"

    /// A line to the console and to `DiagnosticsLog` (More → Diagnostics),
    /// so a phone can say whether its build carried the table.
    private static func log(_ message: String) {
        #if DEBUG
        print("[ClipTimings] \(message)")
        DiagnosticsLog.shared.record("[ClipTimings] \(message)")
        #endif
    }
}
