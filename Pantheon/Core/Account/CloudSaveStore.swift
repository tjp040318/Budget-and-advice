import Foundation
import CloudKit

/// The cloud copy of one save, as fetched or as about to be written.
struct CloudSnapshot {
    let data: Data
    /// The save's own `savedAt`: the clock every comparison uses.
    let modifiedAt: Date
    /// The player's `createdAt` — the save's LINEAGE. Two saves of one
    /// lineage are the same game on two phones; two lineages are two games.
    let lineage: Date?
}

/// The first of two racing tasks to fire wins; the other finds it shut.
private final class Latch: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

/// A copy of an Apple account's save in the container's PRIVATE CloudKit
/// database — one `Save` record per account, the JSON as a `CKAsset`,
/// because a veteran's save passes the megabyte a record's fields allow — so
/// a new iPhone gets the player's island back (`Docs/PLAN.md`, *Accounts —
/// Sign in with Apple*).
///
/// Nothing here may run without the iCloud entitlement: touching
/// `CKContainer` unentitled is an uncatchable exception, and the CI job
/// builds the app unsigned. The gate is the social layer's own
/// (`CloudKitSocialBackend.isEntitled`, read off the binary's signature), the
/// initialiser is failable on it, and `accountStatus` is asked before every
/// fetch — a phone with no iCloud account is a phone with no cloud copy.
///
/// Last-writer-wins by `modifiedAt` within one lineage; an older copy never
/// replaces a newer one in either direction; a DIFFERENT lineage is never
/// overwritten — a fresh game started on a new phone while iCloud was out of
/// reach would otherwise be the newest save in the world and bury the
/// veteran's — it is remembered as `foreign`, and the Account panel offers to
/// restore it.
@MainActor
final class CloudSaveStore {
    static let recordType = "Save"
    /// Uploads are coalesced to one every 60 s after a change.
    static let minimumInterval: TimeInterval = 60

    static var isSupported: Bool { CloudKitSocialBackend.isEntitled }

    let key: String
    private let container: CKContainer
    private let database: CKDatabase

    private var pending: CloudSnapshot?
    private var waiter: Task<Void, Never>?
    private var isUploading = false
    private(set) var lastUploadAt: Date?
    private(set) var lastError: String?
    /// A save of ANOTHER lineage found in the cloud, which this store will
    /// never overwrite; the Account panel offers it.
    private(set) var foreign: CloudSnapshot?
    /// Called after any change worth a re-render; the store forwards it.
    var onChange: (() -> Void)?

    /// Nil when the binary is not signed for iCloud: CI, and any dev build
    /// without the capability.
    init?(key: String) {
        guard CloudSaveStore.isSupported else { return nil }
        self.key = key
        let container = CKContainer(identifier: CloudKitSocialBackend.containerID)
        self.container = container
        self.database = container.privateCloudDatabase
    }

    var recordID: CKRecord.ID { CKRecord.ID(recordName: "save_\(key)") }

    // MARK: - Reading

    func accountAvailable() async -> Bool {
        do {
            return try await container.accountStatus() == .available
        } catch {
            return false
        }
    }

    /// The cloud copy, or nil when there is none.
    func fetch() async throws -> CloudSnapshot? {
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        return CloudSaveStore.snapshot(from: record)
    }

