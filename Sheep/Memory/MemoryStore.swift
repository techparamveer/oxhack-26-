import Foundation

/// A markdown memory file under `Documents/memory/` (relative path, e.g. "knowledge/patterns.md").
struct MemoryFile: Identifiable, Equatable {
    var path: String
    var content: String
    var id: String { path }
}

/// Markdown memory files with YAML headers (id / type / aliases / updated) — see `MemoryHeader`.
/// Every overwrite/delete/move first copies the old file to `history/<timestamp>/<path>` (our "git").
/// Paths are relative to the memory root; anything escaping it (or touching `history/`) is refused.
final class MemoryStore: @unchecked Sendable {
    static let shared = MemoryStore()
    private let fm = FileManager.default
    private let lock = NSRecursiveLock()
    private let rootOverride: URL?
    /// When set, all snapshots in the current `batch {}` share one history folder.
    private var batchStamp: String?

    /// `root` defaults to `AppPaths.memory` (evaluated lazily so tests can swap `AppPaths.root`).
    init(root: URL? = nil) {
        self.rootOverride = root
    }

    var root: URL { rootOverride ?? AppPaths.memory }
    var historyRoot: URL { root.appendingPathComponent("history", isDirectory: true) }

    // MARK: - Read

    /// All `.md` files (excluding `history/`), sorted by path.
    func list() -> [MemoryFile] {
        lock.lock(); defer { lock.unlock() }
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [MemoryFile] = []
        for case let url as URL in e where url.pathExtension == "md" {
            let rel = relativePath(url)
            if rel.hasPrefix("history/") { continue }
            out.append(MemoryFile(path: rel, content: (try? String(contentsOf: url, encoding: .utf8)) ?? ""))
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Files under a folder prefix, e.g. `list(in: "workstreams/active/")`.
    func list(in folder: String) -> [MemoryFile] {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return list().filter { $0.path.hasPrefix(prefix) }
    }

    func read(_ path: String) -> String? {
        guard let url = safeURL(path) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func file(_ path: String) -> MemoryFile? {
        read(path).map { MemoryFile(path: path, content: $0) }
    }

    /// Alias keyword search: files whose header aliases (or id) match any keyword, best match first.
    func search(keywords: [String]) -> [MemoryFile] {
        let kws = Set(keywords.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 })
        guard !kws.isEmpty else { return [] }
        var scored: [(MemoryFile, Int)] = []
        for file in list() {
            guard let header = file.header else { continue }
            let terms = header.aliases + (header.id.isEmpty ? [] : [header.id.lowercased()])
            let hits = kws.filter { kw in terms.contains { Self.matches(alias: $0, keyword: kw) } }.count
            if hits > 0 { scored.append((file, hits)) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.path < $1.0.path }.map(\.0)
    }

    static func matches(alias: String, keyword: String) -> Bool {
        if alias == keyword { return true }
        if keyword.count >= 4, alias.contains(keyword) { return true }
        if alias.count >= 4, keyword.contains(alias) { return true }
        return false
    }

    // MARK: - Write

    /// Writes a file, snapshotting the previous version first. Refuses paths outside the memory root.
    /// No-op (and no snapshot) when the content is unchanged.
    @discardableResult
    func write(_ path: String, content: String) -> Bool {
        guard let url = safeURL(path) else { return false }
        lock.lock(); defer { lock.unlock() }
        if let old = try? String(contentsOf: url, encoding: .utf8) {
            if old == content { return true }
            snapshot(path)
        }
        AppPaths.ensure(url.deletingLastPathComponent())
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Deletes a file after snapshotting it.
    @discardableResult
    func delete(_ path: String) -> Bool {
        guard let url = safeURL(path) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard fm.fileExists(atPath: url.path) else { return false }
        snapshot(path)
        return (try? fm.removeItem(at: url)) != nil
    }

    /// Moves `from` → `to` (snapshotting both sides first), optionally replacing the content.
    @discardableResult
    func move(_ from: String, to: String, content: String? = nil) -> Bool {
        guard let src = safeURL(from), safeURL(to) != nil else { return false }
        lock.lock(); defer { lock.unlock() }
        let existing = try? String(contentsOf: src, encoding: .utf8)
        guard let newContent = content ?? existing else { return false }
        return batch {
            guard write(to, content: newContent) else { return false }
            if existing != nil, from != to { delete(from) }
            return true
        }
    }

    /// Groups all snapshots taken inside `body` into a single `history/<timestamp>/` folder.
    @discardableResult
    func batch<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        if batchStamp != nil { return body() }
        batchStamp = Self.newStamp(in: historyRoot)
        defer { batchStamp = nil }
        return body()
    }

    /// Number of `history/<timestamp>/` snapshot folders.
    func historySnapshotCount() -> Int {
        let items = (try? fm.contentsOfDirectory(atPath: historyRoot.path)) ?? []
        return items.filter { !$0.hasPrefix(".") }.count
    }

    // MARK: - Paths

    /// Resolves a relative path inside the memory root, or `nil` if it escapes it, is absolute,
    /// or points into `history/`.
    func safeURL(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else { return nil }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        guard parts.first != "history" else { return nil }
        let base = root.standardizedFileURL
        let url = base.appendingPathComponent(trimmed).standardizedFileURL
        guard url.path.hasPrefix(base.path + "/") else { return nil }
        return url
    }

    func relativePath(_ url: URL) -> String {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        let full = url.standardizedFileURL.resolvingSymlinksInPath().path
        return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
    }

    /// "Dissertation ch.3" → "dissertation-ch3"
    static func slug(_ s: String) -> String {
        var out = ""
        var lastDash = false
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch); lastDash = false
            } else if ch == " " || ch == "-" || ch == "_" || ch == "/" {
                if !lastDash, !out.isEmpty { out.append("-"); lastDash = true }
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "untitled" : String(out.prefix(48))
    }

    // MARK: - History

    private func snapshot(_ path: String) {
        guard let src = safeURL(path), fm.fileExists(atPath: src.path) else { return }
        let stamp = batchStamp ?? Self.newStamp(in: historyRoot)
        let dest = historyRoot.appendingPathComponent(stamp, isDirectory: true).appendingPathComponent(path)
        AppPaths.ensure(dest.deletingLastPathComponent())
        if fm.fileExists(atPath: dest.path) { return } // first version in this batch wins
        try? fm.copyItem(at: src, to: dest)
    }

    private static func newStamp(in history: URL) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let base = f.string(from: .now)
        var stamp = base
        var n = 2
        while FileManager.default.fileExists(atPath: history.appendingPathComponent(stamp).path) {
            stamp = "\(base)-\(n)"; n += 1
        }
        return stamp
    }
}
