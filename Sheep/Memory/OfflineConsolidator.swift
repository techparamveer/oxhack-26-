import Foundation

/// Deterministic, on-device consolidation used when Gemini is unavailable (no key, timeout, bad JSON).
/// Everything here is computed from logged events — it never invents anything.
///
/// - `timeline/daily/<day>.md` is re-rendered from ALL logged events of each touched day (idempotent).
/// - `knowledge/what-works.md` and `knowledge/patterns.md` are merged incrementally: counts already in the
///   file (possibly from older, pruned history) plus the NEW events only.
/// - The active workstream gets a dated progress bullet per finished session.
enum OfflineConsolidator {
    static let whatWorksPath = "knowledge/what-works.md"
    static let patternsPath = "knowledge/patterns.md"

    static func consolidate(newEvents: [SheepEvent], allEvents: [SheepEvent], files: [MemoryFile],
                            now: Date = .now, calendar: Calendar = .current) -> ConsolidatorResponse {
        let today = MemoryDates.day(now, calendar: calendar)
        let all = allEvents.sorted { $0.ts < $1.ts }
        let fresh = newEvents.sorted { $0.ts < $1.ts }
        let existing = Dictionary(files.map { ($0.path, $0.content) }, uniquingKeysWith: { a, _ in a })
        var out: [ConsolidatorResponse.File] = []
        func emit(_ path: String, _ content: String) {
            if existing[path] != content { out.append(.init(path: path, content: content)) }
        }

        // 1. Daily timelines.
        var days = Set(fresh.map { MemoryDates.day($0.ts, calendar: calendar) })
        if fresh.isEmpty, let y = calendar.date(byAdding: .day, value: -1, to: now) {
            days = [MemoryDates.day(y, calendar: calendar), today] // forced refresh: finalise yesterday + today
        }
        let byDay = Dictionary(grouping: all) { MemoryDates.day($0.ts, calendar: calendar) }
        for day in days.sorted() {
            guard let evs = byDay[day], evs.contains(where: { $0.type != .modeChange && $0.type != .wrapperOpen })
            else { continue }
            emit("timeline/daily/\(day).md", DailyRenderer.render(day: day, events: evs, updated: today, calendar: calendar))
        }

        // 2. Procedural memory: what works.
        let nudges = fresh.filter { $0.type == .nudge && ($0.outcome == "returned" || $0.outcome == "ignored") }
        var works = WhatWorks.parse(existing[whatWorksPath])
        if !nudges.isEmpty {
            for n in nudges { works.add(n, calendar: calendar) }
            emit(whatWorksPath, works.render(updated: today))
        }

        // 3. Patterns.
        var patterns = Patterns.parse(existing[patternsPath])
        let observations = Patterns.observations(in: fresh, all: all, calendar: calendar)
        if !observations.isEmpty {
            for o in observations { patterns.add(o) }
            emit(patternsPath, patterns.render(updated: today))
        }

        // 4. Workstream progress.
        var workstreamFiles = existing
        for end in fresh where end.type == .sessionEnd {
            let start = Sessions.start(for: end, in: all)
            guard let name = (start?.workstream ?? end.workstream), !name.isEmpty else { continue }
            let (path, content) = Workstreams.logProgress(name: name, start: start, end: end,
                                                          files: workstreamFiles, today: today, calendar: calendar)
            workstreamFiles[path] = content
            out.removeAll { $0.path == path }
            emit(path, content)
        }

        // 5. Learned (1–3 honest lines).
        let learned = Learned.lines(fresh: fresh, all: all, works: works, now: now, calendar: calendar)
        return ConsolidatorResponse(files: out, learned: learned)
    }
}

// MARK: - Wording helpers

enum MemoryText {
    /// "Instagram Reels", "YouTube Shorts", "Instagram feed", "Instagram DMs"
    static func place(_ app: WrappedApp?, _ section: AppSection?) -> String {
        let a = app?.title ?? "your feed"
        guard let section else { return a }
        return "\(a) \(sectionName(section))"
    }

