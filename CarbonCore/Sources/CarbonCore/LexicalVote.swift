import Foundation

/// Which language a stream's transcript reads as, one chunk of `TextLanguage.chunkWords` final words at a time. A
/// chunk counts for a language when its share passes `minimumShare`; the vote calls for another language than the
/// current one when `agreeing` of the last `window` chunks count for it. Franglais and loanwords don't sway it: on two
/// French Meetings, not one chunk read as English (docs/research/text-vs-acoustic-language-identification.md).
public struct LexicalVote: Sendable {
    public static let minimumShare = 0.9
    public static let window = 4
    public static let agreeing = 3

    private let current: String
    /// The language each of the last chunks counted for, by BCP 47 identifier; nil when it counted for none.
    private var recent: [(id: String, locale: Locale)?] = []

    public init(current: Locale) {
        self.current = MeetingFormat.bcp47(current)
    }

    /// Adds one chunk's share per candidate language. Returns the language it calls for, if any.
    public mutating func add(_ shares: [Locale: Double]) -> Locale? {
        let top = shares.max { $0.value < $1.value }
        recent.append(top.flatMap { $0.value >= Self.minimumShare ? (MeetingFormat.bcp47($0.key), $0.key) : nil })
        if recent.count > Self.window { recent.removeFirst() }
        let others = recent.compactMap { $0 }.filter { $0.id != current }
        return others.first { language in others.filter { $0.id == language.id }.count >= Self.agreeing }?.locale
    }

    /// Forgets every chunk: the next call needs `agreeing` new ones.
    public mutating func reset() {
        recent = []
    }
}
