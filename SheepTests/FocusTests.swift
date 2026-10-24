import XCTest
@testable import Sheep

final class PlannerPromptTests: XCTestCase {
    private let answers = ["Dissertation ch.3 — due Fri 30 Oct", "800-word intro drafted", "Instagram reels"]

    func testFallbackShape() {
        let plan = PlannerPrompt.fallback(answers: answers, pomodoros: 3, minutes: 75, workstream: "dissertation-ch3")
        XCTAssertTrue((3...5).contains(plan.checklist.count))
        let verbs = ["Outline", "Get", "Review", "Pick", "Finish"]
        for item in plan.checklist {
            let first = String(item.split(separator: " ").first ?? "")
            XCTAssertTrue(verbs.contains(first), "not verb-first: \(item)")
        }
        XCTAssertEqual(plan.title, "Dissertation ch.3")
        XCTAssertLessThanOrEqual(plan.title.split(separator: " ").count, 6)
        XCTAssertEqual(plan.workstream, "dissertation-ch3")
        XCTAssertTrue(plan.watchOut.contains("Instagram reels"))
        XCTAssertLessThanOrEqual(plan.watchOut.split(separator: " ").count, 15)
        XCTAssertLessThanOrEqual(plan.opener.split(separator: " ").count, 25)
        XCTAssertTrue(plan.checklist[1].contains("800-word intro drafted"))
    }

    func testFallbackWithEmptyAnswers() {
        let plan = PlannerPrompt.fallback(answers: ["Write tests", "", ""], pomodoros: 1, minutes: 25)
        XCTAssertEqual(plan.checklist.count, 3)
        XCTAssertFalse(plan.watchOut.isEmpty)
        XCTAssertEqual(plan.workstream, "write-tests")
        XCTAssertTrue(plan.opener.hasPrefix("1 Pomodoro,"))
    }

    func testUserTemplateFilling() {
        let user = PlannerPrompt.user(minutes: 75, pomodoros: 3, answers: answers, memory: "MEMO-LINE")
        XCTAssertTrue(user.contains("SESSION LENGTH: 75 minutes (3 × Pomodoro)"))
        XCTAssertTrue(user.contains("Q1 What do you want to achieve? Dissertation ch.3 — due Fri 30 Oct"))
        XCTAssertTrue(user.contains("Q2 What does \"done\" look like? 800-word intro drafted"))
        XCTAssertTrue(user.contains("Q3 What usually distracts you? Instagram reels"))
        XCTAssertTrue(user.contains("MEMORY:\nMEMO-LINE"))
        XCTAssertFalse(user.contains("{{"))
        let prompt = PlannerPrompt.prompt(minutes: 75, pomodoros: 3, answers: answers, memory: "m")
        XCTAssertEqual(prompt.temperature, 0.6)
        XCTAssertEqual(prompt.name, "planner")
    }

    func testActiveWorkstreamParsing() {
        let content = """
        ---
        id: dissertation-ch3
        type: workstream
        aliases: [dissertation, ch3]
        updated: 2026-10-23
        ---
        # Dissertation chapter 3
        - **Goal:** Dissertation ch.3 — due Fri 30 Oct
        - Progress: outline done
        """
        let files = [MemoryFile(path: "profile.md", content: "x"),
                     MemoryFile(path: "workstreams/active/dissertation-ch3.md", content: content)]
        let ws = ActiveWorkstream.first(in: files)
        XCTAssertEqual(ws?.slug, "dissertation-ch3")
        XCTAssertEqual(ws?.goal, "Dissertation chapter 3")
        XCTAssertNil(ws?.nextStep)

        let goalOnly = ActiveWorkstream.parse(path: "workstreams/active/g.md", content: "- **Goal:** Ship v1\n")
        XCTAssertEqual(goalOnly?.goal, "Ship v1")

        let headingOnly = ActiveWorkstream.parse(path: "workstreams/active/x.md", content: "# Learn Swift\nnotes")
        XCTAssertEqual(headingOnly?.goal, "Learn Swift")
        let headerTitle = ActiveWorkstream.parse(path: "workstreams/active/y.md", content: "---\ntitle: \"Ship app\"\n---\n")
        XCTAssertEqual(headerTitle?.goal, "Ship app")
        XCTAssertNil(ActiveWorkstream.first(in: [MemoryFile(path: "workstreams/completed/z.md", content: "# Done")]))
    }
}

