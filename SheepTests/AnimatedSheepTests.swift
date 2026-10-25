import XCTest
import SwiftUI
@testable import Sheep

final class AnimatedSheepTests: XCTestCase {
    func testModeMapsToMood() {
        XCTAssertEqual(SheepMood(mode: .idle), .awake)
        XCTAssertEqual(SheepMood(mode: .focus), .focus)
        XCTAssertEqual(SheepMood(mode: .rest), .rest)
        XCTAssertEqual(SheepMood(mode: .play), .play)
    }

    func testPlayFallsBackToAwakeArtUntilControllerSheepIsReadded() {
        XCTAssertEqual(SheepMood.play.art, .awake)
        XCTAssertEqual(SheepMood.awake.art, .awake)
        XCTAssertEqual(SheepMood.focus.art, .focus)
        XCTAssertEqual(SheepMood.rest.art, .rest)
    }

    func testEveryPartIsDrawnByTheLayerOrder() {
        for kind in [SheepArtKind.awake, .focus, .rest] {
            XCTAssertFalse(kind.parts.isEmpty, "\(kind) has no parts")
            XCTAssertFalse(kind.viewBox.isEmpty)
            let groups = Set(kind.parts.map(\.group))
            XCTAssertTrue(groups.isSubset(of: Set(kind.layerOrder)),
                          "\(kind) groups \(groups.subtracting(kind.layerOrder)) are never drawn")
            XCTAssertEqual(kind.layerOrder.count, Set(kind.layerOrder).count, "\(kind) draws a group twice")
            for part in kind.parts {
                XCTAssertFalse(part.path.isEmpty)
                XCTAssertTrue(kind.viewBox.insetBy(dx: -2, dy: -2).contains(part.path.boundingRect),
                              "\(kind) part leaves the viewBox: \(part.path.boundingRect)")
            }
        }
    }

    func testPartsKeepExactSVGColours() {
        // Spot checks against the source SVGs.
        XCTAssertTrue(SheepVectorArt.Awake.parts.contains { $0.color == 0xF7F6F4 && $0.group == .body })  // wool
        XCTAssertTrue(SheepVectorArt.Awake.parts.contains { $0.color == 0xD96411 })                        // nose
        XCTAssertTrue(SheepVectorArt.Focus.parts.contains { $0.color == 0x8F9C89 && $0.group == .book })   // cover
        XCTAssertTrue(SheepVectorArt.Rest.parts.contains { $0.color == 0x202020 && $0.group == .eyes })    // closed eyes
        XCTAssertTrue(SheepVectorArt.Focus.parts.contains { $0.opacity == 0.3 })
    }

    func testLoosePageIsTheRightHalfOfThePages() {
        let page = SheepVectorArt.Focus.loosePage
        XCTAssertFalse(page.isEmpty)
        for part in page {
            XCTAssertGreaterThanOrEqual(part.path.boundingRect.minX, 29.4)
        }
    }

    func testReduceMotionDisablesAnimation() {
        XCTAssertTrue(SheepMotion.isAnimated(reduceMotion: false))
        XCTAssertFalse(SheepMotion.isAnimated(reduceMotion: true))
    }

    func testModeChangeTransitionStaysUnderFourTenthsOfASecond() {
        XCTAssertLessThanOrEqual(SheepMotion.transitionLength, 0.4)
    }

    func testSnoreLettersFadeAtBothEnds() {
        for i in 0..<3 {
            let start = SheepPose.snoreLetter(i, phase: CGFloat(3 - i) / 3)   // each letter's own phase 0
            XCTAssertEqual(start.opacity, 0, accuracy: 1e-6)
            XCTAssertEqual(start.dy, 0, accuracy: 1e-6)
            let mid = SheepPose.snoreLetter(i, phase: CGFloat(3 - i) / 3 + 0.5)
            XCTAssertEqual(mid.opacity, 1, accuracy: 1e-6)
            XCTAssertLessThan(mid.dy, 0, "z should drift upward")
        }
    }

    func testPageFlipIsInvisibleWhenIdle() {
        XCTAssertEqual(SheepPose.pageOpacity(0), 0)
        XCTAssertEqual(SheepPose.pageOpacity(1), 0)
        XCTAssertEqual(SheepPose.pageOpacity(0.5), 1)
        XCTAssertEqual(SheepPose.pageScale(0), 1, accuracy: 1e-6)
        XCTAssertEqual(SheepPose.pageScale(1), -1, accuracy: 1e-6, "page lands mirrored on the left")
    }

    func testCycleLengthsArePositive() {
        for mood in SheepMood.allCases {
            XCTAssertGreaterThan(mood.cycleLength, 0)
        }
    }
}
