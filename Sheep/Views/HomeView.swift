import SwiftUI

/// Home: sheep, daily brief, one primary mode action, wrappers. Long-press the sheep for the dev menu.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: Theme.space(3))
                SheepView(woolStage: state.progress.woolStage)
                    .frame(maxWidth: .infinity)
                    .onLongPressGesture { router.showDevMenu = true }
                    .accessibilityHint("Long-press for developer menu")
                Caption("level \(state.progress.level) · \(state.progress.xp) xp")
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.space(1))
                Spacer(minLength: Theme.space(3))
                DailyBriefCard()
                Spacer(minLength: Theme.space(3))
                modeActions
                Hairline().padding(.vertical, Theme.space(2))
                wrappers
                footer
            }
            .padding(.vertical, Theme.space(2))
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: Theme.space(1)) {
            ModeDot(mode: state.mode)
            Text(state.mode == .idle ? "sheep" : state.mode.title.lowercased())
                .font(Theme.caption)
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
    }

    private var modeActions: some View {
        VStack(spacing: Theme.space(1)) {
            PrimaryButton(title: primaryTitle, accent: Mode.focus.accent) { go(.focus) }
            HStack {
                TextButton(title: "rest") { go(.rest) }
                Spacer()
                TextButton(title: "play") { go(.play) }
            }
        }
    }

    private var primaryTitle: String {
        state.activeSession == nil ? "Focus" : "Back to focus"
    }

    private var wrappers: some View {
        HStack(spacing: Theme.space(3)) {
            ForEach(WrappedApp.allCases) { app in
                Button { router.open(app) } label: {
                    Label(app.title.lowercased(), systemImage: app.symbol)
                        .font(Theme.body)
                        .foregroundStyle(Theme.text)
                        .symbolRenderingMode(.monochrome)
                        .fontWeight(.light)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            TextButton(title: "notebook") { router.push(.notebook) }
            Spacer()
            TextButton(title: "setup") { router.push(.setup) }
        }
        .padding(.top, Theme.space(1))
    }

    private func go(_ mode: Mode) {
        switch mode {
        case .focus: router.push(state.activeSession == nil ? .focusIntake : .focusSession)
        case .rest: state.setMode(.rest); router.push(.rest)
        case .play: state.setMode(.play); router.push(.play)
        case .idle: break
        }
    }
}

/// Daily brief from memory (GEMINI_PROMPTS §1). STUB — implemented in the Memory step.
struct DailyBriefCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(1)) {
            Text("Morning.").font(Theme.headline).foregroundStyle(Theme.text)
            Text("What do you want to get done today?").font(Theme.body).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
