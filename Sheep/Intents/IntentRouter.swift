import SwiftUI
import Observation

/// The `sheep://` URLs Sheep understands. Intents, the Setup screen and tests build links here so
/// there is one spelling of every route; `Router.handle(url:state:)` is the one place they are parsed.
enum DeepLink {
    static func open(_ app: WrappedApp) -> URL { URL(string: "sheep://open/\(app.rawValue)")! }
    static func mode(_ mode: Mode) -> URL { URL(string: "sheep://mode/\(mode.rawValue)")! }
}

/// Hand-off from App Intents (which run outside the view tree) to the running app.
///
/// An intent calls `send(_:)`; `RootView` observes `pending` (see `consumesIntentRoutes`) and forwards it
/// to `Router.handle(url:state:)`, so intents and deep links share one code path. `pending` survives until
/// the UI is ready, which covers both a cold launch by the intent and an already-running app.
@MainActor
@Observable
final class IntentRouter {
    static let shared = IntentRouter()

    private(set) var pending: URL?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
        sendLaunchURL(from: environment)
        #endif
    }

    func send(_ url: URL) { pending = url }

    /// Routes the pending URL (if any) and clears it. Returns true if the router handled it.
    @discardableResult
    func deliver(to router: Router, state: AppState) -> Bool {
        guard let url = pending else { return false }
        pending = nil
        return router.handle(url: url, state: state)
    }

    #if DEBUG
    /// QA hook: the simulator asks "Open in Sheep?" for `simctl openurl`, which can't be tapped headless.
    /// `SIMCTL_CHILD_SHEEP_OPEN_URL=sheep://mode/rest xcrun simctl launch <sim> com.oxhack.sheep` sends the
    /// link through the same path an intent uses — at launch (cold) or, with `SHEEP_OPEN_URL_DELAY=<sec>`,
    /// once the app is already running.
    private func sendLaunchURL(from environment: [String: String]) {
        guard let raw = environment["SHEEP_OPEN_URL"], let url = URL(string: raw) else { return }
        guard let delay = environment["SHEEP_OPEN_URL_DELAY"].flatMap(Double.init), delay > 0 else {
            send(url)
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.send(url)
        }
    }
    #endif
}

private struct IntentRouteConsumer: ViewModifier {
    let router: Router
    let state: AppState

    func body(content: Content) -> some View {
        let intents = IntentRouter.shared
        return content.onChange(of: intents.pending, initial: true) { _, url in
            guard url != nil else { return }
            intents.deliver(to: router, state: state)
        }
    }
}

extension View {
    /// Forwards routes sent by App Intents to `router`. Apply once, at the root.
    func consumesIntentRoutes(router: Router, state: AppState) -> some View {
        modifier(IntentRouteConsumer(router: router, state: state))
    }
}
