import SwiftUI

/// Running Focus session: Pomodoro ring, plan, checklist, wrapper links, one "finish session".
struct FocusSessionView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @State private var timer: PomodoroTimer?
    @State private var isFinishing = false

    var body: some View {
        Screen(title: "focus") {
            if let session = state.activeSession {
                content(session)
            } else {
                Color.clear
            }
        }
        .onAppear(perform: makeTimer)
        .onChange(of: state.activeSession?.id) { _, _ in makeTimer() }
        .task(id: timer?.sessionID) { await timer?.run() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { timer?.tick() } }
        .onChange(of: timer?.isFinished ?? false) { was, now in
            // Auto-finish only when the last Pomodoro ends while the user is looking at this screen.
            if !was && now && scenePhase == .active && router.presentedWrapper == nil && router.path.last == .focusSession {
                finish()
            }
        }
    }

    private func content(_ session: FocusSession) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(session.title)
                    .font(Theme.title)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.space(2))
                if let timer {
                    ring(timer)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.space(3))
                }
                if !session.opener.isEmpty {
                    Text(session.opener)
                        .font(Theme.body)
                        .foregroundStyle(Theme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                checklist(session)
                    .padding(.top, Theme.space(3))
                if !session.watchOut.isEmpty {
                    Caption(session.watchOut)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.space(2))
                }
                HStack(spacing: Theme.space(3)) {
                    ForEach(WrappedApp.allCases) { app in
                        TextButton(title: app.title.lowercased()) { router.open(app) }
                    }
                    Spacer()
                }
                .padding(.top, Theme.space(2))
            }
            .padding(.bottom, Theme.space(2))
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "finish session", accent: Mode.focus.accent, icon: "checkmark",
                          isLoading: isFinishing, action: finish)
                .accessibilityIdentifier("focus.session.finish")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space(2))
                .background(Theme.background)
        }
    }

    // MARK: Ring

    private func ring(_ timer: PomodoroTimer) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: 6)
            Circle()
                .trim(from: 0, to: timer.progressInCurrent)
                .stroke(Mode.focus.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timer.progressInCurrent)
            VStack(spacing: Theme.space(1)) {
                Text(timer.countdownText)
                    .font(Theme.display.monospacedDigit())
                    .tracking(Theme.Tracking.display)
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(countsDown: true))
                Caption(timer.isFinished ? "time's up · tick what you finished"
                        : "pomodoro \(timer.currentPomodoro) of \(timer.pomodoros)")
            }
        }
        .frame(width: 232, height: 232)
        .accessibilityElement(children: .combine)
    }

    // MARK: Checklist

    private func checklist(_ session: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(session.checklist) { item in
                Button {
                    withAnimation(Theme.spring) { FocusController.shared.toggle(itemID: item.id, state: state) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.space(2)) {
                        Image(systemName: item.done ? "checkmark.circle" : "circle")
                            .font(Theme.nunito(20, weight: 600))
                            .fontWeight(.semibold)
                            .foregroundStyle(item.done ? Theme.text : Theme.secondary)
                        Text(item.text)
                            .font(Theme.body)
                            .foregroundStyle(item.done ? Theme.secondary : Theme.text)
                            .strikethrough(item.done, color: Theme.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Theme.space(1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item.done ? .isSelected : [])
                Hairline()
            }
        }
        .sensoryFeedback(.success, trigger: session.doneCount)
    }

    // MARK: Actions

    private func makeTimer() {
        guard let session = state.activeSession else { return }
        guard timer?.sessionID != session.id else { return }
        timer = PomodoroTimer(session: session)
    }

    private func finish() {
        guard !isFinishing, state.activeSession != nil else { return }
        isFinishing = true
        Task { await FocusController.shared.finish(state: state, router: router) }
    }
}
