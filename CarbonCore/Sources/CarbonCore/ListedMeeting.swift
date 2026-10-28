import Foundation

/// A Meeting as the main window lists it: its `meetings.json` entry joined with its Markdown file.
public struct ListedMeeting: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var file: URL
    public var title: String
    public var start: Date
    public var end: Date
    /// BCP 47, e.g. `en-US`.
    public var language: String
    public var provider: String
    public var participants: [Participant]
    public var color: String?
    /// The whole Markdown file, frontmatter included.
    public let markdown: String
    /// The body's text lines, Turn headers shown as "Speaker: ", built once for Search.
    let searchLines: [String]

    init?(_ entry: MeetingIndex.Entry, folder: URL) {
        let file = folder.appending(path: entry.file)
        guard
            let start = try? Date(entry.start, strategy: .iso8601),
            let end = try? Date(entry.end, strategy: .iso8601),
            let markdown = try? String(contentsOf: file, encoding: .utf8)
        else { return nil }
        id = entry.id
        self.file = file
        title = entry.title
        self.start = start
        self.end = end
        language = entry.language
        provider = entry.provider
        participants = entry.participants
        color = entry.color
        self.markdown = markdown
        searchLines = Self.searchLines(markdown)
    }

    private static func searchLines(_ markdown: String) -> [String] {
        var lines = markdown.split(separator: "\n")[...]
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            lines = lines[(end + 1)...]
        }
        return lines.compactMap { line in
            guard !line.hasPrefix("#"), !line.allSatisfy(\.isWhitespace) else { return nil }
            if let turn = TranscriptBuilder.turn(atHeaderOf: line) { return "\(turn.speaker): \(turn.text)" }
            return String(line)
        }
    }

    /// The grey line under a row's title: "Oct 27 at 10:00 AM · 42 min · Dana, Marcus +1".
    public func rowDetails(in timeZone: TimeZone) -> String {
        let firstNames = participants.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        var people = firstNames.prefix(2).joined(separator: ", ")
        if firstNames.count > 2 { people += " +\(firstNames.count - 2)" }
        return [dateAndLength(in: timeZone), people].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The window subtitle: "Oct 27 at 10:00 AM · 42 min · Google Meet · English".
    public func titleBarDetails(in timeZone: TimeZone) -> String {
        let english = Locale(identifier: "en_US")
        let languageName = Locale(identifier: language).language.languageCode
            .flatMap { english.localizedString(forLanguageCode: $0.identifier) } ?? language
        return [dateAndLength(in: timeZone), provider, languageName].joined(separator: " · ")
    }

    /// Everyone, for the row's hover.
    public var participantList: String {
        participants.map(\.name).joined(separator: ", ")
    }

    private func dateAndLength(in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d 'at' h:mm a"
        let minutes = max(1, Int(end.timeIntervalSince(start) / 60))
        let length = minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
        return "\(formatter.string(from: start)) · \(length)"
    }
}
