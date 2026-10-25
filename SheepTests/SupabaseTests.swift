import XCTest
@testable import Sheep

// MARK: - Mock network

/// Routes every request of a test URLSession to `MockURLProtocol.handler`.
final class MockURLProtocol: URLProtocol {
    enum Reply {
        case json(Int, String, delay: TimeInterval = 0)
        case fail(URLError.Code, delay: TimeInterval = 0)
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Reply)?
    nonisolated(unsafe) private static var _log: [URLRequest] = []
    private static let lock = NSLock()

    static var log: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _log }
    static func reset(_ h: ((URLRequest) -> Reply)? = nil) {
        lock.lock(); _log = []; lock.unlock()
        handler = h
    }

    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private var work: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream { req.httpBody = Self.read(stream) }
        Self.lock.lock(); Self._log.append(req); Self.lock.unlock()
        let reply = Self.handler?(req) ?? .fail(.notConnectedToInternet)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            switch reply {
            case .json(let status, let body, _):
                let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
                self.client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: Data(body.utf8))
                self.client?.urlProtocolDidFinishLoading(self)
            case .fail(let code, _):
                self.client?.urlProtocol(self, didFailWithError: URLError(code))
            }
        }
        work = item
        let delay: TimeInterval
        switch reply { case .json(_, _, let d), .fail(_, let d): delay = d }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
    }

    override func stopLoading() { work?.cancel() }

    static func read(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}

private let testConfig = SupabaseConfig(host: "test-ref.supabase.co", anonKey: "sb_publishable_test")!

private func sessionJSON(_ token: String = "jwt-1", refresh: String = "rt-1", expiresIn: Int = 3600) -> String {
    #"{"access_token":"\#(token)","refresh_token":"\#(refresh)","expires_in":\#(expiresIn),"token_type":"bearer","user":{"id":"user-1","is_anonymous":true}}"#
}

private let geminiOK = #"{"candidates":[{"content":{"parts":[{"text":"{\"headline\":\"live\"}"}]}}]}"#

private func bodyJSON(_ r: URLRequest) -> Any? {
    r.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
}

private func suite() -> UserDefaults {
    UserDefaults(suiteName: "sheep-supabase-tests-\(UUID())")!
}

// MARK: - Config + request building

final class SupabaseRequestTests: XCTestCase {
    func testConfigParsing() {
        XCTAssertEqual(SupabaseConfig(host: "abc.supabase.co", anonKey: "k")?.baseURL.absoluteString, "https://abc.supabase.co")
        XCTAssertEqual(SupabaseConfig(host: "https://abc.supabase.co/", anonKey: "k")?.baseURL.absoluteString, "https://abc.supabase.co")
        XCTAssertEqual(SupabaseConfig(host: "127.0.0.1:54321", anonKey: "k")?.baseURL.absoluteString, "http://127.0.0.1:54321")
        XCTAssertNil(SupabaseConfig(host: "", anonKey: "k"))
        XCTAssertNil(SupabaseConfig(host: "abc.supabase.co", anonKey: " "))
        XCTAssertNil(SupabaseConfig(host: "$(SUPABASE_HOST)", anonKey: "$(SUPABASE_ANON_KEY)"))
    }

    func testSharedClientIsDisabledUnderTests() {
        XCTAssertTrue(RuntimeEnvironment.isRunningTests)
        XCTAssertNil(SupabaseClient.shared)
        XCTAssertNil(GeminiClient.shared.proxy)
    }

