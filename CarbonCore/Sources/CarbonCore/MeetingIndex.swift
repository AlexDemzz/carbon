import Foundation

/// `meetings.json`, version 1: Carbon's index of the Library.
public struct MeetingIndex: Equatable, Sendable, Codable {
    public var version = 1
    public var meetings: [Entry] = []
    public var deleted: [Tombstone] = []

    public init() {}

    public struct Entry: Equatable, Sendable, Codable {
        public var id: UUID
        /// Relative to the Library folder.
        public var file: String
        public var title: String
        public var start: String
        public var end: String
        public var language: String
        public var provider: String
        public var providerMeetingId: String?
        public var meetingApp: String?
        public var calendarEventId: String?
        public var participants: [Participant]
        public var speakers: [Speaker]
        public var transcript: String
        public var summary: String
        public var color: String?
        public var audio: String?
        public var writtenHash: String

        private enum CodingKeys: String, CodingKey {
            case id, file, title, start, end, language, provider, providerMeetingId, meetingApp
            case calendarEventId, participants, speakers, transcript, summary, color, audio, writtenHash
        }

        public init(
            id: UUID, file: String, title: String, start: String, end: String, language: String,
            provider: String, providerMeetingId: String? = nil, meetingApp: String? = nil,
            calendarEventId: String? = nil, participants: [Participant], speakers: [Speaker] = [],
            transcript: String, summary: String, color: String? = nil, audio: String? = nil, writtenHash: String
        ) {
            self.id = id
            self.file = file
            self.title = title
            self.start = start
            self.end = end
            self.language = language
            self.provider = provider
            self.providerMeetingId = providerMeetingId
            self.meetingApp = meetingApp
            self.calendarEventId = calendarEventId
            self.participants = participants
            self.speakers = speakers
            self.transcript = transcript
            self.summary = summary
            self.color = color
            self.audio = audio
            self.writtenHash = writtenHash
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(file, forKey: .file)
            try container.encode(title, forKey: .title)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(language, forKey: .language)
            try container.encode(provider, forKey: .provider)
            try container.encodeIfPresent(providerMeetingId, forKey: .providerMeetingId)
            try container.encodeIfPresent(meetingApp, forKey: .meetingApp)
            try container.encodeIfPresent(calendarEventId, forKey: .calendarEventId)
            try container.encode(participants, forKey: .participants)
            try container.encode(speakers, forKey: .speakers)
            try container.encode(transcript, forKey: .transcript)
            try container.encode(summary, forKey: .summary)
            try container.encode(color, forKey: .color)
            try container.encodeIfPresent(audio, forKey: .audio)
            try container.encode(writtenHash, forKey: .writtenHash)
        }
    }

    public struct Speaker: Equatable, Sendable, Codable {
        public var label: String
        public var cluster: String
        public var name: String?
        public var voicePrintId: UUID?
        public var match: String?
        public var distance: Double?
        public var speechSeconds: Double

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            try container.encode(cluster, forKey: .cluster)
            try container.encode(name, forKey: .name)
            try container.encode(voicePrintId, forKey: .voicePrintId)
            try container.encode(match, forKey: .match)
            try container.encodeIfPresent(distance, forKey: .distance)
            try container.encode(speechSeconds, forKey: .speechSeconds)
        }
    }

    public struct Tombstone: Equatable, Sendable, Codable {
        public var id: UUID
        public var deletedAt: String

        public init(id: UUID, deletedAt: String) {
            self.id = id
            self.deletedAt = deletedAt
        }
    }
}