final class FocusMemoryTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sheep-focus-mem-\(UUID())")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// Q1 pre-fill uses the file the real MemorySeeder writes.
    func testPrefillFromSeededWorkstream() {
        let store = MemoryStore(root: root)
        let log = EventLog(fileURL: { [root] in root!.appendingPathComponent("events.jsonl") })
        let consolidator = MemoryConsolidator(store: store, log: log, client: GeminiClient(apiKey: "", model: nil),
                                              defaults: UserDefaults(suiteName: "sheep-focus-mem-\(UUID())")!)
        MemorySeeder.seedYesterday(store: store, log: log, consolidator: consolidator)
        let ws = ActiveWorkstream.first(in: store.list())
        XCTAssertEqual(ws?.slug, "dissertation-ch3")
        XCTAssertEqual(ws?.goal, "Dissertation ch.3")
        XCTAssertEqual(ws?.nextStep, "Write the 3 intro paragraphs from yesterday's outline")

        // Offline plan carries memory: workstream next step first, yesterday's recap in the opener.
        let today = Calendar.current.startOfDay(for: .now)
        let recap = OfflineBrief.recapSentence(log.readAll().filter { $0.ts < today }, calendar: .current)
        XCTAssertNotNil(recap)
        let plan = PlannerPrompt.fallback(answers: [ws!.goal, "800 words", "instagram reels"], pomodoros: 3, minutes: 3,
                                          workstream: ws?.slug, nextStep: ws?.nextStep, recap: recap)
        XCTAssertEqual(plan.title, "Dissertation ch.3")
        XCTAssertEqual(plan.workstream, "dissertation-ch3")
        XCTAssertEqual(plan.checklist.first, "Write the 3 intro paragraphs from yesterday's outline")
        XCTAssertTrue(plan.opener.hasPrefix("Yesterday you did 1 of 3"), plan.opener)
        XCTAssertLessThanOrEqual(plan.opener.split(separator: " ").count, 25)
    }

    func testRecapTooLongFallsBackToDefaultOpener() {
        let long = Array(repeating: "word", count: 24).joined(separator: " ")
        let plan = PlannerPrompt.fallback(answers: ["a", "b", "c"], pomodoros: 2, minutes: 50, recap: long)
        XCTAssertTrue(plan.opener.hasPrefix("2 Pomodoros, 50 minutes."))
    }
}

final class ReflectionPromptTests: XCTestCase {
    func testUserTemplateFilling() {
        var s = makeSession(done: 1, of: 3)
        s.nudgeCount = 2; s.nudgesResisted = 1; s.scrollSeconds = 270
        let user = ReflectionPrompt.user(session: s, memory: "MEMO")
        XCTAssertTrue(user.contains("SESSION: Ch.3 intro (3 min planned, 2 min actual)"))
        XCTAssertTrue(user.contains("CHECKLIST: 1 done / 3; remaining: Item 2; Item 3"))
        XCTAssertTrue(user.contains("NUDGES: 2 shown, 1 resisted"))
        XCTAssertTrue(user.contains("SCROLL IN WRAPPERS DURING SESSION: 4.5 min"))
        XCTAssertTrue(user.contains("MEMORY:\nMEMO"))
    }

    func testFallbackIsHonestAboutWeakSession() {
        let weak = ReflectionPrompt.fallback(session: makeSession(done: 0, of: 3))
        XCTAssertFalse(weak.headline.lowercased().contains("great"))
        XCTAssertEqual(weak.xpBonus, 0)
        let full = ReflectionPrompt.fallback(session: makeSession(done: 3, of: 3))
        XCTAssertGreaterThan(full.xpBonus, 0)
        XCTAssertTrue((0...50).contains(full.xpBonus))
    }
}

final class PomodoroTimerTests: XCTestCase {
    func testMathWithInjectedClock() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var now = start
        let t = PomodoroTimer(startedAt: start, pomodoros: 3, pomodoroMinutes: 25, clock: { now },
                              scheduler: { _, _, _, _ in }, canceller: { _ in })
        XCTAssertEqual(t.currentPomodoro, 1)
        XCTAssertEqual(t.remainingInCurrent, 25 * 60)
        XCTAssertEqual(t.countdownText, "25:00")

        now = start.addingTimeInterval(10 * 60 + 30); t.tick()
        XCTAssertEqual(t.currentPomodoro, 1)
        XCTAssertEqual(t.remainingInCurrent, 14 * 60 + 30)
        XCTAssertEqual(t.countdownText, "14:30")

        now = start.addingTimeInterval(25 * 60); t.tick()
        XCTAssertEqual(t.currentPomodoro, 2)
        XCTAssertEqual(t.remainingInCurrent, 25 * 60)

