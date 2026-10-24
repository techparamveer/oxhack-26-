import SwiftUI

/// "● Focus mode" → big score with delta → "today's score".
struct ScoreHeader: View {
    /// Mode shown in the label; `.idle` → "No mode on" in secondary.
    let mode: Mode
    let score: Int?
    let delta: Int?

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
                Text(score.map(String.init) ?? "–")
                    .font(Theme.score)
                    .tracking(Theme.Tracking.score)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(height: 80)
                    .contentTransition(.numericText())
                if let delta {
                    // Paper: the triangle is visibly smaller than the 15/800 digits.
                    (Text(delta >= 0 ? "▲" : "▼").font(Theme.nunito(11, weight: 800))
                        + Text(" \(abs(delta))").font(Theme.labelBold))
                        .foregroundStyle(delta >= 0 ? Theme.scoreUp : Theme.scoreDown)
                }
            }

            Text(score == nil ? "no score yet" : "today's score")
                .font(Theme.meta)
                .foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    static func deltaText(_ delta: Int) -> String {
        delta >= 0 ? "▲ \(delta)" : "▼ \(abs(delta))"
    }
}
