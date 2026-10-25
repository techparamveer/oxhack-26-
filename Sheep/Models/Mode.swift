import SwiftUI

/// The three ways to spend time, plus Idle when no session is running.
enum Mode: String, Codable, CaseIterable, Identifiable {
    case idle, focus, rest, play

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: "Idle"
        case .focus: "Focus"
        case .rest: "Rest"
        case .play: "Play"
        }
    }

    var accent: Color {
        switch self {
        case .idle: Theme.text
        case .focus: Theme.focusAccent
        case .rest: Theme.restAccent
        case .play: Theme.playAccent
        }
    }

    /// Text/icon colour on a filled accent button (Play's yellow takes ink, not white).
    var onAccent: Color {
        switch self {
        case .play: Theme.ink
        case .idle: Theme.background
        default: .white
        }
    }

    /// Modes the user can pick (Idle is the absence of a choice).
    static var selectable: [Mode] { [.focus, .rest, .play] }
}
