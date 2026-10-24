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
            Screen(title: "dev") {
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
                    TextButton(title: "reset all", color: .red) {
                        DevActions.resetAll(state: state)
                        router.popToRoot()
                        status = "reset"
                    }
                    if !status.isEmpty { Caption(status) }
                    Spacer()
                    Caption(GeminiClient.shared.hasKey ? "gemini: \(GeminiClient.shared.model)" : "gemini: no key — fallbacks")
                }
                .padding(.top, Theme.space(2))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TextButton(title: "done", color: Theme.text) { dismiss() }
                }
            }
        }
    }
}

/// Dev actions. Feature steps replace these bodies (memory seeding, consolidator).
enum DevActions {
    static func seedYesterday(state: AppState) {
        // Memory step: MemorySeeder.seedYesterday()
    }

    static func runConsolidator(state: AppState) async -> [String] {
        // Memory step: await MemoryConsolidator.shared.run(reason: .dailyRollover)
        []
    }

    static func resetAll(state: AppState) {
        state.resetAll()
        EventLog.shared.clear()
        try? FileManager.default.removeItem(at: AppPaths.memory)
    }
}
