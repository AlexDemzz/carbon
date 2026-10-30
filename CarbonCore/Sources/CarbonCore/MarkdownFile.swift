import Foundation

/// A Meeting's Markdown file: YAML frontmatter, then the body.
enum MarkdownFile {
    static func render(_ meeting: FinishedMeeting, body: String) -> String {
        var lines = [
            "---",
            "provider: \(yaml(meeting.provider))",
            "id: \(meeting.id.uuidString)",
            "date: \(MeetingFormat.timestamp(meeting.start, in: meeting.timeZone))",
            "title: \(yaml(meeting.title))",
            "duration: \(MeetingFormat.clock(meeting.end.timeIntervalSince(meeting.start)))",
            "language: \(MeetingFormat.bcp47(meeting.language))",
        ]
        if meeting.participants.isEmpty {
            lines.append("participants: []")
        } else {
            lines.append("participants:")
            for participant in meeting.participants {
                lines.append("  - \(yaml(item(participant)))")
            }
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n\n" + body
    }

    /// The frontmatter's `id`, Carbon's Meeting UUID, or nil for a file Carbon didn't write.
    static func id(in markdown: String) -> UUID? {
        frontmatterLines(markdown)?.lazy.compactMap { line in
            line.hasPrefix("id:") ? UUID(uuidString: line.dropFirst(3).trimmingCharacters(in: .whitespaces)) : nil
        }.first
    }

    /// The file with only its frontmatter `title` line changed, or nil when it has none.
    static func replacingTitle(in markdown: String, with title: String) -> String? {
        var lines = markdown.linesKeepingEnds
        guard let frontmatter = frontmatterLines(markdown),
              let position = frontmatter.firstIndex(where: { $0.hasPrefix("title:") })
        else { return nil }
        let lineEnd = lines[position].hasSuffix("\r") ? "\r" : ""
        lines[position] = "title: \(yaml(title))\(lineEnd)"
        return lines.joined(separator: "\n")
    }

    /// The lines between the opening and closing `---`, without their line endings, or nil without frontmatter.
    /// Their indices are those of `markdown.lines`.
    static func frontmatterLines(_ markdown: String) -> ArraySlice<String>? {
        let lines = markdown.lines
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        return lines[1..<end]
    }

    /// The lines after the frontmatter, or every line without one, without their line endings.
    static func bodyLines(_ markdown: String) -> ArraySlice<String> {
        let lines = markdown.lines
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return lines[...] }
        return lines[(end + 1)...]
    }

    /// A `participants` item as `participant(_:)` reads it back: `Name <email>`, or a bare name.
    static func item(_ participant: Participant) -> String {
        participant.email.map { "\(participant.name) <\($0)>" } ?? participant.name
    }

    /// A plain scalar when YAML reads it back unchanged, a double-quoted string otherwise.
    static func yaml(_ value: String) -> String {
        let indicators = Set("-?:,[]{}#&*!|>'\"%@`")
        let needsQuotes =
            value.isEmpty
            || value.first.map(indicators.contains) == true
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
            || value.contains(": ") || value.contains(" #")
            || value.contains(where: \.isNewline)
            || ["true", "false", "yes", "no", "null", "~", "on", "off"].contains(value.lowercased())
            || Double(value) != nil
        guard needsQuotes else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
