import Foundation
import Observation

enum Route: Hashable {
    case focusIntake, focusSession, congrats, rest, play, notebook, setup, homeScreenIcons
    /// One memory file in Sheep's Notebook (path relative to the memory root).
    case notebookFile(String)
}

/// Root tabs shown in the floating tab bar (only at the navigation root).
enum HomeTab: String, CaseIterable, Identifiable {
    case home, apps, notebook
    var id: String { rawValue }
}

/// Navigation for the single NavigationStack on Home, plus the full-screen wrapper.
@Observable
final class Router {
    var path: [Route] = []
    var presentedWrapper: WrappedApp?
    var showDevMenu = false
    /// Root tab picked in the floating tab bar.
    var tab: HomeTab = .home
    /// Settings sheet (gear on Home).
    var showSettings = false

    func push(_ route: Route) { path.append(route) }
    func replaceTop(with route: Route) {
        if !path.isEmpty { path.removeLast() }
        path.append(route)
    }
    func popToRoot() { path.removeAll() }
    func open(_ app: WrappedApp) { presentedWrapper = app }

    /// `sheep://open/{instagram|youtube}`, `sheep://mode/{focus|rest|play|idle}`. Returns true if handled.
    /// Mode links follow Home's rules (`HomePrimary.plan` + `apply`): a running Focus is never ended (the
    /// link routes back to it); a running Rest/Play is ended through its controller before switching.
    @MainActor @discardableResult
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
            if mode == .idle {
                HomePrimary.stop(state: state)
            } else {
                let plan = HomePrimary.plan(for: mode, running: HomePrimary.running(state))
                push(HomePrimary.apply(plan, state: state))
            }
            return true
        default:
            return false
        }
    }
}
