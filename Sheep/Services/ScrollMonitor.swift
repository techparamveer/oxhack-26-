import Foundation
import Observation

/// A scroll report posted by inject.js every 5 s: `{type:"scroll", px, activeSec, path}`.
struct ScrollSample: Equatable {
    var app: WrappedApp
    var section: AppSection
    var path: String
    var px: Double
    var activeSec: Double
    var at: Date = .now
}

/// What the overlay is showing. Carries the decoded nudge (live or fallback).
struct InterventionRequest: Identifiable, Equatable {
    var id = UUID()
    var app: WrappedApp
    var section: AppSection
    var activeMinutes: Double
    var mode: Mode
    var nudge = Nudge(headline: "still scrolling?", message: "", primaryAction: .keepGoing,
                      primaryLabel: "ok", tone: .gentle)
    var shownAt: Date = .now
}

/// Consumes scroll samples from wrappers and decides when to intervene (MVP_PLAN "Wrapper mechanics").
///
/// - A *streak* is continuous active scrolling in one app section. It breaks when no sample arrives
///   for > `gapLimit` seconds, the user navigates to a different section, or leaves the wrapper.
///   When a streak with ≥ 30 s of activity ends, one aggregated `scroll` event is logged.
/// - When a streak's activity crosses the mode threshold (and the cooldown has passed) the nudge
///   prompt runs and `pendingIntervention` is set; WrapperView overlays `InterventionOverlay`.
/// - Each nudge resolves once: `returned` if the user leaves the feed/wrapper (or taps a leaving
///   action) within 60 s, else `ignored`. Resolution logs ONE `nudge` event and applies XP.
///
/// Uses `now()` as its only clock (sample `at` is ignored) so tests can drive time.
@Observable
final class ScrollMonitor {
    /// Set when an intervention should be shown; WrapperView presents `InterventionOverlay` for it.
    var pendingIntervention: InterventionRequest?

    // MARK: Tunables

    static let cooldown: TimeInterval = 120
    static let gapLimit: TimeInterval = 12
    static let outcomeWindow: TimeInterval = 60
    static let minLoggedStreak: TimeInterval = 30

    /// Continuous active seconds before intervening; nil = never (Play / Idle).
    static func threshold(mode: Mode, fast: Bool) -> TimeInterval? {
        switch mode {
        case .focus: fast ? 30 : 3 * 60
        case .rest: fast ? 2 * 60 : 30 * 60
        case .play, .idle: nil
        }
    }

    // MARK: Dependencies (injectable for tests)

    @ObservationIgnored weak var state: AppState?
    @ObservationIgnored var now: () -> Date = { .now }
    @ObservationIgnored var log: EventLog = .shared
    @ObservationIgnored var nudgeProvider: (NudgeInput) async -> Nudge = { await NudgePrompt.generate($0) }
    /// Schedules the 60 s outcome timer in real time. Tests turn it off and call `tick()`.
    @ObservationIgnored var autoResolve = true
    /// Where the Settings "Voice" preference (`sheep.voice`) is read from.
    @ObservationIgnored var preferences: UserDefaults = .standard

    func attach(_ state: AppState) { self.state = state }

    // MARK: Internal state

    private struct Streak {
        var app: WrappedApp
        var section: AppSection
        var mode: Mode
        var lastSampleAt: Date
        var activeSec: Double = 0
        var activeSinceNudge: Double = 0
    }

    private struct ActiveNudge {
        var request: InterventionRequest
        var shownAt: Date
    }

    @ObservationIgnored private var streak: Streak?
    @ObservationIgnored private var lastInterventionAt: Date?
    @ObservationIgnored private var active: ActiveNudge?
    @ObservationIgnored private var requestToken: UUID?
    @ObservationIgnored private var outcomeTimer: Task<Void, Never>?
    /// The in-flight nudge request (tests `await` it).
    @ObservationIgnored private(set) var nudgeTask: Task<Void, Never>?

    /// Seconds of the current streak (for debugging / tests).
    var currentStreakSeconds: Double { streak?.activeSec ?? 0 }
    var hasUnresolvedNudge: Bool { active != nil }

    // MARK: Inputs from the wrapper

    func ingest(_ sample: ScrollSample, mode: Mode) {
        tick()
        guard sample.px > 0, sample.activeSec > 0 else { return }
        let t = now()
        let secs = min(sample.activeSec, 15)

        if var s = streak, s.app == sample.app, s.section == sample.section,
           t.timeIntervalSince(s.lastSampleAt) <= Self.gapLimit {
            s.activeSec += secs
            s.activeSinceNudge += secs
            s.lastSampleAt = t
            s.mode = mode
            streak = s
        } else {
            endStreak()
            streak = Streak(app: sample.app, section: sample.section, mode: mode, lastSampleAt: t,
                            activeSec: secs, activeSinceNudge: secs)
        }

        if mode == .focus, state?.activeSession != nil {
            state?.activeSession?.scrollSeconds += secs
        }

        maybeIntervene(mode: mode, at: t)
    }