    func testAuthRequests() {
        let s = SupabaseRequests.signUpAnonymously(testConfig)
        XCTAssertEqual(s.url?.absoluteString, "https://test-ref.supabase.co/auth/v1/signup")
        XCTAssertEqual(s.httpMethod, "POST")
        XCTAssertEqual(s.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertNil(s.value(forHTTPHeaderField: "Authorization"), "publishable keys must never go in Authorization")
        XCTAssertEqual(String(decoding: s.httpBody ?? Data(), as: UTF8.self), "{}")

        let r = SupabaseRequests.refresh(testConfig, refreshToken: "rt+/=")
        XCTAssertEqual(r.url?.absoluteString, "https://test-ref.supabase.co/auth/v1/token?grant_type=refresh_token")
        XCTAssertEqual((bodyJSON(r) as? [String: String])?["refresh_token"], "rt+/=")
    }

    func testUpsertRequest() {
        let r = SupabaseRequests.upsert(testConfig, token: "jwt", table: "memory_files",
                                        rows: [["path": "a.md", "content": "x"]], onConflict: "user_id,path")
        XCTAssertEqual(r.url?.absoluteString, "https://test-ref.supabase.co/rest/v1/memory_files?on_conflict=user_id%2Cpath")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
        XCTAssertEqual(r.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        XCTAssertEqual((bodyJSON(r) as? [[String: String]])?.first?["path"], "a.md")

        let e = SupabaseRequests.upsert(testConfig, token: "jwt", table: "events", rows: [], onConflict: "user_id,client_id",
                                        ignoreDuplicates: true)
        XCTAssertEqual(e.value(forHTTPHeaderField: "Prefer"), "resolution=ignore-duplicates,return=minimal")
    }

    func testDeleteRequestEncodesFilterValues() {
        let r = SupabaseRequests.delete(testConfig, token: "jwt", table: "memory_files", filters: ["path": "knowledge/a b&c+d.md"])
        XCTAssertEqual(r.httpMethod, "DELETE")
        XCTAssertEqual(r.url?.absoluteString,
                       "https://test-ref.supabase.co/rest/v1/memory_files?path=eq.knowledge/a%20b%26c%2Bd.md")
    }

    func testInvokeRequest() {
        let r = SupabaseRequests.invoke(testConfig, token: "jwt", function: "gemini", body: ["model": "m"], timeout: 2.5)
        XCTAssertEqual(r.url?.absoluteString, "https://test-ref.supabase.co/functions/v1/gemini")
        XCTAssertEqual(r.timeoutInterval, 2.5)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
        XCTAssertEqual((bodyJSON(r) as? [String: String])?["model"], "m")
    }

    func testRows() {
        let start = SheepEvent(ts: Date(timeIntervalSince1970: 1_000), type: .sessionStart, mode: .focus,
                               title: "Ch.3", plannedMin: 75, answers: ["a"])
        let end = SheepEvent(ts: Date(timeIntervalSince1970: 5_500), type: .sessionEnd, mode: .focus,
                             actualMin: 75, done: 1, total: 3, xp: 60)
        let id = UUID()
        guard case .object(let ev) = SupabaseRows.event(start, clientId: id),
              case .object(let payload) = ev["payload"] else { return XCTFail() }
        XCTAssertEqual(ev["type"], "session_start")
        XCTAssertEqual(ev["client_id"], .string(id.uuidString.lowercased()))
        XCTAssertNil(payload["ts"]); XCTAssertNil(payload["type"])
        XCTAssertEqual(payload["title"], "Ch.3")
        XCTAssertEqual(payload["answers"], ["a"])

        guard case .object(let row) = SupabaseRows.session(end: end, start: start, clientId: id) else { return XCTFail() }
        XCTAssertEqual(row["mode"], "focus")
        XCTAssertEqual(row["title"], "Ch.3")
        XCTAssertEqual(row["planned_min"], 75)
        XCTAssertEqual(row["xp"], 60)
        XCTAssertEqual(row["started_at"], .string(SupabaseRows.iso(start.ts)))
        XCTAssertEqual(Set(row.keys), ["client_id", "mode", "title", "planned_min", "actual_min", "done", "total", "xp",
                                       "started_at", "ended_at"])

        // Without a start, started_at is derived from actualMin and keys stay uniform (batchable).
        guard case .object(let lone) = SupabaseRows.session(end: end, start: nil, clientId: id) else { return XCTFail() }
        XCTAssertEqual(lone["started_at"], .string(SupabaseRows.iso(Date(timeIntervalSince1970: 1_000))))
        XCTAssertEqual(lone["title"], .null)
        XCTAssertEqual(Set(lone.keys), Set(row.keys))

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard case .object(let score) = SupabaseRows.dailyScore(date: Date(timeIntervalSince1970: 0), score: 70, focus: 60,
                                                                 rest: 10, play: 0, updatedAt: .now, calendar: cal)
        else { return XCTFail() }
        XCTAssertEqual(score["date"], "1970-01-01")
    }
}

// MARK: - Auth session

final class SupabaseAuthTests: XCTestCase {
    override func tearDown() { MockURLProtocol.reset() }

    func testSignUpPersistsAndReusesSession() async throws {
        MockURLProtocol.reset { _ in .json(200, sessionJSON()) }
        let defaults = suite()
        let client = SupabaseClient(config: testConfig, session: MockURLProtocol.session(), defaults: defaults)
        let t1 = try await client.auth.accessToken()
        let t2 = try await client.auth.accessToken()
        XCTAssertEqual(t1, "jwt-1"); XCTAssertEqual(t2, "jwt-1")
        XCTAssertEqual(MockURLProtocol.log.count, 1)
        XCTAssertEqual(MockURLProtocol.log[0].url?.path, "/auth/v1/signup")

        // A fresh client (app relaunch) restores the session from UserDefaults without the network.
        let relaunch = SupabaseClient(config: testConfig, session: MockURLProtocol.session(), defaults: defaults)
        let t3 = try await relaunch.auth.accessToken()
        XCTAssertEqual(t3, "jwt-1")
        XCTAssertEqual(MockURLProtocol.log.count, 1)
        let uid = await relaunch.auth.userId
        XCTAssertEqual(uid, "user-1")
    }

    func testExpiredSessionRefreshes() async throws {
        MockURLProtocol.reset { r in
            r.url?.path == "/auth/v1/signup" ? .json(200, sessionJSON("jwt-old", expiresIn: 30))
                                              : .json(200, sessionJSON("jwt-new", refresh: "rt-2"))
        }
        let client = SupabaseClient(config: testConfig, session: MockURLProtocol.session(), defaults: suite())
        let t1 = try await client.auth.accessToken()   // expires within the 60 s leeway → next call refreshes
        let t2 = try await client.auth.accessToken()
        XCTAssertEqual(t1, "jwt-old"); XCTAssertEqual(t2, "jwt-new")
        let refresh = MockURLProtocol.log[1]
        XCTAssertEqual(refresh.url?.absoluteString, "https://test-ref.supabase.co/auth/v1/token?grant_type=refresh_token")
        XCTAssertEqual((bodyJSON(refresh) as? [String: String])?["refresh_token"], "rt-1")
    }

    func testRevokedRefreshTokenSignsUpAgain() async throws {
        var signups = 0
        MockURLProtocol.reset { r in
            if r.url?.path == "/auth/v1/token" { return .json(400, #"{"error":"invalid_grant"}"#) }
            signups += 1
            return .json(200, sessionJSON("jwt-\(signups)", expiresIn: 30))
        }
        let client = SupabaseClient(config: testConfig, session: MockURLProtocol.session(), defaults: suite())
        _ = try await client.auth.accessToken()
        let t = try await client.auth.accessToken()
        XCTAssertEqual(t, "jwt-2")
        XCTAssertEqual(MockURLProtocol.log.map { $0.url!.path }, ["/auth/v1/signup", "/auth/v1/token", "/auth/v1/signup"])
    }

    func testConcurrentCallersShareOneSignUp() async throws {
        MockURLProtocol.reset { _ in .json(200, sessionJSON(), delay: 0.1) }
        let client = SupabaseClient(config: testConfig, session: MockURLProtocol.session(), defaults: suite())
        async let a = client.auth.accessToken()
        async let b = client.auth.accessToken()
        async let c = client.auth.accessToken()
        let tokens = try await [a, b, c]
        XCTAssertEqual(tokens, ["jwt-1", "jwt-1", "jwt-1"])
        XCTAssertEqual(MockURLProtocol.log.count, 1)
    }

    func testFailedSignUpCoolsDownWithoutNetwork() async {
        MockURLProtocol.reset { _ in .json(422, #"{"msg":"Anonymous sign-ins are disabled"}"#) }
        let client = SupabaseClient(config: testConfig, session: MockURLProtocol.session(), defaults: suite())
        do { _ = try await client.auth.accessToken(); XCTFail() } catch {}
        do { _ = try await client.auth.accessToken(); XCTFail() } catch {
            XCTAssertEqual(error as? SupabaseError, .authUnavailable)
        }
        XCTAssertEqual(MockURLProtocol.log.count, 1)
    }

    func testUnauthorizedRestCallRefreshesOnceAndRetries() async throws {
        var restCalls = 0
        MockURLProtocol.reset { r in
            switch r.url?.path {
            case "/auth/v1/signup": return .json(200, sessionJSON("jwt-a"))
            case "/auth/v1/token": return .json(200, sessionJSON("jwt-b"))
            default:
                restCalls += 1
                return restCalls == 1 ? .json(401, "{}") : .json(201, "")
            }
        }
        let client = SupabaseClient(config: testConfig, session: MockURLProtocol.session(), defaults: suite())
        try await client.upsert(table: "events", rows: [["a": 1]], onConflict: "user_id,client_id")
        let rest = MockURLProtocol.log.filter { $0.url?.path == "/rest/v1/events" }
        XCTAssertEqual(rest.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer jwt-a", "Bearer jwt-b"])
    }
}

// MARK: - Gemini ordering

final class GeminiProxyOrderingTests: XCTestCase {
    struct Brief: Codable, Equatable { var headline: String }
    let fallback = Brief(headline: "fallback")

    override func tearDown() { MockURLProtocol.reset() }

    private func prompt(timeout: TimeInterval = 3) -> GeminiPrompt {
        var p = GeminiPrompt(name: "t", system: "s", user: "u", schema: ["type": "object"], temperature: 0.5)
        p.timeout = timeout
        return p
    }

    private func client(key: String, proxy: Bool) -> GeminiClient {
        let s = MockURLProtocol.session()
        let supabase = proxy ? SupabaseClient(config: testConfig, session: s, defaults: suite()) : nil
        return GeminiClient(apiKey: key, model: "gemini-flash-latest", session: s, proxy: supabase)
    }

    private func route(proxy: MockURLProtocol.Reply, direct: MockURLProtocol.Reply) {
        MockURLProtocol.reset { r in
            switch r.url?.host {
            case "generativelanguage.googleapis.com": return direct
            default: return r.url?.path == "/auth/v1/signup" ? .json(200, sessionJSON()) : proxy
            }
        }
    }

    private var directCalls: Int { MockURLProtocol.log.filter { $0.url?.host == "generativelanguage.googleapis.com" }.count }
    private var proxyCalls: [URLRequest] { MockURLProtocol.log.filter { $0.url?.path == "/functions/v1/gemini" } }

    func testProxyOKIsUsedAndDirectIsSkipped() async throws {
        route(proxy: .json(200, geminiOK), direct: .json(500, "{}"))
        let r = await client(key: "direct-key", proxy: true).generate(Brief.self, prompt(), fallback: fallback)
        XCTAssertEqual(r.source, .live); XCTAssertEqual(r.value.headline, "live")
        XCTAssertEqual(directCalls, 0)
        let call = try XCTUnwrap(proxyCalls.first)
        XCTAssertEqual(call.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-1")
        let body = try XCTUnwrap(bodyJSON(call) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gemini-flash-latest")
        XCTAssertNotNil(body["systemInstruction"]); XCTAssertNotNil(body["contents"]); XCTAssertNotNil(body["generationConfig"])
        XCTAssertNil(call.value(forHTTPHeaderField: "x-goog-api-key"), "the Gemini key must never be sent to the proxy")
    }

    func testProxy403FallsBackToDirect() async {
        route(proxy: .json(403, #"{"error":{"status":"PERMISSION_DENIED","message":"API_KEY_SERVICE_BLOCKED"}}"#),
              direct: .json(200, geminiOK))
        let r = await client(key: "direct-key", proxy: true).generate(Brief.self, prompt(), fallback: fallback)
        XCTAssertEqual(r.source, .live)
        XCTAssertEqual(proxyCalls.count, 1); XCTAssertEqual(directCalls, 1)
    }

    func testProxyTimeoutFallsBackToDirectWithinBudget() async {
        route(proxy: .json(200, geminiOK, delay: 5), direct: .json(200, geminiOK))
        let t0 = Date()
        let r = await client(key: "direct-key", proxy: true).generate(Brief.self, prompt(timeout: 1), fallback: fallback)
        XCTAssertEqual(r.source, .live)
        XCTAssertEqual(directCalls, 1)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.3)
    }

    func testBothFailReturnsFallback() async {
        route(proxy: .json(403, "{}"), direct: .json(403, "{}"))
        let r = await client(key: "direct-key", proxy: true).generate(Brief.self, prompt(), fallback: fallback)
        XCTAssertEqual(r.source, .fallback); XCTAssertEqual(r.value, fallback)
    }

    func testNoConfigReturnsFallbackInstantly() async {
        route(proxy: .json(200, geminiOK), direct: .json(200, geminiOK))
        let t0 = Date()
        let r = await client(key: "", proxy: false).generate(Brief.self, prompt(), fallback: fallback)
        XCTAssertEqual(r.source, .fallback)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.05)
        XCTAssertTrue(MockURLProtocol.log.isEmpty)
    }

    func testOfflineProxyOnlyFallsBackFastAndThenInstantly() async {
        MockURLProtocol.reset { _ in .fail(.notConnectedToInternet) }
        let c = client(key: "", proxy: true)
        let t0 = Date()
        let r1 = await c.generate(Brief.self, prompt(), fallback: fallback)
        XCTAssertEqual(r1.source, .fallback)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.5)
        let n = MockURLProtocol.log.count
        let t1 = Date()
        let r2 = await c.generate(Brief.self, prompt(), fallback: fallback)
        XCTAssertEqual(r2.source, .fallback)
        XCTAssertLessThan(Date().timeIntervalSince(t1), 0.05)
        XCTAssertEqual(MockURLProtocol.log.count, n, "offline cooldown: no new requests")
    }

    func testEverythingHangingStaysWithinBudget() async {
        MockURLProtocol.reset { _ in .json(200, geminiOK, delay: 10) }
        let t0 = Date()
        let r = await client(key: "direct-key", proxy: true).generate(Brief.self, prompt(timeout: 0.5), fallback: fallback)
        XCTAssertEqual(r.source, .fallback)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.8)
    }
}

// MARK: - Offline queue

private final class FakeSender: SyncSending, @unchecked Sendable {
    private let lock = NSLock()
    private var _batches: [[SyncOp]] = []
    private var _error: Error?
    var batches: [[SyncOp]] { lock.lock(); defer { lock.unlock() }; return _batches }
    var error: Error? {
        get { lock.lock(); defer { lock.unlock() }; return _error }
        set { lock.lock(); _error = newValue; lock.unlock() }
    }
    func send(_ batch: [SyncOp]) async throws {
        lock.lock(); _batches.append(batch); let e = _error; lock.unlock()
        if let e { throw e }
    }
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

final class SyncQueueTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID())", isDirectory: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func event(_ n: Int) -> SyncOp {
        .upsert("events", row: ["n": .int(n)], onConflict: "user_id,client_id", key: "e\(n)", ignoreDuplicates: true)
    }

    func testPersistsAcrossInstances() {
        let url = dir.appendingPathComponent("q.json")
        let q = SyncQueue(fileURL: url)
        q.enqueue(event(1)); q.enqueue(event(2))
        let reloaded = SyncQueue(fileURL: url)
        XCTAssertEqual(reloaded.pending.count, 2)
        XCTAssertEqual(reloaded.pending.map(\.key), ["events:e1", "events:e2"])
    }

    func testCoalescesSameKeyKeepingLatest() {
        let q = SyncQueue(fileURL: dir.appendingPathComponent("q.json"))
        q.enqueue(.upsert("memory_files", row: ["content": "v1"], onConflict: "user_id,path", key: "a.md"))
        q.enqueue(event(1))
        q.enqueue(.upsert("memory_files", row: ["content": "v2"], onConflict: "user_id,path", key: "a.md"))
        q.enqueue(.delete("memory_files", filters: ["path": "b.md"], key: "b.md"))
        XCTAssertEqual(q.pending.count, 3)
        XCTAssertEqual(q.pending[1].row, ["content": "v2"])
        q.enqueue(.delete("memory_files", filters: ["path": "a.md"], key: "a.md"))   // delete supersedes the write
        XCTAssertEqual(q.pending.filter { $0.key == "memory_files:a.md" }.map(\.kind), [.delete])
    }

    func testFlushBatchesByTableAndEmptiesQueue() async {
        let url = dir.appendingPathComponent("q.json")
        let q = SyncQueue(fileURL: url)
        for i in 0..<3 { q.enqueue(event(i)) }
        q.enqueue(.upsert("sessions", row: ["x": 1], onConflict: "user_id,client_id", key: "s1"))
        q.enqueue(.delete("memory_files", filters: ["path": "a.md"], key: "a.md"))
        let sender = FakeSender()
        let result = await q.flush(using: sender)
        XCTAssertEqual(result.sent, 5)
        XCTAssertNil(result.nextAttemptAt)
        XCTAssertEqual(sender.batches.map(\.count), [3, 1, 1])
        XCTAssertEqual(sender.batches[0].map(\.table), ["events", "events", "events"])
        XCTAssertTrue(q.pending.isEmpty)
        XCTAssertTrue(SyncQueue(fileURL: url).pending.isEmpty, "emptied queue is persisted")
    }

    func testRetryableFailureBacksOffAndRetriesLater() async {
        let clock = Clock()
        let q = SyncQueue(fileURL: dir.appendingPathComponent("q.json"), now: { clock.now })
        q.enqueue(event(1))
        let sender = FakeSender()
        sender.error = SupabaseError.http(503, "down")

        var r = await q.flush(using: sender)
        XCTAssertEqual(r.failed, 1)
        XCTAssertEqual(q.pending.first?.attempts, 1)
        XCTAssertEqual(r.nextAttemptAt, clock.now.addingTimeInterval(2))

        r = await q.flush(using: sender)              // not due yet → nothing sent
        XCTAssertEqual(sender.batches.count, 1)

        clock.now.addTimeInterval(2)
        r = await q.flush(using: sender)
        XCTAssertEqual(q.pending.first?.attempts, 2)
        XCTAssertEqual(r.nextAttemptAt, clock.now.addingTimeInterval(4))

        clock.now.addTimeInterval(4)
        sender.error = nil
        r = await q.flush(using: sender)
        XCTAssertEqual(r.sent, 1)
        XCTAssertTrue(q.pending.isEmpty)
        // Same op (same client_id row) was resent each time → server-side idempotent upsert.
        XCTAssertEqual(Set(sender.batches.map { $0[0].id }).count, 1)
    }

    func testBackoffSchedule() {
        XCTAssertEqual(SyncQueue.backoff(attempts: 1), 2)
        XCTAssertEqual(SyncQueue.backoff(attempts: 2), 4)
        XCTAssertEqual(SyncQueue.backoff(attempts: 5), 32)
        XCTAssertEqual(SyncQueue.backoff(attempts: 20), 600)
    }

    func testPermanentFailureIsDropped() async {
        let q = SyncQueue(fileURL: dir.appendingPathComponent("q.json"))
        q.enqueue(event(1))
        q.enqueue(.upsert("sessions", row: ["x": 1], onConflict: "user_id,client_id", key: "s1"))
        let sender = FakeSender()
        sender.error = SupabaseError.http(400, "bad column")
        let r = await q.flush(using: sender)
        XCTAssertEqual(r.dropped, 2)
        XCTAssertTrue(q.pending.isEmpty)
    }

    func testTransportErrorStopsFlushEarly() async {
        let q = SyncQueue(fileURL: dir.appendingPathComponent("q.json"))
        q.enqueue(event(1))
        q.enqueue(.upsert("sessions", row: ["x": 1], onConflict: "user_id,client_id", key: "s1"))
        let sender = FakeSender()
        sender.error = URLError(.notConnectedToInternet)
        let r = await q.flush(using: sender)
        XCTAssertEqual(sender.batches.count, 1, "offline: don't try every other batch")
        XCTAssertEqual(r.failed, 1)
        XCTAssertEqual(q.pending.count, 2)
    }

    func testLongOfflineStretchNeverDropsOps() async {
        let clock = Clock()
        let q = SyncQueue(fileURL: dir.appendingPathComponent("q.json"), now: { clock.now })
        q.enqueue(event(1))
        let sender = FakeSender()
        sender.error = SupabaseError.offline
        for _ in 0..<(SyncQueue.maxAttempts + 3) {
            let r = await q.flush(using: sender)
            XCTAssertEqual(r.dropped, 0)
            clock.now.addTimeInterval(601)
        }
        XCTAssertEqual(q.pending.count, 1, "connectivity failures back off but never drop")
        XCTAssertGreaterThan(q.pending[0].attempts, SyncQueue.maxAttempts)
        sender.error = SupabaseError.http(503, "down")   // server errors still give up eventually
        _ = await q.flush(using: sender)
        XCTAssertTrue(q.pending.isEmpty)
    }

    func testFlushEndToEndThroughSupabaseClient() async throws {
        MockURLProtocol.reset { r in r.url?.path == "/auth/v1/signup" ? .json(200, sessionJSON()) : .json(201, "") }
        defer { MockURLProtocol.reset() }
        let client = SupabaseClient(config: testConfig, session: MockURLProtocol.session(), defaults: suite())
        let q = SyncQueue(fileURL: dir.appendingPathComponent("q.json"))
        q.enqueue(event(1)); q.enqueue(event(2))
        q.enqueue(.delete("memory_files", filters: ["path": "a.md"], key: "a.md"))
        let r = await q.flush(using: client)
        XCTAssertEqual(r.sent, 3)
        let rest = MockURLProtocol.log.filter { $0.url?.path.hasPrefix("/rest/") == true }
        XCTAssertEqual(rest.count, 2)
        XCTAssertEqual(rest[0].url?.absoluteString, "https://test-ref.supabase.co/rest/v1/events?on_conflict=user_id%2Cclient_id")
        XCTAssertEqual(rest[0].value(forHTTPHeaderField: "Prefer"), "resolution=ignore-duplicates,return=minimal")
        XCTAssertEqual((bodyJSON(rest[0]) as? [[String: Int]])?.map { $0["n"] }, [1, 2])
        XCTAssertEqual(rest[1].httpMethod, "DELETE")
        XCTAssertEqual(rest[1].url?.query, "path=eq.a.md")
    }
}

// MARK: - Sync hooks

final class SupabaseSyncTests: XCTestCase {
    private var dir: URL!
    private var sync: SupabaseSync!
    private var queue: SyncQueue!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID())", isDirectory: true)
        queue = SyncQueue(fileURL: dir.appendingPathComponent("q.json"))
        sync = SupabaseSync()
        // Sender that never succeeds so ops stay visible in the queue for assertions.
        let sender = FakeSender(); sender.error = SupabaseError.offline
        sync.configure(sender: sender, queue: queue, defaults: suite())
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testDisabledByDefault() {
        let fresh = SupabaseSync()
        XCTAssertFalse(fresh.isEnabled)
        fresh.record(SheepEvent(type: .scroll))   // no crash, no queue
        SupabaseSync.shared.start()               // no-op under XCTest
        XCTAssertFalse(SupabaseSync.shared.isEnabled)
    }

    func testSessionStartAndEndArePaired() {
        let start = SheepEvent(ts: Date(timeIntervalSince1970: 100), type: .sessionStart, mode: .focus, title: "Essay", plannedMin: 25)
        let end = SheepEvent(ts: Date(timeIntervalSince1970: 1600), type: .sessionEnd, mode: .focus, actualMin: 25, done: 2, total: 3, xp: 40)
        sync.record(start)
        sync.record(end)
        sync.waitForPendingWork()
        let ops = queue.pending
        XCTAssertEqual(ops.map(\.table), ["events", "events", "sessions"])
        XCTAssertTrue(ops[0].ignoreDuplicates)
        XCTAssertEqual(ops[0].onConflict, "user_id,client_id")
        guard case .object(let row)? = ops[2].row else { return XCTFail() }
        XCTAssertEqual(row["title"], "Essay")
        XCTAssertEqual(row["planned_min"], 25)
        XCTAssertEqual(row["xp"], 40)
        XCTAssertEqual(row["started_at"], .string(SupabaseRows.iso(start.ts)))
        XCTAssertFalse(ops[2].ignoreDuplicates)
    }

    func testMemoryHooksSkipHistoryAndCoalesce() {
        sync.memoryWritten(path: "knowledge/patterns.md", content: "v1")
        sync.memoryWritten(path: "history/2026/x.md", content: "old")
        sync.memoryWritten(path: "knowledge/patterns.md", content: "v2")
        sync.memoryDeleted(path: "people/sam.md")
        sync.waitForPendingWork()
        let ops = queue.pending
        XCTAssertEqual(ops.count, 2)
        guard case .object(let row)? = ops[0].row else { return XCTFail() }
        XCTAssertEqual(row["content"], "v2")
        XCTAssertEqual(ops[0].onConflict, "user_id,path")
        XCTAssertEqual(ops[1].kind, .delete)
        XCTAssertEqual(ops[1].filters, ["path": "people/sam.md"])
    }

    func testDailyScoreUpsertsOneRowPerDay() {
        sync.recordDailyScore(score: 50, focus: 40, rest: 10, play: 0)
        sync.recordDailyScore(score: 70, focus: 60, rest: 10, play: 0)
        sync.waitForPendingWork()
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending[0].onConflict, "user_id,date")
        guard case .object(let row)? = queue.pending[0].row else { return XCTFail() }
        XCTAssertEqual(row["score"], 70)
    }
}
