import XCTest
@testable import Sheep

final class HomeScreenIconsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "sheep.tests.homeScreenIcons.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsAreUnset() {
        let s = SheepSettings(defaults: defaults)
        XCTAssertEqual(s.homeScreenIcons, [])
        XCTAssertEqual(s.homeScreenIconsSummary, "Set up")
        XCTAssertFalse(s.isOnHomeScreen(.instagram))
        XCTAssertFalse(s.isOnHomeScreen(.youtube))
    }

    func testToggleAndSummary() {
        let s = SheepSettings(defaults: defaults)
        s.toggleHomeScreen(.youtube)
        XCTAssertTrue(s.isOnHomeScreen(.youtube))
        XCTAssertFalse(s.isOnHomeScreen(.instagram))
        XCTAssertEqual(s.homeScreenIcons, ["youtube"])
        XCTAssertEqual(s.homeScreenIconsSummary, "1 of 2")
        XCTAssertEqual(defaults.stringArray(forKey: SheepSettings.Key.homeScreenIcons), ["youtube"])

        s.toggleHomeScreen(.instagram)
        XCTAssertEqual(s.homeScreenIcons, ["instagram", "youtube"])
        XCTAssertEqual(s.homeScreenIconsSummary, "2 of 2")

        s.toggleHomeScreen(.youtube)
        XCTAssertEqual(s.homeScreenIcons, ["instagram"])
        XCTAssertEqual(s.homeScreenIconsSummary, "1 of 2")
        XCTAssertFalse(s.isOnHomeScreen(.youtube))
    }

    func testToggleKeepsCanonicalOrderAndReloads() {
        let s = SheepSettings(defaults: defaults)
        s.toggleHomeScreen(.youtube)
        s.toggleHomeScreen(.instagram)
        XCTAssertEqual(s.homeScreenIcons, ["instagram", "youtube"])
        s.toggleHomeScreen(.instagram)
        s.toggleHomeScreen(.instagram)
        XCTAssertEqual(s.homeScreenIcons, ["instagram", "youtube"])

        let reloaded = SheepSettings(defaults: defaults)
        XCTAssertEqual(reloaded.homeScreenIcons, ["instagram", "youtube"])
        XCTAssertEqual(reloaded.homeScreenIconsSummary, "2 of 2")
    }

    func testSummaryIgnoresUnknownRawValues() {
        defaults.set(["instagram", "tiktok"], forKey: SheepSettings.Key.homeScreenIcons)
        let s = SheepSettings(defaults: defaults)
        XCTAssertTrue(s.isOnHomeScreen(.instagram))
        XCTAssertEqual(s.homeScreenIconsSummary, "1 of 2")
    }

    func testShortcutsURLConstantAndFallback() {
        XCTAssertEqual(HomeScreenShortcutsURL.create.absoluteString, "shortcuts://create-shortcut")
        XCTAssertEqual(HomeScreenShortcutsURL.app.absoluteString, "shortcuts://")
        XCTAssertEqual(HomeScreenShortcutsURL.open { $0 == HomeScreenShortcutsURL.create },
                       HomeScreenShortcutsURL.create)
        XCTAssertEqual(HomeScreenShortcutsURL.open { _ in false }, HomeScreenShortcutsURL.app)
    }

    @MainActor
    func testIconRenders1024() {
        for app in WrappedApp.allCases {
            let image = HomeScreenIcon.render(app)
            XCTAssertNotNil(image, "\(app.rawValue) render")
            XCTAssertEqual(image?.size, CGSize(width: 1024, height: 1024), "\(app.rawValue) size")
            XCTAssertEqual(image?.scale, 1, "\(app.rawValue) scale")
        }
    }
}
