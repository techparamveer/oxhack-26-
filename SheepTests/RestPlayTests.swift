import XCTest
@testable import Sheep

@MainActor
final class RestPlayTests: XCTestCase {
    private var tmp: URL!
    private var originalRoot: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("restplay-\(UUID())", isDirectory: true)
        originalRoot = AppPaths.root
        AppPaths.root = tmp
        suiteName = "restplay-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        AppPaths.root = originalRoot
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: Timing

    func testOveruseFireDelayFastVsReal() {
        XCTAssertEqual(LimitClock.overuseDelay(limitMinutes: 45, fast: true), 20)
        XCTAssertEqual(LimitClock.overuseDelay(limitMinutes: 15, fast: true), 20, "fast fires at 20 s regardless of limit")
        XCTAssertEqual(LimitClock.overuseDelay(limitMinutes: 45, fast: false), 46 * 60)
        XCTAssertEqual(LimitClock.projectedMinutesAtOveruse(limitMinutes: 45, fast: true), 50)
        XCTAssertEqual(LimitClock.projectedMinutesAtOveruse(limitMinutes: 45, fast: false), 46)
        // Fast display: the full limit plays out before the notification fires.
        let start = Date(timeIntervalSince1970: 0)
        let atFire = LimitClock.elapsedMinutes(startedAt: start, now: start.addingTimeInterval(20), limitMinutes: 45, fast: true)
        XCTAssertGreaterThan(atFire, 45)
        XCTAssertEqual(atFire, 50, accuracy: 0.01)
        // After the notification, fast mode ticks at 1x.
        let later = LimitClock.elapsedSeconds(startedAt: start, now: start.addingTimeInterval(80), limitMinutes: 45, fast: true)
        XCTAssertEqual(later, 50 * 60 + 60, accuracy: 0.01)
        XCTAssertEqual(LimitClock.elapsedMinutes(startedAt: start, now: start.addingTimeInterval(600), limitMinutes: 45, fast: false), 10)
    }

    func testFormat() {
        XCTAssertEqual(LimitClock.format(65), "1:05")
        XCTAssertEqual(LimitClock.format(3723), "1:02:03")
    }

    // MARK: XP

    func testXPUnderAndOverLimit() {
        XCTAssertEqual(XPRules.restOrPlay(actualMinutes: 30, limitMinutes: 45), XPRules.underLimit)
        XCTAssertEqual(XPRules.restOrPlay(actualMinutes: 45, limitMinutes: 45), XPRules.underLimit)
        XCTAssertEqual(XPRules.restOrPlay(actualMinutes: 50, limitMinutes: 45), 0)
    }

    // MARK: Prompt

    func testRestPromptTemplateFilling() {
        var comps = DateComponents(); comps.year = 2026; comps.month = 10; comps.day = 24; comps.hour = 22; comps.minute = 40
        let now = Calendar.current.date(from: comps)!
        let p = RestNudgePrompt.prompt(activity: "netflix", limitMinutes: 45, actualMinutes: 50, now: now, memory: "MEM-LINE")
        XCTAssertTrue(p.user.contains("ACTIVITY: netflix   SET LIMIT: 45 min   ACTUAL: 50 min"), p.user)
        XCTAssertTrue(p.user.contains("NOW: 22:40"))
        XCTAssertTrue(p.user.hasSuffix("MEMORY:\nMEM-LINE"))
        XCTAssertEqual(p.temperature, 0.8)
        XCTAssertTrue(p.system.hasPrefix("The user is in Rest mode"))
        XCTAssertEqual(p.timeout, 3)
    }

    func testFallbackMentionsDurationAndNextThing() async {
        var comps = DateComponents(); comps.year = 2026; comps.month = 10; comps.day = 24; comps.hour = 15
        let afternoon = Calendar.current.date(from: comps)!
        comps.hour = 23
        let late = Calendar.current.date(from: comps)!
        let day = RestNudgePrompt.fallback(activity: "Netflix", limitMinutes: 45, actualMinutes: 50, now: afternoon)
        XCTAssertTrue(day.body.contains("50 min"))
        XCTAssertTrue(day.body.contains("netflix"))
        XCTAssertTrue(day.body.contains("water"))
        XCTAssertLessThanOrEqual(day.title.split(separator: " ").count, 6)
        XCTAssertLessThanOrEqual(day.body.split(separator: " ").count, 20)
        XCTAssertTrue(RestNudgePrompt.fallback(activity: "walk", limitMinutes: 30, actualMinutes: 46, now: late).body.contains("sleep"))

        let offline = await RestNudgePrompt.generate(activity: "netflix", limitMinutes: 45, actualMinutes: 50, now: afternoon,
                                                     client: GeminiClient(apiKey: "", model: nil))
        XCTAssertEqual(offline, day)
    }

