import CryptoKit
import Foundation
import MetricKit
import UIKit

/// The crash that happens on the owner's phone and nowhere else, reported by
/// the phone itself (2026-09-24; "when I do many summons, or sometimes when I
/// play chapters, or randomly the app crashes").
///
/// Two witnesses, both Apple's own and neither an SDK:
///
/// 1. **MetricKit.** `MXMetricManager` hands the app its own crash, hang,
///    CPU-exception, disk-write and slow-launch reports — on iOS 15 and later
///    at the NEXT launch, as soon as this object subscribes — each with the
///    exception, the signal, the termination reason and the crashed thread's
///    call stack (binary and offset; MetricKit does not symbolicate). Every
///    payload's own JSON is saved to Application Support/diagnostics/ and a
///    readable summary goes to the console and More → Diagnostics as
///    `[Crash]` lines, where Copy and Share already are. The newest saved
///    summaries are replayed at every launch, so the report is still there
///    the day the owner opens Diagnostics, not only the launch it arrived on.
///    The daily metric payload adds the exit counts, including the one
///    thing no crash report covers: a kill for memory.
///
/// 2. **The exit flag.** iOS kills a foreground app over its memory limit
///    (jetsam) without a crash report; MetricKit only counts it, a day later.
///    So a flag is set at launch and on every return to the foreground and
///    cleared on the way to the background or out: a launch that finds it
///    still set knows the last session died in the foreground, and prints
///    how — with the footprint's high-water mark, the last reading, the
///    memory still available then and the memory warnings it had
///    (`MemoryProbe`), which together say "memory" or "not memory".
///
/// Off under the tour (the CI job kills the app at every step, which would
/// read as a crash every launch) except for the one line saying it is armed,
/// and off under the unit tests.
final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    static let shared = CrashReporter()

    /// Application Support/diagnostics: one `<stamp>-<kind>-<hash>.json` per
    /// payload, exactly as MetricKit wrote it, and a `.txt` summary beside it.
    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostics", isDirectory: true)
    }

    private let queue = DispatchQueue(label: "pantheon.crash-reporter", qos: .utility)
    private let lock = NSLock()
    private var started = false
    private var observers: [NSObjectProtocol] = []

    private enum ExitFlag {
        static let open = "diag.session.open"
        static let startedAt = "diag.session.startedAt"
        static let binaryStamp = "diag.session.binaryStamp"
        static let version = "diag.session.version"
    }

    /// How many saved summaries a launch replays.
    private static let replayed = 3
    /// How many payload files are kept; the oldest go first.
    private static let kept = 60

    private override init() {
        super.init()
    }

    // MARK: - Launch

    /// Once, first thing in `PantheonApp.init`, BEFORE `MemoryProbe.start()`
    /// (which clears the record of the last session this reads).
    func start(touring: Bool) {
        lock.lock()
        let already = started
        started = true
        lock.unlock()
        guard !already else { return }
        if touring {
            Self.say("[Crash] armed (under the tour MetricKit and the exit flag are off: the job kills the app at every step)")
            return
        }
        // A test run hosts the app: nothing there is a player's session.
        if NSClassFromString("XCTestCase") != nil { return }

        reportPreviousSession()
        markOpen(true)
        observeApp()

        // The saved summaries first, then whatever MetricKit brings: the
        // queue is serial, so a report arriving this launch is written after
        // the replay has read the folder and prints once, as new.
        queue.async { [self] in
            replaySaved()
        }
        MXMetricManager.shared.add(self)
        queue.async { [self] in
            // Anything delivered while no build of this reporter was
            // listening; a payload already saved is skipped by its name.
            handleDiagnostics(MXMetricManager.shared.pastDiagnosticPayloads)
            handleMetrics(MXMetricManager.shared.pastPayloads)
        }
        Self.say("[Crash] armed: MetricKit subscribed, exit flag set, reports in Application Support/diagnostics")
    }

    // MARK: - The exit flag

    private func observeApp() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.markOpen(false)
            },
            center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                self?.markOpen(false)
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.markOpen(true)
            },
        ]
    }

    private func markOpen(_ open: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(open, forKey: ExitFlag.open)
        if open {
            defaults.set(Date(), forKey: ExitFlag.startedAt)
            defaults.set(Self.binaryStamp, forKey: ExitFlag.binaryStamp)
            defaults.set(Self.appVersion, forKey: ExitFlag.version)
        }
    }

    /// How the last session ended, from the flag and the memory record.
    private func reportPreviousSession() {
        let defaults = UserDefaults.standard
        let memory = MemoryProbe.previousSession()
        if let memory {
            var line = "[Mem] last session peaked at \(memory.peakMB) MB"
            if let at = memory.peakAt { line += " at \(Self.clock(at))" }
            if let label = memory.peakLabel { line += " (after '\(label)')" }
            line += "; last reading \(memory.lastMB) MB"
            if let available = memory.lastAvailableMB { line += " with \(available) MB available" }
            if let at = memory.lastAt { line += " at \(Self.clock(at))" }
            line += memory.warnings > 0 ? "; \(memory.warnings) memory warning(s)" : "; no memory warning"
            Self.say(line)
        }
        guard defaults.bool(forKey: ExitFlag.open) else {
            Self.say("[Crash] the last session exited cleanly (or this is the first)")
            return
        }
        let started = (defaults.object(forKey: ExitFlag.startedAt) as? Date).map(Self.clock) ?? "?"
        let alive = memory?.lastAt.map(Self.clock) ?? "?"
        Self.say("[Crash] THE LAST SESSION DID NOT EXIT CLEANLY: in the foreground since \(started), last sign of life \(alive) (version \(defaults.string(forKey: ExitFlag.version) ?? "?"))")
        let reinstalled = defaults.double(forKey: ExitFlag.binaryStamp) != Self.binaryStamp
        let short = (memory?.warnings ?? 0) > 0 || (memory?.lastAvailableMB.map { $0 < 200 } ?? false)
        if reinstalled {
            Self.say("[Crash]   the app has been reinstalled since, and installing from Xcode kills the running app — this may be only that")
        } else if short {
            Self.say("[Crash]   memory was short at the end: most likely iOS killed the app for memory (jetsam). That leaves no crash report; Settings → Privacy & Security → Analytics & Improvements → Analytics Data has a JetsamEvent file from that minute, and MetricKit's daily exit counts will show a 'MemoryResourceLimit' exit")
        } else {
            Self.say("[Crash]   memory was not short: if it crashed, MetricKit brings the report to this launch (iOS 15+) and it prints here as '[Crash] MetricKit report'; Settings → Privacy & Security → Analytics & Improvements → Analytics Data has it as a Pantheon-….ips file")
        }
    }

    // MARK: - MetricKit

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        queue.async { [self] in handleDiagnostics(payloads) }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        queue.async { [self] in handleMetrics(payloads) }
    }

    private func handleDiagnostics(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let json = payload.jsonRepresentation()
            guard let name = newFileName(stamp: payload.timeStampEnd, kind: "diagnostic", json: json) else { continue }
            let lines = summary(of: payload, file: name)
            save(json: json, summary: lines, as: name)
            lines.forEach(Self.say)
        }
    }

    private func handleMetrics(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let json = payload.jsonRepresentation()
            guard let name = newFileName(stamp: payload.timeStampEnd, kind: "metrics", json: json) else { continue }
            let lines = summary(of: payload, json: json, file: name)
            save(json: json, summary: lines, as: name)
            lines.forEach(Self.say)
        }
    }

    // MARK: - Summaries

    private func summary(of payload: MXDiagnosticPayload, file: String) -> [String] {
        var lines = ["[Crash] MetricKit report \(Self.stamp(payload.timeStampBegin))–\(Self.clock(payload.timeStampEnd)) (\(file))"]
        let crashes = payload.crashDiagnostics ?? []
        for (i, crash) in crashes.enumerated() {
            lines.append("[Crash] CRASH \(i + 1) of \(crashes.count): \(Self.describe(crash))  [app \(crash.applicationVersion), \(crash.metaData.osVersion), \(crash.metaData.deviceType)]")
            if let reason = crash.terminationReason, !reason.isEmpty {
                lines.append("[Crash]   termination: \(reason)")
            }
            if let region = crash.virtualMemoryRegionInfo, !region.isEmpty {
                lines.append("[Crash]   address: \(region.replacingOccurrences(of: "\n", with: " | "))")
            }
            if let objc = Self.objectiveCReason(crash.jsonRepresentation()) {
                lines.append("[Crash]   Objective-C exception: \(objc)")
            }
            lines.append("[Crash]   crashed thread, innermost first:")
            lines += Self.frames(crash.callStackTree, limit: 24).map { "[Crash]     \($0)" }
        }
        for (i, hang) in (payload.hangDiagnostics ?? []).enumerated() {
            let seconds = hang.hangDuration.converted(to: .seconds).value
            lines.append(String(format: "[Crash] HANG %d: the main thread did not answer for %.1f s", i + 1, seconds))
            lines += Self.frames(hang.callStackTree, limit: 12).map { "[Crash]     \($0)" }
        }
        for (i, cpu) in (payload.cpuExceptionDiagnostics ?? []).enumerated() {
            let used = cpu.totalCPUTime.converted(to: .seconds).value
            let over = cpu.totalSampledTime.converted(to: .seconds).value
            lines.append(String(format: "[Crash] CPU EXCEPTION %d: %.0f s of CPU in %.0f s", i + 1, used, over))
            lines += Self.frames(cpu.callStackTree, limit: 8).map { "[Crash]     \($0)" }
        }
        for (i, disk) in (payload.diskWriteExceptionDiagnostics ?? []).enumerated() {
            let megabytes = disk.totalWritesCaused.converted(to: .megabytes).value
            lines.append(String(format: "[Crash] DISK WRITES %d: %.0f MB written in a day", i + 1, megabytes))
            lines += Self.frames(disk.callStackTree, limit: 8).map { "[Crash]     \($0)" }
        }
        for (i, launch) in (payload.appLaunchDiagnostics ?? []).enumerated() {
            let seconds = launch.launchDuration.converted(to: .seconds).value
            lines.append(String(format: "[Crash] SLOW LAUNCH %d: %.1f s", i + 1, seconds))
            lines += Self.frames(launch.callStackTree, limit: 8).map { "[Crash]     \($0)" }
        }
        if !crashes.isEmpty {
            lines.append("[Crash]   a 'Pantheon +0x…' frame is symbolicated on the Mac that built the app: atos -arch arm64 -o <Pantheon.app.dSYM>/Contents/Resources/DWARF/Pantheon -l <load> <address>, both numbers as printed")
        }
        return lines
    }

    /// The daily payload: the exits by kind (a kill for memory is
    /// 'MemoryResourceLimit'), read off its JSON so every count Apple adds is
    /// printed too, and the day's peak memory.
    private func summary(of payload: MXMetricPayload, json: Data, file: String) -> [String] {
        var lines: [String] = []
        let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let exits = object?["applicationExitMetrics"] as? [String: Any]
        for (ground, key) in [("foreground", "foregroundExitData"), ("background", "backgroundExitData")] {
            guard let counts = exits?[key] as? [String: Any] else { continue }
            let nonzero = counts.compactMap { name, value -> String? in
                guard let count = (value as? NSNumber)?.intValue, count > 0 else { return nil }
                let short = name.replacingOccurrences(of: "cumulative", with: "").replacingOccurrences(of: "ExitCount", with: "")
                return "\(short) \(count)"
            }.sorted()
            guard !nonzero.isEmpty else { continue }
            lines.append("[Crash] exits in the \(ground), \(Self.stamp(payload.timeStampBegin))–\(Self.clock(payload.timeStampEnd)): " + nonzero.joined(separator: ", "))
        }
        if let peak = payload.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value {
            lines.append(String(format: "[Mem] MetricKit's day to %@: peak memory %.0f MB", Self.stamp(payload.timeStampEnd), peak))
        }
        if lines.isEmpty { return [] }
        return lines + ["[Crash]   (\(file))"]
    }

    /// "EXC_BAD_ACCESS (SIGSEGV) code 1 — a bad memory access", with what
    /// the pair usually means in this app.
    private static func describe(_ crash: MXCrashDiagnostic) -> String {
        let type = crash.exceptionType?.intValue ?? -1
        let signal = crash.signal?.intValue ?? -1
        var text = "\(type >= 0 ? machException(type) : "no exception type") (\(signal >= 0 ? signalName(signal) : "no signal"))"
        if let code = crash.exceptionCode?.intValue { text += " code \(code)" }
        if type == 1 || signal == 11 || signal == 10 {
            text += " — a bad memory access: a freed object or a pointer into one (the SceneKit render-queue crashes were this)"
        } else if type == 6 || signal == 5 {
            text += " — a Swift runtime trap: a force-unwrapped nil, an index out of range, a fatalError or a failed precondition"
        } else if signal == 6 {
            text += " — an abort: an uncaught exception or an assertion"
        } else if signal == 9 {
            text += " — killed by the system (the termination line says why: 0x8badf00d is the watchdog)"
        }
        return text
    }

    private static func machException(_ type: Int) -> String {
        let names = [1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION",
                     5: "EXC_SOFTWARE", 6: "EXC_BREAKPOINT", 7: "EXC_SYSCALL", 8: "EXC_MACH_SYSCALL",
                     9: "EXC_RPC_ALERT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY"]
        return names[type] ?? "exception \(type)"
    }

    private static func signalName(_ signal: Int) -> String {
        let names = [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT", 8: "SIGFPE", 9: "SIGKILL",
                     10: "SIGBUS", 11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 15: "SIGTERM"]
        return names[signal] ?? "signal \(signal)"
    }

    /// iOS 17 adds the Objective-C exception's name and message to a crash;
    /// read off the JSON so the older SDK's field names cannot break a build.
    private static func objectiveCReason(_ json: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let meta = object["diagnosticMetaData"] as? [String: Any],
              let reason = meta.first(where: { $0.key.lowercased().contains("exceptionreason") })?.value as? [String: Any]
        else { return nil }
        let name = reason["exceptionName"] as? String ?? reason["exceptionType"] as? String ?? "exception"
        let message = reason["composedMessage"] as? String ?? ""
        return message.isEmpty ? name : "\(name): \(message)"
    }

    /// The call stack as lines, innermost first: `0 SceneKit +0x1a2b40 (load
    /// 0x1b0000000, address 0x1b01a2b40)`. A crash's tree is one stack per
    /// thread and the crashed one is marked `threadAttributed`; a hang's is
    /// sampled, so the walk follows the frame with the most samples.
    private static func frames(_ tree: MXCallStackTree, limit: Int) -> [String] {
        guard let object = (try? JSONSerialization.jsonObject(with: tree.jsonRepresentation())) as? [String: Any],
              let stacks = object["callStacks"] as? [[String: Any]], !stacks.isEmpty else {
            return ["(no call stack)"]
        }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks[0]
        var frame = heaviest(stack["callStackRootFrames"] as? [[String: Any]])
        var lines: [String] = []
        while let current = frame, lines.count < limit {
            let binary = current["binaryName"] as? String ?? "?"
            let offset = (current["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value ?? 0
            let address = (current["address"] as? NSNumber)?.uint64Value ?? 0
            let load = address >= offset ? address - offset : 0
            let index = String(lines.count).padding(toLength: 2, withPad: " ", startingAt: 0)
            lines.append("\(index) \(binary) +0x\(String(offset, radix: 16)) (load 0x\(String(load, radix: 16)), address 0x\(String(address, radix: 16)))")
            frame = heaviest(current["subFrames"] as? [[String: Any]])
        }
        return lines.isEmpty ? ["(empty call stack)"] : lines
    }

    private static func heaviest(_ frames: [[String: Any]]?) -> [String: Any]? {
        frames?.max { a, b in
            ((a["sampleCount"] as? NSNumber)?.intValue ?? 0) < ((b["sampleCount"] as? NSNumber)?.intValue ?? 0)
        }
    }

    // MARK: - Files

    /// The payload's file name, or nil when that exact payload is already
    /// saved (MetricKit hands a past payload back on every launch).
    private func newFileName(stamp: Date, kind: String, json: Data) -> String? {
        guard let folder = Self.directory else { return nil }
        let hash = SHA256.hash(data: json).prefix(4).map { String(format: "%02x", $0) }.joined()
        let name = "\(Self.fileStamp(stamp))-\(kind)-\(hash)"
        let path = folder.appendingPathComponent(name + ".json").path
        return FileManager.default.fileExists(atPath: path) ? nil : name
    }

    private func save(json: Data, summary: [String], as name: String) {
        guard let folder = Self.directory else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try? json.write(to: folder.appendingPathComponent(name + ".json"), options: .atomic)
        if !summary.isEmpty {
            try? Data(summary.joined(separator: "\n").utf8).write(to: folder.appendingPathComponent(name + ".txt"), options: .atomic)
        }
        // The oldest go once there are more than `kept`.
        if let names = try? manager.contentsOfDirectory(atPath: folder.path) {
            let payloads = names.filter { $0.hasSuffix(".json") }.sorted()
            for old in payloads.dropLast(Self.kept) {
                let base = String(old.dropLast(5))
                try? manager.removeItem(at: folder.appendingPathComponent(old))
                try? manager.removeItem(at: folder.appendingPathComponent(base + ".txt"))
            }
        }
    }

    /// Every launch: how many reports this phone holds and the newest few
    /// crash, hang and exit summaries again, so Diagnostics shows them on
    /// any day, not only the launch MetricKit delivered them on.
    private func replaySaved() {
        guard let folder = Self.directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            Self.say("[Crash] no MetricKit report saved on this phone yet")
            return
        }
        let summaries = names.filter { $0.hasSuffix(".txt") }.sorted(by: >)
        guard !summaries.isEmpty else {
            Self.say("[Crash] no MetricKit report saved on this phone yet")
            return
        }
        // The crashes, hangs and exits first, then the newest day's metrics:
        // a daily metrics summary arrives almost every day, and replayed by
        // date alone three of them would push a crash out within three days.
        let diagnostics = summaries.filter { $0.contains("-diagnostic-") }
        let metrics = summaries.filter { !$0.contains("-diagnostic-") }
        let replay = Array(diagnostics.prefix(Self.replayed)) + Array(metrics.prefix(1))
        Self.say("[Crash] \(summaries.count) MetricKit report(s) saved on this phone; the newest \(replay.count) again:")
        for name in replay {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                Self.say("(saved) " + line)
            }
        }
    }

    // MARK: - Words

    private static func say(_ line: String) {
        print(line)
        DiagnosticsLog.shared.record(line)
    }

    /// The executable's modification time: it changes on every install, so a
    /// session that "died" across one is known to be the install.
    private static var binaryStamp: Double {
        guard let path = Bundle.main.executablePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attributes[.modificationDate] as? Date else { return 0 }
        return date.timeIntervalSince1970
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func clock(_ date: Date) -> String {
        Formats.clock.string(from: date)
    }

    private static func stamp(_ date: Date) -> String {
        Formats.stamp.string(from: date)
    }

    private static func fileStamp(_ date: Date) -> String {
        Formats.file.string(from: date)
    }
}

/// The reporter's date formats, made once. Outside the class so no actor or
/// Sendable rule reaches them; every use is on one thread at a time
/// (DateFormatter is thread-safe for formatting since iOS 7).
private enum Formats {
    static let clock: DateFormatter = make("HH:mm:ss")
    static let stamp: DateFormatter = make("yyyy-MM-dd HH:mm")
    static let file: DateFormatter = make("yyyy-MM-dd_HHmmss")

    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
