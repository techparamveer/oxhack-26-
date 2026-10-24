import SwiftUI
import UIKit

/// A 1024×1024 foggy-field Home Screen icon: ink fill, the wrapped app's SF Symbol, and a tiny
/// "sheep" wordmark. No gradients or shadows. Rendered with `ImageRenderer` (scale 1).
///
/// The in-screen 56 pt preview follows the current appearance. The saved/shared bitmap is always
/// light foggy-field (ink fill, fog glyph) so Photos / Shortcuts don't depend on Dark Mode.
struct HomeScreenIcon: View {
    let app: WrappedApp
    var size: CGFloat = Self.pixelSize
    /// `true` for the on-screen preview; `false` for the Photos / share bitmap.
    var followsAppearance = true

    static let pixelSize: CGFloat = 1024
    /// Light-mode ink / fog — `Theme.text` / `Theme.background` invert in Dark Mode.
    static let exportFill = Theme.ink
    static let exportGlyph = Color(hex: 0xECEDEB)

    var body: some View {
        let symbol = size * 0.37
        let mark = max(11, size * 0.07)
        let fill = followsAppearance ? Theme.text : Self.exportFill
        let glyph = followsAppearance ? Theme.background : Self.exportGlyph
        ZStack {
            fill
            Image(systemName: app.symbol)
                .font(.system(size: symbol, weight: .semibold))
                .foregroundStyle(glyph)
                .offset(y: -size * 0.02)
            Text("sheep")
                .font(Theme.nunito(mark, weight: 900))
                .tracking(mark * -0.03)
                .foregroundStyle(glyph)
                .padding(.bottom, size * 0.094)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
    }

    /// PNG-ready bitmap at `size` points, scale 1. Always light foggy-field. Call on the main actor.
    @MainActor
    static func render(_ app: WrappedApp, size: CGFloat = pixelSize) -> UIImage? {
        // Explicit non-dynamic colours (ImageRenderer often ignores `colorScheme` for UIColor
        // dynamic providers) plus a light-scheme environment as a belt-and-braces override.
        let content = HomeScreenIcon(app: app, size: size, followsAppearance: false)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size, height: size)
        return renderer.uiImage
    }

    static func shareURL(for app: WrappedApp,
                         in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        directory.appendingPathComponent("sheep-\(app.rawValue)-icon.png")
    }

    @discardableResult
    static func writePNG(_ image: UIImage, app: WrappedApp,
                         to directory: URL = FileManager.default.temporaryDirectory) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = shareURL(for: app, in: directory)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// Shortcuts URLs for the Home Screen icons flow. `create` opens a new shortcut; `app` is the fallback.
enum HomeScreenShortcutsURL {
    static let create = URL(string: "shortcuts://create-shortcut")!
    static let app = URL(string: "shortcuts://")!

    static func open(_ canOpen: (URL) -> Bool = { UIApplication.shared.canOpenURL($0) }) -> URL {
        canOpen(create) ? create : app
    }
}

/// Add-only save to Photos (`NSPhotoLibraryAddUsageDescription` — not an entitlement).
enum PhotoLibraryAdd {
    /// Self-retains until the system calls back.
    private final class Target: NSObject {
        private var finish: (Error?) -> Void
        private var keep: Target?
        init(_ finish: @escaping (Error?) -> Void) {
            self.finish = finish
            super.init()
            keep = self
        }
        @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?,
                         contextInfo: UnsafeMutableRawPointer?) {
            finish(error)
            keep = nil
        }
    }

    static func save(_ image: UIImage, completion: @escaping (Error?) -> Void) {
        let target = Target { error in
            DispatchQueue.main.async { completion(error) }
        }
        UIImageWriteToSavedPhotosAlbum(
            image, target, #selector(Target.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
}
