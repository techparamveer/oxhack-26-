import Foundation

/// Write path for memory (GEMINI_PROMPTS §6). Runs at session end and on daily rollover.
/// STUB — implemented in the Memory step. Keep this signature: returns `learned[]`.
final class MemoryConsolidator: @unchecked Sendable {
    static let shared = MemoryConsolidator()

    enum Reason: String { case sessionEnd = "session_end", dailyRollover = "daily_rollover" }

    @discardableResult
    func run(reason: Reason) async -> [String] { [] }
}
