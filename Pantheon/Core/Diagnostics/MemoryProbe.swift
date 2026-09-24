import Foundation
import UIKit
import os

extension Notification.Name {
    /// Posted on the MAIN thread when iOS says memory is short: UIKit's
    /// memory warning, or the kernel's memory-pressure event (warning or
    /// critical), at most once a second. A cache that can be rebuilt — the
    /// parsed models, decoded textures, card images — observes it and lets go
    /// of what nothing on the screen is using. `userInfo["level"]` is
    /// "warning" or "critical", `userInfo["source"]` "uikit" or "kernel".
    static let pantheonMemoryPressure = Notification.Name("PantheonMemoryPressure")
}

/// How much memory the app holds, in the number iOS kills it by.
///
/// `phys_footprint` (task_info TASK_VM_INFO) is the figure the jetsam limit
/// is measured against — Xcode's memory gauge shows the same number — and
/// `os_proc_available_memory()` is how far the process is from that limit
/// right now (zero where the OS gives no figure, as in the simulator). The
/// two together say whether a kill was coming: a 6 GB phone gives a game
/// about 3 GB, a 4 GB phone about 2, and an app over its limit in the
/// foreground is killed with no crash report at all — only a count in
/// MetricKit's daily exit metrics.
///
/// `log(_:)` prints `[Mem] <label> footprint N MB, available M MB, peak P MB`
/// to the console and More → Diagnostics; anything may call it. `start()`
/// (PantheonApp, at launch) samples the footprint every two seconds for the
/// session's high-water mark, persists it with a heartbeat so the NEXT launch
/// can say how the session ended (`CrashReporter`), and turns memory
/// warnings into `.pantheonMemoryPressure`.
enum MemoryProbe {

    struct Reading: Sendable {
        /// Bytes charged to the process (phys_footprint).
        let footprint: UInt64
        /// Bytes left before the limit; 0 when the OS gives no figure.
        let available: UInt64

        var footprintMB: Int { Int(footprint / 1_048_576) }
        var availableMB: Int? { available > 0 ? Int(available / 1_048_576) : nil }
        var availableText: String { availableMB.map { "\($0)" } ?? "n/a" }
    }

    /// What the last session left behind, read before `start()` clears it.
    struct SessionRecord: Sendable {
        var peakMB: Int
        var peakAt: Date?
        var peakLabel: String?
        var lastMB: Int
        var lastAvailableMB: Int?
        var lastAt: Date?
        var warnings: Int
    }

    // MARK: - Reading

    /// The process footprint in bytes; 0 if the kernel refuses.
    static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    /// Bytes the process may still take before iOS kills it; 0 where the OS
    /// gives no figure (the simulator).
    static func availableBytes() -> UInt64 {
        UInt64(max(0, os_proc_available_memory()))
    }

    static func read() -> Reading {
        Reading(footprint: footprintBytes(), available: availableBytes())
    }

    /// Reads, remembers and prints one line:
    /// `[Mem] <label> footprint N MB, available M MB, peak P MB`.
    @discardableResult
    static func log(_ label: String) -> Reading {
        let reading = read()
        state.note(reading, label: label)
        let line = "[Mem] \(label) footprint \(reading.footprintMB) MB, available \(reading.availableText) MB, peak \(state.peakMB) MB"
        print(line)
        DiagnosticsLog.shared.record(line)
        return reading
    }

    /// The session's high-water mark so far, in MB.
    static var peakMB: Int { state.peakMB }

    // MARK: - The session

    /// Once, at launch, AFTER `CrashReporter.start` has read the last
    /// session's record: clears it, starts the sampler, and listens for
    /// memory warnings.
    static func start() {
        guard state.claimStart() else { return }
        Keys.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            pressure(level: "warning", source: "uikit")
        }

