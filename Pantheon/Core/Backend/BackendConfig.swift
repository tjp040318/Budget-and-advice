import Foundation

/// Where the backend lives (`Docs/BACKEND.md`): the Supabase project's URL
/// and its anon key, read from `Backend.plist` in the bundle. Both empty
/// means NO backend: the game is the offline one it was, with iCloud for an
/// Apple account's cloud copy. The anon key is public by design (Supabase's
/// row-level security is what keeps a player to his own rows), so the plist
/// is committed filled — the owner's project since 2026-09-22. The CI tour
/// never talks to a backend, whatever the plist says: a tour that made
/// anonymous users on the live project every run would be a bill and a mess.
///
/// The dashboard shows the project's URL in two places, as
/// `https://<ref>.supabase.co` and as the REST endpoint
/// `https://<ref>.supabase.co/rest/v1`; the owner pasted the second, and
/// since every request here appends its own `auth/v1/…` or `rest/v1/…`
/// path, that base would have sent every call to `…/rest/v1/auth/v1/signup`
/// and a 404. `from(dictionary:)` strips a service path and trailing
/// slashes, so either paste works.
struct BackendConfig: Equatable {
    let url: URL
    let anonKey: String

    static let filename = "Backend"

    /// The bundle's configuration, or nil when the plist is missing or empty.
    static let shared: BackendConfig? = load()

    /// True when the app should use the backend: configured, and not the tour.
    static var isConfigured: Bool { shared != nil && !isTour }

    static var isTour: Bool { ProcessInfo.processInfo.arguments.contains("-tour") }

    static func load(bundle: Bundle = .main) -> BackendConfig? {
        guard let url = bundle.url(forResource: filename, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return from(dictionary: plist)
    }

    /// Nil unless both values are filled and the URL is https. A service
    /// path pasted from the dashboard (`/rest/v1`, `/auth/v1`, …) and any
    /// trailing slash are stripped: the client appends its own.
    static func from(dictionary plist: [String: Any]) -> BackendConfig? {
        guard let rawURL = plist["SupabaseURL"] as? String,
              let rawKey = plist["SupabaseAnonKey"] as? String else { return nil }
        let trimmedURL = projectURL(fromPasted: rawURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty,
              let url = URL(string: trimmedURL), url.scheme == "https", url.host != nil else { return nil }
        return BackendConfig(url: url, anonKey: trimmedKey)
    }

    /// The Supabase services whose endpoint the dashboard also prints as a URL.
    static let servicePaths = ["rest", "auth", "storage", "functions", "realtime", "graphql"]

    /// `https://x.supabase.co/rest/v1/` -> `https://x.supabase.co`.
    static func projectURL(fromPasted pasted: String) -> String {
        var text = pasted
        while text.hasSuffix("/") { text.removeLast() }
        for service in servicePaths where text.hasSuffix("/\(service)/v1") {
            text.removeLast("/\(service)/v1".count)
            while text.hasSuffix("/") { text.removeLast() }
            break
        }
        return text
    }
}
