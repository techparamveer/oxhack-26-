import SwiftUI

// PLACEHOLDER — delete this file and add Sheep/Views/InterventionOverlay.swift with the same type name.
// Contract: presented by WrapperView over the page while `state.scrollMonitor.pendingIntervention` is set.
// The overlay resolves itself (clears pendingIntervention, logs outcome, routes) — WrapperView only shows it.
struct InterventionOverlay: View {
    let request: InterventionRequest
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(spacing: Theme.space(2)) {
            Text("still scrolling?").font(Theme.headline).foregroundStyle(Theme.text)
            TextButton(title: "ok", color: Theme.text) { state.scrollMonitor.pendingIntervention = nil }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