    static func sectionName(_ s: AppSection) -> String {
        switch s {
        case .reels: "Reels"
        case .shorts: "Shorts"
        case .dms: "DMs"
        case .feed: "feed"
        }
    }

    /// Short name used in the brief: "Reels", "Shorts", "the Instagram feed".
    static func shortPlace(_ app: WrappedApp?, _ section: AppSection?) -> String {
        switch section {
        case .reels: "Reels"
        case .shorts: "Shorts"
        case .dms: "DMs"
        case .feed, .none: "the \(app?.title ?? "") feed".replacingOccurrences(of: "the  feed", with: "the feed")
        }
    }

    static func minutes(_ m: Double?) -> String {
        guard let m else { return "0" }
        let r = (m * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    static func activity(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "Rest" }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    static func tone(_ s: String?) -> String { activity(s ?? "a") }

    static func action(_ s: String?) -> String { (s ?? "nudge").replacingOccurrences(of: "_", with: " ") }

    /// "Pomodoros" when the checklist maps 1:1 to 25-min Pomodoros, else "checklist items".
    static func unit(plannedMin: Int?, total: Int) -> String {
        if let p = plannedMin, p > 0, p % 25 == 0, p / 25 == total {
            return total == 1 ? "Pomodoro" : "Pomodoros"
        }
        return total == 1 ? "checklist item" : "checklist items"
    }
}

/// Session pairing helpers.
enum Sessions {
    /// The latest `session_start` before `event` with no `session_end` in between.
    static func start(for event: SheepEvent, in all: [SheepEvent]) -> SheepEvent? {
        var current: SheepEvent?
        for e in all where e.ts <= event.ts {
            if e.type == .sessionStart { current = e }
            if e.type == .sessionEnd, e != event, e.ts < event.ts { current = nil }
        }
        return current
    }
}

// MARK: - Daily timeline

enum DailyRenderer {
    static func render(day: String, events: [SheepEvent], updated: String, calendar: Calendar) -> String {
        let evs = events.sorted { $0.ts < $1.ts }
        let starts = evs.filter { $0.type == .sessionStart }
        let ends = evs.filter { $0.type == .sessionEnd }
        let t: (Date) -> String = { MemoryDates.time($0, calendar: calendar) }

        var lines: [String] = []
        let date = MemoryDates.parseDay(day, calendar: calendar) ?? evs.first?.ts ?? .now
        lines.append("# \(MemoryDates.weekday(date, calendar: calendar)) \(MemoryDates.format(date, "d MMM", calendar))")
        lines.append("")

        if starts.isEmpty && ends.isEmpty {
            lines.append("- No Focus sessions.")
        } else {
            let planned = starts.compactMap(\.plannedMin).reduce(0, +)
            let done = ends.compactMap(\.done).reduce(0, +)
            let total = ends.compactMap(\.total).reduce(0, +)
            let focusMin = ends.compactMap(\.actualMin).reduce(0, +)
            if starts.count == 1, let s = starts.first {
                let pomos = planned > 0 && planned % 25 == 0 ? "\(planned / 25) Pomodoros (\(planned) min)" : "\(planned) min"
                lines.append("- Planned: \(pomos) — \(s.title ?? "Focus")")
            } else {
                lines.append("- Planned: \(starts.count) sessions, \(planned) min")
            }
            let unit = MemoryText.unit(plannedMin: starts.count == 1 ? starts.first?.plannedMin : nil, total: total)
            let sessions = ends.count == 1 ? "1 session" : "\(ends.count) sessions"
            lines.append("- Done: \(done) of \(total) \(unit) · \(MemoryText.minutes(focusMin)) min focus · \(sessions)")
        }
        lines.append("")
        lines.append("## Timeline")

        var timeline: [String] = []
        var wins: [String] = []
        for e in evs {
            switch e.type {
            case .sessionStart:
                timeline.append("- \(t(e.ts)) Focus: \(e.title ?? "session") (\(e.plannedMin ?? 0) min planned)")
            case .sessionEnd:
                let xp = e.xp.map { ", +\($0) xp" } ?? ""
                timeline.append("- \(t(e.ts)) Focus ended: \(e.done ?? 0) of \(e.total ?? 0) done, \(MemoryText.minutes(e.actualMin)) min\(xp)")
                if let d = e.done, let tot = e.total, tot > 0, d >= tot { wins.append("- Finished every item at \(t(e.ts))") }
            case .checklistDone:
                timeline.append("- \(t(e.ts)) Ticked: \(e.item ?? "item")")
            case .scroll:
                var s = "- \(t(e.ts)) Slipped into \(MemoryText.place(e.app, e.section)), \(MemoryText.minutes(e.activeMin)) min"
                if let start = Sessions.start(for: e, in: evs), e.mode == .focus || e.mode == nil {
                    s += ", \(Int(e.ts.timeIntervalSince(start.ts) / 60)) min into Focus"
                }
                timeline.append(s)
            case .nudge:
                timeline.append("- \(t(e.ts)) \(MemoryText.tone(e.tone)) nudge (\(MemoryText.action(e.action))) → \(e.outcome ?? "shown")")
                if e.outcome == "returned" { wins.append("- Came back after a \(e.tone ?? "") nudge at \(t(e.ts))") }
            case .blocked:
                timeline.append("- \(t(e.ts)) Blocked: \(MemoryText.place(e.app, e.section))")
            case .restActivity:
                let limit = e.limitMin.map { " (limit \($0))" } ?? ""
                timeline.append("- \(t(e.ts)) Rest: \(MemoryText.activity(e.activity)) \(MemoryText.minutes(e.actualMin)) min\(limit)")
                if let l = e.limitMin, let a = e.actualMin, a <= Double(l) {
                    wins.append("- Kept \(MemoryText.activity(e.activity)) within \(l) min")
                }
            case .playSession:
                let limit = e.limitMin.map { " (limit \($0))" } ?? ""
                timeline.append("- \(t(e.ts)) Play: \(MemoryText.minutes(e.actualMin)) min\(limit)")
            case .modeChange, .wrapperOpen:
                continue
            }
        }
        lines.append(contentsOf: timeline.suffix(14))
        if !wins.isEmpty {
            lines.append("")
            lines.append("## Wins")
            lines.append(contentsOf: wins.prefix(3))
        }

        var aliases = ["daily", day, MemoryDates.weekday(date, calendar: calendar).lowercased()]
        for e in evs {
            if let a = e.app?.rawValue { aliases.append(a) }
            if let s = e.section?.rawValue { aliases.append(s) }
            if let a = e.activity?.lowercased() { aliases.append(a) }
            if let w = e.workstream { aliases.append(MemoryStore.slug(w)) }
        }
        let header = MemoryHeader(id: "daily-\(day)", type: "daily", aliases: Array(aliases.uniqued().prefix(8)), updated: updated)
        return header.file(body: lines.joined(separator: "\n"))
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - What works (procedural memory)

struct WhatWorks: Equatable {
    struct Stat: Equatable {
        var tone: String
        var action: String
        var back: Int
        var total: Int
        var last: String
        var rate: Double { total == 0 ? 0 : Double(back) / Double(total) }
    }

    var stats: [Stat] = []
    var notes: [String] = []

    // "- Playful nudges (close app): got you back 1 of 1 (last 2026-10-23)"
    private static let regex = try! NSRegularExpression(
        pattern: #"^- (\w+) nudges \(([^)]+)\): got you back (\d+) of (\d+) \(last (\d{4}-\d{2}-\d{2})\)"#)

    static func parse(_ content: String?) -> WhatWorks {
        guard let content else { return WhatWorks() }
        var w = WhatWorks()
        for raw in MemoryHeader.parse(content).body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let ns = line as NSString
            if let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let g = { (i: Int) in ns.substring(with: m.range(at: i)) }
                w.stats.append(Stat(tone: g(1).lowercased(), action: g(2).replacingOccurrences(of: " ", with: "_"),
                                    back: Int(g(3)) ?? 0, total: Int(g(4)) ?? 0, last: g(5)))
            } else if line.hasPrefix("- ") {
                w.notes.append(line)
            }
        }
        return w
    }

    mutating func add(_ e: SheepEvent, calendar: Calendar) {
        let tone = (e.tone ?? "unknown").lowercased()
        let action = e.action ?? "nudge"
        let day = MemoryDates.day(e.ts, calendar: calendar)
        let back = e.outcome == "returned" ? 1 : 0
        if let i = stats.firstIndex(where: { $0.tone == tone && $0.action == action }) {
            stats[i].back += back
            stats[i].total += 1
            stats[i].last = max(stats[i].last, day)
        } else {
            stats.append(Stat(tone: tone, action: action, back: back, total: 1, last: day))
        }
    }

    /// Totals per tone across actions.
    var byTone: [(tone: String, back: Int, total: Int)] {
        var d: [String: (Int, Int)] = [:]
        for s in stats { d[s.tone, default: (0, 0)].0 += s.back; d[s.tone, default: (0, 0)].1 += s.total }
        return d.map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { a, b in
                let ra = Double(a.back) / Double(max(a.total, 1)), rb = Double(b.back) / Double(max(b.total, 1))
                if ra != rb { return ra > rb }
                return a.total != b.total ? a.total > b.total : a.tone < b.tone // deterministic on ties
            }
    }

    func render(updated: String) -> String {
        let sorted = stats.sorted {
            if $0.rate != $1.rate { return $0.rate > $1.rate }
            if $0.total != $1.total { return $0.total > $1.total }
            return ($0.tone, $0.action) < ($1.tone, $1.action)
        }
        var lines = ["# What works", ""]
        let tones = byTone
        if let best = tones.first {
            var summary = "Best so far: \(best.tone) nudges (back \(best.back) of \(best.total))."
            if tones.count > 1, let worst = tones.last {
                summary += " Least: \(worst.tone) (back \(worst.back) of \(worst.total))."
            }
            lines.append(summary)
            lines.append("")
        }
        let statLines = sorted.prefix(6).map {
            "- \(MemoryText.tone($0.tone)) nudges (\(MemoryText.action($0.action))): got you back \($0.back) of \($0.total) (last \($0.last))"
        }
        lines.append(contentsOf: statLines)
        lines.append(contentsOf: notes.prefix(max(0, 8 - statLines.count)))
        var aliases = ["nudges", "tone", "what works"]
        aliases.append(contentsOf: sorted.map(\.tone))
        let header = MemoryHeader(id: "what-works", type: "procedural", aliases: Array(aliases.uniqued().prefix(8)), updated: updated)
        return header.file(body: lines.joined(separator: "\n"))
    }
}

// MARK: - Patterns

struct Patterns: Equatable {
    struct Line: Equatable {
        var label: String
        var count: Int
        var last: String
        /// Label with the "~12 min" number blanked, so averages merge into one line.
        var key: String { Patterns.minutesRegex.stringByReplacingMatches(
            in: label, range: NSRange(location: 0, length: (label as NSString).length), withTemplate: "~#") }
    }

    struct Observation: Equatable {
        var label: String
        var day: String
        var minutesInto: Int?
    }

    var lines: [Line] = []
    var notes: [String] = []

    static let minutesRegex = try! NSRegularExpression(pattern: #"~\d+(\.\d+)?"#)
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^- (.+) \(seen (\d+)×, last (\d{4}-\d{2}-\d{2})\)\s*$"#)

    static func parse(_ content: String?) -> Patterns {
        guard let content else { return Patterns() }
        var p = Patterns()
        for raw in MemoryHeader.parse(content).body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let ns = line as NSString
            if let m = lineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                p.lines.append(Line(label: ns.substring(with: m.range(at: 1)), count: Int(ns.substring(with: m.range(at: 2))) ?? 1,
                                    last: ns.substring(with: m.range(at: 3))))
            } else if line.hasPrefix("- ") {
                p.notes.append(line)
            }
        }
        return p
    }

    static func observations(in fresh: [SheepEvent], all: [SheepEvent], calendar: Calendar) -> [Observation] {
        var out: [Observation] = []
        for e in fresh {
            let day = MemoryDates.day(e.ts, calendar: calendar)
            switch e.type {
            case .scroll where (e.activeMin ?? 0) >= 1:
                let place = MemoryText.place(e.app, e.section)
                if e.mode == .focus || (e.mode == nil && Sessions.start(for: e, in: all) != nil),
                   let start = Sessions.start(for: e, in: all) {
                    let into = max(0, Int(e.ts.timeIntervalSince(start.ts) / 60))
                    out.append(Observation(label: "Slips into \(place) ~\(into) min into Focus", day: day, minutesInto: into))
                }
                let hour = calendar.component(.hour, from: e.ts)
                if hour >= 22 || hour < 4 {
                    out.append(Observation(label: "\(place) after 22:00", day: day))
                }
            case .restActivity:
                if let l = e.limitMin, let a = e.actualMin, a > Double(l) {
                    out.append(Observation(label: "\(MemoryText.activity(e.activity)) runs past its Rest limit", day: day))
                }
            case .playSession:
                if let l = e.limitMin, let a = e.actualMin, a > Double(l) {
                    out.append(Observation(label: "Play runs past its limit", day: day))
                }
            default:
                break
            }
        }
        return out
    }

    mutating func add(_ o: Observation) {
        let probe = Line(label: o.label, count: 1, last: o.day)
        if let i = lines.firstIndex(where: { $0.key == probe.key }) {
            var line = lines[i]
            if let into = o.minutesInto, let old = Self.firstNumber(in: line.label) {
                let avg = Int(((old * Double(line.count) + Double(into)) / Double(line.count + 1)).rounded())
                line.label = Self.minutesRegex.stringByReplacingMatches(
                    in: line.label, range: NSRange(location: 0, length: (line.label as NSString).length), withTemplate: "~\(avg)")
            }
            line.count += 1
            line.last = max(line.last, o.day)
            lines[i] = line
        } else {
            lines.append(probe)
        }
    }

    private static func firstNumber(in s: String) -> Double? {
        let ns = s as NSString
        guard let m = minutesRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Double(ns.substring(with: m.range).dropFirst())
    }

    func render(updated: String) -> String {
        let sorted = lines.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.last != $1.last ? $0.last > $1.last : $0.label < $1.label
        }
        var body = ["# Patterns", ""]
        let rendered = sorted.prefix(10).map { "- \($0.label) (seen \($0.count)×, last \($0.last))" }
        body.append(contentsOf: rendered)
        body.append(contentsOf: notes.prefix(max(0, 10 - rendered.count)))
        var aliases = ["patterns", "distraction", "slips"]
        for l in sorted {
            for w in ["instagram", "youtube", "reels", "shorts", "feed", "late", "focus"] where l.label.lowercased().contains(w) {
                aliases.append(w)
            }
        }
        let header = MemoryHeader(id: "patterns", type: "patterns", aliases: Array(aliases.uniqued().prefix(8)), updated: updated)
        return header.file(body: body.joined(separator: "\n"))
    }
}

// MARK: - Workstreams

enum Workstreams {
    static func activePath(for name: String, files: [String: String]) -> String {
        let slug = MemoryStore.slug(name)
        let direct = "workstreams/active/\(slug).md"
        if files[direct] != nil { return direct }
        for (path, content) in files where path.hasPrefix("workstreams/active/") {
            let f = MemoryFile(path: path, content: content)
            if f.header?.id == slug || MemoryStore.slug(f.title) == slug { return path }
        }
        return direct
    }

