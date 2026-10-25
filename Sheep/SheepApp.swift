import SwiftUI
import UIKit

/// Sets the notification-center delegate before SwiftUI windows (including Liquid Glass
/// overlays) come up. `UNUserNotificationCenter.delegate` is weak; `NotificationService`
/// is a singleton, so this just wins the race against those windows stealing it.
final class SheepAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationService.shared.configure()
        NotificationService.shared.requestAuthorizationSoon()
        return true
    }
}

@main
struct SheepApp: App {
    @UIApplicationDelegateAdaptor(SheepAppDelegate.self) private var appDelegate
    @State private var state = AppState()
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationService.shared.configure()
        SupabaseSync.shared.start()   // anonymous sign-in + queue flush in the background; never blocks launch
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(router)
                .onOpenURL { router.handle(url: $0, state: state) }
                .consumesIntentRoutes(router: router, state: state)
                .debugLaunchHooks(state: state, router: router)   // DEBUG-only launch args (Sheep/Debug)
                .task {
                    // Rollover even while the permission alert (asked once, in `SheepAppDelegate`)
                    // keeps the scene `.inactive`. A second concurrent request raced the first on a
                    // fresh install and left the app "not authorized" despite Allow.
                    DailyRollover.handleActive()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        NotificationService.shared.configure()
                        DailyRollover.handleActive()
                        RestController.restoreOveruseNotifications(state: state)
                    }
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
            RootTabContent()
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
                    case .homeScreenIcons: HomeScreenIconsView()
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
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
    }
}
