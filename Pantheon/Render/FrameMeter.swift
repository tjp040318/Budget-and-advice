import Foundation

/// A stage's frame pacing, counted on the render thread (Docs/FEEL.md W2.26).
///
/// "Inconsistent frame delivery feels worse than a stable lower frame rate",
/// and the gap between the average and the 1% low is what says so. The game
/// had a main-thread watchdog (`Perf`) and no frame count at all, so a hitch
/// was a feeling the owner reported rather than a number a run printed.
///
/// Every stage's render delegate wears a `StageRenderGovernor`, which hands
/// each `renderer(_:updateAtTime:)` to `record(at:)`: the interval since the
/// last frame goes into a fixed histogram of `bucketCount` half-millisecond
/// buckets (the last collects everything longer), one integer bumped under a
/// lock, nothing allocated. A gap longer than `pauseGap` is a stage that
/// stopped drawing (a hidden island, a view taken off the screen), never a
/// frame, and is left out.
///
/// It speaks in one line, `[Frames] battle p50 16.8 p95 18.3 p99 41.3 · 3
/// over 33 ms of 1,812`, to the console and to More → Diagnostics: when its
/// stage goes (`report(final:)` from the governor's deinit) and, under the CI
/// tour, every `tourEvery` seconds of drawing, so the line nearest a
/// photograph is never more than a few seconds old (`tools/ciframes.py`
/// prints each step's). A single frame over `hitchLine` prints a line of its
/// own under the tour, with when it came: the first ultimate's compile, if
/// W2.24's pre-draw missed one, is that line.
///
/// The simulator's GPU is not a phone's: read CI's numbers as trends between
/// runs, and the phone's Diagnostics for the absolute ones.
final class FrameMeter {

    /// Half a millisecond a bucket, 256 buckets: 0–128 ms, the last bucket
    /// everything longer.
    static let bucketWidth: Double = 0.0005
    static let bucketCount = 256
    /// A frame over this is a missed frame at 30 and two at 60.
    static let slowFrame: Double = 1.0 / 30.0
    /// A gap this long is a stage that stopped drawing, not a frame.
    static let pauseGap: Double = 2.0
    /// A frame this long gets a line of its own under the tour.
    static let hitchLine: Double = 0.1
    /// Seconds of drawing between the tour's lines.
    static let tourEvery: Double = 3.0
    /// Hitch lines a stage may print, so a stuttering simulator cannot
    /// drown the console.
    static let mostHitchLines = 24

    let name: String
    private let lock = NSLock()
    private var counts = [UInt32](repeating: 0, count: FrameMeter.bucketCount)
    private var frames = 0
    private var slow = 0
    private var worst: Double = 0
    private var last: TimeInterval?
    /// Seconds of drawing since the meter began, and since the last line.
    private var drawn: Double = 0
    private var sinceLine: Double = 0
    private var hitchLines = 0
    private let touring: Bool

    init(name: String) {
        self.name = name
        touring = ProcessInfo.processInfo.arguments.contains("-tour")
    }

    /// The render thread, once a frame: the interval since the last frame
    /// counted. Returns the line to print under the tour when one is due
    /// (the caller prints it, outside the lock), and nil otherwise.
    @discardableResult
    func record(at time: TimeInterval) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let previous = last else {
            last = time
            return nil
        }
        last = time
        let interval: Double = time - previous
        guard interval >= 0, interval < Self.pauseGap else { return nil }
        let index: Int = Self.bucket(for: interval)
        counts[index] &+= 1
        frames += 1
        if interval > Self.slowFrame { slow += 1 }
        if interval > worst { worst = interval }
        drawn += interval
        sinceLine += interval
        guard touring else { return nil }
        if interval > Self.hitchLine, hitchLines < Self.mostHitchLines {
            hitchLines += 1
            let at = String(format: "%.1f", drawn)
            let long = Int((interval * 1000).rounded())
            return "[Frames] \(name) hitch \(long) ms at \(at) s"
        }
        if sinceLine >= Self.tourEvery {
            sinceLine = 0
            return line(suffix: "")
        }
        return nil
    }

    /// The whole of the stage's pacing so far as its line, or nil before a
    /// frame has been counted. `final` marks the line its stage's last.
    func report(final: Bool) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard frames > 0 else { return nil }
        return line(suffix: final ? " (the stage gone)" : "")
    }

    /// Under the lock.
    private func line(suffix: String) -> String {
        let p50 = Self.percentile(0.50, of: counts)
        let p95 = Self.percentile(0.95, of: counts)
        let p99 = Self.percentile(0.99, of: counts)
        let figures = String(format: "p50 %.1f p95 %.1f p99 %.1f", p50 * 1000, p95 * 1000, p99 * 1000)
        let longest = Int((worst * 1000).rounded())
        return "[Frames] \(name) \(figures) · \(slow) over 33 ms of \(frames.formatted()), the longest \(longest) ms\(suffix)"
    }

    // MARK: The sums (pure, pinned in BattleFeelTests)

    /// The bucket an interval falls in: half a millisecond each, the last
    /// holding everything longer.
    static func bucket(for interval: Double) -> Int {
        let raw: Double = max(0, interval) / bucketWidth
        guard raw < Double(bucketCount - 1) else { return bucketCount - 1 }
        return Int(raw)
    }

    /// The interval `fraction` of the counted frames came in under, read off
    /// the histogram as the middle of the bucket that crosses it; 0 when
    /// nothing is counted.
    static func percentile(_ fraction: Double, of counts: [UInt32]) -> Double {
        var total: UInt64 = 0
        for count in counts { total += UInt64(count) }
        guard total > 0 else { return 0 }
        let wanted: Double = min(1, max(0, fraction)) * Double(total)
        var running: UInt64 = 0
        for (index, count) in counts.enumerated() {
            running += UInt64(count)
            if Double(running) >= wanted, count > 0 {
                return (Double(index) + 0.5) * bucketWidth
            }
        }
        return (Double(counts.count) - 0.5) * bucketWidth
    }
}
