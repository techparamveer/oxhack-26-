import SwiftUI
import UIKit
import WebKit

/// A message posted by `inject.js` through `window.webkit.messageHandlers.sheep`.
enum WrapperMessage: Equatable {
    case nav(path: String)
    case scroll(px: Double, activeSec: Double, path: String)

    static func parse(_ body: Any) -> WrapperMessage? {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        let path = (dict["path"] as? String) ?? "/"
        switch type {
        case "nav":
            return .nav(path: path)
        case "scroll":
            let px = (dict["px"] as? NSNumber)?.doubleValue ?? 0
            let active = (dict["activeSec"] as? NSNumber)?.doubleValue ?? 0
            guard px > 0 else { return nil }
            return .scroll(px: px, activeSec: active, path: path)
        default:
            return nil
        }
    }
}

/// Owns one `WKWebView` for a wrapped app: scripts, policy enforcement, ScrollMonitor wiring.
/// Lives as `@State` in `WrapperView`, so the page stays alive while overlays are shown.
@Observable
final class WrapperController: NSObject {
    let app: WrappedApp
    @ObservationIgnored let webView: WKWebView

    /// Set while the blocked overlay should show.
    var blocked: AppSection?
    var isLoading = false
    var progress: Double = 0

    @ObservationIgnored private weak var state: AppState?
    @ObservationIgnored private var mode: Mode = .idle
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var started = false

    static let messageName = "sheep"
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    /// `inject.js` from the app bundle.
    static let injectSource: String = {
        guard let url = Bundle(for: WrapperController.self).url(forResource: "inject", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("inject.js missing from bundle")
            return ""
        }
        return source
    }()

    init(app: WrappedApp) {
        self.app = app
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        #if DEBUG
        webView.isInspectable = true
        #endif
        self.webView = webView
        super.init()

        config.userContentController.add(WeakScriptHandler(self), name: Self.messageName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.progress = wv.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.isLoading = wv.isLoading }
            }
        ]
    }

    deinit {
        observations.forEach { $0.invalidate() }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageName)
        webView.stopLoading()
    }

    /// Loads the app's home page once.
    func start(state: AppState) {
        guard !started else { return }
        started = true
        self.state = state
        mode = state.mode
        installScripts()
        webView.load(URLRequest(url: app.homeURL))
    }

    /// Re-applies hiding CSS and re-checks the current page under the new mode.
    func modeChanged(to newMode: Mode) {
        mode = newMode
        installScripts()
        applyCSS()
        if let path = webView.url?.path, !Policy.isAllowed(app: app, path: path, mode: newMode) {
            block(Policy.section(app: app, path: path))
            leaveBlockedPage()
        }
        if Policy.blockedSections(app: app, mode: newMode).isEmpty { blocked = nil }
    }

    func dismissBlocked() { blocked = nil }

    // MARK: Scripts & CSS

    private var cssCall: String {
        let css = Policy.hidingCSS(app: app, mode: mode)
        let literal = (try? String(decoding: JSONEncoder().encode(css), as: UTF8.self)) ?? "\"\""
        return "window.__sheepSetCSS && window.__sheepSetCSS(\(literal));"
    }

    /// inject.js + the current mode's CSS, both at document start so entry points never flash.
    private func installScripts() {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: Self.injectSource, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: cssCall, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func applyCSS() {
        webView.evaluateJavaScript(cssCall, completionHandler: nil)
    }

    // MARK: Messages

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let parsed = WrapperMessage.parse(message.body) else { return }
        // Sign-in pages (facebook.com, accounts.google.com) run inject.js too; their paths aren't the app's.
        guard Policy.isAppHost(message.frameInfo.request.url?.host ?? webView.url?.host, app: app) else { return }
        handle(parsed)
    }

    func handle(_ message: WrapperMessage) {
        switch message {
        case .nav(let path):
            let section = Policy.section(app: app, path: path)
            state?.scrollMonitor.didNavigate(app: app, section: section)
            if !Policy.isAllowed(section: section, mode: mode) {
                block(section)
                leaveBlockedPage()
            }
        case let .scroll(px, activeSec, path):
            guard let state else { return }
            let sample = ScrollSample(app: app, section: Policy.section(app: app, path: path),
                                      path: path, px: px, activeSec: activeSec)
            state.scrollMonitor.ingest(sample, mode: state.mode)
        }
    }

    private func block(_ section: AppSection) {
        blocked = section
    }

    /// `history.back()`; with no history, load the home URL.
    private func leaveBlockedPage() {
        if webView.canGoBack {
            webView.evaluateJavaScript("history.back()", completionHandler: nil)
        } else {
            webView.load(URLRequest(url: app.homeURL))
        }
    }

    /// Leaving to Safari counts as leaving the wrapper (nudge outcome timing).
    private func openExternally(_ url: URL) {
        state?.scrollMonitor.didLeaveWrapper(app: app)
        UIApplication.shared.open(url)
    }
}

// MARK: - WKNavigationDelegate / WKUIDelegate

extension WrapperController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }
        // A nil target frame is a new window (handled in `createWebViewWith`); treat it as main frame.
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        switch WrapperNavigation.decide(url: url, app: app, mode: mode, isMainFrame: isMainFrame,
                                        userInitiated: WrapperNavigation.isUserInitiated(action.navigationType)) {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .block(let section):
            decisionHandler(.cancel)
            block(section)
            if webView.url == nil { webView.load(URLRequest(url: app.homeURL)) }
        case .openExternally:
            decisionHandler(.cancel)
            openExternally(url)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { applyCSS() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { applyCSS() }

    /// `target=_blank` / `window.open`: app + sign-in hosts load in place, everything else opens in Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            switch WrapperNavigation.decideNewWindow(url: url, app: app) {
            case .allow: webView.load(action.request)
            case .openExternally: openExternally(url)
            default: break
            }
        }
        return nil
    }
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WrapperController?
    init(_ target: WrapperController) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message)
    }
}

/// SwiftUI host for the controller's long-lived `WKWebView`.
struct WebView: UIViewRepresentable {
    let controller: WrapperController
    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
