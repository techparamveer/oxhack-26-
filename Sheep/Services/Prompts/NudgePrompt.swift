import Foundation

/// What the overlay's primary button does (GEMINI_PROMPTS §3 `primaryAction`).
enum NudgeAction: String, Codable, CaseIterable {
    case backToFocus = "back_to_focus"
    case takeBreak = "take_break"
    case keepGoing = "keep_going"
    case closeApp = "close_app"

    /// Actions that take the user out of the feed/wrapper (count as "returned").
    var leaves: Bool { self != .keepGoing }
}

/// Tone the nudge used — logged with the outcome so the consolidator can learn what works.
enum NudgeTone: String, Codable, CaseIterable {
    case firm, playful, gentle, data
}

/// GEMINI_PROMPTS §3 response.
struct Nudge: Codable, Equatable {
    var headline: String
    var message: String
    var primaryAction: NudgeAction
    var primaryLabel: String
    var tone: NudgeTone
}

/// Everything the §3 user template needs, captured when the threshold is crossed.
struct NudgeInput: Equatable {
    var mode: Mode
    var app: WrappedApp
    var section: AppSection
    var activeMinutes: Double
    var nudgesThisSession: Int
    var sessionTitle: String?
    var done: Int
    var total: Int
    /// Seconds left in the current Pomodoro (0 once every planned Pomodoro has elapsed); nil outside Focus.
    var secondsLeft: Int?
    var restActivity: String?
    var restLimitMinutes: Int?
    var now: Date
    var voice: NudgePrompt.Voice = .lockIn
}

/// GEMINI_PROMPTS §3 — doom-scroll nudge shown inside a wrapper.
enum NudgePrompt {
    /// Settings "Voice" preference, stored in UserDefaults `sheep.voice` (`lockIn` default / `gentle`).
    enum Voice: String {
        case lockIn, gentle
        static let defaultsKey = "sheep.voice"
        static func current(_ defaults: UserDefaults = .standard) -> Voice {
            defaults.string(forKey: defaultsKey).flatMap(Voice.init(rawValue:)) ?? .lockIn
        }
    }

    static let system = """
    The user has been scrolling continuously inside a wrapped app. Write the overlay that interrupts them.
    - headline: ≤ 8 words, punchy.
    - message: ≤ 25 words. Name their session goal or active workstream, the real minutes scrolled, and — if MEMORY has it — the matching pattern from yesterday or recent days ("this is exactly when Reels got you yesterday").
    - primaryAction: what the main button should do.
    - primaryLabel: ≤ 4 words for that button.
    - tone: which tone you used, so the app can log whether it worked.
    Mode guidance:
    - focus: firm. Default primaryAction "back_to_focus".
    - rest: gentle. They're allowed to be here; only nudge about duration. Default "take_break" or "keep_going".
    - play / idle: light touch.
    Follow what-works in MEMORY over these defaults (e.g. if humour works and guilt doesn't, use humour).
    """