    static func logProgress(name: String, start: SheepEvent?, end: SheepEvent, files: [String: String],
                            today: String, calendar: Calendar) -> (String, String) {
        let path = activePath(for: name, files: files)
        let when = start?.ts ?? end.ts
        let stamp = "\(MemoryDates.day(when, calendar: calendar)) \(MemoryDates.time(when, calendar: calendar))"
        let done = end.done ?? 0, total = end.total ?? 0
        let bullet = "- \(stamp) · \(start?.title ?? "Focus"): \(done) of \(total) done, \(MemoryText.minutes(end.actualMin)) min focus"
        let next = total > done
            ? "- Finish the remaining \(total - done) of \(total) from \"\(start?.title ?? "the last session")\"."
            : "- Plan the next chunk — last session was complete."

        if let content = files[path] {
            let parsed = MemoryHeader.parse(content)
            var lines = parsed.body.components(separatedBy: "\n")
            if lines.contains(where: { $0.hasPrefix("- \(stamp) ·") }) { return (path, content) }
            if let p = lines.firstIndex(where: { $0.lowercased().hasPrefix("## progress") }) {
                var i = p + 1
                while i < lines.count, !lines[i].hasPrefix("## ") { i += 1 }
                var insertAt = i
                while insertAt > p + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertAt -= 1 }
                lines.insert(bullet, at: insertAt)
                // keep the log short: max 8 bullets
                let bullets = (p + 1..<lines.count).prefix { !lines[$0].hasPrefix("## ") }.filter { lines[$0].hasPrefix("- ") }
                if bullets.count > 8, let first = bullets.first { lines.remove(at: first) }
            } else {
                lines.append(contentsOf: ["", "## Progress", bullet])
            }
            if let n = lines.firstIndex(where: { $0.lowercased().hasPrefix("## next step") }) {
                var j = n + 1
                while j < lines.count, !lines[j].hasPrefix("## ") { j += 1 }
                lines.replaceSubrange(n + 1..<j, with: [next])
            } else {
                lines.append(contentsOf: ["", "## Next step", next])
            }
            var header = parsed.header ?? MemoryHeader(id: MemoryStore.slug(name), type: "workstream", updated: today)
            header.updated = today
            return (path, header.file(body: lines.joined(separator: "\n")))
        }

