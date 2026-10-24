import SwiftUI

/// Small "+20 xp" / "−10 xp" caption that floats up and fades whenever `xp` changes.
/// Reusable: overlay it near the sheep, e.g.
/// `SheepView(…, xp: state.progress.xp).overlay(alignment: .topTrailing) { XPChangeLabel(xp: state.progress.xp) }`.
/// Nothing is shown on first appearance — only on changes.
struct XPChangeLabel: View {
    var xp: Int
    /// How far the label rises before it fades.
    var rise: CGFloat = 28

    @State private var items: [Item] = []

    private struct Item: Identifiable {
        let id = UUID()
        let text: String
        let gained: Bool
    }

    var body: some View {
        ZStack {
            ForEach(items) { item in
                FloatingCaption(text: item.text, color: item.gained ? Theme.scoreUp : Theme.scoreDown, rise: rise)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: xp) { old, new in
            guard let text = XPChange.label(delta: new - old) else { return }
            let item = Item(text: text, gained: new > old)
            items.append(item)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(XPChange.duration + 0.2))
                items.removeAll { $0.id == item.id }
            }
        }
    }
}

/// Pure formatting for the XP change label (tested in `SheepXPTests`).
enum XPChange {
    static let duration: Double = 1.5

    /// "+20 xp", "−10 xp" (true minus sign), nil for no change.
    static func label(delta: Int) -> String? {
        if delta > 0 { return "+\(delta) xp" }
        if delta < 0 { return "\u{2212}\(-delta) xp" }
        return nil
    }
}

private struct FloatingCaption: View {
    let text: String
    let color: Color
    let rise: CGFloat
    @State private var floating = false

    var body: some View {
        Text(text)
            .font(Theme.labelBold)
            .foregroundStyle(color)
            .monospacedDigit()
            .fixedSize()
            .offset(y: floating ? -rise : 0)
            .animation(.easeOut(duration: XPChange.duration), value: floating)
            .opacity(floating ? 0 : 1)
            .animation(.easeIn(duration: 0.6).delay(XPChange.duration - 0.6), value: floating)
            .onAppear { floating = true }
    }
}
