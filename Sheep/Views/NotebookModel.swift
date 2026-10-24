import Foundation

/// A memory file split into its (optional) YAML header and markdown body. Lenient: files without
/// a `---` fenced header simply have no fields and the whole content as body.
struct MemoryDocument: Equatable {
    var fields: [String: String]
    var body: String

    init(_ content: String) {
        var text = content
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else {
            fields = [:]
            body = content
            return
        }
        var parsed: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("-") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let q = value.first, (q == "\"" || q == "'"), value.last == q {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { parsed[key] = value }
        }
        fields = parsed
        body = lines[(end + 1)...].joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }

    var id: String? { fields["id"].flatMap { $0.isEmpty ? nil : $0 } }
    var updated: String? { fields["updated"].flatMap { $0.isEmpty ? nil : $0 } }

    /// Text of the first markdown heading in the body, if any.
    var firstHeading: String? {
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("#") else { continue }
            let title = t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return nil
    }
}

enum NotebookSection: Int, CaseIterable, Identifiable {
    case about, days, noticed, goals, other
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .about: "About you"
        case .days: "Days"
        case .noticed: "What Sheep noticed"
        case .goals: "Goals"
        case .other: "Other notes"
        }
    }
}

struct NotebookEntry: Identifiable, Hashable {
    var path: String
    var title: String
    var caption: String?
    var section: NotebookSection
    var id: String { path }
}

struct NotebookGroup: Identifiable, Equatable {
    var section: NotebookSection
    var entries: [NotebookEntry]
    var id: Int { section.rawValue }
}

/// Pure grouping / titling logic for Sheep's Notebook (testable without UI).
enum NotebookModel {
    static func section(for path: String) -> NotebookSection {
        if path == "profile.md" { return .about }
        if path.hasPrefix("timeline/daily/") { return .days }
        if path.hasPrefix("knowledge/") { return .noticed }
        if path.hasPrefix("workstreams/") { return .goals }
        return .other
    }

    static func groups(from files: [MemoryFile]) -> [NotebookGroup] {
        let entries = files.map(entry(for:))
        return NotebookSection.allCases.compactMap { section in
            let items = entries.filter { $0.section == section }
            guard !items.isEmpty else { return nil }
            return NotebookGroup(section: section, entries: items.sorted { order($0, $1, in: section) })
        }
    }

    static func entry(for file: MemoryFile) -> NotebookEntry {
        let doc = MemoryDocument(file.content)
        var caption = doc.updated.map { "updated \(formatUpdated($0))" }
        if file.path.hasPrefix("workstreams/completed/") {
            caption = ["done", caption].compactMap { $0 }.joined(separator: " · ")
        }
        return NotebookEntry(path: file.path, title: title(path: file.path, document: doc),
                             caption: caption, section: section(for: file.path))
    }

    /// Friendly title: fixed labels for known files, date for daily files, otherwise
    /// first heading → YAML `id` → file name.
    static func title(path: String, document doc: MemoryDocument) -> String {
        let name = (path as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        if path == "knowledge/what-works.md" { return "What gets you back" }
        if path.hasPrefix("timeline/daily/"), let date = dailyTitle(stem) { return date }
        if let heading = doc.firstHeading { return heading }
        if let id = doc.id { return humanize(id) }
        return humanize(stem)
    }

    static func humanize(_ slug: String) -> String {
        let words = slug.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard let first = words.first else { return slug }
        return first.uppercased() + words.dropFirst()
    }

    /// "2026-10-23" → "Fri 23 Oct". Nil if not a yyyy-MM-dd date.
    static func dailyTitle(_ stem: String) -> String? {
        guard let date = dayParser.date(from: stem) else { return nil }
        return dayFormatter.string(from: date)
    }

    /// Lenient `updated:` formatting: ISO datetime or date → "Fri 23 Oct"; anything else is shown raw.
    static func formatUpdated(_ raw: String) -> String {
        if let date = parseDate(raw) { return dayFormatter.string(from: date) }
        return raw
    }

    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        if s.count >= 10, let d = dayParser.date(from: String(s.prefix(10))) { return d }
        return nil
    }

    private static func order(_ a: NotebookEntry, _ b: NotebookEntry, in section: NotebookSection) -> Bool {
        switch section {
        case .days:
            return a.path > b.path // yyyy-MM-dd file names → newest first
        case .noticed:
            let rank = ["knowledge/patterns.md": 0, "knowledge/what-works.md": 1]
            let (ra, rb) = (rank[a.path] ?? 2, rank[b.path] ?? 2)
            return ra != rb ? ra < rb : a.path < b.path
        case .goals:
            let (ca, cb) = (a.path.hasPrefix("workstreams/completed/"), b.path.hasPrefix("workstreams/completed/"))
            return ca != cb ? !ca : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        default:
            return a.path < b.path
        }
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()
}

/// Line-based markdown blocks for the Notebook file view (headings, bullets, paragraphs).
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(indent: Int, text: String)
    case paragraph(String)
    case spacer

    static func parse(_ body: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        for raw in body.components(separatedBy: "\n") {
            let leading = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if let last = out.last, last != .spacer { out.append(.spacer) }
            } else if t.hasPrefix("#") {
                let level = t.prefix(while: { $0 == "#" }).count
                let text = t.dropFirst(level).trimmingCharacters(in: .whitespaces)
                out.append(text.isEmpty ? .spacer : .heading(level: level, text: text))
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                out.append(.bullet(indent: leading / 2, text: String(t.dropFirst(2))))
            } else {
                out.append(.paragraph(t))
            }
        }
        while out.last == .spacer { out.removeLast() }
        while out.first == .spacer { out.removeFirst() }
        return out
    }
}
