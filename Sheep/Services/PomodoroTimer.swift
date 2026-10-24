import Foundation
import Observation

/// Back-to-back Pomodoros derived purely from the wall-clock start time, so the countdown survives
/// navigation, backgrounding and relaunch. Call `tick()` (or `run()`) to refresh `now`.
@Observable
final class PomodoroTimer {
    let startedAt: Date
    let pomodoros: Int
    let pomodoroMinutes: Int
    let sessionID: UUID
    private(set) var now: Date

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let scheduler: (_ id: String, _ title: String, _ body: String, _ after: TimeInterval) -> Void
    @ObservationIgnored private let canceller: (_ id: String) -> Void

    init(startedAt: Date, pomodoros: Int, pomodoroMinutes: Int, sessionID: UUID = UUID(),
         clock: @escaping () -> Date = { Date() },
         scheduler: @escaping (String, String, String, TimeInterval) -> Void = { id, title, body, after in
             NotificationService.shared.schedule(id: id, title: title, body: body, after: after)
         },
         canceller: @escaping (String) -> Void = { NotificationService.shared.cancel(id: $0) }) {
        self.startedAt = startedAt
        self.pomodoros = max(1, pomodoros)
        self.pomodoroMinutes = max(1, pomodoroMinutes)
        self.sessionID = sessionID
        self.clock = clock
        self.scheduler = scheduler
        self.canceller = canceller
        self.now = clock()
    }

    convenience init(session: FocusSession) {
        self.init(startedAt: session.startedAt, pomodoros: session.pomodoros,
                  pomodoroMinutes: session.pomodoroMinutes, sessionID: session.id)
    }

    // MARK: Math

    var pomodoroSeconds: TimeInterval { TimeInterval(pomodoroMinutes * 60) }
    var totalSeconds: TimeInterval { pomodoroSeconds * TimeInterval(pomodoros) }
    var elapsed: TimeInterval { min(totalSeconds, max(0, now.timeIntervalSince(startedAt))) }
    var isFinished: Bool { now.timeIntervalSince(startedAt) >= totalSeconds }

    /// 1-based index of the running Pomodoro (stays at the last one once finished).
    var currentPomodoro: Int {
        min(pomodoros, Int(elapsed / pomodoroSeconds) + 1)
    }

    /// Seconds left in the running Pomodoro (0 once the session's time is up).
    var remainingInCurrent: TimeInterval {
        if isFinished { return 0 }
        return pomodoroSeconds - elapsed.truncatingRemainder(dividingBy: pomodoroSeconds)
    }

    /// 0…1 progress through the running Pomodoro, for the ring.
    var progressInCurrent: Double {
        isFinished ? 1 : 1 - remainingInCurrent / pomodoroSeconds
    }

    var totalRemaining: TimeInterval { max(0, totalSeconds - elapsed) }

    /// "24:59"
    var countdownText: String { Self.format(remainingInCurrent) }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Ticking

    func tick() { now = clock() }

    /// Ticks once a second until cancelled (use from a view's `.task`).
    func run() async {
        while !Task.isCancelled {
            tick()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: Notifications

    func notificationID(_ index: Int) -> String { "pomodoro-\(sessionID.uuidString)-\(index)" }

    /// Schedules one local notification per remaining Pomodoro end; the last doubles as "session done".
    /// Idempotent: re-scheduling replaces by id.
    func scheduleNotifications(title: String) {
        let sinceStart = clock().timeIntervalSince(startedAt)
        for i in 1...pomodoros {
            let after = pomodoroSeconds * TimeInterval(i) - sinceStart
            guard after > 0 else { continue }
            if i == pomodoros {
                scheduler(notificationID(i), "session done 🐑", "\(title): time's up. Come back and tick off what you finished.", after)
            } else {
                scheduler(notificationID(i), "pomodoro \(i) of \(pomodoros) done", "Straight into the next one. \(title).", after)
            }
        }
    }

    func cancelNotifications() {
        for i in 1...pomodoros { canceller(notificationID(i)) }
    }
}
