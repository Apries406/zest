import Foundation

/// Release notes come from CHANGELOG.md. The update dialog shows only a short summary;
/// the full notes are one click away ("Release Notes").
public enum ReleaseNotes {
    /// The CHANGELOG.md section of `version` (the lines under `## <version> …`), or nil.
    public static func section(_ changelog: String, version: String) -> String? {
        var lines: [Substring] = []
        var found = false
        for line in changelog.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                if found { break }
                let title = line.dropFirst(3)
                found = title == version || title.hasPrefix(version + " ")
                continue
            }
            if found { lines.append(line) }
        }
        guard found else { return nil }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// A few plain lines for the update dialog: the first sentence of each change, without
    /// links, issue numbers, @mentions or thanks. At most `maxItems` lines.
    public static func summary(_ markdown: String, maxItems: Int = 4) -> String {
        var items: [String] = []
        var current: String?
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if let current { items.append(current) }
                current = String(trimmed.dropFirst(2))
            } else if let open = current, !trimmed.isEmpty, line.hasPrefix(" ") {
                current = open + " " + trimmed  // a wrapped bullet
            } else {
                if let open = current { items.append(open) }
                current = nil
            }
        }
        if let current { items.append(current) }

        var lines = items.compactMap(clean).filter { !$0.isEmpty }
        if lines.isEmpty {
            // No list: use the first paragraph.
            let paragraph = markdown.components(separatedBy: "\n\n").first { !$0.hasPrefix("#") } ?? ""
            return clean(paragraph.replacingOccurrences(of: "\n", with: " ")) ?? ""
        }
        let extra = lines.count - maxItems
        lines = Array(lines.prefix(maxItems))
        var text = lines.map { "• " + $0 }.joined(separator: "\n")
        if extra > 0 { text += "\n…and \(extra) more " + (extra == 1 ? "change" : "changes") }
        return text
    }

    /// The first sentence, as plain text. Nil for lines that are only credits or links.
    static func clean(_ text: String) -> String? {
        var s = text
        // [label](url) → label
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // GitHub's generated notes: "Add X by @someone in https://…".
        s = s.replacingOccurrences(of: #"\s+by\s+@[\w-]+(\s+in\s+\S+)?"#, with: "", options: .regularExpression)
        // Raw links, issue references and @mentions.
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\(\s*(#\d+[,\s]*)+\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(^|\s)#\d+\b"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "`", with: "")
        s = s.replacingOccurrences(of: "**", with: "")
        // Drop sentences that thank people or point elsewhere; keep the first remaining one.
        // A sentence ends at `.` or `!` followed by a space and a capital letter, so `0.1.2`,
        // `e.g. Cyrillic` and file names stay whole.
        s = s.replacingOccurrences(of: "e.g. ", with: "e.g.\u{0}").replacingOccurrences(of: "i.e. ", with: "i.e.\u{0}")
        let sentences = s.replacingOccurrences(of: #"(?<=[.!])\s+(?=[A-Z])"#, with: "\n", options: .regularExpression)
            .split(separator: "\n")
            .map { $0.replacingOccurrences(of: "\u{0}", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { sentence in
                let lower = sentence.lowercased()
                return !sentence.isEmpty && !lower.hasPrefix("thanks") && !lower.hasPrefix("thank you")
                    && !lower.contains("made their first contribution") && !lower.contains("full changelog")
                    && !sentence.contains("@")
            }
        guard let first = sentences.first else { return nil }
        let collapsed = first.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!)])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
        return collapsed.isEmpty ? nil : collapsed
    }
}
