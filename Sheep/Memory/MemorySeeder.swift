import Foundation

/// Dev "Seed yesterday": realistic yesterday-local-time events + memory files so the
/// "Yesterday you…" moment works on day one. Re-seeding replaces yesterday's events (no duplicates).
enum MemorySeeder {
    static let workstreamPath = "workstreams/active/dissertation-ch3.md"

    @discardableResult
    static func seedYesterday(now: Date = .now, calendar: Calendar = .current, store: MemoryStore = .shared,
                              log: EventLog = .shared, consolidator: MemoryConsolidator = .shared) -> [SheepEvent] {
        let today = calendar.startOfDay(for: now)
        let yDay = calendar.date(byAdding: .day, value: -1, to: today)!
        func at(_ h: Int, _ m: Int, _ s: Int = 0) -> Date {
            calendar.date(bySettingHour: h, minute: m, second: s, of: yDay)!
        }
        let ws = "dissertation-ch3"
        let events: [SheepEvent] = [
            SheepEvent(ts: at(21, 5), type: .sessionStart, mode: .focus, title: "Dissertation ch.3 intro", workstream: ws,
                       plannedMin: 75, answers: ["Finish the ch.3 intro draft", "800 words, 3 paragraphs", "Instagram reels"]),
            SheepEvent(ts: at(21, 17, 30), type: .scroll, mode: .focus, app: .instagram, section: .reels, activeMin: 4.5),
            SheepEvent(ts: at(21, 18), type: .nudge, app: .instagram, section: .reels, tone: "firm",
                       action: "back_to_focus", outcome: "ignored"),
            SheepEvent(ts: at(21, 28), type: .checklistDone, item: "Outline 3 intro paragraphs"),
            SheepEvent(ts: at(21, 32), type: .sessionEnd, mode: .focus, workstream: ws, actualMin: 27, done: 1, total: 3, xp: 20),
            SheepEvent(ts: at(22, 40), type: .scroll, mode: .idle, app: .instagram, section: .reels, activeMin: 12),
            SheepEvent(ts: at(22, 52), type: .nudge, app: .instagram, section: .reels, tone: "playful",
                       action: "close_app", outcome: "returned"),
            SheepEvent(ts: at(22, 58), type: .restActivity, mode: .rest, actualMin: 110, activity: "netflix", limitMin: 45)
        ]

        // Replace any previously seeded/logged events from yesterday, keep everything else.
        let kept = log.readAll().filter { !($0.ts >= yDay && $0.ts < today) }
        log.clear()
        for e in (kept + events).sorted(by: { $0.ts < $1.ts }) { log.append(e) }

        let y = MemoryDates.day(yDay, calendar: calendar)
        let d = { (days: Int) in MemoryDates.day(calendar.date(byAdding: .day, value: days, to: yDay)!, calendar: calendar) }
        let friday = calendar.nextDate(after: now, matching: DateComponents(weekday: 6), matchingPolicy: .nextTime)
            ?? calendar.date(byAdding: .day, value: 6, to: today)!
        let fridayISO = MemoryDates.day(friday, calendar: calendar)
        let fridayShort = MemoryDates.short(friday, calendar: calendar)

        store.batch {
            store.write("profile.md", content: MemoryHeader(
                id: "profile", type: "profile", aliases: ["profile", "student", "tone", "lock in", "dissertation"], updated: y
            ).file(body: """
            # Profile

            ## Life context
            - Final-year student writing a dissertation; works best in evening Focus blocks.
            - Instagram Reels is the main time sink, worst late at night.

            ## Tone that works
            - Blunt, "lock in" energy. Short sentences, real numbers, no lectures.
            - Playful beats firm when they're already mid-scroll.

            ## Autonomy
            - Happy for Sheep to hide Reels in Focus; ask before anything bigger.
            """))

            store.write("timeline/daily/\(y).md", content: DailyRenderer.render(
                day: y, events: events, updated: y, calendar: calendar))

            store.write(OfflineConsolidator.patternsPath, content: MemoryHeader(
                id: "patterns", type: "patterns", aliases: ["patterns", "distraction", "instagram", "reels", "late", "focus", "netflix"], updated: y
            ).file(body: """
            # Patterns

            - Slips into Instagram Reels ~12 min into Focus (seen 3×, last \(y))
            - Instagram Reels after 22:00 (seen 2×, last \(y))
            - Netflix runs past its Rest limit (seen 2×, last \(y))
            """))

            store.write(OfflineConsolidator.whatWorksPath, content: MemoryHeader(
                id: "what-works", type: "procedural", aliases: ["nudges", "tone", "what works", "playful", "firm"], updated: y
            ).file(body: """
            # What works

            Best so far: playful nudges (back 2 of 2). Least: firm (back 1 of 3).

            - Playful nudges (close app): got you back 2 of 2 (last \(y))
            - Firm nudges (back to focus): got you back 1 of 3 (last \(y))
            - Naming the deadline ("due Friday") gets a Focus session started.
            """))

            store.write(workstreamPath, content: MemoryHeader(
                id: ws, type: "workstream", aliases: ["dissertation", "ch3", "chapter 3", "thesis", "writing", "uni"], updated: y
            ).file(body: """
            # Dissertation ch.3

            - Goal: Draft chapter 3 (methods), starting with the intro.
            - Deadline: \(fridayShort) (\(fridayISO))

            ## Progress
            - \(d(-2)) · Read 4 papers for the lit review section
            - \(y) 21:05 · Dissertation ch.3 intro: 1 of 3 done, 27 min focus

            ## Next step
            - Write the 3 intro paragraphs from yesterday's outline.
            """))
        }

        consolidator.lastRunAt = events.map(\.ts).max() // seeded events are already reflected in memory
        consolidator.latestLearned = []
        NotificationCenter.default.post(name: .memoryDidChange, object: nil)
        return events
    }
}

