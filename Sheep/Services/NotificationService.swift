import Foundation
import UserNotifications

/// Coalesces concurrent authorization attempts into one `requestAuthorization`.
/// A second in-flight call on a fresh install (didFinishLaunching + `.task`, or
/// `schedule` while the Allow sheet is up) resolves both off the one tap and
/// leaves every later `add` failing with "Source is not authorized".
final class AuthorizationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight: Task<Bool, Never>?
    var request: @Sendable () async -> Bool

    init(request: @escaping @Sendable () async -> Bool) {
        self.request = request
    }

    func ensure() async -> Bool {
        lock.lock()
        if let inFlight {
            lock.unlock()
            return await inFlight.value
        }
        let task = Task { await self.request() }
        inFlight = task
        lock.unlock()
        return await task.value
    }

    /// One `requestAuthorization`, invoked on the caller’s thread (a user gesture).
    func start(center: UNUserNotificationCenter) {
        lock.lock()
        if inFlight != nil { lock.unlock(); return }
        let state = CallbackWaiter()
        inFlight = Task { await state.wait() }
        lock.unlock()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            #if DEBUG
            NSLog("[Notifications] requestAuthorization granted=\(granted) error=\(String(describing: error))")
            #endif
            state.resume(granted)
        }
    }

    /// Tests only: drop the cached task so the next `ensure` runs `request` again.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        inFlight = nil
    }
}

/// Bridges the callback-style `requestAuthorization` to async waiters.
private final class CallbackWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var value: Bool?

    func resume(_ granted: Bool) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: granted)
        } else {
            value = granted
            lock.unlock()
        }
    }

    func wait() async -> Bool {
        await withCheckedContinuation { cont in
            lock.lock()
            if let value {
                lock.unlock()
                cont.resume(returning: value)
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }
}

/// Local notifications only (no push, no entitlements). Banners also show while the app is open.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()
    private let center: UNUserNotificationCenter
    private let authorization: AuthorizationGate

    override init() {
        let center = UNUserNotificationCenter.current()
        self.center = center
        authorization = AuthorizationGate { [center] in
            await NotificationService.ask(center)
        }
        super.init()
    }

    private static func ask(_ center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied { return false }
        // Always call the API unless denied. iOS 27 can report Authorized while
        // `add` still fails; skipping the call is what skipped the Allow sheet.
        return await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    #if DEBUG
                    NSLog("[Notifications] requestAuthorization granted=\(granted) error=\(String(describing: error))")
                    #endif
                    cont.resume(returning: granted)
                }
            }
        }
    }

    func configure() {
        center.delegate = self
    }

    /// Starts the one Allow prompt on the caller’s thread (Home / Rest / Play start tap).
    func requestAuthorizationSoon() {
        authorization.start(center: center)
    }

    /// Waits for the in-flight prompt (or returns the cached grant).
    func requestAuthorization() async {
        _ = await waitUntilAuthorized()
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
        #if DEBUG
        NotificationRecorder.scheduled(id: id, title: title, body: body, fireAt: fireAt)
        #endif
        Task { [id, title, body] in
            // Never `add` while `.notDetermined`. On iOS 27 that rejection
            // ("Source is not authorized") sticks until the simulator is erased,
            // even after the user later taps Allow.
            let granted = await self.waitUntilAuthorized()
            #if DEBUG
            NSLog("[Notifications] wait \(id) granted=\(granted)")
            #endif
            guard granted else {
                #if DEBUG
                NSLog("[Notifications] skip \(id): not authorized")
                NotificationRecorder.status(id: id, "denied")
                #endif
                return
            }
            // Let BulletinBoard finish writing the Allow tap. Adding in the same
            // run loop as the callback poisons the source until the sim is erased.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if onlyIfMissing {
                let pending = await self.center.pendingNotificationRequests()
                if pending.contains(where: { $0.identifier == id }) { return }
            }
            guard self.isCurrent(id, generation) else { return }   // cancelled or replaced meanwhile
            self.enqueue(id: id, title: title, body: body, after: max(1, fireAt.timeIntervalSinceNow),
                         generation: generation)
        }
    }

    /// Joins the one in-flight prompt started from a user gesture.
    /// Do not trust `notificationSettings` as a skip — iOS 27 can report Authorized
    /// while `add` still fails with "Source is not authorized".
    private func waitUntilAuthorized() async -> Bool {
        await authorization.ensure()
    }

    private func enqueue(id: String, title: String, body: String, after seconds: TimeInterval, generation: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.delegate = self   // Liquid Glass overlay windows can steal the weak delegate
        center.removePendingNotificationRequests(withIdentifiers: [id])
        add(request, id: id, generation: generation, attempt: 0)
    }

    private func add(_ request: UNNotificationRequest, id: String, generation: Int, attempt: Int) {
        center.add(request) { [weak self] error in
            #if DEBUG
            if let error {
                NSLog("[Notifications] add \(id) failed (attempt \(attempt)): \(error.localizedDescription)")
            } else {
                NSLog("[Notifications] add \(id) ok")
            }
            #endif
            guard let self, self.isCurrent(id, generation) else { return }
            let retry = attempt < 4 && error?.localizedDescription.contains("not authorized") == true
            #if DEBUG
            NotificationRecorder.status(id: id, error.map {
                (retry ? "retrying: " : "error: ") + NotificationRecorder.describe($0)
            } ?? "ok")
            #endif
            guard retry else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.isCurrent(id, generation) else { return }
                self.add(request, id: id, generation: generation, attempt: attempt + 1)
            }
        }
    }

    func cancel(id: String) {
        _ = bump(id)
        #if DEBUG
        NotificationRecorder.status(id: id, "cancelled")
        #endif
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
