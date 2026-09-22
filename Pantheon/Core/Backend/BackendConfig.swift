import Foundation

/// Where the backend lives (`Docs/BACKEND.md`): the Supabase project's URL
/// and its anon key, read from `Backend.plist` in the bundle. Both empty —
/// the file as first committed, and every CI build — means NO backend: the
/// game is the offline one it was, with iCloud for an Apple account's cloud
/// copy. The anon key is public by design (Supabase's row-level security is
/// what keeps a player to his own rows), so the plist can be committed once
/// the owner fills it. The CI tour never talks to a backend, whatever the
/// plist says: a tour that made anonymous users on the live project every
/// run would be a bill and a mess.
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

    /// Nil unless both values are filled and the URL is https.
    static func from(dictionary plist: [String: Any]) -> BackendConfig? {
        guard let rawURL = plist["SupabaseURL"] as? String,
              let rawKey = plist["SupabaseAnonKey"] as? String else { return nil }
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty,
              let url = URL(string: trimmedURL), url.scheme == "https", url.host != nil else { return nil }
        return BackendConfig(url: url, anonKey: trimmedKey)
    }
}
