import SwiftUI

/// Full-screen web-view wrapper for Instagram / YouTube. Presented by `RootView`.
/// Minimal chrome: close, app name, mode dot, thin loading bar. Overlays sit on top of the live page.
struct WrapperView: View {
    let app: WrappedApp

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: WrapperController?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .top) {
                Theme.background
                if let controller {
                    WebView(controller: controller)
                }
                loadingBar
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Theme.background)
        .overlay {
            if let controller, let section = controller.blocked {
                BlockedOverlay(app: app, section: section) { controller.dismissBlocked() }
                    .transition(.opacity)
            }
        }
        .overlay {
            if let request = state.scrollMonitor.pendingIntervention {
                InterventionOverlay(request: request)
                    .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: controller?.blocked)
        .animation(Theme.spring, value: state.scrollMonitor.pendingIntervention)
        .onAppear(perform: start)
        // Every exit path reports leaving (safe to call twice): close, swipe-dismiss, background, Safari.
        .onDisappear { state.scrollMonitor.didLeaveWrapper(app: app) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { state.scrollMonitor.didLeaveWrapper(app: app) }
        }
        .onChange(of: state.mode) { _, mode in controller?.modeChanged(to: mode) }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                IconCircleButton(systemName: "xmark", label: "Close \(app.title)") { close() }
                Spacer()
            }
            HStack(spacing: Theme.space(1)) {
                ModeDot(mode: state.mode)
                Text(app.title.uppercased())
                    .font(Theme.caption)
                    .tracking(Theme.Tracking.caption)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, Theme.space(2))
        .padding(.vertical, Theme.space(1))
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var loadingBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Theme.text)
                .frame(width: geo.size.width * (controller?.progress ?? 0), height: 1.5)
        }
        .frame(height: 1.5)
        .opacity(controller?.isLoading == true ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: controller?.progress)
        .allowsHitTesting(false)
    }

    private func close() {
        state.scrollMonitor.didLeaveWrapper(app: app)
        dismiss()
    }

    private func start() {
        guard controller == nil else { return }
        let controller = WrapperController(app: app)
        self.controller = controller
        controller.start(state: state)
        EventLog.shared.append(SheepEvent(type: .wrapperOpen, mode: state.mode, app: app))
    }
}
