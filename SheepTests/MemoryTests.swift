import XCTest
@testable import Sheep

final class MemoryTests: XCTestCase {
    var tmp: URL!
    var store: MemoryStore!
    var log: EventLog!
    var defaults: UserDefaults!
    var suite: String!
    var oldRoot: URL!
    let cal = Calendar.current
    var now: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now)! }

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sheep-mem-\(UUID())", isDirectory: true)
        oldRoot = AppPaths.root
        AppPaths.root = tmp
        store = MemoryStore(root: tmp.appendingPathComponent("memory"))
        let events = tmp.appendingPathComponent("memory/events.jsonl")
        log = EventLog(fileURL: { events })
        suite = "sheep.tests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        AppPaths.root = oldRoot
        try? FileManager.default.removeItem(at: tmp)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func consolidator() -> MemoryConsolidator {
        MemoryConsolidator(store: store, log: log, client: GeminiClient(apiKey: ""), defaults: defaults)
    }

    @discardableResult
    private func seed() -> [SheepEvent] {
        MemorySeeder.seedYesterday(now: now, calendar: cal, store: store, log: log, consolidator: consolidator())
    }

    // MARK: Header

    func testHeaderParseAndSerializeRoundTrip() {
        let h = MemoryHeader(id: "what-works", type: "procedural", aliases: ["nudges", "tone", "lock in"], updated: "2026-10-24")
        let file = h.file(body: "# What works\n\n- one")
        let parsed = MemoryHeader.parse(file)
        XCTAssertEqual(parsed.header, h)
        XCTAssertEqual(parsed.body, "# What works\n\n- one\n")
    }

    func testHeaderParsesBlockListAndQuotes() {
        let text = "---\nid: \"profile\"\ntype: profile\naliases:\n  - Student\n  - 'lock in'\nupdated: 2026-10-23\n---\nBody"
        let parsed = MemoryHeader.parse(text)
        XCTAssertEqual(parsed.header?.id, "profile")
        XCTAssertEqual(parsed.header?.aliases, ["student", "lock in"])
        XCTAssertEqual(parsed.body, "Body")
        XCTAssertNil(MemoryHeader.parse("# no header").header)
    }

    // MARK: Store

    func testAliasSearch() {
        store.write("a.md", content: MemoryHeader(id: "a", type: "note", aliases: ["instagram", "reels"], updated: "x").file(body: "A"))
        store.write("b.md", content: MemoryHeader(id: "b", type: "note", aliases: ["dissertation"], updated: "x").file(body: "B"))
        store.write("c.md", content: MemoryHeader(id: "c", type: "note", aliases: ["instagram"], updated: "x").file(body: "C"))
        XCTAssertEqual(store.search(keywords: ["instagram", "reels"]).map(\.path), ["a.md", "c.md"])
        XCTAssertEqual(store.search(keywords: ["Dissertation"]).map(\.path), ["b.md"])
        XCTAssertTrue(store.search(keywords: ["youtube"]).isEmpty)
    }

    func testSnapshotBeforeOverwriteAndDelete() throws {
        store.write("knowledge/patterns.md", content: "v1")
        XCTAssertEqual(store.historySnapshotCount(), 0)
        store.write("knowledge/patterns.md", content: "v1") // unchanged → no snapshot
        XCTAssertEqual(store.historySnapshotCount(), 0)
        store.write("knowledge/patterns.md", content: "v2")
        XCTAssertEqual(store.historySnapshotCount(), 1)
        XCTAssertEqual(store.read("knowledge/patterns.md"), "v2")
        let snap = try FileManager.default.contentsOfDirectory(at: store.historyRoot, includingPropertiesForKeys: nil)[0]
        XCTAssertEqual(try String(contentsOf: snap.appendingPathComponent("knowledge/patterns.md"), encoding: .utf8), "v1")
        XCTAssertFalse(store.list().contains { $0.path.hasPrefix("history/") })
        store.delete("knowledge/patterns.md")
        XCTAssertNil(store.read("knowledge/patterns.md"))
        XCTAssertEqual(store.historySnapshotCount(), 2)
    }

    func testPathTraversalRefused() {
        for bad in ["../evil.md", "/etc/evil.md", "a/../../evil.md", "history/x.md", "./x.md", "", "~/x.md"] {
            XCTAssertFalse(store.write(bad, content: "x"), bad)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("evil.md").path))
        XCTAssertTrue(store.write("workstreams/active/ok.md", content: "x"))
    }

    func testSymlinkEscapeRefused() throws {
        let fm = FileManager.default
        let outside = tmp.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try "secret".write(to: outside.appendingPathComponent("s.md"), atomically: true, encoding: .utf8)
        XCTAssertTrue(store.write("ok.md", content: "x")) // creates the root
        try fm.createSymbolicLink(at: store.root.appendingPathComponent("link"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: store.root.appendingPathComponent("file.md"),
                                  withDestinationURL: outside.appendingPathComponent("s.md"))
        try fm.createSymbolicLink(at: store.root.appendingPathComponent("dangling.md"),
                                  withDestinationURL: outside.appendingPathComponent("nope.md"))
        XCTAssertFalse(store.write("link/new.md", content: "x"))
        XCTAssertNil(store.read("link/s.md"))
        XCTAssertNil(store.read("file.md"))
        XCTAssertFalse(store.write("file.md", content: "x"))
        XCTAssertFalse(store.write("dangling.md", content: "x"))
        XCTAssertFalse(store.delete("link/s.md"))
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("new.md").path))
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("nope.md").path))
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("s.md"), encoding: .utf8), "secret")
        XCTAssertTrue(store.write("knowledge/new.md", content: "x"), "normal nested writes still work")
    }

    func testWhatWorksTieOrderIsDeterministic() {
        let ts = now
        var a = WhatWorks(), b = WhatWorks()
        let evs = ["zany", "calm", "firm"].map {
            SheepEvent(ts: ts, type: .nudge, tone: $0, action: "back_to_focus", outcome: "ignored")
        }
        evs.forEach { a.add($0, calendar: cal) }
        evs.reversed().forEach { b.add($0, calendar: cal) }
        XCTAssertEqual(a.render(updated: "x"), b.render(updated: "x"))
        XCTAssertEqual(a.byTone.map(\.tone), ["calm", "firm", "zany"])
    }

    // MARK: Seeder

    func testSeederCreatesFilesWithValidHeaders() {
        let events = seed()
        XCTAssertEqual(events.count, 8)
        let y = MemoryDates.day(cal.date(byAdding: .day, value: -1, to: now)!)
        let expected = ["profile.md", "knowledge/patterns.md", "knowledge/what-works.md",
                        "workstreams/active/dissertation-ch3.md", "timeline/daily/\(y).md"]
        for path in expected {
            let f = store.file(path)
            XCTAssertNotNil(f, path)
            XCTAssertFalse(f?.header?.id.isEmpty ?? true, path)
            XCTAssertFalse(f?.header?.type.isEmpty ?? true, path)
            XCTAssertGreaterThanOrEqual(f?.header?.aliases.count ?? 0, 3, path)
        }
        XCTAssertEqual(log.readAll().count, 8)
        XCTAssertTrue(log.readAll().allSatisfy { MemoryDates.day($0.ts) == y })
        XCTAssertEqual(consolidator().lastRunAt, events.map(\.ts).max())
        let ws = store.read("workstreams/active/dissertation-ch3.md") ?? ""
        XCTAssertTrue(ws.contains("# Dissertation ch.3"))
        XCTAssertTrue(ws.contains("Deadline: Fri "))
        // Re-seeding does not duplicate events.
        seed()
        XCTAssertEqual(log.readAll().count, 8)
    }

    // MARK: Offline consolidation

    func testOfflineConsolidationFromSeededEvents() {
        let events = seed()
        let y = MemoryDates.day(cal.date(byAdding: .day, value: -1, to: now)!)
        // Fresh memory (no seeded knowledge files) so counts come purely from events.
        let result = OfflineConsolidator.consolidate(newEvents: events, allEvents: events, files: [], now: now, calendar: cal)
        let byPath = Dictionary(result.files.map { ($0.path, $0.content) }, uniquingKeysWith: { a, _ in a })

        let daily = byPath["timeline/daily/\(y).md"] ?? ""
        XCTAssertTrue(daily.contains("Done: 1 of 3 Pomodoros"), daily)
        XCTAssertTrue(daily.contains("22:40 Slipped into Instagram Reels, 12 min"), daily)
        XCTAssertTrue(daily.contains("21:17 Slipped into Instagram Reels, 4.5 min, 12 min into Focus"), daily)
        XCTAssertTrue(daily.contains("Netflix 110 min (limit 45)"), daily)
        XCTAssertNotNil(MemoryHeader.parse(daily).header)

        let works = byPath["knowledge/what-works.md"] ?? ""
        XCTAssertTrue(works.contains("Firm nudges (back to focus): got you back 0 of 1"), works)
        XCTAssertTrue(works.contains("Playful nudges (close app): got you back 1 of 1"), works)

        let patterns = byPath["knowledge/patterns.md"] ?? ""
        XCTAssertTrue(patterns.contains("Slips into Instagram Reels ~12 min into Focus (seen 1×"), patterns)
        XCTAssertTrue(patterns.contains("Instagram Reels after 22:00 (seen 1×"), patterns)

        let ws = byPath["workstreams/active/dissertation-ch3.md"] ?? ""
        XCTAssertTrue(ws.contains("1 of 3 done, 27 min focus"), ws)

        XCTAssertFalse(result.learned.isEmpty)
        XCTAssertLessThanOrEqual(result.learned.count, 3)
        XCTAssertTrue(result.learned[0].contains("1 of 3"), result.learned.joined(separator: " | "))
    }

    func testWhatWorksAndPatternsMergeIncrementally() {
        seed()
        let late = cal.date(bySettingHour: 11, minute: 0, second: 0, of: now)!
        let newEvents = [
            SheepEvent(ts: late, type: .nudge, app: .instagram, tone: "firm", action: "back_to_focus", outcome: "returned")
        ]
        let result = OfflineConsolidator.consolidate(newEvents: newEvents, allEvents: log.readAll() + newEvents,
                                                     files: store.list(), now: now, calendar: cal)
        let works = result.files.first { $0.path == "knowledge/what-works.md" }?.content ?? ""
        XCTAssertTrue(works.contains("Firm nudges (back to focus): got you back 2 of 4"), works)
        XCTAssertTrue(works.contains("Playful nudges (close app): got you back 2 of 2"), works)
        XCTAssertTrue(works.contains("Naming the deadline"), "free-form notes are preserved")
        XCTAssertTrue(result.learned.contains("Firm nudges got you back 2 of 4 times."), result.learned.joined(separator: " | "))
    }

    func testConsolidatorRunOfflineAppliesAndSnapshots() async {
        seed()
        let c = consolidator()
        // Rollover with no new events is skipped.
        let before = store.historySnapshotCount()
        let skipped = await c.run(reason: .dailyRollover, force: false, now: now)
        XCTAssertEqual(skipped, [])
        XCTAssertEqual(store.historySnapshotCount(), before)

        // A new session today → today's daily, workstream progress, snapshot of the old workstream.
        let s = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        log.append(SheepEvent(ts: s, type: .sessionStart, mode: .focus, title: "Ch.3 intro paragraphs",
                              workstream: "dissertation-ch3", plannedMin: 75))
        log.append(SheepEvent(ts: s.addingTimeInterval(80 * 60), type: .sessionEnd, mode: .focus,
                              workstream: "dissertation-ch3", actualMin: 75, done: 3, total: 3, xp: 80))
        let learned = await c.run(reason: .sessionEnd, force: false, now: now)
        XCTAssertNotNil(store.read("timeline/daily/\(MemoryDates.day(now)).md"))
        XCTAssertTrue(store.read(MemorySeeder.workstreamPath)?.contains("3 of 3 done, 75 min focus") ?? false)
        XCTAssertGreaterThan(store.historySnapshotCount(), before)
        XCTAssertTrue(learned.first?.contains("3 of 3 Pomodoros — best session this week.") ?? false, learned.joined(separator: " | "))
        XCTAssertEqual(c.latestLearned, learned)
        XCTAssertEqual(c.lastRunAt, s.addingTimeInterval(80 * 60))
    }

    func testForcedRunFinalisesYesterdayWithSnapshot() async {
        seed()
        let before = store.historySnapshotCount()
        _ = await consolidator().run(reason: .dailyRollover, force: true, now: now)
        XCTAssertEqual(store.historySnapshotCount(), before + 1)
        let y = MemoryDates.day(cal.date(byAdding: .day, value: -1, to: now)!)
        XCTAssertEqual(store.file("timeline/daily/\(y).md")?.header?.updated, MemoryDates.day(now))
    }

    // MARK: Gemini response application

    func testApplyCannedGeminiResponseIncludingMoveToCompleted() throws {
        seed()
        let inner = """
        {"files":[
          {"path":"knowledge/patterns.md","content":"---\\nid: patterns\\ntype: patterns\\naliases: [reels]\\nupdated: 2026-10-24\\n---\\n# Patterns\\n- New","op":"write"},
          {"path":"workstreams/active/dissertation-ch3.md","content":"","op":"move_to_completed"},
          {"path":"notes/plain.md","content":"No header here","op":"write"},
          {"path":"../escape.md","content":"x","op":"write"}
        ],"learned":["Mornings are your best focus time."]}
        """
        let envelope = try JSONSerialization.data(withJSONObject: ["candidates": [["content": ["parts": [["text": inner]]]]]])
        let response = try GeminiClient.decodeResponse(ConsolidatorResponse.self, from: envelope)
        XCTAssertEqual(response.files.count, 4)
        XCTAssertEqual(response.files[1].op, .moveToCompleted)
        XCTAssertEqual(response.learned, ["Mornings are your best focus time."])

        let before = store.historySnapshotCount()
        let written = consolidator().apply(response, today: "2026-10-24")
        XCTAssertEqual(Set(written), ["knowledge/patterns.md", "workstreams/completed/dissertation-ch3.md", "notes/plain.md"])
        XCTAssertNil(store.read("workstreams/active/dissertation-ch3.md"))
        XCTAssertTrue(store.read("workstreams/completed/dissertation-ch3.md")?.contains("# Dissertation ch.3") ?? false)
        XCTAssertNotNil(store.file("notes/plain.md")?.header, "missing headers are added")
        XCTAssertEqual(store.historySnapshotCount(), before + 1, "one batch = one history folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("escape.md").path))
    }

    // MARK: Context

    func testContextIncludesYesterdayAndWorkstreamWithinCap() {
        XCTAssertTrue(MemoryContext.build(for: .dailyBrief, store: store, now: now, defaults: defaults).contains("no memory yet"))
        seed()
        let ctx = MemoryContext.build(for: .nudge(app: .instagram, section: .reels, goal: "Dissertation intro"),
                                      store: store, now: now, defaults: defaults)
        XCTAssertTrue(ctx.contains("## Yesterday ("), ctx)
        XCTAssertTrue(ctx.contains("1 of 3 Pomodoros"), ctx)
        XCTAssertTrue(ctx.contains("## Active workstreams"), ctx)
        XCTAssertTrue(ctx.contains("Dissertation ch.3"), ctx)
        XCTAssertTrue(ctx.contains("## What works"), ctx)
        XCTAssertLessThanOrEqual(ctx.count, MemoryContext.cap)

        defaults.set("gentle", forKey: "sheep.voice")
        defaults.set(true, forKey: "sheep.askBeforeActing")
        XCTAssertTrue(MemoryContext.build(for: .dailyBrief, store: store, now: now, defaults: defaults)
            .contains("Voice: gentle and encouraging. Ask before acting."))

        let huge = String(repeating: "- a very long line about reels and focus\n", count: 600)
        store.write("profile.md", content: MemoryHeader(id: "profile", type: "profile", updated: "x").file(body: huge))
        for i in 0..<5 {
            store.write("workstreams/active/w\(i).md", content: MemoryHeader(id: "w\(i)", type: "workstream", aliases: ["instagram"], updated: "x").file(body: huge))
        }
        let capped = MemoryContext.build(for: .nudge(app: .instagram, section: .reels, goal: nil), store: store, now: now, defaults: defaults)
        XCTAssertLessThanOrEqual(capped.count, MemoryContext.cap)
        XCTAssertTrue(capped.contains("## Yesterday"))
    }

    // MARK: Brief

    func testBriefFallbackAfterSeeding() {
        let first = OfflineBrief.make(events: log.readAll(), store: store, now: now, calendar: cal)
        XCTAssertEqual(first.headline, "How to start")
        XCTAssertFalse(first.isFromMemory)

        seed()
        let brief = OfflineBrief.make(events: log.readAll(), store: store, now: now, calendar: cal)
        XCTAssertTrue(brief.body.contains("Yesterday you did 1 of 3 Pomodoros before Reels got you at 22:40."), brief.body)
        XCTAssertTrue(brief.body.contains("Lock in — Dissertation ch.3 is due"), brief.body)
        XCTAssertTrue(brief.isFromMemory)
        XCTAssertEqual(brief.suggestedMode, .focus)
        XCTAssertLessThanOrEqual(brief.headline.split(separator: " ").count, 10)
    }

    func testDuePhrase() {
        let d = { (n: Int) in self.cal.date(byAdding: .day, value: n, to: self.now)! }
        XCTAssertEqual(OfflineBrief.duePhrase(d(0), now: now, calendar: cal), "today")
        XCTAssertEqual(OfflineBrief.duePhrase(d(1), now: now, calendar: cal), "tomorrow")
        XCTAssertEqual(OfflineBrief.duePhrase(d(3), now: now, calendar: cal), MemoryDates.weekday(d(3)))
    }
}
