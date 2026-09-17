import Foundation
import CryptoKit

/// Who signed in: Apple, or nobody — a guest, whose progress lives on this
/// phone only until he binds it. An `.email` case is the door that option B
/// of `Docs/PLAN.md` (*Accounts — Sign in with Apple*) would come through.
enum AccountProvider: String, Codable, Sendable {
    case apple
    case guest
}

/// One identity per player, so two people on one phone — or one person on
/// two phones — never share a save. The id is Apple's stable user identifier
/// when the player signed in with Apple and `guest-<uuid>` when he did not;
/// everything on disk and in the cloud is keyed by a hash of it.
struct Account: Codable, Equatable, Sendable {
    /// Apple's user identifier (stable per developer team, never an email),
    /// or `guest-<uuid>`.
    let id: String
    var provider: AccountProvider
    /// The name Apple handed over at the FIRST authorisation — it is never
    /// sent again — or nil for a guest.
    var displayName: String?
    /// The email from the same first authorisation, possibly a Hide My
    /// Email relay address, kept as given.
    var email: String?
    var createdAt: Date

    static let guestPrefix = "guest-"

    var isGuest: Bool { provider == .guest }

    /// A fresh guest.
    static func guest(now: Date = Date()) -> Account {
        Account(
            id: guestPrefix + UUID().uuidString.lowercased(),
            provider: .guest,
            displayName: nil,
            email: nil,
            createdAt: now
        )
    }

    /// The account's name on disk (`pantheon_save_<key>.json`) and in the
    /// cloud (`save_<key>`): the first sixteen hex characters of SHA-256 of
    /// the id. Stable, filesystem-safe — an Apple id carries dots and a
    /// guest's a UUID — and it never reveals the id.
    var storageKey: String { Account.key(for: id) }

    static func key(for id: String) -> String {
        let digest = SHA256.hash(data: Data(id.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// The six characters the Account panel prints as "Player ID": the
    /// key's tail in capitals, which is also the tail of the CloudKit
    /// record's name (`save_<key>`), so a support request quoting it finds
    /// the record in the Dashboard.
    var playerCode: String { String(storageKey.suffix(6)).uppercased() }

    /// What a new save calls its demigod: the given name Apple sent, or the
    /// default every save has had.
    var demigodName: String {
        guard let displayName else { return "Demigod" }
        let given = displayName.split(separator: " ").first.map(String.init) ?? displayName
        return given.isEmpty ? "Demigod" : given
    }
}
