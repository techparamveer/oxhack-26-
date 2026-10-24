import SwiftUI
import UIKit

/// Explains the two Shortcuts automations that stand in for real app blocking (no entitlements),
/// and lists the deep links. One primary action: open the Shortcuts app.
struct SetupView: View {
    @State private var copied: URL?
    @State private var done = ShortcutsDone.ids()

    private static let links: [URL] =
        WrappedApp.allCases.map(DeepLink.open) + Mode.selectable.map(DeepLink.mode)

    var body: some View {
        Screen(title: "Shortcuts setup") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sheep can’t close other apps on its own. Two shortcuts do it for you.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Theme.space(4))

                    step(1, "Instagram opens Sheep") {
                        line("Shortcuts › Automation › New › App › Instagram › Is Opened › Run Immediately.")
                        line("Add the action \(Text("Open Instagram in Sheep").font(Theme.bodyBold)).")
                        Caption("Do the same for YouTube.")
                    }
                    divider
                    step(2, "Rest silences work") {
                        line("New shortcut named \(Text("Sheep Rest").font(Theme.bodyBold)) with two actions: \(Text("Start Rest in Sheep").font(Theme.bodyBold)), then \(Text("Set Focus: Rest — On").font(Theme.bodyBold)).")
                        line("Teams, Outlook and Slack go quiet while you rest.")
                        Caption("Optional: a matching “Sheep Focus”.")
                    }
                    divider
                    step(3, "Deep links") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Self.links, id: \.self, content: linkRow)
                        }
                        Caption("Tap to copy. Any shortcut can open these.")
                    }
                    divider
                    SectionLabel("I’ve set these up")
                        .padding(.bottom, Theme.space(1))
                    doneToggle(ShortcutsDone.openInSheep, "Instagram opens Sheep")
                    Hairline()
                    doneToggle(ShortcutsDone.restSilences, "Rest silences work")
                    divider
                    Caption("Real blocking of native apps needs Apple’s Screen Time API — that’s the production version.")
                }
                .padding(.vertical, Theme.space(3))
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Open Shortcuts", icon: "arrow.up.right") {
                    UIApplication.shared.open(URL(string: "shortcuts://")!)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space(2))
                .background(Theme.background)
            }
        }
    }

    /// Marks a shortcut as set up (Settings › Shortcuts setup shows "n of 2 on").
    private func doneToggle(_ id: String, _ title: String) -> some View {
        Toggle(isOn: Binding(get: { done.contains(id) },
                             set: { done = ShortcutsDone.set(id, on: $0) })) {
            Text(title).font(Theme.rowTitle).foregroundStyle(Theme.text)
        }
        .tint(Theme.focusAccent)   // same tint as Settings' toggle
        .frame(minHeight: 52)
    }

    private var divider: some View {
        Hairline().padding(.vertical, Theme.space(3))
    }

    private func step<Content: View>(_ number: Int, _ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space(2)) {
            Text("\(number)")
                .font(Theme.headline)
                .foregroundStyle(Theme.secondary)
                .monospacedDigit()
                .frame(width: Theme.space(2), alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.space(1)) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.text)
                    .padding(.bottom, Theme.space(0.5))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func line(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Theme.body)
            .foregroundStyle(Theme.bodyText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func linkRow(_ url: URL) -> some View {
        Button { copy(url) } label: {
            HStack {
                Text(url.absoluteString)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.text)
                Spacer()
                if copied == url {
                    Text("copied")
                        .font(Theme.captionMeta)
                        .foregroundStyle(Theme.scoreUp)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Copies the link")
    }

    private func copy(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        withAnimation(Theme.spring) { copied = url }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == url { withAnimation(Theme.spring) { copied = nil } }
        }
    }
}

/// Which Shortcut automations the user has marked as set up, stored under `sheep.shortcutsDone`
/// (read by Settings › Shortcuts setup via `SheepSettings.shortcutsDoneCount`).
enum ShortcutsDone {
    static let openInSheep = "openInSheep"
    static let restSilences = "restSilences"
    static let all = [openInSheep, restSilences]

    static func ids(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: SheepSettings.Key.shortcutsDone) ?? []
    }

    /// Turns `id` on/off and returns the stored ids (canonical order, no duplicates).
    @discardableResult
    static func set(_ id: String, on: Bool, defaults: UserDefaults = .standard) -> [String] {
        let current = ids(defaults: defaults)
        let next = all.filter { $0 == id ? on : current.contains($0) }
        defaults.set(next, forKey: SheepSettings.Key.shortcutsDone)
        return next
    }
}
