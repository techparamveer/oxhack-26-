import Foundation
import UIKit

/// Row encoders for the Supabase tables (see supabase/migrations). Every row always carries the same
/// keys (null when absent) so rows for one table can be bulk-upserted together.
enum SupabaseRows {
    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    static func day(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `events`: ts + type as columns, every other field of the JSONL line in `payload`.
    static func event(_ e: SheepEvent, clientId: UUID) -> JSONValue {
        var payload: [String: JSONValue] = [:]
        if let data = try? SheepEvent.encoder.encode(e),
           case .object(let all)? = try? JSONDecoder().decode(JSONValue.self, from: data) {
            payload = all
            payload["ts"] = nil
            payload["type"] = nil
        }
        return [
            "client_id": .string(clientId.uuidString.lowercased()),
            "ts": .string(iso(e.ts)),
            "type": .string(e.type.rawValue),
            "payload": .object(payload),
        ]
    }

    /// `sessions`: built from a `session_end` and (if we saw it) its `session_start`.
    static func session(end: SheepEvent, start: SheepEvent?, clientId: UUID) -> JSONValue {
        let mode = end.mode ?? start?.mode ?? .idle
        let actual = end.actualMin
        let startedAt = start?.ts ?? actual.map { end.ts.addingTimeInterval(-$0 * 60) }
        return [
            "client_id": .string(clientId.uuidString.lowercased()),
            "mode": .string(mode.rawValue),
            "title": opt(end.title ?? start?.title),
            "planned_min": opt(end.plannedMin ?? start?.plannedMin),
            "actual_min": actual.map { .double($0) } ?? .null,
            "done": opt(end.done),
            "total": opt(end.total),
            "xp": opt(end.xp),
            "started_at": startedAt.map { .string(iso($0)) } ?? .null,
            "ended_at": .string(iso(end.ts)),
        ]
    }

    static func memoryFile(path: String, content: String, updatedAt: Date) -> JSONValue {
        ["path": .string(path), "content": .string(content), "updated_at": .string(iso(updatedAt))]
    }

    static func dailyScore(date: Date, score: Int, focus: Int, rest: Int, play: Int, updatedAt: Date,
                           calendar: Calendar = .current) -> JSONValue {
        [
            "date": .string(day(date, calendar: calendar)),
            "score": .int(score), "focus": .int(focus), "rest": .int(rest), "play": .int(play),
            "updated_at": .string(iso(updatedAt)),
        ]
    }

    private static func opt(_ s: String?) -> JSONValue { s.map { .string($0) } ?? .null }
    private static func opt(_ i: Int?) -> JSONValue { i.map { .int($0) } ?? .null }
}

/// Fire-and-forget background sync of events / memory files / sessions / daily scores to Supabase.
/// On-device data stays the source of truth. Every entry point returns immediately; nothing here can
/// block or fail the UI. Disabled (all no-ops) when Supabase isn't configured and under XCTest.
final class SupabaseSync: @unchecked Sendable {
    static let shared = SupabaseSync()

    private let lock = NSLock()
    private var sender: SyncSending?
    private var queue: SyncQueue?
    private var defaults: UserDefaults = .standard
    private var now: @Sendable () -> Date = { Date() }
    private var retryTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    static let openSessionKey = "sheep.supabase.openSession"
    static var queueURL: URL { AppPaths.root.appendingPathComponent("sync/supabase-queue.json") }

    var isEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return queue != nil
    }

