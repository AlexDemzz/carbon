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
    static let snapWords = 2
    static let snapSpan: TimeInterval = 1
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
        /// Me clusters that are the call heard back through the mic: their words heard while Them speaks are left out.
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
        let heard = kept(attributed(me: me, them: them, split: split))
        let letters = letters(of: heard)
        func words(_ stream: AudioStream) -> [Word] {
            heard[stream, default: []].map { word, cluster in
                Word(
                    stream: stream, speaker: speaker(of: cluster, on: stream, letters: letters, labels: labels),
                    word: word)
            }
        }
        let sentences = sentences(words(.me)) + sentences(words(.them))
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
        letters(of: kept(attributed(me: me, them: them, split: split)))
    }

    /// Each word of both streams with its cluster and the Speaker it is written as, or the Them speech it was
    /// left out over as echo.
    static func heard(
        me: [TranscribedWord], them: [TranscribedWord], split: Split, labels: [String: String]
    ) -> [AudioStream: [HeardWord]] {
        let attributed = attributed(me: me, them: them, split: split)
        let letters = letters(of: kept(attributed))
        return attributed.mapValues { words in
            words.map { word in
                guard word.themSpeech == nil else { return word }
                var written = word
                written.speaker = speaker(of: word.cluster, on: word.stream, letters: letters, labels: labels)
                return written
            }
        }
    }

    struct HeardWord {
        var stream: AudioStream
        var word: TranscribedWord
        var cluster: String?
        /// The Them speech this word was heard over, when it is left out as echo.
        var themSpeech: MicEcho.Span?
        var speaker: String?
    }

    /// The written label of a cluster: its letter's label, else `Speaker <letter>`; the stream's name without one.
    private static func speaker(
        of cluster: String?, on stream: AudioStream, letters: [StreamCluster: String], labels: [String: String]
    ) -> String {
        guard let letter = cluster.map({ letters[StreamCluster(stream, $0)]! }) else {
            return stream == .me ? Self.me : Self.them
        }
        return labels[letter] ?? "Speaker \(letter)"
    }

    private static func kept(
        _ heard: [AudioStream: [HeardWord]]
    ) -> [AudioStream: [(word: TranscribedWord, cluster: String?)]] {
        heard.mapValues { $0.filter { $0.themSpeech == nil }.map { ($0.word, $0.cluster) } }
    }

    /// Each stream's words with their cluster, nil for a stream that is not split. A word of an echo cluster heard
    /// while Them speaks is left out; one heard while Them is silent takes the nearest cluster in the room however
    /// far, as someone in the room spoke over a quiet call, or none without one. Clusters are then snapped to
    /// sentence ends.
    private static func attributed(
        me: [TranscribedWord], them: [TranscribedWord], split: Split
    ) -> [AudioStream: [HeardWord]] {
        func attributed(_ stream: AudioStream, _ words: [TranscribedWord], _ segments: [Diarization.Segment]?)
            -> [HeardWord]
        {
            let found = segments.flatMap { clusters(of: words, in: $0) } ?? words.map { _ in nil }
            return zip(words, found).map { HeardWord(stream: stream, word: $0, cluster: $1) }
        }
        let heardThem = snapped(attributed(.them, them, split.them?.segments))
        guard let mic = split.me, !split.echo.isEmpty else {
            return [.me: snapped(attributed(.me, me, split.me?.segments)), .them: heardThem]
        }
        let themSpeech = MicEcho.themSpeech(them: split.them, themWords: them)
        let room = SegmentIndex(mic.segments.filter { !split.echo.contains($0.cluster) })
        let heardMe = attributed(.me, me, mic.segments).map { heard in
            guard let cluster = heard.cluster, split.echo.contains(cluster) else { return heard }
            guard let heardOver = MicEcho.themSpeech(over: heard.word, in: themSpeech) else {
                var inTheRoom = heard
                inTheRoom.cluster = room.cluster(of: heard.word, within: .infinity)
                return inTheRoom
            }
            var dropped = heard
            dropped.themSpeech = heardOver
            return dropped
        }
        return [.me: snapped(heardMe), .them: heardThem]
    }

    /// Snaps the clusters of the words written to sentence ends. Echo words take no part: none is moved to the
    /// Speaker next to it, and none takes a neighbour's words with it out of the Transcript.
    private static func snapped(_ heard: [HeardWord]) -> [HeardWord] {
        let written = heard.indices.filter { heard[$0].themSpeech == nil && heard[$0].cluster != nil }
        let clusters = snapped(written.map { heard[$0].cluster! }, of: written.map { heard[$0].word })
        var snapped = heard
        for (index, cluster) in zip(written, clusters) { snapped[index].cluster = cluster }
        return snapped
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
        let segments = SegmentIndex(segments)
        var found = words.map { segments.cluster(of: $0) }
        guard let first = found.firstIndex(where: { $0 != nil }) else { return nil }
        var previous = found[first]
        for index in found.indices {
            if found[index] == nil { found[index] = previous } else { previous = found[index] }
        }
        return found.map { $0! }
    }

    /// Moves a change of cluster that falls inside a sentence to the nearest sentence end, when at most 2 words
    /// and 1 s away: the words are contiguous and the segment boundaries a fraction of a second off, so a change
    /// often lands a word early or late. Nearest is in words moved; on a tie the words finish the sentence they are in.
    private static func snapped(_ clusters: [String], of words: [TranscribedWord]) -> [String] {
        var clusters = clusters
        func ends(_ index: Int) -> Bool { endsSentence(words[index].text) }
        for change in words.indices.dropFirst() where clusters[change] != clusters[change - 1] && !ends(change - 1) {
            let (before, after) = (clusters[change - 1], clusters[change])
            let finishing = (change..<min(change + snapWords, words.count - 1)).first { last in
                ends(last) && clusters[change...last + 1].allSatisfy { $0 == after }
                    && words[last].end - words[change].start <= snapSpan
            }
            let starting = stride(from: change - 1, through: max(change - snapWords, 1), by: -1).first { first in
                ends(first - 1) && clusters[first - 1..<change].allSatisfy { $0 == before }
                    && words[change].start - words[first].start <= snapSpan
            }
            let finished = finishing.map { $0 - change + 1 } ?? .max
            let started = starting.map { change - $0 } ?? .max
            if let finishing, finished <= started {
                clusters.replaceSubrange(change...finishing, with: repeatElement(before, count: finished))
            } else if let starting {
                clusters.replaceSubrange(starting..<change, with: repeatElement(after, count: started))
            }
        }
        return clusters
    }

    /// A diarization's segments sorted by start, so each word looks only at the few segments around it: a Meeting has
    /// thousands of both.
    private struct SegmentIndex {
        private let segments: [Diarization.Segment]
        /// The positions of `segments`, by start.
        private let byStart: [Int]
        /// The latest end among the segments up to each position of `byStart`.
        private let latestEnd: [TimeInterval]

        init(_ segments: [Diarization.Segment]) {
            self.segments = segments
            byStart = segments.indices.sorted { segments[$0].start < segments[$1].start }
            var latest = -TimeInterval.infinity
            latestEnd = byStart.map { position in
                latest = max(latest, segments[position].end)
                return latest
            }
        }

        /// The word's cluster: the most-overlapping segment's, else the nearest one's within `reach` of its middle.
        /// On a tie, the segment listed first.
        func cluster(of word: TranscribedWord, within reach: TimeInterval = nearestSegment) -> String? {
            let overlapping = positions(startingWhere: { $0 < word.end }, endingWhere: { $0 > word.start })
                .map { (position: $0, overlap: min(word.end, segments[$0].end) - max(word.start, segments[$0].start)) }
                .filter { $0.overlap > 0 }
            // The most overlap, then the lowest position.
            if let best = overlapping.max(by: { ($0.overlap, $1.position) < ($1.overlap, $0.position) }) {
                return segments[best.position].cluster
            }
            let middle = (word.start + word.end) / 2
            let nearest = positions(startingWhere: { $0 - middle <= reach }, endingWhere: { middle - $0 <= reach })
                .map { (position: $0, distance: max(segments[$0].start - middle, middle - segments[$0].end, 0)) }
                .filter { $0.distance <= reach }
                .min { ($0.distance, $0.position) < ($1.distance, $1.position) }
            return nearest.map { segments[$0.position].cluster }
        }

        /// The positions of the segments whose start and end pass. `starts` must pass every start up to some
        /// time and none after it, `ends` every end from some time on.
        private func positions(
            startingWhere starts: (TimeInterval) -> Bool, endingWhere ends: (TimeInterval) -> Bool
        ) -> [Int] {
            var (low, high) = (0, byStart.count)
            while low < high {
                let middle = (low + high) / 2
                if starts(segments[byStart[middle]].start) { low = middle + 1 } else { high = middle }
            }
            var found: [Int] = []
            var index = low - 1
            while index >= 0, ends(latestEnd[index]) {
                if ends(segments[byStart[index]].end) { found.append(byStart[index]) }
                index -= 1
            }
            return found
        }
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
