import XCTest
@testable import Sheep

final class DayScoreTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func focusSession(day: Int, hour: Int, planned: Int, actual: Double, done: Int, total: Int,
                              nudges: [String] = []) -> [SheepEvent] {
        var events = [SheepEvent(ts: at(day, hour), type: .sessionStart, mode: .focus, title: "Ch.3", plannedMin: planned)]
        for (i, outcome) in nudges.enumerated() {
            events.append(SheepEvent(ts: at(day, hour, 5 + i), type: .nudge, app: .instagram, outcome: outcome))
        }
        events.append(SheepEvent(ts: at(day, hour, 50), type: .sessionEnd, mode: .focus,
                                 actualMin: actual, done: done, total: total))
        return events
    }

    func testEmptyDayIsNil() {
        let score = DayScore.compute(events: [], day: at(24, 12), calendar: calendar)
        XCTAssertNil(score.focus); XCTAssertNil(score.rest); XCTAssertNil(score.play); XCTAssertNil(score.total)
    }

    func testPerfectFocusSessionIs100() {
        let events = focusSession(day: 24, hour: 9, planned: 75, actual: 80, done: 3, total: 3)
        XCTAssertEqual(DayScore.compute(events: events, day: at(24, 12), calendar: calendar).focus, 100)
    }

    func testFocusFormulaWithNudges() {
        // 0.5 × 1/3 + 0.3 × 50/75 + 0.2 × 1/2 = 0.1667 + 0.2 + 0.1 = 0.4667 → 47
        let events = focusSession(day: 24, hour: 9, planned: 75, actual: 50, done: 1, total: 3,
                                  nudges: ["ignored", "returned"])
        XCTAssertEqual(DayScore.compute(events: events, day: at(24, 12), calendar: calendar).focus, 47)
    }

    func testFocusAveragesMultipleSessionsAndResetsNudgesPerSession() {
        // A: 100. B: 0.5 × 0 + 0.3 × 1 + 0.2 × 0 = 30. Mean 65.
        let a = focusSession(day: 24, hour: 9, planned: 25, actual: 25, done: 3, total: 3)
        let b = focusSession(day: 24, hour: 14, planned: 25, actual: 30, done: 0, total: 3, nudges: ["ignored"])
        let score = DayScore.compute(events: b + a, day: at(24, 20), calendar: calendar) // unsorted input
        XCTAssertEqual(score.focus, 65)
    }

    func testFocusSessionWithoutEndIsIgnored() {
        let start = SheepEvent(ts: at(24, 9), type: .sessionStart, mode: .focus, plannedMin: 75)
        XCTAssertNil(DayScore.compute(events: [start], day: at(24, 12), calendar: calendar).focus)
    }

    func testRestAndPlayLimitScores() {
        let events = [
            SheepEvent(ts: at(24, 22), type: .restActivity, actualMin: 110, activity: "netflix", limitMin: 45),
            SheepEvent(ts: at(24, 23), type: .restActivity, actualMin: 20, activity: "walk", limitMin: 30),
            SheepEvent(ts: at(24, 18), type: .playSession, actualMin: 60, limitMin: 60),
            SheepEvent(ts: at(24, 19), type: .restActivity, activity: "started", limitMin: 30), // no actual → skipped
        ]
        let score = DayScore.compute(events: events, day: at(24, 12), calendar: calendar)
        // netflix 45/110 = 40.9 → 41; walk → 100; mean 70.5 → 71 (banker's? no: .rounded() = schoolbook)
        XCTAssertEqual(score.rest, 71)
        XCTAssertEqual(score.play, 100)
        XCTAssertNil(score.focus)
        XCTAssertEqual(score.total, 86) // (71 + 100) / 2 = 85.5 → 86
    }

    func testOnlyEventsOnThatDayCount() {
        let yesterday = focusSession(day: 23, hour: 21, planned: 75, actual: 75, done: 1, total: 3, nudges: ["ignored"])
        let today = [SheepEvent(ts: at(24, 10), type: .playSession, actualMin: 60, limitMin: 30)]
        let score = DayScore.compute(events: yesterday + today, day: at(24, 12), calendar: calendar)
        XCTAssertNil(score.focus)
        XCTAssertEqual(score.play, 50)
    }

    func testSessionStartedBeforeMidnightPairsWithEndAfter() {
        let events = [
            SheepEvent(ts: at(23, 23, 30), type: .sessionStart, mode: .focus, plannedMin: 60),
            SheepEvent(ts: at(24, 0, 30), type: .sessionEnd, mode: .focus, actualMin: 30, done: 2, total: 2),
        ]
        // 0.5 + 0.3 × 0.5 + 0.2 = 0.85
        XCTAssertEqual(DayScore.compute(events: events, day: at(24, 12), calendar: calendar).focus, 85)
        XCTAssertNil(DayScore.compute(events: events, day: at(23, 12), calendar: calendar).focus)
    }

    func testDeltaVsSeededYesterday() {
        // Seed-yesterday style: 1 of 3 pomodoros, Reels got you, Netflix overran.
        var events = focusSession(day: 23, hour: 21, planned: 75, actual: 75, done: 1, total: 3, nudges: ["ignored"])
        events.append(SheepEvent(ts: at(23, 22, 40), type: .restActivity, actualMin: 110, activity: "netflix", limitMin: 45))
        events += focusSession(day: 24, hour: 9, planned: 75, actual: 75, done: 3, total: 3, nudges: ["returned"])

        let result = DayScore.today(events: events, now: at(24, 12), calendar: calendar)
        // Yesterday: focus 0.5/3 + 0.3 + 0 = 0.4667 → 47; rest 41; total 44. Today: 100.
        XCTAssertEqual(result.score.total, 100)
        XCTAssertEqual(result.delta, 56)
    }

    func testDeltaNilWhenEitherDayMissing() {
        let events = focusSession(day: 24, hour: 9, planned: 75, actual: 75, done: 3, total: 3)
        XCTAssertNil(DayScore.today(events: events, now: at(24, 12), calendar: calendar).delta)
        XCTAssertNil(DayScore.today(events: events, now: at(25, 12), calendar: calendar).delta) // today empty
    }

    func testScoreForModeAndDeltaText() {
        let s = DayScore(focus: 80, rest: nil, play: 60)
        XCTAssertEqual(s.score(for: .focus), 80)
        XCTAssertNil(s.score(for: .rest))
        XCTAssertEqual(s.score(for: .idle), 70)
        XCTAssertEqual(ScoreHeader.deltaText(6), "▲ 6")
        XCTAssertEqual(ScoreHeader.deltaText(-4), "▼ 4")
    }
}

