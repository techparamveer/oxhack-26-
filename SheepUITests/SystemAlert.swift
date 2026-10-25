import XCTest

/// iOS 27 shows the notification Allow sheet in the *app* hierarchy as often as on
/// SpringBoard, and it is not always an XCTest "interruption". Taps on app controls
/// go through the sheet, so the test can start Rest without ever granting permission.
///
/// Tap **Allow exactly once**. A second tap (interruption monitor + this helper, or
/// Allow then the dimming view) deactivates the alert as "User Dismissed" and leaves
/// every later `UNUserNotificationCenter.add` failing with "Source is not authorized"
/// until the simulator is erased.
enum SystemAlert {
    private static var didTapAllow = false

    static func reset() { didTapAllow = false }

    @discardableResult
    static func dismiss(app: XCUIApplication, springboard: XCUIApplication, timeout: TimeInterval) -> Bool {
        if tapOpen(app: app, springboard: springboard) { return true }
        if didTapAllow { return false }

        let allow = NSPredicate(format: "label ==[c] %@", "Allow")
        let queries: [XCUIElement] = [
            app.alerts.buttons.matching(allow).firstMatch,
            springboard.alerts.buttons.matching(allow).firstMatch,
            app.buttons.matching(allow).firstMatch,
            springboard.buttons.matching(allow).firstMatch,
        ]
        if queries.contains(where: tapAllow) { return true }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if queries.contains(where: tapAllow) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private static func tapAllow(_ button: XCUIElement) -> Bool {
        guard !didTapAllow, button.exists else { return false }
        button.tap()
        didTapAllow = true
        _ = button.waitForNonExistence(timeout: 2)
        return true
    }

    @discardableResult
    private static func tapOpen(app: XCUIApplication, springboard: XCUIApplication) -> Bool {
        let open = NSPredicate(format: "label ==[c] %@", "Open")
        for root in [app, springboard] {
            let button = root.buttons.matching(open).firstMatch
            if button.exists {
                button.tap()
                _ = button.waitForNonExistence(timeout: 2)
                return true
            }
        }
        return false
    }
}