    // MARK: End of session

    func testRestEndLogsEventAwardsXPAndClears() {
        let log = EventLog(fileURL: { self.tmp.appendingPathComponent("events.jsonl") })
        let state = AppState(defaults: defaults)
        state.fastTimers = false
        let start = Date()
        state.restSession = RestSession(activity: "Netflix", limitMinutes: 45, startedAt: start)
        state.setMode(.rest)

        let xp = RestController.endRest(state: state, now: start.addingTimeInterval(30 * 60), log: log)

        XCTAssertEqual(xp, XPRules.underLimit)
        XCTAssertEqual(state.progress.xp, XPRules.underLimit)
        XCTAssertNil(state.restSession)
        XCTAssertEqual(state.mode, .idle)
        let events = log.readAll()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .restActivity)
        XCTAssertEqual(events[0].activity, "netflix")
        XCTAssertEqual(events[0].limitMin, 45)
        XCTAssertEqual(events[0].actualMin, 30)
    }

    func testRestOverLimitInFastModeGivesNoXP() {
        let log = EventLog(fileURL: { self.tmp.appendingPathComponent("events.jsonl") })
        let state = AppState(defaults: defaults)
        state.fastTimers = true
        let start = Date()
        state.restSession = RestSession(activity: "Netflix", limitMinutes: 45, startedAt: start)
        let xp = RestController.endRest(state: state, now: start.addingTimeInterval(20), log: log)
        XCTAssertEqual(xp, 0)
        XCTAssertEqual(log.readAll().first?.actualMin, 50)
    }

    func testPlayEndLogsEvent() {
        let log = EventLog(fileURL: { self.tmp.appendingPathComponent("events.jsonl") })
        let state = AppState(defaults: defaults)
        state.fastTimers = false
        let start = Date()
        state.playSession = PlaySession(limitMinutes: 60, startedAt: start)
        state.setMode(.play)
        let xp = RestController.endPlay(state: state, now: start.addingTimeInterval(40 * 60), log: log)
        XCTAssertEqual(xp, XPRules.underLimit)
        XCTAssertNil(state.playSession)
        XCTAssertEqual(state.mode, .idle)
        let e = log.readAll()
        XCTAssertEqual(e.first?.type, .playSession)
        XCTAssertEqual(e.first?.limitMin, 60)
        XCTAssertEqual(e.first?.actualMin, 40)
        XCTAssertEqual(e.first?.xp, XPRules.underLimit)
    }

    // MARK: Muted work apps

    func testMutedAppsReadFromDefaults() {
        XCTAssertEqual(MutedAppsList.apps(defaults), ["Teams", "Outlook", "Slack"])
        defaults.set(["Teams", " ", "Linear"], forKey: MutedAppsList.defaultsKey)
        XCTAssertEqual(MutedAppsList.apps(defaults), ["Teams", "Linear"])
    }

    // MARK: Persistence

    func testSessionPersistenceRoundTrip() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let state = AppState(defaults: defaults)
        state.restSession = RestSession(activity: "Walk", limitMinutes: 30, startedAt: start)
        state.playSession = PlaySession(limitMinutes: 90, startedAt: start)

        let reloaded = AppState(defaults: defaults)
        XCTAssertEqual(reloaded.restSession, state.restSession)
        XCTAssertEqual(reloaded.playSession, state.playSession)
    }

    func testStartRestPersistsAndSetsMode() {
        let state = AppState(defaults: defaults)
        RestController.startRest(activity: "  Netflix ", limitMinutes: 45, state: state)
        XCTAssertEqual(state.restSession?.activity, "Netflix")
        XCTAssertEqual(state.mode, .rest)
        XCTAssertEqual(AppState(defaults: defaults).restSession?.limitMinutes, 45)
        RestController.endRest(state: state, log: EventLog(fileURL: { self.tmp.appendingPathComponent("e.jsonl") }))
    }
}
