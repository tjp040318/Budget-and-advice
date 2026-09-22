import Foundation

/// The cloud copy of a save in the Supabase backend (2026-09-22;
/// `Docs/BACKEND.md`): one row of `saves` per player, the JSON as text so it
/// round-trips byte for byte, kept behind row-level security so a player
/// reads and writes his own row and nobody else's. A guest has one too: his
/// Supabase user is anonymous, made on the first launch, and it becomes the
/// Apple ID's the day he binds (the file rename `AccountService` does is
/// followed by an upload under the Apple user).
///
/// The rules are CloudKit's (`CloudSaveStore`), enforced on the SERVER by
/// the `saves_guard` trigger as well as here: last writer wins by `savedAt`
/// within one lineage, an older copy never replaces a newer one, and a save
/// of another lineage — another game, its `createdAt` different — is never
/// overwritten; the trigger answers `lineage`, the copy is remembered as
/// `foreign`, and the Account panel offers to restore it.
@MainActor
final class SupabaseSaveStore: CloudSaveSyncing {
    /// Uploads are coalesced to one every 60 s after a change.
    static let minimumInterval: TimeInterval = 60

    let serviceName = "Pantheon Cloud"
    let client: SupabaseClient
    let account: Account

    private var pending: CloudSnapshot?
    private var waiter: Task<Void, Never>?
    private var isUploading = false
    private(set) var lastUploadAt: Date?
    private(set) var lastError: String?
    private(set) var foreign: CloudSnapshot?
    var onChange: (() -> Void)?
    /// The identity token of a Sign in with Apple this launch, spent on the
    /// first session and never kept.
    private var appleIdentityToken: String?

    init(client: SupabaseClient, account: Account, appleIdentityToken: String? = nil) {
        self.client = client
        self.account = account
        self.appleIdentityToken = appleIdentityToken
    }

    // MARK: - Signing in

