import Foundation
import WebKit

/// Where a navigation inside a wrapper should go. Pure, so the host rules are unit-tested.
///
/// - App hosts (`WrappedApp.hosts`) load in the wrapper, subject to the mode `Policy` (path blocking).
/// - Login / consent / CDN hosts (`loginHosts`) always load in the wrapper: Instagram logs in through
///   Facebook and YouTube through Google, and bouncing to Safari mid-login loses the session cookies.
/// - Sub-frames (embeds, login iframes, consent sheets) are never sent to Safari.
/// - Only a *user-initiated* main-frame navigation (link tap / form submit) to a truly foreign host
///   opens in Safari. Script and server redirects to foreign hosts stay in the wrapper — they are
///   almost always part of a sign-in hop (regional Google domains, cookie bounces).
enum WrapperNavigation {
    enum Decision: Equatable {
        case allow
        case cancel
        /// Cancel and show the blocked overlay for this section.
        case block(AppSection)
        /// Cancel and open in Safari.
        case openExternally
    }

    /// Sign-in, consent and asset hosts both wrappers need (exact or subdomain match).
    static let loginHosts = [
        "facebook.com", "m.facebook.com", "www.facebook.com",
        "accounts.google.com", "accounts.youtube.com",
        "consent.google.com", "consent.youtube.com",
        "gstatic.com", "googleusercontent.com",
        "cdninstagram.com", "fbcdn.net"
    ]

    static func isLoginHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return loginHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Hosts that load inside the wrapper (app or sign-in).
    static func staysInWrapper(_ host: String?, app: WrappedApp) -> Bool {
        Policy.isAppHost(host, app: app) || isLoginHost(host)
    }

    static func decide(url: URL, app: WrappedApp, mode: Mode, isMainFrame: Bool, userInitiated: Bool,
                       defaults: UserDefaults = .standard) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["about", "blob", "data", "javascript"].contains(scheme) { return .allow }
        // Never bounce out to the real Instagram/YouTube apps via custom schemes.
        guard scheme == "http" || scheme == "https" else { return .cancel }
        guard isMainFrame else { return .allow }

        if Policy.isAppHost(url.host, app: app) {
            guard Policy.isAllowed(app: app, path: url.path, mode: mode, defaults: defaults) else {
                return .block(Policy.section(app: app, path: url.path))
            }
            return .allow
        }
        if isLoginHost(url.host) { return .allow }
        return userInitiated ? .openExternally : .allow
    }

    /// `target=_blank` / `window.open`: app + sign-in hosts load in place, other web links open in Safari.
    static func decideNewWindow(url: URL, app: WrappedApp) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return .cancel }
        return staysInWrapper(url.host, app: app) ? .allow : .openExternally
    }

    /// Link taps and form submits count as the user leaving; redirects, reloads and back/forward don't.
    static func isUserInitiated(_ type: WKNavigationType) -> Bool {
        type == .linkActivated || type == .formSubmitted
    }
}
