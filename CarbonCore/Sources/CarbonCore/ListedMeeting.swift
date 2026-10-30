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
    /// The `meetings.json` Speakers: who each Turn header label stands for.
    public var speakers: [MeetingIndex.Speaker]
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
        speakers = entry.speakers
        self.markdown = markdown
        searchLines = Self.searchLines(markdown)
    }

    /// True for a Them Speaker no one has named yet: `Them`, or a label whose Speaker has no name.
    public func isUnnamedSpeaker(_ label: String) -> Bool {
        label == TranscriptBuilder.them || speakers.contains { $0.label == label && $0.name == nil }
    }

    /// True for a Speaker heard on a shared mic: the one kind that can be named `Me`, or renamed from it.
    public func isOnMic(_ label: String) -> Bool {
        let named = speakers.filter { $0.label == label }
        return !named.isEmpty && named.allSatisfy { $0.stream == .me }
    }

    /// True for a diarized Speaker whose voice can't become a Voice Print: under 10 s of speech, or no clean voice.
    public func tooLittleSpeechToRemember(_ label: String) -> Bool {
        let clusters = speakers.filter { $0.label == label && $0.cluster != TranscriptBuilder.them }
        return !clusters.isEmpty && clusters.allSatisfy {
            $0.centroid == nil || $0.speechSeconds < VoicePrintMatcher.minimumSpeechSeconds
        }
    }

    private static func searchLines(_ markdown: String) -> [String] {
        MarkdownFile.bodyLines(markdown).compactMap { line in
            guard !line.hasPrefix("#"), !line.allSatisfy(\.isWhitespace) else { return nil }
            if let turn = TranscriptBuilder.turn(atHeaderOf: line[...]) { return "\(turn.speaker): \(turn.text)" }
            return line
        }
    }

    /// The grey line under a row's title: "Oct 27 at 10:00 AM · 42 min · Dana, Marcus +1".
    public func rowDetails(in timeZone: TimeZone) -> String {
        let firstNames = participants.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        var people = firstNames.prefix(2).joined(separator: ", ")
        if firstNames.count > 2 { people += " +\(firstNames.count - 2)" }
        return [dateAndLength(in: timeZone), people].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public struct Detail: Equatable, Sendable {
        public let label: String
        public let value: String
    }

    /// The lines above the Transcript, like a Mail message header: "Date: Oct 27, 2026 at 10:00 AM", "Length: 42 min",
    /// "App: Google Meet", "Language: English".
    public func headerDetails(in timeZone: TimeZone) -> [Detail] {
        let english = Locale(identifier: "en_US")
        let languageName = Locale(identifier: language).language.languageCode
            .flatMap { english.localizedString(forLanguageCode: $0.identifier) } ?? language
        return [
            Detail(label: "Date", value: formatted(start, "MMM d, yyyy 'at' h:mm a", in: timeZone)),
            Detail(label: "Length", value: length),
            Detail(label: "App", value: provider),
            Detail(label: "Language", value: languageName),
        ]
    }

    /// Everyone, for the row's hover.
    public var participantList: String {
        participants.map(\.name).joined(separator: ", ")
    }

    private func dateAndLength(in timeZone: TimeZone) -> String {
        "\(formatted(start, "MMM d 'at' h:mm a", in: timeZone)) · \(length)"
    }

    private var length: String {
        let minutes = max(1, Int(end.timeIntervalSince(start) / 60))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    private func formatted(_ date: Date, _ format: String, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
