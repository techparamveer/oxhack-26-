import XCTest

/// End-to-end acceptance test: walks the MVP_PLAN demo script fully offline
/// (`-sheepOffline -sheepReset -sheepSeedYesterday -sheepFastTimers`) and saves a screenshot of every
/// step, both as `XCTAttachment`s and as numbered PNGs in `$SHEEP_SHOTS_DIR` (default `/tmp/sheep-acceptance`).
///
/// Long-running (≈3 min) and so opt-in: it only runs when `SHEEP_ACCEPTANCE=1` reaches the test runner,
/// which `scripts/acceptance.sh` does via `TEST_RUNNER_SHEEP_ACCEPTANCE=1`. Plain `xcodebuild test`
/// (unit tests) skips it.
///
/// The demo is split across a few relaunches; app state persists between them (UserDefaults + files), only
/// the DEBUG launch hooks change (see `Sheep/Debug/DebugLaunchHooks.swift`).
final class DemoScriptUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    static let shotsDir: URL = {
        let path = ProcessInfo.processInfo.environment["SHEEP_SHOTS_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "/tmp/sheep-acceptance"
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    override class func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SHEEP_ACCEPTANCE"] == "1",
                          "Acceptance UI test is opt-in: run scripts/acceptance.sh (sets SHEEP_ACCEPTANCE=1).")
        continueAfterFailure = false
        // Backup for system alerts that appear while interacting (notification permission, "Open in…").
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "Open", "OK", "Continue"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    // MARK: - Demo script (MVP_PLAN "Demo script")

