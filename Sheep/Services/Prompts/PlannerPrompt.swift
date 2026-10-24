import Foundation

/// GEMINI_PROMPTS §2 — Focus planner (after the 3 intake questions).
enum PlannerPrompt {
    static let system = """
    The user is starting a Focus session. Turn their answers into a concrete plan for THIS session only.
    - title: ≤ 6 words naming the session.
    - opener: ≤ 25 words. If MEMORY has something relevant from yesterday or a pattern (e.g. they slip into Reels around minute 12), mention it and say how today will be different.
    - checklist: 3–5 items, each a specific, finishable action that fits in the session length. Start each with a verb. No vague items like "work on essay".
    - watchOut: ≤ 15 words naming their most likely distraction from MEMORY or answer 3, plus a tactic from what-works if available.
    - workstream: short name of the ongoing goal this belongs to (reuse an existing active workstream name from MEMORY if it matches).
    """

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "opener": ["type": "string"],
            "checklist": ["type": "array", "items": ["type": "string"], "minItems": 3, "maxItems": 5],
            "watchOut": ["type": "string"],
            "workstream": ["type": "string"]
        ],
        "required": ["title", "opener", "checklist", "watchOut", "workstream"]
    ]

    static let temperature = 0.6

    struct Response: Codable, Equatable {
        var title: String
        var opener: String
        var checklist: [String]
        var watchOut: String
        var workstream: String
    }

    static func user(minutes: Int, pomodoros: Int, answers: [String], memory: String, now: Date = .now) -> String {
        let a = padded(answers)
        return """
        SESSION LENGTH: \(minutes) minutes (\(pomodoros) × Pomodoro)
        NOW: \(PromptClock.weekday(now)) \(PromptClock.time(now))
        Q1 What do you want to achieve? \(a[0])
        Q2 What does "done" look like? \(a[1])
        Q3 What usually distracts you? \(a[2])
        MEMORY:
        \(memory)
        """
    }

    static func prompt(minutes: Int, pomodoros: Int, answers: [String], memory: String, now: Date = .now) -> GeminiPrompt {
        GeminiPrompt(name: "planner", system: system,
                     user: user(minutes: minutes, pomodoros: pomodoros, answers: answers, memory: memory, now: now),
                     schema: schema, temperature: temperature)
    }

    /// Offline plan built only from the user's answers. Reads naturally, verb-first checklist of 3.
    static func fallback(answers: [String], pomodoros: Int, minutes: Int, workstream: String? = nil) -> Response {
        let a = padded(answers)
        let goal = shortGoal(a[0])
        let done = trimmed(a[1], max: 60)
        let distraction = trimmed(a[2], max: 40)

        let checklist = [
            goal.isEmpty ? "Pick the one thing this session is for" : "Outline the next step of \(goal)",
            done.isEmpty ? "Finish one solid chunk before checking anything" : "Get it to done: \(lowerFirst(done))",
            "Review what you did and note where to start next"
        ]
        let plural = pomodoros == 1 ? "Pomodoro" : "Pomodoros"
        let opener = "\(pomodoros) \(plural), \(minutes) minutes. One item at a time, phone stays boring. Let's lock in."
        let watchOut = distraction.isEmpty
            ? "Reels and Shorts. If you drift, come straight back here."
            : "Watch for \(lowerFirst(distraction)). Drift? Come straight back here."

        return Response(
            title: title(from: goal),
            opener: opener,
            checklist: checklist,
            watchOut: watchOut,
            workstream: workstream ?? (goal.isEmpty ? "focus" : ActiveWorkstream.slug(goal))
        )
    }

    // MARK: Helpers

    private static func padded(_ answers: [String]) -> [String] {
        let clean = answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return clean + Array(repeating: "", count: max(0, 3 - clean.count))
    }

    /// "Dissertation ch.3 — due Fri 30 Oct" → "Dissertation ch.3".
    static func shortGoal(_ goal: String) -> String {
        var g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in [" — ", " – ", " - ", ": ", "; ", ". "] {
            if let r = g.range(of: sep), r.lowerBound > g.startIndex { g = String(g[..<r.lowerBound]) }
        }
        return trimmed(g.trimmingCharacters(in: CharacterSet(charactersIn: ".!")), max: 40)
    }

    private static func title(from goal: String) -> String {
        guard !goal.isEmpty else { return "Focus session" }
        let words = goal.split(separator: " ")
        return words.prefix(6).joined(separator: " ")
    }

    private static func trimmed(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > max else { return t }
        let cut = t.prefix(max)
        if let space = cut.lastIndex(of: " ") { return String(cut[..<space]) + "…" }
        return String(cut) + "…"
    }

    private static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        // Keep acronyms / proper-looking words ("Instagram", "YouTube") as typed.
        let firstWord = s.split(separator: " ").first.map(String.init) ?? s
        let isProper = ["instagram", "youtube", "tiktok", "reels", "shorts", "netflix", "spotify", "whatsapp"]
            .contains(firstWord.lowercased().trimmingCharacters(in: .punctuationCharacters))
        if isProper || firstWord.dropFirst().contains(where: \.isUppercase) { return s }
        return first.lowercased() + s.dropFirst()
    }
}

