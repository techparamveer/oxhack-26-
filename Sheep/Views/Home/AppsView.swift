import SwiftUI

/// Apps tab: the wrapped apps (what's hidden in the current mode) and the work apps Sheep mutes.
struct AppsView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router
    @State private var settings = SheepSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Apps")
                    .font(Theme.wordmark)
                    .tracking(Theme.Tracking.wordmark)
                    .foregroundStyle(Theme.text)
                    .frame(height: 44)
                    .padding(.top, 4)

                // Flat on fog (no white cards): caption + hairline-separated rows.
                FlatGroup("Open in Sheep", top: Theme.space(3)) {
                    ForEach(Array(WrappedApp.allCases.enumerated()), id: \.element) { index, app in
                        if index > 0 { Hairline() }
                        Button { router.open(app) } label: {
                            AppRow(icon: app.symbol, title: app.title,
                                   caption: AppsCaption.wrapped(app: app, mode: state.mode),
                                   showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                FlatGroup("Work apps") {
                    ForEach(Array(SheepSettings.workApps.enumerated()), id: \.element) { index, name in
                        if index > 0 { Hairline() }
                        AppRow(icon: AppsCaption.workIcon(name), title: name,
                               caption: AppsCaption.work(muted: settings.isMuted(name), mode: state.mode),
                               dimmed: settings.isMuted(name) && (state.mode == .rest || state.mode == .play))
                    }
                }

                Text("Work apps are muted by your iOS Focus Shortcut while Rest or Play is on.")
                    .font(Theme.meta)
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, Theme.space(2))
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.space(2))
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { settings.reload() }
    }
}

private struct AppRow: View {
    let icon: String
    let title: String
    let caption: String
    var showsChevron = false
    var dimmed = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28)
                .foregroundStyle(dimmed ? Theme.tertiary : Theme.text)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.rowTitle)
                    .foregroundStyle(dimmed ? Theme.secondary : Theme.text)
                Text(caption)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron { RowChevron() }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Captions for the Apps tab. Wrapped-app captions ask `Policy` (the single source of truth).
enum AppsCaption {
    /// Representative paths for the sections Sheep can hide.
    static func probes(for app: WrappedApp) -> [(AppSection, String)] {
        switch app {
        case .instagram: [(.reels, "/reels/"), (.dms, "/direct/inbox/")]
        case .youtube: [(.shorts, "/shorts/")]
        }
    }

    static func hiddenSections(app: WrappedApp, mode: Mode,
                               isAllowed: (WrappedApp, String, Mode) -> Bool = { Policy.isAllowed(app: $0, path: $1, mode: $2) }) -> [AppSection] {
        probes(for: app).filter { !isAllowed(app, $0.1, mode) }.map(\.0)
    }

    /// "Reels and DMs hidden" in the current mode; when idle, previews Focus ("In Focus: Shorts hidden").
    static func wrapped(app: WrappedApp, mode: Mode,
                        isAllowed: (WrappedApp, String, Mode) -> Bool = { Policy.isAllowed(app: $0, path: $1, mode: $2) }) -> String {
        let effective = mode == .idle ? Mode.focus : mode
        let hidden = hiddenSections(app: app, mode: effective, isAllowed: isAllowed).map(SheepSettings.sectionTitle)
        let text: String
        switch hidden.count {
        case 0: text = mode == .idle ? "Everything open" : "Everything open in \(mode.title)"
        case 1: text = "\(hidden[0]) hidden"
        default: text = hidden.dropLast().joined(separator: ", ") + " and \(hidden.last!) hidden"
        }
        if mode == .idle && !hidden.isEmpty { return "In Focus: " + text }
        return text
    }

    static func work(muted: Bool, mode: Mode) -> String {
        guard muted else { return "Not muted" }
        return (mode == .rest || mode == .play) ? "Muted now" : "Muted in Rest & Play"
    }

    static func workIcon(_ name: String) -> String {
        switch name {
        case "Teams": "person.2"
        case "Outlook": "envelope"
        case "Slack": "number"
        default: "app"
        }
    }
}