    func test1_DemoScriptOffline() throws {
        // 1. Home: daily brief from memory, referencing yesterday.
        launch(["-sheepReset", "-sheepSeedYesterday"], firstLaunch: true)
        let message = element("home.message")
        waitFor(message, timeout: 15, "Home message card")
        waitUntil(message, labelContains: "22:40", timeout: 15)
        XCTAssertTrue(message.label.contains("1 of 3"), "Brief should recap yesterday: \(message.label)")
        shot("01-home-daily-brief")

        // 2. Focus intake → plan → session with checklist.
        tap("home.primary")
        let q1 = element("focus.intake.answer.0")
        waitFor(q1, "Intake Q1")
        // A fresh simulator may still be showing the notification prompt / the first-keyboard tip.
        dismissSystemAlerts(timeout: 3)
        dismissKeyboardTips()
        let q1Value = (q1.value as? String) ?? ""
        XCTAssertTrue(q1Value.contains("Dissertation ch.3"), "Q1 should be pre-filled from the notebook, got '\(q1Value)'")
        shot("02-focus-intake-q1-prefilled")
        tap("focus.intake.primary")
        answer(1, "800 words, 3 paragraphs")
        tap("focus.intake.primary")
        answer(2, "instagram reels")
        tap("focus.intake.primary")
        // Step 4 of 4: Pomodoro count (default 3) → "make a plan".
        waitFor(app.staticTexts["How many Pomodoros?"], "Pomodoro picker")
        tap("focus.intake.primary")
        waitFor(element("focus.session.finish"), timeout: 20, "Focus session screen")
        let items = app.buttons.matching(identifier: "focus.checklist.item")
        XCTAssertGreaterThanOrEqual(items.count, 3, "Plan should have a 3–5 item checklist")
        XCTAssertTrue(text(containing: "Dissertation").exists, "Session should be titled after the goal")
        shot("03-focus-session-plan")

        // 3. Instagram wrapper → Reels blocked; DMs stay open (SocialLite-style Focus).
        launch(["-sheepWrapperPath", "/reels/", "-sheepOpenWrapper", "instagram"])
        waitFor(element("blocked.title"), timeout: 20, "Blocked overlay on /reels/")
        let focusing = text(containing: "focusing on")
        XCTAssertTrue(focusing.exists && focusing.label.localizedCaseInsensitiveContains("Dissertation"),
                      "Blocked overlay should name the goal: \(focusing.label)")
        XCTAssertTrue(text(containing: "reels are off").exists)
        shot("04-instagram-reels-blocked")
        tap("blocked.backToFocus")
        waitFor(element("focus.session.finish"), "Back to focus from the blocked overlay")

        launch(["-sheepWrapperPath", "/direct/inbox/", "-sheepOpenWrapper", "instagram"])
        waitFor(element("wrapper.close"), timeout: 20, "Instagram wrapper on /direct/inbox/")
        XCTAssertFalse(element("blocked.title").waitForExistence(timeout: 4), "DMs must stay open in Focus")
        shot("05-instagram-dms-open")
        tap("wrapper.close")
        waitFor(element("focus.session.finish"), "Back to focus from open DMs")

        // 4. Scrolling the feed → doom-scroll nudge quoting the goal → primary → back in focus.
        launch(["-sheepOpenWrapper", "instagram", "-sheepSimulateScroll", "90"])
        let nudgePrimary = element("nudge.primary")
        waitFor(nudgePrimary, timeout: 30, "Doom-scroll nudge")
        let nudgeMessage = element("nudge.message")
        XCTAssertTrue(nudgeMessage.label.localizedCaseInsensitiveContains("Dissertation"),
                      "Nudge should reference the goal: \(nudgeMessage.label)")
        shot("06-doom-scroll-nudge")
        nudgePrimary.tap()
        waitFor(element("focus.session.finish"), "Back in focus after the nudge")
        XCTAssertFalse(nudgePrimary.exists)
        shot("07-back-in-focus")

        // 5. Tick the checklist → finish → Congrats with +XP, wool, "What Sheep learned".
        let checklist = app.buttons.matching(identifier: "focus.checklist.item")
        for i in 0..<checklist.count {
            let item = checklist.element(boundBy: i)
            item.tap()
            waitUntil(item, isSelected: true)
        }
        shot("08-checklist-ticked")
        tap("focus.session.finish")
        let xp = element("focus.congrats.xp")
        waitFor(xp, timeout: 20, "Congrats screen")
        XCTAssertNotNil(xp.label.range(of: #"^\+\d+ xp$"#, options: .regularExpression), "XP label: \(xp.label)")
        waitFor(text(containing: "what sheep learned"), timeout: 20, "What Sheep learned")
        shot("09-congrats-xp-learned")
        tap("focus.congrats.done")

        // 6. Rest: DMs still open (same as Focus); Netflix → overuse notification.
        launch(["-sheepWrapperPath", "/direct/inbox/"])
        tap("home.pill.rest")
        tap("home.primary")
        waitFor(element("rest.start"), "Rest picker")
        tap("rest.wrapper.instagram")
        waitFor(element("wrapper.close"), "Instagram wrapper in Rest")
        XCTAssertFalse(element("blocked.title").waitForExistence(timeout: 8), "DMs must be allowed in Rest")
        shot("10-rest-instagram-dms-open")
        tap("wrapper.close")
        tap("rest.activity.netflix")
        tap("rest.start")
        waitFor(element("rest.end"), "Rest running")
        shot("11-rest-netflix-running")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "netflix")).firstMatch
        waitFor(banner, timeout: 45, "Rest overuse notification banner")
        shot("12-rest-overuse-notification")

        // 7. Play briefly: muted work apps.
        tap("rest.end")
        tap("home.pill.play")
        tap("home.primary")
        waitFor(element("play.start"), "Play picker")
        XCTAssertTrue(text(containing: "work apps").exists)
        XCTAssertTrue(text(containing: "muted by your").exists)
        tap("play.start")
        waitFor(element("play.end"), "Play running")
        shot("13-play-running-muted-apps")
        tap("play.end")

        // 8. Settings sheet + Notebook tab (memory files).
        tap("home.settings")
        waitFor(element("settings.close"), "Settings sheet")
        shot("14-settings")
        tap("settings.close")
        tap("tab.notebook")
        waitFor(text(containing: "Dissertation ch.3"), "Notebook lists the workstream memory file")
        XCTAssertTrue(text(containing: "Profile").exists, "Notebook lists profile.md")
        shot("15-notebook")
        assertNotebookFooterClearsTabBar()
        shot("16-notebook-footer")
    }