        // The kernel's own event arrives earlier than UIKit's, and also when
        // no view controller is there to be told.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            let critical = source.data.contains(.critical)
            pressure(level: critical ? "critical" : "warning", source: "kernel")
        }
        source.resume()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(500))
        timer.setEventHandler {
            state.sample(read())
        }
        timer.resume()
        state.keep(source, timer)
    }

    /// The record the last session left, or nil when there is none (a first
    /// launch, or a build before this probe).
    static func previousSession() -> SessionRecord? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.peakMB) != nil else { return nil }
        let available = defaults.integer(forKey: Keys.lastAvailableMB)
        return SessionRecord(
            peakMB: defaults.integer(forKey: Keys.peakMB),
            peakAt: defaults.object(forKey: Keys.peakAt) as? Date,
            peakLabel: defaults.string(forKey: Keys.peakLabel),
            lastMB: defaults.integer(forKey: Keys.lastMB),
            lastAvailableMB: available > 0 ? available : nil,
            lastAt: defaults.object(forKey: Keys.lastAt) as? Date,
            warnings: defaults.integer(forKey: Keys.warnings)
        )
    }

    /// Main thread. Logged, counted into the session's record, and posted
    /// for the caches — once a second at most, since UIKit and the kernel
    /// usually both speak.
    private static func pressure(level: String, source: String) {
        #if targetEnvironment(simulator)
        // The simulator's app is a process of the Mac, so the kernel's event
        // is the HOST's pressure (a CI runner with Xcode and the simulator
        // on it), not the app's: noted, never counted or posted, so a tour
        // frame never depends on the runner's memory.
        if source == "kernel" {
            _ = log("host pressure \(level) (the simulator's Mac, not the app)")
            return
        }
        #endif
        guard state.claimPressure(critical: level == "critical") else { return }
        log("memory \(level) from \(source == "uikit" ? "UIKit" : "the kernel")")
        state.persist()
        NotificationCenter.default.post(
            name: .pantheonMemoryPressure, object: nil,
            userInfo: ["level": level, "source": source]
        )
    }

    enum Keys {
        static let peakMB = "diag.mem.peakMB"
        static let peakAt = "diag.mem.peakAt"
        static let peakLabel = "diag.mem.peakLabel"
        static let lastMB = "diag.mem.lastMB"
        static let lastAvailableMB = "diag.mem.lastAvailableMB"
        static let lastAt = "diag.mem.lastAt"
        static let warnings = "diag.mem.warnings"
        static let all = [peakMB, peakAt, peakLabel, lastMB, lastAvailableMB, lastAt, warnings]
    }

    private static let state = ProbeState()
}

/// The probe's shared numbers, behind one lock: the sampler runs on a
/// utility queue, `log` on whatever thread calls it.
private final class ProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var peak: UInt64 = 0
    private var peakAt: Date?
    private var peakLabel: String?
    /// The label of the last `log` call: where the app was, as far as
    /// anything has said.
    private var lastLabel: String?
    private var last = MemoryProbe.Reading(footprint: 0, available: 0)
    private var lastAt: Date?
    private var warnings = 0
    private var lastPressure: Date?
    private var lastPressureCritical = false
    private var persistedPeak: UInt64 = 0
    private var persistedAt: Date?
    /// The sources live as long as the process.
    private var retained: [Any] = []

    var peakMB: Int {
        lock.lock(); defer { lock.unlock() }
        return Int(peak / 1_048_576)
    }

    func claimStart() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return false }
        started = true
        return true
    }

    func keep(_ objects: Any...) {
        lock.lock(); retained += objects; lock.unlock()
    }

    /// A pressure event is let through when none came in the last second,
    /// or when this one is critical and the last was not.
    func claimPressure(critical: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if let previous = lastPressure, now.timeIntervalSince(previous) < 1,
           !(critical && !lastPressureCritical) {
            return false
        }
        lastPressure = now
        lastPressureCritical = critical
        warnings += 1
        return true
    }

    func note(_ reading: MemoryProbe.Reading, label: String) {
        lock.lock()
        lastLabel = label
        lock.unlock()
        sample(reading)
    }

    /// Every two seconds, and on every `log`: the high-water mark, and the
    /// record written through when the peak has climbed 8 MB or ten seconds
    /// have passed — a heartbeat the next launch reads as the last sign of
    /// life.
    func sample(_ reading: MemoryProbe.Reading) {
        lock.lock()
        let now = Date()
        last = reading
        lastAt = now
        if reading.footprint > peak {
            peak = reading.footprint
            peakAt = now
            peakLabel = lastLabel
        }
        let climbed = peak > persistedPeak + 8 * 1_048_576
        let stale = persistedAt.map { now.timeIntervalSince($0) >= 10 } ?? true
        lock.unlock()
        if climbed || stale { persist() }
    }

    func persist() {
        lock.lock()
        let snapshot = (peak, peakAt, peakLabel, last, lastAt, warnings)
        persistedPeak = peak
        persistedAt = Date()
        lock.unlock()
        let defaults = UserDefaults.standard
        defaults.set(Int(snapshot.0 / 1_048_576), forKey: MemoryProbe.Keys.peakMB)
        defaults.set(snapshot.1, forKey: MemoryProbe.Keys.peakAt)
        defaults.set(snapshot.2, forKey: MemoryProbe.Keys.peakLabel)
        defaults.set(snapshot.3.footprintMB, forKey: MemoryProbe.Keys.lastMB)
        defaults.set(snapshot.3.availableMB ?? 0, forKey: MemoryProbe.Keys.lastAvailableMB)
        defaults.set(snapshot.4, forKey: MemoryProbe.Keys.lastAt)
        defaults.set(snapshot.5, forKey: MemoryProbe.Keys.warnings)
    }
}
