import SwiftUI
import UIKit
import UserNotifications
#if DEBUG
import WebKit
#endif

/// Scriptable launch arguments for QA, the acceptance UI test (`SheepUITests`) and `simctl launch`.
/// Everything is compiled out of Release builds (`isOffline` is then always false).
///
/// | Argument | Effect |
/// |---|---|
/// | `-sheepReset` | Fresh install state: AppState, settings, memory files, events, brief cache, notifications. |
/// | `-sheepSeedYesterday` | Seeds yesterday's events + memory (also handled by `DailyRollover`; re-run after a reset). |
/// | `-sheepFastTimers` | Forces fast timers on (1-min Pomodoros, 20 s Rest/Play overuse, 30 s scroll nudge). |
/// | `-sheepOffline` | Gemini + Supabase skip the network → hardcoded fallbacks ("Wi-Fi off"). |
/// | `-sheepOpenWrapper instagram\|youtube` | Presents that wrapper right after launch. |
/// | `-sheepOpenHomeScreenIcons` | Pushes the Home Screen icons setup screen. |
/// | `-sheepWrapperPath /reels/` | Every time a wrapper is presented, navigates it to this path (policy applies). |
/// | `-sheepSimulateScroll <seconds>` | Every time a wrapper is presented, feeds that many seconds of synthetic feed scrolling into `ScrollMonitor`. |
/// | `-sheepAppearance dark\|light` | Overrides the interface style for every window. |
/// | `-sheepOpenHiddenByMode [focus\|rest\|play]` | Opens Settings on the Hidden-by-mode screen (optional mode). |
/// | `-sheepRecordNotifications` | Exposes the last scheduled notification per id + its `add` result to UI tests (`NotificationRecorder`). |
/// | `-sheepRunConsolidator` | (existing, `DailyRollover`) forces a consolidator run. |
enum DebugLaunch {
    /// `-sheepOffline`: no Gemini / Supabase traffic, every prompt returns its fallback.
    static let isOffline: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-sheepOffline")
        #else
        false
        #endif
    }()
}

extension View {
    /// Applied once to the root view in `SheepApp`. No-op in Release.
    @ViewBuilder
    func debugLaunchHooks(state: AppState, router: Router) -> some View {
        #if DEBUG
        modifier(DebugLaunchHooksModifier(state: state, router: router))
        #else
        self
        #endif
    }
}

#if DEBUG
private struct DebugLaunchHooksModifier: ViewModifier {
    let state: AppState
    let router: Router

    func body(content: Content) -> some View {
        content
            .onAppear { DebugLaunchHooks.launch(state: state, router: router) }
            .onChange(of: router.presentedWrapper) { _, app in
                if let app { DebugLaunchHooks.wrapperPresented(app, state: state, router: router) }
            }
            .overlay(alignment: .topLeading) {
                if NotificationRecorder.isEnabled { NotificationRecorderOverlay() }
            }
    }
}

@MainActor
enum DebugLaunchHooks {
    private static var didLaunch = false
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    static func has(_ flag: String) -> Bool { args.contains(flag) }

