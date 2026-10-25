import SwiftUI

/// The hero sheep, built from the SVG parts so eyes, ears, wool, book page and "z z z" animate
/// independently. Pure SwiftUI: one `KeyframeAnimator` per mood drives a `SheepPose`; every part
/// is a static `Shape` that only receives transform/opacity effects, so nothing is re-rasterised
/// per frame. Honours Reduce Motion (static pose) and squashes-and-settles on mood change (≤ 0.4 s).
///
/// Home usage: replace the static hero image with `AnimatedSheepView(mood: SheepMood(mode: mode))`.
struct AnimatedSheepView: View {
    var mood: SheepMood
    var size: CGFloat = 196

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownMood: SheepMood?
    @State private var squash: CGFloat = 0

    var body: some View {
        let current = shownMood ?? mood
        Group {
            if SheepMotion.isAnimated(reduceMotion: reduceMotion) {
                // One animator per mood: a `switch` can't live inside a KeyframesBuilder.
                switch current {
                case .awake:
                    KeyframeAnimator(initialValue: .still, repeating: true, content: figure) { _ in SheepKeyframes.awake }
                case .focus:
                    KeyframeAnimator(initialValue: .still, repeating: true, content: figure) { _ in SheepKeyframes.focus }
                case .rest:
                    KeyframeAnimator(initialValue: .still, repeating: true, content: figure) { _ in SheepKeyframes.rest }
                case .play:
                    KeyframeAnimator(initialValue: .still, repeating: true, content: figure) { _ in SheepKeyframes.play }
                }
            } else {
                SheepFigure(mood: current, pose: .still, size: size)
            }
        }
        .scaleEffect(x: 1 + 0.08 * squash, y: 1 - 0.12 * squash, anchor: .bottom)
        .frame(width: size, height: size)
        .accessibilityLabel(current.accessibilityLabel)
        .onChange(of: mood) { _, new in change(to: new) }
    }

    private func figure(_ pose: SheepPose) -> SheepFigure {
        SheepFigure(mood: shownMood ?? mood, pose: pose, size: size)
    }

    private func change(to new: SheepMood) {
        guard SheepMotion.isAnimated(reduceMotion: reduceMotion) else { shownMood = new; return }
        withAnimation(.easeIn(duration: SheepMotion.squashIn)) { squash = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + SheepMotion.squashIn) {
            shownMood = new
            withAnimation(.spring(response: SheepMotion.settle, dampingFraction: 0.55)) { squash = 0 }
        }
    }
}

// MARK: - Keyframes

enum SheepKeyframes {
    // Awake — 9.6 s: three idle breaths, two blinks, one ear twitch.
    @KeyframesBuilder<SheepPose>
    static var awake: some Keyframes<SheepPose> {
        KeyframeTrack(\.breathe) {
            CubicKeyframe(1, duration: 1.6)
            CubicKeyframe(0, duration: 1.6)
            CubicKeyframe(1, duration: 1.6)
            CubicKeyframe(0, duration: 1.6)
            CubicKeyframe(1, duration: 1.6)
            CubicKeyframe(0, duration: 1.6)
        }
        KeyframeTrack(\.blink) {
            LinearKeyframe(0, duration: 4.0)
            LinearKeyframe(1, duration: 0.07)
            LinearKeyframe(1, duration: 0.05)
            LinearKeyframe(0, duration: 0.09)
            LinearKeyframe(0, duration: 3.9)
            LinearKeyframe(1, duration: 0.07)
            LinearKeyframe(1, duration: 0.05)
            LinearKeyframe(0, duration: 0.09)
            LinearKeyframe(0, duration: 1.28)
        }
        KeyframeTrack(\.ear) {
            LinearKeyframe(0, duration: 6.0)
            CubicKeyframe(-9, duration: 0.12)
            CubicKeyframe(4, duration: 0.14)
            CubicKeyframe(0, duration: 0.24)
            LinearKeyframe(0, duration: 3.1)
        }
    }

    // Focus — 8.0 s: two slow breaths, eyes read two lines, one blink, one page flip at the end.
    @KeyframesBuilder<SheepPose>
    static var focus: some Keyframes<SheepPose> {
        KeyframeTrack(\.breathe) {
            CubicKeyframe(1, duration: 2.0)
            CubicKeyframe(0, duration: 2.0)
            CubicKeyframe(1, duration: 2.0)
            CubicKeyframe(0, duration: 2.0)
        }
        KeyframeTrack(\.gaze) {
            MoveKeyframe(-1)
            LinearKeyframe(1, duration: 3.4)
            CubicKeyframe(-1, duration: 0.2)
            LinearKeyframe(1, duration: 3.4)
            CubicKeyframe(-1, duration: 0.3)
            LinearKeyframe(-1, duration: 0.7)
        }
        KeyframeTrack(\.blink) {
            LinearKeyframe(0, duration: 3.45)
            LinearKeyframe(1, duration: 0.08)
            LinearKeyframe(0, duration: 0.12)
            LinearKeyframe(0, duration: 4.35)
        }
        KeyframeTrack(\.page) {
            LinearKeyframe(0, duration: 7.0)
            CubicKeyframe(1, duration: 0.6)
            MoveKeyframe(0)
            LinearKeyframe(0, duration: 0.4)
        }
        KeyframeTrack(\.ear) {
            LinearKeyframe(0, duration: 5.2)
            CubicKeyframe(-6, duration: 0.12)
            CubicKeyframe(0, duration: 0.28)
            LinearKeyframe(0, duration: 2.4)
        }
    }

