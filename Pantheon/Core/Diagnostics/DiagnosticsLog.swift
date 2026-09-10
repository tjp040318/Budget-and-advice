import Foundation

/// Where every diagnostic line the app prints also goes, so a phone with no
/// Xcode attached can still hand the console over: More → Diagnostics shows
/// the buffer with Copy and Share. A ring of the last few hundred lines; the
/// `[ModelLibrary]` block that decides whether a model loaded is the reason
/// it exists.
final class DiagnosticsLog: @unchecked Sendable {

    static let shared = DiagnosticsLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let capacity = 800
    private var headerRecorded = false

    private init() {}

    func record(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    /// Once per launch: the app version and the device, at the top of the
    /// block, because a paste without them starts with a question.
    func recordDeviceHeader() {
        lock.lock()
        let already = headerRecorded
        headerRecorded = true
        lock.unlock()
        guard !already else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        record("[Diagnostics] Pantheon \(version) (\(build)) on \(Self.deviceModel) iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return lines.count
    }

    /// The hardware identifier ("iPhone16,1"), which names the exact model
    /// where `UIDevice.model` only says "iPhone".
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown device" : identifier
    }
}

/// Wall-clock probes for the stalls the owner feels on the phone and this
/// environment cannot reproduce — there is no Swift toolchain here and no
/// phone, so the code can only be read, and it has been read three times
/// for the Arena's lag without the seconds being found. Every probe over
/// its threshold prints a `[Perf]` line and records it, so More →
/// Diagnostics → Copy carries the answer back.
///
/// `startWatchdog()` is the one probe that needs no guess about where the
/// time goes: it pings the main queue every tenth of a second, and a ping
/// answered late reports how long the main thread was busy. Read beside the
/// other lines' timestamps, that names the stall whatever caused it.
enum Perf {
    static func begin() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }

    /// Logs `label` if the work since `start` took at least `threshold`
    /// milliseconds; hands the duration back either way.
    @discardableResult
    static func end(_ start: CFAbsoluteTime, _ label: String, over threshold: Double = 16) -> Double {
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if ms >= threshold {
            note(String(format: "%@ took %.0f ms%@", label, ms, Thread.isMainThread ? " on main" : " off main"))
        }
        return ms
    }

    static func note(_ message: String) {
        let line = "[Perf] \(clock.string(from: Date())) \(message)"
        print(line)
        DiagnosticsLog.shared.record(line)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// One ping in flight at a time, so a long stall reports once with its
    /// whole length rather than as a queue of late pings.
    private final class WatchdogState: @unchecked Sendable {
        private let lock = NSLock()
        private var answered = true
        func take() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard answered else { return false }
            answered = false
            return true
        }
        func release() {
            lock.lock(); answered = true; lock.unlock()
        }
    }
    private static let watchdog = WatchdogState()
    private static var watchdogStarted = false

    static func startWatchdog() {
        guard !watchdogStarted else { return }
        watchdogStarted = true
        let state = watchdog
        let thread = Thread {
            while true {
                Thread.sleep(forTimeInterval: 0.1)
                guard state.take() else { continue }
                let sent = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async {
                    let waited = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                    if waited >= 250 {
                        note(String(format: "main thread was busy for about %.0f ms before this", waited))
                    }
                    state.release()
                }
            }
        }
        thread.name = "perf.watchdog"
        thread.qualityOfService = .utility
        thread.start()
    }
}
