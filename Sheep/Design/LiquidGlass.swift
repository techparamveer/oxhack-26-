import SwiftUI

/// Liquid Glass is reserved for the floating tab bar and 44 pt circle buttons (iOS 26+).
/// Content surfaces (message card, Settings groups, mode pills) always use Paper fills/strokes.
enum LiquidGlass {
    /// Groups adjacent glass so sampling and morphing stay consistent (tab bar).
    @ViewBuilder
    static func container<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(content: content)
        } else {
            content()
        }
    }
}

extension View {
    /// 44 pt settings / close / back control.
    @ViewBuilder
    func sheepGlassCircleButtonChrome() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            overlay(Circle().stroke(Theme.outline, lineWidth: Theme.outlineWidth))
        }
    }

    /// Home message card, Settings groups (radius 24). Always Paper white — never glass.
    func sheepGlassCard(radius: CGFloat = Theme.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Theme.surface))
    }

    /// Mode pill score capsule. Always Paper stroke — never glass.
    func sheepGlassModePill(active: Bool, accent: Color) -> some View {
        // Paper: active = white capsule + 2.5 pt accent ring; inactive = 1.5 pt outline, no fill.
        background(Capsule().fill(active ? Theme.surface : Color.clear))
            .overlay(
                Capsule().strokeBorder(active ? accent : Theme.outline,
                                       lineWidth: active ? Theme.activeOutlineWidth : Theme.outlineWidth)
            )
    }

    /// Floating tab bar capsule.
    @ViewBuilder
    func sheepGlassTabBarChrome() -> some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(shape.fill(Theme.surface))
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    /// Active tab item highlight inside the bar.
    @ViewBuilder
    func sheepGlassTabItemChrome(active: Bool) -> some View {
        if active {
            let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
            if #available(iOS 26.0, *) {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                background(shape.fill(Theme.background))
            }
        } else {
            // ViewBuilder `if` without `else` returns EmptyView, which hid Apps and Notebook.
            self
        }
    }
}