        now = start.addingTimeInterval(60 * 60); t.tick()
        XCTAssertEqual(t.currentPomodoro, 3)
        XCTAssertEqual(t.remainingInCurrent, 15 * 60)
        XCTAssertFalse(t.isFinished)

        now = start.addingTimeInterval(80 * 60); t.tick()
        XCTAssertTrue(t.isFinished)
        XCTAssertEqual(t.currentPomodoro, 3)
        XCTAssertEqual(t.remainingInCurrent, 0)
        XCTAssertEqual(t.progressInCurrent, 1)

        now = start.addingTimeInterval(-5); t.tick() // clock skew
        XCTAssertEqual(t.currentPomodoro, 1)
    }

    func testSchedulesRemainingPomodoroEnds() {
        let start = Date(timeIntervalSince1970: 0)
        var scheduled: [(String, TimeInterval)] = []
        var cancelled: [String] = []
        let t = PomodoroTimer(startedAt: start, pomodoros: 3, pomodoroMinutes: 1, sessionID: UUID(),
                              clock: { start.addingTimeInterval(70) },
                              scheduler: { id, _, _, after in scheduled.append((id, after)) },
                              canceller: { cancelled.append($0) })
        t.scheduleNotifications(title: "x")
        XCTAssertEqual(scheduled.map(\.1), [50, 110])   // pomodoro 1 already over
        XCTAssertEqual(scheduled.last?.0, t.notificationID(3))
        t.cancelNotifications()
        XCTAssertEqual(cancelled.count, 3)
    }
}

@MainActor
final class FocusControllerTests: XCTestCase {
    private var logURL: URL!
    private var log: EventLog!
    private var state: AppState!
    private var router: Router!
    private var savedRoot: URL!