    /// Called when the user navigates to a new path.
    func didNavigate(app: WrappedApp, section: AppSection) {
        tick()
        if let s = streak, s.app != app || s.section != section {
            endStreak()
            requestToken = nil
        }
        // Leaving the feed counts as "returned" — but hopping to Reels/Shorts doesn't.
        if active != nil, section == .dms {
            resolve(.returned)
        }
    }

    func didLeaveWrapper(app: WrappedApp) {
        tick()
        endStreak()
        requestToken = nil
        nudgeTask = nil
        if active != nil { resolve(.returned) }
        pendingIntervention = nil
    }

    /// The overlay's buttons. Leaving actions resolve as `returned`; `keep_going` just dismisses
    /// (the outcome is decided by what the user does in the next 60 s).
    func userChose(_ action: NudgeAction) {
        pendingIntervention = nil
        guard action.leaves else { tick(); return }
        endStreak()
        if active != nil { resolve(.returned) }
    }

    /// Resolves an open nudge as `ignored` once its 60 s window has passed with the overlay dismissed.
    /// While the overlay is still up the user isn't scrolling, so the button decides the outcome.
    func tick() {
        let t = now()
        if let s = streak, t.timeIntervalSince(s.lastSampleAt) > Self.gapLimit { endStreak() }
        if let a = active, pendingIntervention?.id != a.request.id,
           t.timeIntervalSince(a.shownAt) >= Self.outcomeWindow {
            resolve(.ignored)
        }
    }

    // MARK: Intervention

    private func maybeIntervene(mode: Mode, at t: Date) {
        guard let s = streak,
              let limit = Self.threshold(mode: mode, fast: state?.fastTimers ?? true),
              s.activeSinceNudge >= limit,
              pendingIntervention == nil, active == nil, requestToken == nil else { return }
        if let last = lastInterventionAt, t.timeIntervalSince(last) < Self.cooldown { return }

        lastInterventionAt = t
        streak?.activeSinceNudge = 0
        let input = makeInput(mode: mode, streak: s, at: t)
        let token = UUID()
        requestToken = token
        let provider = nudgeProvider
        nudgeTask = Task { @MainActor [weak self] in
            let nudge = await provider(input)
            self?.present(nudge, input: input, token: token)
        }
    }

    private func present(_ nudge: Nudge, input: NudgeInput, token: UUID) {
        guard requestToken == token else { return }   // user left while Gemini was thinking
        requestToken = nil
        let shownAt = now()
        let request = InterventionRequest(app: input.app, section: input.section, activeMinutes: input.activeMinutes,
                                          mode: input.mode, nudge: nudge, shownAt: shownAt)
        active = ActiveNudge(request: request, shownAt: shownAt)
        pendingIntervention = request
        state?.activeSession?.nudgeCount += 1
        scheduleOutcomeTimer()
    }

    private func scheduleOutcomeTimer() {
        outcomeTimer?.cancel()
        guard autoResolve else { return }
        outcomeTimer = Task { @MainActor [weak self] in
            // Re-check every few seconds after the window so a late overlay dismissal still resolves.
            try? await Task.sleep(nanoseconds: UInt64(Self.outcomeWindow * 1_000_000_000))
            while let self = self, self.active != nil, !Task.isCancelled {
                self.tick()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    enum Outcome: String { case returned, ignored }

    private func resolve(_ outcome: Outcome) {
        guard let a = active else { return }
        active = nil
        outcomeTimer?.cancel()
        outcomeTimer = nil
        let req = a.request
        log.append(SheepEvent(type: .nudge, mode: req.mode, app: req.app, section: req.section,
                              tone: req.nudge.tone.rawValue, action: req.nudge.primaryAction.rawValue,
                              outcome: outcome.rawValue))
        switch outcome {
        case .returned:
            state?.progress.add(XPRules.resistedNudge)
            state?.activeSession?.nudgesResisted += 1
        case .ignored:
            state?.progress.add(XPRules.ignoredNudge)
        }
    }

    private func makeInput(mode: Mode, streak s: Streak, at t: Date) -> NudgeInput {
        let session = state?.activeSession
        let rest = mode == .rest ? state?.restSession : nil
        return NudgeInput(mode: mode, app: s.app, section: s.section,
                          activeMinutes: s.activeSec / 60,
                          nudgesThisSession: session?.nudgeCount ?? 0,
                          sessionTitle: session?.title,
                          done: session?.doneCount ?? 0,
                          total: session?.checklist.count ?? 0,
                          minutesLeft: session.map { NudgePrompt.minutesLeftInPomodoro($0, now: t) },
                          restActivity: rest?.activity,
                          restLimitMinutes: rest?.limitMinutes,
                          now: t,
                          voice: NudgePrompt.Voice.current(preferences))
    }

    // MARK: Streak accounting

    private func endStreak() {
        guard let s = streak else { return }
        streak = nil
        guard s.activeSec >= Self.minLoggedStreak else { return }
        log.append(SheepEvent(type: .scroll, mode: s.mode, app: s.app, section: s.section,
                              activeMin: (s.activeSec / 60 * 10).rounded() / 10))
    }
}