    /// Call once at launch. Signs in (anonymously) and flushes in the background.
    func start(client: SupabaseClient? = SupabaseClient.shared) {
        guard !RuntimeEnvironment.isRunningTests, let client else { return }
        configure(sender: client, queue: SyncQueue(fileURL: Self.queueURL))
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            client.transport.resetOffline()
            self?.flushSoon()
        }
        Task.detached(priority: .utility) { [weak self] in
            _ = try? await client.auth.accessToken()   // warm the session for the Gemini proxy
            self?.flushSoon()
        }
    }

    /// Test seam / manual wiring.
    func configure(sender: SyncSending?, queue: SyncQueue?, defaults: UserDefaults = .standard,
                   now: @escaping @Sendable () -> Date = { Date() }) {
        lock.lock()
        self.sender = sender
        self.queue = queue
        self.defaults = defaults
        self.now = now
        lock.unlock()
    }

    // MARK: - Hooks (called from EventLog / MemoryStore / scoring)

    func record(_ event: SheepEvent) {
        guard let queue = currentQueue() else { return }
        let id = UUID()
        queue.enqueue(.upsert("events", row: SupabaseRows.event(event, clientId: id),
                              onConflict: "user_id,client_id", key: id.uuidString, ignoreDuplicates: true))
        switch event.type {
        case .sessionStart:
            saveOpenSession(OpenSession(clientId: UUID(), start: event))
        case .sessionEnd:
            let open = takeOpenSession()
            let sid = open?.clientId ?? UUID()
            queue.enqueue(.upsert("sessions", row: SupabaseRows.session(end: event, start: open?.start, clientId: sid),
                                  onConflict: "user_id,client_id", key: sid.uuidString))
        default:
            break
        }
        flushSoon()
    }

    func memoryWritten(path: String, content: String) {
        guard !path.hasPrefix("history/"), let queue = currentQueue() else { return }
        queue.enqueue(.upsert("memory_files", row: SupabaseRows.memoryFile(path: path, content: content, updatedAt: currentNow()),
                              onConflict: "user_id,path", key: path))
        flushSoon()
    }

    func memoryDeleted(path: String) {
        guard !path.hasPrefix("history/"), let queue = currentQueue() else { return }
        queue.enqueue(.delete("memory_files", filters: ["path": path], key: path))
        flushSoon()
    }

    /// Seam for the Home score: call whenever today's score changes (upserts one row per day).
    func recordDailyScore(date: Date = .now, score: Int, focus: Int, rest: Int, play: Int) {
        guard let queue = currentQueue() else { return }
        let row = SupabaseRows.dailyScore(date: date, score: score, focus: focus, rest: rest, play: play,
                                          updatedAt: currentNow())
        queue.enqueue(.upsert("daily_scores", row: row, onConflict: "user_id,date", key: SupabaseRows.day(date)))
        flushSoon()
    }

    // MARK: - Flushing

    func flushSoon() {
        guard currentQueue() != nil else { return }
        Task.detached(priority: .utility) { [weak self] in await self?.flush() }
    }

    @discardableResult
    func flush() async -> SyncQueue.FlushResult? {
        lock.lock(); let queue = self.queue, sender = self.sender; lock.unlock()
        guard let queue, let sender else { return nil }
        let result = await queue.flush(using: sender)
        if let next = result.nextAttemptAt { scheduleRetry(at: next) }
        return result
    }

    private func scheduleRetry(at date: Date) {
        let delay = max(1, date.timeIntervalSince(currentNow()))
        lock.lock()
        retryTask?.cancel()
        retryTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
        lock.unlock()
    }

    // MARK: - Session pairing

    struct OpenSession: Codable { var clientId: UUID; var start: SheepEvent }

    private func saveOpenSession(_ s: OpenSession) {
        let d = currentDefaults()
        if let data = try? JSONEncoder().encode(s) { d.set(data, forKey: Self.openSessionKey) }
    }

    private func takeOpenSession() -> OpenSession? {
        let d = currentDefaults()
        defer { d.removeObject(forKey: Self.openSessionKey) }
        guard let data = d.data(forKey: Self.openSessionKey) else { return nil }
        return try? JSONDecoder().decode(OpenSession.self, from: data)
    }

    private func currentQueue() -> SyncQueue? { lock.lock(); defer { lock.unlock() }; return queue }
    private func currentDefaults() -> UserDefaults { lock.lock(); defer { lock.unlock() }; return defaults }
    private func currentNow() -> Date { lock.lock(); let n = now; lock.unlock(); return n() }
}
