import Foundation

/// How one step of a deletion ended.
enum DeletionOutcome: Equatable {
    case done
    /// Nothing to do there: no backend, a guest, a build not signed for
    /// iCloud. The words say which.
    case skipped(String)
    case failed(String)

    var isDone: Bool { self == .done }
}

/// What one deletion did, step by step: worded for the console
/// (`[Account]` lines) and for the sentence the sign-in screen shows after
/// it (`Docs/SETTINGS.md` §3).
struct AccountDeletionReport: Equatable {
    let isApple: Bool
    var cloudCopy: DeletionOutcome = .skipped("no cloud copy was kept")
    var appleRevocation: DeletionOutcome = .skipped("a guest has no Apple ID")
    var backendAccount: DeletionOutcome = .skipped("no backend is configured")
    var iCloudSave: DeletionOutcome = .skipped("this build is not signed for iCloud")
    var socialRecords: DeletionOutcome = .skipped("this build is not signed for iCloud")
    var filesRemoved = 0
    /// True when a step that would let the account come back failed — the
    /// cloud copy, or the backend's user — and the deletion stopped before
    /// anything on the phone was touched. The account is kept whole and the
    /// player is asked to try again with a connection.
    var stopped = false

    /// Sign in with Apple still lists Pantheon: the player stops it by hand
    /// (TN3194's path when no token could be revoked).
    var needsManualAppleStop: Bool { isApple && !appleRevocation.isDone }

    static let manualAppleStop = "To finish, open the iPhone's Settings → your name → Sign-In & Security → Sign in with Apple → Pantheon, and tap Stop Using Apple ID."

    /// The sentence for the player.
    var sentence: String {
        if stopped {
            return "Your account was NOT deleted: the cloud could not be reached. Nothing was removed. Check the connection and try again."
        }
        var words = "Your account and its data were deleted."
        if needsManualAppleStop { words += " " + AccountDeletionReport.manualAppleStop }
        return words
    }

    /// One line per step, for the console and the diagnostics.
    var lines: [String] {
        [
            "cloud copy: \(AccountDeletionReport.describe(cloudCopy))",
            "Sign in with Apple: \(AccountDeletionReport.describe(appleRevocation))",
            "backend user: \(AccountDeletionReport.describe(backendAccount))",
            "iCloud save: \(AccountDeletionReport.describe(iCloudSave))",
            "Allies records: \(AccountDeletionReport.describe(socialRecords))",
            stopped ? "stopped before the phone: nothing local was removed" : "files removed on this phone: \(filesRemoved)",
        ]
    }

    static func describe(_ outcome: DeletionOutcome) -> String {
        switch outcome {
        case .done: return "deleted"
        case .skipped(let why): return "skipped (\(why))"
        case .failed(let why): return "FAILED (\(why))"
        }
    }
}

/// The CloudKit half of a deletion, behind a protocol so a test can stand in
/// for it: the private save record and the public Allies records. The app's
/// is `CloudAccountEraser`, which exists only in a build signed for iCloud.
@MainActor
protocol CloudAccountErasing: AnyObject {
    func eraseSave(key: String) async -> DeletionOutcome
    func eraseSocialRecords() async -> DeletionOutcome
}

/// Deletes one account everywhere it lives (`Docs/SETTINGS.md` §3), in the
/// order that never leaves a copy able to bring it back:
///
/// 0. an Apple ID signs in to the backend again with the identity token of
///    the fresh authorization, so the next steps run on a good session;
/// 1. the cloud copy the store keeps — its pending upload cancelled first,
///    so nothing re-creates the row afterwards;
/// 2. the backend: Sign in with Apple's tokens revoked by the `apple-revoke`
///    Edge Function (an Apple ID, with the code of a fresh authorization),
///    then the user, its player row and its save deleted by
///    `delete_my_account()`, then the session file;
/// 3. CloudKit: the private save record of an Apple ID and the public Allies
///    records (profile, guild membership, requests, friendships, mail, board
///    posts, war attacks);
/// 4. this phone: the save, every copy kept aside (`reset_`, `replaced_`,
///    `corrupt_`), the backend session file, the offline practice world.
///
/// Steps 1 and 2 must succeed — a copy left there would restore on the next
/// sign-in — so a failure there stops the deletion before the phone is
/// touched (`AccountDeletionReport.stopped`), and so does an Apple ID the
/// backend could not be signed in to. The exception is a user nobody can
/// sign in as again (a guest whose session the backend refused, an Apple ID
/// it refuses outright): its copy can never restore. A missing Edge Function, a
/// missing SQL function and a CloudKit record that will not go are logged
/// and the rest carries on. `AppSession.deleteAccount` runs it, then forgets
/// the account in the ledger and clears the reminders.
@MainActor
final class AccountDeletion {
    let account: Account
    private let cloudSave: CloudSaveSyncing?
    private let client: SupabaseClient?
    private let cloudKit: CloudAccountErasing?
    private let directory: URL?

