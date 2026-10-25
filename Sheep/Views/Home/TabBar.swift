import SwiftUI
import UIKit

/// Root content of the NavigationStack: the selected tab plus the floating tab bar.
/// The tab bar is attached to the root view, so any pushed route covers it.
struct RootTabContent: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        Group {
            switch router.tab {
            case .home: HomeView()
            case .apps: AppsView()
            case .notebook: NotebookView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(selection: $router.tab)
                .frame(maxWidth: .infinity)
                // Paper: the capsule sits 24 pt above the physical screen edge (inside the home-indicator area).
                .padding(.bottom, 24 - TabBar.bottomSafeArea)
        }
    }
}

/// Floating white capsule: Home · Apps · Notebook. Active item gets a fog capsule.
struct TabBar: View {
    @Binding var selection: HomeTab

    var body: some View {
        // Buttons sit *above* the glass, not inside GlassEffectContainer / glassEffect.
        // iOS 26 merges accessibility descendants of a glass view, so XCTest/VoiceOver
        // then fail to hit `tab.notebook` (`kAXErrorFailure` scrolling to visible).
        HStack(spacing: 4) {
            ForEach(HomeTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(5)
        .background { Color.clear.sheepGlassTabBarChrome() }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
    }

    private func item(_ tab: HomeTab) -> some View {
        let active = tab == selection
        return Button {
            withAnimation(Theme.spring) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: Self.icon(tab))
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 22)
                Text(Self.title(tab))
                    .font(active ? Theme.tab : Theme.tabInactive)
            }
            .foregroundStyle(active ? Theme.text : Theme.secondary)
            .frame(width: 92)
            .padding(.vertical, 8)
            .sheepGlassTabItemChrome(active: active)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title(tab))
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityRespondsToUserInteraction(true)
    }

    static func title(_ tab: HomeTab) -> String {
        switch tab {
        case .home: "Home"
        case .apps: "Apps"
        case .notebook: "Notebook"
        }
    }

    static func icon(_ tab: HomeTab) -> String {
        switch tab {
        case .home: "house"
        case .apps: "circle.grid.2x2.fill"
        case .notebook: "book.closed"
        }
    }

    /// Bottom safe-area inset of the key window (34 on Face ID phones, 0 on Home-button phones).
    static var bottomSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }
}
