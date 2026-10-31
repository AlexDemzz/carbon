import Foundation
import NaturalLanguage
import Synchronization

/// Reads which of the checked Meeting Languages a transcript is written in, with `NLLanguageRecognizer` constrained to
/// them: about 1.5 ms a call, from 30 to 500 words. Languages it can't tell apart, such as en-US and en-GB, count as
/// one, the first of them.
struct TextLanguage: Sendable {
    /// The words of each chunk a transcript is judged in.
    static let chunkWords = 10
    /// The least words a transcript's last, shorter chunk needs to be judged at all.
    static let minimumChunkWords = 5

    private let languages: [(locale: Locale, language: NLLanguage)]
    /// One recognizer for every read: a new one loads its model again, two thirds of a read's cost.
    private let recognizer = SharedRecognizer()

    /// Nil when fewer than two of `candidates` are different languages: there is nothing to tell apart.
    init?(candidates: [Locale]) {
        var kept: [(locale: Locale, language: NLLanguage)] = []
        for locale in candidates {
            guard let language = Self.language(of: locale), !kept.contains(where: { $0.language == language })
            else { continue }
            kept.append((locale, language))
        }
        guard kept.count > 1 else { return nil }
        languages = kept
    }

    /// The candidates, one per language.
    var candidates: [Locale] { languages.map(\.locale) }

    /// Whether the recognizer reads `a` and `b` as the same language.
    func same(_ a: Locale, _ b: Locale) -> Bool {
        Self.language(of: a) == Self.language(of: b)
    }

    /// Each candidate's share of `words`, the shares adding up to 1, by candidate.
    func shares(of words: some Collection<TranscribedWord>) -> [Locale: Double] {
        let text = words.map(\.text).joined(separator: " ")
        let hypotheses = recognizer.recognizer.withLock { recognizer in
            recognizer.reset()
            recognizer.languageConstraints = languages.map(\.language)
            recognizer.processString(text)
            return recognizer.languageHypotheses(withMaximum: languages.count)
        }
        return Dictionary(uniqueKeysWithValues: languages.map { ($0.locale, hypotheses[$0.language] ?? 0) })
    }

    /// `locale`'s share of each chunk of `words`, the last one only with `minimumChunkWords` or more.
    func chunkShares(of words: [TranscribedWord], for locale: Locale) -> [Double] {
        let candidate = languages.first { same($0.locale, locale) }?.locale ?? locale
        return stride(from: 0, to: words.count, by: Self.chunkWords).compactMap { start in
            let end = min(start + Self.chunkWords, words.count)
            guard end - start >= Self.minimumChunkWords else { return nil }
            return shares(of: words[start..<end])[candidate] ?? 0
        }
    }

    private static func language(of locale: Locale) -> NLLanguage? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        guard code == "zh" else { return NLLanguage(rawValue: code) }
        let script = locale.language.script ?? Locale.Language(identifier: locale.language.maximalIdentifier).script
        return script == Locale.Script("Hant") ? .traditionalChinese : .simplifiedChinese
    }
}

private final class SharedRecognizer: Sendable {
    let recognizer = Mutex(NLLanguageRecognizer())
}

/// One re-transcription of a stretch of a stream in a candidate language, judged against the current language's
/// transcript of the same stretch. It confirms the candidate when the candidate writes at least as many words, and at
/// least `minimumRate` per second of speech, and most of its chunks read as the candidate. A model given a language it
/// doesn't know writes 0.2–0.8 words per second of speech, or fluent text in its own language
/// (docs/research/text-vs-acoustic-language-identification.md).
struct LanguageProbe: Equatable, Sendable {
    /// The fewest words per second of speech a candidate's transcript must reach.
    static let minimumRate = 0.2

    var candidate: Locale
    var words: Int
    var rate: Double
    var currentRate: Double
    /// The candidate's chunks that read as the candidate, and all its chunks.
    var confirmedChunks: Int
    var chunks: Int
    /// The candidate's share of its whole transcript.
    var share: Double

    init(
        _ candidate: Locale, wrote words: [TranscribedWord], against currentWords: Int, speech: TimeInterval,
        reader: TextLanguage
    ) {
        self.candidate = candidate
        self.words = words.count
        rate = Double(words.count) / max(speech, 1)
        currentRate = Double(currentWords) / max(speech, 1)
        let shares = reader.chunkShares(of: words, for: candidate)
        confirmedChunks = shares.filter { $0 >= LexicalVote.minimumShare }.count
        chunks = shares.count
        share = words.isEmpty ? 0 : reader.shares(of: words).first { reader.same($0.key, candidate) }?.value ?? 0
    }

    var confirms: Bool {
        rate >= max(currentRate, Self.minimumRate) && confirmedChunks * 2 > chunks
    }

    /// "en-US writes 2.65 words/s against 1.74, 6 of 6 chunks read as en-US"
    var summary: String {
        let language = MeetingFormat.bcp47(candidate)
        return "\(language) writes \(Self.format(rate)) words/s against \(Self.format(currentRate)), "
            + "\(confirmedChunks) of \(chunks) chunks read as \(language)"
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
