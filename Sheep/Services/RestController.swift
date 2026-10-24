import Foundation
import UserNotifications

/// Wall-clock maths shared by Rest and Play timers.
///
/// Real mode: the timer runs at 1x and the overuse notification fires one minute past the limit.
/// Fast timers (demo): the whole limit plays out in `fastLimitSeconds` real seconds and the
/// notification fires at `fastFireSeconds`, whatever limit was picked — so a 45 min Netflix
/// limit shows as "50 min" when the banner lands after 20 s. After that the clock runs at 1x.
enum LimitClock {
    static let fastFireSeconds: TimeInterval = 20
    static let fastLimitSeconds: TimeInterval = 18
    static let realGraceSeconds: TimeInterval = 60

    /// Display seconds per real second.
    static func speed(limitMinutes: Int, fast: Bool) -> Double {
        fast ? Double(max(1, limitMinutes) * 60) / fastLimitSeconds : 1
    }

    /// Real seconds from start until the overuse notification fires.
    static func overuseDelay(limitMinutes: Int, fast: Bool) -> TimeInterval {
        fast ? fastFireSeconds : Double(limitMinutes * 60) + realGraceSeconds
    }

    /// Minutes the user will have spent (as displayed) at the moment the notification fires.
    static func projectedMinutesAtOveruse(limitMinutes: Int, fast: Bool) -> Int {
        Int((overuseDelay(limitMinutes: limitMinutes, fast: fast) * speed(limitMinutes: limitMinutes, fast: fast) / 60).rounded())
    }

    /// Displayed elapsed seconds. Fast timers compress time only up to the notification; after it
    /// the clock ticks at 1x so the "over" counter stays readable during the demo.
    static func elapsedSeconds(startedAt: Date, now: Date = .now, limitMinutes: Int, fast: Bool) -> TimeInterval {
        let real = max(0, now.timeIntervalSince(startedAt))
        guard fast else { return real }
        let compressed = min(real, fastFireSeconds)
        return compressed * speed(limitMinutes: limitMinutes, fast: true) + (real - compressed)
    }

    static func elapsedMinutes(startedAt: Date, now: Date = .now, limitMinutes: Int, fast: Bool) -> Double {
        elapsedSeconds(startedAt: startedAt, now: now, limitMinutes: limitMinutes, fast: fast) / 60
    }

    /// "4:05" or "1:02:03".
    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// The two notification calls Rest/Play need — injectable so tests never touch UNUserNotificationCenter.
protocol LimitNotifier {
    /// Schedules or replaces (same id) a pending notification.
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval)
    /// Removes the pending request and any already-delivered banner for `id`.
    func clear(id: String)
}

extension NotificationService: LimitNotifier {
    func clear(id: String) {
        cancel(id: id)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
}

/// Start / end logic for Rest and Play sessions. Views call these; tests drive them directly.
enum RestController {
    @MainActor static var notifier: LimitNotifier = NotificationService.shared

    static let restNotificationID = "sheep.rest.overuse"
    static let playNotificationID = "sheep.play.overuse"

    static let activities = ["Spotify", "Netflix", "Sport", "Walk"]
    static let restLimits = [15, 30, 45, 60]
    static let playLimits = [30, 60, 90]

    // MARK: Rest

    @MainActor @discardableResult
    static func startRest(activity: String, limitMinutes: Int, state: AppState, now: Date = .now,
                          client: GeminiClient = .shared) -> Task<Void, Never> {
        let name = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = RestSession(activity: name.isEmpty ? "rest" : name, limitMinutes: limitMinutes, startedAt: now)
        state.restSession = session
        state.setMode(.rest)
        return scheduleRestNudge(for: session, state: state, client: client)
    }

