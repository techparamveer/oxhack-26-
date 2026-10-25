import XCTest
@testable import Sheep

@MainActor
final class InterventionTests: XCTestCase {
    final class Clock {
        var t = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ s: TimeInterval) { t += s }
    }

    var clock: Clock!
    var state: AppState!
    var monitor: ScrollMonitor!
    var log: EventLog!
    var inputs: [NudgeInput] = []
    var prefs: UserDefaults!

    override func setUp() {
        super.setUp()
        clock = Clock()
        state = AppState(defaults: UserDefaults(suiteName: "intervention-\(UUID())")!)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID()).jsonl")
        log = EventLog(fileURL: { url })
        inputs = []
        monitor = state.scrollMonitor
        monitor.now = { [unowned self] in self.clock.t }
        monitor.log = log
        monitor.autoResolve = false
        prefs = UserDefaults(suiteName: "intervention-prefs-\(UUID())")!
        monitor.preferences = prefs
        monitor.nudgeProvider = { [unowned self] input in
            await MainActor.run { self.inputs.append(input) }
            return NudgePrompt.fallback(input)
        }
    }

    // MARK: Helpers

    private func configure(_ mode: Mode, fast: Bool = true, session: Bool = true) {
        state.mode = mode
        state.fastTimers = fast
        if session {
            state.activeSession = FocusSession(
                answers: ["Finish intro", "800 words", "reels"], title: "Dissertation ch.3 intro",
                opener: "", watchOut: "", workstream: "dissertation",
                checklist: [ChecklistItem(text: "a", done: true), ChecklistItem(text: "b"), ChecklistItem(text: "c")],
                pomodoros: 3, pomodoroMinutes: fast ? 1 : 25, startedAt: clock.t)
        }
    }

    /// Feeds 5 s samples for `seconds` of active scrolling, then waits for any nudge call.
    private func scroll(_ seconds: Int, section: AppSection = .feed, mode: Mode? = nil) async {
        for _ in 0..<(seconds / 5) {
            clock.advance(5)
            monitor.ingest(ScrollSample(app: .instagram, section: section, path: "/", px: 800, activeSec: 5),
                           mode: mode ?? state.mode)
            await monitor.nudgeTask?.value
        }
    }

    private func nudges() -> [SheepEvent] { log.readAll().filter { $0.type == .nudge } }
    private func scrolls() -> [SheepEvent] { log.readAll().filter { $0.type == .scroll } }

    // MARK: Thresholds

    func testThresholdTable() {
        XCTAssertEqual(ScrollMonitor.threshold(mode: .focus, fast: true), 30)
        XCTAssertEqual(ScrollMonitor.threshold(mode: .focus, fast: false), 180)
        XCTAssertEqual(ScrollMonitor.threshold(mode: .rest, fast: true), 120)
        XCTAssertEqual(ScrollMonitor.threshold(mode: .rest, fast: false), 1800)
        XCTAssertNil(ScrollMonitor.threshold(mode: .play, fast: true))
        XCTAssertNil(ScrollMonitor.threshold(mode: .idle, fast: false))
    }

    func testFocusFastTriggersAt30Seconds() async {
        configure(.focus)
        await scroll(25)
        XCTAssertNil(monitor.pendingIntervention)
        await scroll(5)
        let req = monitor.pendingIntervention
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.mode, .focus)
        XCTAssertEqual(req?.nudge.primaryAction, .backToFocus)
        XCTAssertEqual(req?.nudge.tone, .firm)
        XCTAssertEqual(req?.activeMinutes ?? 0, 0.5, accuracy: 0.001)
    }

    func testFocusRealTriggersAt3Minutes() async {
        configure(.focus, fast: false)
        await scroll(175)
        XCTAssertNil(monitor.pendingIntervention)
        await scroll(5)
        XCTAssertNotNil(monitor.pendingIntervention)
    }

    func testRestFastTriggersAt2Minutes() async {
        configure(.rest, session: false)
        await scroll(115)
        XCTAssertNil(monitor.pendingIntervention)
        await scroll(5)
        XCTAssertEqual(monitor.pendingIntervention?.nudge.primaryAction, .takeBreak)
        XCTAssertEqual(monitor.pendingIntervention?.nudge.tone, .gentle)
    }

    func testRestRealTriggersAt30Minutes() async {
        configure(.rest, fast: false, session: false)
        await scroll(1795)
        XCTAssertNil(monitor.pendingIntervention)
        await scroll(5)
        XCTAssertNotNil(monitor.pendingIntervention)
    }

    func testNoInterventionInPlayOrIdle() async {
        for mode in [Mode.play, .idle] {
            configure(mode, session: false)
            await scroll(600)
            XCTAssertNil(monitor.pendingIntervention, "\(mode)")
            XCTAssertTrue(inputs.isEmpty)
        }
    }

    // MARK: Cooldown & streaks

    func testCooldownTwoMinutesBetweenInterventions() async {
        configure(.focus)
        await scroll(30)
        XCTAssertNotNil(monitor.pendingIntervention)
        monitor.userChose(.keepGoing)
        await scroll(115)                            // 115 s after the first nudge
        XCTAssertNil(monitor.pendingIntervention)
        XCTAssertEqual(nudges().map(\.outcome), ["ignored"])
        await scroll(5)                              // 120 s → allowed again
        XCTAssertNotNil(monitor.pendingIntervention)
        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(inputs[1].nudgesThisSession, 1)
    }

    func testStreakResetsOnGap() async {
        configure(.focus)
        await scroll(20)
        clock.advance(13)                             // > 12 s without a sample
        await scroll(15)
        XCTAssertNil(monitor.pendingIntervention)
        XCTAssertEqual(monitor.currentStreakSeconds, 15)
    }

    func testStreakResetsOnSectionNavigation() async {
        configure(.rest, session: false)
        await scroll(100)
        monitor.didNavigate(app: .instagram, section: .reels)
        await scroll(30, section: .reels)
        XCTAssertNil(monitor.pendingIntervention)
        XCTAssertEqual(monitor.currentStreakSeconds, 30)
    }

    func testSameSectionNavigationKeepsStreak() async {
        configure(.focus)
        await scroll(20)
        monitor.didNavigate(app: .instagram, section: .feed)
        await scroll(10)
        XCTAssertNotNil(monitor.pendingIntervention)
    }

    func testLeavingWrapperResetsStreak() async {
        configure(.focus)
        await scroll(25)
        monitor.didLeaveWrapper(app: .instagram)
        await scroll(10)
        XCTAssertNil(monitor.pendingIntervention)
    }

    // MARK: Outcomes, XP, events, counters

    func testReturnedWhenLeavingWrapperWithin60s() async {
        configure(.focus)
        state.progress.xp = 50
        await scroll(30)
        XCTAssertEqual(state.activeSession?.nudgeCount, 1)
        clock.advance(20)
        monitor.didLeaveWrapper(app: .instagram)
        XCTAssertNil(monitor.pendingIntervention)
        XCTAssertEqual(state.progress.xp, 50 + XPRules.resistedNudge)
        XCTAssertEqual(state.activeSession?.nudgesResisted, 1)
        let events = nudges()
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.app, .instagram)
        XCTAssertEqual(e.mode, .focus)
        XCTAssertEqual(e.tone, "firm")
        XCTAssertEqual(e.action, "back_to_focus")
        XCTAssertEqual(e.outcome, "returned")
        // Wrapper closing again doesn't double-log.
        monitor.didLeaveWrapper(app: .instagram)
        XCTAssertEqual(nudges().count, 1)
    }

    func testReturnedWhenTappingLeavingAction() async {
        configure(.focus)
        await scroll(30)
        monitor.userChose(.backToFocus)
        XCTAssertNil(monitor.pendingIntervention)
        XCTAssertEqual(nudges().map(\.outcome), ["returned"])
        XCTAssertEqual(state.progress.xp, XPRules.resistedNudge)
    }

    func testNavigatingToDMsCountsAsLeavingButReelsDoesNot() async {
        configure(.rest, session: false)
        await scroll(120)
        monitor.userChose(.keepGoing)
        monitor.didNavigate(app: .instagram, section: .reels)
        XCTAssertTrue(nudges().isEmpty)
        monitor.didNavigate(app: .instagram, section: .dms)
        XCTAssertEqual(nudges().map(\.outcome), ["returned"])
        XCTAssertEqual(nudges().first?.tone, "gentle")
        XCTAssertEqual(nudges().first?.action, "take_break")
        XCTAssertEqual(nudges().first?.mode, .rest)
    }

    func testIgnoredAfter60sOfKeepScrolling() async {
        configure(.focus)
        state.progress.xp = 50
        await scroll(30)
        monitor.userChose(.keepGoing)
        clock.advance(59)
        monitor.tick()
        XCTAssertTrue(nudges().isEmpty)
        clock.advance(1)
        monitor.tick()
        XCTAssertEqual(nudges().map(\.outcome), ["ignored"])
        XCTAssertEqual(state.progress.xp, 50 + XPRules.ignoredNudge)
        XCTAssertEqual(state.activeSession?.nudgeCount, 1)
        XCTAssertEqual(state.activeSession?.nudgesResisted, 0)
        // Leaving later doesn't flip it.
        monitor.didLeaveWrapper(app: .instagram)
        XCTAssertEqual(nudges().count, 1)
        XCTAssertEqual(state.progress.xp, 50 + XPRules.ignoredNudge)
    }

    func testLeavingAfter60sIsIgnored() async {
        configure(.focus)
        await scroll(30)
        monitor.userChose(.keepGoing)
        clock.advance(61)
        monitor.didLeaveWrapper(app: .instagram)
        XCTAssertEqual(nudges().map(\.outcome), ["ignored"])
    }

    func testOverlayStillUpDoesNotAutoIgnore() async {
        configure(.focus)
        await scroll(30)
        clock.advance(90)
        monitor.tick()
        XCTAssertTrue(nudges().isEmpty)
        XCTAssertNotNil(monitor.pendingIntervention)
        monitor.userChose(.keepGoing)                // now dismissed after the window → ignored
        XCTAssertEqual(nudges().map(\.outcome), ["ignored"])
    }

    func testNudgeInputCarriesSessionContext() async {
        configure(.focus)
        clock.advance(20)                            // 20 s into a 1-min Pomodoro before scrolling
        await scroll(30)
        let input = try! XCTUnwrap(inputs.first)
        XCTAssertEqual(input.sessionTitle, "Dissertation ch.3 intro")
        XCTAssertEqual(input.done, 1)
        XCTAssertEqual(input.total, 3)
        XCTAssertEqual(input.section, .feed)
        XCTAssertEqual(input.nudgesThisSession, 0)
        XCTAssertEqual(input.secondsLeft, 10)         // 50 s into a 1-min Pomodoro → 10 s left
    }

    // MARK: Scroll accounting

    func testScrollSecondsAndAggregatedScrollEvent() async {
        configure(.play, session: true)
        await scroll(20)
        XCTAssertEqual(state.activeSession?.scrollSeconds, 0, "only counted in Focus")
        monitor.didLeaveWrapper(app: .instagram)
        XCTAssertTrue(scrolls().isEmpty, "< 30 s streaks aren't logged")

        configure(.focus)
        await scroll(25)
        XCTAssertEqual(state.activeSession?.scrollSeconds, 25)
        XCTAssertTrue(scrolls().isEmpty, "never per sample")
        monitor.didNavigate(app: .instagram, section: .reels)   // streak ends at 25 s → not logged
        await scroll(45, section: .reels)
        monitor.didLeaveWrapper(app: .instagram)
        let events = scrolls()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].app, .instagram)
        XCTAssertEqual(events[0].section, .reels)
        XCTAssertEqual(events[0].mode, .focus)
        XCTAssertEqual(events[0].activeMin ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(state.activeSession?.scrollSeconds, 70)
    }

    func testGapEndsStreakAndLogsScroll() async {
        configure(.idle, session: false)
        await scroll(60)
        clock.advance(30)
        monitor.tick()
        XCTAssertEqual(scrolls().count, 1)
        XCTAssertEqual(scrolls().first?.activeMin, 1)
    }

    // MARK: Prompt & fallback

    private func input(_ mode: Mode, minutes: Double = 3, secondsLeft: Int = 12 * 60) -> NudgeInput {
        NudgeInput(mode: mode, app: .instagram, section: .feed, activeMinutes: minutes, nudgesThisSession: 1,
                   sessionTitle: mode == .focus ? "Dissertation ch.3 intro" : nil, done: 1, total: 3,
                   secondsLeft: mode == .focus ? secondsLeft : nil,
                   restActivity: mode == .rest ? "netflix" : nil, restLimitMinutes: mode == .rest ? 45 : nil,
                   now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testFocusFallbackNamesGoalAndMinutes() {
        let n = NudgePrompt.fallback(input(.focus))
        XCTAssertTrue(n.message.contains("Dissertation ch.3 intro"), n.message)
        XCTAssertTrue(n.message.contains("3 min"), n.message)
        XCTAssertTrue(n.message.contains("12 min left"), n.message)
        XCTAssertEqual(n.primaryAction, .backToFocus)
        XCTAssertEqual(n.tone, .firm)
    }

    func testFastFallbackUsesSeconds() {
        let n = NudgePrompt.fallback(input(.focus, minutes: 0.5))
        XCTAssertTrue(n.message.contains("30 seconds"), n.message)
    }

    /// ~30 s left must not read "1 min left" (the acceptance run's fast-timer nudge).
    func testUnderAMinuteLeftCopy() {
        let n = NudgePrompt.fallback(input(.focus, minutes: 0.5, secondsLeft: 30))
        XCTAssertTrue(n.message.hasSuffix("Under a minute left in this pomodoro."), n.message)
        XCTAssertFalse(n.message.contains("1 min left"), n.message)
        let text = NudgePrompt.user(input(.focus, minutes: 0.5, secondsLeft: 30), memory: "MEM")
        XCTAssertTrue(text.contains("checklist 1/3 done, under a minute left in Pomodoro"), text)
        // Pomodoros all elapsed: no time-left sentence in the fallback, "0 min" for the model.
        XCTAssertFalse(NudgePrompt.fallback(input(.focus, secondsLeft: 0)).message.contains("left in this"))
        XCTAssertTrue(NudgePrompt.user(input(.focus, secondsLeft: 0), memory: "").contains("done, 0 min left in Pomodoro"))
    }

    func testTimeLeftRoundsToNearestMinute() {
        XCTAssertNil(NudgePrompt.displayMinutes(secondsLeft: 59))
        XCTAssertEqual(NudgePrompt.displayMinutes(secondsLeft: 60), 1)
        XCTAssertEqual(NudgePrompt.displayMinutes(secondsLeft: 89), 1)
        XCTAssertEqual(NudgePrompt.displayMinutes(secondsLeft: 90), 2)
        XCTAssertEqual(NudgePrompt.displayMinutes(secondsLeft: 12 * 60 + 20), 12)
        XCTAssertEqual(NudgePrompt.fallbackTimeLeft(150), " 3 min left in this pomodoro.")
        XCTAssertEqual(NudgePrompt.fallbackTimeLeft(nil), "")
        XCTAssertEqual(NudgePrompt.promptTimeLeft(nil), "n/a min")
    }

    func testRestFallbackIsGentleAndNamesPlan() {
        let n = NudgePrompt.fallback(input(.rest, minutes: 2))
        XCTAssertTrue(n.message.contains("2 min"), n.message)
        XCTAssertTrue(n.message.contains("45 min of netflix"), n.message)
        XCTAssertEqual(n.primaryAction, .takeBreak)
        XCTAssertEqual(n.tone, .gentle)
    }

    func testUserTemplateFill() {
        let text = NudgePrompt.user(input(.focus, minutes: 0.5), memory: "MEM")
        XCTAssertTrue(text.contains("MODE: focus"))
        XCTAssertTrue(text.contains("APP: instagram  SECTION: feed"))
        XCTAssertTrue(text.contains("SCROLLED: 0.5 min continuous, 1 nudges already this session"))
        XCTAssertTrue(text.contains("SESSION GOAL: Dissertation ch.3 intro — checklist 1/3 done, 12 min left in Pomodoro"))
        XCTAssertTrue(text.contains("MEMORY:\nMEM"))
        let p = NudgePrompt.prompt(input(.focus), memory: "MEM")
        XCTAssertEqual(p.temperature, 0.9)
        XCTAssertTrue(p.usePersona)
    }

    func testNudgeDecodesFromSchemaShapedJSON() throws {
        let json = #"{"headline":"h","message":"m","primaryAction":"close_app","primaryLabel":"close","tone":"data"}"#
        let n = try JSONDecoder().decode(Nudge.self, from: Data(json.utf8))
        XCTAssertEqual(n.primaryAction, .closeApp)
        XCTAssertEqual(n.tone, .data)
    }

    func testGentleVoiceSoftensFallbackAndTagsTemplate() async {
        var i = input(.focus)
        XCTAssertFalse(NudgePrompt.user(i, memory: "").contains("VOICE"))
        i.voice = .gentle
        XCTAssertTrue(NudgePrompt.user(i, memory: "").contains("\nVOICE: gentle\nMEMORY:"))
        let n = NudgePrompt.fallback(i)
        XCTAssertEqual(n.tone, .gentle)
        XCTAssertEqual(n.primaryAction, .backToFocus)
        XCTAssertTrue(n.message.contains("Dissertation ch.3 intro") && n.message.contains("3 min"), n.message)

        prefs.set("gentle", forKey: NudgePrompt.Voice.defaultsKey)
        configure(.focus)
        await scroll(30)
        XCTAssertEqual(inputs.first?.voice, .gentle)
        XCTAssertEqual(monitor.pendingIntervention?.nudge.tone, .gentle)
    }

    func testVoiceDefaultsToLockIn() {
        XCTAssertEqual(NudgePrompt.Voice.current(prefs), .lockIn)
        prefs.set("nonsense", forKey: NudgePrompt.Voice.defaultsKey)
        XCTAssertEqual(NudgePrompt.Voice.current(prefs), .lockIn)
    }

    func testMinutesLeftInPomodoro() {
        let start = Date(timeIntervalSince1970: 0)
        var s = FocusSession(answers: [], title: "t", opener: "", watchOut: "", workstream: "", checklist: [],
                             pomodoros: 2, pomodoroMinutes: 25, startedAt: start)
        XCTAssertEqual(NudgePrompt.secondsLeftInPomodoro(s, now: start + 10 * 60), 15 * 60)
        XCTAssertEqual(NudgePrompt.secondsLeftInPomodoro(s, now: start + 30 * 60), 20 * 60)
        XCTAssertEqual(NudgePrompt.secondsLeftInPomodoro(s, now: start + 60 * 60), 0)
        s.pomodoroMinutes = 1
        XCTAssertEqual(NudgePrompt.secondsLeftInPomodoro(s, now: start + 30), 30)
        XCTAssertEqual(NudgePrompt.secondsLeftInPomodoro(s, now: start + 29.4), 31)   // rounded up
    }
}
