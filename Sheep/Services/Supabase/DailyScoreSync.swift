import Foundation

/// Mirrors Home's `DayScore` to Supabase `daily_scores`, debounced and de-duplicated.
/// Fire-and-forget: Home calls `submit(_:)` on every recompute; nothing here ever blocks the UI.
@MainActor
final class DailyScoreSync {
    static let shared = DailyScoreSync()

    struct Row: Equatable {
        var day: String
        var total, focus, rest, play: Int
    }

    var debounce: Duration
    /// Defaults to `SupabaseSync.shared.recordDailyScore` (a no-op queue when Supabase isn't configured).
    var send: (Date, Row) -> Void

    private var pending: Task<Void, Never>?
    private(set) var lastSent: Row?

    init(debounce: Duration = .seconds(2),
         send: @escaping (Date, Row) -> Void = { date, row in
             SupabaseSync.shared.recordDailyScore(date: date, score: row.total, focus: row.focus,
                                                  rest: row.rest, play: row.play)
         }) {
        self.debounce = debounce
        self.send = send
    }

    /// The row for a day's score; nil when nothing was scored (no row for empty days).
    static func row(for score: DayScore, day: String) -> Row? {
        guard let total = score.total else { return nil }
        return Row(day: day, total: total, focus: score.focus ?? 0, rest: score.rest ?? 0, play: score.play ?? 0)
    }

    func submit(_ score: DayScore, now: Date = .now) {
        guard let row = Self.row(for: score, day: MemoryDates.day(now)), row != lastSent else { return }
        pending?.cancel()
        pending = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self, row != self.lastSent else { return }
            self.lastSent = row
            self.send(now, row)
        }
    }
}
