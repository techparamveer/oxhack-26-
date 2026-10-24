import SwiftUI
import UIKit

/// Guided flow: save Sheep's Instagram/YouTube icons, make Shortcuts, pin them on the Home Screen,
/// then tuck the real apps into the App Library. One primary action: open Shortcuts to create one.
struct HomeScreenIconsView: View {
    @State private var settings = SheepSettings.shared
    @State private var icons: [WrappedApp: UIImage] = [:]
    @State private var shareURLs: [WrappedApp: URL] = [:]
    @State private var confirmations: [WrappedApp: Confirmation] = [:]

    private enum Confirmation: Equatable {
        case saved, denied
    }

    var body: some View {
        Screen(title: "Home Screen icons") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Put Sheep's Instagram and YouTube on your Home Screen, then tuck the real apps away.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Theme.space(4))

                    ForEach(Array(WrappedApp.allCases.enumerated()), id: \.element) { index, app in
                        if index > 0 { Hairline() }
                        appRow(app)
                    }

                    divider
                    step(1, "Save the icon") {
                        line("Sheep saves it to Photos.")
                    }
                    divider
                    step(2, "Create the shortcut") {
                        line("Tap \(Text("Create shortcut").font(Theme.bodyBold)) → add \(Text("Open Instagram in Sheep").font(Theme.bodyBold)) (search “Sheep”).")
                        Caption("Do the same for YouTube.")
                    }
                    divider
                    step(3, "Add to Home Screen") {
                        line("Share → Add to Home Screen → tap the icon → Choose Photo → pick the saved icon, name it “Instagram”.")
                    }
                    divider
                    step(4, "Tuck the real app away") {
                        line("Long-press the real Instagram → Remove from Home Screen (it stays in your App Library).")
                    }
                    divider
                    Caption("The “Instagram opened → open Sheep” automation is in Shortcuts setup.")
                }
                .padding(.vertical, Theme.space(3))
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Create shortcut", icon: "arrow.up.right") {
                    UIApplication.shared.open(HomeScreenShortcutsURL.open())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space(2))
                .background(Theme.background)
                .accessibilityIdentifier("homeScreen.createShortcut")
            }
        }
        .onAppear {
            settings.reload()
            for app in WrappedApp.allCases {
                guard let image = icons[app] ?? HomeScreenIcon.render(app) else { continue }
                icons[app] = image
                if shareURLs[app] == nil { shareURLs[app] = writePNG(app, image) }
            }
        }
    }

    private func appRow(_ app: WrappedApp) -> some View {
        VStack(alignment: .leading, spacing: Theme.space(1)) {
            HStack(alignment: .center, spacing: Theme.space(2)) {
                HomeScreenIcon(app: app, size: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.title)
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.text)
                    HStack(spacing: Theme.space(2)) {
                        TextButton(title: "Save icon") { save(app) }
                            .accessibilityIdentifier("homeScreen.save.\(app.rawValue)")
                        shareButton(app)
                    }
                    status(app)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, Theme.space(1))
            doneToggle(app)
        }
    }

    @ViewBuilder
    private func shareButton(_ app: WrappedApp) -> some View {
        if let url = shareURLs[app] {
            ShareLink(item: url) {
                Text("Share icon")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.secondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeScreen.share.\(app.rawValue)")
        }
    }

    @ViewBuilder
    private func status(_ app: WrappedApp) -> some View {
        switch confirmations[app] {
        case .saved:
            Text("saved")
                .font(Theme.captionMeta)
                .foregroundStyle(Theme.scoreUp)
                .transition(.opacity)
        case .denied:
            Text("Photos access denied — share the icon instead.")
                .font(Theme.caption)
                .foregroundStyle(Theme.scoreDown)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        case nil:
            EmptyView()
        }
    }

    /// Marks this app as on the Home Screen (Settings › Home Screen icons shows "n of 2").
    private func doneToggle(_ app: WrappedApp) -> some View {
        Toggle(isOn: Binding(get: { settings.isOnHomeScreen(app) },
                             set: { _ in settings.toggleHomeScreen(app) })) {
            Text("On my Home Screen").font(Theme.rowTitle).foregroundStyle(Theme.text)
        }
        .tint(Theme.focusAccent)
        .frame(minHeight: 52)
        .accessibilityIdentifier("homeScreen.done.\(app.rawValue)")
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

    private func save(_ app: WrappedApp) {
        guard let image = image(for: app) else { return }
        PhotoLibraryAdd.save(image) { error in
            withAnimation(Theme.spring) {
                confirmations[app] = error == nil ? .saved : .denied
            }
            if error == nil {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if confirmations[app] == .saved {
                        withAnimation(Theme.spring) { confirmations[app] = nil }
                    }
                }
            }
        }
    }

    private func image(for app: WrappedApp) -> UIImage? {
        if let cached = icons[app] { return cached }
        let rendered = HomeScreenIcon.render(app)
        icons[app] = rendered
        return rendered
    }

    private func writePNG(_ app: WrappedApp, _ image: UIImage) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sheep-\(app.rawValue)-icon.png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
