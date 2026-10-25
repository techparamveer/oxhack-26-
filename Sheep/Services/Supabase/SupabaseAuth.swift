import Foundation

/// A Supabase Auth session for the device's anonymous user.
struct SupabaseSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String

    func isValid(at now: Date, leeway: TimeInterval = 60) -> Bool {
        !accessToken.isEmpty && expiresAt.timeIntervalSince(now) > leeway
    }
}

/// URLSession wrapper shared by auth, REST and functions. Remembers connectivity failures for a few
/// seconds so that, offline, every later call fails instantly instead of waiting on the radio.
final class SupabaseTransport: @unchecked Sendable {
    let session: URLSession
    let now: @Sendable () -> Date
    static let offlineCooldown: TimeInterval = 15

    private let lock = NSLock()
    private var offlineUntil: Date?

    init(session: URLSession, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 20
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }

    var isOffline: Bool {
        lock.lock(); defer { lock.unlock() }
        if let until = offlineUntil, until > now() { return true }
        return false
    }

    func resetOffline() {
        lock.lock(); offlineUntil = nil; lock.unlock()
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if isOffline { throw SupabaseError.offline }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SupabaseError.badResponse }
            return (data, http)
        } catch let error as URLError where Self.isConnectivity(error) {
            lock.lock(); offlineUntil = now().addingTimeInterval(Self.offlineCooldown); lock.unlock()
            throw error
        }
    }

    static func isConnectivity(_ e: URLError) -> Bool {
        [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
         .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed]
            .contains(e.code)
    }
}

/// Anonymous sign-in (`POST /auth/v1/signup`) + refresh (`POST /auth/v1/token?grant_type=refresh_token`).
/// Session persisted in UserDefaults (Keychain sharing is an entitlement; plain defaults are fine here).
actor SupabaseAuth {
    static let signUpCooldown: TimeInterval = 60

    let config: SupabaseConfig
    private let transport: SupabaseTransport
    private let defaults: UserDefaults
    private(set) var session: SupabaseSession?
    private var inflight: Task<SupabaseSession, Error>?
    private var signUpBlockedUntil: Date?

    var storageKey: String { "sheep.supabase.session." + (config.baseURL.host ?? "default") }

    init(config: SupabaseConfig, transport: SupabaseTransport, defaults: UserDefaults = .standard) {
        self.config = config
        self.transport = transport
        self.defaults = defaults
        let key = "sheep.supabase.session." + (config.baseURL.host ?? "default")
        if let data = defaults.data(forKey: key) {
            self.session = try? JSONDecoder().decode(SupabaseSession.self, from: data)
        }
    }

    var userId: String? { session?.userId }

    /// A valid access token, refreshing or signing up if needed. Concurrent callers share one request.
    func accessToken() async throws -> String {
        if let s = session, s.isValid(at: transport.now()) { return s.accessToken }
        if let inflight { return try await inflight.value.accessToken }
        let task = Task { try await self.renew() }
        inflight = task
        defer { inflight = nil }
        let s = try await task.value
        return s.accessToken
    }

    /// Forces the next `accessToken()` to refresh (e.g. after a 401).
    func invalidateAccessToken() {
        guard var s = session else { return }
        s.expiresAt = .distantPast
        session = s
    }

    func signOut() {
        session = nil
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: - Private

    private func renew() async throws -> SupabaseSession {
        if let s = session, !s.refreshToken.isEmpty {
            do {
                return try await exchange(SupabaseRequests.refresh(config, refreshToken: s.refreshToken))
            } catch SupabaseError.http(let status, _) where (400..<500).contains(status) && status != 429 {
                // Refresh token revoked / user deleted → start over with a fresh anonymous user.
                signOut()
            }
        }
        if let until = signUpBlockedUntil, until > transport.now() { throw SupabaseError.authUnavailable }
        do {
            return try await exchange(SupabaseRequests.signUpAnonymously(config))
        } catch let SupabaseError.http(status, body) {
            signUpBlockedUntil = transport.now().addingTimeInterval(Self.signUpCooldown)
            throw SupabaseError.http(status, body)
        }
    }

    private func exchange(_ request: URLRequest) async throws -> SupabaseSession {
        let (data, http) = try await transport.perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.http(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let s = try Self.parseSession(data, now: transport.now())
        session = s
        signUpBlockedUntil = nil
        if let encoded = try? JSONEncoder().encode(s) { defaults.set(encoded, forKey: storageKey) }
        return s
    }

    static func parseSession(_ data: Data, now: Date) throws -> SupabaseSession {
        struct Response: Decodable {
            struct User: Decodable { var id: String }
            var access_token: String
            var refresh_token: String
            var expires_in: Double?
            var expires_at: Double?
            var user: User?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let expires = r.expires_at.map { Date(timeIntervalSince1970: $0) }
            ?? now.addingTimeInterval(r.expires_in ?? 3600)
        return SupabaseSession(accessToken: r.access_token, refreshToken: r.refresh_token,
                               expiresAt: expires, userId: r.user?.id ?? "")
    }
}
