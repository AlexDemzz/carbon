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
        var speaker: String
        var word: TranscribedWord
    }

    /// The Me / Them Turns of a Meeting from both streams' words, each timed from the start of the Meeting.
    public static func turns(me: [TranscribedWord], them: [TranscribedWord]) -> [Turn] {
        turns(me: me, them: them, diarization: nil)
    }

    /// The Turns of a Meeting with the Them words split by Speaker: `Speaker A`, `Speaker B`… unless `labels`
    /// names a cluster letter. Without a diarization, the Me / Them fallback.
    public static func turns(
        me: [TranscribedWord], them: [TranscribedWord], diarization: Diarization?, labels: [String: String] = [:]
    ) -> [Turn] {
        let themWords: [Word]
        if let diarization, let clusters = clusters(of: them, in: diarization.segments) {
            let letters = letters(ofClustersInOrder: clusters)
            themWords = zip(them, clusters).map { word, cluster in
                let letter = letters[cluster]!
                return Word(speaker: labels[letter] ?? "Speaker \(letter)", word: word)
            }
        } else {
            themWords = them.map { Word(speaker: Self.them, word: $0) }
        }
        let sentences = sentences(me.map { Word(speaker: Self.me, word: $0) }) + sentences(themWords)
        let ordered = sentences.enumerated().sorted { lhs, rhs in
            let (left, right) = (lhs.element[0], rhs.element[0])
            if left.word.start != right.word.start { return left.word.start < right.word.start }
            if (left.speaker == Self.me) != (right.speaker == Self.me) { return left.speaker == Self.me }
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
        clusters(of: them, in: diarization.segments).map(letters(ofClustersInOrder:)) ?? [:]
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

    private static func letters(ofClustersInOrder clusters: [String]) -> [String: String] {
        var letters: [String: String] = [:]
        for cluster in clusters where letters[cluster] == nil {
            letters[cluster] = letter(letters.count)
        }
        return letters
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
