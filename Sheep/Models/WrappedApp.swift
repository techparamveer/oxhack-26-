import Foundation

/// Apps that live inside Sheep as web-view wrappers.
enum WrappedApp: String, Codable, CaseIterable, Identifiable {
    case instagram, youtube

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        }
    }

    var homeURL: URL {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com/")!
        case .youtube: URL(string: "https://m.youtube.com/")!
        }
    }

    /// SF Symbol used where an icon replaces a word.
    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .youtube: "play.rectangle"
        }
    }

    /// Hosts that belong to this app (navigation to other hosts opens in Safari).
    var hosts: [String] {
        switch self {
        case .instagram: ["instagram.com", "www.instagram.com", "cdninstagram.com"]
        case .youtube: ["youtube.com", "m.youtube.com", "www.youtube.com", "accounts.google.com", "consent.youtube.com"]
        }
    }
}

/// Coarse section of a wrapped app, derived from the URL path. Never the content.
enum AppSection: String, Codable {
    case feed, reels, explore, dms, shorts
}
