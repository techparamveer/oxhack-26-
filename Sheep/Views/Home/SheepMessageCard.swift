import SwiftUI

/// What the Home message card says. Always ends with what to do next.
struct HomeMessage: Equatable {
    var caption: String      // "SHEEP SAYS" / "HOW TO START"
    var meta: String         // "from memory" / current time
    var headline: String
    var body: String
    var isFromMemory: Bool

    /// The daily brief from memory (GEMINI_PROMPTS §1).
    static func fromMemory(headline: String, body: String) -> HomeMessage {
        HomeMessage(caption: "Sheep says", meta: "from memory", headline: headline, body: body, isFromMemory: true)
    }

    /// The memory step's daily brief: "SHEEP SAYS / from memory" when it's built from memory,
    /// else its how-to greeting under "HOW TO START" + the time.
    static func brief(headline: String, body: String, isFromMemory: Bool, now: Date = .now) -> HomeMessage? {
        guard !headline.isEmpty || !body.isEmpty else { return nil }
        if isFromMemory { return .fromMemory(headline: headline, body: body) }
        return HomeMessage(caption: "How to start", meta: now.formatted(date: .omitted, time: .shortened),
                           headline: headline, body: body, isFromMemory: false)
    }

    /// Offline / no-brief copy for the selected mode. `running` = that mode already has a live session.
    static func howTo(for mode: Mode, running: Bool, now: Date = .now) -> HomeMessage {
        let time = now.formatted(date: .omitted, time: .shortened)
        let (headline, body): (String, String)
        switch (mode, running) {
        case (.focus, true):
            (headline, body) = ("You're in focus.", "Tap Back to focus for your timer and checklist. Reels stay hidden.")
        case (.rest, true):
            (headline, body) = ("You're resting.", "Tap Back to rest to see your time left. I'll only nudge if you overrun.")
        case (.play, true):
            (headline, body) = ("You're playing.", "Tap Back to play to see your limit. Stop on time to earn XP.")
        case (.rest, false):
            (headline, body) = ("Rest on purpose.", "Pick something restful and a time limit. DMs open up; I'll only nudge if you overrun.")
        case (.play, false):
            (headline, body) = ("Play, then stop on time.", "Set a play limit. Work apps stay muted; you earn XP for stopping on time.")
        default:
            (headline, body) = ("\(greeting(now)). Ready to lock in?", "Tap Focus, tell me the goal, and I'll plan 3 pomodoros and hide Reels.")
        }
        return HomeMessage(caption: "How to start", meta: time, headline: headline, body: body, isFromMemory: false)
    }

    static func greeting(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 4..<12: "Morning"
        case 12..<18: "Afternoon"
        default: "Evening"
        }
    }
}

/// White card on Home: caption + meta, headline, body.
struct SheepMessageCard: View {
    let message: HomeMessage
    var isLoading = false

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(message.caption)
                    Spacer(minLength: 8)
                    if isLoading {
                        ProgressView().controlSize(.mini).tint(Theme.tertiary)
                    } else {
                        Text(message.meta)
                            .font(Theme.captionMeta)
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                Text(message.headline)
                    .font(Theme.messageHeadline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message.body)
                    .font(Theme.bodySmall)
                    .lineSpacing(1.5)
                    .foregroundStyle(Theme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(Theme.spring, value: message)
        .accessibilityElement(children: .combine)
    }
}
