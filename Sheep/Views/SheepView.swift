import SwiftUI

/// The sheep hero. Coloured art from the asset catalog, used as-is, one pose per mode (cross-fades when
/// the mode changes). The wool stage (0…4) is shown by extra cream wool puffing out behind the body.
/// When `xp` drops (ignored nudge) a few puffs of wool drift down and fade.
///
/// Source-compatible with the scaffold: `SheepView(woolStage:)` and `SheepView(woolStage:size:)`.
/// Pass `mode:` for the pose and `xp:` (e.g. `state.progress.xp`) to get the wool-shed animation.
struct SheepView: View {
    var woolStage: Int
    var size: CGFloat
    var mode: Mode
    var xp: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bursts: [ShedBurst] = []
    @State private var shakes = 0

    init(woolStage: Int, size: CGFloat = 160, mode: Mode = .idle, xp: Int? = nil) {
        self.woolStage = woolStage
        self.size = size
        self.mode = mode
        self.xp = xp
    }

    private var art: SheepArt { SheepArt(mode) }
    private var stage: Int { min(4, max(0, woolStage)) }
    private var line: CGFloat { max(1, size / 140) }

    var body: some View {
        ZStack {
            sheep
                .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(-size * 0.025, duration: 0.08)
                        SpringKeyframe(size * 0.025, duration: 0.08)
                        SpringKeyframe(-size * 0.012, duration: 0.08)
                        SpringKeyframe(0, duration: 0.12)
                    }
                }
                .modifier(Breathing(enabled: !reduceMotion))
            ForEach(bursts) { burst in
                WoolShedPuffs(burst: burst, art: art, stage: CGFloat(stage), size: size, line: line)
            }
        }
        .frame(width: size * 1.2, height: size)
        .onChange(of: xp) { old, new in
            guard WoolShed.shouldShed(from: old, to: new), let old, let new else { return }
            let burst = ShedBurst(count: WoolShed.puffCount(lost: old - new))
            bursts.append(burst)
            if !reduceMotion { shakes += 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(WoolShed.duration + 0.3))
                bursts.removeAll { $0.id == burst.id }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sheep, wool stage \(stage + 1) of 5")
    }

    /// Wool puff (soft rim + cream fill) behind the art. Only the outer half of the rim shows, so the
    /// puffs read as one fleece rather than separate circles.
    private var sheep: some View {
        let cloud = WoolCloud(growth: CGFloat(stage), anchor: art.anchor)
        return ZStack {
            cloud.stroke(SheepPalette.rim, style: StrokeStyle(lineWidth: line * 2, lineJoin: .round))
            cloud.fill(SheepPalette.wool)
            Image(art.imageName)
                .resizable()
                .scaledToFit()
                .id(art.imageName)
                .transition(.opacity)
        }
        .frame(width: size, height: size)
        .animation(Theme.spring, value: stage)
        .animation(.easeInOut(duration: 0.35), value: art)
    }
}

// MARK: - Art

/// One pose per mode, from `Assets.xcassets/Sheep`. `anchor` is where the woolly body sits inside the
/// square art frame (fractions, top-left origin) so the wool puff grows from behind the body, not the head.
struct SheepArt: Equatable {
    let imageName: String
    let anchor: WoolAnchor

    init(_ mode: Mode) {
        switch mode {
        case .idle:  self.init("sheep-awake", WoolAnchor(x: 0.58, y: 0.50, rx: 0.29, ry: 0.20))
        case .focus: self.init("sheep-focus", WoolAnchor(x: 0.62, y: 0.58, rx: 0.24, ry: 0.26))
        case .rest:  self.init("sheep-rest", WoolAnchor(x: 0.59, y: 0.50, rx: 0.30, ry: 0.19))
        // TODO: replace with controller sheep when the user re-adds the asset (sheep-play@3x.png was blank).
        case .play:  self.init("sheep-awake", WoolAnchor(x: 0.58, y: 0.50, rx: 0.29, ry: 0.20))
        }
    }

    private init(_ imageName: String, _ anchor: WoolAnchor) {
        self.imageName = imageName
        self.anchor = anchor
    }

    static let allImageNames = Set(Mode.allCases.map { SheepArt($0).imageName }).sorted()
}

/// Ellipse (fractions of the art frame) the wool puff is built around. Animatable so the puff glides
/// to the new pose when the mode changes.
struct WoolAnchor: Equatable, Animatable {
    var x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(x, y), AnimatablePair(rx, ry)) }
        set { (x, y, rx, ry) = (newValue.first.first, newValue.first.second, newValue.second.first, newValue.second.second) }
    }
}

enum SheepPalette {
    /// The art's own cream wool, so extra puffs look like more fleece.
    static let wool = Color(hex: 0xF7F6F4)
    /// The art's wool shading tone, softened — just enough edge to read on fog and in dark mode.
    static let rim = Color(hex: 0xB8B4B2).opacity(0.4)
}

// MARK: - Wool puff

/// Union of an ellipse and a ring of puffs around it. `growth` (0…4) is animatable, so stage changes
/// spring smoothly. At stage 0 the puff sits entirely behind the art; stage 4 is a big fleece.
struct WoolCloud: Shape {
    var growth: CGFloat
    var anchor: WoolAnchor

