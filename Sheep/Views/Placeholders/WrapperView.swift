import SwiftUI

// PLACEHOLDER — delete this file and add Sheep/Wrapper/WrapperView.swift with the same type name.
// Contract: when `state.scrollMonitor.pendingIntervention` is non-nil, overlay `InterventionOverlay(request:)`.
struct WrapperView: View {
    let app: WrappedApp
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PlaceholderScreen(title: app.title.lowercased(), note: "wrapper — step 2")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        TextButton(title: "close", color: Theme.text) { dismiss() }
                    }
                }
        }
    }
}
