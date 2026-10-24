import SwiftUI

/// Calm overlay shown over the page (scrim, no glass) when the current mode blocks a section.
struct BlockedOverlay: View {
    let app: WrappedApp
    let section: AppSection
    /// Hides the overlay and leaves the user on the (allowed) feed.
    let onStay: () -> Void

    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            // Opaque fog over the live page (no glass): the page stays alive underneath but never
            // shows through, so the copy is crisp on busy pages (consent sheets, thumbnails).
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                SheepView(woolStage: state.progress.woolStage, size: 140)
                Text("Not now")
                    .font(Theme.title)
                    .foregroundStyle(Theme.text)
                    .padding(.top, Theme.space(4))
                Text("you're focusing on \(Text(goal).font(Theme.nunito(17, weight: 800, italic: true)).foregroundStyle(Theme.text))")
                    .font(Theme.body)
                    .foregroundStyle(Theme.bodyText)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.space(1))
                Caption(sectionNote)
                    .padding(.top, Theme.space(2))
                Spacer()
                PrimaryButton(title: "Back to focus", accent: Mode.focus.accent, action: backToFocus)
                TextButton(title: "stay on the feed", action: onStay)
                    .padding(.top, Theme.space(1))
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.space(2))
        }
        .onAppear {
            EventLog.shared.append(SheepEvent(type: .blocked, mode: state.mode, app: app, section: section))
        }
    }

    private var goal: String {
        let title = state.activeSession?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "your goal" : title
    }

    private var sectionNote: String {
        let name: String = switch section {
        case .reels: "reels"
        case .dms: "messages"
        case .shorts: "shorts"
        case .feed: "this"
        }
        return "\(name) are off while you focus"
    }

    private func backToFocus() {
        router.presentedWrapper = nil
        if state.activeSession != nil {
            if router.path.last != .focusSession {
                router.popToRoot()
                router.push(.focusSession)
            }
        } else {
            router.popToRoot()
        }
    }
}
