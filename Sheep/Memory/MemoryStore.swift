import Foundation

/// A markdown memory file under `Documents/memory/` (relative path, e.g. "knowledge/patterns.md").
struct MemoryFile: Identifiable, Equatable {
    var path: String
    var content: String
    var id: String { path }
}

/// Markdown memory files with YAML headers (id / type / aliases / updated).
/// MINIMAL CONTRACT — the Memory step adds YAML header parsing, alias search and
/// `history/<timestamp>/` snapshots before overwrite. Keep these signatures.
final class MemoryStore: @unchecked Sendable {
    static let shared = MemoryStore()
    private let fm = FileManager.default

    var root: URL { AppPaths.memory }

    /// All `.md` files (excluding `history/`), sorted by path.
    func list() -> [MemoryFile] {
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [MemoryFile] = []
        for case let url as URL in e where url.pathExtension == "md" {
            let rel = relativePath(url)
            if rel.hasPrefix("history/") { continue }
            out.append(MemoryFile(path: rel, content: (try? String(contentsOf: url, encoding: .utf8)) ?? ""))
        }
        return out.sorted { $0.path < $1.path }
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func write(_ path: String, content: String) {
        let url = root.appendingPathComponent(path)
        AppPaths.ensure(url.deletingLastPathComponent())
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func delete(_ path: String) {
        try? fm.removeItem(at: root.appendingPathComponent(path))
    }

    /// Number of `history/<timestamp>/` snapshot folders.
    func historySnapshotCount() -> Int {
        (try? fm.contentsOfDirectory(atPath: AppPaths.history.path))?.count ?? 0
    }

    func relativePath(_ url: URL) -> String {
        let base = root.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
    }
}
