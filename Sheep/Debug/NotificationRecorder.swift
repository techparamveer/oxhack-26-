import SwiftUI

#if DEBUG
/// `-sheepRecordNotifications`: records the last `NotificationService` request per id and the
/// `UNUserNotificationCenter.add` result, and exposes each as an invisible accessibility element
/// (`debug.notification.<id>`, label `status|title|body|fireAtEpoch`) for the acceptance UI test.
///
/// Lets the test assert the app scheduled the right banner even where the simulator refuses
/// delivery ("Source is not authorized" after an XCTest-driven Allow on iOS 27).
@MainActor @Observable
final class NotificationRecorder {
    static let shared = NotificationRecorder()
    nonisolated static let isEnabled = ProcessInfo.processInfo.arguments.contains("-sheepRecordNotifications")

    struct Entry: Equatable {
        var title: String
        var body: String
        var fireAt: Date
        /// `waiting` (for the Allow answer) · `denied` · `retrying: …` · `ok` · `error: <domain> <code>: <description>` · `cancelled`.
        var status: String
    }

    private(set) var entries: [String: Entry] = [:]

    nonisolated static func scheduled(id: String, title: String, body: String, fireAt: Date) {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            shared.entries[id] = Entry(title: title, body: body, fireAt: fireAt, status: "waiting")
        }
    }

    nonisolated static func status(id: String, _ status: String) {
        guard isEnabled else { return }
        DispatchQueue.main.async { shared.entries[id]?.status = status }
    }

    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}

/// Invisible 1×1 elements; does not change layout, hit testing or screenshots.
struct NotificationRecorderOverlay: View {
    private let recorder = NotificationRecorder.shared

    var body: some View {
        ZStack {
            ForEach(recorder.entries.keys.sorted(), id: \.self) { id in
                if let e = recorder.entries[id] {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "\(e.status)|\(e.title)|\(e.body)|\(Int(e.fireAt.timeIntervalSince1970))"))
                        .accessibilityIdentifier("debug.notification.\(id)")
                }
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
