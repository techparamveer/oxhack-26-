import SwiftUI
import UIKit

/// A 1024×1024 foggy-field Home Screen icon: ink fill, the wrapped app's SF Symbol, and a tiny
/// "sheep" wordmark. No gradients or shadows. Rendered with `ImageRenderer` (scale 1).
struct HomeScreenIcon: View {
    let app: WrappedApp
    var size: CGFloat = Self.pixelSize

    static let pixelSize: CGFloat = 1024

    var body: some View {
        let symbol = size * 0.37
        let mark = max(11, size * 0.07)
        ZStack {
            Theme.text
            Image(systemName: app.symbol)
                .font(.system(size: symbol, weight: .semibold))
                .foregroundStyle(Theme.background)
                .offset(y: -size * 0.02)
            Text("sheep")
                .font(Theme.nunito(mark, weight: 900))
                .tracking(mark * -0.03)
                .foregroundStyle(Theme.background)
                .padding(.bottom, size * 0.094)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
    }

    /// PNG-ready bitmap at `size` points, scale 1. Call on the main actor.
    @MainActor
    static func render(_ app: WrappedApp, size: CGFloat = pixelSize) -> UIImage? {
        let renderer = ImageRenderer(content: HomeScreenIcon(app: app, size: size))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size, height: size)
        return renderer.uiImage
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
