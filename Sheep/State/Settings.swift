import Foundation
import Observation

/// How Sheep talks (persona tone).
enum SheepVoice: String, CaseIterable, Identifiable {
    case lockIn, gentle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lockIn: "Lock in"
        case .gentle: "Gentle"
        }
    }
}

/// User preferences shown in Settings, backed by UserDefaults under stable `sheep.*` keys
/// (other features read these keys directly — don't rename them).
@Observable
final class SheepSettings {
    static let shared = SheepSettings()

    enum Key {
        static let voice = "sheep.voice"                       // "lockIn" | "gentle"
        static let askBeforeActing = "sheep.askBeforeActing"   // Bool, default true
        static let pomodoroMinutes = "sheep.pomodoroMinutes"   // Int: 15 / 25 / 50, default 25
        static let blockedInFocus = "sheep.blockedInFocus"     // [String] AppSection raw values
        static let mutedWorkApps = "sheep.mutedWorkApps"       // [String]
        static let shortcutsDone = "sheep.shortcutsDone"       // [String] ids of Shortcut automations set up (SetupView)
    }

    static let pomodoroOptions = [15, 25, 50]
    static let blockableSections: [AppSection] = [.reels, .dms, .shorts]
    static let workApps = ["Teams", "Outlook", "Slack"]
    static let shortcutsTotal = 2

    var voice: SheepVoice { didSet { defaults.set(voice.rawValue, forKey: Key.voice) } }
    var askBeforeActing: Bool { didSet { defaults.set(askBeforeActing, forKey: Key.askBeforeActing) } }
    var pomodoroMinutes: Int { didSet { defaults.set(pomodoroMinutes, forKey: Key.pomodoroMinutes) } }
    var blockedInFocus: [AppSection] {
        didSet { defaults.set(blockedInFocus.map(\.rawValue), forKey: Key.blockedInFocus) }
    }
    var mutedWorkApps: [String] { didSet { defaults.set(mutedWorkApps, forKey: Key.mutedWorkApps) } }
    /// Written by SetupView's "I've set these up" toggles (`ShortcutsDone`); read-only here.
    private(set) var shortcutsDone: [String]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voice = defaults.string(forKey: Key.voice).flatMap(SheepVoice.init(rawValue:)) ?? .lockIn
        askBeforeActing = defaults.object(forKey: Key.askBeforeActing) as? Bool ?? true
        let minutes = defaults.integer(forKey: Key.pomodoroMinutes)
        pomodoroMinutes = Self.pomodoroOptions.contains(minutes) ? minutes : 25
        if let raw = defaults.stringArray(forKey: Key.blockedInFocus) {
            blockedInFocus = Self.blockableSections.filter { raw.contains($0.rawValue) }
        } else {
            blockedInFocus = Self.blockableSections
        }
        mutedWorkApps = defaults.stringArray(forKey: Key.mutedWorkApps) ?? Self.workApps
        shortcutsDone = defaults.stringArray(forKey: Key.shortcutsDone) ?? []
    }

    /// Re-read everything (e.g. after another screen or a reset wrote the keys).
    func reload() {
        let fresh = SheepSettings(defaults: defaults)
        voice = fresh.voice
        askBeforeActing = fresh.askBeforeActing
        pomodoroMinutes = fresh.pomodoroMinutes
        blockedInFocus = fresh.blockedInFocus
        mutedWorkApps = fresh.mutedWorkApps
        shortcutsDone = fresh.shortcutsDone
    }

    /// How many of the Shortcut automations the user has marked as set up (written by SetupView).
    var shortcutsDoneCount: Int {
        min(Self.shortcutsTotal, shortcutsDone.count)
    }

    func isBlocked(_ section: AppSection) -> Bool { blockedInFocus.contains(section) }

    func toggleBlocked(_ section: AppSection) {
        if isBlocked(section) {
            blockedInFocus.removeAll { $0 == section }
        } else {
            blockedInFocus = Self.blockableSections.filter { $0 == section || blockedInFocus.contains($0) }
        }
    }

    func isMuted(_ app: String) -> Bool { mutedWorkApps.contains(app) }

    func toggleMuted(_ app: String) {
        if isMuted(app) {
            mutedWorkApps.removeAll { $0 == app }
        } else {
            mutedWorkApps = Self.workApps.filter { $0 == app || mutedWorkApps.contains($0) }
        }
    }

    // MARK: Display strings

    static func sectionTitle(_ section: AppSection) -> String {
        switch section {
        case .reels: "Reels"
        case .dms: "DMs"
        case .shorts: "Shorts"
        case .feed: "Feed"
        }
    }

    var blockedSummary: String {
        blockedInFocus.isEmpty ? "Nothing" : blockedInFocus.map(Self.sectionTitle).joined(separator: ", ")
    }

    var mutedSummary: String {
        switch mutedWorkApps.count {
        case 0: "None"
        case 1, 2: mutedWorkApps.joined(separator: ", ")
        default: "\(mutedWorkApps.count) apps"   // "Teams, Outlook, Slack" doesn't fit the row
        }
    }
}