    /// `cloudSave` is the retired store's own cloud copy; `client` the
    /// backend client it signed in with (or one reading this account's
    /// session file); `cloudKit` nil in a build not signed for iCloud and in
    /// the tests; `directory` the save folder.
    init(
        account: Account,
        cloudSave: CloudSaveSyncing?,
        client: SupabaseClient?,
        cloudKit: CloudAccountErasing?,
        directory: URL? = SaveStore.directory
    ) {
        self.account = account
        self.cloudSave = cloudSave
        self.client = client
        self.cloudKit = cloudKit
        self.directory = directory
    }

    /// The Edge Function that revokes Sign in with Apple's tokens, and the
    /// SQL function that deletes the caller (Backend/supabase).
    static let revokeFunction = "apple-revoke"
    static let deleteFunction = "rpc/delete_my_account"

    func run(appleAuthorizationCode: String?, appleIdentityToken: String?) async -> AccountDeletionReport {
        var report = AccountDeletionReport(isApple: account.provider == .apple)
        if report.isApple { report.appleRevocation = .skipped("no backend to reach Apple through") }

        // 0. Apple's fresh sheet signs straight back in to the same backend
        // user, so the next two steps run on a good session whatever state
        // the phone's was in (expired, refused, never made). An Apple ID can
        // always sign in again, so a copy the backend kept would come back
        // with it: with no session after this the deletion stops, unless the
        // backend REFUSED the sign-in outright (its Apple provider off, the
        // token not its), when no sign-in can ever reach that copy either.
        var appleRefused = false
        if let client, report.isApple {
            if let token = appleIdentityToken {
                do {
                    _ = try await client.signInWithApple(identityToken: token)
                } catch BackendError.http(let status, _, let message) where AccountDeletion.isRefusal(status) {
                    appleRefused = true
                    AccountDeletion.log("the backend refused Apple's sign-in (\(status): \(message)); nothing can restore through it")
                } catch {
                    AccountDeletion.log("Apple's sign-in did not reach the backend: \(error.localizedDescription)")
                }
            }
            if !client.isSignedIn && !appleRefused {
                report.cloudCopy = .failed("no backend session to reach it with")
                report.stopped = true
                return finish(report)
            }
        }

        // 1. The copy the store keeps.
        if let cloudSave {
            if await cloudSave.erase() {
                report.cloudCopy = .done
            } else if let client, !client.isSignedIn, !report.isApple || appleRefused, cloudSave is SupabaseSaveStore {
                // A session the backend refused (a guest's dead refresh
                // token, or an Apple ID it will not sign in): nobody can
                // sign in as that user again, so its copy can never restore.
                // Carry on.
                report.cloudCopy = .failed("the cloud session had ended; its copy can never be restored")
                AccountDeletion.log("the cloud session had ended; its orphaned copy is left to the backend's sweep")
            } else {
                report.cloudCopy = .failed(cloudSave.lastError ?? "\(cloudSave.serviceName) could not be reached")
                report.stopped = true
                return finish(report)
            }
        }

        // 2. The backend.
        if let client {
            if client.isSignedIn {
                if report.isApple {
                    report.appleRevocation = await revokeApple(code: appleAuthorizationCode, client: client)
                }
                report.backendAccount = await deleteBackendUser(client)
                if case .failed = report.backendAccount, !missingDeleteFunction {
                    report.stopped = true
                    return finish(report)
                }
                client.signOut()
            } else {
                report.backendAccount = .skipped("no backend session on this phone")
                if report.isApple { report.appleRevocation = .skipped("no backend session to reach Apple through") }
            }
        }

        // 3. CloudKit, where the build may use it.
        if let cloudKit {
            if report.isApple { report.iCloudSave = await cloudKit.eraseSave(key: account.storageKey) }
            report.socialRecords = await cloudKit.eraseSocialRecords()
        }

        // 4. This phone.
        report.filesRemoved = AccountDeletion.removeLocalFiles(key: account.storageKey, in: directory)
        LocalSocialBackend.wipe()
        return finish(report)
    }