    /// `-sheepOpenHiddenByMode [focus|rest|play]`: Settings opens on Hidden by mode, optional mode selected.
    nonisolated static var openHiddenByMode: Mode? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-sheepOpenHiddenByMode") else { return nil }
        if let i = args.firstIndex(of: "-sheepOpenHiddenByMode"), args.indices.contains(i + 1) {
            let raw = args[i + 1]
            if !raw.hasPrefix("-"), let mode = Mode(rawValue: raw), Mode.selectable.contains(mode) {
                return mode
            }
        }
        return .focus
    }

    /// Value following `flag` (`-sheepOpenWrapper instagram` → "instagram").
    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        let v = args[i + 1]
        return v.hasPrefix("-") ? nil : v
    }

    static func launch(state: AppState, router: Router) {
        guard !didLaunch else { return }
        didLaunch = true
        if has("-sheepReset") { reset(state: state, router: router) }
        if has("-sheepSeedYesterday") { seedYesterday() }
        if has("-sheepFastTimers") { state.fastTimers = true }
        if let style = value("-sheepAppearance") { applyAppearance(style) }
        if let raw = value("-sheepOpenWrapper"), let app = WrappedApp(rawValue: raw) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                router.open(app)
            }
        }
        if has("-sheepOpenHomeScreenIcons") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                router.push(.homeScreenIcons)
            }
        }
        if has("-sheepOpenHiddenByMode") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                router.showSettings = true
            }
        }
        if DebugLaunch.isOffline { print("[Debug] -sheepOffline: Gemini + Supabase disabled, using fallbacks") }
    }

    // MARK: Reset / seed

    static func reset(state: AppState, router: Router) {
        let defaults = UserDefaults.standard
        if let id = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: id) }
        state.resetAll()
        EventLog.shared.clear()
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: AppPaths.root, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
        SheepSettings.shared.reload()
        DailyBriefService.shared.invalidate()
        // Today's rollover counts as done: don't consolidate an empty memory behind the seed's back.
        defaults.set(MemoryDates.day(.now), forKey: DailyRollover.lastDayKey)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        router.presentedWrapper = nil
        router.showSettings = false
        router.showDevMenu = false
        router.popToRoot()
        router.tab = .home
        NotificationCenter.default.post(name: .memoryDidChange, object: nil)
        if !has("-sheepSeedYesterday") {
            Task { await DailyBriefService.shared.refresh(force: true) }
        }
        print("[Debug] -sheepReset: fresh state")
    }

    static func seedYesterday() {
        MemorySeeder.seedYesterday()
        UserDefaults.standard.set(MemoryDates.day(.now), forKey: DailyRollover.lastDayKey)
        DailyBriefService.shared.invalidate()
        Task { await DailyBriefService.shared.refresh(force: true) }
    }

    // MARK: Appearance

    static func applyAppearance(_ raw: String) {
        let style: UIUserInterfaceStyle = switch raw.lowercased() {
        case "dark": .dark
        case "light": .light
        default: .unspecified
        }
        func apply() {
            for scene in UIApplication.shared.connectedScenes {
                (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = style }
            }
        }
        apply()
        DispatchQueue.main.async(execute: apply)   // the key window may not exist on the first pass
    }

    // MARK: Wrapper

    static func wrapperPresented(_ app: WrappedApp, state: AppState, router: Router) {
        if let path = value("-sheepWrapperPath") {
            Task { @MainActor in
                // Let WrapperView create its web view and start loading the home page first.
                try? await Task.sleep(nanoseconds: 800_000_000)
                for _ in 0..<50 {
                    guard router.presentedWrapper == app else { return }
                    if let webView = findWebView() {
                        let url = URL(string: path, relativeTo: app.homeURL)?.absoluteURL ?? app.homeURL
                        print("[Debug] -sheepWrapperPath: \(url.absoluteString)")
                        webView.load(URLRequest(url: url))
                        return
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
        if let secs = value("-sheepSimulateScroll").flatMap(Double.init), secs > 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                var fed = 0.0
                // 5 s of "active scrolling" every 0.4 s: well inside ScrollMonitor's 12 s gap limit,
                // so it reads as one continuous feed streak and crosses the mode threshold quickly.
                while fed < secs, router.presentedWrapper == app, state.scrollMonitor.pendingIntervention == nil {
                    let chunk = min(5, secs - fed)
                    let path = "/"
                    state.scrollMonitor.ingest(
                        ScrollSample(app: app, section: Policy.section(app: app, path: path), path: path,
                                     px: 1400, activeSec: chunk),
                        mode: state.mode)
                    fed += chunk
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                print("[Debug] -sheepSimulateScroll: fed \(fed) s")
            }
        }
    }

    private static func findWebView() -> WKWebView? {
        func search(_ view: UIView) -> WKWebView? {
            if let wv = view as? WKWebView { return wv }
            for sub in view.subviews { if let found = search(sub) { return found } }
            return nil
        }
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                if let found = search(window) { return found }
            }
        }
        return nil
    }
}
#endif