final class SettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "sheep.tests.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaults() {
        let s = SheepSettings(defaults: defaults)
        XCTAssertEqual(s.voice, .lockIn)
        XCTAssertTrue(s.askBeforeActing)
        XCTAssertEqual(s.pomodoroMinutes, 25)
        XCTAssertEqual(s.blockedInFocus, [.reels, .dms, .explore, .shorts])
        XCTAssertTrue(s.blocked(in: .rest).isEmpty)
        XCTAssertTrue(s.blocked(in: .play).isEmpty)
        XCTAssertTrue(s.blocked(in: .idle).isEmpty)
        XCTAssertEqual(s.mutedWorkApps, ["Teams", "Outlook", "Slack"])
        XCTAssertEqual(s.shortcutsDoneCount, 0)
        XCTAssertEqual(s.blockedSummary, "Focus: Reels, DMs +2")
        XCTAssertLessThanOrEqual(s.blockedSummary.count, 20)
        XCTAssertEqual(s.mutedSummary, "3 apps")
        s.toggleMuted("Slack")
        XCTAssertEqual(s.mutedSummary, "Teams, Outlook")
    }

    func testRoundTripUsesSharedKeys() {
        let s = SheepSettings(defaults: defaults)
        s.voice = .gentle
        s.askBeforeActing = false
        s.pomodoroMinutes = 50
        s.toggleBlocked(.dms)
        s.toggleMuted("Slack")

        XCTAssertEqual(defaults.string(forKey: "sheep.voice"), "gentle")
        XCTAssertEqual(defaults.object(forKey: "sheep.askBeforeActing") as? Bool, false)
        XCTAssertEqual(defaults.integer(forKey: "sheep.pomodoroMinutes"), 50)
        XCTAssertEqual(defaults.stringArray(forKey: "sheep.blockedInFocus"), ["explore", "reels", "shorts"])
        XCTAssertEqual(defaults.stringArray(forKey: "sheep.mutedWorkApps"), ["Teams", "Outlook"])

        let reloaded = SheepSettings(defaults: defaults)
        XCTAssertEqual(reloaded.voice, .gentle)
        XCTAssertFalse(reloaded.askBeforeActing)
        XCTAssertEqual(reloaded.pomodoroMinutes, 50)
        XCTAssertEqual(reloaded.blockedInFocus, [.reels, .explore, .shorts])
        XCTAssertEqual(reloaded.mutedWorkApps, ["Teams", "Outlook"])
    }

    func testToggleBackKeepsCanonicalOrder() {
        let s = SheepSettings(defaults: defaults)
        s.toggleBlocked(.reels)
        s.toggleBlocked(.reels)
        XCTAssertEqual(s.blockedInFocus, [.reels, .dms, .explore, .shorts])
        s.toggleMuted("Teams"); s.toggleMuted("Teams")
        XCTAssertEqual(s.mutedWorkApps, ["Teams", "Outlook", "Slack"])
    }

    func testPerModeTogglePersistsAndReloadReadsNewKeys() {
        let s = SheepSettings(defaults: defaults)
        XCTAssertFalse(s.isBlocked(.reels, in: .rest))
        XCTAssertFalse(s.isBlocked(.dms, in: .rest))
        s.toggleBlocked(.dms, in: .rest)
        s.toggleBlocked(.reels, in: .rest)
        XCTAssertTrue(s.isBlocked(.dms, in: .rest))
        XCTAssertTrue(s.isBlocked(.reels, in: .rest))
        XCTAssertEqual(defaults.stringArray(forKey: "sheep.blockedInRest"), ["dms", "reels"])
        XCTAssertEqual(defaults.stringArray(forKey: "sheep.blockedInFocus"), nil,
                       "Focus key stays unset until Focus is edited")

        s.toggleBlocked(.explore, in: .play)
        XCTAssertEqual(defaults.stringArray(forKey: "sheep.blockedInPlay"), ["explore"])

        s.reload()
        XCTAssertEqual(s.blocked(in: .rest), [.reels, .dms])
        XCTAssertEqual(s.blocked(in: .play), [.explore])
        XCTAssertEqual(s.blockedInFocus, [.reels, .dms, .explore, .shorts])
    }

    func testInvalidPomodoroFallsBackTo25AndEmptyBlockedIsRespected() {
        defaults.set(40, forKey: "sheep.pomodoroMinutes")
        defaults.set([String](), forKey: "sheep.blockedInFocus")
        let s = SheepSettings(defaults: defaults)
        XCTAssertEqual(s.pomodoroMinutes, 25)
        XCTAssertEqual(s.blockedInFocus, [])
        XCTAssertEqual(s.blockedSummary, "Focus: none")
    }

    /// The row shows what Focus will actually plan; fast timers don't overwrite the stored choice.
    @MainActor func testPomodoroRowShowsEffectiveLengthWithFastTimers() {
        let s = SheepSettings(defaults: defaults)
        s.pomodoroMinutes = 50
        XCTAssertEqual(SheepSettings.pomodoroRowValue(stored: s.pomodoroMinutes, fastTimers: false), "50 min")
        XCTAssertEqual(SheepSettings.pomodoroRowValue(stored: s.pomodoroMinutes, fastTimers: true), "1 min · fast timers")
        XCTAssertEqual(SheepSettings(defaults: defaults).pomodoroMinutes, 50)
        // Matches the length FocusController really uses.
        let state = AppState(defaults: defaults)
        state.fastTimers = true
        XCTAssertEqual(FocusController.pomodoroMinutes(state: state, defaults: defaults), 1)
    }
}

