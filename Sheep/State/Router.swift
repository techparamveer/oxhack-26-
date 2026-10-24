import Foundation
import Observation

enum Route: Hashable {
    case focusIntake, focusSession, congrats, rest, play, notebook, setup
    /// One memory file in Sheep's Notebook (path relative to the memory root).
    case notebookFile(String)
}

/// Navigation for the single NavigationStack on Home, plus the full-screen wrapper.
@Observable
final class Router {
    var path: [Route] = []
    var presentedWrapper: WrappedApp?
    var showDevMenu = false

    func push(_ route: Route) { path.append(route) }
    func replaceTop(with route: Route) {
        if !path.isEmpty { path.removeLast() }
        path.append(route)
    }
    func popToRoot() { path.removeAll() }
    func open(_ app: WrappedApp) { presentedWrapper = app }

    /// `sheep://open/{instagram|youtube}`, `sheep://mode/{focus|rest|play}`. Returns true if handled.
    /// Mode links only navigate; starting the mode is done by the destination screen / AppState.
    @discardableResult
    func handle(url: URL, state: AppState) -> Bool {
        guard url.scheme == "sheep", let host = url.host else { return false }
        let arg = url.pathComponents.dropFirst().first ?? ""
        switch host {
        case "open":
            guard let app = WrappedApp(rawValue: arg) else { return false }
            open(app)
            return true
        case "mode":
            guard let mode = Mode(rawValue: arg) else { return false }
            presentedWrapper = nil
            popToRoot()
            switch mode {
            case .focus: push(state.activeSession == nil ? .focusIntake : .focusSession)
            case .rest: state.setMode(.rest); push(.rest)
            case .play: state.setMode(.play); push(.play)
            case .idle: state.setMode(.idle)
            }
            return true
        default:
            return false
        }
    }
}
