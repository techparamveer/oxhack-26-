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

    /// Offline plan built from the user's answers plus what's already on device: the workstream's
    /// "next step" becomes the first item and yesterday's recap (`OfflineBrief.recapSentence`) opens it.
    /// Reads naturally, verb-first checklist of 3.
    static func fallback(answers: [String], pomodoros: Int, minutes: Int, workstream: String? = nil,
                         nextStep: String? = nil, recap: String? = nil) -> Response {
        let a = padded(answers)
        let goal = shortGoal(a[0])
        let done = trimmed(a[1], max: 60)
        let distraction = trimmed(a[2], max: 40)
        // "Plan the next chunk — last session was complete." → "Plan the next chunk"
        let next = nextStep
            .map { s in (s.components(separatedBy: " — ").first ?? s).trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
            .flatMap { $0.isEmpty ? nil : trimmed($0, max: 70) }

        let checklist = [
            next ?? (goal.isEmpty ? "Pick the one thing this session is for" : "Outline the next step of \(goal)"),
            done.isEmpty ? "Finish one solid chunk before checking anything" : "Get it to done: \(lowerFirst(done))",
            "Review what you did and note where to start next"
        ]
        let plural = pomodoros == 1 ? "Pomodoro" : "Pomodoros"
        var opener = "\(pomodoros) \(plural), \(minutes) minutes. One item at a time, phone stays boring. Let's lock in."
        if let recap = recap?.trimmingCharacters(in: .whitespacesAndNewlines), !recap.isEmpty {
            let withRecap = "\(recap) Today: \(pomodoros) \(plural), one item at a time."
            if withRecap.split(separator: " ").count <= 25 { opener = withRecap }
        }
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
    var goal: String      // e.g. "Dissertation ch.3"
    var nextStep: String? = nil   // e.g. "Write the 3 intro paragraphs from yesterday's outline"

    static func first(in files: [MemoryFile]) -> ActiveWorkstream? {
        files.filter { $0.path.hasPrefix("workstreams/active/") && $0.path.hasSuffix(".md") }
            .sorted { $0.path < $1.path }
            .lazy.compactMap { parse(path: $0.path, content: $0.content) }.first
    }

    static func current() -> ActiveWorkstream? { first(in: MemoryStore.shared.list()) }

    /// Priority: first "# heading" (the workstream's name, e.g. "Dissertation ch.3") → header title/goal →
    /// body "goal:" line → header id → slug. The name reads best as the Q1 answer and as the offline title;
    /// the seeded/consolidated files all start their body with it.
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

        func nonEmpty(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : $0 } }
        var goal = nonEmpty(body.first { $0.hasPrefix("# ") }.map { clean(String($0.dropFirst(2))) })
        if goal == nil { goal = nonEmpty(header["title"]) ?? nonEmpty(header["goal"]) }
        if goal == nil {
            for raw in body {
                let line = clean(raw.replacingOccurrences(of: "**", with: ""))
                let stripped = line.drop(while: { "-*• ".contains($0) })
                if stripped.lowercased().hasPrefix("goal:"), let value = nonEmpty(clean(String(stripped.dropFirst(5)))) {
                    goal = value; break
                }
            }
        }
        if goal == nil { goal = nonEmpty(header["id"]) }
        if goal == nil { goal = nonEmpty(slug.replacingOccurrences(of: "-", with: " ").capitalized) }
        guard let g = goal, !slug.isEmpty else { return nil }
        return ActiveWorkstream(slug: slug, goal: g, nextStep: nextStep(in: body))
    }

    /// First bullet under "## Next step", if it reads like an action (used as the offline plan's first item).
    static func nextStep(in body: [String]) -> String? {
        guard let i = body.firstIndex(where: { $0.lowercased().hasPrefix("## next step") }) else { return nil }
        for raw in body[(i + 1)...] {
            if raw.hasPrefix("## ") { break }
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            let text = clean(String(line.dropFirst(2))).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return text.isEmpty ? nil : text
        }
        return nil
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
