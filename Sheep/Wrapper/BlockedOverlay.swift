import SwiftUI

/// Copy for the blocked-section overlay. Tested independently of the view.
enum BlockedCopy {
    /// "Reels are off while you rest."
    static func sectionNote(section: AppSection, mode: Mode) -> String {
        "\(clause(section)) while you \(modeVerb(mode))"
    }

    static func clause(_ section: AppSection) -> String {
        switch section {
        case .reels: "Reels are off"
        case .dms: "messages are off"
        case .shorts: "Shorts are off"
        case .explore: "Explore is off"
        case .feed: "this is off"
        }
    }

    static func modeVerb(_ mode: Mode) -> String {
        switch mode {
        case .focus: "focus"
        case .rest: "rest"
        case .play: "play"
        case .idle: "idle"
        }
    }

    static func backTitle(mode: Mode) -> String {
        switch mode {
        case .rest: "Back to rest"
        case .play: "Back to play"
        default: "Back to focus"
        }
    }
}

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
                SheepView(woolStage: state.progress.woolStage, size: 140, mode: sheepMode, xp: state.progress.xp)
                Text("Not now")
                    .font(Theme.title)
                    .accessibilityIdentifier("blocked.title")
                    .foregroundStyle(Theme.text)
                    .padding(.top, Theme.space(4))
                if state.mode == .focus {
                    Text("you're focusing on \(Text(goal).font(Theme.nunito(17, weight: 800, italic: true)).foregroundStyle(Theme.text))")
                        .font(Theme.body)
                        .foregroundStyle(Theme.bodyText)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.space(1))
                    Caption(BlockedCopy.sectionNote(section: section, mode: .focus).lowercased())
                        .padding(.top, Theme.space(2))
                } else {
                    Text(BlockedCopy.sectionNote(section: section, mode: state.mode))
                        .font(Theme.body)
                        .foregroundStyle(Theme.bodyText)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.space(1))
                }
                Spacer()
                PrimaryButton(title: BlockedCopy.backTitle(mode: state.mode),
                              accent: buttonAccent,
                              action: backToMode)
                    .accessibilityIdentifier("blocked.backToFocus")
                TextButton(title: "stay on the feed", action: onStay)
                    .accessibilityIdentifier("blocked.stay")
                    .padding(.top, Theme.space(1))
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.space(2))
        }
        .onAppear {
            EventLog.shared.append(SheepEvent(type: .blocked, mode: state.mode, app: app, section: section))
        }
    }

    private var sheepMode: Mode {
        state.mode == .idle ? .focus : state.mode
    }

    private var buttonAccent: Color {
        let mode = state.mode == .idle ? Mode.focus : state.mode
        return mode.accent
    }

    private var goal: String {
        let title = state.activeSession?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "your goal" : title
    }

    private func backToMode() {
        router.presentedWrapper = nil
        switch state.mode {
        case .focus:
            if state.activeSession != nil {
                if router.path.last != .focusSession {
                    router.popToRoot()
                    router.push(.focusSession)
                }
            } else {
                router.popToRoot()
            }
        case .rest:
            if router.path.last != .rest {
                router.popToRoot()
                router.push(.rest)
            }
        case .play:
            if router.path.last != .play {
                router.popToRoot()
                router.push(.play)
            }
        case .idle:
            router.popToRoot()
        }
    }
}