    var animatableData: AnimatablePair<CGFloat, WoolAnchor.AnimatableData> {
        get { AnimatablePair(growth, anchor.animatableData) }
        set { growth = newValue.first; anchor.animatableData = newValue.second }
    }

    static let puffCount = 12

    func path(in rect: CGRect) -> Path {
        let geometry = WoolGeometry(rect: rect, anchor: anchor, growth: growth)
        var path = Path()
        path.addEllipse(in: CGRect(x: geometry.center.x - geometry.rx, y: geometry.center.y - geometry.ry,
                                   width: geometry.rx * 2, height: geometry.ry * 2))
        for i in 0..<Self.puffCount {
            let (p, r) = geometry.puff(i, of: Self.puffCount)
            path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        return path
    }
}

struct WoolGeometry {
    let center: CGPoint
    let rx: CGFloat
    let ry: CGFloat

    init(rect: CGRect, anchor: WoolAnchor, growth: CGFloat) {
        let s = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        let scale = 0.66 + 0.14 * growth
        // Grow evenly around the body, drifting slightly up and back (away from the head and legs).
        center = CGPoint(x: origin.x + s * (anchor.x + 0.008 * growth),
                         y: origin.y + s * (anchor.y - 0.012 * growth))
        rx = s * anchor.rx * scale
        ry = s * anchor.ry * scale
    }

    /// Puff `i` of `n` on the ellipse rim; alternating sizes so the edge looks fluffy, not regular.
    func puff(_ i: Int, of n: Int) -> (CGPoint, CGFloat) {
        let a = Double(i) / Double(n) * 2 * .pi + 0.3
        // Smaller puffs on the underside so the fleece doesn't hang over the legs like a skirt.
        let underside = sin(a) > 0.35 ? 0.6 : 1
        let r = min(rx, ry) * (i.isMultiple(of: 2) ? 0.5 : 0.4) * underside
        return (CGPoint(x: center.x + cos(a) * rx, y: center.y + sin(a) * ry), r)
    }
}

// MARK: - Wool shed

/// Pure shed logic (tested in `SheepXPTests`).
enum WoolShed {
    static let duration: Double = 1.2

    /// Shed only when a known xp value goes down (first appearance / nil never sheds).
    static func shouldShed(from old: Int?, to new: Int?) -> Bool {
        guard let old, let new else { return false }
        return new < old
    }

    /// 3 puffs for a normal ignored nudge, up to 5 for bigger losses.
    static func puffCount(lost: Int) -> Int {
        min(5, max(3, 2 + lost / 10))
    }
}

struct ShedBurst: Identifiable {
    let id = UUID()
    let count: Int
}

/// A few wool puffs that fall off the back of the fleece, drift down and fade.
private struct WoolShedPuffs: View {
    let burst: ShedBurst
    let art: SheepArt
    let stage: CGFloat
    let size: CGFloat
    let line: CGFloat
    @State private var falling = false

    private static let rimPuffs = [10, 11, 1, 9, 0]
    private static let drifts: [CGFloat] = [-0.10, 0.08, 0.14, -0.04, 0.03]

    var body: some View {
        let geometry = WoolGeometry(rect: CGRect(x: 0, y: 0, width: size, height: size),
                                    anchor: art.anchor, growth: stage)
        ZStack {
            ForEach(0..<burst.count, id: \.self) { i in
                // Start on the upper/back rim of the fleece.
                let (start, _) = geometry.puff(Self.rimPuffs[i % 5], of: WoolCloud.puffCount)
                let r = size * (i.isMultiple(of: 2) ? 0.055 : 0.042)
                let delay = 0.05 * Double(i)
                Circle()
                    .fill(SheepPalette.wool)
                    .overlay(Circle().stroke(SheepPalette.rim, lineWidth: line))
                    .frame(width: r * 2, height: r * 2)
                    .position(start)
                    .offset(x: falling ? Self.drifts[i % 5] * size : 0,
                            y: falling ? size * (0.42 + 0.06 * CGFloat(i)) : 0)
                    .rotationEffect(.degrees(falling ? Double(i * 25 - 30) : 0))
                    .animation(.easeOut(duration: WoolShed.duration).delay(delay), value: falling)
                    .opacity(falling ? 0 : 1)
                    .animation(.easeIn(duration: WoolShed.duration).delay(delay), value: falling)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .onAppear { falling = true }
    }
}

// MARK: - Idle breathing

private struct Breathing: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.phaseAnimator([false, true]) { view, inhale in
                view.scaleEffect(inhale ? 1.015 : 1, anchor: .bottom)
            } animation: { _ in
                .easeInOut(duration: 2.4)
            }
        } else {
            content
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack { ForEach(0..<3) { SheepView(woolStage: $0, size: 100) } }
        HStack { ForEach(3..<5) { SheepView(woolStage: $0, size: 100) } }
        HStack { ForEach(Mode.allCases) { SheepView(woolStage: 2, size: 70, mode: $0) } }
    }
    .padding()
    .background(Color(hex: 0xECEDEB))
}
