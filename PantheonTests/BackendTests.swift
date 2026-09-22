import XCTest
@testable import Pantheon

/// The Supabase backend (`Docs/BACKEND.md`, 2026-09-22): the config the
/// bundle carries, the requests the client builds, a session kept on disk,
/// the refresh on a refused token, the save row's round trip, the restore
/// rules, and the archive a start-over leaves behind. Nothing here reaches
/// a network: every client is handed a canned transport, and every file
/// goes to a temporary folder.
final class BackendTests: XCTestCase {
    private var folder: URL!
    private var previousBase: URL?

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackendTests-\(UUID().uuidString)", isDirectory: true)
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
    private static let userID = "11111111-1111-1111-1111-111111111111"

    /// What Supabase's auth answers a sign-in with.
    private static func authAnswer(token: String, refresh: String) -> String {
        """
        {"access_token":"\(token)","token_type":"bearer","expires_in":3600,"refresh_token":"\(refresh)","user":{"id":"\(userID)","is_anonymous":true}}
        """
    }

    /// A canned backend: records every request and answers each by its
    /// path, its method and its place in the sequence.
    private actor StubBackend {
        private(set) var requests: [URLRequest] = []
        private let answer: @Sendable (URLRequest, Int) -> (status: Int, body: String)

        init(answer: @escaping @Sendable (URLRequest, Int) -> (status: Int, body: String)) {
            self.answer = answer
        }

        func handle(_ request: URLRequest) -> (Data, HTTPURLResponse) {
            requests.append(request)
            let reply = answer(request, requests.count)
            let url = request.url ?? URL(string: "https://example.supabase.co")!
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            return (Data(reply.body.utf8), response)
        }

        var transport: SupabaseClient.Transport {
            { request in await self.handle(request) }
        }
    }

    private static func path(of request: URLRequest) -> String { request.url?.path ?? "" }

    // MARK: - The config

    func testConfigNeedsBothValuesAndHTTPS() {
        XCTAssertNil(BackendConfig.from(dictionary: ["SupabaseURL": "", "SupabaseAnonKey": ""]), "the plist as committed: no backend")
        XCTAssertNil(BackendConfig.from(dictionary: ["SupabaseURL": "https://x.supabase.co", "SupabaseAnonKey": "  "]))
        XCTAssertNil(BackendConfig.from(dictionary: ["SupabaseURL": "http://x.supabase.co", "SupabaseAnonKey": "k"]), "never over plain http")
        XCTAssertNil(BackendConfig.from(dictionary: ["SupabaseURL": "https://x.supabase.co"]), "a missing key is no backend")
        let config = BackendConfig.from(dictionary: ["SupabaseURL": " https://x.supabase.co \n", "SupabaseAnonKey": " k "])
        XCTAssertEqual(config?.url.host, "x.supabase.co")
        XCTAssertEqual(config?.anonKey, "k")
    }

    func testBundledPlistShipsEmpty() {
        let bundle = Bundle(for: AccountService.self)
        XCTAssertNotNil(bundle.url(forResource: BackendConfig.filename, withExtension: "plist"),
                        "Backend.plist must be in the app bundle, or the owner's keys have nowhere to go")
        XCTAssertNil(BackendConfig.load(bundle: bundle), "the committed plist is empty: CI and a fresh checkout play offline")
    }

    // MARK: - Requests and sessions

