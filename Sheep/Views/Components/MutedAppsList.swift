import SwiftUI

/// Work apps shown as muted in Rest / Play. Display only — the real muting is the user's iOS Focus
/// (turned on by a Shortcut, explained in Setup). No entitlements.
/// The list comes from UserDefaults `sheep.mutedWorkApps` so Settings ("Work apps to mute") can drive it.
struct MutedAppsList: View {
    var mode: Mode = .rest
    @Environment(Router.self) private var router

    static let defaultsKey = "sheep.mutedWorkApps"
    static let defaultApps = ["Teams", "Outlook", "Slack"]

    static func apps(_ defaults: UserDefaults = .standard) -> [String] {
        let stored = defaults.stringArray(forKey: defaultsKey)?
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return stored ?? defaultApps
    }

    var body: some View {
        let apps = Self.apps()
        VStack(alignment: .leading, spacing: Theme.space(1)) {
            SectionLabel("work apps")
            if apps.isEmpty {
                Caption("no work apps to mute")
            } else {
                // Wraps onto extra lines if Settings adds more apps.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.space(3)) { rows(apps) }
                    VStack(alignment: .leading, spacing: Theme.space(1)) { rows(apps) }
                }
            }
            HStack(spacing: 4) {
                Caption("muted by your \(mode.title) focus ·")
                Button { router.push(.setup) } label: {
                    Text("setup")
                        .font(Theme.meta)
                        .foregroundStyle(Theme.text)
                        .underline()
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func rows(_ apps: [String]) -> some View {
        ForEach(apps, id: \.self) { name in
            HStack(spacing: Theme.space(1)) {
                Image(systemName: "bell.slash")
                    .font(Theme.meta)
                    .fontWeight(.semibold)
                Text(name.lowercased())
                    .font(Theme.rowTitle)
            }
            .foregroundStyle(Theme.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(name), muted")
        }
    }
}
