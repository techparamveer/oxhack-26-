import SwiftUI

/// Pill filled with the mode accent (56 pt, hugging its label unless `fullWidth`).
/// Use for the ONE primary action on a screen. Play's yellow gets ink text automatically.
struct PrimaryButton: View {
    let title: String
    var accent: Color = Theme.text
    var icon: String? = nil          // SF Symbol, e.g. "play.fill"
    var fullWidth = false
    var isLoading = false
    let action: () -> Void

    private var foreground: Color {
        if accent == Theme.playAccent { return Theme.ink }
        if accent == Theme.text { return Theme.background }
        return .white
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 10) {
                    if let icon {
                        Image(systemName: icon).font(.system(size: 15, weight: .bold))
                    }
                    Text(title).font(Theme.headline)
                }
                .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(foreground)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 32)
            .frame(minWidth: 200, maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 56)
            .background(Capsule().fill(accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

/// Plain text button for secondary actions.
struct TextButton: View {
    let title: String
    var color: Color = Theme.secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.rowTitle)
                .foregroundStyle(color)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 1 px separator.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// Small coloured dot showing the active mode.
struct ModeDot: View {
    let mode: Mode
    var body: some View {
        Circle()
            .fill(mode == .idle ? Theme.secondary : mode.accent)
            .frame(width: 8, height: 8)
    }
}

/// Small secondary meta text ("today's score", status lines).
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.meta)
            .foregroundStyle(Theme.secondary)
    }
}

/// UPPERCASE section label ("SHEEP SAYS", "MODES").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.caption)
            .tracking(Theme.Tracking.caption)
            .foregroundStyle(Theme.secondary)
    }
}

/// White rounded surface (radius 24, no shadow). Allowed ONLY for the Home message card,
/// Settings groups and the tab bar.
struct Surface<Content: View>: View {
    var padding: EdgeInsets = Theme.cardPadding
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface))
    }
}

/// 44 pt circular icon button with a 1.5 pt outline (settings gear, close).
struct IconCircleButton: View {
    let systemName: String
    var label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Theme.outline, lineWidth: Theme.outlineWidth))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Standard screen chrome: fog background, 24 pt margins, Nunito nav title.
struct Screen<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content()
                .padding(.horizontal, Theme.margin)
        }
        .toolbar {
            if let title {
                ToolbarItem(placement: .principal) {
                    Text(title).font(Theme.headline).foregroundStyle(Theme.text)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
    }
}
