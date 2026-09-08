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
