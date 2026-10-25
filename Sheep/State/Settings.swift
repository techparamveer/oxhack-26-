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
        static let blockedInFocus = Policy.blockedInFocusKey   // [String] AppSection raw values
        static let blockedInRest = Policy.blockedInRestKey
        static let blockedInPlay = Policy.blockedInPlayKey
        static let mutedWorkApps = "sheep.mutedWorkApps"       // [String]
        static let shortcutsDone = "sheep.shortcutsDone"       // [String] ids of Shortcut automations set up (SetupView)
        static let homeScreenIcons = "sheep.homeScreenIcons"   // [String] WrappedApp raw values marked on the Home Screen
    }

    static let pomodoroOptions = [15, 25, 50]
    static let blockableSections: [AppSection] = [.reels, .dms, .explore, .shorts]
    static let workApps = ["Teams", "Outlook", "Slack"]
    static let shortcutsTotal = 2

    var voice: SheepVoice { didSet { defaults.set(voice.rawValue, forKey: Key.voice) } }
    var askBeforeActing: Bool { didSet { defaults.set(askBeforeActing, forKey: Key.askBeforeActing) } }
    var pomodoroMinutes: Int { didSet { defaults.set(pomodoroMinutes, forKey: Key.pomodoroMinutes) } }
    var blockedInFocus: [AppSection] {
        didSet { Policy.setBlockedInFocus(Set(blockedInFocus), defaults: defaults) }
    }
    var mutedWorkApps: [String] { didSet { defaults.set(mutedWorkApps, forKey: Key.mutedWorkApps) } }
    /// Written by SetupView's "I've set these up" toggles (`ShortcutsDone`); read-only here.
    private(set) var shortcutsDone: [String]
    /// WrappedApp raw values the user marked as on their Home Screen (`HomeScreenIconsView`).
    var homeScreenIcons: [String] { didSet { defaults.set(homeScreenIcons, forKey: Key.homeScreenIcons) } }
    /// Bumped when Rest/Play hiding changes so `@Observable` views refresh.
    private(set) var blockedRevision = 0

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voice = defaults.string(forKey: Key.voice).flatMap(SheepVoice.init(rawValue:)) ?? .lockIn
        askBeforeActing = defaults.object(forKey: Key.askBeforeActing) as? Bool ?? true
        let minutes = defaults.integer(forKey: Key.pomodoroMinutes)
        pomodoroMinutes = Self.pomodoroOptions.contains(minutes) ? minutes : 25
        blockedInFocus = Self.storedBlocked(in: .focus, defaults: defaults)
        mutedWorkApps = defaults.stringArray(forKey: Key.mutedWorkApps) ?? Self.workApps
        shortcutsDone = defaults.stringArray(forKey: Key.shortcutsDone) ?? []
        homeScreenIcons = defaults.stringArray(forKey: Key.homeScreenIcons) ?? []
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
        homeScreenIcons = fresh.homeScreenIcons
        blockedRevision += 1
    }

    /// How many of the Shortcut automations the user has marked as set up (written by SetupView).
    var shortcutsDoneCount: Int {
        min(Self.shortcutsTotal, shortcutsDone.count)
    }

    func blocked(in mode: Mode) -> [AppSection] {
        _ = blockedRevision
        if mode == .focus { return blockedInFocus }
        return Self.blockableSections.filter { Policy.blockedSections(in: mode, defaults: defaults).contains($0) }
    }

    func isBlocked(_ section: AppSection) -> Bool { isBlocked(section, in: .focus) }

    func isBlocked(_ section: AppSection, in mode: Mode) -> Bool {
        blocked(in: mode).contains(section)
    }

    func toggleBlocked(_ section: AppSection) {
        toggleBlocked(section, in: .focus)
    }

    func toggleBlocked(_ section: AppSection, in mode: Mode) {
        var next = Set(blocked(in: mode))
        if next.contains(section) { next.remove(section) } else { next.insert(section) }
        Policy.setBlocked(next, in: mode, defaults: defaults)
        if mode == .focus {
            blockedInFocus = Self.blockableSections.filter { next.contains($0) }
        }
        blockedRevision += 1
    }

    func isOnHomeScreen(_ app: WrappedApp) -> Bool { homeScreenIcons.contains(app.rawValue) }

    func toggleHomeScreen(_ app: WrappedApp) {
        if isOnHomeScreen(app) {
            homeScreenIcons.removeAll { $0 == app.rawValue }
        } else {
            homeScreenIcons = WrappedApp.allCases.map(\.rawValue).filter { $0 == app.rawValue || homeScreenIcons.contains($0) }
        }
    }

    /// Settings row value: "Set up", "1 of 2 on", "2 of 2 on" — same wording as Shortcuts setup.
    var homeScreenIconsSummary: String {
        let n = WrappedApp.allCases.filter(isOnHomeScreen).count
        let total = WrappedApp.allCases.count
        return n == 0 ? "Set up" : "\(n) of \(total) on"
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

    /// Settings row value for Pomodoro length: the EFFECTIVE length (what Focus will actually plan).
    /// Fast timers (dev menu) force 1-min Pomodoros without touching the stored choice.
    static func pomodoroRowValue(stored: Int, fastTimers: Bool) -> String {
        fastTimers ? "1 min · fast timers" : "\(stored) min"
    }

    static func sectionTitle(_ section: AppSection) -> String {
        switch section {
        case .reels: "Reels"
        case .dms: "DMs"
        case .explore: "Explore"
        case .shorts: "Shorts"
        case .feed: "Feed"
        }
    }

    /// Compact Focus summary for the Settings row (≤ ~18 characters).
    var blockedSummary: String {
        Self.compactBlockedSummary(blockedInFocus)
    }

    static func compactBlockedSummary(_ sections: [AppSection]) -> String {
        let names = sections.map(sectionTitle)
        switch names.count {
        case 0: return "Focus: none"
        case 1: return "Focus: \(names[0])"
        case 2: return "Focus: \(names[0]), \(names[1])"
        default: return "Focus: \(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }

    var mutedSummary: String {
        switch mutedWorkApps.count {
        case 0: "None"
        case 1, 2: mutedWorkApps.joined(separator: ", ")
        default: "\(mutedWorkApps.count) apps"   // "Teams, Outlook, Slack" doesn't fit the row
        }
    }

    private static func storedBlocked(in mode: Mode, defaults: UserDefaults) -> [AppSection] {
        let chosen = Policy.blockedSections(in: mode, defaults: defaults)
        return blockableSections.filter { chosen.contains($0) }
    }
}
