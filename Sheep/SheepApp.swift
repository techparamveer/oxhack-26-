import SwiftUI

@main
struct SheepApp: App {
    @State private var state = AppState()
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(router)
                .onOpenURL { router.handle(url: $0, state: state) }
                .consumesIntentRoutes(router: router, state: state)
                .task {
                    // Rollover first (idempotent, guarded by the persisted day) so the permission
                    // alert below — which keeps the scene `.inactive` — never delays it.
                    DailyRollover.handleActive()
                    await NotificationService.shared.requestAuthorization()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { DailyRollover.handleActive() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .focusIntake: FocusIntakeView()
                    case .focusSession: FocusSessionView()
                    case .congrats: CongratsView()
                    case .rest: RestView()
                    case .play: PlayView()
                    case .notebook: NotebookView()
                    case .notebookFile(let path): NotebookFileView(path: path)
                    case .setup: SetupView()
                    }
                }
        }
        .tint(Theme.text)
        .fullScreenCover(item: $router.presentedWrapper) { app in
            WrapperView(app: app)
        }
        .sheet(isPresented: $router.showDevMenu) {
            DevMenuView()
        }
    }
}
