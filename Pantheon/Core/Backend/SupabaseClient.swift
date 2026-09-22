import Foundation

/// What a backend call ends in, worded for the console and the panel.
enum BackendError: Error, LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case http(status: Int, code: String?, message: String)
    case decoding(String)
    /// The cloud copy is another game's (a different `createdAt`): never
    /// overwritten; offered as `foreign` instead.
    case lineage
    /// The cloud copy is newer than the upload: another phone saved since.
    case stale

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No backend is configured."
        case .notSignedIn: return "Not signed in to the backend."
        case .http(let status, let code, let message):
            return "The backend answered \(status)\(code.map { " (\($0))" } ?? ""): \(message)"
        case .decoding(let what): return "The backend's answer could not be read: \(what)"
        case .lineage: return "The cloud holds a different game's save."
        case .stale: return "The cloud copy is newer than this phone's."
        }
    }

    /// The error an HTTP answer carries. Supabase's auth speaks
    /// `{"msg":…}` or `{"error_description":…}`, its REST layer
    /// `{"code":"P0001","message":…}`, and the save table's guard raises
    /// `lineage` or `stale` as the message.
    static func from(status: Int, data: Data) -> BackendError {
        var code: String?
        var message = String(data: data, encoding: .utf8) ?? ""
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let c = object["code"] as? String { code = c }
            else if let c = object["error_code"] as? String { code = c }
            if let m = object["message"] as? String { message = m }
            else if let m = object["msg"] as? String { message = m }
            else if let m = object["error_description"] as? String { message = m }
            else if let m = object["error"] as? String { message = m }
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "lineage" { return .lineage }
        if trimmed == "stale" { return .stale }
        return .http(status: status, code: code, message: trimmed)
    }
}

/// A Supabase session: the tokens and who they are for. Kept in
/// `backend_session_<key>.json` beside the saves, one per game account, so
/// a guest's anonymous user and an Apple ID's user are never confused.
struct BackendSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userID: String
    /// "anonymous" or "apple".
    var provider: String
    var expiresAt: Date

    /// A minute of margin: refreshed before a request would be refused.
    var isExpiringSoon: Bool { expiresAt.timeIntervalSinceNow < 60 }

    /// The session an auth answer carries: `access_token`, `refresh_token`,
    /// `expires_in` (seconds) and `user.id`.
    static func from(authResponse data: Data, provider: String, now: Date = Date()) throws -> BackendSession {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String,
              let refresh = object["refresh_token"] as? String,
              let user = object["user"] as? [String: Any],
              let id = user["id"] as? String else {
            throw BackendError.decoding("an auth answer without a session")
        }
        let expiresIn = (object["expires_in"] as? Double) ?? 3600
        return BackendSession(accessToken: access, refreshToken: refresh, userID: id,
                              provider: provider, expiresAt: now.addingTimeInterval(expiresIn))
    }
}