    override func setUp() async throws {
        savedRoot = AppPaths.root
        AppPaths.root = FileManager.default.temporaryDirectory.appendingPathComponent("sheep-focus-\(UUID())")
        logURL = FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID()).jsonl")
        log = EventLog(fileURL: { [logURL] in logURL! })
        state = AppState(defaults: UserDefaults(suiteName: "sheep-focus-\(UUID())")!)
        router = Router()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: logURL)
        try? FileManager.default.removeItem(at: AppPaths.root)
        AppPaths.root = savedRoot
    }

    private func controller(start: Date, now: @escaping () -> Date, consolidate: @escaping (MemoryConsolidator.Reason) async -> [String]) -> FocusController {
        FocusController(eventLog: log, gemini: GeminiClient(apiKey: "", model: nil),
                        memory: { _ in "MEM" }, consolidate: consolidate, clock: now)
    }

    func testStartFinishLogsSessionEndBeforeConsolidatorAndAwardsXP() async {
        let start = Date()
        var now = start
        var sawSessionEndFirst = false
        let c = controller(start: start, now: { now }) { [log] reason in
            XCTAssertEqual(reason, .sessionEnd)
            sawSessionEndFirst = log!.readAll().contains { $0.type == .sessionEnd }
            return ["Mornings are your best focus time."]
        }
        state.fastTimers = true
        router.push(.focusIntake)
        let answers = ["Write tests", "All green", "YouTube"]
        let plan = await c.makePlan(answers: answers, pomodoros: 3, pomodoroMinutes: 1, workstream: nil)
        let session = c.start(plan: plan, answers: answers, pomodoros: 3,
                              pomodoroMinutes: FocusController.pomodoroMinutes(state: state), state: state, router: router)

        XCTAssertEqual(state.mode, .focus)
        XCTAssertEqual(state.activeSession?.pomodoroMinutes, 1)
        XCTAssertEqual(router.path, [.focusSession])
        XCTAssertEqual(log.readAll().first?.type, .sessionStart)
        XCTAssertEqual(log.readAll().first?.plannedMin, 3)
        XCTAssertEqual(log.readAll().first?.answers, answers)

        for item in session.checklist { c.toggle(itemID: item.id, state: state) }
        XCTAssertEqual(state.progress.xp, 3 * XPRules.perChecklistItem)

        now = start.addingTimeInterval(3 * 60)
        await c.finish(state: state, router: router)

        XCTAssertTrue(sawSessionEndFirst, "session_end must be logged before the consolidator runs")
        XCTAssertNil(state.activeSession)
        XCTAssertEqual(state.mode, .idle)
        XCTAssertEqual(router.path, [.congrats])

        let outcome = try! XCTUnwrap(state.lastOutcome)
        let bonus = ReflectionPrompt.fallback(session: outcome.session).xpBonus
        let endXP = XPRules.sessionEnd(focusedMinutes: 3, fast: true, completed: true, reflectionBonus: bonus)
        XCTAssertEqual(endXP, 30 + 50 + bonus)
        XCTAssertEqual(outcome.xpEarned, endXP + 3 * XPRules.perChecklistItem)
        XCTAssertEqual(state.progress.xp, endXP + 3 * XPRules.perChecklistItem)
        XCTAssertEqual(outcome.learned, ["Mornings are your best focus time."])

        let types = log.readAll().map(\.type)
        XCTAssertEqual(types.filter { $0 == .checklistDone }.count, 3)
        let end = log.readAll().first { $0.type == .sessionEnd }
        XCTAssertEqual(end?.done, 3)
        XCTAssertEqual(end?.total, 3)
        XCTAssertEqual(end?.actualMin, 3)
    }

    func testStartEndsRunningRestAndKeepsOneMode() async {
        let spy = SpyNotifier()
        let saved = RestController.notifier
        RestController.notifier = spy
        defer { RestController.notifier = saved }
        let start = Date()
        let c = controller(start: start, now: { start }) { _ in [] }
        RestController.startRest(activity: "Netflix", limitMinutes: 45, state: state, now: start.addingTimeInterval(-600))
        XCTAssertEqual(state.mode, .rest)
        let plan = PlannerPrompt.fallback(answers: ["a", "b", "c"], pomodoros: 1, minutes: 1)
        c.start(plan: plan, answers: ["a", "b", "c"], pomodoros: 1, pomodoroMinutes: 1, state: state, router: router)
        XCTAssertNil(state.restSession)
        XCTAssertEqual(state.mode, .focus)
        XCTAssertTrue(log.readAll().contains { $0.type == .restActivity })
        XCTAssertNotNil(state.activeSession)
    }

    func testFinishTwiceIsANoOp() async {
        let start = Date()
        var calls = 0
        let c = controller(start: start, now: { start.addingTimeInterval(60) }) { _ in calls += 1; return [] }
        let plan = PlannerPrompt.fallback(answers: ["a", "b", "c"], pomodoros: 1, minutes: 1)
        c.start(plan: plan, answers: ["a", "b", "c"], pomodoros: 1, pomodoroMinutes: 1, state: state, router: router)
        async let first: Void = c.finish(state: state, router: router)
        async let second: Void = c.finish(state: state, router: router)
        _ = await (first, second)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(log.readAll().filter { $0.type == .sessionEnd }.count, 1)
    }

    func testPomodoroMinutesSetting() {
        let defaults = UserDefaults(suiteName: "sheep-pomo-\(UUID())")!
        state.fastTimers = true
        XCTAssertEqual(FocusController.pomodoroMinutes(state: state, defaults: defaults), 1)
        state.fastTimers = false
        XCTAssertEqual(FocusController.pomodoroMinutes(state: state, defaults: defaults), 25)
        defaults.set(50, forKey: FocusController.pomodoroMinutesKey)
        XCTAssertEqual(FocusController.pomodoroMinutes(state: state, defaults: defaults), 50)
    }

    func testFocusedMinutesCappedAtPlan() async {
        let start = Date()
        var now = start
        let c = controller(start: start, now: { now }) { _ in [] }
        let plan = PlannerPrompt.fallback(answers: ["a", "b", "c"], pomodoros: 1, minutes: 1)
        c.start(plan: plan, answers: ["a", "b", "c"], pomodoros: 1, pomodoroMinutes: 1, state: state, router: router)
        now = start.addingTimeInterval(60 * 60)
        await c.finish(state: state, router: router)
        let bonus = ReflectionPrompt.fallback(session: state.lastOutcome!.session).xpBonus
        XCTAssertEqual(state.lastOutcome?.xpEarned, XPRules.sessionEnd(focusedMinutes: 1, fast: true, completed: false, reflectionBonus: bonus))
        XCTAssertTrue(state.lastOutcome!.learned.isEmpty)
    }
}

private func makeSession(done: Int, of total: Int) -> FocusSession {
    let start = Date(timeIntervalSince1970: 0)
    var items = (1...total).map { ChecklistItem(text: "Item \($0)") }
    for i in 0..<done { items[i].done = true }
    return FocusSession(answers: ["a", "b", "c"], title: "Ch.3 intro", opener: "", watchOut: "", workstream: "ch3",
                        checklist: items, pomodoros: 3, pomodoroMinutes: 1,
                        startedAt: start, endedAt: start.addingTimeInterval(120))
}