        let goal = start?.answers?.first.flatMap { $0.isEmpty ? nil : $0 } ?? start?.title ?? name
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 }
        let header = MemoryHeader(id: MemoryStore.slug(name), type: "workstream",
                                  aliases: Array((words + ["focus", "goal"]).uniqued().prefix(8)), updated: today)
        let body = """
        # \(name)

        - Goal: \(goal)
        - Deadline: not set

        ## Progress
        \(bullet)

        ## Next step
        \(next)
        """
        return (path, header.file(body: body))
    }
}

// MARK: - Learned

enum Learned {
    static func lines(fresh: [SheepEvent], all: [SheepEvent], works: WhatWorks, now: Date, calendar: Calendar) -> [String] {
        var out: [String] = []

        // Session result.
        if let end = fresh.last(where: { $0.type == .sessionEnd }), let total = end.total, total > 0 {
            let done = end.done ?? 0
            let start = Sessions.start(for: end, in: all)
            let unit = MemoryText.unit(plannedMin: start?.plannedMin, total: total)
            if done >= total {
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                let others = all.filter { $0.type == .sessionEnd && $0 != end && $0.ts >= weekAgo && ($0.total ?? 0) > 0 }
                let best = !others.isEmpty && others.allSatisfy {
                    Double($0.done ?? 0) / Double($0.total ?? 1) < 1 || ($0.done ?? 0) < done
                }
                out.append("You finished \(done) of \(total) \(unit)" + (best ? " — best session this week." : ". Clean session."))
            } else {
                out.append("You finished \(done) of \(total) \(unit) in \(MemoryText.minutes(end.actualMin)) min of Focus.")
            }
        }

        // Nudge tones (cumulative, from what-works).
        let freshTones = Set(fresh.filter { $0.type == .nudge && $0.outcome != nil }.map { ($0.tone ?? "unknown").lowercased() })
        let tones = works.byTone.filter { freshTones.contains($0.tone) }
        // These are all-time counts, so the line names its scope ("Across the last two days, …") — otherwise it
        // reads as contradicting the Congrats summary, which counts this session only.
        func scoped(_ t: (tone: String, back: Int, total: Int)) -> String {
            toneLine(t.tone, t.back, t.total, scope: toneScope(t.tone, total: t.total, all: all, now: now, calendar: calendar))
        }
        if let best = tones.first(where: { $0.back > 0 }) {
            out.append(scoped(best))
        }
        if let worst = tones.last(where: { $0.back < $0.total }), worst.tone != tones.first(where: { $0.back > 0 })?.tone {
            out.append(scoped(worst))
        }

        // Late-night slip.
        if let late = fresh.filter({ $0.type == .scroll && ($0.activeMin ?? 0) >= 1 })
            .filter({ let h = calendar.component(.hour, from: $0.ts); return h >= 22 || h < 4 })
            .max(by: { ($0.activeMin ?? 0) < ($1.activeMin ?? 0) }) {
            out.append("Late-night \(MemoryText.place(late.app, late.section)) is a weak spot — \(MemoryText.minutes(late.activeMin)) min at \(MemoryDates.time(late.ts, calendar: calendar)).")
        }

        // Rest overrun.
        if let over = fresh.first(where: { $0.type == .restActivity && ($0.actualMin ?? 0) > Double($0.limitMin ?? .max) }),
           let l = over.limitMin, let a = over.actualMin {
            out.append("\(MemoryText.activity(over.activity)) ran \(MemoryText.minutes(a - Double(l))) min past your \(l)-min limit.")
        }
        return Array(out.prefix(3))
    }

