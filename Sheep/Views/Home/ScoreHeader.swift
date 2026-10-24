import SwiftUI

/// "● Focus mode" → big score with delta → "today's score".
struct ScoreHeader: View {
    /// Mode shown in the label; `.idle` → "No mode on" in secondary.
    let mode: Mode
    let score: Int?
    let delta: Int?
    /// Shown dimmed (captioned "yesterday's score") until something is scored today.
    var yesterday: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ModeDot(mode: mode)
                Text(mode == .idle ? "No mode on" : "\(mode.title) mode")
                    .font(Theme.modeLabel)
                    .foregroundStyle(mode == .idle ? Theme.secondary : mode.accent)
            }
            .animation(Theme.spring, value: mode)

            HStack(spacing: 8) {
                Group {
                    if let shown = score ?? yesterday {
                        Text(String(shown))
                            .font(Theme.score)
                            .tracking(Theme.Tracking.score)
                            .monospacedDigit()
                            .foregroundStyle(score == nil ? Theme.tertiary : Theme.text)
                    } else {
                        // Nunito's heavy en dash reads as a loading bar at 72 pt; a lighter, smaller dash reads as "none".
                        Text("–")
                            .font(Theme.nunito(56, weight: 500))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(height: 80)
                .contentTransition(.numericText())
                if score != nil, let delta {
                    // Paper: the triangle is visibly smaller than the 15/800 digits.
                    (Text(delta >= 0 ? "▲" : "▼").font(Theme.nunito(11, weight: 800))
                        + Text(" \(abs(delta))").font(Theme.labelBold))
                        .foregroundStyle(delta >= 0 ? Theme.scoreUp : Theme.scoreDown)
                }
            }

            Text(Self.caption(score: score, yesterday: yesterday))
                .font(Theme.meta)
                .foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// "today's score"; before anything is scored today, yesterday's (dimmed) or "no score yet".
    static func caption(score: Int?, yesterday: Int?) -> String {
        if score != nil { return "today's score" }
        return yesterday != nil ? "yesterday's score" : "no score yet"
    }

    static func deltaText(_ delta: Int) -> String {
        delta >= 0 ? "▲ \(delta)" : "▼ \(abs(delta))"
    }
}
