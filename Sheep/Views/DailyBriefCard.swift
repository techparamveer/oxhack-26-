import SwiftUI

/// Daily brief from memory (GEMINI_PROMPTS §1). STUB — implemented in the Memory step.
struct DailyBriefCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(1)) {
            Text("Morning.").font(Theme.headline).foregroundStyle(Theme.text)
            Text("What do you want to get done today?").font(Theme.body).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
