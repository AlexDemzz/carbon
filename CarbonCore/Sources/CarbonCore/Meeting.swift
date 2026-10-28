import Foundation

/// A person who took part in a Meeting, as listed in the frontmatter and `meetings.json`.
public struct Participant: Equatable, Sendable, Codable {
    public var name: String
    public var email: String?

    public init(name: String, email: String? = nil) {
        self.name = name
        self.email = email
    }
}

/// A Meeting that has ended, with everything the Library needs to file it.
public struct FinishedMeeting: Equatable, Sendable {
    public enum TranscriptKind: String, Sendable {
        case speakers
        case fallback
    }

    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var timeZone: TimeZone
    public var language: Locale
    public var provider: String
    public var meetingApp: String?
    public var participants: [Participant]
    public var transcriptKind: TranscriptKind
    /// The diarized Speakers, lettered as in the Transcript. Empty for the Me / Them fallback.
    public var speakers: [MeetingIndex.Speaker]

    public init(
        id: UUID, title: String, start: Date, end: Date, timeZone: TimeZone, language: Locale,
        provider: String, meetingApp: String? = nil, participants: [Participant] = [],
        transcriptKind: TranscriptKind, speakers: [MeetingIndex.Speaker] = []
    ) {
        self.speakers = speakers
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.timeZone = timeZone
        self.language = language
        self.provider = provider
        self.meetingApp = meetingApp
        self.participants = participants
        self.transcriptKind = transcriptKind
    }
}

enum MeetingFormat {
    /// ISO 8601 with the offset of `timeZone`, e.g. `2026-10-27T10:00:00-04:00`.
    static func timestamp(_ date: Date, in timeZone: TimeZone) -> String {
        formatter("yyyy-MM-dd'T'HH:mm:ssxxxxx", timeZone).string(from: date)
    }

    /// `2026-10-27`, the file name's date.
    static func day(_ date: Date, in timeZone: TimeZone) -> String {
        formatter("yyyy-MM-dd", timeZone).string(from: date)
    }

    static func year(_ date: Date, in timeZone: TimeZone) -> String {
        formatter("yyyy", timeZone).string(from: date)
    }

    /// The default title, e.g. `Meeting Oct 23, 9:15 AM`.
    static func defaultTitle(start: Date, in timeZone: TimeZone) -> String {
        formatter("'Meeting' MMM d, h:mm a", timeZone).string(from: start)
    }

    /// `m:ss` below an hour, `h:mm:ss` from an hour on, truncated to the second.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func bcp47(_ locale: Locale) -> String {
        locale.identifier(.bcp47)
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