    static let temperature = 0.9

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "headline": ["type": "string"],
            "message": ["type": "string"],
            "primaryAction": ["type": "string", "enum": ["back_to_focus", "take_break", "keep_going", "close_app"]],
            "primaryLabel": ["type": "string"],
            "tone": ["type": "string", "enum": ["firm", "playful", "gentle", "data"]]
        ],
        "required": ["headline", "message", "primaryAction", "primaryLabel", "tone"]
    ]

    static func user(_ input: NudgeInput, memory: String) -> String {
        """
        MODE: \(input.mode.rawValue)
        APP: \(input.app.rawValue)  SECTION: \(input.section.rawValue)
        SCROLLED: \(minutesString(input.activeMinutes)) min continuous, \(input.nudgesThisSession) nudges already this session
        SESSION GOAL: \(goalLine(input)) — checklist \(checklistLine(input)) done, \(promptTimeLeft(input.secondsLeft)) left in Pomodoro
        NOW: \(PromptClock.time(input.now))\(input.voice == .gentle ? "\nVOICE: gentle" : "")
        MEMORY:
        \(memory)
        """
    }

    static func prompt(_ input: NudgeInput, memory: String) -> GeminiPrompt {
        GeminiPrompt(name: "nudge", system: system, user: user(input, memory: memory),
                     schema: schema, temperature: temperature)
    }

    /// Live call with memory; falls back to `fallback(_:)` offline / on timeout.
    static func generate(_ input: NudgeInput) async -> Nudge {
        let memory = MemoryContext.build(for: .nudge(app: input.app, section: input.section, goal: input.sessionTitle))
        return await GeminiClient.shared.generate(Nudge.self, prompt(input, memory: memory), fallback: fallback(input)).value
    }

    // MARK: Fallback

    /// Hardcoded copy per mode that still names the real goal and minutes.
    static func fallback(_ input: NudgeInput) -> Nudge {
        let scrolled = durationPhrase(input.activeMinutes)
        let place = placePhrase(app: input.app, section: input.section)
        switch input.mode {
        case .focus:
            let goal = input.sessionTitle.map { "“\($0)”" } ?? "your focus session"
            let left = fallbackTimeLeft(input.secondsLeft)
            if input.voice == .gentle {
                return Nudge(headline: "a little check-in",
                             message: "\(scrolled) on \(place). \(goal) is still there when you're ready.\(left)",
                             primaryAction: .backToFocus, primaryLabel: "back to focus", tone: .gentle)
            }
            return Nudge(headline: "\(shortPlace(input.section)) can wait",
                         message: "\(scrolled) on \(place). \(goal) is waiting.\(left)",
                         primaryAction: .backToFocus, primaryLabel: "back to focus", tone: .firm)
        case .rest:
            let plan = input.restActivity.map { activity in
                input.restLimitMinutes.map { " You planned \($0) min of \(activity)." } ?? " You planned \(activity)."
            } ?? ""
            return Nudge(headline: input.voice == .gentle ? "how's your rest going?" : "still enjoying this?",
                         message: "\(scrolled) straight on \(place).\(plan) Rest is yours — maybe stretch your legs?",
                         primaryAction: .takeBreak, primaryLabel: "take a break", tone: .gentle)
        case .play, .idle:
            return Nudge(headline: "quick check-in",
                         message: "\(scrolled) on \(place) so far. Still having fun?",
                         primaryAction: .keepGoing, primaryLabel: "all good", tone: .playful)
        }
    }

    // MARK: Formatting

    /// "0.5", "3", "12.5" — one decimal, trailing ".0" dropped.
    static func minutesString(_ minutes: Double) -> String {
        let rounded = (minutes * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    /// "45 seconds" under a minute, otherwise "3 min".
    static func durationPhrase(_ minutes: Double) -> String {
        if minutes < 1 { return "\(Int((minutes * 60).rounded())) seconds" }
        return "\(Int(minutes.rounded())) min"
    }

    static func placePhrase(app: WrappedApp, section: AppSection) -> String {
        switch section {
        case .feed: "the \(app.title) feed"
        case .reels: "Reels"
        case .shorts: "Shorts"
        case .dms: "\(app.title) DMs"
        }
    }

    static func shortPlace(_ section: AppSection) -> String {
        switch section {
        case .feed: "the feed"
        case .reels: "Reels"
        case .shorts: "Shorts"
        case .dms: "DMs"
        }
    }

    /// "1/3"; "n/a" outside a Focus session (Rest/Play/idle have no checklist).
    private static func checklistLine(_ input: NudgeInput) -> String {
        input.total > 0 || input.sessionTitle != nil ? "\(input.done)/\(input.total)" : "n/a"
    }

    private static func goalLine(_ input: NudgeInput) -> String {
        if let title = input.sessionTitle { return title }
        if let activity = input.restActivity {
            return input.restLimitMinutes.map { "rest — \(activity), \($0) min limit" } ?? "rest — \(activity)"
        }
        return "none"
    }

    /// Seconds left in the current Pomodoro (rounded up), 0 once all planned Pomodoros have elapsed.
    static func secondsLeftInPomodoro(_ session: FocusSession, now: Date) -> Int {
        let pomo = Double(max(1, session.pomodoroMinutes)) * 60
        let elapsed = max(0, now.timeIntervalSince(session.startedAt))
        guard elapsed < pomo * Double(max(1, session.pomodoros)) else { return 0 }
        let left = pomo - elapsed.truncatingRemainder(dividingBy: pomo)
        return Int(left.rounded(.up))
    }

    /// Whole minutes for display, rounded to the nearest minute; nil under a minute ("under a minute").
    static func displayMinutes(secondsLeft: Int) -> Int? {
        secondsLeft < 60 ? nil : Int((Double(secondsLeft) / 60).rounded())
    }

    /// Prompt template value: "12 min", "under a minute", "0 min" (time's up), "n/a min" outside Focus.
    static func promptTimeLeft(_ secondsLeft: Int?) -> String {
        guard let secondsLeft else { return "n/a min" }
        if secondsLeft <= 0 { return "0 min" }
        return displayMinutes(secondsLeft: secondsLeft).map { "\($0) min" } ?? "under a minute"
    }

    /// Fallback sentence: " 12 min left in this pomodoro." / " Under a minute left in this pomodoro.";
    /// empty outside Focus or once the planned Pomodoros are over.
    static func fallbackTimeLeft(_ secondsLeft: Int?) -> String {
        guard let secondsLeft, secondsLeft > 0 else { return "" }
        guard let minutes = displayMinutes(secondsLeft: secondsLeft) else { return " Under a minute left in this pomodoro." }
        return " \(minutes) min left in this pomodoro."
    }
}