    /// Schedules the fallback text immediately, then swaps in Gemini's text if it arrives (≤ 3 s).
    /// Both use the same identifier, so the Gemini text *replaces* the pending fallback (never a second
    /// banner); it is dropped if the session ended/changed or the fire time is under a second away.
    @MainActor @discardableResult
    static func scheduleRestNudge(for session: RestSession, state: AppState,
                                  client: GeminiClient = .shared) -> Task<Void, Never> {
        let fast = state.fastTimers
        let fireAt = session.startedAt.addingTimeInterval(LimitClock.overuseDelay(limitMinutes: session.limitMinutes, fast: fast))
        let actual = LimitClock.projectedMinutesAtOveruse(limitMinutes: session.limitMinutes, fast: fast)
        let activity = session.activity.lowercased()
        let fallback = RestNudgePrompt.fallback(activity: activity, limitMinutes: session.limitMinutes,
                                                actualMinutes: actual, now: fireAt)
        notifier.schedule(id: restNotificationID, title: fallback.title, body: fallback.body,
                          after: fireAt.timeIntervalSinceNow)
        return Task { @MainActor in
            let text = await RestNudgePrompt.generate(activity: activity, limitMinutes: session.limitMinutes,
                                                      actualMinutes: actual, now: fireAt, client: client)
            guard state.restSession?.startedAt == session.startedAt, state.restSession?.endedAt == nil,
                  fireAt.timeIntervalSinceNow > 1 else { return }
            guard text != fallback else { return }   // offline: the fallback is already pending
            notifier.schedule(id: restNotificationID, title: text.title, body: text.body,
                              after: fireAt.timeIntervalSinceNow)
        }
    }

    /// Logs `rest_activity`, awards XP, clears the session and returns to Idle. Returns XP earned.
    @MainActor @discardableResult
    static func endRest(state: AppState, now: Date = .now, log: EventLog = .shared) -> Int {
        notifier.clear(id: restNotificationID)
        guard let session = state.restSession else {
            if state.mode == .rest { state.setMode(.idle) }
            return 0
        }
        let minutes = LimitClock.elapsedMinutes(startedAt: session.startedAt, now: now,
                                                limitMinutes: session.limitMinutes, fast: state.fastTimers)
        let actual = Int(minutes.rounded())
        let xp = XPRules.restOrPlay(actualMinutes: actual, limitMinutes: session.limitMinutes)
        log.append(SheepEvent(ts: now, type: .restActivity, actualMin: rounded1(minutes), xp: xp,
                              activity: session.activity.lowercased(), limitMin: session.limitMinutes))
        state.progress.add(xp)
        state.restSession = nil
        state.setMode(.idle)
        return xp
    }

    // MARK: Play

    @MainActor
    static func startPlay(limitMinutes: Int, state: AppState, now: Date = .now) {
        let session = PlaySession(limitMinutes: limitMinutes, startedAt: now)
        state.playSession = session
        state.setMode(.play)
        let fast = state.fastTimers
        let actual = LimitClock.projectedMinutesAtOveruse(limitMinutes: limitMinutes, fast: fast)
        let text = playFallback(limitMinutes: limitMinutes, actualMinutes: actual)
        notifier.schedule(id: playNotificationID, title: text.title, body: text.body,
                          after: LimitClock.overuseDelay(limitMinutes: limitMinutes, fast: fast))
    }

    @MainActor @discardableResult
    static func endPlay(state: AppState, now: Date = .now, log: EventLog = .shared) -> Int {
        notifier.clear(id: playNotificationID)
        guard let session = state.playSession else {
            if state.mode == .play { state.setMode(.idle) }
            return 0
        }
        let minutes = LimitClock.elapsedMinutes(startedAt: session.startedAt, now: now,
                                                limitMinutes: session.limitMinutes, fast: state.fastTimers)
        let xp = XPRules.restOrPlay(actualMinutes: Int(minutes.rounded()), limitMinutes: session.limitMinutes)
        log.append(SheepEvent(ts: now, type: .playSession, actualMin: rounded1(minutes), xp: xp,
                              limitMin: session.limitMinutes))
        state.progress.add(xp)
        state.playSession = nil
        state.setMode(.idle)
        return xp
    }

    static func playFallback(limitMinutes: Int, actualMinutes: Int) -> RestNudgePrompt.Response {
        RestNudgePrompt.Response(
            title: "good game — time's up",
            body: "\(actualMinutes) min of play, past your \(limitMinutes). save, stand up, grab some water."
        )
    }

    private static func rounded1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}
