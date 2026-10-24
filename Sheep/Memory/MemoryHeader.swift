import Foundation

/// YAML front matter on every memory file:
/// ```
/// ---
/// id: what-works
/// type: procedural
/// aliases: [nudges, tone, instagram]
/// updated: 2026-10-24
/// ---
/// ```
/// Only these four keys are understood; anything else is ignored on parse and dropped on serialise.
struct MemoryHeader: Equatable {
    var id: String
    var type: String
    var aliases: [String]
    var updated: String

    init(id: String, type: String, aliases: [String] = [], updated: String) {
        self.id = id
        self.type = type
        self.aliases = aliases
        self.updated = updated
    }

    /// Splits `content` into header + body. Returns `nil` header when there is no `---` front matter.
    static func parse(_ content: String) -> (header: MemoryHeader?, body: String) {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (nil, content) }

        var fields: [String: String] = [:]
        var aliases: [String] = []
        var currentKey: String?
        for raw in lines[1..<end] {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("- "), currentKey == "aliases" {
                aliases.append(unquote(String(line.dropFirst(2))))
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            currentKey = key
            if key == "aliases" {
                aliases.append(contentsOf: parseInlineList(value))
            } else {
                fields[key] = unquote(value)
            }
        }
        lines.removeSubrange(0...end)
        var body = lines.joined(separator: "\n")
        while body.hasPrefix("\n") { body.removeFirst() }
        let header = MemoryHeader(
            id: fields["id"] ?? "",
            type: fields["type"] ?? "",
            aliases: aliases.map { $0.lowercased() }.filter { !$0.isEmpty },
            updated: fields["updated"] ?? ""
        )
        return (header, body)
    }

    var serialized: String {
        let list = aliases.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ", ")
        return "---\nid: \(id)\ntype: \(type)\naliases: [\(list)]\nupdated: \(updated)\n---\n"
    }

    /// Header + body as a full file.
    func file(body: String) -> String {
        serialized + "\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func parseInlineList(_ value: String) -> [String] {
        var v = value
        guard !v.isEmpty else { return [] }
        if v.hasPrefix("[") { v.removeFirst() }
        if v.hasSuffix("]") { v.removeLast() }
        var out: [String] = []
        var current = ""
        var inQuote: Character?
        for ch in v {
            if let q = inQuote {
                if ch == q { inQuote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch == "," {
                out.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            } else {
                current.append(ch)
            }
        }
        out.append(current.trimmingCharacters(in: .whitespaces))
        return out.filter { !$0.isEmpty }
    }

    private static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, let f = t.first, let l = t.last, f == l, f == "\"" || f == "'" {
            return String(t.dropFirst().dropLast())
        }
        return t
    }
}

extension MemoryFile {
    var header: MemoryHeader? { MemoryHeader.parse(content).header }
    /// Content without the YAML header.
    var body: String { MemoryHeader.parse(content).body }
    /// First `# ` heading, else the header id, else the file name.
    var title: String {
        for line in body.components(separatedBy: "\n") where line.hasPrefix("# ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if let id = header?.id, !id.isEmpty { return id }
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

/// Shared date formats for memory files (local time).
enum MemoryDates {
    static func day(_ d: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func time(_ d: Date, calendar: Calendar = .current) -> String {
        format(d, "HH:mm", calendar)
    }

    /// "Fri 30 Oct"
    static func short(_ d: Date, calendar: Calendar = .current) -> String {
        format(d, "EEE d MMM", calendar)
    }

    /// "Friday"
    static func weekday(_ d: Date, calendar: Calendar = .current) -> String {
        format(d, "EEEE", calendar)
    }

    static func parseDay(_ s: String, calendar: Calendar = .current) -> Date? {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    static func format(_ d: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = pattern
        return f.string(from: d)
    }
}