    /// The cloud copy within a time cap, or nil: a race of the fetch against
    /// a sleep on a latch, because CloudKit's async calls do not honour
    /// cancellation and a bad network would otherwise hold the launch.
    func fetch(within seconds: TimeInterval) async -> CloudSnapshot? {
        await withCheckedContinuation { continuation in
            let latch = Latch()
            Task { [weak self] in
                let found = await self?.fetchQuietly()
                if latch.fire() { continuation.resume(returning: found ?? nil) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if latch.fire() { continuation.resume(returning: nil) }
            }
        }
    }

    private func fetchQuietly() async -> CloudSnapshot? {
        guard await accountAvailable() else { return nil }
        do {
            return try await fetch()
        } catch {
            lastError = error.localizedDescription
            note("fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pulls the cloud copy over the local save when it is newer — or when
    /// there is no local save — within a time cap. A copy of another lineage
    /// is never pulled over a save: it is remembered as `foreign`. Returns
    /// true when the local file changed.
    func restoreIfNewer(than local: SaveGame?, within seconds: TimeInterval) async -> Bool {
        guard let snapshot = await fetch(within: seconds) else { return false }
        if let local, let lineage = snapshot.lineage,
           abs(lineage.timeIntervalSince(local.player.createdAt)) > 1 {
            foreign = snapshot
            note("iCloud holds a save of another lineage (\(snapshot.modifiedAt)); this phone's is kept")
            onChange?()
            return false
        }
        if let local, snapshot.modifiedAt <= local.savedAt.addingTimeInterval(1) {
            note("this phone's save is as new as the cloud copy; kept")
            return false
        }
        do {
            try SaveStore.importData(snapshot.data, key: key)
            note("restored \(snapshot.data.count) bytes from iCloud (\(snapshot.modifiedAt))")
            return true
        } catch {
            lastError = error.localizedDescription
            note("restore failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The Account panel's "Restore from iCloud": the foreign copy written
    /// over this phone's save (which `importData` keeps aside).
    func restoreForeign() -> Bool {
        guard let snapshot = foreign else { return false }
        do {
            try SaveStore.importData(snapshot.data, key: key)
            foreign = nil
            note("restored the other lineage (\(snapshot.modifiedAt)) on request")
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Writing

    /// A save just written locally: uploaded at most once every 60 s.
    func schedule(_ data: Data, savedAt: Date, lineage: Date) {
        pending = CloudSnapshot(data: data, modifiedAt: savedAt, lineage: lineage)
        guard waiter == nil else { return }
        let since = Date().timeIntervalSince(lastUploadAt ?? Date.distantPast)
        let wait = max(0, CloudSaveStore.minimumInterval - since)
        waiter = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Uploads what is pending now — on the way to the background.
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

    /// Writes the snapshot over the cloud copy — unless the cloud copy is of
    /// another lineage (another game, remembered as `foreign`) or newer
    /// (another phone saved since); then it is left alone and false comes
    /// back. A record changed under the save is fetched again, twice.
    private func upload(_ snapshot: CloudSnapshot) async throws -> Bool {
        var attempt = 0
        while true {
            attempt += 1
            let existing: CKRecord?
            do {
                existing = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                existing = nil
            }
            if let existing {
                if let theirs = existing["createdAt"] as? Date, let lineage = snapshot.lineage,
                   abs(theirs.timeIntervalSince(lineage)) > 1 {
                    foreign = CloudSaveStore.snapshot(from: existing)
                    return false
                }
                if let theirs = existing["modifiedAt"] as? Date, theirs > snapshot.modifiedAt.addingTimeInterval(1) {
                    return false
                }
            }
            let record = existing ?? CKRecord(recordType: CloudSaveStore.recordType, recordID: recordID)
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("pantheon_cloud_\(key)_\(UUID().uuidString).json")
            try snapshot.data.write(to: temporary, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporary) }
            record["payload"] = CKAsset(fileURL: temporary)
            record["modifiedAt"] = snapshot.modifiedAt
            record["createdAt"] = snapshot.lineage
            record["bytes"] = snapshot.data.count
            record["version"] = SaveGame.currentVersion
            do {
                _ = try await database.save(record)
                return true
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 3 {
                continue
            }
        }
    }

    // MARK: - Helpers

    private static func snapshot(from record: CKRecord) -> CloudSnapshot? {
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let modifiedAt = record["modifiedAt"] as? Date ?? record.modificationDate ?? Date(timeIntervalSince1970: 0)
        return CloudSnapshot(data: data, modifiedAt: modifiedAt, lineage: record["createdAt"] as? Date)
    }

    /// One line in the console, the way the model loader reports.
    private func note(_ line: String) {
        print("[CloudSave] \(line)")
    }
}

extension CloudSaveStore: CloudSaveSyncing {
    var serviceName: String { "iCloud" }

    /// The record deleted, for a player starting over (2026-09-22). A record
    /// that is not there counts as erased.
    func erase() async -> Bool {
        waiter?.cancel()
        waiter = nil
        pending = nil
        do {
            _ = try await database.deleteRecord(withID: recordID)
            foreign = nil
            note("the cloud copy is erased")
            return true
        } catch let error as CKError where error.code == .unknownItem {
            foreign = nil
            return true
        } catch {
            lastError = error.localizedDescription
            note("erase failed: \(error.localizedDescription)")
            return false
        }
    }
}
