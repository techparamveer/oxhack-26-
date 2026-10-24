import Foundation

/// Write path for memory (GEMINI_PROMPTS §6). Runs at session end and on daily rollover.
/// Input: all current memory files + events since `lastRunAt`. Output applied via `MemoryStore`
/// (which snapshots to `history/` first). Falls back to `OfflineConsolidator` when Gemini is unavailable.
/// Concurrent runs are serialised.
final class MemoryConsolidator: @unchecked Sendable {
    static let shared = MemoryConsolidator()

    enum Reason: String { case sessionEnd = "session_end", dailyRollover = "daily_rollover" }

    static let lastRunKey = "sheep.memory.consolidator.lastRunAt"
    static let learnedKey = "sheep.memory.consolidator.learned"

    let store: MemoryStore
    let log: EventLog
    let client: GeminiClient
    let defaults: UserDefaults
    var calendar: Calendar

    private let lock = NSLock()
    private var tail: Task<[String], Never>?

    init(store: MemoryStore = .shared, log: EventLog = .shared, client: GeminiClient = .shared,
         defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.store = store
        self.log = log
        self.client = client
        self.defaults = defaults
        self.calendar = calendar
    }

    /// Timestamp of the newest event already consolidated.
    var lastRunAt: Date? {
        get { defaults.object(forKey: Self.lastRunKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastRunKey) }
    }

    /// `learned[]` from the most recent run that produced any.
    var latestLearned: [String] {
        get { defaults.stringArray(forKey: Self.learnedKey) ?? [] }
        set { defaults.set(newValue, forKey: Self.learnedKey) }
    }

    /// Returns `learned[]`. With no new events, a daily rollover is skipped.
    @discardableResult
    func run(reason: Reason) async -> [String] {
        await run(reason: reason, force: false)
    }

    /// `force` (dev menu) runs even with no new events — re-finalising yesterday's/today's timeline.
    @discardableResult
    func run(reason: Reason, force: Bool, now: Date = .now) async -> [String] {
        lock.lock()
        let previous = tail
        let task = Task { [self] () -> [String] in
            _ = await previous?.value
            return await perform(reason: reason, force: force, now: now)
        }
        tail = task
        lock.unlock()
        return await task.value
    }

    private func perform(reason: Reason, force: Bool, now: Date) async -> [String] {
        let since = lastRunAt
        let all = log.readAll()
        let fresh = all.filter { since == nil || $0.ts > since! }
        if fresh.isEmpty && reason == .dailyRollover && !force { return [] }

        let files = store.list()
        let offline = OfflineConsolidator.consolidate(newEvents: fresh, allEvents: all, files: files,
                                                      now: now, calendar: calendar)
        var response = offline
        if !fresh.isEmpty && client.isConfigured {
            let prompt = ConsolidatorPrompt.prompt(
                today: MemoryDates.day(now, calendar: calendar), reason: reason, files: files,
                lastRunAt: since, events: fresh.map { $0.jsonLine() }.joined(separator: "\n"))
            let live = await client.generate(ConsolidatorResponse.self, prompt, fallback: offline).value
            // An empty / unusable live reply must not swallow the new events: use the offline rewrite.
            // (`lastRunAt` then advances because the offline consolidator really did fold them in.)
            response = isUsable(live) ? live : offline
        }

        apply(response, today: MemoryDates.day(now, calendar: calendar))
        if let newest = fresh.map(\.ts).max() { lastRunAt = newest }
        let learned = Array(response.learned.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(3))
        if !learned.isEmpty { latestLearned = learned }
        NotificationCenter.default.post(name: .memoryDidChange, object: nil)
        return learned
    }

    /// True when a reply has at least one file `apply` would accept (safe `.md` path; a write with content).
    func isUsable(_ response: ConsolidatorResponse) -> Bool {
        response.files.contains { file in
            let path = file.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasSuffix(".md"), store.safeURL(path) != nil else { return false }
            return file.op == .moveToCompleted || !file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Applies returned files in one history batch. Returns the paths written.
    @discardableResult
    func apply(_ response: ConsolidatorResponse, today: String) -> [String] {
        store.batch {
            var written: [String] = []
            for file in response.files {
                let path = file.path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard path.hasSuffix(".md"), store.safeURL(path) != nil else { continue }
                switch file.op {
                case .write:
                    guard !file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    if store.write(path, content: Self.ensureHeader(file.content, path: path, today: today)) {
                        written.append(path)
                    }
                case .moveToCompleted:
                    let name = (path as NSString).lastPathComponent
                    let from = "workstreams/active/\(name)"
                    let to = "workstreams/completed/\(name)"
                    let content = file.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil : Self.ensureHeader(file.content, path: to, today: today)
                    if store.move(from, to: to, content: content) { written.append(to) }
                }
            }
            return written
        }
    }

    /// Model output without a YAML header gets one, so headers stay parseable.
    static func ensureHeader(_ content: String, path: String, today: String) -> String {
        if MemoryHeader.parse(content).header != nil { return content }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let type: String
        switch true {
        case path == "profile.md": type = "profile"
        case path.hasPrefix("timeline/daily/"): type = "daily"
        case path.hasSuffix("patterns.md"): type = "patterns"
        case path.hasSuffix("what-works.md"): type = "procedural"
        case path.hasPrefix("workstreams/"): type = "workstream"
        default: type = "note"
        }
        return MemoryHeader(id: name, type: type, aliases: [name], updated: today).file(body: content)
    }
}

extension Notification.Name {
    /// Posted after the consolidator or seeder changes memory files.
    static let memoryDidChange = Notification.Name("sheep.memoryDidChange")
}
