import Foundation

/// Per-mode scores (0–100) for one calendar day, computed from `events.jsonl`. Pure — no I/O.
///
/// - Focus: per `session_end`, `round(100 × (0.5 × done/total + 0.3 × min(1, actual/planned) + 0.2 × resist))`
///   where `planned` comes from the paired `session_start` and `resist` = returned / nudges in that session
///   (1 when there were no nudges). Averaged over the day's sessions.
/// - Rest / Play: per `rest_activity` / `play_session`, `round(100 × min(1, limit/actual))`, averaged.
/// - A mode with no data that day is `nil`.
struct DayScore: Equatable {
    var focus: Int?
    var rest: Int?
    var play: Int?

    func score(for mode: Mode) -> Int? {
        switch mode {
        case .focus: focus
        case .rest: rest
        case .play: play
        case .idle: total
        }
    }

    /// Mean of the non-nil mode scores; nil when nothing happened that day.
    var total: Int? { Self.mean([focus, rest, play].compactMap { $0 }) }

    // MARK: Computation

    static func compute(events: [SheepEvent], day: Date, calendar: Calendar = .current) -> DayScore {
        let sorted = events.sorted { $0.ts < $1.ts }
        var focusScores: [Int] = []
        var restScores: [Int] = []
        var playScores: [Int] = []

        // Pairing state runs over ALL events so a session that started before midnight still pairs.
        var plannedMin: Int?
        var nudges = 0
        var returned = 0

        for event in sorted {
            let onDay = calendar.isDate(event.ts, inSameDayAs: day)
            switch event.type {
            case .sessionStart where event.mode == nil || event.mode == .focus:
                plannedMin = event.plannedMin
                nudges = 0
                returned = 0
            case .nudge:
                nudges += 1
                if event.outcome == "returned" { returned += 1 }
            case .sessionEnd where event.mode == nil || event.mode == .focus:
                if onDay {
                    focusScores.append(focusSessionScore(done: event.done ?? 0, total: event.total ?? 0,
                                                         actualMin: event.actualMin ?? 0,
                                                         plannedMin: plannedMin ?? event.plannedMin,
                                                         nudges: nudges, returned: returned))
                }
                plannedMin = nil
                nudges = 0
                returned = 0
            case .restActivity where onDay:
                if let s = limitScore(limitMin: event.limitMin, actualMin: event.actualMin) { restScores.append(s) }
            case .playSession where onDay:
                if let s = limitScore(limitMin: event.limitMin, actualMin: event.actualMin) { playScores.append(s) }
            default:
                break
            }
        }

        return DayScore(focus: mean(focusScores), rest: mean(restScores), play: mean(playScores))
    }

    /// Today − yesterday when both days have a score.
    static func delta(today: DayScore, yesterday: DayScore) -> Int? {
        guard let t = today.total, let y = yesterday.total else { return nil }
        return t - y
    }

    /// Convenience for Home: today's score plus the delta vs yesterday.
    static func today(events: [SheepEvent], now: Date = .now, calendar: Calendar = .current) -> (score: DayScore, delta: Int?) {
        let today = compute(events: events, day: now, calendar: calendar)
        guard let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) else { return (today, nil) }
        let yesterday = compute(events: events, day: yesterdayDate, calendar: calendar)
        return (today, delta(today: today, yesterday: yesterday))
    }

    static func focusSessionScore(done: Int, total: Int, actualMin: Double, plannedMin: Int?,
                                  nudges: Int, returned: Int) -> Int {
        let checklist = total > 0 ? min(1, Double(max(0, done)) / Double(total)) : 0
        let time: Double
        if let plannedMin, plannedMin > 0 {
            time = min(1, max(0, actualMin) / Double(plannedMin))
        } else {
            time = actualMin > 0 ? 1 : 0
        }
        let resist = nudges > 0 ? min(1, Double(returned) / Double(nudges)) : 1
        return Int((100 * (0.5 * checklist + 0.3 * time + 0.2 * resist)).rounded())
    }

    /// `round(100 × min(1, limit/actual))`; nil when the event lacks a limit or an actual duration.
    static func limitScore(limitMin: Int?, actualMin: Double?) -> Int? {
        guard let limitMin, let actualMin else { return nil }
        guard actualMin > 0 else { return 100 }
        return Int((100 * min(1, Double(max(0, limitMin)) / actualMin)).rounded())
    }

    private static func mean(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