    /// Signs in — the saved session, Apple's token, or a fresh anonymous
    /// user — and registers the player row. False when the backend is out
    /// of reach: the store still works, and the next flush tries again.
    @discardableResult
    func prepare() async -> Bool {
        do {
            _ = try await client.ensureSession(appleIdentityToken: appleIdentityToken)
            appleIdentityToken = nil
            try await registerPlayer()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            note("sign-in failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The `players` row: who this user is in the game's terms, for support
    /// (the Player ID) and for the leaderboards to come.
    private func registerPlayer() async throws {
        guard let uid = client.userID else { throw BackendError.notSignedIn }
        var row: [String: Any] = [
            "id": uid,
            "provider": account.provider.rawValue,
            "player_code": account.playerCode,
            "last_seen_at": SupabaseSaveStore.iso(Date()),
        ]
        if let name = account.displayName { row["display_name"] = name }
        let body = try JSONSerialization.data(withJSONObject: [row])
        _ = try await client.rest("POST", "players", body: body, prefer: "resolution=merge-duplicates,return=minimal")
    }

    // MARK: - Reading

    /// The cloud row within a time cap, or nil when there is none or the
    /// backend is out of reach.
    func fetch(within seconds: TimeInterval) async -> CloudSnapshot? {
        guard client.isSignedIn, let uid = client.userID else { return nil }
        do {
            let (data, _) = try await client.rest("GET", "saves", query: [
                URLQueryItem(name: "select", value: "payload,version,lineage,saved_at,revision"),
                URLQueryItem(name: "player_id", value: "eq.\(uid)"),
                URLQueryItem(name: "limit", value: "1"),
            ], timeout: max(2, seconds))
            return try SupabaseSaveStore.snapshot(fromRows: data)
        } catch {
            lastError = error.localizedDescription
            note("fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The one row PostgREST answers with, as a snapshot; nil for none.
    static func snapshot(fromRows data: Data) throws -> CloudSnapshot? {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw BackendError.decoding("the saves rows")
        }
        guard let row = rows.first else { return nil }
        guard let payload = row["payload"] as? String, let savedAt = row["saved_at"] as? String else {
            throw BackendError.decoding("a saves row without its payload")
        }
        let lineage = (row["lineage"] as? String).flatMap(SupabaseSaveStore.date)
        return CloudSnapshot(data: Data(payload.utf8),
                             modifiedAt: SupabaseSaveStore.date(savedAt) ?? Date(timeIntervalSince1970: 0),
                             lineage: lineage)
    }

    /// Pulls the cloud copy over the local save when it is newer — or when
    /// there is no local save — within a time cap; a copy of another lineage
    /// is remembered as `foreign` instead. True when the local file changed.
    func restoreIfNewer(than local: SaveGame?, within seconds: TimeInterval) async -> Bool {
        guard let snapshot = await fetch(within: seconds) else { return false }
        if let local, let lineage = snapshot.lineage,
           abs(lineage.timeIntervalSince(local.player.createdAt)) > 1 {
            foreign = snapshot
            note("the cloud holds a save of another lineage (\(snapshot.modifiedAt)); this phone's is kept")
            onChange?()
            return false
        }
        if let local, snapshot.modifiedAt <= local.savedAt.addingTimeInterval(1) {
            note("this phone's save is as new as the cloud copy; kept")
            return false
        }
        do {
            try SaveStore.importData(snapshot.data, key: account.storageKey)
            note("restored \(snapshot.data.count) bytes from the cloud (\(snapshot.modifiedAt))")
            return true
        } catch {
            lastError = error.localizedDescription
            note("restore failed: \(error.localizedDescription)")
            return false
        }
    }

    func restoreForeign() -> Bool {
        guard let snapshot = foreign else { return false }
        do {
            try SaveStore.importData(snapshot.data, key: account.storageKey)
            foreign = nil
            note("restored the other lineage (\(snapshot.modifiedAt)) on request")
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Writing

    func schedule(_ data: Data, savedAt: Date, lineage: Date) {
        pending = CloudSnapshot(data: data, modifiedAt: savedAt, lineage: lineage)
        guard waiter == nil else { return }
        let since = Date().timeIntervalSince(lastUploadAt ?? Date.distantPast)
        let wait = max(0, SupabaseSaveStore.minimumInterval - since)
        waiter = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    func flush() async {
        waiter?.cancel()
        waiter = nil
        guard !isUploading, let snapshot = pending else { return }
        pending = nil
        isUploading = true
        defer { isUploading = false }
        do {
            let written = try await upload(snapshot)
            lastUploadAt = Date()
            lastError = nil
            note(written ? "uploaded \(snapshot.data.count) bytes" : "upload skipped: the cloud copy is newer, or another game's")
        } catch {
            lastError = error.localizedDescription
            if pending == nil { pending = snapshot }
            note("upload failed: \(error.localizedDescription)")
        }
        onChange?()
    }

    /// One upsert; the server's guard says `lineage` or `stale` when the
    /// row must not change, and the answer is false.
    private func upload(_ snapshot: CloudSnapshot) async throws -> Bool {
        if !client.isSignedIn {
            _ = try await client.ensureSession(appleIdentityToken: appleIdentityToken)
            appleIdentityToken = nil
            try await registerPlayer()
        }
        guard let uid = client.userID else { throw BackendError.notSignedIn }
        let body = try SupabaseSaveStore.upsertBody(playerID: uid, snapshot: snapshot)
        do {
            _ = try await client.rest("POST", "saves", body: body, prefer: "resolution=merge-duplicates,return=minimal")
            return true
        } catch BackendError.lineage {
            foreign = await fetch(within: 10)
            onChange?()
            return false
        } catch BackendError.stale {
            return false
        }
    }

    /// The row an upsert sends: the save as one JSON string, its stamp, its
    /// lineage and its size.
    static func upsertBody(playerID: String, snapshot: CloudSnapshot) throws -> Data {
        let row: [String: Any] = [
            "player_id": playerID,
            "payload": String(decoding: snapshot.data, as: UTF8.self),
            "version": SaveGame.currentVersion,
            "lineage": iso(snapshot.lineage ?? Date(timeIntervalSince1970: 0)),
            "saved_at": iso(snapshot.modifiedAt),
            "bytes": snapshot.data.count,
        ]
        return try JSONSerialization.data(withJSONObject: [row])
    }

    /// The row deleted, for a player starting over.
    func erase() async -> Bool {
        waiter?.cancel()
        waiter = nil
        pending = nil
        guard client.isSignedIn, let uid = client.userID else {
            // Nothing signed in means nothing was ever uploaded from here.
            foreign = nil
            return true
        }
        do {
            _ = try await client.rest("DELETE", "saves", query: [URLQueryItem(name: "player_id", value: "eq.\(uid)")],
                                      prefer: "return=minimal")
            foreign = nil
            note("the cloud copy is erased")
            return true
        } catch {
            lastError = error.localizedDescription
            note("erase failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    /// Postgres writes `2026-09-22T10:11:12.123456+00:00`; the formatter
    /// reads whole seconds, so the fraction is cut before it is parsed.
    static func date(_ text: String) -> Date? {
        if let whole = isoFormatter.date(from: text) { return whole }
        guard let dot = text.firstIndex(of: ".") else { return nil }
        var tail = text[text.index(after: dot)...]
        while let first = tail.first, first.isNumber { tail = tail.dropFirst() }
        let trimmed = String(text[..<dot]) + String(tail)
        return isoFormatter.date(from: trimmed)
    }

    private func note(_ line: String) {
        print("[Backend] \(line)")
    }
}
