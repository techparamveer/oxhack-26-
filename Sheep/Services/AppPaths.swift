import Foundation

/// File locations. Tests swap `root` for a temp directory.
enum AppPaths {
    nonisolated(unsafe) static var root: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]

    /// `Documents/memory/` — markdown memory files + events.jsonl (see MVP_PLAN "Memory").
    static var memory: URL { root.appendingPathComponent("memory", isDirectory: true) }
    static var events: URL { memory.appendingPathComponent("events.jsonl") }
    static var history: URL { memory.appendingPathComponent("history", isDirectory: true) }

    static func ensure(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
