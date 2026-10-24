import Foundation

/// GEMINI_PROMPTS §1 — Daily brief on Home. Fallback = `OfflineBrief` (computed from yesterday's events),
/// or `firstDayFallback` when there is no yesterday.
enum DailyBriefPrompt {
    static let system = """
    Write the one-line brief shown at the top of the Home screen when the user opens Sheep. It should feel like a friend greeting them with yesterday's recap and today's focus.
    - headline: ≤ 10 words.
    - body: ≤ 30 words. Reference one specific thing from yesterday (a win or a slip, with a number or time) and connect it to an active goal or deadline if one exists.
    - suggestedMode: the mode that best fits right now given the time of day and goals.
    If MEMORY has no yesterday, greet them as a first day and ask what they want to get done.
    """

    static let temperature = 0.8

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "headline": ["type": "string"],
            "body": ["type": "string"],
            "suggestedMode": ["type": "string", "enum": ["focus", "rest", "play"]]
        ],
        "required": ["headline", "body", "suggestedMode"]
    ]

    struct Response: Codable, Equatable {
        var headline: String
        var body: String
        var suggestedMode: String
    }

    static func user(now: Date, memory: String) -> String {
        """
        NOW: \(PromptClock.weekday(now)) \(PromptClock.date(now)) \(PromptClock.time(now)) (\(PromptClock.timezone))
        MEMORY:
        \(memory)
        """
    }

    static func prompt(now: Date, memory: String) -> GeminiPrompt {
        GeminiPrompt(name: "daily_brief", system: system, user: user(now: now, memory: memory),
                     schema: schema, temperature: temperature)
    }

    /// No yesterday / no memory: a how-to that always ends in a next step.
    static let firstDayFallback = Response(
        headline: "How to start",
        body: "Tap Focus, tell me the goal, and I'll plan 3 pomodoros and hide Reels.",
        suggestedMode: "focus"
    )
}
