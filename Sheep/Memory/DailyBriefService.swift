import Foundation
import Observation

/// One day's brief (GEMINI_PROMPTS §1).
struct DailyBriefValue: Codable, Equatable {
    var day: String
    var headline: String
    var body: String
    var suggestedMode: Mode
    /// True when the text is built from memory (yesterday / workstreams), false for the how-to greeting.
    var isFromMemory: Bool
    var source: String // "live" | "fallback"
}

/// Owns the Home brief: cached per calendar day in UserDefaults, refreshed on daily rollover / seed / tap.
/// Views read `headline`, `body`, `suggestedMode`, `isFromMemory`, `isLoading`.
@MainActor
@Observable
final class DailyBriefService {
    static let shared = DailyBriefService()
    static let cacheKey = "sheep.memory.dailyBrief.v1"

    private(set) var current: DailyBriefValue?
    private(set) var isLoading = false

    var headline: String { current?.headline ?? "" }
    var body: String { current?.body ?? "" }
    var suggestedMode: Mode { current?.suggestedMode ?? .focus }
    var isFromMemory: Bool { current?.isFromMemory ?? false }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: MemoryStore
    @ObservationIgnored private let log: EventLog
    @ObservationIgnored private let client: GeminiClient
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlight: Task<DailyBriefValue, Never>?

    init(defaults: UserDefaults = .standard, store: MemoryStore = .shared, log: EventLog = .shared,
         client: GeminiClient = .shared) {
        self.defaults = defaults
        self.store = store
        self.log = log
        self.client = client
        if let data = defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(DailyBriefValue.self, from: data),
           cached.day == MemoryDates.day(.now) {
            current = cached
        }
    }

    /// Uses today's cached brief if there is one, otherwise generates it.
    /// Concurrent callers (card `.task`, launch rollover) share one in-flight load.
    func loadIfNeeded() async {
        if let current, current.day == MemoryDates.day(.now) { return }
        if let inFlight { _ = await inFlight.value; return }
        await refresh(force: true)
    }

    /// Regenerates the brief (Gemini → offline fallback) and caches it for today.
    func refresh(force: Bool = true) async {
        if !force, let current, current.day == MemoryDates.day(.now) { return }
        generation += 1
        let gen = generation
        isLoading = true
        let (store, log, client) = (self.store, self.log, self.client)
        let task = Task.detached { await Self.compute(store: store, log: log, client: client, now: .now) }
        inFlight = task
        let value = await task.value
        guard gen == generation else { return } // a newer refresh/invalidate superseded this one
        inFlight = nil
        current = value
        isLoading = false
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.cacheKey) }
    }

    /// Drops the cache (e.g. after seeding or forgetting everything).
    func invalidate() {
        generation += 1
        inFlight = nil
        current = nil
        isLoading = false
        defaults.removeObject(forKey: Self.cacheKey)
    }

    nonisolated static func compute(store: MemoryStore, log: EventLog, client: GeminiClient, now: Date,
                                    calendar: Calendar = .current) async -> DailyBriefValue {
        let offline = OfflineBrief.make(events: log.readAll(), store: store, now: now, calendar: calendar)
        let day = MemoryDates.day(now, calendar: calendar)
        guard client.isConfigured else { return offline }
        let memory = MemoryContext.build(for: .dailyBrief, store: store, now: now, calendar: calendar)
        let prompt = DailyBriefPrompt.prompt(now: now, memory: memory)
        let fallback = DailyBriefPrompt.Response(headline: offline.headline, body: offline.body,
                                                 suggestedMode: offline.suggestedMode.rawValue)
        let result = await client.generate(DailyBriefPrompt.Response.self, prompt, fallback: fallback)
        guard result.source == .live else { return offline }
        return DailyBriefValue(day: day, headline: result.value.headline, body: result.value.body,
                               suggestedMode: Mode(rawValue: result.value.suggestedMode) ?? offline.suggestedMode,
                               isFromMemory: offline.isFromMemory, source: "live")
    }
}

