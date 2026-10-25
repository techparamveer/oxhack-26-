import XCTest

/// Short Rest-overuse probe for the flaky "Source is not authorized" failure.
/// Opt-in: `TEST_RUNNER_SHEEP_NOTIF_PROBE=1` (see `scripts/notif-auth-probe.sh`).
final class NotifAuthProbeUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SHEEP_NOTIF_PROBE"] == "1",
                          "Notif probe is opt-in: run scripts/notif-auth-probe.sh")
        continueAfterFailure = false
        SystemAlert.reset()
        // Do not also add an interruption monitor that taps Allow — a second tap
        // poisons the simulator notification source until erase.
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    func testRestOveruseBannerAfterFreshAllow() {
        app = XCUIApplication()
        app.launchArguments = ["-sheepOffline", "-sheepFastTimers", "-sheepReset"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        _ = SystemAlert.dismiss(app: app, springboard: springboard, timeout: 8)
        // User gesture starts the one requestAuthorization (iOS 27 presents here).
        tap("home.primary")
        let allowed = SystemAlert.dismiss(app: app, springboard: springboard, timeout: 25)
        if element("screen.back").waitForExistence(timeout: 3) { tap("screen.back") }
        _ = SystemAlert.dismiss(app: app, springboard: springboard, timeout: 4)
        // Adding in the same few seconds as Allow poisons the iOS 27 simulator
        // source. The demo has ~2 min of Focus before Rest; wait that out.
        if allowed { RunLoop.current.run(until: Date().addingTimeInterval(25)) }

        tap("home.pill.rest")
        tap("home.primary")
        waitFor(element("rest.start"), "Rest picker")
        tap("rest.activity.netflix")
        tap("rest.start")
        _ = SystemAlert.dismiss(app: app, springboard: springboard, timeout: 8)
        waitFor(element("rest.end"), "Rest running")

        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "netflix")).firstMatch
        // iOS 27 / XCTest often defers the Allow sheet by tens of seconds.
        // Keep tapping it so `schedule` (waiting on the one in-flight request) can add.
        let deadline = Date().addingTimeInterval(70)
        while Date() < deadline {
            if banner.waitForExistence(timeout: 1) { return }
            _ = SystemAlert.dismiss(app: app, springboard: springboard, timeout: 1)
        }
        waitFor(banner, timeout: 1, "Rest overuse notification banner")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = element(id)
        waitFor(e, "\(id) to exist", file: file, line: line)
        if !e.isHittable {
            let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: e)
            _ = XCTWaiter().wait(for: [exp], timeout: 5)
        }
        e.tap()
    }

    private func waitFor(_ e: XCUIElement, timeout: TimeInterval = 10, _ what: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        if !e.waitForExistence(timeout: timeout) {
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "FAIL-\(what)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("Timed out waiting for \(what)\nAPP:\n\(app.debugDescription)\nSPRINGBOARD:\n\(springboard.debugDescription)", file: file, line: line)
        }
    }
}
