import XCTest
@testable import Pantheon

/// Deleting an account (`Docs/SETTINGS.md` §3, `Docs/BACKEND.md` §7; App
/// Review 5.1.1(v)): the order of the backend's calls — the cloud copy,
/// Apple's revocation, then the user — the files of ONE storage key and no
/// other, the steps that stop the deletion before the phone is touched, and
/// the ledger forgetting the account. Every backend is a canned transport, as
/// in `BackendTests`; every file goes to a temporary folder; CloudKit is a
/// stand-in.
final class AccountDeletionTests: XCTestCase {
    private var folder: URL!
    private var previousBase: URL?

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountDeletionTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        previousBase = SaveStore.baseURL
        SaveStore.baseURL = folder
    }

    override func tearDown() {
        SaveStore.baseURL = previousBase
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private static let config = BackendConfig(url: URL(string: "https://example.supabase.co")!, anonKey: "anon-key")
    private static let userID = "22222222-2222-2222-2222-222222222222"

    private static func authAnswer(token: String) -> String {
        """
        {"access_token":"\(token)","token_type":"bearer","expires_in":3600,"refresh_token":"ref-\(token)","user":{"id":"\(userID)"}}
        """
    }

    /// A canned backend that records every request and answers by the
    /// request's path and method.
    private actor DeletionBackend {
        private(set) var requests: [URLRequest] = []
        private let answer: @Sendable (String, String) -> (status: Int, body: String)

        init(answer: @escaping @Sendable (String, String) -> (status: Int, body: String)) {
            self.answer = answer
        }

        func handle(_ request: URLRequest) -> (Data, HTTPURLResponse) {
            requests.append(request)
            let reply = answer(request.url?.path ?? "", request.httpMethod ?? "")
            let url = request.url ?? URL(string: "https://example.supabase.co")!
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            return (Data(reply.body.utf8), response)
        }

        var transport: SupabaseClient.Transport {
            { request in await self.handle(request) }
        }

        /// "POST /rest/v1/rpc/delete_my_account", in the order they came.
        var paths: [String] {
            requests.map { request in
                let method = request.httpMethod ?? "?"
                let path = request.url?.path ?? "?"
                return method + " " + path
            }
        }
    }

    /// CloudKit's half, stood in: records what it was asked.
    @MainActor
    private final class CloudStandIn: CloudAccountErasing {
        var savesErased: [String] = []
        var socialErased = 0

        func eraseSave(key: String) async -> DeletionOutcome {
            savesErased.append(key)
            return .done
        }

        func eraseSocialRecords() async -> DeletionOutcome {
            socialErased += 1
            return .done
        }
    }

    private func account(_ provider: AccountProvider) -> Account {
        Account(id: provider == .apple ? "000777.deleted.0001" : "guest-deleted", provider: provider,
                displayName: nil, email: nil, createdAt: Date())
    }

    private var saveFolder: URL { folder.appendingPathComponent("Pantheon", isDirectory: true) }

    // MARK: - The files of one key

    @MainActor
    func testOnlyTheKeysFilesAreRemoved() throws {
        _ = SaveStore.directory   // creates the folder
        let mine = "aaaaaaaaaaaa1111"
        let theirs = "bbbbbbbbbbbb2222"
        let names = [
            SaveStore.filename(for: mine),
            SaveStore.filename(for: mine) + ".tmp",
            "reset_1790000000_" + SaveStore.filename(for: mine),
            "replaced_1790000001_" + SaveStore.filename(for: mine),
            "corrupt_1790000002_" + SaveStore.filename(for: mine),
            SupabaseClient.filename(for: mine),
            SaveStore.filename(for: theirs),
            "reset_1790000003_" + SaveStore.filename(for: theirs),
            SupabaseClient.filename(for: theirs),
            AccountService.filename,
            SaveStore.legacyFilename,
        ]
        for name in names {
            try Data("{}".utf8).write(to: saveFolder.appendingPathComponent(name))
        }
        let removed = AccountDeletion.removeLocalFiles(key: mine, in: SaveStore.directory)
        XCTAssertEqual(removed, 6, "the save, its temp file, three copies kept aside and the session")
        let left = try Set(FileManager.default.contentsOfDirectory(atPath: saveFolder.path))
        let expectedLeft: Set<String> = [
            SaveStore.filename(for: theirs),
            "reset_1790000003_" + SaveStore.filename(for: theirs),
            SupabaseClient.filename(for: theirs),
            AccountService.filename,
            SaveStore.legacyFilename,
        ]
        XCTAssertEqual(left, expectedLeft, "another account's files, the ledger and the legacy save are never touched")
        XCTAssertFalse(AccountDeletion.belongs("reset_1_" + SaveStore.filename(for: mine + "0"), toKey: mine),
                       "a longer key's copy is not this key's")
    }

    // MARK: - A guest

    @MainActor
    func testAGuestLeavesTheBackendAndThePhone() async throws {
        let guest = account(.guest)
        let key = guest.storageKey
        try SaveStore.save(NewGame.create(), key: key)
        let backend = DeletionBackend { path, method in
            switch (path, method) {
            case ("/auth/v1/signup", "POST"): return (200, AccountDeletionTests.authAnswer(token: "tok-1"))
            case ("/rest/v1/saves", "DELETE"): return (204, "")
            case ("/rest/v1/rpc/delete_my_account", "POST"): return (204, "")
            default: return (404, "{\"message\":\"unexpected\"}")
            }
        }
        let client = SupabaseClient(config: AccountDeletionTests.config, storageKey: key,
                                    directory: SaveStore.directory, transport: await backend.transport)
        _ = try await client.signInAnonymously()
        let sessionFile = saveFolder.appendingPathComponent(SupabaseClient.filename(for: key))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFile.path))

        let cloud = SupabaseSaveStore(client: client, account: guest)
        let cloudKit = CloudStandIn()
        let report = await AccountDeletion(account: guest, cloudSave: cloud, client: client,
                                           cloudKit: cloudKit, directory: SaveStore.directory)
            .run(appleAuthorizationCode: nil, appleIdentityToken: nil)

        XCTAssertFalse(report.stopped)
        XCTAssertEqual(report.cloudCopy, .done)
        XCTAssertEqual(report.backendAccount, .done)
        XCTAssertFalse(report.needsManualAppleStop, "a guest has no Apple ID to stop")
        XCTAssertEqual(report.filesRemoved, 1, "the save; the session file went with the backend's sign-out")
        XCTAssertFalse(SaveStore.hasSave(key: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionFile.path), "deleted, not archived")
        XCTAssertFalse(client.isSignedIn)
        XCTAssertTrue(cloudKit.savesErased.isEmpty, "a guest has no iCloud save record")
        XCTAssertEqual(cloudKit.socialErased, 1, "the Allies records go for a guest too")
        let paths = await backend.paths
        XCTAssertEqual(paths, ["POST /auth/v1/signup", "DELETE /rest/v1/saves", "POST /rest/v1/rpc/delete_my_account"])
        XCTAssertFalse(paths.contains { $0.contains("apple-revoke") })
    }

    // MARK: - An Apple ID

    @MainActor
    func testAnAppleIDIsRevokedBeforeItsUserIsDeleted() async throws {
        let apple = account(.apple)
        try SaveStore.save(NewGame.create(), key: apple.storageKey)
        let backend = DeletionBackend { path, method in
            switch (path, method) {
            case ("/auth/v1/token", "POST"): return (200, AccountDeletionTests.authAnswer(token: "apple-1"))
            case ("/functions/v1/apple-revoke", "POST"): return (200, "{\"revoked\":true}")
            case ("/rest/v1/rpc/delete_my_account", "POST"): return (204, "")
            default: return (404, "{\"message\":\"unexpected\"}")
            }
        }
        // No session on the phone: the fresh identity token signs back in.
        let client = SupabaseClient(config: AccountDeletionTests.config, storageKey: apple.storageKey,
                                    directory: SaveStore.directory, transport: await backend.transport)
        let cloudKit = CloudStandIn()
        let report = await AccountDeletion(account: apple, cloudSave: nil, client: client,
                                           cloudKit: cloudKit, directory: SaveStore.directory)
            .run(appleAuthorizationCode: "c0de", appleIdentityToken: "id-token")

        XCTAssertFalse(report.stopped)
        XCTAssertEqual(report.appleRevocation, .done)
        XCTAssertEqual(report.backendAccount, .done)
        XCTAssertFalse(report.needsManualAppleStop)
        XCTAssertFalse(report.sentence.contains("Stop Using"), "nothing left for the player to do by hand")
        XCTAssertEqual(cloudKit.savesErased, [apple.storageKey], "an Apple ID's iCloud save record goes as well")
        XCTAssertFalse(SaveStore.hasSave(key: apple.storageKey))

        let requests = await backend.requests
        let order = requests.map { $0.url?.path ?? "" }
        XCTAssertEqual(order, ["/auth/v1/token", "/functions/v1/apple-revoke", "/rest/v1/rpc/delete_my_account"],
                       "revoked while the session still stands, then the user deleted")
        let revokeBody = requests.dropFirst().first?.httpBody.map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(revokeBody, "{\"authorization_code\":\"c0de\"}")
        XCTAssertEqual(requests.dropFirst().first?.value(forHTTPHeaderField: "Authorization"), "Bearer apple-1",
                       "the function is called as the signed-in player")
    }

    @MainActor
    func testAMissingRevokeFunctionIsLoggedAndEverythingElseGoes() async throws {
        let apple = account(.apple)
        try SaveStore.save(NewGame.create(), key: apple.storageKey)
        let backend = DeletionBackend { path, method in
            switch (path, method) {
            case ("/auth/v1/token", "POST"): return (200, AccountDeletionTests.authAnswer(token: "apple-2"))
            case ("/functions/v1/apple-revoke", "POST"): return (404, "{\"code\":\"NOT_FOUND\",\"message\":\"Requested function was not found\"}")
            case ("/rest/v1/rpc/delete_my_account", "POST"): return (204, "")
            default: return (404, "{\"message\":\"unexpected\"}")
            }
        }
        let client = SupabaseClient(config: AccountDeletionTests.config, storageKey: apple.storageKey,
                                    directory: SaveStore.directory, transport: await backend.transport)
        let report = await AccountDeletion(account: apple, cloudSave: nil, client: client,
                                           cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: "c0de", appleIdentityToken: "id-token")

        XCTAssertFalse(report.stopped, "a missing function never keeps the account")
        XCTAssertEqual(report.appleRevocation, .failed("the apple-revoke function is not deployed"))
        XCTAssertEqual(report.backendAccount, .done)
        XCTAssertTrue(report.needsManualAppleStop)
        XCTAssertTrue(report.sentence.contains(AccountDeletionReport.manualAppleStop), "the player is told how to stop it by hand")
        XCTAssertFalse(SaveStore.hasSave(key: apple.storageKey))
    }

    @MainActor
    func testWithoutABackendAnAppleIDIsDeletedAndStoppedByHand() async throws {
        let apple = account(.apple)
        try SaveStore.save(NewGame.create(), key: apple.storageKey)
        let report = await AccountDeletion(account: apple, cloudSave: nil, client: nil,
                                           cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: "c0de", appleIdentityToken: nil)
        XCTAssertFalse(report.stopped)
        XCTAssertTrue(report.needsManualAppleStop, "no server to revoke through")
        XCTAssertEqual(report.filesRemoved, 1)
    }

    // MARK: - What stops a deletion

    @MainActor
    func testAnUnreachableCloudStopsBeforeThePhoneIsTouched() async throws {
        let guest = account(.guest)
        let key = guest.storageKey
        try SaveStore.save(NewGame.create(), key: key)
        let backend = DeletionBackend { path, method in
            switch (path, method) {
            case ("/auth/v1/signup", "POST"): return (200, AccountDeletionTests.authAnswer(token: "tok-3"))
            case ("/rest/v1/saves", "DELETE"): return (503, "{\"message\":\"upstream unavailable\"}")
            default: return (204, "")
            }
        }
        let client = SupabaseClient(config: AccountDeletionTests.config, storageKey: key,
                                    directory: SaveStore.directory, transport: await backend.transport)
        _ = try await client.signInAnonymously()
        let cloud = SupabaseSaveStore(client: client, account: guest)
        let report = await AccountDeletion(account: guest, cloudSave: cloud, client: client,
                                           cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: nil, appleIdentityToken: nil)

        XCTAssertTrue(report.stopped)
        XCTAssertTrue(report.sentence.contains("NOT deleted"))
        XCTAssertTrue(SaveStore.hasSave(key: key), "the save is still on the phone")
        XCTAssertTrue(client.isSignedIn, "and so is the session")
        let paths = await backend.paths
        XCTAssertFalse(paths.contains("POST /rest/v1/rpc/delete_my_account"), "the user is never deleted after a failed step")
    }

    /// A guest whose session the backend refuses (its refresh token dead) can
    /// never be signed in as again, so its copy cannot restore: the deletion
    /// carries on and empties the phone rather than keeping an account nobody
    /// can delete.
    @MainActor
    func testAGuestWithADeadSessionIsStillDeleted() async throws {
        let guest = account(.guest)
        let key = guest.storageKey
        try SaveStore.save(NewGame.create(), key: key)
        let backend = DeletionBackend { path, method in
            switch (path, method) {
            case ("/auth/v1/signup", "POST"): return (200, AccountDeletionTests.authAnswer(token: "tok-5"))
            case ("/rest/v1/saves", "DELETE"): return (401, "{\"message\":\"JWT expired\"}")
            case ("/auth/v1/token", "POST"): return (400, "{\"error_description\":\"Invalid Refresh Token\"}")
            default: return (500, "{\"message\":\"unexpected\"}")
            }
        }
        let client = SupabaseClient(config: AccountDeletionTests.config, storageKey: key,
                                    directory: SaveStore.directory, transport: await backend.transport)
        _ = try await client.signInAnonymously()
        let cloud = SupabaseSaveStore(client: client, account: guest)
        let report = await AccountDeletion(account: guest, cloudSave: cloud, client: client,
                                           cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: nil, appleIdentityToken: nil)

        XCTAssertFalse(report.stopped, "an orphaned copy is no reason to keep the account")
        XCTAssertEqual(report.backendAccount, .skipped("no backend session on this phone"))
        XCTAssertFalse(SaveStore.hasSave(key: key))
    }

    /// An Apple ID can always sign in again, so a copy the backend kept would
    /// come back with it: with no session, the deletion stops — unless the
    /// backend refuses Apple's sign-in outright, when nothing can restore.
    @MainActor
    func testAnAppleIDTheBackendCannotReachStopsUnlessItIsRefused() async throws {
        let apple = account(.apple)
        let key = apple.storageKey

        // No session on the phone and no token from Apple's sheet.
        try SaveStore.save(NewGame.create(), key: key)
        let silent = DeletionBackend { _, _ in (500, "{\"message\":\"unexpected\"}") }
        let unsigned = SupabaseClient(config: AccountDeletionTests.config, storageKey: key,
                                      directory: SaveStore.directory, transport: await silent.transport)
        let noToken = await AccountDeletion(account: apple, cloudSave: nil, client: unsigned,
                                            cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: nil, appleIdentityToken: nil)
        XCTAssertTrue(noToken.stopped)
        XCTAssertTrue(SaveStore.hasSave(key: key), "nothing on the phone is touched")
        let silentPaths = await silent.paths
        XCTAssertTrue(silentPaths.isEmpty)

        // The backend is down: stop too.
        let down = DeletionBackend { _, _ in (503, "{\"message\":\"upstream unavailable\"}") }
        let downClient = SupabaseClient(config: AccountDeletionTests.config, storageKey: key,
                                        directory: SaveStore.directory, transport: await down.transport)
        let unreachable = await AccountDeletion(account: apple, cloudSave: nil, client: downClient,
                                                cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: "c0de", appleIdentityToken: "id-token")
        XCTAssertTrue(unreachable.stopped)
        XCTAssertTrue(SaveStore.hasSave(key: key))

        // The backend refuses Apple's sign-in: nobody can restore through it.
        let refusing = DeletionBackend { path, method in
            switch (path, method) {
            case ("/auth/v1/token", "POST"): return (400, "{\"error_code\":\"provider_disabled\",\"msg\":\"Unsupported provider\"}")
            default: return (500, "{\"message\":\"unexpected\"}")
            }
        }
        let refusedClient = SupabaseClient(config: AccountDeletionTests.config, storageKey: key,
                                           directory: SaveStore.directory, transport: await refusing.transport)
        let refused = await AccountDeletion(account: apple, cloudSave: nil, client: refusedClient,
                                            cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: "c0de", appleIdentityToken: "id-token")
        XCTAssertFalse(refused.stopped)
        XCTAssertEqual(refused.backendAccount, .skipped("no backend session on this phone"))
        XCTAssertTrue(refused.needsManualAppleStop, "no session to reach Apple through")
        XCTAssertFalse(SaveStore.hasSave(key: key))
        XCTAssertTrue(AccountDeletion.isRefusal(400))
        XCTAssertFalse(AccountDeletion.isRefusal(429), "a rate limit is worth a retry")
    }

    @MainActor
    func testARefusedUserDeletionStopsTooButAMissingFunctionDoesNot() async throws {
        let guest = account(.guest)
        let key = guest.storageKey

        // The database refuses: the account stays whole.
        try SaveStore.save(NewGame.create(), key: key)
        let refusing = DeletionBackend { path, method in
            switch (path, method) {
            case ("/auth/v1/signup", "POST"): return (200, AccountDeletionTests.authAnswer(token: "tok-4"))
            case ("/rest/v1/rpc/delete_my_account", "POST"): return (500, "{\"message\":\"internal\"}")
            default: return (204, "")
            }
        }
        let first = SupabaseClient(config: AccountDeletionTests.config, storageKey: key,
                                   directory: SaveStore.directory, transport: await refusing.transport)
        _ = try await first.signInAnonymously()
        let stopped = await AccountDeletion(account: guest, cloudSave: nil, client: first,
                                            cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: nil, appleIdentityToken: nil)
        XCTAssertTrue(stopped.stopped)
        XCTAssertTrue(SaveStore.hasSave(key: key))

        // The migration was never applied: the save row goes instead, and
        // so does everything on the phone.
        let unmigrated = DeletionBackend { path, method in
            switch (path, method) {
            case ("/rest/v1/rpc/delete_my_account", "POST"):
                return (404, "{\"code\":\"PGRST202\",\"message\":\"Could not find the function public.delete_my_account\"}")
            case ("/rest/v1/saves", "DELETE"): return (204, "")
            default: return (404, "{\"message\":\"unexpected\"}")
            }
        }
        let second = SupabaseClient(config: AccountDeletionTests.config, storageKey: key,
                                    directory: SaveStore.directory, transport: await unmigrated.transport)
        XCTAssertTrue(second.isSignedIn, "the session kept by the stopped deletion")
        let carried = await AccountDeletion(account: guest, cloudSave: nil, client: second,
                                            cloudKit: nil, directory: SaveStore.directory)
            .run(appleAuthorizationCode: nil, appleIdentityToken: nil)
        XCTAssertFalse(carried.stopped)
        XCTAssertEqual(carried.backendAccount, .failed("delete_my_account() is missing; the save row was deleted"))
        XCTAssertFalse(SaveStore.hasSave(key: key))
        let paths = await unmigrated.paths
        XCTAssertEqual(paths, ["POST /rest/v1/rpc/delete_my_account", "DELETE /rest/v1/saves"])
    }

    // MARK: - The ledger

    @MainActor
    func testAForgottenAccountLeavesTheLedger() {
        let accounts = AccountService(directory: SaveStore.directory)
        let first = AppleCredential(user: "000777.forget.0001", givenName: "Tyler", familyName: "Pratt", email: "owner@example.com")
        let signedIn = accounts.signInWithApple(first)
        XCTAssertEqual(signedIn.displayName, "Tyler Pratt")

        accounts.forget(signedIn)
        XCTAssertNil(accounts.account)

        let again = AccountService(directory: SaveStore.directory)
        XCTAssertNil(again.account, "the ledger on disk forgot it too")
        let later = AppleCredential(user: "000777.forget.0001", givenName: nil, familyName: nil, email: nil)
        let back = again.signInWithApple(later)
        XCTAssertNil(back.displayName, "its name is gone from this phone")
        XCTAssertNil(back.email)
    }
}