final class HomePrimaryTests: XCTestCase {
    func testTitlesPerModeAndSessionState() {
        let idle = HomePrimary.Running()
        XCTAssertEqual(HomePrimary.title(for: .focus, running: idle), "Start focus")
        XCTAssertEqual(HomePrimary.title(for: .rest, running: idle), "Start rest")
        XCTAssertEqual(HomePrimary.title(for: .play, running: idle), "Start playing")

        XCTAssertEqual(HomePrimary.title(for: .focus, running: .init(focus: true)), "Back to focus")
        XCTAssertEqual(HomePrimary.title(for: .rest, running: .init(rest: true)), "Back to rest")
        XCTAssertEqual(HomePrimary.title(for: .play, running: .init(play: true)), "Back to play")
        // A running Focus session is never ended from Home: other pills only preview.
        XCTAssertEqual(HomePrimary.title(for: .rest, running: .init(focus: true)), "Back to focus")
        XCTAssertEqual(HomePrimary.title(for: .play, running: .init(focus: true)), "Back to focus")
    }

    func testFocusRunningKeepsBackToFocusAndEndsNothing() {
        for pick in Mode.allCases {
            let plan = HomePrimary.plan(for: pick, running: .init(focus: true))
            XCTAssertEqual(plan, .init(mode: .focus, title: "Back to focus", end: nil, route: .focusSession), "\(pick)")
        }
    }

