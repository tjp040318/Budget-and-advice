import Foundation
import UIKit

/// Where every cache that can be rebuilt hears that memory is short.
///
/// The owner's crash with no crash log (2026-09-24: "when I do many summons,
/// or sometimes when I play chapters, or randomly the app crashes") is what
/// iOS does to a foreground app over its memory limit: it kills it and
/// writes no report. Until then nothing in the app let go of anything — the
/// model cache kept every family it had ever parsed with its 2048-pixel
/// textures decoded, and `BundleArt` every full-size painting. The caches
/// are bounded now; this is the second line, for when iOS warns first.
///
/// Two voices say it: UIKit's memory warning, observed directly, and
/// `MemoryProbe`'s relay (`Core/Diagnostics`), which adds the kernel's
/// earlier memory-pressure event and posts it under the name below. The
/// name is spelt here rather than read off `MemoryProbe` so the caches do
/// not depend on the probe being in the build; it must stay the same
/// string as `Notification.Name.pantheonMemoryPressure` in MemoryProbe.swift.
/// A purge that runs twice for one warning (both voices) costs nothing.
///
/// The kernel speaks twice: a first `warning`, often while the app is only
/// busy, and `critical` when it means it. A full purge on the first would
/// throw away the next wave's warmed meshes and every clip in the middle of
/// a fight and parse them again on the main thread, a hitch per attack on
/// a phone that sits at that level; so the first level is `observeEarly`'s
/// (a trim to the tight limits), and the full purge waits for `critical`
/// or UIKit's own warning.
enum MemoryRelief {
    /// The same string `MemoryProbe` posts (`.pantheonMemoryPressure`).
    static let pressure = Notification.Name("PantheonMemoryPressure")

    /// Runs `purge` on the MAIN thread when memory is really short: UIKit's
    /// warning, or the kernel's critical level. The registration lasts for
    /// the process: every caller is a cache that lives as long as the app.
    static func observe(_ purge: @escaping () -> Void) {
        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                               object: nil, queue: .main) { _ in purge() }
        _ = center.addObserver(forName: pressure, object: nil, queue: .main) { note in
            if isSevere(note) { purge() }
        }
    }

    /// Runs `trim` on the MAIN thread at the kernel's first warning only.
    static func observeEarly(_ trim: @escaping () -> Void) {
        _ = NotificationCenter.default.addObserver(forName: pressure, object: nil, queue: .main) { note in
            if !isSevere(note) { trim() }
        }
    }

    /// The probe tags what it posts with `level` and `source`; a post
    /// without them is taken as severe.
    private static func isSevere(_ note: Notification) -> Bool {
        guard let info = note.userInfo else { return true }
        return (info["level"] as? String) == "critical" || (info["source"] as? String) == "uikit"
    }
}
