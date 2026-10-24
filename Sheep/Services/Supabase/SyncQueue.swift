import Foundation

/// One pending write to Supabase.
struct SyncOp: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case upsert, delete }

    var id = UUID()
    var kind: Kind
    var table: String
    /// Coalescing key: a newer op with the same key replaces a pending older one
    /// (e.g. two writes of the same memory file → only the latest is sent).
    var key: String
    var onConflict: String?
    var ignoreDuplicates = false
    var row: JSONValue?
    var filters: [String: String]?
    var attempts = 0
    var nextAttemptAt: Date = .distantPast

    static func upsert(_ table: String, row: JSONValue, onConflict: String, key: String,
                       ignoreDuplicates: Bool = false) -> SyncOp {
        SyncOp(kind: .upsert, table: table, key: "\(table):\(key)", onConflict: onConflict,
               ignoreDuplicates: ignoreDuplicates, row: row)
    }

    static func delete(_ table: String, filters: [String: String], key: String) -> SyncOp {
        SyncOp(kind: .delete, table: table, key: "\(table):\(key)", filters: filters)
    }

    /// Same request shape → can share one bulk upsert.
    func batchable(with other: SyncOp) -> Bool {
        kind == .upsert && other.kind == .upsert && table == other.table
            && onConflict == other.onConflict && ignoreDuplicates == other.ignoreDuplicates
    }
}

/// Sends one batch (all ops share `batchable`). Throw to retry later.
protocol SyncSending: Sendable {
    func send(_ batch: [SyncOp]) async throws
}

extension SupabaseClient: SyncSending {
    func send(_ batch: [SyncOp]) async throws {
        guard let first = batch.first else { return }
        switch first.kind {
        case .upsert:
            try await upsert(table: first.table, rows: batch.compactMap(\.row),
                             onConflict: first.onConflict ?? "", ignoreDuplicates: first.ignoreDuplicates)
        case .delete:
            try await delete(table: first.table, filters: first.filters ?? [:])
        }
    }
}

/// Persisted FIFO of pending writes (JSON file under Documents). Enqueue is synchronous so the order
/// of writes is preserved; flush is async, single-flight, batched, with exponential backoff.
final class SyncQueue: @unchecked Sendable {
    static let maxOps = 1000
    static let maxAttempts = 12
    static let batchSize = 50

    struct FlushResult: Equatable {
        var sent = 0
        var dropped = 0
        var failed = 0
        /// Earliest time a remaining op may be retried (nil = queue empty).
        var nextAttemptAt: Date?
    }

    let fileURL: URL
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var ops: [SyncOp]
    private var flushing = false

    init(fileURL: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SyncOp].self, from: data) {
            ops = saved
        } else {
            ops = []
        }
    }

    var pending: [SyncOp] {
        lock.lock(); defer { lock.unlock() }
        return ops
    }

    func enqueue(_ op: SyncOp) {
        lock.lock(); defer { lock.unlock() }
        ops.removeAll { $0.key == op.key }
        ops.append(op)
        if ops.count > Self.maxOps { ops.removeFirst(ops.count - Self.maxOps) }
        persistLocked()
    }

    /// 2 s, 4 s, 8 s … capped at 10 min.
    static func backoff(attempts: Int) -> TimeInterval {
        min(600, 2 * pow(2, Double(max(0, attempts - 1))))
    }

    /// Sends every op that's due. Returns immediately if another flush is running.
    @discardableResult
    func flush(using sender: SyncSending) async -> FlushResult {
        lock.lock()
        if flushing { lock.unlock(); return FlushResult(nextAttemptAt: nextAttemptLocked()) }
        flushing = true
        lock.unlock()

        var result = FlushResult()
        var skipped = Set<UUID>()      // failed during this flush; don't retry until next flush
        while let batch = nextBatch(excluding: skipped) {
            do {
                try await sender.send(batch)
                let ids = Set(batch.map(\.id))
                lock.lock(); ops.removeAll { ids.contains($0.id) }; persistLocked(); lock.unlock()
                result.sent += batch.count
            } catch {
                let supabaseError = error as? SupabaseError
                let retryable = supabaseError?.isRetryable ?? true   // URLError etc. → retry later
                let (dropped, failed) = markFailed(batch, retryable: retryable)
                result.dropped += dropped
                result.failed += failed
                batch.forEach { skipped.insert($0.id) }
                // Transport down / offline / auth down: stop rather than hammering with every other op.
                if supabaseError == nil || supabaseError == .offline || supabaseError == .authUnavailable { break }
            }
        }

        lock.lock()
        flushing = false
        result.nextAttemptAt = nextAttemptLocked()
        lock.unlock()
        return result
    }

    // MARK: - Private (call with lock held where noted)

    private func nextBatch(excluding skipped: Set<UUID>) -> [SyncOp]? {
        lock.lock(); defer { lock.unlock() }
        let t = now()
        let ready = ops.filter { $0.nextAttemptAt <= t && !skipped.contains($0.id) }
        guard let first = ready.first else { return nil }
        guard first.kind == .upsert else { return [first] }
        return Array(ready.filter { $0.batchable(with: first) }.prefix(Self.batchSize))
    }

    private func markFailed(_ batch: [SyncOp], retryable: Bool) -> (dropped: Int, failed: Int) {
        lock.lock(); defer { lock.unlock() }
        let ids = Set(batch.map(\.id))
        var dropped = 0, failed = 0
        let t = now()
        ops = ops.compactMap { op in
            guard ids.contains(op.id) else { return op }
            var op = op
            op.attempts += 1
            if !retryable || op.attempts >= Self.maxAttempts { dropped += 1; return nil }
            op.nextAttemptAt = t.addingTimeInterval(Self.backoff(attempts: op.attempts))
            failed += 1
            return op
        }
        persistLocked()
        return (dropped, failed)
    }

    private func nextAttemptLocked() -> Date? {
        ops.map(\.nextAttemptAt).min()
    }

    private func persistLocked() {
        AppPaths.ensure(fileURL.deletingLastPathComponent())
        if let data = try? JSONEncoder().encode(ops) { try? data.write(to: fileURL, options: .atomic) }
    }
}