    func testSwitchingBetweenRestAndPlayEndsTheOtherFirst() {
        XCTAssertEqual(HomePrimary.plan(for: .rest, running: .init(play: true)),
                       .init(mode: .rest, title: "Start rest", end: .play, route: .rest))
        XCTAssertEqual(HomePrimary.plan(for: .play, running: .init(rest: true)),
                       .init(mode: .play, title: "Start playing", end: .rest, route: .play))
        XCTAssertEqual(HomePrimary.plan(for: .focus, running: .init(rest: true)),
                       .init(mode: .focus, title: "Start focus", end: .rest, route: .focusIntake))
        // Same mode running: just go back to it, nothing ends.
        XCTAssertEqual(HomePrimary.plan(for: .rest, running: .init(rest: true)),
                       .init(mode: .rest, title: "Back to rest", end: nil, route: .rest))
        XCTAssertNil(HomePrimary.plan(for: .idle, running: .init()).end)
    }

    func testFirstDayBriefDoesNotRepeatCaption() {
        let noon = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let msg = HomeMessage.brief(headline: "How to start", body: "Tap Focus.", isFromMemory: false, now: noon)
        XCTAssertEqual(msg?.headline, "Morning. Ready to lock in?")
        XCTAssertEqual(msg?.caption, "How to start")
        XCTAssertEqual(HomeMessage.brief(headline: "Lock in.", body: "x", isFromMemory: true)?.caption, "Sheep says")
    }

    func testShortcutsDoneWritesTheKeySettingsReads() {
        let name = "sheep.tests.shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SheepSettings(defaults: defaults).shortcutsDoneCount, 0)
        ShortcutsDone.set(ShortcutsDone.restSilences, on: true, defaults: defaults)
        ShortcutsDone.set(ShortcutsDone.openInSheep, on: true, defaults: defaults)
        ShortcutsDone.set(ShortcutsDone.openInSheep, on: true, defaults: defaults)
        XCTAssertEqual(ShortcutsDone.ids(defaults: defaults), [ShortcutsDone.openInSheep, ShortcutsDone.restSilences])
        XCTAssertEqual(SheepSettings(defaults: defaults).shortcutsDoneCount, 2)
        ShortcutsDone.set(ShortcutsDone.openInSheep, on: false, defaults: defaults)
        XCTAssertEqual(SheepSettings(defaults: defaults).shortcutsDoneCount, 1)
    }

    func testRoutes() {
        XCTAssertEqual(HomePrimary.route(for: .focus, running: .init()), .focusIntake)
        XCTAssertEqual(HomePrimary.route(for: .focus, running: .init(focus: true)), .focusSession)
        XCTAssertEqual(HomePrimary.route(for: .rest, running: .init()), .rest)
        XCTAssertEqual(HomePrimary.route(for: .play, running: .init()), .play)
    }

    func testHowToCopyAlwaysSaysWhatToDo() {
        let focus = HomeMessage.howTo(for: .focus, running: false)
        XCTAssertEqual(focus.body, "Tap Focus, tell me the goal, and I'll plan 3 pomodoros and hide Reels.")
        XCTAssertEqual(focus.caption, "How to start")
        XCTAssertFalse(focus.isFromMemory)
        XCTAssertEqual(HomeMessage.howTo(for: .rest, running: false).body,
                       "Pick something restful and a time limit. DMs open up; I'll only nudge if you overrun.")
        XCTAssertEqual(HomeMessage.howTo(for: .play, running: false).body,
                       "Set a play limit. Work apps stay muted; you earn XP for stopping on time.")
        let brief = HomeMessage.fromMemory(headline: "Lock in.", body: "Yesterday: 1/3.")
        XCTAssertEqual(brief.meta, "from memory")
        XCTAssertTrue(brief.isFromMemory)
    }

    func testAppsCaptionsFromPolicy() {
        let focusBlocks: (WrappedApp, String, Mode) -> Bool = { _, path, mode in
            mode != .focus || !(path.hasPrefix("/reels") || path.hasPrefix("/direct") || path.hasPrefix("/shorts"))
        }
        XCTAssertEqual(AppsCaption.wrapped(app: .instagram, mode: .focus, isAllowed: focusBlocks), "Reels and DMs hidden")
        XCTAssertEqual(AppsCaption.wrapped(app: .youtube, mode: .focus, isAllowed: focusBlocks), "Shorts hidden")
        XCTAssertEqual(AppsCaption.wrapped(app: .instagram, mode: .rest, isAllowed: focusBlocks), "Everything open in Rest")
        XCTAssertEqual(AppsCaption.wrapped(app: .youtube, mode: .idle, isAllowed: focusBlocks), "In Focus: Shorts hidden")
        XCTAssertEqual(AppsCaption.work(muted: true, mode: .play), "Muted now")
        XCTAssertEqual(AppsCaption.work(muted: true, mode: .focus), "Muted in Rest & Play")
        XCTAssertEqual(AppsCaption.work(muted: false, mode: .rest), "Not muted")
    }
}
