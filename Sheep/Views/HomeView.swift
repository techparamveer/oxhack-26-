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
                            rest: state.restSession != nil && state.restSession?.endedAt == nil,
                            play: state.playSession != nil && state.playSession?.endedAt == nil)
    }

    private var plan: HomePrimary.Plan { HomePrimary.plan(for: selection, running: running) }

    private var message: HomeMessage {
        // The daily brief is about the day (focus-led): shown when nothing runs and Focus is the pick.
        // Otherwise the card explains the button (how to start, or how to get back to the running mode).
        if running == HomePrimary.Running(), plan.mode == .focus,
           let message = HomeMessage.brief(headline: brief.headline, body: brief.body, isFromMemory: brief.isFromMemory) {
            return message
        }
        // Follow the button (a running Focus keeps it on "Back to focus"), so card and button agree.
        var message = HomeMessage.howTo(for: plan.mode, running: running.isRunning(plan.mode))
        if let end = plan.end { message.body += " Starting ends your \(end == .play ? "play" : "rest")." }
        return message
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
                    PrimaryButton(title: plan.title, accent: plan.mode.accent, icon: "play.fill", action: start)
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
        .onChange(of: state.mode) {
            picked = nil   // a mode started or ended: pills follow the running mode again
            recompute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .memoryDidChange)) { _ in recompute() }
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
        let plan = plan
        // Switching between Rest and Play (or to Focus) ends the running one cleanly first.
        switch plan.end {
        case .rest: RestController.endRest(state: state)
        case .play: RestController.endPlay(state: state)
        default: break
        }
        switch plan.route {
        case .rest: state.setMode(.rest)
        case .play: state.setMode(.play)
        default: break
        }
        router.push(plan.route)
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
///
/// - A running Focus session is never ended from Home: the button stays "Back to focus" whatever pill
///   is picked (other pills only preview).
/// - Starting a mode while a *different* Rest/Play session runs ends that session first (via
///   `RestController`, so it logs its event and clears its notification).
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

    struct Plan: Equatable {
        /// Mode the button acts on (its accent and the card copy follow it).
        var mode: Mode
        var title: String
        /// Running Rest/Play session to end before pushing `route`.
        var end: Mode?
        var route: Route
    }

    static func plan(for selection: Mode, running: Running) -> Plan {
        if running.focus {
            return Plan(mode: .focus, title: "Back to focus", end: nil, route: .focusSession)
        }
        let mode: Mode = selection == .idle ? .focus : selection
        if running.isRunning(mode) {
            return Plan(mode: mode, title: "Back to \(mode == .play ? "play" : mode.title.lowercased())",
                        end: nil, route: route(mode, running: running))
        }
        let end: Mode? = running.rest ? .rest : (running.play ? .play : nil)
        let title = switch mode {
        case .rest: "Start rest"
        case .play: "Start playing"
        default: "Start focus"
        }
        return Plan(mode: mode, title: title, end: end, route: route(mode, running: running))
    }

    static func title(for mode: Mode, running: Running) -> String { plan(for: mode, running: running).title }
    static func route(for mode: Mode, running: Running) -> Route { plan(for: mode, running: running).route }

    private static func route(_ mode: Mode, running: Running) -> Route {
        switch mode {
        case .rest: .rest
        case .play: .play
        default: running.focus ? .focusSession : .focusIntake
        }
    }
}
