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
                let entry = participant.email.map { "\(participant.name) <\($0)>" } ?? participant.name
                lines.append("  - \(yaml(entry))")
            }
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n\n" + body
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
