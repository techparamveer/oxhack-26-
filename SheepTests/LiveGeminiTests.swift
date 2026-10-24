import XCTest
@testable import Sheep

/// Hits the deployed Supabase `gemini` proxy with each prompt built exactly as the app builds it.
/// Skipped unless `TEST_RUNNER_SHEEP_LIVE=1` (forwarded as `SHEEP_LIVE=1`).
final class LiveGeminiTests: XCTestCase {
    private var tmp: URL!
    private var savedRoot: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SHEEP_LIVE"] == "1",
            "Live Gemini test is opt-in: TEST_RUNNER_SHEEP_LIVE=1 xcodebuild … test -only-testing:SheepTests/LiveGeminiTests"
        )
        savedRoot = AppPaths.root
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sheep-live-\(UUID())", isDirectory: true)
        AppPaths.root = tmp
        suiteName = "sheep.live.\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let savedRoot { AppPaths.root = savedRoot }
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        if let suiteName { defaults?.removePersistentDomain(forName: suiteName) }
        super.tearDown()
    }

    func testAllPromptsAgainstDeployedProxy() async throws {
        guard let config = SupabaseConfig.fromBundle() else {
            throw XCTSkip("SUPABASE_HOST / SUPABASE_ANON_KEY missing from Info.plist (Config/Secrets.xcconfig)")
        }

        let sessionCfg = URLSessionConfiguration.ephemeral
        sessionCfg.timeoutIntervalForRequest = 30
        sessionCfg.timeoutIntervalForResource = 45
        sessionCfg.waitsForConnectivity = false
        let client = SupabaseClient(config: config, session: URLSession(configuration: sessionCfg), defaults: defaults)
        let builder = GeminiClient(apiKey: "", model: GeminiClient.defaultModel)
        let store = MemoryStore(root: tmp.appendingPathComponent("memory"))
        let now = Date()
        seedMemory(store: store, now: now)

        do {
            _ = try await client.auth.accessToken()
        } catch {
            throw XCTSkip("Anonymous sign-up failed: \(snippet(error))")
        }

        let cases = makeCases(store: store, now: now)
        var rows: [Row] = []
        var failures: [String] = []

        for c in cases {
            var oks = 0
            var times: [Int] = []
            var sample = ""
            var lastError = ""
            let body = builder.requestBody(c.prompt)
            // Consolidator stays on its 15 s prompt budget; others get a diagnostic
            // window so we can report real latency past the app's 3 s fallback cut-off.
            let timeout = c.prompt.timeout >= 10 ? c.prompt.timeout : 20
            for i in 1...3 {
                let started = Date()
                do {
                    let data = try await client.generateContent(
                        model: GeminiClient.defaultModel, body: body, timeout: timeout)
                    let decoded = try c.decode(data)
                    let ms = millis(since: started)
                    times.append(ms)
                    if c.matchesFallback(decoded) {
                        lastError = "identical to hardcoded fallback"
                        if sample.isEmpty { sample = oneLine(decoded) }
                    } else {
                        oks += 1
                        sample = oneLine(decoded)
                    }
                } catch {
                    let ms = millis(since: started)
                    times.append(ms)
                    lastError = snippet(error)
                    if sample.isEmpty { sample = lastError }
                    print("LIVE| \(c.name) run \(i)/3 failed after \(ms)ms: \(lastError)")
                }
            }
            if oks == 0 { failures.append("\(c.name): 0/3 (\(lastError))") }
            rows.append(Row(name: c.name, ok: oks, times: times, sample: sample))
        }

        print("LIVE| prompt            ok    p50_ms  max_ms  sample")
        for row in rows {
            let p50 = percentile(row.times, 0.5)
            let max = row.times.max() ?? 0
            print("LIVE| \(pad(row.name, 16)) \(row.ok)/3   \(pad("\(p50)", 7)) \(pad("\(max)", 7)) \(row.sample)")
        }

        if !failures.isEmpty {
            XCTFail("Live Gemini decode failures: \(failures.joined(separator: "; "))")
        }
    }

    // MARK: - Cases

    private struct Case {
        var name: String
        var prompt: GeminiPrompt
        var decode: (Data) throws -> any Encodable
        var matchesFallback: (any Encodable) -> Bool
    }

    private struct Row {
        var name: String
        var ok: Int
        var times: [Int]
        var sample: String
    }

    private func makeCases(store: MemoryStore, now: Date) -> [Case] {
        let defaults = self.defaults!
        let answers = ["Finish the OxHack pitch deck", "A 10-slide deck ready to present", "Instagram Reels"]
        let session = finishedFocus(answers: answers, now: now)

        let briefMemory = MemoryContext.build(for: .dailyBrief, store: store, now: now, defaults: defaults)
        let brief = DailyBriefPrompt.prompt(now: now, memory: briefMemory)
        let briefFallback = DailyBriefPrompt.firstDayFallback

        let planMemory = MemoryContext.build(for: .planner(goal: answers[0]), store: store, now: now, defaults: defaults)
        let planner = PlannerPrompt.prompt(minutes: 75, pomodoros: 3, answers: answers, memory: planMemory, now: now)
        let plannerFallback = PlannerPrompt.fallback(answers: answers, pomodoros: 3, minutes: 75)

        let nudgeInput = NudgeInput(
            mode: .focus, app: .instagram, section: .reels, activeMinutes: 4.5,
            nudgesThisSession: 0, sessionTitle: session.title, done: 1, total: 3,
            secondsLeft: 12 * 60, restActivity: nil, restLimitMinutes: nil, now: now)
        let nudgeMemory = MemoryContext.build(
            for: .nudge(app: nudgeInput.app, section: nudgeInput.section, goal: nudgeInput.sessionTitle),
            store: store, now: now, defaults: defaults)
        let nudge = NudgePrompt.prompt(nudgeInput, memory: nudgeMemory)
        let nudgeFallback = NudgePrompt.fallback(nudgeInput)

        let restMemory = MemoryContext.build(for: .rest(activity: "YouTube"), store: store, now: now, defaults: defaults)
        let rest = RestNudgePrompt.prompt(
            activity: "YouTube", limitMinutes: 20, actualMinutes: 28, now: now, memory: restMemory)
        let restFallback = RestNudgePrompt.fallback(
            activity: "YouTube", limitMinutes: 20, actualMinutes: 28, now: now)

        let reflectionMemory = MemoryContext.build(
            for: .reflection(goal: session.title), store: store, now: now, defaults: defaults)
        let reflection = ReflectionPrompt.prompt(session: session, memory: reflectionMemory)
        let reflectionFallback = ReflectionPrompt.fallback(session: session)

        let events = sampleEvents(session: session, answers: answers, now: now)
            .map { $0.jsonLine() }.joined(separator: "\n")
        let consolidator = ConsolidatorPrompt.prompt(
            today: MemoryDates.day(now), reason: .sessionEnd, files: store.list(),
            lastRunAt: now.addingTimeInterval(-86_400), events: events)
        let consolidatorFallback = ConsolidatorPrompt.emptyFallback

        return [
            Case(name: "daily_brief", prompt: brief,
                 decode: { try GeminiClient.decodeResponse(DailyBriefPrompt.Response.self, from: $0) },
                 matchesFallback: { ($0 as? DailyBriefPrompt.Response) == briefFallback }),
            Case(name: "planner", prompt: planner,
                 decode: { try GeminiClient.decodeResponse(PlannerPrompt.Response.self, from: $0) },
                 matchesFallback: { ($0 as? PlannerPrompt.Response) == plannerFallback }),
            Case(name: "nudge", prompt: nudge,
                 decode: { try GeminiClient.decodeResponse(Nudge.self, from: $0) },
                 matchesFallback: { ($0 as? Nudge) == nudgeFallback }),
            Case(name: "rest_nudge", prompt: rest,
                 decode: { try GeminiClient.decodeResponse(RestNudgePrompt.Response.self, from: $0) },
                 matchesFallback: { ($0 as? RestNudgePrompt.Response) == restFallback }),
            Case(name: "reflection", prompt: reflection,
                 decode: { try GeminiClient.decodeResponse(ReflectionPrompt.Response.self, from: $0) },
                 matchesFallback: { ($0 as? ReflectionPrompt.Response) == reflectionFallback }),
            Case(name: "consolidator", prompt: consolidator,
                 decode: { try GeminiClient.decodeResponse(ConsolidatorResponse.self, from: $0) },
                 matchesFallback: { ($0 as? ConsolidatorResponse) == consolidatorFallback }),
        ]
    }

    private func finishedFocus(answers: [String], now: Date) -> FocusSession {
        let started = now.addingTimeInterval(-75 * 60)
        return FocusSession(
            answers: answers,
            title: "OxHack pitch deck",
            opener: "Three pomodoros. Hide Reels.",
            watchOut: "Instagram Reels around minute 12.",
            workstream: "oxhack-pitch",
            checklist: [
                ChecklistItem(text: "Outline the 10 slides", done: true, doneAt: started.addingTimeInterval(20 * 60)),
                ChecklistItem(text: "Write the problem slide", done: true, doneAt: started.addingTimeInterval(45 * 60)),
                ChecklistItem(text: "Record a 60s walkthrough", done: false),
            ],
            pomodoros: 3,
            pomodoroMinutes: 25,
            startedAt: started,
            endedAt: now,
            nudgeCount: 2,
            nudgesResisted: 1,
            scrollSeconds: 90
        )
    }

    private func sampleEvents(session: FocusSession, answers: [String], now: Date) -> [SheepEvent] {
        let started = session.startedAt
        return [
            SheepEvent(ts: started, type: .sessionStart, mode: .focus, title: session.title,
                       workstream: session.workstream, plannedMin: session.plannedMinutes, answers: answers),
            SheepEvent(ts: started.addingTimeInterval(12 * 60), type: .nudge, mode: .focus,
                       app: .instagram, section: .reels, tone: "firm", action: "back_to_focus", outcome: "returned"),
            SheepEvent(ts: started.addingTimeInterval(40 * 60), type: .nudge, mode: .focus,
                       app: .instagram, section: .reels, tone: "firm", action: "back_to_focus", outcome: "ignored"),
            SheepEvent(ts: now, type: .sessionEnd, mode: .focus, title: session.title,
                       workstream: session.workstream, plannedMin: session.plannedMinutes,
                       actualMin: Double(session.actualMinutes), done: session.doneCount,
                       total: session.checklist.count, xp: 80),
        ]
    }

    private func seedMemory(store: MemoryStore, now: Date) {
        let today = MemoryDates.day(now)
        let yesterday = MemoryDates.day(now.addingTimeInterval(-86_400))
        _ = store.write("profile.md", content: MemoryHeader(
            id: "profile", type: "profile", aliases: ["student", "hackathon"], updated: yesterday
        ).file(body: """
        # Life context
        Oxford student, building Sheep for OxHack '26.
        # Tone that works
        Blunt lock-in energy; humour works, guilt does not.
        """))
        _ = store.write("timeline/daily/\(yesterday).md", content: MemoryHeader(
            id: yesterday, type: "daily", aliases: ["yesterday", "focus"], updated: yesterday
        ).file(body: """
        - 14:00–15:15 Focus “pitch outline”: 2/3 items, 55 min. Slipped into Instagram Reels at 14:12 (4 min).
        - Win: finished the problem slide.
        """))
        _ = store.write("workstreams/active/oxhack-pitch.md", content: MemoryHeader(
            id: "oxhack-pitch", type: "workstream", aliases: ["oxhack", "pitch", "deck"], updated: today
        ).file(body: """
        # OxHack pitch deck
        - Goal: Finish the OxHack pitch deck
        ## Next step
        - Record a 60s walkthrough
        """))
        _ = store.write("knowledge/patterns.md", content: MemoryHeader(
            id: "patterns", type: "patterns", aliases: ["instagram", "reels"], updated: yesterday
        ).file(body: "- Slips into Instagram Reels ~12 min into Focus (seen 2×, last \(yesterday))"))
        _ = store.write("knowledge/what-works.md", content: MemoryHeader(
            id: "what-works", type: "procedural", aliases: ["nudges", "tone"], updated: yesterday
        ).file(body: "- Firm back_to_focus returns them (1/2). Gentle ignored."))
    }

    // MARK: - Formatting

    private func millis(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    private func percentile(_ values: [Int], _ p: Double) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let i = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[i]
    }

    private func oneLine(_ value: any Encodable) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? enc.encode(AnyEncodable(value))) ?? Data()
        let raw = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
        return String(raw.prefix(80))
    }

    private func snippet(_ error: Error) -> String {
        switch error {
        case GeminiError.http(let status, let body):
            return "HTTP \(status) \(String(body.prefix(220)).replacingOccurrences(of: "\n", with: " "))"
        case GeminiError.timeout:
            return "timeout"
        case GeminiError.emptyResponse:
            return "empty response"
        case SupabaseError.http(let status, let body):
            return "HTTP \(status) \(String(body.prefix(220)).replacingOccurrences(of: "\n", with: " "))"
        case let url as URLError:
            return "URLError \(url.code.rawValue) \(url.localizedDescription)"
        default:
            let ns = error as NSError
            return "\(ns.domain) \(ns.code) \(error.localizedDescription)"
        }
    }

    private func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }
}

private struct AnyEncodable: Encodable {
    var value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
