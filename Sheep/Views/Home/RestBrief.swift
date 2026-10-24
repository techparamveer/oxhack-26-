import Foundation

/// Home message for the Rest pill once there's Focus data today (Paper "02 Home — Rest"):
/// "You did 3 Pomodoros. Switch off." + which work apps stay muted (+ the running activity's end time).
/// Built from TODAY's events only, with real numbers; nil when there's nothing to say (→ how-to card).
enum RestBrief {
    static func message(events: [SheepEvent], mutedApps: [String], rest: RestSession?, fast: Bool,
                        now: Date = .now, calendar: Calendar = .current) -> HomeMessage? {
        let today = events.filter { calendar.isDate($0.ts, inSameDayAs: now) }
        let ends = today.filter { $0.type == .sessionEnd && ($0.mode == nil || $0.mode == .focus) }
        let ticked = today.filter { $0.type == .checklistDone }.count
        guard !ends.isEmpty || ticked > 0,
              let headline = headline(ends: ends, ticked: ticked, all: events) else { return nil }

        var body: [String] = []
        if let muted = mutedSentence(mutedApps) { body.append(muted) }
        if let rest, rest.endedAt == nil {
            body.append(activitySentence(rest, fast: fast, calendar: calendar))
        } else {
            body.append("Pick something restful and a time limit.")
        }
        return HomeMessage(caption: "Sheep says", meta: "from today", headline: headline,
                           body: body.joined(separator: " "), isFromMemory: true)
    }

    /// "You did 3 Pomodoros. Switch off." / "You did 2 of 4 checklist items. Switch off."
    static func headline(ends: [SheepEvent], ticked: Int, all: [SheepEvent]) -> String? {
        let total = ends.compactMap(\.total).reduce(0, +)
        let done = ends.isEmpty ? ticked : ends.compactMap(\.done).reduce(0, +)
        if total > 0 {
            let planned = ends.compactMap { Sessions.start(for: $0, in: all)?.plannedMin }
            let unit = MemoryText.unit(plannedMin: planned.count == ends.count ? planned.reduce(0, +) : nil, total: total)
            if done >= total { return "You did \(total) \(unit). Switch off." }
            if done > 0 { return "You did \(done) of \(total) \(unit). Switch off." }
        } else if done > 0 {
            return "You ticked \(done) \(done == 1 ? "item" : "items") today. Switch off."
        }
        let minutes = Int(ends.compactMap(\.actualMin).reduce(0, +).rounded())
        return minutes > 0 ? "You focused \(minutes) min today. Switch off." : nil
    }

    /// "Teams and Outlook stay muted while you rest." (from `sheep.mutedWorkApps`).
    static func mutedSentence(_ apps: [String]) -> String? {
        switch apps.count {
        case 0: return nil
        case 1: return "\(apps[0]) stays muted while you rest."
        default: return apps.dropLast().joined(separator: ", ") + " and \(apps.last!) stay muted while you rest."
        }
    }

    /// "Netflix till 23:00, then bed." — the clock time only for real timers (fast ones compress time).
    static func activitySentence(_ rest: RestSession, fast: Bool, calendar: Calendar = .current) -> String {
        let name = MemoryText.activity(rest.activity)
        guard !fast else { return "\(name) for \(rest.limitMinutes) min." }
        let end = rest.startedAt.addingTimeInterval(Double(rest.limitMinutes) * 60)
        let hour = calendar.component(.hour, from: end)
        let late = hour >= 22 || hour < 4
        return "\(name) till \(MemoryDates.time(end, calendar: calendar))\(late ? ", then bed." : ".")"
    }
}
