import SwiftUI

/// Doom-scroll nudge, presented by WrapperView over the page while
/// `state.scrollMonitor.pendingIntervention` is set. Dark scrim over the page, centred text, one pill.
/// The overlay resolves itself via `ScrollMonitor.userChose(_:)` and routes; WrapperView only shows it.
struct InterventionOverlay: View {
    let request: InterventionRequest
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router
    @State private var appeared = false

    private var nudge: Nudge { request.nudge }

    var body: some View {
        ZStack {
            scrim.ignoresSafeArea()

            VStack(spacing: Theme.space(3)) {
                Spacer()
                SheepView(woolStage: state.progress.woolStage, size: 120, mode: request.mode, xp: state.progress.xp)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .rotationEffect(.degrees(appeared ? 0 : -8))
                    .offset(y: appeared ? 0 : Theme.space(1))
                VStack(spacing: Theme.space(1.5)) {
                    Text(nudge.headline)
                        .font(Theme.title)
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier("nudge.headline")
                    if !nudge.message.isEmpty {
                        Text(nudge.message)
                            .font(Theme.body)
                            .foregroundStyle(Theme.bodyText)
                            .accessibilityIdentifier("nudge.message")
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                Spacer()
                VStack(spacing: Theme.space(1)) {
                    PrimaryButton(title: nudge.primaryLabel, accent: request.mode.accent) {
                        choose(nudge.primaryAction)
                    }
                    .accessibilityIdentifier("nudge.primary")
                    if nudge.primaryAction != .keepGoing {
                        TextButton(title: "keep scrolling", color: Theme.bodyText) { choose(.keepGoing) }
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.space(2))
            // The scrim is dark in both appearances, so resolve Theme colours as dark-mode (light ink).
            .environment(\.colorScheme, .dark)
        }
        .transition(.opacity)
        .sensoryFeedback(.impact(weight: .light), trigger: appeared) { _, new in new }
        .onAppear { withAnimation(Theme.spring) { appeared = true } }
        .accessibilityAddTraits(.isModal)
    }

    /// Dark scrim — the one gradient the design allows, and only at the very top edge (a hint of the page
    /// under the status bar). Everything from ~12 % down is opaque so the copy is crisp on any page
    /// (cookie sheets, thumbnails, white feeds).
    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: Self.scrimColor.opacity(0.6), location: 0),
            .init(color: Self.scrimColor, location: 0.12),
            .init(color: Self.scrimColor, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    private static let scrimColor = Theme.scrim

    private func choose(_ action: NudgeAction) {
        state.scrollMonitor.userChose(action)
        switch action {
        case .keepGoing:
            break
        case .backToFocus:
            router.presentedWrapper = nil
            if state.activeSession != nil { showFocusSession() }
        case .takeBreak, .closeApp:
            router.presentedWrapper = nil
        }
    }

    private func showFocusSession() {
        if let i = router.path.lastIndex(of: .focusSession) {
            router.path = Array(router.path.prefix(through: i))
        } else {
            router.push(.focusSession)
        }
    }
}
