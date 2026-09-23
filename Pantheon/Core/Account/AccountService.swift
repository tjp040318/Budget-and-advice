import Foundation
import AuthenticationServices

/// What Apple's credential carries into the game, as plain values, so the
/// service, the session and the tests never name a framework type.
struct AppleCredential: Equatable, Sendable {
    let user: String
    var givenName: String?
    var familyName: String?
    var email: String?
    /// Apple's identity token (a JWT), which the backend exchanges for its
    /// own session (`SupabaseClient.signInWithApple`; 2026-09-22). Present
    /// at a sign-in, never stored: the ledger keeps the account, not this.
    var identityToken: String? = nil
    /// Apple's one-time authorization code — single use, five minutes —
    /// which the `apple-revoke` Edge Function exchanges for a refresh token
    /// and revokes when the account is deleted (`Docs/SETTINGS.md` §3).
    /// Never stored.
    var authorizationCode: String? = nil

    /// The name as one string, or nil when Apple sent none — which is every
    /// authorisation after the first.
    var fullName: String? {
        let parts = [givenName, familyName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func from(_ credential: ASAuthorizationAppleIDCredential) -> AppleCredential {
        AppleCredential(
            user: credential.user,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName,
            email: credential.email,
            identityToken: credential.identityToken.flatMap { String(data: $0, encoding: .utf8) },
            authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        )
    }
}

/// The ledger on disk: who is signed in now, and everyone who ever was on
/// this phone — so a second Apple sign-in, which carries no name, gets the
/// first one's back.
private struct AccountLedger: Codable {
    var current: Account?
    var known: [Account]
}

/// The account the app is signed in to, persisted as `account.json` beside
/// the saves — a file, not UserDefaults, so the export and a support script
/// can read it — and the ways in and out of it (`Docs/PLAN.md`, *Accounts —
/// Sign in with Apple*). It never reads a save's contents: the file renames a
/// bind needs are `SaveStore`'s.
@MainActor
final class AccountService: ObservableObject {
    /// Who is signed in, or nil: the sign-in screen is the root then.
    @Published private(set) var account: Account?
    /// The last thing worth a sentence on the sign-in screen: a revoked
    /// sign-in, a bind that found a save already there.
    @Published var notice: String?

    /// What the app does when a sign-in is dropped from UNDER a running game
    /// (Apple says revoked): the session saves and retires the store.
    var onDropped: (() -> Void)?

    static let filename = "account.json"

    /// The CI tour's account: a fixed guest, so every launch of the tour
    /// opens the same save (the tour seeds its roster once and expects it on
    /// the next launch), with nothing to fetch and nothing to verify.
    static let tourAccount = Account(
        id: "guest-tour-000000",
        provider: .guest,
        displayName: "Demigod",
        email: nil,
        createdAt: Date(timeIntervalSince1970: 0)
    )

    private let directory: URL?
    private let persists: Bool
    private var known: [Account]

    /// `directory` is where `account.json` lives — the save folder, or a
    /// test's temporary one. A `preset` account is held in memory and never
    /// written: the tour's.
    init(directory: URL? = SaveStore.directory, preset: Account? = nil) {
        self.directory = directory
        if let preset {
            persists = false
            known = [preset]
            account = preset
            return
        }
        persists = true
        let ledger = AccountService.read(from: directory)
        known = ledger.known
        account = ledger.current
    }

    // MARK: - Sign in

    /// Apple's credential, unpacked. The name and the email arrive only at
    /// the FIRST authorisation; a later one carries neither, and the ledger
    /// gives the first one's back.
    @discardableResult
    func signInWithApple(_ credential: AppleCredential) -> Account {
        let remembered = known.first { $0.id == credential.user }
        var next = remembered ?? Account(
            id: credential.user,
            provider: .apple,
            displayName: nil,
            email: nil,
            createdAt: Date()
        )
        next.provider = .apple
        if let name = credential.fullName { next.displayName = name }
        if let email = credential.email, !email.isEmpty { next.email = email }
        adopt(next)
        return next
    }

    /// The same, straight from the system button's credential.
    @discardableResult
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) -> Account {
        signInWithApple(AppleCredential.from(credential))
    }

    /// No account: progress on this phone only, until it is bound.
    @discardableResult
    func continueAsGuest() -> Account {
        let guest = Account.guest()
        adopt(guest)
        return guest
    }

    enum BindOutcome: Equatable {
        /// The guest's save now lives under the Apple account's key.
        case bound
        /// The Apple account already had a save on this phone; it wins, and
        /// the guest's file stays on disk under its own key.
        case keptAppleSave
        /// There was no guest to bind.
        case notAGuest
    }

    /// A guest who signs in with Apple keeps his progress: the guest's save
    /// file is renamed to the Apple key when that key has no save yet.
    @discardableResult
    func bindGuestToApple(_ credential: AppleCredential) -> BindOutcome {
        guard let guest = account, guest.isGuest else { return .notAGuest }
        let apple = signInWithApple(credential)
        if SaveStore.hasSave(key: apple.storageKey) {
            notice = "That Apple ID already had a save on this phone, so it was kept. The guest's progress stays on this phone under its own key."
            return .keptAppleSave
        }
        _ = SaveStore.adopt(from: guest.storageKey, to: apple.storageKey)
        return .bound
    }

    /// Drops the account. The save file stays on disk under its key and the
    /// ledger keeps the name, so the same Apple ID signs back in to the same
    /// progress.
    func signOut() {
        account = nil
        write()
    }

    /// A DELETED account (`Docs/SETTINGS.md` §3): signed out and gone from
    /// the ledger too, so its name and email are forgotten on this phone and
    /// the next sign-in with the same Apple ID starts a new account.
    func forget(_ gone: Account) {
        known.removeAll { $0.id == gone.id }
        if account?.id == gone.id { account = nil }
        write()
    }

    /// Asks Apple whether the signed-in Apple ID still authorises this app —
    /// on launch and on every return to the foreground. `.revoked` and
    /// `.notFound` drop the account (the file stays); a network error keeps
    /// it, because an offline player is not a revoked one. Returns false when
    /// the account was dropped. A guest has nothing to verify.
    @discardableResult
    func verifyCredentialState() async -> Bool {
        guard let current = account, current.provider == .apple else { return true }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: current.id)
            switch state {
            case .revoked, .notFound:
                notice = "This Apple ID no longer signs in to Pantheon. Sign in again to pick up where you left off."
                signOut()
                onDropped?()
                return false
            case .authorized, .transferred:
                return true
            @unknown default:
                return true
            }
        } catch {
            return true
        }
    }

    // MARK: - The ledger

    private func adopt(_ next: Account) {
        known.removeAll { $0.id == next.id }
        known.append(next)
        account = next
        write()
    }

    private var fileURL: URL? { directory?.appendingPathComponent(AccountService.filename) }

    private func write() {
        guard persists, let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(AccountLedger(current: account, known: known))
            try data.write(to: url, options: .atomic)
        } catch {
            notice = "The account could not be written: \(error.localizedDescription)"
        }
    }

    private static func read(from directory: URL?) -> AccountLedger {
        let empty = AccountLedger(current: nil, known: [])
        guard let url = directory?.appendingPathComponent(filename),
              let data = try? Data(contentsOf: url) else { return empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AccountLedger.self, from: data)) ?? empty
    }
}
