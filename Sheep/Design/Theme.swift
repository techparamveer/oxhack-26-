import SwiftUI
import UIKit

/// Single source of typography, colour and spacing. Every visible string uses `Theme.nunito`.
///
/// The bundled Nunito is a variable font whose default instance is ExtraLight (PostScript
/// `Nunito-ExtraLight`), so `Font.custom("Nunito", …)` would render hairline-thin. We build every
/// font from a descriptor that sets the `wght` variation axis explicitly.
enum Theme {
    // MARK: Typography

    static let wghtAxisTag = 0x77676874 // 'wght'

    static func uiNunito(_ size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> UIFont {
        let name = italic ? "Nunito-ExtraLightItalic" : "Nunito-ExtraLight"
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: name,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtAxisTag: weight]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Nunito at an explicit weight (200–1000). `relativeTo` scales with Dynamic Type.
    static func nunito(_ size: CGFloat, weight: CGFloat = 400, italic: Bool = false,
                       relativeTo style: UIFont.TextStyle? = nil) -> Font {
        var font = uiNunito(size, weight: weight, italic: italic)
        if let style {
            font = UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        }
        return Font(font as CTFont)
    }

    static let display  = nunito(64, weight: 300)
    static let title    = nunito(28, weight: 700, relativeTo: .title1)
    static let headline = nunito(20, weight: 700, relativeTo: .headline)
    static let body     = nunito(17, weight: 400, relativeTo: .body)
    static let bodyBold = nunito(17, weight: 700, relativeTo: .body)
    static let caption  = nunito(13, weight: 600, relativeTo: .caption1)

    // MARK: Colour (near-monochrome, light + dark)

    static let background = dynamic(light: 0xFAFAF7, dark: 0x0E0E0D)
    static let text       = dynamic(light: 0x111111, dark: 0xF2F2EE)
    static let secondary  = dynamic(light: 0x8A8A85, dark: 0x7A7A75)
    static let hairline   = dynamic(light: 0xE8E8E3, dark: 0x222220)

    static let focusAccent = Color(hex: 0x3D5AFE)
    static let restAccent  = Color(hex: 0x2E7D5B)
    static let playAccent  = Color(hex: 0xE07A2E)

    // MARK: Spacing (8 pt grid)

    static let margin: CGFloat = 24
    static func space(_ units: CGFloat) -> CGFloat { units * 8 }

    // MARK: Motion

    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}
