import Foundation

/// The on-disk save file.
///
/// Versioned from day one. `migrate(_:)` is the only place that is allowed to
/// know about old shapes, and it runs before the payload is handed to the game.
struct SaveGame: Codable, Sendable {
    static let currentVersion = 1

    var version: Int = SaveGame.currentVersion
    var player: Player
    var savedAt: Date = Date()
    /// Seed stream for anything that must stay reproducible across launches.
    var rngSeed: UInt64
}

/// Reads and writes the save files — one per account since 2026-09-17
/// (`Docs/PLAN.md`, *Accounts — Sign in with Apple*): `pantheon_save_<key>.json`
/// under Application Support/Pantheon, keyed by `Account.storageKey`. The one
/// file every save was before, `pantheon_save.json`, is renamed to the first
/// account that signs in on the phone (`migrateLegacySave(to:)`), so nobody
/// loses progress to the sign-in screen.
///
/// Writes are atomic (temp file plus replace) so a crash mid-save cannot leave a
/// truncated file, and a corrupt save is moved aside rather than deleted — a
/// player who loses an account to a parse bug should still have the bytes. A
/// cloud restore goes through `importData(_:key:)`, which decodes the bytes
/// before it replaces anything and keeps the replaced file aside the same way.
enum SaveStore {

    enum StoreError: Error, LocalizedError {
        case noDocumentsDirectory
        case corrupt(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noDocumentsDirectory: return "Could not find a place to save."
            case .corrupt(let error): return "The save file could not be read: \(error.localizedDescription)"
            }
        }
    }

    /// The name every save had before accounts.
    static let legacyFilename = "pantheon_save.json"

    /// A folder to use instead of Application Support — a test's temporary
    /// directory. Nil in the app.
    static var baseURL: URL? = nil

    static func filename(for key: String) -> String { "pantheon_save_\(key).json" }

    /// The save folder, created on first use: `<base>/Pantheon`.
    static var directory: URL? {
        let base: URL
        if let baseURL {
            base = baseURL
        } else {
            guard let support = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else { return nil }
            base = support
        }
        let folder = base.appendingPathComponent("Pantheon", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static var legacySaveURL: URL? { directory?.appendingPathComponent(legacyFilename) }

    static func saveURL(for key: String) -> URL? { directory?.appendingPathComponent(filename(for: key)) }

    static func hasSave(key: String) -> Bool {
        guard let url = saveURL(for: key) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The bytes a save is written as — for a test that plants a file.
    static func encode(_ game: SaveGame) throws -> Data {
        try encoder.encode(game)
    }

    /// Writes the account's save and returns the bytes and the stamp they
    /// carry, which the cloud copy is made from.
    @discardableResult
    static func save(_ game: SaveGame, key: String) throws -> (data: Data, savedAt: Date) {
        guard let url = saveURL(for: key) else { throw StoreError.noDocumentsDirectory }
        var payload = game
        payload.savedAt = Date()
        payload.version = SaveGame.currentVersion
        let data = try encoder.encode(payload)
        try write(data, to: url)
        return (data, payload.savedAt)
    }

    /// A temp file beside the target, then a replace.
    private static func write(_ data: Data, to url: URL) throws {
        let temporary = url.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    static func load(key: String) throws -> SaveGame? {
        guard let url = saveURL(for: key), FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            let decoded = try decoder.decode(SaveGame.self, from: data)
            return migrate(decoded)
        } catch {
            quarantine(url)
            throw StoreError.corrupt(underlying: error)
        }
    }

    /// The one save every phone had before accounts, renamed to the first
    /// account that signs in there. Once, because the rename removes it; an
    /// account that already has a save leaves it where it is. True when it
    /// moved.
    @discardableResult
    static func migrateLegacySave(to key: String) -> Bool {
        guard let legacy = legacySaveURL, let target = saveURL(for: key),
              FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: target.path) else { return false }
        do {
            try FileManager.default.moveItem(at: legacy, to: target)
            return true
        } catch {
            return false
        }
    }

    /// A guest's save renamed to the Apple account he bound it to — only
    /// when that account has no save yet. True when it moved.
    @discardableResult
    static func adopt(from oldKey: String, to newKey: String) -> Bool {
        guard oldKey != newKey, let source = saveURL(for: oldKey), let target = saveURL(for: newKey),
              FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.fileExists(atPath: target.path) else { return false }
        do {
            try FileManager.default.moveItem(at: source, to: target)
            return true
        } catch {
            return false
        }
    }

    /// Bytes from the cloud written as the account's save — after they have
    /// proved they decode. A save already on disk is moved aside as
    /// `replaced_<stamp>_…`, never deleted.
    static func importData(_ data: Data, key: String) throws {
        _ = try decoder.decode(SaveGame.self, from: data)
        guard let url = saveURL(for: key) else { throw StoreError.noDocumentsDirectory }
        if FileManager.default.fileExists(atPath: url.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("replaced_\(stamp)_\(filename(for: key))")
            try? FileManager.default.moveItem(at: url, to: backup)
        }
        try write(data, to: url)
    }

    /// Moves an unreadable save aside instead of losing it.
    private static func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("corrupt_\(stamp)_\(url.lastPathComponent)")
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    /// Brings older saves forward. Empty today; the shape is what matters.
    private static func migrate(_ save: SaveGame) -> SaveGame {
        var result = save
        if result.version < SaveGame.currentVersion {
            result.version = SaveGame.currentVersion
        }
        return result
    }

    /// A save moved aside as `reset_<stamp>_…` when the player starts over
    /// (2026-09-22): kept, never deleted, like a replaced or a corrupt one.
    /// True when a file moved.
    @discardableResult
    static func archive(key: String) -> Bool {
        guard let url = saveURL(for: key), FileManager.default.fileExists(atPath: url.path) else { return false }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("reset_\(stamp)_\(filename(for: key))")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return true
        } catch {
            return false
        }
    }

    static func deleteSave(key: String) {
        guard let url = saveURL(for: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Exports the raw save for support and for moving between devices.
    static func exportData(key: String) throws -> Data? {
        guard let url = saveURL(for: key), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}

/// Builds the starting account.
enum NewGame {
    /// A fresh player: one Anubis at 4★ level 1, a starter relic set, and enough
    /// scrolls to see the summon screen do something on day one.
    static func create(displayName: String = "Demigod") -> SaveGame {
        var rng = SeededRandom(seed: UInt64(Date().timeIntervalSince1970.bitPattern))
        var player = Player(displayName: displayName)

        // The fire Anubis (`UnitDatabase.starter`): a jackal-headed judge
        // with the family's kit in the element the first chapter's mobs are
        // weak to. Never a light or dark form — those are the Light & Dark
        // scroll's alone (2026-09-17, evening).
        let blueprint = UnitDatabase.starter
        var starter = Unit(blueprint: blueprint)
        starter.isLocked = true
        starter.acquiredFrom = "starter"
        player.units.append(starter)
        player.codex.insert(blueprint.id)

        let starterRelics = RelicService.generateLoadout(
            grade: 3,
            primarySet: .fury,
            secondarySet: .thunder,
            upgradeLevel: 0,
            quality: .rare,
            rng: &rng
        )
        player.relics.append(contentsOf: starterRelics)

        player.campaignTeam = TeamPreset(name: "Campaign", unitIDs: [starter.id])
        player.arenaOffenseTeam = TeamPreset(name: "Arena Offense", unitIDs: [starter.id])
        player.arenaDefenseTeam = TeamPreset(name: "Arena Defense", unitIDs: [starter.id])

        var seeded = player
        RelicService.autoEquip(unitID: starter.id, player: &seeded)

        return SaveGame(player: seeded, rngSeed: rng.next())
    }
}