/// Offline brief computed from yesterday's events + active workstreams. Real numbers and times only.
/// e.g. "Yesterday you did 1 of 3 Pomodoros before Reels got you at 22:40. Lock in — Dissertation ch.3 is due Friday."
enum OfflineBrief {
    static func make(events: [SheepEvent], store: MemoryStore, now: Date = .now,
                     calendar: Calendar = .current) -> DailyBriefValue {
        let day = MemoryDates.day(now, calendar: calendar)
        let startToday = calendar.startOfDay(for: now)
        let startYesterday = calendar.date(byAdding: .day, value: -1, to: startToday) ?? startToday
        let yesterday = events.filter { $0.ts >= startYesterday && $0.ts < startToday }.sorted { $0.ts < $1.ts }
        let workstream = activeWorkstream(store: store, now: now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        let greeting = hour < 12 ? "Morning." : hour < 18 ? "Afternoon." : "Evening."
        let lateMode: Mode = (hour >= 22 || hour < 5) ? .rest : .focus

        let recap = recapSentence(yesterday, calendar: calendar)
        guard recap != nil || workstream != nil else {
            let f = DailyBriefPrompt.firstDayFallback
            return DailyBriefValue(day: day, headline: f.headline, body: f.body, suggestedMode: .focus,
                                   isFromMemory: false, source: "fallback")
        }

        let next: String
        if let ws = workstream {
            next = ws.due.map { "Lock in — \(ws.title) is due \($0)." } ?? "Lock in on \(ws.title) today."
        } else {
            next = "Tap Focus and lock in."
        }
        let allDone = yesterday.last(where: { $0.type == .sessionEnd }).map { ($0.done ?? 0) >= ($0.total ?? 1) } ?? false
        let slipped = yesterday.contains { $0.type == .scroll && ($0.activeMin ?? 0) >= 1 }
        let headline: String
        if recap == nil { headline = "\(greeting) Let's lock in." }
        else if allDone && !slipped { headline = "\(greeting) Good run yesterday." }
        else { headline = "\(greeting) Today we lock in." }

        let body = [recap, next].compactMap { $0 }.joined(separator: " ")
        return DailyBriefValue(day: day, headline: headline, body: body, suggestedMode: lateMode,
                               isFromMemory: true, source: "fallback")
    }

    /// One sentence about yesterday, or nil if nothing worth saying was logged.
    static func recapSentence(_ evs: [SheepEvent], calendar: Calendar) -> String? {
        let end = evs.last { $0.type == .sessionEnd }
        let start = end.flatMap { Sessions.start(for: $0, in: evs) }
        let slip = evs.filter { $0.type == .scroll && ($0.activeMin ?? 0) >= 1 }
            .max { ($0.activeMin ?? 0) < ($1.activeMin ?? 0) }
        let t: (Date) -> String = { MemoryDates.time($0, calendar: calendar) }

        if let end, let total = end.total, total > 0 {
            let done = end.done ?? 0
            let unit = MemoryText.unit(plannedMin: start?.plannedMin, total: total)
            let did = done >= total ? "Yesterday you finished all \(total) \(unit)" : "Yesterday you did \(done) of \(total) \(unit)"
            if let slip {
                let place = MemoryText.shortPlace(slip.app, slip.section)
                if slip.ts >= (start?.ts ?? end.ts) {
                    return "\(did) before \(place) got you at \(t(slip.ts))."
                }
                return "\(place) got you at \(t(slip.ts)) yesterday, then you did \(done) of \(total) \(unit)."
            }
            return "\(did)."
        }
        if let slip {
            return "Yesterday \(MemoryText.shortPlace(slip.app, slip.section)) got you for \(MemoryText.minutes(slip.activeMin)) min at \(t(slip.ts))."
        }
        if let over = evs.first(where: { $0.type == .restActivity && ($0.actualMin ?? 0) > Double($0.limitMin ?? .max) }),
           let l = over.limitMin {
            return "Yesterday \(MemoryText.activity(over.activity)) ran \(MemoryText.minutes(over.actualMin)) min against a \(l)-min limit."
        }
        if let s = evs.first(where: { $0.type == .sessionStart }) {
            return "Yesterday you started \"\(s.title ?? "a Focus session")\" at \(t(s.ts))."
        }
        return nil
    }

    struct Workstream: Equatable { var title: String; var due: String? }

    /// The active workstream with the nearest deadline (or the first one).
    static func activeWorkstream(store: MemoryStore, now: Date, calendar: Calendar) -> Workstream? {
        let files = store.list(in: "workstreams/active/")
        guard !files.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        let withDates = files.map { f -> (MemoryFile, Date?) in (f, deadline(in: f.body, calendar: calendar)) }
        let upcoming = withDates.filter { ($0.1 ?? .distantFuture) >= today }
            .sorted { ($0.1 ?? .distantFuture) < ($1.1 ?? .distantFuture) }
        guard let (file, date) = upcoming.first ?? withDates.first.map({ ($0.0, nil) }) else { return nil }
        return Workstream(title: file.title, due: date.map { duePhrase($0, now: now, calendar: calendar) })
    }

    /// ISO date on a line mentioning "deadline" or "due".
    static func deadline(in body: String, calendar: Calendar) -> Date? {
        let regex = try! NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}"#)
        for line in body.components(separatedBy: "\n") {
            let l = line.lowercased()
            guard l.contains("deadline") || l.contains("due") else { continue }
            if l.contains("not set") { continue }
            let ns = line as NSString
            if let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                return MemoryDates.parseDay(ns.substring(with: m.range), calendar: calendar)
            }
        }
        return nil
    }

    static func duePhrase(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...6: return MemoryDates.weekday(date, calendar: calendar)
        default: return MemoryDates.short(date, calendar: calendar)
        }
    }
}