    // Rest — 4.8 s: one slow, deep breath; "z z z" drift continuously.
    @KeyframesBuilder<SheepPose>
    static var rest: some Keyframes<SheepPose> {
        KeyframeTrack(\.breathe) {
            CubicKeyframe(1, duration: 2.4)
            CubicKeyframe(0, duration: 2.4)
        }
        KeyframeTrack(\.snore) {
            LinearKeyframe(1, duration: 4.8)
        }
    }

    // Play — 4.8 s: three small happy hops with a landing squash, plus the awake blink.
    @KeyframesBuilder<SheepPose>
    static var play: some Keyframes<SheepPose> {
        KeyframeTrack(\.bounce) {
            LinearKeyframe(0, duration: 0.55)
            CubicKeyframe(1, duration: 0.28)
            CubicKeyframe(0, duration: 0.28)
            LinearKeyframe(0, duration: 0.49)
            LinearKeyframe(0, duration: 0.55)
            CubicKeyframe(1, duration: 0.28)
            CubicKeyframe(0, duration: 0.28)
            LinearKeyframe(0, duration: 0.49)
            LinearKeyframe(0, duration: 0.55)
            CubicKeyframe(1, duration: 0.28)
            CubicKeyframe(0, duration: 0.28)
            LinearKeyframe(0, duration: 0.49)
        }
        KeyframeTrack(\.squash) {
            LinearKeyframe(0, duration: 0.4)
            CubicKeyframe(0.5, duration: 0.15)   // anticipation
            CubicKeyframe(0, duration: 0.28)
            LinearKeyframe(0, duration: 0.28)
            CubicKeyframe(1, duration: 0.07)     // landing
            SpringKeyframe(0, duration: 0.42, spring: .bouncy)
            LinearKeyframe(0, duration: 0.4)
            CubicKeyframe(0.5, duration: 0.15)   // anticipation
            CubicKeyframe(0, duration: 0.28)
            LinearKeyframe(0, duration: 0.28)
            CubicKeyframe(1, duration: 0.07)     // landing
            SpringKeyframe(0, duration: 0.42, spring: .bouncy)
            LinearKeyframe(0, duration: 0.4)
            CubicKeyframe(0.5, duration: 0.15)   // anticipation
            CubicKeyframe(0, duration: 0.28)
            LinearKeyframe(0, duration: 0.28)
            CubicKeyframe(1, duration: 0.07)     // landing
            SpringKeyframe(0, duration: 0.42, spring: .bouncy)
        }
        KeyframeTrack(\.breathe) {
            CubicKeyframe(1, duration: 1.2)
            CubicKeyframe(0, duration: 1.2)
            CubicKeyframe(1, duration: 1.2)
            CubicKeyframe(0, duration: 1.2)
        }
        KeyframeTrack(\.blink) {
            LinearKeyframe(0, duration: 2.2)
            LinearKeyframe(1, duration: 0.07)
            LinearKeyframe(0, duration: 0.1)
            LinearKeyframe(0, duration: 2.43)
        }
    }
}

// MARK: - Figure

/// Draws one frame of a mood from its pose. Each group is a cached layer with effects applied.
struct SheepFigure: View {
    let mood: SheepMood
    let pose: SheepPose
    let size: CGFloat

    private var art: SheepArtKind { mood.art }
    private var viewBox: CGRect { art.viewBox }
    /// Points per viewBox unit.
    private var unit: CGFloat { size / max(viewBox.width, viewBox.height) }
    private var figureSize: CGSize {
        CGSize(width: viewBox.width * unit, height: viewBox.height * unit)
    }

    var body: some View {
        ZStack {
            ForEach(art.layerOrder, id: \.self) { group in
                layer(group)
            }
            if mood == .focus { flippingPage }
            if mood == .rest { snore }
        }
        .frame(width: figureSize.width, height: figureSize.height)
        .offset(y: -pose.bounce * 3.5 * unit)
        .scaleEffect(x: 1 + 0.04 * pose.squash, y: 1 - 0.06 * pose.squash, anchor: .bottom)
    }

