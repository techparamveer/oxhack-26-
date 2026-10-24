import SwiftUI

/// Focus / Rest / Play capsules with today's per-mode score. Tapping selects a mode.
struct ModePills: View {
    /// Highlighted pill; nil = none (Home — Normal: idle and nothing tapped yet).
    let selection: Mode?
    let scores: DayScore
    let onSelect: (Mode) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Mode.selectable) { mode in
                pill(mode)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(_ mode: Mode) -> some View {
        let active = mode == selection
        let value = scores.score(for: mode)
        return Button { onSelect(mode) } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: Self.icon(mode))
                        .font(.system(size: mode == .play ? 14 : 15, weight: .semibold))
                    Text(value.map(String.init) ?? "–")
                        .font(Theme.pillNumber)
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.text)
                .frame(width: 96, height: 44)
                .background(Capsule().fill(active ? Theme.surface : Color.clear))
                .overlay(
                    Capsule().strokeBorder(active ? mode.accent : Theme.outline,
                                           lineWidth: active ? Theme.activeOutlineWidth : Theme.outlineWidth)
                )
                Text(mode.title)
                    .font(active ? Theme.labelBold : Theme.label)
                    .foregroundStyle(active ? Theme.text : Theme.secondary)
            }
            .frame(width: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.spring, value: active)
        .accessibilityLabel("\(mode.title), score \(value.map(String.init) ?? "none")")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    static func icon(_ mode: Mode) -> String {
        switch mode {
        case .focus: "hourglass"
        case .rest: "moon"
        case .play: "gamecontroller"
        case .idle: "circle"
        }
    }
}
