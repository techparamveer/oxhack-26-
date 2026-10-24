import Foundation

/// One line of `events.jsonl`. Format from GEMINI_PROMPTS "Event log format".
/// Only app, section/path, timings and the user's own typed answers — never DM/post content.
struct SheepEvent: Codable, Equatable {
    enum Kind: String, Codable {
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
        case checklistDone = "checklist_done"
        case scroll
        case nudge
        case blocked
        case wrapperOpen = "wrapper_open"
        case modeChange = "mode_change"
        case restActivity = "rest_activity"
        case playSession = "play_session"
    }

    var ts: Date = .now
    var type: Kind
    var mode: Mode?
    var app: WrappedApp?
    var section: AppSection?
    var title: String?
    var workstream: String?
    var plannedMin: Int?
    var actualMin: Double?
    var answers: [String]?
    var item: String?
    var activeMin: Double?
    var tone: String?
    var action: String?
    var outcome: String?          // nudges: "returned" | "ignored"
    var done: Int?
    var total: Int?
    var xp: Int?
    var activity: String?
    var limitMin: Int?

    /// Compact single-line JSON (nil fields omitted, ISO-8601 timestamps).
    func jsonLine() -> String {
        let data = (try? SheepEvent.encoder.encode(self)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Append-only JSONL log at `Documents/memory/events.jsonl`. Thread-safe.
final class EventLog: @unchecked Sendable {
    static let shared = EventLog()

    private let lock = NSLock()
    private let fileURL: () -> URL

    init(fileURL: @escaping () -> URL = { AppPaths.events }) {
        self.fileURL = fileURL
    }

    func append(_ event: SheepEvent) {
        lock.lock(); defer { lock.unlock() }
        let url = fileURL()
        AppPaths.ensure(url.deletingLastPathComponent())
        let line = Data((event.jsonLine() + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
        SupabaseSync.shared.record(event)   // background mirror; no-op unless Supabase is configured
    }

    func readAll() -> [SheepEvent] {
        lock.lock(); defer { lock.unlock() }
        guard let text = try? String(contentsOf: fileURL(), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            try? SheepEvent.decoder.decode(SheepEvent.self, from: Data($0.utf8))
        }
    }

    func events(since date: Date?) -> [SheepEvent] {
        guard let date else { return readAll() }
        return readAll().filter { $0.ts > date }
    }

    /// Raw JSONL for prompts.
    func jsonl(since date: Date?) -> String {
        events(since: date).map { $0.jsonLine() }.joined(separator: "\n")
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL())
    }
}
