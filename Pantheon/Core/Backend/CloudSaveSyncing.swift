import Foundation

/// What a cloud copy of a save does, whoever keeps it: CloudKit's private
/// database (`CloudSaveStore`, 2026-09-17) or the Supabase backend
/// (`SupabaseSaveStore`, 2026-09-22; `Docs/BACKEND.md`). `GameStore` and
/// `AppSession` speak only this, so the Account panel's words and the
/// start-over path are the same over either.
@MainActor
protocol CloudSaveSyncing: AnyObject {
    /// "iCloud" or "Pantheon Cloud": the word the Account panel prints.
    var serviceName: String { get }
    /// A save of ANOTHER lineage found in the cloud, which the store never
    /// overwrites; the Account panel offers to restore it.
    var foreign: CloudSnapshot? { get }
    var lastError: String? { get }
    /// Called after any change worth a re-render; the store forwards it.
    var onChange: (() -> Void)? { get set }
    /// Pulls the cloud copy over the local save when it is newer, within a
    /// time cap. True when the local file changed.
    func restoreIfNewer(than local: SaveGame?, within seconds: TimeInterval) async -> Bool
    /// The foreign copy written over this phone's save, on request.
    func restoreForeign() -> Bool
    /// A save just written locally, to upload (coalesced).
    func schedule(_ data: Data, savedAt: Date, lineage: Date)
    /// Uploads what is pending now.
    func flush() async
    /// The cloud copy removed, for a player starting over. False when the
    /// service could not be reached, in which case the old copy may come
    /// back as `foreign` and the panel offers it.
    func erase() async -> Bool
}
