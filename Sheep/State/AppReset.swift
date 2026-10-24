import Foundation
import UserNotifications

/// Dev menu "Reset all": back to a fresh install for the demo.
/// XP/mode/sessions, memory files + event log + brief cache + consolidator state, every `sheep.*`
/// preference, and all pending + delivered notifications. The Supabase identity and its retry queue
/// (`sheep.supabase.*`) are kept so the backend user isn't orphaned mid-sync.
enum AppReset {
    static let keptPrefixes = ["sheep.supabase."]

    @MainActor
    static func resetAll(state: AppState, defaults: UserDefaults = .standard,
                         clearNotifications: () -> Void = clearAllNotifications) {
        clearNotifications()
        clearPreferences(defaults)
        state.resetAll()
        MemoryReset.forgetEverything(defaults: defaults)
        SheepSettings.shared.reload()
    }

    /// Removes every `sheep.*` key except the kept prefixes. Returns the removed keys (sorted).
    @discardableResult
    static func clearPreferences(_ defaults: UserDefaults) -> [String] {
        let keys = defaults.dictionaryRepresentation().keys.filter { key in
            key.hasPrefix("sheep.") && !keptPrefixes.contains { key.hasPrefix($0) }
        }.sorted()
        keys.forEach { defaults.removeObject(forKey: $0) }
        return keys
    }

    static func clearAllNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
