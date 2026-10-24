import Foundation

/// GEMINI_PROMPTS §5 — Session reflection (Congrats screen).
enum ReflectionPrompt {
    static let system = """
    The session just ended. Write the congrats card.
    - headline: ≤ 6 words celebrating honestly (don't over-praise a weak session).
    - summary: ≤ 30 words: what they finished, focus minutes, and one comparison to yesterday or recent days if MEMORY has it ("double yesterday's focus time").
    - xpBonus: 0–50 based on effort vs plan and nudges resisted.
    - nextStep: ≤ 15 words suggesting what to do next (break length, next item, or mode).
    """

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "headline": ["type": "string"],
            "summary": ["type": "string"],
            "xpBonus": ["type": "integer", "minimum": 0, "maximum": 50],
            "nextStep": ["type": "string"]
        ],
        "required": ["headline", "summary", "xpBonus", "nextStep"]
    ]

    static let temperature = 0.7

    struct Response: Codable, Equatable {
        var headline: String
        var summary: String
        var xpBonus: Int
        var nextStep: String
    }

    static func user(session s: FocusSession, memory: String) -> String {
        let remaining = s.checklist.filter { !$0.done }.map(\.text)
        let scrollMinutes = (s.scrollSeconds / 60 * 10).rounded() / 10
        return """
        SESSION: \(s.title) (\(s.plannedMinutes) min planned, \(s.actualMinutes) min actual)
        CHECKLIST: \(s.doneCount) done / \(s.checklist.count); remaining: \(remaining.isEmpty ? "none" : remaining.joined(separator: "; "))
        NUDGES: \(s.nudgeCount) shown, \(s.nudgesResisted) resisted (went back to focus)
        SCROLL IN WRAPPERS DURING SESSION: \(formatted(scrollMinutes)) min
        MEMORY:
        \(memory)
        """
    }

    static func prompt(session: FocusSession, memory: String) -> GeminiPrompt {
        GeminiPrompt(name: "reflection", system: system, user: user(session: session, memory: memory),
                     schema: schema, temperature: temperature)
    }

    /// Honest offline card: celebrates a full session, doesn't over-praise a weak one.
    static func fallback(session s: FocusSession) -> Response {
        let done = s.doneCount, total = s.checklist.count
        let minutes = s.actualMinutes
        let mins = minutes == 0 ? "under a minute" : "\(minutes) focused minute\(minutes == 1 ? "" : "s")"
        let ratio = total == 0 ? 0 : Double(done) / Double(total)
        let scrolled = s.scrollSeconds >= 60
        let remaining = s.checklist.first { !$0.done }?.text

        let headline: String
        var summary: String
        let nextStep: String
        var bonus = 0

        if total > 0 && done == total {
            headline = "All done. Proper focus."
            summary = "You finished all \(total) items in \(mins)."
            nextStep = "Take a 5-minute break away from the phone."
            bonus = 30
        } else if ratio >= 0.5 {
            headline = "Solid progress."
            summary = "\(done) of \(total) items done in \(mins)."
            nextStep = remaining.map { "After a short break: \(lowerFirst($0))." } ?? "Take a short break, then go again."
            bonus = 15
        } else if done > 0 {
            headline = "A start, not a finish."
            summary = "\(done) of \(total) items in \(mins). Most of the plan is still open."
            nextStep = remaining.map { "Next session, start with: \(lowerFirst($0))." } ?? "Go again with a smaller plan."
            bonus = 5
        } else {
            headline = "Not this time."
            summary = "No items ticked in \(mins). That's honest data, not a verdict."
            nextStep = "Try one Pomodoro with just the first item."
        }
        if s.nudgeCount > 0 {
            summary += " \(s.nudgesResisted) of \(s.nudgeCount) nudges resisted."
            bonus += min(15, s.nudgesResisted * 5)
        }
        if scrolled {
            summary += " \(Int((s.scrollSeconds / 60).rounded())) min lost to scrolling."
            bonus = max(0, bonus - 10)
        }
        return Response(headline: headline, summary: summary, xpBonus: min(50, max(0, bonus)), nextStep: nextStep)
    }

    private static func formatted(_ minutes: Double) -> String {
        minutes == minutes.rounded() ? String(Int(minutes)) : String(format: "%.1f", minutes)
    }

    private static func lowerFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }
}