/// The first active workstream (`workstreams/active/*.md`), parsed leniently, used to pre-fill intake Q1.
struct ActiveWorkstream: Equatable {
    var slug: String      // file name without .md, e.g. "dissertation-ch3"
    var goal: String      // e.g. "Dissertation ch.3 — due Fri 30 Oct"

    static func first(in files: [MemoryFile]) -> ActiveWorkstream? {
        files.filter { $0.path.hasPrefix("workstreams/active/") && $0.path.hasSuffix(".md") }
            .sorted { $0.path < $1.path }
            .lazy.compactMap { parse(path: $0.path, content: $0.content) }.first
    }

    static func current() -> ActiveWorkstream? { first(in: MemoryStore.shared.list()) }

    /// Priority: body "goal:" line → header goal/title → first "# heading" → header id → slug.
    static func parse(path: String, content: String) -> ActiveWorkstream? {
        let slug = (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        var header: [String: String] = [:]
        var body: [String] = []
        var lines = content.components(separatedBy: .newlines)[...]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = lines.dropFirst()
            while let line = lines.first, line.trimmingCharacters(in: .whitespaces) != "---" {
                if let colon = line.firstIndex(of: ":") {
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    header[key] = clean(String(line[line.index(after: colon)...]))
                }
                lines = lines.dropFirst()
            }
            lines = lines.dropFirst()
        }
        body = Array(lines)

        var goal: String?
        for raw in body {
            let line = clean(raw.replacingOccurrences(of: "**", with: ""))
            let stripped = line.drop(while: { "-*• ".contains($0) })
            if stripped.lowercased().hasPrefix("goal:") {
                let value = clean(String(stripped.dropFirst(5)))
                if !value.isEmpty { goal = value; break }
            }
        }
        if goal == nil { goal = [header["goal"], header["title"]].compactMap { $0 }.first { !$0.isEmpty } }
        if goal == nil {
            goal = body.first { $0.hasPrefix("# ") }.map { clean(String($0.dropFirst(2))) }
        }
        if goal == nil || goal!.isEmpty { goal = header["id"].flatMap { $0.isEmpty ? nil : $0 } }
        if goal == nil || goal!.isEmpty {
            goal = slug.replacingOccurrences(of: "-", with: " ").capitalized
        }
        guard let g = goal, !g.isEmpty, !slug.isEmpty else { return nil }
        return ActiveWorkstream(slug: slug, goal: g)
    }

    static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let parts = s.lowercased().unicodeScalars.split { !allowed.contains($0) }.map { String(String.UnicodeScalarView($0)) }
        return parts.prefix(5).joined(separator: "-")
    }

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespaces)
    }
}
