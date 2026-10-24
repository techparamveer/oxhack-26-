import XCTest
@testable import Sheep

@MainActor
final class RestPlayTests: XCTestCase {
    private var tmp: URL!
    private var originalRoot: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var spy: SpyNotifier!
    private var originalNotifier: LimitNotifier!

    override func setUp() async throws {
        spy = SpyNotifier()
        originalNotifier = RestController.notifier
        RestController.notifier = spy
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("restplay-\(UUID())", isDirectory: true)
        originalRoot = AppPaths.root
        AppPaths.root = tmp
        suiteName = "restplay-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        RestController.notifier = originalNotifier
        StubGemini.reply = nil
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
        RestController.startRest(activity: "  Netflix ", limitMinutes: 45, state: state, client: GeminiClient(apiKey: ""))
        XCTAssertEqual(state.restSession?.activity, "Netflix")
        XCTAssertEqual(state.mode, .rest)
        XCTAssertEqual(AppState(defaults: defaults).restSession?.limitMinutes, 45)
        RestController.endRest(state: state, log: EventLog(fileURL: { self.tmp.appendingPathComponent("e.jsonl") }))
    }

    // MARK: Overuse notification

    private var offline: GeminiClient { GeminiClient(apiKey: "") }
    private var live: GeminiClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGemini.self]
        return GeminiClient(apiKey: "test-key", model: "stub", session: URLSession(configuration: config))
    }

    func testOfflineSchedulesFallbackOnceAndEndClearsIt() async {
        let state = AppState(defaults: defaults)
        let task = RestController.startRest(activity: "Netflix", limitMinutes: 45, state: state, client: offline)
        await task.value
        XCTAssertEqual(spy.scheduled.count, 1, "offline: only the fallback, no re-schedule")
        XCTAssertEqual(spy.scheduled.first?.id, RestController.restNotificationID)
        XCTAssertTrue(spy.scheduled.first?.body.contains("50 min of netflix") ?? false)
        XCTAssertEqual(spy.scheduled.first?.after ?? 0, 20, accuracy: 1)
        RestController.endRest(state: state, log: EventLog(fileURL: { self.tmp.appendingPathComponent("e.jsonl") }))
        XCTAssertEqual(spy.cleared, [RestController.restNotificationID])
    }

    func testGeminiTextReplacesFallbackUnderSameID() async {
        StubGemini.reply = #"{"title":"pause netflix?","body":"50 min in. stretch."}"#
        let state = AppState(defaults: defaults)
        await RestController.startRest(activity: "Netflix", limitMinutes: 45, state: state, client: live).value
        XCTAssertEqual(spy.scheduled.count, 2)
        XCTAssertEqual(Set(spy.scheduled.map(\.id)), [RestController.restNotificationID], "same id → replaces, never a second banner")
        XCTAssertEqual(spy.scheduled.last?.title, "pause netflix?")
    }

    func testGeminiTextDroppedIfRestEndedFirst() async {
        StubGemini.reply = #"{"title":"pause netflix?","body":"50 min in. stretch."}"#
        let state = AppState(defaults: defaults)
        let task = RestController.startRest(activity: "Netflix", limitMinutes: 45, state: state, client: live)
        RestController.endRest(state: state, log: EventLog(fileURL: { self.tmp.appendingPathComponent("e.jsonl") }))
        await task.value
        XCTAssertEqual(spy.scheduled.count, 1, "late Gemini text must not resurrect a cancelled notification")
        XCTAssertEqual(spy.cleared, [RestController.restNotificationID])
    }

    func testEndRestAndEndPlayWithoutSessionLeaveFocusAlone() {
        let state = AppState(defaults: defaults)
        state.activeSession = FocusSession(answers: ["a"], title: "Ch.3", opener: "", watchOut: "",
                                           workstream: "", checklist: [], pomodoros: 1, pomodoroMinutes: 25,
                                           startedAt: Date())
        state.setMode(.focus)

        XCTAssertEqual(RestController.endRest(state: state), 0)
        XCTAssertEqual(state.mode, .focus)
        XCTAssertNotNil(state.activeSession)

        XCTAssertEqual(RestController.endPlay(state: state), 0)
        XCTAssertEqual(state.mode, .focus)
        XCTAssertNotNil(state.activeSession)
    }

    func testEndWithoutSessionIdlesOnlyTheModeBeingEnded() {
        let state = AppState(defaults: defaults)
        state.setMode(.rest)
        XCTAssertEqual(RestController.endRest(state: state), 0)
        XCTAssertEqual(state.mode, .idle)

        state.setMode(.play)
        XCTAssertEqual(RestController.endRest(state: state), 0)
        XCTAssertEqual(state.mode, .play)

        XCTAssertEqual(RestController.endPlay(state: state), 0)
        XCTAssertEqual(state.mode, .idle)

        state.setMode(.rest)
        XCTAssertEqual(RestController.endPlay(state: state), 0)
        XCTAssertEqual(state.mode, .rest)
    }

    func testEndRestTwiceAwardsXPOnce() {
        let log = EventLog(fileURL: { self.tmp.appendingPathComponent("events.jsonl") })
        let state = AppState(defaults: defaults)
        state.fastTimers = false
        let start = Date()
        state.restSession = RestSession(activity: "Walk", limitMinutes: 30, startedAt: start)
        RestController.endRest(state: state, now: start.addingTimeInterval(600), log: log)
        XCTAssertEqual(RestController.endRest(state: state, now: start.addingTimeInterval(601), log: log), 0)
        XCTAssertEqual(state.progress.xp, XPRules.underLimit)
        XCTAssertEqual(log.readAll().count, 1)
    }

    func testPlayStartSchedulesAndEndClears() {
        let state = AppState(defaults: defaults)
        RestController.startPlay(limitMinutes: 60, state: state)
        XCTAssertEqual(spy.scheduled.map(\.id), [RestController.playNotificationID])
        XCTAssertEqual(spy.scheduled.first?.after, 20)
        RestController.endPlay(state: state, log: EventLog(fileURL: { self.tmp.appendingPathComponent("e.jsonl") }))
        XCTAssertEqual(spy.cleared, [RestController.playNotificationID])
    }

    func testEndWithoutSessionDoesNotClearARunningRestNotification() {
        let live = AppState(defaults: defaults)
        RestController.startRest(activity: "Netflix", limitMinutes: 45, state: live, client: offline)
        XCTAssertEqual(spy.scheduled.count, 1)

        let other = AppState(defaults: UserDefaults(suiteName: "rest-other-\(UUID())")!)
        other.setMode(.focus)
        XCTAssertEqual(RestController.endRest(state: other), 0)
        XCTAssertTrue(spy.cleared.isEmpty, "ending a missing Rest must not cancel a running Rest's banner")
        XCTAssertEqual(live.mode, .rest)
        XCTAssertNotNil(live.restSession)
    }

    func testRelaunchKeepsRunningRestAndRestoresOveruseNotification() async {
        let state = AppState(defaults: defaults)
        await RestController.startRest(activity: "Netflix", limitMinutes: 45, state: state, client: offline).value
        XCTAssertEqual(spy.scheduled.count, 1)
        spy.scheduled.removeAll()
        spy.cleared.removeAll()

        let reloaded = AppState(defaults: defaults)
        XCTAssertEqual(reloaded.mode, .rest)
        XCTAssertEqual(reloaded.restSession?.activity, "Netflix")
        XCTAssertTrue(spy.cleared.isEmpty, "mode reconciliation must not cancel the overuse notification")

        RestController.restoreOveruseNotifications(state: reloaded)
        XCTAssertEqual(spy.scheduled.last?.id, RestController.restNotificationID)
        XCTAssertTrue(spy.scheduled.last?.body.contains("netflix") ?? false, spy.scheduled.last?.body ?? "")
        XCTAssertEqual(spy.scheduled.last?.after ?? 0, 20, accuracy: 1)
    }

    func testRestoreDoesNotScheduleWithoutARunningSession() {
        let state = AppState(defaults: defaults)
        state.setMode(.rest)
        RestController.restoreOveruseNotifications(state: state)
        XCTAssertTrue(spy.scheduled.isEmpty)
        XCTAssertEqual(state.mode, .rest)
    }

    func testRestoreDoesNotRefireAnOveruseNotificationThatAlreadyFired() {
        let state = AppState(defaults: defaults)
        state.fastTimers = true
        let start = Date()
        RestController.startRest(activity: "Netflix", limitMinutes: 45, state: state, now: start, client: offline)
        RestController.startPlay(limitMinutes: 60, state: state, now: start)
        spy.scheduled.removeAll()
        // Scene flips back to active after the banners were delivered: no second banner.
        RestController.restoreOveruseNotifications(state: state, now: start.addingTimeInterval(LimitClock.fastFireSeconds + 5))
        XCTAssertTrue(spy.scheduled.isEmpty)
    }

    func testRestoreRearmsPlayOveruseNotification() {
        let state = AppState(defaults: defaults)
        RestController.startPlay(limitMinutes: 60, state: state)
        spy.scheduled.removeAll()
        RestController.restoreOveruseNotifications(state: state)
        XCTAssertEqual(spy.scheduled.last?.id, RestController.playNotificationID)
        XCTAssertEqual(spy.scheduled.last?.after ?? 0, 20, accuracy: 1)
    }
}

final class SpyNotifier: LimitNotifier {
    struct Call { var id, title, body: String; var after: TimeInterval }
    var scheduled: [Call] = []
    var cleared: [String] = []
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) {
        scheduled.append(Call(id: id, title: title, body: body, after: seconds))
    }
    func clear(id: String) { cleared.append(id) }
}

/// Answers every Gemini request with `reply` wrapped in a generateContent envelope.
final class StubGemini: URLProtocol {
    nonisolated(unsafe) static var reply: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let text = Self.reply ?? ""
        let envelope: [String: Any] = ["candidates": [["content": ["parts": [["text": text]]]]]]
        let data = try! JSONSerialization.data(withJSONObject: envelope)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
