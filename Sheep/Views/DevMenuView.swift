import SwiftUI

/// Hidden dev menu (long-press the sheep). Actions call into feature services.
struct DevMenuView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var status = ""

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            Screen(title: "dev", showsBack: false) {
                TextButton(title: "done", color: Theme.text) { dismiss() }
            } content: {
                VStack(alignment: .leading, spacing: Theme.space(2)) {
                    Toggle(isOn: $state.fastTimers) {
                        Text("fast timers").font(Theme.body).foregroundStyle(Theme.text)
                    }
                    Hairline()
                    TextButton(title: "seed yesterday", color: Theme.text) {
                        DevActions.seedYesterday(state: state)
                        status = "seeded yesterday"
                    }
                    TextButton(title: "run consolidator", color: Theme.text) {
                        status = "consolidating…"
                        Task {
                            let learned = await DevActions.runConsolidator(state: state)
                            status = learned.isEmpty ? "consolidated" : learned.joined(separator: "\n")
                        }
                    }
                    TextButton(title: "reset all", color: Theme.scoreDown) {
                        DevActions.resetAll(state: state)
                        router.popToRoot()
                        status = "reset"
                    }
                    if !status.isEmpty { Caption(status) }
                    Spacer()
                    Caption(GeminiClient.shared.isConfigured
                            ? "gemini: \(GeminiClient.shared.model) via \(GeminiClient.shared.proxy != nil ? "supabase" : "key")"
                            : "gemini: not configured — fallbacks")
                }
                .padding(.top, Theme.space(2))
            }
        }
    }
}

/// Dev actions. Feature steps replace these bodies (memory seeding, consolidator).
enum DevActions {
    static func seedYesterday(state: AppState) {
        MemorySeeder.seedYesterday()
        Task { @MainActor in
            DailyBriefService.shared.invalidate()
            await DailyBriefService.shared.refresh()
        }
    }

    static func runConsolidator(state: AppState) async -> [String] {
        await MemoryConsolidator.shared.run(reason: .dailyRollover, force: true)
    }

    /// A true fresh install for the demo: state, memory, `sheep.*` settings, caches, notifications.
    @MainActor
    static func resetAll(state: AppState) {
        AppReset.resetAll(state: state)
    }
}
