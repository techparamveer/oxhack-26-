import Foundation

/// Minimal JSON value used to write Gemini response schemas as literals.
indirect enum JSONValue: Codable, Equatable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                         ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
                         ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    case string(String), int(Int), double(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    /// Gemini's `responseSchema` wants OpenAPI type names in upper case ("OBJECT", "STRING").
    /// Prompt files copy the lower-case schemas from GEMINI_PROMPTS.md; this normalises them.
    var geminiSchema: JSONValue {
        switch self {
        case .object(let dict):
            var out: [String: JSONValue] = [:]
            for (k, v) in dict {
                if k == "type", case .string(let t) = v { out[k] = .string(t.uppercased()) }
                else if k == "minItems" || k == "maxItems", case .int(let n) = v { out[k] = .string(String(n)) }
                else { out[k] = v.geminiSchema }
            }
            return .object(out)
        case .array(let items): return .array(items.map(\.geminiSchema))
        default: return self
        }
    }
}

/// One Gemini call: system prompt + filled user template + JSON schema.
struct GeminiPrompt {
    var name: String                 // for logs, e.g. "planner"
    var system: String               // call-specific system prompt (Persona is prepended unless `usePersona` is false)
    var user: String                 // filled user template
    var schema: JSONValue
    var temperature: Double
    var timeout: TimeInterval = 3     // consolidator uses 15
    var usePersona = true
}

enum GeminiSource: String { case live, fallback }

struct GeminiResult<T> {
    var value: T
    var source: GeminiSource
}

/// REST client for `generateContent`. Every call returns a value: live JSON if it arrives in time
/// and decodes, otherwise the caller's hardcoded fallback. The UI never hangs or errors.
/// Order: Supabase `gemini` Edge Function (if configured) → direct key (if present) → fallback,
/// all inside the prompt's single `timeout` budget.
final class GeminiClient: @unchecked Sendable {
    static let shared = GeminiClient(proxy: SupabaseClient.shared)

    /// Rolling Flash alias; override with GEMINI_MODEL in Secrets.xcconfig.
    static let defaultModel = "gemini-flash-latest"

    let apiKey: String
    let model: String
    let proxy: GeminiProxying?
    private let session: URLSession

    init(apiKey: String? = nil, model: String? = nil, session: URLSession = .shared, proxy: GeminiProxying? = nil) {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = apiKey ?? (info["GEMINI_API_KEY"] as? String) ?? ""
        let m = model ?? (info["GEMINI_MODEL"] as? String) ?? ""
        self.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultModel : m
        self.session = session
        self.proxy = proxy
    }

    var hasKey: Bool { !apiKey.isEmpty && !apiKey.hasPrefix("$(") }
    /// A live call can be attempted (Supabase proxy or a direct key); false → fallbacks instantly.
    var isConfigured: Bool { hasKey || proxy != nil }

    func generate<T: Decodable>(_ type: T.Type, _ prompt: GeminiPrompt, fallback: @autoclosure () -> T) async -> GeminiResult<T> {
        guard hasKey || proxy != nil else { return GeminiResult(value: fallback(), source: .fallback) }
        do {
            let value: T = try await withTimeout(prompt.timeout) { try await self.callChain(T.self, prompt) }
            return GeminiResult(value: value, source: .live)
        } catch {
            #if DEBUG
            print("[Gemini] \(prompt.name) fell back: \(error)")
            #endif
            return GeminiResult(value: fallback(), source: .fallback)
        }
    }

    // MARK: - Request

    func requestBody(_ prompt: GeminiPrompt) -> JSONValue {
        let system = prompt.usePersona ? Persona.text + "\n\n" + prompt.system : prompt.system
        return [
            "systemInstruction": ["parts": [["text": .string(system)]]],
            "contents": [["role": "user", "parts": [["text": .string(prompt.user)]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": prompt.schema.geminiSchema,
                "temperature": .double(prompt.temperature)
            ]
        ]
    }

    /// Proxy first (60% of the budget when a direct key can still be tried), then the direct key.
    private func callChain<T: Decodable>(_ type: T.Type, _ prompt: GeminiPrompt) async throws -> T {
        let start = Date()
        if let proxy {
            let budget = hasKey ? prompt.timeout * 0.6 : prompt.timeout
            do {
                return try await withTimeout(budget) {
                    let data = try await proxy.generateContent(model: self.model, body: self.requestBody(prompt), timeout: budget)
                    return try Self.decodeResponse(T.self, from: data)
                }
            } catch {
                #if DEBUG
                print("[Gemini] \(prompt.name) proxy failed: \(error)")
                #endif
                if !hasKey { throw error }
            }
        }
        let remaining = max(0.5, prompt.timeout - Date().timeIntervalSince(start))
        return try await call(T.self, prompt, timeout: remaining)
    }

    private func call<T: Decodable>(_ type: T.Type, _ prompt: GeminiPrompt, timeout: TimeInterval) async throws -> T {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONEncoder().encode(requestBody(prompt))

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GeminiError.http((response as? HTTPURLResponse)?.statusCode ?? -1,
                                   String(decoding: data.prefix(500), as: UTF8.self))
        }
        return try Self.decodeResponse(T.self, from: data)
    }

    /// Pulls `candidates[0].content.parts[0].text` and decodes it as `T`.
    static func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let env = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard let text = env.candidates?.first?.content?.parts?.compactMap(\.text).joined(), !text.isEmpty else {
            throw GeminiError.emptyResponse
        }
        return try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    /// Hard deadline (see `withDeadline`): returns on time even if `op` ignores cancellation.
    private func withTimeout<R>(_ seconds: TimeInterval, _ op: @escaping @Sendable () async throws -> R) async throws -> R {
        try await withDeadline(seconds, onTimeout: GeminiError.timeout, op)
    }
}

private struct GeminiEnvelope: Decodable {
    struct Candidate: Decodable { var content: Content? }
    struct Content: Decodable { var parts: [Part]? }
    struct Part: Decodable { var text: String? }
    var candidates: [Candidate]?
}

enum GeminiError: Error {
    case timeout, emptyResponse, http(Int, String)
}
