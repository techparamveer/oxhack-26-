import XCTest
import UIKit
import SwiftUI
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
        XCTAssertEqual(s.homeScreenIconsSummary, "1 of 2 on")
        XCTAssertEqual(defaults.stringArray(forKey: SheepSettings.Key.homeScreenIcons), ["youtube"])

        s.toggleHomeScreen(.instagram)
        XCTAssertEqual(s.homeScreenIcons, ["instagram", "youtube"])
        XCTAssertEqual(s.homeScreenIconsSummary, "2 of 2 on")

        s.toggleHomeScreen(.youtube)
        XCTAssertEqual(s.homeScreenIcons, ["instagram"])
        XCTAssertEqual(s.homeScreenIconsSummary, "1 of 2 on")
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
        XCTAssertEqual(reloaded.homeScreenIconsSummary, "2 of 2 on")
    }

    func testSummaryIgnoresUnknownRawValues() {
        defaults.set(["instagram", "tiktok"], forKey: SheepSettings.Key.homeScreenIcons)
        let s = SheepSettings(defaults: defaults)
        XCTAssertTrue(s.isOnHomeScreen(.instagram))
        XCTAssertEqual(s.homeScreenIconsSummary, "1 of 2 on")
    }

    func testShortcutsURLConstantAndFallback() {
        XCTAssertEqual(HomeScreenShortcutsURL.create.absoluteString, "shortcuts://create-shortcut")
        XCTAssertEqual(HomeScreenShortcutsURL.app.absoluteString, "shortcuts://")
        XCTAssertEqual(HomeScreenShortcutsURL.open { $0 == HomeScreenShortcutsURL.create },
                       HomeScreenShortcutsURL.create)
        XCTAssertEqual(HomeScreenShortcutsURL.open { _ in false }, HomeScreenShortcutsURL.app)
    }

    @MainActor
    func testIconRenders1024InkFill() {
        for app in WrappedApp.allCases {
            let image = HomeScreenIcon.render(app)
            XCTAssertNotNil(image, "\(app.rawValue) render")
            XCTAssertEqual(image?.size, CGSize(width: 1024, height: 1024), "\(app.rawValue) size")
            XCTAssertEqual(image?.scale, 1, "\(app.rawValue) scale")
            assertInkFill(image, label: app.rawValue)
        }
    }

    /// ImageRenderer often ignores `colorScheme` for dynamic `UIColor`s (`Theme.text`). Export
    /// uses fixed ink/fog, so a dark environment must not invert the Photos / share bitmap.
    @MainActor
    func testExportIconStaysInkUnderDarkColorScheme() {
        let content = HomeScreenIcon(app: .instagram, followsAppearance: false)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: HomeScreenIcon.pixelSize,
                                                 height: HomeScreenIcon.pixelSize)
        let image = renderer.uiImage
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size, CGSize(width: 1024, height: 1024))
        assertInkFill(image, label: "dark-scheme export")
    }

    @MainActor
    func testSharePNGHasExtensionAndRewrites() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sheep-homeScreenIcons-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(HomeScreenIcon.shareURL(for: .instagram, in: dir).pathExtension, "png")
        XCTAssertEqual(HomeScreenIcon.shareURL(for: .youtube, in: dir).lastPathComponent,
                       "sheep-youtube-icon.png")

        let image = try XCTUnwrap(HomeScreenIcon.render(.instagram))
        let url = try XCTUnwrap(HomeScreenIcon.writePNG(image, app: .instagram, to: dir))
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let rewritten = try XCTUnwrap(HomeScreenIcon.writePNG(image, app: .instagram, to: dir))
        XCTAssertEqual(rewritten, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rewritten.path))
    }

    /// Ink #17191A — must not follow Dark Mode (`Theme.text` inverts to ~#F2F2EE).
    private func assertInkFill(_ image: UIImage?, label: String) {
        let ink = (r: 23.0, g: 25.0, b: 26.0)
        for (x, y) in [(8, 8), (1015, 8), (8, 1015), (1015, 1015)] {
            guard let rgb = image?.pixelRGB(x: x, y: y) else {
                XCTFail("\(label) missing pixel at \(x),\(y)")
                continue
            }
            XCTAssertEqual(rgb.r, ink.r, accuracy: 3, "\(label) R at \(x),\(y)")
            XCTAssertEqual(rgb.g, ink.g, accuracy: 3, "\(label) G at \(x),\(y)")
            XCTAssertEqual(rgb.b, ink.b, accuracy: 3, "\(label) B at \(x),\(y)")
        }
    }
}

private extension UIImage {
    func pixelRGB(x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        ctx.translateBy(x: CGFloat(-x), y: CGFloat(-y))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return (CGFloat(pixel[0]), CGFloat(pixel[1]), CGFloat(pixel[2]))
    }
}
