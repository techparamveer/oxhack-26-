import AppIntents
import Foundation

// App Intents need no entitlement: they show up in the Shortcuts app as soon as the app is installed.
// Each intent opens Sheep and hands a `sheep://` URL to `IntentRouter`, which feeds `Router.handle`.

/// The modes a Shortcut can start (Idle is not a choice).
enum ModeOption: String, AppEnum, CaseIterable {
    case focus, rest, play

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sheep Mode"
    static let caseDisplayRepresentations: [ModeOption: DisplayRepresentation] = [
        .focus: DisplayRepresentation(title: "Focus", image: .init(systemName: "scope")),
        .rest: DisplayRepresentation(title: "Rest", image: .init(systemName: "leaf")),
        .play: DisplayRepresentation(title: "Play", image: .init(systemName: "gamecontroller")),
    ]

    var mode: Mode {
        switch self {
        case .focus: .focus
        case .rest: .rest
        case .play: .play
        }
    }

    init?(mode: Mode) { self.init(rawValue: mode.rawValue) }
}

/// The wrapped apps a Shortcut can open inside Sheep.
enum WrappedAppOption: String, AppEnum, CaseIterable {
    case instagram, youtube

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sheep App"
    static let caseDisplayRepresentations: [WrappedAppOption: DisplayRepresentation] = [
        .instagram: DisplayRepresentation(title: "Instagram", image: .init(systemName: "camera")),
        .youtube: DisplayRepresentation(title: "YouTube", image: .init(systemName: "play.rectangle")),
    ]

    var app: WrappedApp {
        switch self {
        case .instagram: .instagram
        case .youtube: .youtube
        }
    }

    init(app: WrappedApp) {
        switch app {
        case .instagram: self = .instagram
        case .youtube: self = .youtube
        }
    }
}

/// "Start Rest in Sheep" — pair with "Set Focus" in a Shortcut to silence work apps.
struct StartModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Mode in Sheep"
    static let description: IntentDescription = IntentDescription("Opens Sheep and starts Focus, Rest or Play.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Mode", default: .rest)
    var mode: ModeOption

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$mode) in Sheep")
    }

    init() {}
    init(mode: ModeOption) { self.mode = mode }

    var url: URL { DeepLink.mode(mode.mode) }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.send(url)
        return .result()
    }
}

/// "Open Instagram in Sheep" — the action for the "Instagram is opened" automation.
struct OpenWrapperIntent: AppIntent {
    static let title: LocalizedStringResource = "Open App in Sheep"
    static let description: IntentDescription = IntentDescription("Opens Instagram or YouTube inside Sheep, where Reels, Explore and Shorts follow your mode.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "App", default: .instagram)
    var app: WrappedAppOption

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$app) in Sheep")
    }

    init() {}
    init(app: WrappedAppOption) { self.app = app }

    var url: URL { DeepLink.open(app.app) }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.send(url)
        return .result()
    }
}

/// Siri phrases + Spotlight / Shortcuts app tiles. Every phrase must contain the app name.
struct SheepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartModeIntent(),
            phrases: [
                "Start \(\.$mode) in \(.applicationName)",
                "\(.applicationName) \(\.$mode)",
                "Start a \(.applicationName) session",
            ],
            shortTitle: "Start Mode",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: OpenWrapperIntent(),
            phrases: [
                "Open \(\.$app) in \(.applicationName)",
                "\(.applicationName) open \(\.$app)",
            ],
            shortTitle: "Open in Sheep",
            systemImageName: "camera"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .grayGreen
}