    @ViewBuilder
    private func layer(_ group: SheepPartGroup) -> some View {
        let base = PartsLayer(id: "\(art.rawValue).\(group.rawValue)",
                              parts: art.grouped[group] ?? [], viewBox: viewBox)
            .equatable()
        switch group {
        case .body:
            base.scaleEffect(1 + 0.015 * pose.breathe, anchor: UnitPoint(x: 0.5, y: 0.78))
        case .head, .earRight, .book, .pages, .hooves:
            base.offset(y: headLift)
        case .earLeft:
            base.rotationEffect(.degrees(pose.ear), anchor: unitPoint(art.leftEarPivot))
                .offset(y: headLift)
        case .eyes:
            base.scaleEffect(x: 1, y: 1 - 0.9 * pose.blink, anchor: unitPoint(art.eyeCentre))
                .offset(x: pose.gaze * 0.6 * unit, y: headLift)
        case .ground, .legs:
            base
        }
    }

    /// The head rises slightly on each inhale; in Rest it sinks instead (deeper, heavier breath).
    private var headLift: CGFloat {
        (mood == .rest ? 0.35 : -0.5) * pose.breathe * unit
    }

    private var flippingPage: some View {
        PartsLayer(id: "focus.loosePage", parts: SheepVectorArt.Focus.loosePage, viewBox: viewBox)
            .equatable()
            .scaleEffect(x: SheepPose.pageScale(pose.page), y: 1,
                         anchor: UnitPoint(x: art.spineX / viewBox.width, y: 0.5))
            .opacity(SheepPose.pageOpacity(pose.page))
            .offset(y: headLift)
    }

    private var snore: some View {
        let origin = art.snoreOrigin
        return ForEach(0..<3, id: \.self) { i in
            let z = SheepPose.snoreLetter(i, phase: pose.snore)
            Text("z")
                .font(Theme.nunito(unit * (4.5 + CGFloat(i) * 0.8), weight: 800))
                .foregroundStyle(Theme.secondary)
                .position(x: (origin.x + z.dx) * unit, y: (origin.y + z.dy) * unit)
                .opacity(z.opacity)
        }
    }

    private func unitPoint(_ p: CGPoint) -> UnitPoint {
        UnitPoint(x: (p.x - viewBox.minX) / viewBox.width, y: (p.y - viewBox.minY) / viewBox.height)
    }
}

// MARK: - Layers

/// A stack of parts that never changes for a given id, so SwiftUI skips re-evaluating it per frame.
struct PartsLayer: View, Equatable {
    let id: String
    let parts: [SheepPart]
    let viewBox: CGRect

    static func == (a: PartsLayer, b: PartsLayer) -> Bool { a.id == b.id }

    var body: some View {
        ZStack {
            ForEach(parts.indices, id: \.self) { i in
                PartShape(path: parts[i].path, viewBox: viewBox)
                    .fill(Color(hex: parts[i].color))
                    .opacity(parts[i].opacity)
            }
        }
    }
}

/// Maps a path in viewBox units into the view's rect (aspect-fit, top-left aligned).
struct PartShape: Shape {
    let path: Path
    let viewBox: CGRect

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let t = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
        return path.applying(t)
    }
}

extension SheepVectorArt.Focus {
    /// The right-hand page, cut from the pages part at the spine — this is what flips over.
    static let loosePage: [SheepPart] = {
        let spine = CGRect(x: 29.5, y: 0, width: 80, height: 80)
        return parts.filter { $0.group == .pages }.map {
            SheepPart(group: .pages, path: $0.path.intersection(Path(spine)), fill: $0.color, opacity: $0.opacity)
        }
    }()
}

// MARK: - Previews

#Preview("All moods") {
    VStack(spacing: Theme.space(3)) {
        HStack(spacing: Theme.space(2)) {
            AnimatedSheepView(mood: .awake, size: 160)
            AnimatedSheepView(mood: .focus, size: 160)
        }
        HStack(spacing: Theme.space(2)) {
            AnimatedSheepView(mood: .rest, size: 160)
            AnimatedSheepView(mood: .play, size: 160)
        }
    }
    .padding(Theme.margin)
    .background(Theme.background)
}

#Preview("Mode change") {
    struct Demo: View {
        @State private var mood: SheepMood = .awake
        var body: some View {
            VStack(spacing: Theme.space(4)) {
                AnimatedSheepView(mood: mood)
                HStack {
                    ForEach(SheepMood.allCases) { m in
                        Button(m.rawValue) { mood = m }
                            .font(Theme.labelBold)
                            .foregroundStyle(Theme.text)
                    }
                }
            }
            .padding(Theme.margin)
            .background(Theme.background)
        }
    }
    return Demo()
}
