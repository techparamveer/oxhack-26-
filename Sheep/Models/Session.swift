import Foundation

struct ChecklistItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
    var doneAt: Date?
}

/// A Focus session: intake answers, Gemini plan, checklist and live counters.
struct FocusSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var answers: [String]            // Q1 achieve, Q2 done looks like, Q3 distractions
    var title: String
    var opener: String
    var watchOut: String
    var workstream: String
    var checklist: [ChecklistItem]
    var pomodoros: Int
    var pomodoroMinutes: Int          // 25 real, 1 in fast mode
    var startedAt: Date
    var endedAt: Date?
    var nudgeCount = 0
    var nudgesResisted = 0
    var scrollSeconds: Double = 0

    var plannedMinutes: Int { pomodoros * pomodoroMinutes }
    var doneCount: Int { checklist.filter(\.done).count }
    var actualMinutes: Int {
        Int(((endedAt ?? .now).timeIntervalSince(startedAt) / 60).rounded())
    }
}

/// Result shown on the Congrats screen after a Focus session ends.
struct SessionOutcome: Codable, Equatable {
    var session: FocusSession
    var headline: String
    var summary: String
    var nextStep: String
    var xpEarned: Int
    var learned: [String]
}

/// A Rest activity with the time limit the user picked.
struct RestSession: Codable, Equatable {
    var activity: String
    var limitMinutes: Int
    var startedAt: Date
    var endedAt: Date?
    var overuseNotified = false
}

/// A Play (gaming) block with a limit.
struct PlaySession: Codable, Equatable {
    var limitMinutes: Int
    var startedAt: Date
    var endedAt: Date?
}
