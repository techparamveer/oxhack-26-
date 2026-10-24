import SwiftUI

/// Full-width pill filled with the mode accent. Use for the ONE primary action on a screen.
struct PrimaryButton: View {
    let title: String
    var accent: Color = Theme.text
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(Theme.bodyBold)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(accent == Theme.text ? Theme.background : .white)
            .frame(maxWidth: .infinity)
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
                .font(Theme.body)
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
            .frame(height: 1 / UIScreen.main.scale)
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

/// Caption-style label, used for small meta text.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.secondary)
    }
}

/// Standard screen chrome: off-white background, 24 pt margins, Nunito nav title.
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