    // MARK: - The backend

    /// An answer that will not change on a retry: a 4xx other than a
    /// timeout or a rate limit.
    nonisolated static func isRefusal(_ status: Int) -> Bool {
        (400..<500).contains(status) && status != 408 && status != 429
    }

    /// Set when the database answered that `delete_my_account()` does not
    /// exist: the migration was never applied. The save row is deleted
    /// instead (its own row-level policy allows it) and the rest carries on,
    /// since nothing is left that could restore.
    private var missingDeleteFunction = false

    private func revokeApple(code: String?, client: SupabaseClient) async -> DeletionOutcome {
        guard let code, !code.isEmpty else {
            AccountDeletion.log("Sign in with Apple not revoked: no authorization code")
            return .skipped("no authorization code from Apple")
        }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["authorization_code": code])
            _ = try await client.function(AccountDeletion.revokeFunction, body: body)
            return .done
        } catch BackendError.http(let status, _, _) where status == 404 {
            AccountDeletion.log("Sign in with Apple not revoked: the \(AccountDeletion.revokeFunction) function is not deployed (404)")
            return .failed("the \(AccountDeletion.revokeFunction) function is not deployed")
        } catch {
            AccountDeletion.log("Sign in with Apple not revoked: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func deleteBackendUser(_ client: SupabaseClient) async -> DeletionOutcome {
        do {
            _ = try await client.rest("POST", AccountDeletion.deleteFunction, body: Data("{}".utf8))
            return .done
        } catch BackendError.http(let status, _, _) where status == 404 {
            missingDeleteFunction = true
            AccountDeletion.log("delete_my_account() is not in the database (404): apply the migration; deleting the save row instead")
            let rowGone = await deleteSaveRow(client)
            let row = rowGone ? "was deleted" : "could not be deleted"
            return .failed("delete_my_account() is missing; the save row \(row)")
        } catch {
            AccountDeletion.log("the backend user could not be deleted: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func deleteSaveRow(_ client: SupabaseClient) async -> Bool {
        guard let uid = client.userID else { return false }
        do {
            _ = try await client.rest("DELETE", "saves", query: [URLQueryItem(name: "player_id", value: "eq.\(uid)")],
                                      prefer: "return=minimal")
            return true
        } catch {
            return false
        }
    }

    // MARK: - This phone

    /// Everything in the save folder that belongs to one storage key: the
    /// save, its half-written temp file, every copy kept aside by a reset, a
    /// restore or a quarantine, and the backend session. Deleted, not
    /// archived. The count removed.
    nonisolated static func removeLocalFiles(key: String, in directory: URL?) -> Int {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where belongs(name, toKey: key) {
            if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))) != nil {
                removed += 1
            }
        }
        return removed
    }

    /// Whether a file name in the save folder is one of the key's.
    nonisolated static func belongs(_ name: String, toKey key: String) -> Bool {
        let save = SaveStore.filename(for: key)
        if name == save || name == save + ".tmp" || name == SupabaseClient.filename(for: key) { return true }
        let asideSuffix = "_" + save
        guard name.hasSuffix(asideSuffix) else { return false }
        return ["reset_", "replaced_", "corrupt_"].contains { name.hasPrefix($0) }
    }

    // MARK: - The log

    private func finish(_ report: AccountDeletionReport) -> AccountDeletionReport {
        AccountDeletion.log("deleting Player ID \(account.playerCode) (\(account.provider.rawValue))")
        for line in report.lines { AccountDeletion.log(line) }
        return report
    }

    nonisolated static func log(_ line: String) {
        let stamped = "[Account] \(line)"
        print(stamped)
        DiagnosticsLog.shared.record(stamped)
    }
}
