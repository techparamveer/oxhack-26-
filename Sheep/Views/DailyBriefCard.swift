import SwiftUI

/// Daily brief from memory (GEMINI_PROMPTS §1). Thin view over `DailyBriefService.shared`
/// (all logic lives there; the Home redesign may restyle this freely).
struct DailyBriefCard: View {
    private var brief = DailyBriefService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(1)) {
            HStack(alignment: .firstTextBaseline) {
                Text(brief.current == nil ? " " : brief.headline)
                    .font(Theme.messageHeadline)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: Theme.space(1))
                Button {
                    Task { await brief.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 44, height: 28, alignment: .trailing)
                        .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(.plain)
                .disabled(brief.isLoading)
                .accessibilityLabel("Refresh brief")
            }
            Text(brief.current == nil ? "thinking about yesterday…" : brief.body)
                .font(Theme.bodySmall)
                .foregroundStyle(brief.current == nil ? Theme.secondary : Theme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.spring, value: brief.current)
        .task { await brief.loadIfNeeded() }
    }
}
