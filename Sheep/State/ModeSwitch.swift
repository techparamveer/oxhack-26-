import Foundation

/// Applying a `HomePrimary.Plan` — shared by Home's primary button and `sheep://mode/…` links
/// (Shortcuts / App Intents), so both follow the same rules:
/// - a running Focus session is never ended silently (the plan routes back to it);
/// - a running Rest/Play session is ended through `RestController` first (logs it, clears its banner).
extension HomePrimary {
    @MainActor
    static func running(_ state: AppState) -> Running {
        Running(focus: state.activeSession != nil,
                rest: state.restSession != nil && state.restSession?.endedAt == nil,
                play: state.playSession != nil && state.playSession?.endedAt == nil)
    }

    /// Ends whatever the plan says to end, enters Rest/Play when routing there, returns the route to push.
    @MainActor @discardableResult
    static func apply(_ plan: Plan, state: AppState) -> Route {
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
        return plan.route
    }

    /// `sheep://mode/idle`: ends a running Rest/Play; a running Focus is left alone (Home shows "Back to focus").
    @MainActor
    static func stop(state: AppState) {
        let running = running(state)
        if running.rest { RestController.endRest(state: state) }
        if running.play { RestController.endPlay(state: state) }
        if !running.focus && state.mode != .idle { state.setMode(.idle) }
    }
}
