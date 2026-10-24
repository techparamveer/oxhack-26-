import XCTest
@testable import Sheep

@MainActor
final class IntentTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var savedRoot: URL!

    override func setUp() {
        super.setUp()
        savedRoot = AppPaths.root
        AppPaths.root = FileManager.default.temporaryDirectory.appendingPathComponent("intents-\(UUID().uuidString)")
        suiteName = "sheep.intentTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: AppPaths.root)
        AppPaths.root = savedRoot
        super.tearDown()
    }

    // MARK: AppEnum mapping

    func testModeOptionMapsToMode() {
        XCTAssertEqual(ModeOption.allCases.map(\.mode), Mode.selectable)
        for mode in Mode.selectable {
            XCTAssertEqual(ModeOption(mode: mode)?.mode, mode)
        }
        XCTAssertNil(ModeOption(mode: .idle), "idle is not a startable mode")
    }

    func testWrappedAppOptionMapsToWrappedApp() {
        XCTAssertEqual(WrappedAppOption.allCases.map(\.app), WrappedApp.allCases)
        for app in WrappedApp.allCases {
            XCTAssertEqual(WrappedAppOption(app: app).app, app)
        }
    }

    func testEveryCaseHasADisplayRepresentation() {
        XCTAssertEqual(Set(ModeOption.caseDisplayRepresentations.keys), Set(ModeOption.allCases))
        XCTAssertEqual(Set(WrappedAppOption.caseDisplayRepresentations.keys), Set(WrappedAppOption.allCases))
    }

    // MARK: Intent → URL

    func testStartModeIntentURLs() {
        XCTAssertEqual(StartModeIntent(mode: .focus).url.absoluteString, "sheep://mode/focus")
        XCTAssertEqual(StartModeIntent(mode: .rest).url.absoluteString, "sheep://mode/rest")
        XCTAssertEqual(StartModeIntent(mode: .play).url.absoluteString, "sheep://mode/play")
    }

    func testOpenWrapperIntentURLs() {
        XCTAssertEqual(OpenWrapperIntent(app: .instagram).url.absoluteString, "sheep://open/instagram")
        XCTAssertEqual(OpenWrapperIntent(app: .youtube).url.absoluteString, "sheep://open/youtube")
    }

    func testIntentsOpenTheApp() {
        XCTAssertTrue(StartModeIntent.openAppWhenRun)
        XCTAssertTrue(OpenWrapperIntent.openAppWhenRun)
    }

    // MARK: IntentRouter hand-off → Router.handle

    func testPerformQueuesRouteUntilDelivered() async throws {
        let intents = IntentRouter.shared
        _ = try await StartModeIntent(mode: .rest).perform()
        XCTAssertEqual(intents.pending?.absoluteString, "sheep://mode/rest")

        let state = AppState(defaults: defaults)
        let router = Router()
        XCTAssertTrue(intents.deliver(to: router, state: state))
        XCTAssertNil(intents.pending, "a route is delivered once")
        XCTAssertFalse(intents.deliver(to: router, state: state))
    }

    func testRestIntentSetsModeAndPath() {
        let (router, state) = deliver(StartModeIntent(mode: .rest).url)
        XCTAssertEqual(state.mode, .rest)
        XCTAssertEqual(router.path, [.rest])
        XCTAssertNil(router.presentedWrapper)
    }

    func testPlayIntentSetsModeAndPath() {
        let (router, state) = deliver(StartModeIntent(mode: .play).url)
        XCTAssertEqual(state.mode, .play)
        XCTAssertEqual(router.path, [.play])
    }

    func testFocusIntentOpensIntake() {
        let (router, _) = deliver(StartModeIntent(mode: .focus).url)
        XCTAssertEqual(router.path, [.focusIntake])
    }

    func testOpenWrapperIntentPresentsWrapper() {
        let (router, _) = deliver(OpenWrapperIntent(app: .youtube).url)
        XCTAssertEqual(router.presentedWrapper, .youtube)
    }

    func testModeIntentReplacesExistingNavigation() {
        let state = AppState(defaults: defaults)
        let router = Router()
        router.push(.notebook)
        router.open(.instagram)
        IntentRouter.shared.send(DeepLink.mode(.rest))
        IntentRouter.shared.deliver(to: router, state: state)
        XCTAssertEqual(router.path, [.rest])
        XCTAssertNil(router.presentedWrapper)
    }

    #if DEBUG
    func testLaunchEnvironmentQueuesURL() {
        let intents = IntentRouter(environment: ["SHEEP_OPEN_URL": "sheep://open/youtube"])
        XCTAssertEqual(intents.pending, DeepLink.open(.youtube))
        XCTAssertNil(IntentRouter(environment: [:]).pending)
    }
    #else
    func testLaunchEnvironmentIgnoredInRelease() {
        XCTAssertNil(IntentRouter(environment: ["SHEEP_OPEN_URL": "sheep://open/youtube"]).pending)
    }
    #endif

    private func deliver(_ url: URL) -> (Router, AppState) {
        let state = AppState(defaults: defaults)
        let router = Router()
        IntentRouter.shared.send(url)
        XCTAssertTrue(IntentRouter.shared.deliver(to: router, state: state))
        return (router, state)
    }
}
