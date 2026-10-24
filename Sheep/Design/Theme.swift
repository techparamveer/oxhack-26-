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

    // Type scale — exact values from the Paper file "Sheep App". Minimum weight is 400 everywhere.
    static let wordmark  = nunito(34, weight: 900)                        // "sheep", screen titles (tracking −0.03em)
    static let score     = nunito(72, weight: 900)                        // today's score (tracking −0.03em)
    static let display   = nunito(76, weight: 800)                        // Pomodoro digits (monospaced, tracking −0.02em)
    static let title     = nunito(30, weight: 800, relativeTo: .title1)   // big headings, nudge headline
    static let headline  = nunito(18, weight: 800, relativeTo: .headline) // primary button label, headings
    static let messageHeadline = nunito(17, weight: 800, relativeTo: .headline) // message card headline (line height 23)
    static let pillNumber = nunito(20, weight: 800)                       // per-mode score in pills
    static let modeLabel = nunito(16, weight: 800, relativeTo: .callout)  // "● Focus mode"
    static let rowTitle  = nunito(17, weight: 700, relativeTo: .body)     // settings / list row titles
    static let body      = nunito(17, weight: 500, relativeTo: .body)
    static let bodyBold  = nunito(17, weight: 800, relativeTo: .body)
    static let bodySmall = nunito(16, weight: 500, relativeTo: .callout)  // message card body (line height 23)
    static let label     = nunito(15, weight: 700, relativeTo: .subheadline)  // pill captions, deltas (inactive)
    static let labelBold = nunito(15, weight: 800, relativeTo: .subheadline)  // active pill caption, "▲ 6"
    static let meta      = nunito(14, weight: 600, relativeTo: .footnote)     // "today's score", small meta
    static let caption   = nunito(13, weight: 800, relativeTo: .caption1)     // UPPERCASE section labels (tracking 0.08em)
    static let captionMeta = nunito(13, weight: 700, relativeTo: .caption1)   // right-hand meta ("from memory")
    static let tab       = nunito(12, weight: 800)                            // active tab label
    static let tabInactive = nunito(12, weight: 700)

    /// Letter-spacing in points (em × size) — apply with `.tracking(_:)`.
    enum Tracking {
        static let wordmark: CGFloat = -1.02   // 34 × −0.03
        static let score: CGFloat = -2.16      // 72 × −0.03
        static let display: CGFloat = -1.52    // 76 × −0.02
        static let caption: CGFloat = 1.04     // 13 × 0.08
    }

    // MARK: Colour ("foggy field", light + dark)

    static let background = dynamic(light: 0xECEDEB, dark: 0x0E0F0E)  // fog
    static let surface    = dynamic(light: 0xFFFFFF, dark: 0x1A1C1B)  // wool — message card, settings groups, tab bar ONLY
    static let text       = dynamic(light: 0x17191A, dark: 0xF2F2EE)
    static let bodyText   = dynamic(light: 0x4A4D4B, dark: 0xC4C7C4)
    static let secondary  = dynamic(light: 0x6E726F, dark: 0x8B8F8C)
    static let tertiary   = dynamic(light: 0x8B8F8C, dark: 0x6E726F)
    static let outline    = dynamic(light: 0xCFD2CE, dark: 0x2C2F2D)  // inactive pill / icon-button outline
    static let hairline   = dynamic(light: 0xDCDEDA, dark: 0x242725)
    static let scoreUp    = dynamic(light: 0x2E7D5B, dark: 0x4FAF84)
    static let scoreDown  = dynamic(light: 0xB4442E, dark: 0xD2654D)  // also destructive
    static let ink        = Color(hex: 0x17191A)                       // fixed dark text on the Play accent

    static let focusAccent = Color(hex: 0x3D5AFE)
    static let restAccent  = Color(hex: 0x2E7D5B)
    static let playAccent  = Color(hex: 0xE8A93B)

    // MARK: Shape

    static let cardRadius: CGFloat = 24
    static let cardPadding = EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20)
    static let cardMargin: CGFloat = 16
    static let outlineWidth: CGFloat = 1.5
    static let activeOutlineWidth: CGFloat = 2.5

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
