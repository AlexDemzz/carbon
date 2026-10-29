import Foundation

/// What the Transcript of a Meeting was built from, written beside it in Debug mode: each stream's words and
/// diarization, the Speaker each word is written as, and why any word was left out.
public struct MeetingDebug: Equatable, Sendable, Codable {
    public struct Stream: Equatable, Sendable, Codable {
        /// The stream's diarization, nil when it is not split by Speaker.
        public var segments: [Diarization.Segment]?
        /// The clusters judged to be the call heard back through the mic.
        public var echo: [String]
        public var words: [Word]

        public init(segments: [Diarization.Segment]?, echo: [String], words: [Word]) {
            self.segments = segments
            self.echo = echo
            self.words = words
        }
    }

    public struct Word: Equatable, Sendable, Codable {
        public var text: String
        public var start: TimeInterval
        public var end: TimeInterval
        public var cluster: String?
        /// The Speaker the word is written as, nil when it was left out.
        public var speaker: String?
        public var dropped: Drop?

        public init(
            text: String, start: TimeInterval, end: TimeInterval, cluster: String?, speaker: String? = nil,
            dropped: Drop? = nil
        ) {
            self.text = text
            self.start = start
            self.end = end
            self.cluster = cluster
            self.speaker = speaker
            self.dropped = dropped
        }
    }

    public struct Drop: Equatable, Sendable, Codable {
        public enum Reason: String, Sendable, Codable {
            /// The call heard back through the mic.
            case echo
        }

        public var reason: Reason
        /// The Them speech the word was heard over.
        public var themSpeech: Span

        public init(reason: Reason, themSpeech: Span) {
            self.reason = reason
            self.themSpeech = themSpeech
        }
    }

    public struct Span: Equatable, Sendable, Codable {
        public var start: TimeInterval
        public var end: TimeInterval

        public init(start: TimeInterval, end: TimeInterval) {
            self.start = start
            self.end = end
        }
    }

    public var me: Stream
    public var them: Stream

    /// The words as `TranscriptBuilder.turns(me:them:split:labels:)` writes them.
    public init(me: [TranscribedWord], them: [TranscribedWord], split: TranscriptBuilder.Split, labels: [String: String]) {
        let heard = TranscriptBuilder.heard(me: me, them: them, split: split, labels: labels)
        func stream(_ stream: AudioStream, _ diarization: Diarization?, echo: Set<String>) -> Stream {
            Stream(
                segments: diarization?.segments, echo: echo.sorted(),
                words: heard[stream, default: []].map { heard in
                    Word(
                        text: heard.word.text, start: heard.word.start, end: heard.word.end, cluster: heard.cluster,
                        speaker: heard.speaker,
                        dropped: heard.echo.map { Drop(reason: .echo, themSpeech: Span(start: $0.start, end: $0.end)) })
                })
        }
        self.me = stream(.me, split.me, echo: split.echo)
        self.them = stream(.them, split.them, echo: [])
    }
}