/// Supabase over URLSession (2026-09-22; `Docs/BACKEND.md`): the auth
/// endpoints (an anonymous user for a guest, Sign in with Apple's identity
/// token for an Apple ID), the REST rows behind row-level security, and the
/// functions. No SDK: the project has no package dependencies, the checker
/// reads plain Swift, and the handful of requests the game makes are simple.
/// Every request carries the anon key; a signed-in one carries the session's
/// bearer token, refreshed a minute before it expires and once more on a 401.
@MainActor
final class SupabaseClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    let config: BackendConfig
    /// The game account's storage key: names the session file.
    let storageKey: String
    private(set) var session: BackendSession?
    private let transport: Transport
    private let directory: URL?

    static func filename(for key: String) -> String { "backend_session_\(key).json" }

    /// `transport` is the network; a test hands in canned answers.
    init(config: BackendConfig, storageKey: String, directory: URL? = SaveStore.directory, transport: Transport? = nil) {
        self.config = config
        self.storageKey = storageKey
        self.directory = directory
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BackendError.decoding("no HTTP response")
            }
            return (data, http)
        }
        session = SupabaseClient.readSession(from: directory, key: storageKey)
    }

    var userID: String? { session?.userID }
    var isSignedIn: Bool { session != nil }

    // MARK: - Sessions on disk

    private var sessionURL: URL? { directory?.appendingPathComponent(SupabaseClient.filename(for: storageKey)) }

    private static func readSession(from directory: URL?, key: String) -> BackendSession? {
        guard let url = directory?.appendingPathComponent(filename(for: key)),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BackendSession.self, from: data)
    }

    private func write(_ session: BackendSession?) {
        self.session = session
        guard let url = sessionURL else { return }
        guard let session else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Drops the session file: the next `ensureSession` signs in afresh.
    func signOut() { write(nil) }

    // MARK: - Auth

    /// A session of the right kind: the saved one when it is still good, an
    /// Apple sign-in when a fresh identity token is given, an anonymous user
    /// otherwise — so a guest has a cloud copy too. Refreshes a session
    /// about to expire.
    @discardableResult
    func ensureSession(appleIdentityToken: String?) async throws -> BackendSession {
        if let token = appleIdentityToken, session?.provider != "apple" {
            return try await signInWithApple(identityToken: token)
        }
        if let current = session {
            if current.isExpiringSoon {
                return try await refresh()
            }
            return current
        }
        if let token = appleIdentityToken {
            return try await signInWithApple(identityToken: token)
        }
        return try await signInAnonymously()
    }

    func signInAnonymously() async throws -> BackendSession {
        let body = try JSONSerialization.data(withJSONObject: ["data": [String: String]()])
        let (data, _) = try await send(SupabaseClient.request(
            config: config, method: "POST", path: "auth/v1/signup", query: [], body: body, bearer: nil, headers: [:]
        ))
        let fresh = try BackendSession.from(authResponse: data, provider: "anonymous")
        write(fresh)
        return fresh
    }

    /// Apple's identity token exchanged for a Supabase session. The Apple
    /// provider must be enabled on the project with the app's bundle id as
    /// an authorised client id (`Docs/BACKEND.md`); the request carries no
    /// nonce because the sign-in request set none.
    func signInWithApple(identityToken: String) async throws -> BackendSession {
        let body = try JSONSerialization.data(withJSONObject: ["provider": "apple", "id_token": identityToken])
        let (data, _) = try await send(SupabaseClient.request(
            config: config, method: "POST", path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "id_token")], body: body, bearer: nil, headers: [:]
        ))
        let fresh = try BackendSession.from(authResponse: data, provider: "apple")
        write(fresh)
        return fresh
    }

    private func refresh() async throws -> BackendSession {
        guard let current = session else { throw BackendError.notSignedIn }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])
        do {
            let (data, _) = try await send(SupabaseClient.request(
                config: config, method: "POST", path: "auth/v1/token",
                query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body, bearer: nil, headers: [:]
            ))
            let fresh = try BackendSession.from(authResponse: data, provider: current.provider)
            write(fresh)
            return fresh
        } catch let error as BackendError {
            // A refresh token the server no longer knows: the session is
            // gone and a sign-in is needed.
            if case .http(let status, _, _) = error, status == 400 || status == 401 || status == 403 {
                write(nil)
            }
            throw error
        }
    }

    // MARK: - Requests

    /// A REST call on the project's tables, signed in. `path` is the table
    /// (`saves`); `query` the PostgREST filters; `prefer` its `Prefer`
    /// header. Refreshes once on a 401.
    func rest(_ method: String, _ table: String, query: [URLQueryItem] = [], body: Data? = nil,
              prefer: String? = nil, timeout: TimeInterval = 20) async throws -> (Data, HTTPURLResponse) {
        guard var current = session else { throw BackendError.notSignedIn }
        if current.isExpiringSoon { current = try await refresh() }
        var headers: [String: String] = [:]
        if let prefer { headers["Prefer"] = prefer }
        var request = SupabaseClient.request(config: config, method: method, path: "rest/v1/\(table)",
                                             query: query, body: body, bearer: current.accessToken, headers: headers)
        request.timeoutInterval = timeout
        do {
            return try await send(request)
        } catch let error as BackendError {
            guard case .http(let status, _, _) = error, status == 401 else { throw error }
            let refreshed = try await refresh()
            var retry = request
            retry.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            return try await send(retry)
        }
    }

    /// An Edge Function called with a JSON body, signed in.
    func function(_ name: String, body: Data, timeout: TimeInterval = 20) async throws -> Data {
        guard var current = session else { throw BackendError.notSignedIn }
        if current.isExpiringSoon { current = try await refresh() }
        var request = SupabaseClient.request(config: config, method: "POST", path: "functions/v1/\(name)",
                                             query: [], body: body, bearer: current.accessToken, headers: [:])
        request.timeoutInterval = timeout
        let (data, _) = try await send(request)
        return data
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw BackendError.from(status: response.statusCode, data: data)
        }
        return (data, response)
    }

    /// The request every call is built from, static so a test can read it:
    /// the anon key on every call, the bearer token when signed in (the anon
    /// key itself otherwise, which is what the auth endpoints expect), JSON
    /// both ways.
    static func request(config: BackendConfig, method: String, path: String, query: [URLQueryItem],
                        body: Data?, bearer: String?, headers: [String: String]) -> URLRequest {
        var components = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components?.url ?? config.url)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = body
        return request
    }
}
