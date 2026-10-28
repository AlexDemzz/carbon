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

/// A Turn header read back from a Markdown line: `**Speaker** [m:ss] text`.
public struct TurnHeader: Equatable, Sendable {
    public var speaker: String
    public var start: TimeInterval
    /// The rest of the line, as written in the file (Markdown escapes included).
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
    static let sentenceEnds: Set<Character> = [".", "?", "!", "…"]
    static let closingMarks: Set<Character> = ["\"", "'", ")"]
    static let escaped: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">"]

    private struct Word {
        var speaker: String
        var word: TranscribedWord
    }

    /// The Me / Them Turns of a Meeting from both streams' words, each timed from the start of the Meeting.
    public static func turns(me: [TranscribedWord], them: [TranscribedWord]) -> [Turn] {
        let sentences = sentences(me.map { Word(speaker: Self.me, word: $0) })
            + sentences(them.map { Word(speaker: Self.them, word: $0) })
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

    /// Reads a Turn header with the anchored pattern `^\*\*(name)\*\* \[(time)\] `, or nil if the line isn't one.
    public static func header(_ line: some StringProtocol) -> TurnHeader? {
        guard let match = String(line).wholeMatch(of: headerPattern) else { return nil }
        let parts = match.output.2.split(separator: ":").compactMap { Int($0) }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return TurnHeader(speaker: String(match.output.1), start: TimeInterval(seconds), text: String(match.output.3))
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

    nonisolated(unsafe) private static let headerPattern = /\*\*([^*\n]+)\*\* \[(\d+:\d{2}(?::\d{2})?)\] (.*)/

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
