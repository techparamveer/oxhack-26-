import SwiftUI

// MARK: - Mood

/// Which sheep the hero shows. Maps 1:1 to `Mode`, but is a separate type so the view can be
/// previewed and tested without app state.
enum SheepMood: String, CaseIterable, Identifiable {
    case awake, focus, rest, play

    var id: String { rawValue }

    init(mode: Mode) {
        switch mode {
        case .idle: self = .awake
        case .focus: self = .focus
        case .rest: self = .rest
        case .play: self = .play
        }
    }

    /// Which vector art the mood draws. Play falls back to the awake sheep.
    /// TODO(play-sheep): the controller sheep was deleted from Paper and `sheep-play@3x.png` is a
    /// broken silhouette. When the user re-adds `sheep-play.svg`, add it to Tools/gen_sheepart.py
    /// (group map + layer order), regenerate SheepVectorArt.swift and return `.play` here.
    var art: SheepArtKind {
        switch self {
        case .awake, .play: .awake
        case .focus: .focus
        case .rest: .rest
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .awake: "Sheep, awake"
        case .focus: "Sheep, reading"
        case .rest: "Sheep, sleeping"
        case .play: "Sheep, playing"
        }
    }

    /// Length of one seamless animation loop, in seconds.
    var cycleLength: TimeInterval {
        switch self {
        case .awake: 9.6
        case .focus: 8.0
        case .rest: 4.8
        case .play: 4.8
        }
    }
}

// MARK: - Art

enum SheepArtKind: String {
    case awake, focus, rest

    var viewBox: CGRect {
        switch self {
        case .awake: SheepVectorArt.Awake.viewBox
        case .focus: SheepVectorArt.Focus.viewBox
        case .rest: SheepVectorArt.Rest.viewBox
        }
    }

    var parts: [SheepPart] {
        switch self {
        case .awake: SheepVectorArt.Awake.parts
        case .focus: SheepVectorArt.Focus.parts
        case .rest: SheepVectorArt.Rest.parts
        }
    }

    /// Back-to-front draw order of the animatable groups (matches the SVG's document order
    /// closely enough that nothing overlaps wrongly).
    var layerOrder: [SheepPartGroup] {
        switch self {
        case .awake: [.legs, .body, .earLeft, .earRight, .head, .eyes]
        case .focus: [.body, .legs, .book, .pages, .hooves, .earLeft, .earRight, .head, .eyes]
        case .rest: [.ground, .legs, .body, .head, .earLeft, .earRight, .eyes]
        }
    }

    /// Centre of the eyes in viewBox units — the blink pivot.
    var eyeCentre: CGPoint {
        switch self {
        case .awake: CGPoint(x: 29, y: 35)
        case .focus: CGPoint(x: 31, y: 31.5)
        case .rest: CGPoint(x: 29.5, y: 35)
        }
    }

    /// Where the left ear attaches to the head — the twitch pivot.
    var leftEarPivot: CGPoint {
        switch self {
        case .awake: CGPoint(x: 16.3, y: 27.8)
        case .focus: CGPoint(x: 15.4, y: 24.1)
        case .rest: CGPoint(x: 16, y: 26.3)
        }
    }

    /// Where the book's spine sits (focus only) — the page-flip pivot.
    var spineX: CGFloat { 29.5 }

    /// Where the "z z z" start (rest only), just above the nose.
    var snoreOrigin: CGPoint { CGPoint(x: 50, y: 24) }

    var grouped: [SheepPartGroup: [SheepPart]] {
        Dictionary(grouping: parts, by: \.group)
    }
}

enum SheepPartGroup: String, CaseIterable {
    case ground, legs, body, head, earLeft, earRight, eyes, book, pages, hooves
}

/// One SVG element: a path in viewBox units plus its exact SVG colour.
struct SheepPart {
    let group: SheepPartGroup
    let path: Path
    let color: UInt32
    let opacity: Double

    init(group: SheepPartGroup, path: Path, fill: UInt32, opacity: Double = 1) {
        self.group = group
        self.path = path
        self.color = fill
        self.opacity = opacity
    }

    /// Stroked SVG paths are pre-expanded into fills so every part renders the same way.
    init(group: SheepPartGroup, path: Path, stroke: UInt32, lineWidth: CGFloat, opacity: Double = 1) {
        self.group = group
        self.path = path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        self.color = stroke
        self.opacity = opacity
    }

    static func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rotation: CGFloat) -> Path {
        let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
        let t = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: rotation * .pi / 180)
            .translatedBy(x: -cx, y: -cy)
        return Path(ellipseIn: rect).applying(t)
    }
}

// MARK: - Pose

/// Everything the figure needs to draw one frame. All values are 0…1 unless noted.
struct SheepPose: Equatable {
    var breathe: CGFloat = 0   // 0 exhaled … 1 inhaled
    var blink: CGFloat = 0     // 0 open … 1 closed
    var ear: CGFloat = 0       // left-ear rotation in degrees
    var gaze: CGFloat = 0      // −1 left of the page … 1 right (focus)
    var page: CGFloat = 0      // page-flip progress; 0 and 1 both mean "no loose page" (focus)
    var bounce: CGFloat = 0    // hop height (play)
    var squash: CGFloat = 0    // landing squash (play)
    var snore: CGFloat = 0     // "z z z" cycle phase (rest)

    static let still = SheepPose()

    /// Position and opacity of the n-th "z" (0…2) for the current snore phase.
    /// Each z lives for one full cycle, staggered by a third; it fades in, drifts up-right, fades out.
    static func snoreLetter(_ index: Int, phase: CGFloat) -> (dx: CGFloat, dy: CGFloat, opacity: CGFloat) {
        let p = (phase + CGFloat(index) / 3).truncatingRemainder(dividingBy: 1)
        return (dx: p * 9, dy: -p * 22, opacity: sin(p * .pi))
    }

    /// The flipping page is scaled across the spine; it is invisible at both ends of the flip.
    static func pageScale(_ page: CGFloat) -> CGFloat { cos(page * .pi) }
    static func pageOpacity(_ page: CGFloat) -> CGFloat { page <= 0 || page >= 1 ? 0 : 1 }
}

// MARK: - Motion policy

enum SheepMotion {
    /// Reduce Motion shows a static pose instead of the looping animation.
    static func isAnimated(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// Mode-change squash-and-settle: total must stay ≤ 0.4 s (CLAUDE.md "springs ≤ 0.4 s").
    static let squashIn: TimeInterval = 0.12
    static let settle: TimeInterval = 0.28
    static var transitionLength: TimeInterval { squashIn + settle }
}
