import SwiftUI
import UIKit

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

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
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
        .sensoryFeedback(.impact(weight: .light), trigger: taps)   // every primary action gets a light tap
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
            .sheepGlassCard()
    }
}

/// 44 pt circular icon button — Liquid Glass on iOS 26+, 1.5 pt outline on earlier OS (settings gear, close).
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
                .sheepGlassCircleButtonChrome()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Standard screen chrome: fog background, 24 pt margins, and our own header row instead of the
/// system navigation bar (iOS 26+ draws its back button as glass): an outlined `IconCircleButton`
/// chevron when the screen was pushed, a centred Nunito title, and an optional trailing control.
/// Swipe-back keeps working (see `UINavigationController` below).
///
/// - `showsBack: false` for roots / screens that must not go back (Congrats, sheet roots).
/// - `backDisabled` hides the back button and blocks swipe-back while true (e.g. while planning).
struct Screen<Content: View, Trailing: View>: View {
    var title: String?
    var showsBack = true
    var backDisabled = false
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPushed

    init(title: String? = nil, showsBack: Bool = true, backDisabled: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.showsBack = showsBack
        self.backDisabled = backDisabled
        self.trailing = trailing
        self.content = content
    }

    private var hasBack: Bool { showsBack && isPushed }
    private var hasHeader: Bool { title != nil || hasBack || ObjectIdentifier(Trailing.self) != ObjectIdentifier(EmptyView.self) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                if hasHeader { header }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, Theme.margin)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { SwipeBack.blocked = hasBack && backDisabled }
        .onChange(of: backDisabled) { _, disabled in SwipeBack.blocked = hasBack && disabled }
        .onDisappear { SwipeBack.blocked = false }
    }

    private var header: some View {
        ZStack {
            if let title {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack {
                if hasBack {
                    IconCircleButton(systemName: "chevron.left", label: "Back") { dismiss() }
                        .accessibilityIdentifier("screen.back")
                        .opacity(backDisabled ? 0 : 1)
                        .disabled(backDisabled)
                }
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .animation(Theme.spring, value: backDisabled)
    }
}

extension Screen where Trailing == EmptyView {
    init(title: String? = nil, showsBack: Bool = true, backDisabled: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, showsBack: showsBack, backDisabled: backDisabled,
                  trailing: { EmptyView() }, content: content)
    }
}

/// Swipe-back with a hidden navigation bar. SwiftUI disables the edge-swipe pop once the system back
/// button is hidden; re-enable it for every stack deeper than its root (unless a screen blocks it).
enum SwipeBack {
    nonisolated(unsafe) static var blocked = false
}

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && !SwipeBack.blocked
    }
}
