import Foundation
import UserNotifications

/// Local notifications only (no push, no entitlements). Banners also show while the app is open.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Fire-and-forget prompt so the Allow sheet can appear in `didFinishLaunching`.
    func requestAuthorizationSoon() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedules (or replaces) a notification `after` seconds from now.
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) {
        let fireAt = Date().addingTimeInterval(max(1, seconds))
        Task { [id, title, body] in
            let settings = await self.center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                await self.requestAuthorization()
            }
            self.enqueue(id: id, title: title, body: body, after: max(1, fireAt.timeIntervalSinceNow))
        }
    }

    private func enqueue(id: String, title: String, body: String, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
            #if DEBUG
            if let error { print("[Notifications] add \(id) failed: \(error.localizedDescription)") }
            #endif
        }
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Completion-handler form: the async `willPresent` witness is skipped on some
    /// iOS 26+ SwiftUI window setups (Liquid Glass overlay windows), which swallows
    /// the Rest/Play banner while the app is open — the live demo's step 7.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
