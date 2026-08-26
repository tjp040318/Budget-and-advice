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

/// Reads and writes the save file.
///
/// Writes are atomic (temp file plus replace) so a crash mid-save cannot leave a
/// truncated file, and a corrupt save is moved aside rather than deleted — a
/// player who loses an account to a parse bug should still have the bytes.
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

    static let filename = "pantheon_save.json"

    static var saveURL: URL? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let folder = directory.appendingPathComponent("Pantheon", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(filename)
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

    static func save(_ game: SaveGame) throws {
        guard let url = saveURL else { throw StoreError.noDocumentsDirectory }
        var payload = game
        payload.savedAt = Date()
        payload.version = SaveGame.currentVersion
        let data = try encoder.encode(payload)

        let temporary = url.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    static func load() throws -> SaveGame? {
        guard let url = saveURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            let decoded = try decoder.decode(SaveGame.self, from: data)
            return migrate(decoded)
        } catch {
            quarantine(url)
            throw StoreError.corrupt(underlying: error)
        }
    }

    /// Moves an unreadable save aside instead of losing it.
    private static func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("corrupt_\(stamp)_\(filename)")
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

    static func deleteSave() {
        guard let url = saveURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Exports the raw save for support and for moving between devices.
    static func exportData() throws -> Data? {
        guard let url = saveURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
}

/// Builds the starting account.
enum NewGame {
    /// A fresh player: one Zeus at 5★ level 1, a starter relic set, and enough
    /// scrolls to see the summon screen do something on day one.
    static func create(displayName: String = "Summoner") -> SaveGame {
        var rng = SeededRandom(seed: UInt64(Date().timeIntervalSince1970.bitPattern))
        var player = Player(displayName: displayName)

        var zeus = Unit(blueprint: UnitDatabase.zeus, level: 1, stars: 5)
        zeus.isLocked = true
        zeus.acquiredFrom = "starter"
        player.units.append(zeus)
        player.codex.insert(UnitDatabase.zeus.id)

        let starterRelics = RelicService.generateLoadout(
            grade: 3,
            primarySet: .fury,
            secondarySet: .thunder,
            upgradeLevel: 0,
            rng: &rng
        )
        player.relics.append(contentsOf: starterRelics)

        player.campaignTeam = TeamPreset(name: "Campaign", unitIDs: [zeus.id])
        player.arenaOffenseTeam = TeamPreset(name: "Arena Offense", unitIDs: [zeus.id])
        player.arenaDefenseTeam = TeamPreset(name: "Arena Defense", unitIDs: [zeus.id])

        var seeded = player
        RelicService.autoEquip(unitID: zeus.id, player: &seeded)

        return SaveGame(player: seeded, rngSeed: rng.next())
    }
}