    /// `scope` prefixes multi-nudge counts: "Across the last two days, firm nudges got you back 1 of 2 times."
    static func toneLine(_ tone: String, _ back: Int, _ total: Int, scope: String? = nil) -> String {
        let t = MemoryText.tone(tone)
        if total == 1 {
            return back == 1 ? "A \(tone) nudge got you back. Noted for next time." : "A \(tone) nudge got ignored — trying another tone next time."
        }
        guard let scope else { return "\(t) nudges got you back \(back) of \(total) times." }
        return "\(scope), \(tone) nudges got you back \(back) of \(total) times."
    }

    /// Honest time span behind a tone's cumulative count: "Today" / "Across the last two days" / "Across the
    /// last 9 days" when every counted nudge is still in the event log; "So far" when some came from older,
    /// pruned history (what-works keeps counts the log no longer has).
    static func toneScope(_ tone: String, total: Int, all: [SheepEvent], now: Date, calendar: Calendar) -> String {
        let logged = all.filter {
            $0.type == .nudge && ($0.outcome == "returned" || $0.outcome == "ignored") && ($0.tone ?? "unknown").lowercased() == tone
        }
        guard logged.count == total, let first = logged.map(\.ts).min() else { return "So far" }
        let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                            to: calendar.startOfDay(for: now)).day ?? 0) + 1
        switch days {
        case ...1: return "Today"
        case 2...7: return "Across the last \(["two", "three", "four", "five", "six", "seven"][days - 2]) days"
        default: return "Across the last \(days) days"
        }
    }
}
