import XCTest
@testable import Sheep

/// Polish pass (step 10): wrapper login hosts, deep-link mode switching, reset, Rest brief,
/// nudge template, daily score sync, consolidator fallback, seeded memory counts.
@MainActor
final class PolishTests: XCTestCase {
    private var tmp: URL!
    private var savedRoot: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private var spy: SpyNotifier!
    private var savedNotifier: LimitNotifier!
    private let cal = Calendar.current

    override func setUp() async throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("polish-\(UUID())", isDirectory: true)
        savedRoot = AppPaths.root
        AppPaths.root = tmp
        suite = "sheep.polishTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        spy = SpyNotifier()
        savedNotifier = RestController.notifier
        RestController.notifier = spy
    }

    override func tearDown() async throws {
        RestController.notifier = savedNotifier
        StubGemini.reply = nil
        AppPaths.root = savedRoot
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: 1 · Wrapper navigation

    private func decide(_ url: String, _ app: WrappedApp = .instagram, mode: Mode = .idle,
                        main: Bool = true, user: Bool = true) -> WrapperNavigation.Decision {
        WrapperNavigation.decide(url: URL(string: url)!, app: app, mode: mode, isMainFrame: main,
                                 userInitiated: user, defaults: defaults)
    }

    func testLoginHostsStayInWrapper() {
        for url in ["https://www.facebook.com/login.php", "https://m.facebook.com/dialog/oauth",
                    "https://facebook.com/", "https://static.xx.fbcdn.net/a.js",
                    "https://scontent.cdninstagram.com/v/x.jpg"] {
            XCTAssertEqual(decide(url, .instagram), .allow, url)
        }
        for url in ["https://accounts.google.com/ServiceLogin", "https://accounts.youtube.com/accounts/SetSID",
                    "https://consent.google.com/m", "https://consent.youtube.com/m",
                    "https://www.gstatic.com/x.js", "https://lh3.googleusercontent.com/a.png"] {
            XCTAssertEqual(decide(url, .youtube), .allow, url)
        }
        XCTAssertTrue(WrapperNavigation.isLoginHost("WWW.Facebook.COM"))
        XCTAssertFalse(WrapperNavigation.isLoginHost("notfacebook.com"))
        XCTAssertFalse(WrapperNavigation.isLoginHost("facebook.com.evil.io"))
        XCTAssertFalse(WrapperNavigation.isLoginHost(nil))
    }

    func testOnlyUserInitiatedMainFrameForeignNavigationsOpenSafari() {
        XCTAssertEqual(decide("https://example.com/article"), .openExternally)
        XCTAssertEqual(decide("https://example.com/article", user: false), .allow, "redirect hops stay in")
        XCTAssertEqual(decide("https://example.com/embed", main: false), .allow, "sub-frames never leave")
        XCTAssertEqual(decide("https://www.youtube.com/", .instagram), .openExternally, "other app's host is foreign")
    }

    func testAppHostsKeepPolicyAndSchemesAreFiltered() {
        XCTAssertEqual(decide("https://www.instagram.com/reels/abc/", mode: .focus), .block(.reels))
        XCTAssertEqual(decide("https://www.instagram.com/reels/abc/", mode: .rest), .allow)
        XCTAssertEqual(decide("https://m.youtube.com/shorts/x", .youtube, mode: .focus), .block(.shorts))
        // A Facebook path that looks like a blocked section is never policy-checked.
        XCTAssertEqual(decide("https://www.facebook.com/reels/1", mode: .focus), .allow)
        XCTAssertEqual(decide("instagram://media?id=1"), .cancel)
        XCTAssertEqual(decide("about:blank"), .allow)
    }

    func testNewWindowDecision() {
        XCTAssertEqual(WrapperNavigation.decideNewWindow(url: URL(string: "https://www.facebook.com/x")!, app: .instagram), .allow)
        XCTAssertEqual(WrapperNavigation.decideNewWindow(url: URL(string: "https://example.com")!, app: .instagram), .openExternally)
        XCTAssertEqual(WrapperNavigation.decideNewWindow(url: URL(string: "fb://x")!, app: .instagram), .cancel)
        XCTAssertTrue(WrapperNavigation.isUserInitiated(.linkActivated))
        XCTAssertFalse(WrapperNavigation.isUserInitiated(.other))
    }

    // MARK: 4 · Deep-link mode switching

    private func focusSession() -> FocusSession {
        FocusSession(answers: ["a", "b", "c"], title: "Ch.3", opener: "", watchOut: "", workstream: "",
                     checklist: [ChecklistItem(text: "one")], pomodoros: 1, pomodoroMinutes: 25, startedAt: .now)
    }

    func testRestLinkEndsRunningPlayFirst() {
        let state = AppState(defaults: defaults)
        let router = Router()
        RestController.startPlay(limitMinutes: 60, state: state)
        XCTAssertTrue(router.handle(url: DeepLink.mode(.rest), state: state))
        XCTAssertNil(state.playSession, "play ended through its controller")
        XCTAssertEqual(spy.cleared, [RestController.playNotificationID])
        XCTAssertEqual(EventLog.shared.readAll().filter { $0.type == .playSession }.count, 1, "play session logged")
        XCTAssertEqual(state.mode, .rest)
        XCTAssertEqual(router.path, [.rest])
    }

    func testPlayLinkKeepsRunningRestUntilPlayStartsViaPlan() {
        let state = AppState(defaults: defaults)
        let router = Router()
        RestController.startRest(activity: "Netflix", limitMinutes: 45, state: state, client: GeminiClient(apiKey: ""))
        router.handle(url: DeepLink.mode(.play), state: state)
        XCTAssertNil(state.restSession)
        XCTAssertEqual(spy.cleared, [RestController.restNotificationID])
        XCTAssertEqual(state.mode, .play)
        XCTAssertEqual(router.path, [.play])
    }

    func testRestLinkNeverEndsFocus() {
        let state = AppState(defaults: defaults)
        state.activeSession = focusSession()
        state.setMode(.focus)
        let router = Router()
        router.handle(url: DeepLink.mode(.rest), state: state)
        XCTAssertNotNil(state.activeSession)
        XCTAssertEqual(state.mode, .focus)
        XCTAssertEqual(router.path, [.focusSession], "routes back to the running focus")
        router.handle(url: DeepLink.mode(.idle), state: state)
        XCTAssertNotNil(state.activeSession, "idle link leaves focus alone too")
        XCTAssertEqual(state.mode, .focus)
    }

    func testRestLinkWhileRestingReturnsToIt() {
        let state = AppState(defaults: defaults)
        RestController.startRest(activity: "Walk", limitMinutes: 30, state: state, client: GeminiClient(apiKey: ""))
        let started = state.restSession?.startedAt
        let router = Router()
        router.handle(url: DeepLink.mode(.rest), state: state)
        XCTAssertEqual(state.restSession?.startedAt, started, "same session, not restarted")
        XCTAssertTrue(spy.cleared.isEmpty)
        XCTAssertEqual(router.path, [.rest])
        router.handle(url: DeepLink.mode(.idle), state: state)
        XCTAssertNil(state.restSession)
        XCTAssertEqual(state.mode, .idle)
    }

    // MARK: 5 · Reset

    func testClearPreferencesWipesSheepKeysButKeepsSupabase() {
        defaults.set("gentle", forKey: SheepSettings.Key.voice)
        defaults.set(50, forKey: SheepSettings.Key.pomodoroMinutes)
        defaults.set(["Teams"], forKey: SheepSettings.Key.mutedWorkApps)
        defaults.set(Data(), forKey: DailyBriefService.cacheKey)
        defaults.set(Date(), forKey: MemoryConsolidator.lastRunKey)
        defaults.set("token", forKey: "sheep.supabase.session.v1")
        defaults.set("other", forKey: "com.apple.something")
        let removed = AppReset.clearPreferences(defaults)
        XCTAssertTrue(removed.contains(SheepSettings.Key.voice))
        XCTAssertNil(defaults.object(forKey: SheepSettings.Key.pomodoroMinutes))
        XCTAssertNil(defaults.object(forKey: SheepSettings.Key.mutedWorkApps))
        XCTAssertNil(defaults.object(forKey: DailyBriefService.cacheKey))
        XCTAssertNil(defaults.object(forKey: MemoryConsolidator.lastRunKey))
        XCTAssertEqual(defaults.string(forKey: "sheep.supabase.session.v1"), "token")
        XCTAssertEqual(defaults.string(forKey: "com.apple.something"), "other")
    }

    func testResetAllClearsNotificationsStateAndMemory() {
        let state = AppState(defaults: defaults)
        state.progress.add(120)
        EventLog.shared.append(SheepEvent(type: .modeChange, mode: .rest))
        defaults.set("gentle", forKey: SheepSettings.Key.voice)
        var cleared = false
        AppReset.resetAll(state: state, defaults: defaults, clearNotifications: { cleared = true })
        XCTAssertTrue(cleared)
        XCTAssertEqual(state.progress.xp, 0)
        XCTAssertTrue(EventLog.shared.readAll().isEmpty)
        XCTAssertNil(defaults.object(forKey: SheepSettings.Key.voice))
    }

    // MARK: 6 · Rest brief

    private func at(_ h: Int, _ m: Int, dayOffset: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: .now))!
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }

    func testRestBriefFromTodaysPomodoros() {
        let events = [
            SheepEvent(ts: at(9, 0), type: .sessionStart, mode: .focus, title: "Ch.3", plannedMin: 75),
            SheepEvent(ts: at(10, 20), type: .sessionEnd, mode: .focus, actualMin: 80, done: 3, total: 3)
        ]
        let m = RestBrief.message(events: events, mutedApps: ["Teams", "Outlook"], rest: nil, fast: false, now: at(18, 0))
        XCTAssertEqual(m?.headline, "You did 3 Pomodoros. Switch off.")
        XCTAssertEqual(m?.body, "Teams and Outlook stay muted while you rest. Pick something restful and a time limit.")
        XCTAssertEqual(m?.caption, "Sheep says")
        XCTAssertTrue(m?.isFromMemory ?? false)
    }

    func testRestBriefPartialAndRunningActivity() {
        let events = [
            SheepEvent(ts: at(9, 0), type: .sessionStart, mode: .focus, plannedMin: 3),
            SheepEvent(ts: at(9, 3), type: .sessionEnd, mode: .focus, actualMin: 3, done: 1, total: 4)
        ]
        let rest = RestSession(activity: "netflix", limitMinutes: 60, startedAt: at(22, 0))
        let m = RestBrief.message(events: events, mutedApps: ["Teams", "Outlook", "Slack"], rest: rest, fast: false,
                                  now: at(22, 5))
        XCTAssertEqual(m?.headline, "You did 1 of 4 checklist items. Switch off.")
        XCTAssertEqual(m?.body, "Teams, Outlook and Slack stay muted while you rest. Netflix till 23:00, then bed.")
        let fast = RestBrief.message(events: events, mutedApps: [], rest: rest, fast: true, now: at(22, 5))
        XCTAssertEqual(fast?.body, "Netflix for 60 min.", "no invented clock time with compressed timers")
    }

    func testRestBriefNilWithoutFocusToday() {
        let yesterday = [SheepEvent(ts: at(10, 0, dayOffset: -1), type: .sessionEnd, mode: .focus, actualMin: 25, done: 1, total: 1)]
        XCTAssertNil(RestBrief.message(events: yesterday, mutedApps: ["Teams"], rest: nil, fast: false, now: at(18, 0)))
        XCTAssertNil(RestBrief.message(events: [], mutedApps: ["Teams"], rest: nil, fast: false, now: at(18, 0)))
        let restOnly = [SheepEvent(ts: at(12, 0), type: .restActivity, actualMin: 30, activity: "walk", limitMin: 30)]
        XCTAssertNil(RestBrief.message(events: restOnly, mutedApps: [], rest: nil, fast: false, now: at(18, 0)))
    }

    func testEmptyScoreCaption() {
        XCTAssertEqual(ScoreHeader.caption(score: 72, yesterday: 40), "today's score")
        XCTAssertEqual(ScoreHeader.caption(score: nil, yesterday: 40), "yesterday's score")
        XCTAssertEqual(ScoreHeader.caption(score: nil, yesterday: nil), "no score yet")
    }

    // MARK: 7 · Nudge template outside Focus

    func testNudgeTemplateSendsNAWithoutFocusSession() {
        let input = NudgeInput(mode: .rest, app: .instagram, section: .feed, activeMinutes: 2, nudgesThisSession: 0,
                               sessionTitle: nil, done: 0, total: 0, secondsLeft: nil, restActivity: "netflix",
                               restLimitMinutes: 45, now: .now)
        let text = NudgePrompt.user(input, memory: "MEM")
        XCTAssertTrue(text.contains("SESSION GOAL: rest — netflix, 45 min limit — checklist n/a done, n/a min left in Pomodoro"), text)
        XCTAssertFalse(text.contains("0 min left"))
    }

    // MARK: 8 · Daily score sync

    func testDailyScoreSyncDebouncesAndDeduplicates() async throws {
        var sent: [DailyScoreSync.Row] = []
        let sync = DailyScoreSync(debounce: .milliseconds(50)) { _, row in sent.append(row) }
        sync.submit(DayScore(focus: 40))
        sync.submit(DayScore(focus: 60))
        sync.submit(DayScore(focus: 80, rest: 100))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(sent.count, 1, "debounced to the last value")
        XCTAssertEqual(sent.first?.total, 90)
        XCTAssertEqual(sent.first?.focus, 80)
        XCTAssertEqual(sent.first?.play, 0)
        sync.submit(DayScore(focus: 80, rest: 100))
        sync.submit(DayScore())   // nothing scored → no row
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(sent.count, 1, "unchanged score isn't re-sent")
    }

    // MARK: 9 · Memory

    private func memoryFixtures() -> (MemoryStore, EventLog) {
        let store = MemoryStore(root: tmp.appendingPathComponent("memory"))
        let file = tmp.appendingPathComponent("memory/events.jsonl")
        return (store, EventLog(fileURL: { file }))
    }

    private var liveClient: GeminiClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGemini.self]
        return GeminiClient(apiKey: "test-key", model: "stub", session: URLSession(configuration: config))
    }

    func testEmptyLiveConsolidatorReplyFallsBackToOffline() async {
        let (store, log) = memoryFixtures()
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))   // log keeps whole seconds
        log.append(SheepEvent(ts: now.addingTimeInterval(-600), type: .sessionStart, mode: .focus, title: "Ch.3", plannedMin: 25))
        log.append(SheepEvent(ts: now.addingTimeInterval(-60), type: .sessionEnd, mode: .focus, actualMin: 9, done: 1, total: 1))
        StubGemini.reply = #"{"files":[],"learned":[]}"#
        let c = MemoryConsolidator(store: store, log: log, client: liveClient, defaults: defaults)
        _ = await c.run(reason: .sessionEnd, force: false, now: now)
        XCTAssertNotNil(store.read("timeline/daily/\(MemoryDates.day(now)).md"), "offline consolidator wrote today")
        XCTAssertEqual(c.lastRunAt, now.addingTimeInterval(-60))
    }

    func testUsableReplyCheck() {
        let (store, log) = memoryFixtures()
        let c = MemoryConsolidator(store: store, log: log, client: GeminiClient(apiKey: ""), defaults: defaults)
        XCTAssertFalse(c.isUsable(ConsolidatorResponse(files: [], learned: ["x"])))
        XCTAssertFalse(c.isUsable(ConsolidatorResponse(files: [.init(path: "../x.md", content: "y")], learned: [])))
        XCTAssertFalse(c.isUsable(ConsolidatorResponse(files: [.init(path: "notes/a.md", content: "  ")], learned: [])))
        XCTAssertFalse(c.isUsable(ConsolidatorResponse(files: [.init(path: "notes/a.txt", content: "y")], learned: [])))
        XCTAssertTrue(c.isUsable(ConsolidatorResponse(files: [.init(path: "notes/a.md", content: "y")], learned: [])))
    }

    func testSeededKnowledgeCountsMatchSeededEvents() {
        let (store, log) = memoryFixtures()
        let c = MemoryConsolidator(store: store, log: log, client: GeminiClient(apiKey: ""), defaults: defaults)
        let events = MemorySeeder.seedYesterday(store: store, log: log, consolidator: c)

        let works = WhatWorks.parse(store.read(OfflineConsolidator.whatWorksPath))
        let nudges = events.filter { $0.type == .nudge }
        XCTAssertEqual(works.stats.map(\.total).reduce(0, +), nudges.count)
        XCTAssertEqual(works.stats.map(\.back).reduce(0, +), nudges.filter { $0.outcome == "returned" }.count)
        XCTAssertTrue(works.notes.contains { $0.contains("Naming the deadline") })

        let patterns = Patterns.parse(store.read(OfflineConsolidator.patternsPath))
        let observations = Patterns.observations(in: events, all: events, calendar: cal)
        XCTAssertEqual(patterns.lines.map(\.count).reduce(0, +), observations.count)
        XCTAssertFalse(patterns.lines.isEmpty)
    }
}
