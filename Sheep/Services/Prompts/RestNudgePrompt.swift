import Foundation

/// GEMINI_PROMPTS §4 — Rest overuse nudge (local notification text).
enum RestNudgePrompt {
    static let system = """
    The user is in Rest mode and has exceeded the time they set for an activity. Write a local notification.
    - title: ≤ 6 words. body: ≤ 20 words.
    Be kind — rest is good. Mention the real duration and suggest one concrete next thing (stretch, water, sleep if late, or an upcoming deadline from MEMORY if it's soon).
    """

    static func user(activity: String, limitMinutes: Int, actualMinutes: Int, now: Date, memory: String) -> String {
        """
        ACTIVITY: \(activity)   SET LIMIT: \(limitMinutes) min   ACTUAL: \(actualMinutes) min
        NOW: \(PromptClock.time(now))
        MEMORY:
        \(memory)
        """
    }

    static let schema: JSONValue = [
        "type": "object",
        "properties": ["title": ["type": "string"], "body": ["type": "string"]],
        "required": ["title", "body"]
    ]

    static let temperature = 0.8

    struct Response: Codable, Equatable {
        var title: String
        var body: String
    }

    static func prompt(activity: String, limitMinutes: Int, actualMinutes: Int, now: Date, memory: String) -> GeminiPrompt {
        GeminiPrompt(name: "rest_nudge", system: system,
                     user: user(activity: activity, limitMinutes: limitMinutes, actualMinutes: actualMinutes, now: now, memory: memory),
                     schema: schema, temperature: temperature)
    }

    /// Kind, offline copy: mentions the real duration and one concrete next thing.
    static func fallback(activity: String, limitMinutes: Int, actualMinutes: Int, now: Date) -> Response {
        let hour = Calendar.current.component(.hour, from: now)
        let late = hour >= 22 || hour < 5
        let what = activity.isEmpty ? "rest" : activity.lowercased()
        let next = late ? "it's late — wind down and get some sleep 🐑" : "stand up, stretch and grab some water 🐑"
        return Response(title: "that was a good rest",
                        body: "\(actualMinutes) min of \(what), past your \(limitMinutes). \(next)")
    }

    static func generate(activity: String, limitMinutes: Int, actualMinutes: Int, now: Date,
                         client: GeminiClient = .shared) async -> Response {
        let memory = MemoryContext.build(for: .rest(activity: activity))
        let p = prompt(activity: activity, limitMinutes: limitMinutes, actualMinutes: actualMinutes, now: now, memory: memory)
        return await client.generate(Response.self, p,
                                     fallback: fallback(activity: activity, limitMinutes: limitMinutes,
                                                        actualMinutes: actualMinutes, now: now)).value
    }
}
