import Foundation

/// GEMINI_PROMPTS §6 — Memory consolidator. NO persona (a librarian, not Sheep). Timeout 15 s.
/// Fallback = `OfflineConsolidator` (deterministic, computed from the same events).
enum ConsolidatorPrompt {
    static let system = """
    You maintain the long-term memory of a screen-time coaching app. You receive the user's current memory files and new raw events. Return the updated files.

    Files you may write (markdown, each starting with a YAML header: id, type, aliases, updated):
    - profile.md (type: profile) — sections: "Life context", "Tone that works", "Autonomy". ≤ 200 words.
    - timeline/daily/YYYY-MM-DD.md (type: daily) — for each day touched by the events: planned vs done, focus minutes, sessions, where they slipped (app, section, time, minutes), wins. Bullets with times. ≤ 150 words per day.
    - knowledge/patterns.md (type: patterns) — recurring distraction patterns, each a bullet with evidence count and last-seen date, e.g. "- Slips into Instagram Reels ~12 min into Focus (seen 3×, last 2026-10-24)". Max 10 bullets, strongest first.
    - knowledge/what-works.md (type: procedural) — which nudge tones/actions led them back vs were ignored, with counts. Max 8 bullets.
    - workstreams/active/<slug>.md (type: workstream) — one per ongoing goal: goal, deadline if stated, progress log (dated bullets), next step.
    - workstreams/completed/<slug>.md — move a workstream here when the user finishes it.

    Rules:
    - Rewrite, don't append. Keep files short and current.
    - Generalise repeated examples into traits; keep one dated example as evidence.
    - Move temporary details (one-off tasks, this-week deadlines) into workstreams, not the profile.
    - If new events contradict a stored fact, replace it with a dated correction ("Deadline moved to Fri 30 Oct (was Wed), 2026-10-24").
    - Drop incidental noise. Never store message/post content — only apps, sections, times, durations and the user's own typed goals.
    - Aliases: list 3–8 lowercase keywords someone might search to find the file (app names, goal words, synonyms).
    - Only include files that changed. Use exact relative paths.
    - learned: 1–3 short, user-facing sentences about what you newly learned ("Mornings are your best focus time."). Empty if nothing meaningful.
    - NEVER invent events not present in the input.
    """

    static let temperature = 0.2
    static let timeout: TimeInterval = 15

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "files": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"],
                        "content": ["type": "string"],
                        "op": ["type": "string", "enum": ["write", "move_to_completed"]]
                    ],
                    "required": ["path", "content", "op"]
                ]
            ],
            "learned": ["type": "array", "items": ["type": "string"], "maxItems": 3]
        ],
        "required": ["files", "learned"]
    ]

    static func user(today: String, reason: MemoryConsolidator.Reason, files: [MemoryFile],
                     lastRunAt: Date?, events: String) -> String {
        var s = "TODAY: \(today)   RUN REASON: \(reason.rawValue)\nCURRENT MEMORY FILES:\n"
        for f in files {
            s += "=== \(f.path) ===\n\(f.content)\n"
        }
        let since = lastRunAt.map { ISO8601DateFormatter().string(from: $0) } ?? "the beginning"
        s += "\nNEW EVENTS (JSONL, since \(since)):\n\(events)"
        return s
    }

    static func prompt(today: String, reason: MemoryConsolidator.Reason, files: [MemoryFile],
                       lastRunAt: Date?, events: String) -> GeminiPrompt {
        GeminiPrompt(name: "consolidator", system: system,
                     user: user(today: today, reason: reason, files: files, lastRunAt: lastRunAt, events: events),
                     schema: schema, temperature: temperature, timeout: timeout, usePersona: false)
    }

    /// Hardcoded "nothing changed" fallback (the consolidator normally falls back to `OfflineConsolidator`).
    static let emptyFallback = ConsolidatorResponse(files: [], learned: [])
}

/// `{ files: [{path, content, op}], learned: [str] }`
struct ConsolidatorResponse: Codable, Equatable {
    struct File: Codable, Equatable {
        enum Op: String, Codable { case write, moveToCompleted = "move_to_completed" }
        var path: String
        var content: String
        var op: Op

        init(path: String, content: String, op: Op = .write) {
            self.path = path; self.content = content; self.op = op
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decode(String.self, forKey: .path)
            content = (try? c.decode(String.self, forKey: .content)) ?? ""
            op = (try? c.decode(Op.self, forKey: .op)) ?? .write
        }
    }

    var files: [File]
    var learned: [String]

    init(files: [File], learned: [String]) {
        self.files = files; self.learned = learned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = (try? c.decode([File].self, forKey: .files)) ?? []
        learned = (try? c.decode([String].self, forKey: .learned)) ?? []
    }
}