    func testRequestCarriesTheKeysAndThePath() {
        let anonymous = SupabaseClient.request(
            config: BackendTests.config, method: "POST", path: "auth/v1/signup",
            query: [], body: Data("{}".utf8), bearer: nil, headers: [:]
        )
        XCTAssertEqual(anonymous.url?.absoluteString, "https://example.supabase.co/auth/v1/signup")
        XCTAssertEqual(anonymous.httpMethod, "POST")
        XCTAssertEqual(anonymous.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(anonymous.value(forHTTPHeaderField: "Authorization"), "Bearer anon-key", "the anon key stands in for a bearer before a sign-in")
        XCTAssertEqual(anonymous.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let signed = SupabaseClient.request(
            config: BackendTests.config, method: "GET", path: "rest/v1/saves",
            query: [URLQueryItem(name: "select", value: "payload"), URLQueryItem(name: "player_id", value: "eq.\(BackendTests.userID)")],
            body: nil, bearer: "tok-1", headers: ["Prefer": "return=minimal"]
        )
        XCTAssertEqual(signed.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/saves?select=payload&player_id=eq.\(BackendTests.userID)")
        XCTAssertEqual(signed.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")
        XCTAssertEqual(signed.value(forHTTPHeaderField: "apikey"), "anon-key", "the anon key rides on every call")
        XCTAssertEqual(signed.value(forHTTPHeaderField: "Prefer"), "return=minimal")
    }

    func testSessionIsReadOffAnAuthAnswer() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = try BackendSession.from(
            authResponse: Data(BackendTests.authAnswer(token: "tok-1", refresh: "ref-1").utf8),
            provider: "anonymous", now: now
        )
        XCTAssertEqual(session.accessToken, "tok-1")
        XCTAssertEqual(session.refreshToken, "ref-1")
        XCTAssertEqual(session.userID, BackendTests.userID)
        XCTAssertEqual(session.provider, "anonymous")
        let lifetime: TimeInterval = session.expiresAt.timeIntervalSince(now)
        let expected: TimeInterval = 3600
        XCTAssertEqual(lifetime, expected, accuracy: 0.001)
        XCTAssertFalse(session.isExpiringSoon)

        var soon = session
        soon.expiresAt = Date().addingTimeInterval(30)
        XCTAssertTrue(soon.isExpiringSoon, "a minute of margin")

        XCTAssertThrowsError(try BackendSession.from(authResponse: Data("{\"msg\":\"no\"}".utf8), provider: "anonymous"))
    }

    func testErrorsMapTheGuardsMessages() {
        let lineage = BackendError.from(status: 400, data: Data("{\"code\":\"P0001\",\"message\":\"lineage\"}".utf8))
        XCTAssertEqual(lineage, .lineage)
        let stale = BackendError.from(status: 400, data: Data("{\"code\":\"P0001\",\"message\":\"stale\"}".utf8))
        XCTAssertEqual(stale, .stale)
        let auth = BackendError.from(status: 422, data: Data("{\"code\":422,\"msg\":\"Anonymous sign-ins are disabled\"}".utf8))
        XCTAssertEqual(auth, .http(status: 422, code: nil, message: "Anonymous sign-ins are disabled"))
        let bare = BackendError.from(status: 500, data: Data("gateway".utf8))
        XCTAssertEqual(bare, .http(status: 500, code: nil, message: "gateway"))
    }

    @MainActor
    func testAnonymousSignInPersistsTheSession() async throws {
        let stub = StubBackend { _, _ in (200, BackendTests.authAnswer(token: "tok-1", refresh: "ref-1")) }
        let client = SupabaseClient(config: BackendTests.config, storageKey: "abc", directory: folder, transport: await stub.transport)
        XCTAssertFalse(client.isSignedIn)

        let session = try await client.ensureSession(appleIdentityToken: nil)
        XCTAssertEqual(session.provider, "anonymous")
        XCTAssertEqual(client.userID, BackendTests.userID)

        let requests = await stub.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(BackendTests.path(of: requests[0]), "/auth/v1/signup")
        XCTAssertEqual(requests[0].httpBody.map { String(decoding: $0, as: UTF8.self) }, "{\"data\":{}}")

        let file = folder.appendingPathComponent(SupabaseClient.filename(for: "abc"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the session is kept beside the saves")

        let again = SupabaseClient(config: BackendTests.config, storageKey: "abc", directory: folder, transport: await stub.transport)
        XCTAssertTrue(again.isSignedIn, "a second launch reads the session back")
        XCTAssertEqual(again.userID, BackendTests.userID)
        _ = try await again.ensureSession(appleIdentityToken: nil)
        let afterReuse = await stub.requests.count
        XCTAssertEqual(afterReuse, 1, "a good session is reused, not signed in again")

        again.signOut()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(again.isSignedIn)
    }

    @MainActor
    func testARefusedTokenIsRefreshedOnceAndTheCallRetried() async throws {
        let stub = StubBackend { request, index in
            switch (BackendTests.path(of: request), index) {
            case ("/auth/v1/signup", _): return (200, BackendTests.authAnswer(token: "tok-1", refresh: "ref-1"))
            case ("/rest/v1/saves", 2): return (401, "{\"message\":\"JWT expired\"}")
            case ("/auth/v1/token", _): return (200, BackendTests.authAnswer(token: "tok-2", refresh: "ref-2"))
            case ("/rest/v1/saves", _): return (200, "[]")
            default: return (404, "{\"message\":\"unexpected\"}")
            }
        }
        let client = SupabaseClient(config: BackendTests.config, storageKey: "abc", directory: folder, transport: await stub.transport)
        _ = try await client.signInAnonymously()
        let (data, _) = try await client.rest("GET", "saves", query: [URLQueryItem(name: "select", value: "payload")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[]")

        let requests = await stub.requests
        XCTAssertEqual(requests.map(BackendTests.path(of:)), ["/auth/v1/signup", "/rest/v1/saves", "/auth/v1/token", "/rest/v1/saves"])
        XCTAssertEqual(requests[2].url?.query, "grant_type=refresh_token")
        XCTAssertEqual(requests[2].httpBody.map { String(decoding: $0, as: UTF8.self) }, "{\"refresh_token\":\"ref-1\"}")
        XCTAssertEqual(requests[3].value(forHTTPHeaderField: "Authorization"), "Bearer tok-2", "the retry carries the new token")
        XCTAssertEqual(client.session?.accessToken, "tok-2")
    }

    // MARK: - The save row

    func testUpsertBodyRoundTripsThroughARow() throws {
        let game = NewGame.create()
        let data = try SaveStore.encode(game)
        let snapshot = CloudSnapshot(data: data, modifiedAt: Date(), lineage: game.player.createdAt)
        let body = try SupabaseSaveStore.upsertBody(playerID: BackendTests.userID, snapshot: snapshot)

        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["player_id"] as? String, BackendTests.userID)
        XCTAssertEqual(rows[0]["bytes"] as? Int, data.count)
        XCTAssertEqual(rows[0]["version"] as? Int, SaveGame.currentVersion)

        let back = try XCTUnwrap(SupabaseSaveStore.snapshot(fromRows: body))
        XCTAssertEqual(back.data, data, "the payload comes back byte for byte")
        let stampDrift: TimeInterval = abs(back.modifiedAt.timeIntervalSince(snapshot.modifiedAt))
        let lineageDrift: TimeInterval = abs((back.lineage ?? .distantPast).timeIntervalSince(game.player.createdAt))
        XCTAssertLessThan(stampDrift, 1, "whole seconds over the wire")
        XCTAssertLessThan(lineageDrift, 1)

        XCTAssertNil(try SupabaseSaveStore.snapshot(fromRows: Data("[]".utf8)), "no row is no cloud copy")
        XCTAssertThrowsError(try SupabaseSaveStore.snapshot(fromRows: Data("[{\"version\":1}]".utf8)))
    }

    func testPostgresTimestampsWithFractionsAreRead() {
        let whole = SupabaseSaveStore.date("2026-09-22T10:11:12Z")
        let fraction = SupabaseSaveStore.date("2026-09-22T10:11:12.123456+00:00")
        XCTAssertNotNil(whole)
        XCTAssertEqual(fraction, whole)
        XCTAssertNil(SupabaseSaveStore.date("yesterday"))
    }

    @MainActor
    func testRestorePullsANewerCopyAndKeepsAForeignOne() async throws {
        // The store restores under the ACCOUNT's storage key, as the app
        // saves: the local game goes under that same key, or the import
        // lands in another file (run 201).
        let account = Account(id: "guest-test", provider: .guest, displayName: nil, email: nil, createdAt: Date())
        let key = account.storageKey
        try SaveStore.save(NewGame.create(), key: key)
        let local = try XCTUnwrap(SaveStore.load(key: key))

        var cloudGame = local
        cloudGame.player.displayName = "FromTheCloud"
        cloudGame.savedAt = local.savedAt.addingTimeInterval(100)
        let cloudPayload = try SaveStore.encode(cloudGame)

        func rows(lineage: Date) throws -> String {
            let row: [String: Any] = [
                "payload": String(decoding: cloudPayload, as: UTF8.self),
                "version": 1,
                "lineage": SupabaseSaveStore.iso(lineage),
                "saved_at": SupabaseSaveStore.iso(cloudGame.savedAt),
                "revision": 3,
            ]
            return String(decoding: try JSONSerialization.data(withJSONObject: [row]), as: UTF8.self)
        }
        let sameLineage = try rows(lineage: local.player.createdAt)
        let otherLineage = try rows(lineage: local.player.createdAt.addingTimeInterval(-1000))

        func backend(answering saves: String) -> StubBackend {
            StubBackend { request, _ in
                switch (BackendTests.path(of: request), request.httpMethod ?? "") {
                case ("/auth/v1/signup", _): return (200, BackendTests.authAnswer(token: "tok-1", refresh: "ref-1"))
                case ("/rest/v1/players", "POST"): return (201, "")
                case ("/rest/v1/saves", "GET"): return (200, saves)
                case ("/rest/v1/saves", "DELETE"): return (204, "")
                default: return (404, "{\"message\":\"unexpected\"}")
                }
            }
        }

        // Same lineage, newer: pulled over the local save, which is kept aside.
        let stub = backend(answering: sameLineage)
        let client = SupabaseClient(config: BackendTests.config, storageKey: key, directory: folder, transport: await stub.transport)
        let store = SupabaseSaveStore(client: client, account: account)
        let reached = await store.prepare()
        XCTAssertTrue(reached)
        let registered = await stub.requests.filter { BackendTests.path(of: $0) == "/rest/v1/players" }
        XCTAssertEqual(registered.count, 1, "the player row is upserted at sign-in")
        XCTAssertEqual(registered.first?.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")

        let restored = await store.restoreIfNewer(than: local, within: 2)
        XCTAssertTrue(restored)
        XCTAssertEqual(try SaveStore.load(key: key)?.player.displayName, "FromTheCloud")
        let folderNames = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Pantheon").path)
        XCTAssertTrue(folderNames.contains { $0.hasPrefix("replaced_") }, "the replaced save is kept aside")
        XCTAssertNil(store.foreign)

        // As new as the local copy: kept.
        let current = try XCTUnwrap(SaveStore.load(key: key))
        let keptSame = await store.restoreIfNewer(than: current, within: 2)
        XCTAssertFalse(keptSame, "the cloud copy is no newer than this phone's")

        // Another lineage: never pulled over a save; remembered as foreign.
        let foreignStub = backend(answering: otherLineage)
        let foreignClient = SupabaseClient(config: BackendTests.config, storageKey: key, directory: folder, transport: await foreignStub.transport)
        let foreignStore = SupabaseSaveStore(client: foreignClient, account: account)
        _ = await foreignStore.prepare()
        let pulled = await foreignStore.restoreIfNewer(than: current, within: 2)
        XCTAssertFalse(pulled)
        XCTAssertNotNil(foreignStore.foreign, "offered on the Account panel, never written unasked")
        XCTAssertEqual(try SaveStore.load(key: key)?.player.displayName, "FromTheCloud", "untouched")

        // Erase: the row deleted by the signed-in user's id.
        let erased = await store.erase()
        XCTAssertTrue(erased)
        let deletes = await stub.requests.filter { $0.httpMethod == "DELETE" }
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(deletes.first?.url?.query, "player_id=eq.\(BackendTests.userID)")
    }

    // MARK: - Starting over

    func testArchiveKeepsTheSaveAside() throws {
        let key = "abc"
        XCTAssertFalse(SaveStore.archive(key: key), "nothing to archive yet")
        try SaveStore.save(NewGame.create(), key: key)
        XCTAssertTrue(SaveStore.hasSave(key: key))

        XCTAssertTrue(SaveStore.archive(key: key))
        XCTAssertFalse(SaveStore.hasSave(key: key), "a new game opens on the next bootstrap")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Pantheon").path)
        XCTAssertTrue(names.contains { $0.hasPrefix("reset_") && $0.hasSuffix("pantheon_save_abc.json") },
                      "the old save is kept as reset_<stamp>_…, never deleted")
        XCTAssertFalse(SaveStore.archive(key: key), "once")
    }
}
