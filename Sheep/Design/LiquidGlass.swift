import SwiftUI

/// iOS 26+ Liquid Glass with Paper fallbacks on iOS 17–25 (outlined / wool surfaces).
enum LiquidGlass {
    /// Groups adjacent glass so sampling and morphing stay consistent (mode pills).
    /// Do not wrap controls that VoiceOver / XCTest must hit — `GlassEffectContainer`
    /// merges descendant accessibility frames on iOS 26.
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

    /// Home message card, Settings groups (radius 24).
    @ViewBuilder
    func sheepGlassCard(radius: CGFloat = Theme.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(shape.fill(Theme.surface))
        }
    }

    /// Mode pill score capsule.
    @ViewBuilder
    func sheepGlassModePill(active: Bool, accent: Color) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = active ? .regular.interactive().tint(accent) : .regular.interactive()
            glassEffect(glass, in: Capsule())
        } else {
            background(active ? Theme.surface : Color.clear)
                .overlay(
                    Capsule().strokeBorder(active ? accent : Theme.outline,
                                           lineWidth: active ? Theme.activeOutlineWidth : Theme.outlineWidth)
                )
        }
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
    /// Inactive must return `self` — a bare `if active` drops the label (`EmptyView`),
    /// which collapsed Apps/Notebook to a 0×0 AX frame and hid them.
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
            self
        }
    }
}
