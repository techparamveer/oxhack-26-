import Foundation

/// Mode policy — single source of truth (MVP_PLAN "Mode policy", Settings → "Hidden by mode").
///
/// Defaults (user-configurable per mode; the feed is never blocked; Idle never blocks):
///
/// |                      | Focus   | Rest    | Play    | Idle    |
/// |----------------------|---------|---------|---------|---------|
/// | Instagram feed       | allowed | allowed | allowed | allowed |
/// | Instagram Reels      | blocked | allowed | allowed | allowed |
/// | Instagram Explore    | blocked | allowed | allowed | allowed |
/// | Instagram DMs        | blocked | allowed | allowed | allowed |
/// | YouTube Shorts       | blocked | allowed | allowed | allowed |
///
/// Read only via `blockedSections(in:)`. Blocking is by URL path (robust); `hidingCSS` only hides
/// entry points cosmetically. Focus keeps the existing `sheep.blockedInFocus` key.
enum Policy {
    /// Coarse section from a URL path (query/fragment ignored; a full URL is accepted too).
    static func section(app: WrappedApp, path: String) -> AppSection {
        let parts = components(of: path)
        switch app {
        case .instagram:
            if parts.first == "direct" { return .dms }
            // `/reels/…`, `/reel/<id>/`, and a profile's reels tab `/<user>/reels/`.
            if parts.first == "reel" || parts.first == "reels" || parts.dropFirst().first == "reels" { return .reels }
            if parts.first == "explore" { return .explore }
            return .feed
        case .youtube:
            return parts.first == "shorts" ? .shorts : .feed
        }
    }

    static func isAllowed(app: WrappedApp, path: String, mode: Mode, defaults: UserDefaults = .standard) -> Bool {
        isAllowed(section: section(app: app, path: path), mode: mode, defaults: defaults)
    }

    static func isAllowed(section: AppSection, mode: Mode, defaults: UserDefaults = .standard) -> Bool {
        !blockedSections(in: mode, defaults: defaults).contains(section)
    }

    // MARK: Per-mode blocked sections (Settings drives this)

    /// UserDefaults key: array of `AppSection` raw values blocked in Focus. Missing → Focus defaults.
    static let blockedInFocusKey = "sheep.blockedInFocus"
    static let blockedInRestKey = "sheep.blockedInRest"
    static let blockedInPlayKey = "sheep.blockedInPlay"

    static var defaultBlockedInFocus: Set<AppSection> { defaultBlocked(in: .focus) }

    /// Persistence key for a mode's hidden sections. Idle has none.
    static func blockedKey(for mode: Mode) -> String? {
        switch mode {
        case .focus: blockedInFocusKey
        case .rest: blockedInRestKey
        case .play: blockedInPlayKey
        case .idle: nil
        }
    }

    static func defaultBlocked(in mode: Mode) -> Set<AppSection> {
        switch mode {
        case .focus: [.reels, .dms, .shorts, .explore]
        case .rest, .play, .idle: []
        }
    }

    /// THE single read of what a mode blocks. The feed is never blocked.
    static func blockedSections(in mode: Mode, defaults: UserDefaults = .standard) -> Set<AppSection> {
        guard let key = blockedKey(for: mode) else { return [] }
        guard let raw = defaults.array(forKey: key) as? [String] else { return defaultBlocked(in: mode) }
        return Set(raw.compactMap(AppSection.init(rawValue:))).subtracting([.feed])
    }

    static func setBlocked(_ sections: Set<AppSection>, in mode: Mode, defaults: UserDefaults = .standard) {
        guard let key = blockedKey(for: mode) else { return }
        defaults.set(sections.subtracting([.feed]).map(\.rawValue).sorted(), forKey: key)
    }

    static func setBlockedInFocus(_ sections: Set<AppSection>, defaults: UserDefaults = .standard) {
        setBlocked(sections, in: .focus, defaults: defaults)
    }

    /// Sections of `app` that `mode` blocks, in display order.
    static func blockedSections(app: WrappedApp, mode: Mode, defaults: UserDefaults = .standard) -> [AppSection] {
        let blocked = blockedSections(in: mode, defaults: defaults)
        return sections(of: app).filter(blocked.contains)
    }

    static func sections(of app: WrappedApp) -> [AppSection] {
        switch app {
        case .instagram: [.feed, .reels, .explore, .dms]
        case .youtube: [.feed, .shorts]
        }
    }

    /// CSS hiding the entry points of blocked sections. Empty when nothing is blocked.
    /// One rule per selector so an unsupported selector can't drop the others.
    static func hidingCSS(app: WrappedApp, mode: Mode, defaults: UserDefaults = .standard) -> String {
        blockedSections(app: app, mode: mode, defaults: defaults)
            .flatMap { hidingSelectors(app: app, section: $0) }
            .map { "\($0) { display: none !important; }" }
            .joined(separator: "\n")
    }

    static func hidingSelectors(app: WrappedApp, section: AppSection) -> [String] {
        switch (app, section) {
        case (.instagram, .reels):
            [#"a[href*="/reels/"]"#, #"a[href$="/reels"]"#, #"a[href^="/reel/"]"#, #"a[href*="/reel/"]"#]
        case (.instagram, .explore):
            [#"a[href^="/explore/"]"#, #"a[href*="/explore/"]"#]
        case (.instagram, .dms):
            [#"a[href^="/direct/"]"#, #"a[href*="/direct/"]"#, #"a[href$="/direct"]"#]
        case (.youtube, .shorts):
            [#"a[href*="/shorts"]"#,
             "ytm-reel-shelf-renderer",
             "ytm-shorts-lockup-view-model",
             "ytm-shorts-lockup-view-model-v2",
             "ytm-rich-section-renderer:has(ytm-reel-shelf-renderer)",
             "ytm-rich-section-renderer:has(ytm-shorts-lockup-view-model)",
             "ytm-rich-section-renderer:has(ytm-shorts-lockup-view-model-v2)",
             "grid-shelf-view-model:has(ytm-shorts-lockup-view-model)",
             "grid-shelf-view-model:has(ytm-shorts-lockup-view-model-v2)",
             "ytm-pivot-bar-item-renderer:has(.pivot-shorts)",
             ".pivot-shorts"]
        default:
            []
        }
    }

    /// True when `host` belongs to `app` (exact or subdomain match).
    static func isAppHost(_ host: String?, app: WrappedApp) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return app.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: Helpers

    /// Lower-cased, non-empty path components with query and fragment stripped.
    static func components(of path: String) -> [String] {
        var p = path
        if let url = URL(string: p), url.scheme != nil { p = url.path }
        if let cut = p.firstIndex(where: { $0 == "?" || $0 == "#" }) { p = String(p[..<cut]) }
        return p.lowercased().split(separator: "/").map(String.init)
    }
}