/// Wipes memory files, the event log and all memory caches. Settings' "Forget everything" calls this.
enum MemoryReset {
    static let defaultsKeys = [
        MemoryConsolidator.lastRunKey, MemoryConsolidator.learnedKey,
        DailyBriefService.cacheKey, DailyRollover.lastDayKey
    ]

    static func forgetEverything(defaults: UserDefaults = .standard, log: EventLog = .shared, store: MemoryStore = .shared) {
        log.clear()
        try? FileManager.default.removeItem(at: store.root)
        defaultsKeys.forEach { defaults.removeObject(forKey: $0) }
        // Today's rollover is already done; don't re-run it against an empty memory.
        defaults.set(MemoryDates.day(.now), forKey: DailyRollover.lastDayKey)
        NotificationCenter.default.post(name: .memoryDidChange, object: nil)
        Task { @MainActor in
            DailyBriefService.shared.invalidate()
            await DailyBriefService.shared.refresh()
        }
    }
}

/// First `.active` of a new calendar day: consolidate yesterday, then refresh the brief. Never blocks UI.
enum DailyRollover {
    static let lastDayKey = "sheep.memory.lastRolloverDay"
    @MainActor private static var didRunLaunchHooks = false
    @MainActor private static var didRunConsolidatorHook = false

    @MainActor
    static func handleActive(defaults: UserDefaults = .standard) {
        #if DEBUG
        // Scriptable demo/QA hooks: `simctl launch … -sheepSeedYesterday` / `-sheepRunConsolidator`.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-sheepSeedYesterday"), !didRunLaunchHooks {
            didRunLaunchHooks = true
            MemorySeeder.seedYesterday()
            DailyBriefService.shared.invalidate()
            defaults.set(MemoryDates.day(.now), forKey: lastDayKey)
        }
        if args.contains("-sheepRunConsolidator"), !didRunConsolidatorHook {
            didRunConsolidatorHook = true
            Task {
                let learned = await MemoryConsolidator.shared.run(reason: .dailyRollover, force: true)
                print("[Memory] consolidator learned: \(learned)")
            }
        }
        #endif
        let today = MemoryDates.day(.now)
        guard defaults.string(forKey: lastDayKey) != today else {
            Task { await DailyBriefService.shared.loadIfNeeded() }
            return
        }
        defaults.set(today, forKey: lastDayKey)
        Task {
            await DailyBriefService.shared.loadIfNeeded() // show something immediately (cached or offline)
            let learned = await MemoryConsolidator.shared.run(reason: .dailyRollover)
            _ = learned
            await DailyBriefService.shared.refresh(force: true)
        }
    }
}
