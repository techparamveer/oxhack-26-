import SwiftUI

/// Play: game timer with a limit, work apps muted, small XP for ending under the limit.
struct PlayView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router

    @State private var limit = 60

    private var accent: Color { Mode.play.accent }

    var body: some View {
        Screen(title: "play") {
            VStack(alignment: .leading, spacing: 0) {
                LimitModeLabel(mode: .play)
                    .padding(.top, Theme.space(2))
                if let session = state.playSession {
                    running(session)
                } else {
                    picker
                }
                Hairline().padding(.vertical, Theme.space(3))
                MutedAppsList(mode: .play)
                primary
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.space(2))
            }
        }
        .animation(Theme.spring, value: state.playSession == nil)
        .onDisappear {
            if state.playSession == nil, !router.path.contains(.play), state.mode == .play {
                state.setMode(.idle)
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("how long are you playing?")
                .font(Theme.title)
                .foregroundStyle(Theme.text)
                .padding(.top, Theme.space(1))
            Spacer(minLength: Theme.space(3))
            SectionLabel("game timer")
                .padding(.bottom, Theme.space(2))
            LimitPresetPicker(options: RestController.playLimits, selection: $limit, accent: accent)
            Caption("end under your limit for +\(XPRules.underLimit) xp")
                .padding(.top, Theme.space(2))
            Spacer(minLength: Theme.space(3))
        }
    }

    private func running(_ session: PlaySession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("game on")
                .font(Theme.title)
                .foregroundStyle(Theme.text)
                .padding(.top, Theme.space(1))
            Spacer(minLength: Theme.space(2))
            LimitTimer(startedAt: session.startedAt, limitMinutes: session.limitMinutes,
                       fast: state.fastTimers, accent: accent)
                .frame(maxWidth: .infinity)
            Spacer(minLength: Theme.space(2))
        }
    }

    @ViewBuilder private var primary: some View {
        if state.playSession == nil {
            PrimaryButton(title: "Start playing", accent: accent, icon: "play.fill") {
                RestController.startPlay(limitMinutes: limit, state: state)
            }
            .accessibilityIdentifier("play.start")
        } else {
            PrimaryButton(title: "End play", accent: accent, icon: "stop.fill") {
                RestController.endPlay(state: state)
                router.popToRoot()
            }
            .accessibilityIdentifier("play.end")
        }
    }
}
