import Foundation

/// Pure request builders for Auth, PostgREST and Edge Functions (unit-tested; no I/O).
enum SupabaseRequests {
    static func signUpAnonymously(_ c: SupabaseConfig) -> URLRequest {
        var r = base(c, "POST", c.url("/auth/v1/signup"))
        r.httpBody = Data("{}".utf8)
        return r
    }

    static func refresh(_ c: SupabaseConfig, refreshToken: String) -> URLRequest {
        var r = base(c, "POST", c.url("/auth/v1/token", query: [("grant_type", "refresh_token")]))
        r.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])
        return r
    }

    /// Bulk upsert. `ignoreDuplicates` → `ON CONFLICT DO NOTHING` (append-only tables),
    /// otherwise `ON CONFLICT DO UPDATE` with the sent columns.
    static func upsert(_ c: SupabaseConfig, token: String, table: String, rows: [JSONValue],
                       onConflict: String, ignoreDuplicates: Bool = false) -> URLRequest {
        var r = base(c, "POST", c.url("/rest/v1/\(table)", query: [("on_conflict", onConflict)]))
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let resolution = ignoreDuplicates ? "ignore-duplicates" : "merge-duplicates"
        r.setValue("resolution=\(resolution),return=minimal", forHTTPHeaderField: "Prefer")
        r.httpBody = try? JSONEncoder().encode(JSONValue.array(rows))
        return r
    }

    /// `DELETE /rest/v1/<table>?<col>=eq.<value>…` (filters sorted for stable URLs).
    static func delete(_ c: SupabaseConfig, token: String, table: String, filters: [String: String]) -> URLRequest {
        let query = filters.sorted { $0.key < $1.key }.map { ($0.key, "eq." + $0.value) }
        var r = base(c, "DELETE", c.url("/rest/v1/\(table)", query: query))
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        return r
    }

    static func invoke(_ c: SupabaseConfig, token: String, function: String, body: JSONValue,
                       timeout: TimeInterval) -> URLRequest {
        var r = base(c, "POST", c.url("/functions/v1/\(function)"))
        r.timeoutInterval = timeout
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.httpBody = try? JSONEncoder().encode(body)
        return r
    }

    private static func base(_ c: SupabaseConfig, _ method: String, _ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.httpMethod = method
        r.setValue(c.anonKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }
}

enum SupabaseError: Error, Equatable {
    case http(Int, String)
    case offline            // recent connectivity failure; skipping the network for a few seconds
    case authUnavailable    // sign-up failed recently (e.g. anonymous sign-ins disabled)
    case badResponse

    /// Worth retrying later (sync queue). Other 4xx are permanent (bad row, missing table…).
    var isRetryable: Bool {
        switch self {
        case .http(let s, _): return s == 401 || s == 408 || s == 429 || s >= 500
        case .offline, .authUnavailable, .badResponse: return true
        }
    }
}
