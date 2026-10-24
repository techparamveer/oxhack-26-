import SwiftUI

/// Monochrome sheep; wool puff size shows the wool stage (0…4).
/// Placeholder art — the XP & sheep step (step 7) replaces it with animated stages + wool shed.
struct SheepView: View {
    var woolStage: Int
    var size: CGFloat = 160

    var body: some View {
        let wool = size * (0.55 + 0.1 * CGFloat(woolStage))
        ZStack {
            Circle()
                .stroke(Theme.text, lineWidth: 1.5)
                .frame(width: wool, height: wool * 0.8)
            Capsule()
                .fill(Theme.text)
                .frame(width: size * 0.22, height: size * 0.28)
                .offset(x: wool * 0.45, y: -wool * 0.1)
        }
        .frame(width: size * 1.2, height: size)
        .animation(Theme.spring, value: woolStage)
        .accessibilityLabel("Sheep, wool stage \(woolStage + 1) of 5")
    }
}
