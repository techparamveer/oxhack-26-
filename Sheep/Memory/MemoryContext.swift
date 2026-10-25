import Foundation

/// What a prompt is for — lets MemoryContext pick keyword hits (app, goal).
enum MemoryPurpose {
    case dailyBrief
    case planner(goal: String)
    case nudge(app: WrappedApp, section: AppSection, goal: String?)
    case rest(activity: String)
    case reflection(goal: String)

    /// Keywords for alias search.
    var keywords: [String] {
        switch self {
        case .dailyBrief: []
        case .planner(let goal), .reflection(let goal): MemoryContext.words(goal)
        case .nudge(let app, let section, let goal): [app.rawValue, section.rawValue] + MemoryContext.words(goal ?? "")
        case .rest(let activity): [activity.lowercased()] + MemoryContext.words(activity)
        }
    }
}

/// Read path for memory, injected as {{MEMORY}} into every Persona prompt (MVP_PLAN "Memory").
/// Profile + preferences + today/yesterday + last 3 days condensed + active workstreams + top patterns /
/// what-works + alias hits for the purpose's keywords. Capped at ~6,000 chars.
enum MemoryContext {
    static let cap = 6_000
    static let empty = "(no memory yet — this is the user's first day with Sheep; there is no yesterday)"

    static func build(for purpose: MemoryPurpose) -> String {
        build(for: purpose, store: .shared, now: .now)
    }

    static func build(for purpose: MemoryPurpose, store: MemoryStore, now: Date = .now,
                      calendar: Calendar = .current, defaults: UserDefaults = .standard) -> String {
        let files = store.list()
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        var used = Set<String>()
        var sections: [(String, String)] = []
        func add(_ label: String, _ text: String, path: String? = nil) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            sections.append((label, t))
            if let path { used.insert(path) }
        }

        let today = MemoryDates.day(now, calendar: calendar)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterday = MemoryDates.day(yesterdayDate, calendar: calendar)

        if let f = byPath["profile.md"] { add("Profile", clip(f.body, 900), path: f.path) }
        if let prefs = preferences(defaults) { add("Preferences", prefs) }

        let todayPath = "timeline/daily/\(today).md"
        if let f = byPath[todayPath] { add("Today so far (\(today))", clip(f.body, 700), path: todayPath) }
        let yPath = "timeline/daily/\(yesterday).md"
        if let f = byPath[yPath] {
            add("Yesterday (\(MemoryDates.weekday(yesterdayDate, calendar: calendar)) \(yesterday))", clip(f.body, 1_200), path: yPath)
        } else {
            add("Yesterday", "No record of yesterday.")
        }

        let earlier = files.filter { $0.path.hasPrefix("timeline/daily/") && $0.path < yPath && $0.path != todayPath }
            .sorted { $0.path > $1.path }.prefix(3)
        if !earlier.isEmpty {
            let text = earlier.map { f -> String in
                let day = ((f.path as NSString).lastPathComponent as NSString).deletingPathExtension
                return "\(day): " + topLines(f.body, 3).joined(separator: " ")
            }.joined(separator: "\n")
            add("Earlier days", clip(text, 900))
            earlier.forEach { used.insert($0.path) }
        }

        let active = files.filter { $0.path.hasPrefix("workstreams/active/") }
        if !active.isEmpty {
            add("Active workstreams", clip(active.map { clip($0.body, 450) }.joined(separator: "\n\n"), 1_000))
            active.forEach { used.insert($0.path) }
        }
        if let f = byPath["knowledge/patterns.md"] {
            add("Patterns (strongest first)", topLines(f.body, 6).joined(separator: "\n"), path: f.path)
        }
        if let f = byPath["knowledge/what-works.md"] {
            add("What works (nudge tones/actions)", topLines(f.body, 6).joined(separator: "\n"), path: f.path)
        }

        let kws = purpose.keywords
        if !kws.isEmpty {
            let hits = store.search(keywords: kws).filter { !used.contains($0.path) }.prefix(3)
            if !hits.isEmpty {
                add("Related to \(kws.prefix(4).joined(separator: ", "))",
                    hits.map { "[\($0.path)]\n" + clip($0.body, 400) }.joined(separator: "\n\n"))
            }
        }

        let hasMemory = sections.contains { $0.0 != "Yesterday" && $0.0 != "Preferences" }
        guard hasMemory else {
            return sections.first(where: { $0.0 == "Preferences" }).map { "\(empty)\n\n## Preferences\n\($0.1)" } ?? empty
        }

        var out = ""
        for (label, text) in sections {
            let block = "## \(label)\n\(text)\n\n"
            if out.count + block.count > cap {
                let room = cap - out.count
                if room > 80 { out += clip(block, room - 1) }
                break
            }
            out += block
        }
        return String(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(cap))
    }

    /// Voice + autonomy preferences written by Settings (`sheep.voice`, `sheep.askBeforeActing`).
    static func preferences(_ defaults: UserDefaults) -> String? {
        var parts: [String] = []
        switch defaults.string(forKey: "sheep.voice") {
        case "lockIn": parts.append("Voice: blunt \"lock in\" energy.")
        case "gentle": parts.append("Voice: gentle and encouraging.")
        default: break
        }
        if defaults.object(forKey: "sheep.askBeforeActing") != nil {
            parts.append(defaults.bool(forKey: "sheep.askBeforeActing") ? "Ask before acting." : "Can act without asking.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Helpers

    /// First `n` meaningful lines (skips headings and blanks).
    static func topLines(_ body: String, _ n: Int) -> [String] {
        Array(body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .prefix(n))
    }

    static func clip(_ s: String, _ max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        return String(t.prefix(max - 1)) + "…"
    }

    private static let stopwords: Set<String> = ["the", "and", "for", "with", "that", "this", "from", "into", "your",
                                                 "about", "finish", "start", "work", "make", "done", "some", "today"]

    static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= 4 && !stopwords.contains($0) }
    }
}
