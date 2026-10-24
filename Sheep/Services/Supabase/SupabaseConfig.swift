import Foundation

/// Project URL + publishable (anon) key from Info.plist (`SUPABASE_HOST`, `SUPABASE_ANON_KEY`, fed by
/// Secrets.xcconfig). xcconfig treats `//` as a comment, so we store the bare host and add the scheme here.
struct SupabaseConfig: Equatable, Sendable {
    var baseURL: URL
    var anonKey: String

    init?(host: String?, anonKey: String?) {
        let h = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let k = (anonKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !k.isEmpty, !h.hasPrefix("$("), !k.hasPrefix("$(") else { return nil }
        let urlString: String
        if h.hasPrefix("http://") || h.hasPrefix("https://") {
            urlString = h
        } else if h.hasPrefix("localhost") || h.hasPrefix("127.0.0.1") {
            urlString = "http://" + h          // `supabase start` on the Mac
        } else {
            urlString = "https://" + h
        }
        guard let url = URL(string: urlString.hasSuffix("/") ? String(urlString.dropLast()) : urlString),
              url.host != nil else { return nil }
        self.baseURL = url
        self.anonKey = k
    }

    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfig? {
        let info = bundle.infoDictionary ?? [:]
        return SupabaseConfig(host: info["SUPABASE_HOST"] as? String, anonKey: info["SUPABASE_ANON_KEY"] as? String)
    }

    /// `baseURL + path` with an already-encoded query string.
    func url(_ path: String, query: [(String, String)] = []) -> URL {
        var s = baseURL.absoluteString + path
        if !query.isEmpty {
            s += "?" + query.map { "\(Self.encode($0.0))=\(Self.encode($0.1))" }.joined(separator: "&")
        }
        return URL(string: s)!
    }

    /// Strict query-component encoding (so `+`, `&`, `=`, `,` in values can't change meaning).
    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

enum RuntimeEnvironment {
    /// True inside XCTest (the test host launches the app; it must never touch the real backend).
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
