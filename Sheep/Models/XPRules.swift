import Foundation

/// XP rules (MVP_PLAN "XP / sheep"). Pure functions — callers apply via `state.progress.add(_:)`.
enum XPRules {
    static let perChecklistItem = 20
    static let sessionComplete = 50
    static let resistedNudge = 15      // chose "back to focus" / left the feed
    static let ignoredNudge = -10      // kept doom-scrolling (wool sheds)
    static let underLimit = 10         // Rest/Play: stayed under the limit you set
    static let perMinuteBlock = 10

    /// One "focused minute-block" = 5 real minutes, or 1 minute with fast timers.
    static func blockMinutes(fast: Bool) -> Int { fast ? 1 : 5 }

    static func focusMinutes(_ minutes: Int, fast: Bool) -> Int {
        max(0, minutes / blockMinutes(fast: fast)) * perMinuteBlock
    }

    /// Total awarded at session end (checklist items are awarded live as they're ticked).
    static func sessionEnd(focusedMinutes: Int, fast: Bool, completed: Bool, reflectionBonus: Int) -> Int {
        focusMinutes(focusedMinutes, fast: fast) + (completed ? sessionComplete : 0) + min(50, max(0, reflectionBonus))
    }

    static func restOrPlay(actualMinutes: Int, limitMinutes: Int) -> Int {
        actualMinutes <= limitMinutes ? underLimit : 0
    }
}
