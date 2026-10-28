import Foundation

/// One stretch of a Transcript attributed to a single Speaker, stamped with the time it starts.
public struct Turn: Equatable, Sendable {
    public var speaker: String
    public var start: TimeInterval
    public var text: String

    public init(speaker: String, start: TimeInterval, text: String) {
        self.speaker = speaker
        self.start = start
        self.text = text
    }
}

/// Turns the Transcriber's words into Turns and the `## Transcript` body, per "Transcript body format in Markdown".
public enum TranscriptBuilder {
    public static let me = "Me"
    public static let them = "Them"

    static let sentencePause: TimeInterval = 1.5
    static let turnSilence: TimeInterval = 10
    static let longestTurn: TimeInterval = 90
    static let nearestSegment: TimeInterval = 1
    static let sentenceEnds: Set<Character> = [".", "?", "!", "…"]
    static let closingMarks: Set<Character> = ["\"", "'", ")"]
    static let escaped: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">"]

    private struct Word {
        var stream: AudioStream
        var speaker: String
        var word: TranscribedWord
    }

    /// A cluster of one stream's diarization. Each run numbers its clusters afresh, so ids are kept per stream.
    public struct StreamCluster: Hashable, Sendable {
        public var stream: AudioStream
        public var id: String

        public init(_ stream: AudioStream, _ id: String) {
            self.stream = stream
            self.id = id
        }
    }

    /// How a Meeting's streams are split into Speakers. A stream with no diarization is written `Me` or `Them`.
    public struct Split: Equatable, Sendable {
        public var me: Diarization?
        public var them: Diarization?
        /// Me clusters left out with their words: the call heard back through the mic.
        public var echo: Set<String>

        public init(me: Diarization? = nil, them: Diarization? = nil, echo: Set<String> = []) {
            self.me = me
            self.them = them
            self.echo = echo
        }
    }

    /// The Me / Them Turns of a Meeting from both streams' words, each timed from the start of the Meeting.
    public static func turns(me: [TranscribedWord], them: [TranscribedWord]) -> [Turn] {
        turns(me: me, them: them, split: Split())
    }

    /// The Turns of a Meeting with the Them words split by Speaker. Without a diarization, the Me / Them fallback.
    public static func turns(
        me: [TranscribedWord], them: [TranscribedWord], diarization: Diarization?, labels: [String: String] = [:]
    ) -> [Turn] {
        turns(me: me, them: them, split: Split(them: diarization), labels: labels)
    }

    /// The Turns of a Meeting with each diarized stream split by Speaker: `Speaker A`, `Speaker B`… lettered
    /// across both streams, unless `labels` names a letter.
    public static func turns(
        me: [TranscribedWord], them: [TranscribedWord], split: Split, labels: [String: String] = [:]
    ) -> [Turn] {
        let heard = attributed(me: me, them: them, split: split)
        let letters = letters(of: heard)
        func words(_ stream: AudioStream, fallback: String) -> [Word] {
            heard[stream, default: []].map { word, cluster in
                let speaker = cluster.map { letters[StreamCluster(stream, $0)]! }.map { labels[$0] ?? "Speaker \($0)" }
                return Word(stream: stream, speaker: speaker ?? fallback, word: word)
            }
        }
        let sentences = sentences(words(.me, fallback: Self.me)) + sentences(words(.them, fallback: Self.them))
        let ordered = sentences.enumerated().sorted { lhs, rhs in
            let (left, right) = (lhs.element[0], rhs.element[0])
            if left.word.start != right.word.start { return left.word.start < right.word.start }
            if left.stream != right.stream { return left.stream == .me }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var grouped: [(speaker: String, start: TimeInterval, end: TimeInterval, words: [String])] = []
        for sentence in ordered {
            let first = sentence[0]
            if let last = grouped.last, last.speaker == first.speaker,
                first.word.start - last.end < turnSilence, first.word.start - last.start <= longestTurn
            {
                grouped[grouped.count - 1].words += sentence.map(\.word.text)
                grouped[grouped.count - 1].end = max(last.end, sentence[sentence.count - 1].word.end)
            } else {
                grouped.append(
                    (first.speaker, first.word.start, sentence[sentence.count - 1].word.end, sentence.map(\.word.text)))
            }
        }
        return grouped.map { Turn(speaker: $0.speaker, start: $0.start, text: capitalized($0.words.joined(separator: " "))) }
    }

    /// The `## Transcript` section: one `**Speaker** [m:ss] text` line per Turn, separated by blank lines.
    public static func body(_ turns: [Turn]) -> String {
        let lines = turns.map { "**\($0.speaker)** [\(MeetingFormat.clock($0.start))] \(escape($0.text))" }
        return (["## Transcript"] + lines).joined(separator: "\n\n") + "\n"
    }

    /// The Speaker label a person's name is written as: `*`, `[` and `]` dropped, line breaks made spaces.
    /// Nil when nothing is left or the name is a reserved label (`Me`, `Them`).
    public static func label(forName name: String) -> String? {
        let cleaned = name.filter { !"*[]".contains($0) }
            .split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        let reserved = [me, them].contains { $0.caseInsensitiveCompare(cleaned) == .orderedSame }
        return reserved ? nil : cleaned
    }

    /// The letter (`A`, `B`…) of each diarization cluster heard in the Them words, in order of its first word.
    /// Empty when no word could be attributed.
    public static func clusterLetters(them: [TranscribedWord], diarization: Diarization) -> [String: String] {
        Dictionary(uniqueKeysWithValues: clusterLetters(me: [], them: them, split: Split(them: diarization)).map {
            ($0.key.id, $0.value)
        })
    }

    /// The letter of each cluster heard in either stream's words, in order of its first word across the Meeting.
    /// Echo clusters have none.
    public static func clusterLetters(
        me: [TranscribedWord], them: [TranscribedWord], split: Split
    ) -> [StreamCluster: String] {
        letters(of: attributed(me: me, them: them, split: split))
    }

    /// Each stream's words with their cluster, nil for a stream that is not split. Echo words are left out.
    private static func attributed(
        me: [TranscribedWord], them: [TranscribedWord], split: Split
    ) -> [AudioStream: [(word: TranscribedWord, cluster: String?)]] {
        func attributed(_ words: [TranscribedWord], _ diarization: Diarization?, echo: Set<String>)
            -> [(word: TranscribedWord, cluster: String?)]
        {
            guard let diarization, let clusters = clusters(of: words, in: diarization.segments) else {
                return words.map { ($0, nil) }
            }
            return zip(words, clusters).filter { !echo.contains($0.1) }.map { ($0, $1) }
        }
        return [.me: attributed(me, split.me, echo: split.echo), .them: attributed(them, split.them, echo: [])]
    }

    /// Letters in order of each cluster's first word, Me first on a tie.
    private static func letters(
        of heard: [AudioStream: [(word: TranscribedWord, cluster: String?)]]
    ) -> [StreamCluster: String] {
        let firsts = [AudioStream.me, .them].flatMap { stream in
            heard[stream, default: []].compactMap { word, cluster in
                cluster.map { (cluster: StreamCluster(stream, $0), start: word.start) }
            }
        }
        var letters: [StreamCluster: String] = [:]
        for first in firsts.enumerated().sorted(by: { lhs, rhs in
            lhs.element.start != rhs.element.start ? lhs.element.start < rhs.element.start : lhs.offset < rhs.offset
        }).map(\.element) where letters[first.cluster] == nil {
            letters[first.cluster] = letter(letters.count)
        }
        return letters
    }

    /// Each word's cluster: the most-overlapping segment, else the nearest one within 1 s of the word's middle,
    /// else the previous word's (the next one's before the first attributed word). Nil when no word is reached.
    private static func clusters(of words: [TranscribedWord], in segments: [Diarization.Segment]) -> [String]? {
        var found = words.map { cluster(of: $0, in: segments) }
        guard let first = found.firstIndex(where: { $0 != nil }) else { return nil }
        var previous = found[first]
        for index in found.indices {
            if found[index] == nil { found[index] = previous } else { previous = found[index] }
        }
        return found.map { $0! }
    }

    private static func cluster(of word: TranscribedWord, in segments: [Diarization.Segment]) -> String? {
        var best: (cluster: String, overlap: TimeInterval)?
        for segment in segments {
            let overlap = min(word.end, segment.end) - max(word.start, segment.start)
            if overlap > (best?.overlap ?? 0) { best = (segment.cluster, overlap) }
        }
        if let best { return best.cluster }
        let middle = (word.start + word.end) / 2
        func distance(_ segment: Diarization.Segment) -> TimeInterval {
            max(segment.start - middle, middle - segment.end, 0)
        }
        guard let nearest = segments.min(by: { distance($0) < distance($1) }), distance(nearest) <= nearestSegment
        else { return nil }
        return nearest.cluster
    }

    /// `A`…`Z`, then `AA`, `AB`…
    private static func letter(_ index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return index < 26 ? String(alphabet[index]) : letter(index / 26 - 1) + String(alphabet[index % 26])
    }

    private static func sentences(_ words: [Word]) -> [[Word]] {
        var sentences: [[Word]] = []
        var current: [Word] = []
        for word in words {
            if let previous = current.last,
                word.speaker != previous.speaker || word.word.start - previous.word.end >= sentencePause
            {
                sentences.append(current)
                current = []
            }
            current.append(word)
            if endsSentence(word.word.text) {
                sentences.append(current)
                current = []
            }
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }

    private static func endsSentence(_ text: String) -> Bool {
        var trimmed = Substring(text)
        while let last = trimmed.last, closingMarks.contains(last) { trimmed = trimmed.dropLast() }
        return trimmed.last.map(sentenceEnds.contains) ?? false
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            if escaped.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
