import SwiftUI

/// Home (Opal-style): wordmark + gear → hero sheep → mode label, today's score → mode pills →
/// Sheep's message → one primary button. The floating tab bar is added by `RootTabContent`.
/// Long-press the sheep for the dev menu.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router

    /// Pill the user tapped; nil until they tap one (then the default below applies).
    @State private var picked: Mode?
    @State private var score = DayScore()
    @State private var delta: Int?
    @State private var hapticTick = 0
    private var brief = DailyBriefService.shared

    /// Running mode, else Focus.
    private var defaultSelection: Mode { state.mode == .idle ? .focus : state.mode }
    private var selection: Mode { picked ?? defaultSelection }
    /// Highlighted pill: picked, else the running mode; none when idle (Paper "00 Home — Normal").
    private var pillSelection: Mode? { picked ?? (state.mode == .idle ? nil : state.mode) }
    /// Label + hero art: the running mode; when idle, the pill the user picked (else "No mode on" / awake sheep).
    private var displayMode: Mode { state.mode != .idle ? state.mode : (picked ?? .idle) }

    private var running: HomePrimary.Running {
        HomePrimary.Running(focus: state.activeSession != nil,
                            rest: state.mode == .rest || (state.restSession != nil && state.restSession?.endedAt == nil),
                            play: state.mode == .play || (state.playSession != nil && state.playSession?.endedAt == nil))
    }

    private var message: HomeMessage {
        // The daily brief is about the day (focus-led); other pills explain how to start that mode.
        if selection == defaultSelection,
           let message = HomeMessage.brief(headline: brief.headline, body: brief.body, isFromMemory: brief.isFromMemory) {
            return message
        }
        return .howTo(for: selection, running: running.isRunning(selection))
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    hero
                    ScoreHeader(mode: displayMode, score: score.total, delta: delta)
                        .padding(.top, 6)
                    ModePills(selection: pillSelection, scores: score, onSelect: select)
                        .padding(.top, 16)
                    SheepMessageCard(message: message, isLoading: brief.isLoading)
                        .padding(.horizontal, Theme.cardMargin)
                        .padding(.top, 20)
                    Spacer(minLength: 16)
                    PrimaryButton(title: HomePrimary.title(for: selection, running: running),
                                  accent: selection.accent, icon: "play.fill", action: start)
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTick)
        .onAppear(perform: recompute)
        .onChange(of: state.progress.xp) { recompute() }
        .onChange(of: state.mode) { recompute() }
        .task { await brief.loadIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text("sheep")
                .font(Theme.wordmark)
                .tracking(Theme.Tracking.wordmark)
                .foregroundStyle(Theme.text)
            Spacer()
            IconCircleButton(systemName: "gearshape", label: "Settings") { router.showSettings = true }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 4)
    }

    private var hero: some View {
        // SheepView cross-fades the pose on mode change and sheds wool when xp drops.
        SheepView(woolStage: state.progress.woolStage, size: 196, mode: displayMode, xp: state.progress.xp)
            .frame(width: 196, height: 196)
            .overlay(alignment: .topTrailing) { XPChangeLabel(xp: state.progress.xp) }
            .contentShape(Rectangle())
            .onLongPressGesture { router.showDevMenu = true }
            .accessibilityHint("Long-press for developer menu")
    }

    private func select(_ mode: Mode) {
        hapticTick += 1
        withAnimation(Theme.spring) { picked = mode }
    }

    private func start() {
        hapticTick += 1
        switch HomePrimary.route(for: selection, running: running) {
        case .focusSession: router.push(.focusSession)
        case .focusIntake: router.push(.focusIntake)
        case .rest: state.setMode(.rest); router.push(.rest)
        case .play: state.setMode(.play); router.push(.play)
        default: break
        }
    }

    private func recompute() {
        let result = DayScore.today(events: EventLog.shared.readAll())
        withAnimation(Theme.spring) {
            score = result.score
            delta = result.delta
        }
    }
}

/// Primary-button logic for Home, kept pure for tests.
enum HomePrimary {
    struct Running: Equatable {
        var focus = false
        var rest = false
        var play = false

        func isRunning(_ mode: Mode) -> Bool {
            switch mode {
            case .focus: focus
            case .rest: rest
            case .play: play
            case .idle: false
            }
        }
    }

    static func title(for mode: Mode, running: Running) -> String {
        switch mode {
        case .focus, .idle: running.focus ? "Back to focus" : "Start focus"
        case .rest: running.rest ? "Back to rest" : "Start rest"
        case .play: running.play ? "Back to play" : "Start playing"
        }
    }

    static func route(for mode: Mode, running: Running) -> Route {
        switch mode {
        case .focus, .idle: running.focus ? .focusSession : .focusIntake
        case .rest: .rest
        case .play: .play
        }
    }
}
