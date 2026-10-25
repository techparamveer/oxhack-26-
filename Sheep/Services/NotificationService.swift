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

    /// Latest schedule/cancel per id. `schedule` enqueues asynchronously (after the permission
    /// check), so a later `schedule`/`cancel` for the same id must win over an earlier one still in flight.
    private let lock = NSLock()
    private var generations: [String: Int] = [:]

    private func bump(_ id: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        generations[id, default: 0] += 1
        return generations[id]!
    }

    private func isCurrent(_ id: String, _ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generations[id] == generation
    }

    /// Schedules (or replaces) a notification `after` seconds from now.
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval) {
        schedule(id: id, title: title, body: body, after: seconds, onlyIfMissing: false)
    }

    /// Like `schedule`, but keeps an already-pending request for `id` (e.g. Gemini's text) untouched.
    func scheduleIfMissing(id: String, title: String, body: String, after seconds: TimeInterval) {
        schedule(id: id, title: title, body: body, after: seconds, onlyIfMissing: true)
    }

    private func schedule(id: String, title: String, body: String, after seconds: TimeInterval, onlyIfMissing: Bool) {
        let fireAt = Date().addingTimeInterval(max(1, seconds))
        let generation = bump(id)
        Task { [id, title, body] in
            let settings = await self.center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                await self.requestAuthorization()
            }
            if onlyIfMissing {
                let pending = await self.center.pendingNotificationRequests()
                if pending.contains(where: { $0.identifier == id }) { return }
            }
            guard self.isCurrent(id, generation) else { return }   // cancelled or replaced meanwhile
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
        _ = bump(id)
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
