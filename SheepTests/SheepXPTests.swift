import XCTest
import UIKit
@testable import Sheep

final class SheepXPTests: XCTestCase {
    private func progress(_ xp: Int) -> Sheep.Progress { Sheep.Progress(xp: xp) }

    func testWoolStageAcrossLevels() {
        let expected: [(xp: Int, stage: Int)] = [
            (0, 0), (49, 0), (50, 1), (90, 1), (100, 1), (149, 1), (150, 2), (299, 2),
            (300, 3), (499, 3), (500, 4), (1_000, 4), (-20, 0)
        ]
        for (xp, stage) in expected {
            XCTAssertEqual(progress(xp).woolStage, stage, "xp \(xp)")
        }
    }

    func testWoolStageAlwaysInRange() {
        for xp in stride(from: -50, through: 1_200, by: 7) {
            XCTAssertTrue((0...4).contains(progress(xp).woolStage), "xp \(xp)")
        }
    }

    func testWoolStageIsMonotonic() {
        var previous = 0
        for xp in stride(from: 0, through: 1_200, by: 1) {
            let stage = progress(xp).woolStage
            XCTAssertGreaterThanOrEqual(stage, previous, "wool shrank going up to xp \(xp)")
            previous = stage
        }
        // Losing 10 XP across a level boundary must not grow wool (was 0 → 4 at 100 → 90).
        XCTAssertLessThanOrEqual(progress(90).woolStage, progress(100).woolStage)
    }

    func testLevelMath() {
        XCTAssertEqual(progress(0).level, 0)
        XCTAssertEqual(progress(99).level, 0)
        XCTAssertEqual(progress(100).level, 1)
        XCTAssertEqual(progress(399).level, 3)
        XCTAssertEqual(progress(400).level, 4)
        XCTAssertEqual(progress(-20).level, 0)
    }

    func testAddClampsAtZero() {
        var p = progress(5)
        p.add(XPRules.ignoredNudge)
        XCTAssertEqual(p.xp, 0)
        p.add(XPRules.perChecklistItem)
        XCTAssertEqual(p.xp, 20)
    }

    func testShedTrigger() {
        XCTAssertTrue(WoolShed.shouldShed(from: 50, to: 40))
        XCTAssertFalse(WoolShed.shouldShed(from: 40, to: 60))
        XCTAssertFalse(WoolShed.shouldShed(from: 40, to: 40))
        XCTAssertFalse(WoolShed.shouldShed(from: nil, to: 40))
        XCTAssertFalse(WoolShed.shouldShed(from: 40, to: nil))
    }

    func testShedPuffCount() {
        XCTAssertEqual(WoolShed.puffCount(lost: 10), 3)
        XCTAssertEqual(WoolShed.puffCount(lost: 1), 3)
        XCTAssertEqual(WoolShed.puffCount(lost: 20), 4)
        XCTAssertEqual(WoolShed.puffCount(lost: 500), 5)
    }

    func testXPChangeLabel() {
        XCTAssertEqual(XPChange.label(delta: 20), "+20 xp")
        XCTAssertEqual(XPChange.label(delta: -10), "\u{2212}10 xp")
        XCTAssertNil(XPChange.label(delta: 0))
    }

    func testArtPerMode() {
        XCTAssertEqual(SheepArt(.idle).imageName, "sheep-awake")
        XCTAssertEqual(SheepArt(.focus).imageName, "sheep-focus")
        XCTAssertEqual(SheepArt(.rest).imageName, "sheep-rest")
        XCTAssertEqual(SheepArt(.play).imageName, "sheep-awake") // fallback until the controller art is re-added
    }

    func testImageAssetsLoad() {
        for name in SheepArt.allImageNames {
            let image = UIImage(named: name, in: Bundle(for: AppState.self), with: nil)
            XCTAssertNotNil(image, name)
            XCTAssertGreaterThan(image?.size.width ?? 0, 0, name)
        }
    }

    func testWoolPuffGrowsWithStage() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let anchor = SheepArt(.idle).anchor
        let widths = (0...4).map { WoolCloud(growth: CGFloat($0), anchor: anchor).path(in: rect).boundingRect.width }
        for (a, b) in zip(widths, widths.dropFirst()) { XCTAssertLessThan(a, b) }
    }
}
