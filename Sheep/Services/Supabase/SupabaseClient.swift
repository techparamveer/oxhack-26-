import Foundation

/// Tiny Supabase client on URLSession (no supabase-swift — no third-party packages).
/// Auth (anonymous), PostgREST upsert/delete, Edge Function invoke. Never used on the UI's critical
/// path except the Gemini proxy, which is always bounded by the prompt's timeout.
final class SupabaseClient: @unchecked Sendable {
    /// nil when SUPABASE_HOST / SUPABASE_ANON_KEY aren't configured, and always nil under XCTest.
    /// Also nil with the DEBUG `-sheepOffline` launch argument.
    static let shared: SupabaseClient? = {
        guard !RuntimeEnvironment.isRunningTests, !DebugLaunch.isOffline, let config = SupabaseConfig.fromBundle() else { return nil }
        return SupabaseClient(config: config)
    }()

    let config: SupabaseConfig
    let transport: SupabaseTransport
    let auth: SupabaseAuth

    init(config: SupabaseConfig, session: URLSession = SupabaseTransport.makeSession(),
         defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.transport = SupabaseTransport(session: session, now: now)
        self.auth = SupabaseAuth(config: config, transport: transport, defaults: defaults)
    }

    // MARK: - REST

    func upsert(table: String, rows: [JSONValue], onConflict: String, ignoreDuplicates: Bool = false) async throws {
        _ = try await authorized(expectOK: true) { token in
            SupabaseRequests.upsert(self.config, token: token, table: table, rows: rows,
                                    onConflict: onConflict, ignoreDuplicates: ignoreDuplicates)
        }
    }

    func delete(table: String, filters: [String: String]) async throws {
        _ = try await authorized(expectOK: true) { token in
            SupabaseRequests.delete(self.config, token: token, table: table, filters: filters)
        }
    }

    // MARK: - Functions

    /// Returns the raw response; the caller decides what a non-2xx means.
    func invoke(function: String, body: JSONValue, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        try await authorized(expectOK: false) { token in
            SupabaseRequests.invoke(self.config, token: token, function: function, body: body, timeout: timeout)
        }
    }

    // MARK: - Private

    /// Adds the user's JWT; on 401 refreshes once and retries.
    private func authorized(expectOK: Bool, _ make: @escaping (String) -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        var token = try await auth.accessToken()
        var (data, http) = try await transport.perform(make(token))
        if http.statusCode == 401 {
            await auth.invalidateAccessToken()
            token = try await auth.accessToken()
            (data, http) = try await transport.perform(make(token))
        }
        if expectOK && !(200..<300).contains(http.statusCode) {
            throw SupabaseError.http(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return (data, http)
    }
}

// MARK: - Gemini proxy

/// Something that can run a Gemini `generateContent` call for us (the Supabase `gemini` Edge Function).
protocol GeminiProxying: Sendable {
    /// Returns Gemini's response JSON; throws on any non-2xx or transport error.
    func generateContent(model: String, body: JSONValue, timeout: TimeInterval) async throws -> Data
}

extension SupabaseClient: GeminiProxying {
    func generateContent(model: String, body: JSONValue, timeout: TimeInterval) async throws -> Data {
        guard case .object(var payload) = body else { throw SupabaseError.badResponse }
        payload["model"] = .string(model)
        let (data, http) = try await invoke(function: "gemini", body: .object(payload), timeout: timeout)
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
        return data
    }
}