    /// Dark-mode pass over the main screens (fresh seeded state).
    func test2_DarkModeScreens() throws {
        launch(["-sheepReset", "-sheepSeedYesterday", "-sheepAppearance", "dark"], firstLaunch: true)
        let message = element("home.message")
        waitFor(message, timeout: 15, "Home message card")
        waitUntil(message, labelContains: "22:40", timeout: 15)
        shot("20-dark-home")
        tap("home.primary")
        waitFor(element("focus.intake.answer.0"), "Intake")
        shot("21-dark-focus-intake")
        tap("screen.back")   // Screen's own outlined back button (the system nav bar is hidden)
        tap("home.settings")
        waitFor(element("settings.close"), "Settings sheet")
        shot("22-dark-settings")
        tap("settings.close")
        tap("tab.notebook")
        waitFor(text(containing: "Dissertation ch.3"), "Notebook")
        shot("23-dark-notebook")
        assertNotebookFooterClearsTabBar()
        shot("24-dark-notebook-footer")
    }

    // MARK: - Helpers

    private func launch(_ args: [String], firstLaunch: Bool = false) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-sheepOffline", "-sheepFastTimers"] + args
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        dismissSystemAlerts(timeout: firstLaunch ? 6 : 2)
    }

    /// Notification permission (first launch) or any other springboard alert.
    /// iOS 27 alerts don't always surface as `alerts`, so look for the buttons themselves.
    private func dismissSystemAlerts(timeout: TimeInterval) {
        let buttons = [springboard.buttons["Allow"], springboard.buttons["Open"]]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for button in buttons where button.exists {
                button.tap()
                _ = button.waitForNonExistence(timeout: 5)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
    }

    /// Scroll the Notebook to the end: the privacy footer must sit above the floating tab bar, not under it.
    private func assertNotebookFooterClearsTabBar(file: StaticString = #filePath, line: UInt = #line) {
        app.swipeUp()
        app.swipeUp()
        let footer = text(containing: "Never messages")
        waitFor(footer, "Notebook privacy footer", file: file, line: line)
        let tab = element("tab.notebook")
        XCTAssertLessThanOrEqual(footer.frame.maxY, tab.frame.minY - 5,
                                 "Notebook footer hidden behind the tab bar", file: file, line: line)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func text(containing s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = element(id)
        waitFor(e, "\(id) to exist", file: file, line: line)
        if !e.isHittable { _ = waitUntilHittable(e) }
        e.tap()
    }

    private func answer(_ index: Int, _ value: String) {
        let field = element("focus.intake.answer.\(index)")
        waitFor(field, "Intake answer \(index)")
        field.tap()
        dismissKeyboardTips()
        field.typeText(value)
    }

    /// The first keyboard on a fresh simulator can show a "slide to type" tip.
    private func dismissKeyboardTips() {
        for cont in [app.buttons["Continue"], springboard.buttons["Continue"]] where cont.waitForExistence(timeout: 1) {
            cont.tap()
            _ = cont.waitForNonExistence(timeout: 3)
        }
    }

    private func waitFor(_ e: XCUIElement, timeout: TimeInterval = 10, _ what: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        if !e.waitForExistence(timeout: timeout) {
            shot("FAIL-\(name.filter { $0.isLetter || $0.isNumber })-\(Int(Date().timeIntervalSince1970))")
            XCTFail("Timed out waiting for \(what)\n\(app.debugDescription)", file: file, line: line)
        }
    }

    private func waitUntil(_ e: XCUIElement, labelContains s: String, timeout: TimeInterval = 10,
                           file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", s), object: e)
        if XCTWaiter().wait(for: [exp], timeout: timeout) != .completed {
            XCTFail("'\(e.label)' never contained '\(s)'", file: file, line: line)
        }
    }

    private func waitUntil(_ e: XCUIElement, isSelected: Bool, timeout: TimeInterval = 5) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: isSelected)), object: e)
        _ = XCTWaiter().wait(for: [exp], timeout: timeout)
    }

    private func waitUntilHittable(_ e: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: e)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    /// Full-screen screenshot (includes springboard banners) → attachment + numbered PNG.
    private func shot(_ name: String) {
        // Let springs (≤ 0.4 s) settle so the picture isn't mid-transition. Not a sync point.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = Self.shotsDir.appendingPathComponent("\(name).png")
        do { try screenshot.pngRepresentation.write(to: url) } catch { print("[acceptance] could not write \(url.path): \(error)") }
    }
}
