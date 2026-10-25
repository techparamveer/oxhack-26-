import SwiftUI

/// A list section that sits flat on the fog background: an uppercase `SectionLabel` caption, then rows
/// separated by `Hairline()` (put `Hairline()` between rows yourself). No white card — white rounded
/// surfaces are reserved for the Home message card, Settings groups and the tab bar.
/// The caller supplies the 24 pt side margin.
struct FlatGroup<Content: View>: View {
    let title: String
    var top: CGFloat
    @ViewBuilder var content: () -> Content

    init(_ title: String, top: CGFloat = Theme.space(4), @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.top = top
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(0.5)) {
            SectionLabel(title)
            VStack(spacing: 0) { content() }
        }
        .padding(.top, top)
    }
}

/// The trailing "›" used by Settings rows (Nunito 17/600, secondary).
struct RowChevron: View {
    var body: some View {
        Text("›")
            .font(Theme.nunito(17, weight: 600))
            .foregroundStyle(Theme.secondary)
            .accessibilityHidden(true)
    }
}
