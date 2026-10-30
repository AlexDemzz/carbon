import Foundation

/// Which of the checked Meeting Languages a Meeting is spoken in, from a spoken language classifier's scores of its
/// speech windows. Each window's scores are restricted to the candidates and renormalized, then weighed by the
/// window's speech into one score per candidate; a window the candidates barely score is not their speech and is
/// left out. The vote decides once at least `minimumSpeech` seconds were heard and the leader's lead passes
/// `minimumMargin`, and gives up after `maximumSpeech` seconds or `maximumWindows` windows.
public struct LanguageVote: Sendable {
    public enum Outcome: Equatable, Sendable {
        case undecided
        case decided(Locale)
        case gaveUp
    }

    /// Untuned: the research note's "about 8–10 s of speech", to be calibrated on recorded Meetings.
    public static let minimumSpeech: TimeInterval = 8
    public static let maximumSpeech: TimeInterval = 60
    /// The leader's mean lead over the runner-up, in log-probability per second of speech: ln 20, odds of 20 to 1.
    /// Untuned, like `minimumSpeech`.
    public static let minimumMargin = log(20.0)
    /// The least the candidates together must score, over all the classifier's labels, for a window to count: only
    /// windows the classifier is sure are another language. It is no test of speech, the speech gate is: no window
    /// of 80 min of music passed it. Accented speech scatters over unrelated labels, so French-accented English
    /// scored 0.005–0.24 for English and French together, yet led French in 8 of 9 windows
    /// (docs/research/language-identification-thresholds.md).
    public static let minimumCandidateProbability = 0.001
    /// The windows scored, counted or not, after which the vote gives up: a Meeting in a language that wasn't
    /// checked is never decided, and must not be scored for its whole length.
    public static let maximumWindows = 40

    /// The candidates the classifier can tell apart: the first locale of each label, in candidate order.
    private let candidates: [(label: String, locale: Locale)]
    private var scores: [String: Double]
    private var speech: TimeInterval = 0
    private var windows = 0

    /// Nil when fewer than two candidates have a label among `labels`: there is nothing to tell apart. Candidates
    /// sharing a label count once, as the first of them.
    public init?(candidates: [Locale], labels: Set<String>) {
        var kept: [(label: String, locale: Locale)] = []
        for locale in candidates {
            guard let label = Self.label(of: locale), labels.contains(label), !kept.contains(where: { $0.label == label })
            else { continue }
            kept.append((label, locale))
        }
        guard kept.count > 1 else { return nil }
        self.candidates = kept
        scores = Dictionary(uniqueKeysWithValues: kept.map { ($0.label, 0) })
    }

    /// Adds one window's log-probabilities, by label, for `speech` seconds of speech.
    public mutating func add(_ logProbabilities: [String: Double], speech seconds: TimeInterval) -> Outcome {
        let restricted = candidates.map { logProbabilities[$0.label] ?? -.infinity }
        let total = Self.logSumExp(restricted)
        windows += 1
        // Not speech in any candidate language: it neither scores nor counts as speech.
        guard exp(total) >= Self.minimumCandidateProbability else { return outcome }
        for (candidate, score) in zip(candidates, restricted) {
            scores[candidate.label, default: 0] += seconds * max(score - total, Self.floor)
        }
        speech += seconds
        return outcome
    }

    /// "en-US leads fr-FR by 1.2 per s over 12 s of speech, 5 windows": where an undecided vote stands.
    public var standing: String {
        let ranked = candidates.sorted { scores[$0.label]! > scores[$1.label]! }
        let lead = speech > 0 ? (scores[ranked[0].label]! - scores[ranked[1].label]!) / speech : 0
        return "\(ranked[0].locale.identifier(.bcp47)) leads \(ranked[1].locale.identifier(.bcp47)) by "
            + "\(lead.formatted(.number.precision(.fractionLength(1)))) per s over \(Int(speech)) s of speech, "
            + "\(windows) windows"
    }

    public var outcome: Outcome {
        if speech >= Self.minimumSpeech {
            let ranked = candidates.sorted { scores[$0.label]! > scores[$1.label]! }
            if (scores[ranked[0].label]! - scores[ranked[1].label]!) / speech >= Self.minimumMargin {
                return .decided(ranked[0].locale)
            }
        }
        return speech >= Self.maximumSpeech || windows >= Self.maximumWindows ? .gaveUp : .undecided
    }

    /// The lowest log-probability a window gives a candidate, so one window the classifier is sure of can't
    /// outweigh many: about 1 in 22,000.
    private static let floor = -10.0

    /// VoxLingua107's label for a locale's language: its language code, or the legacy code VoxLingua107 kept.
    public static func label(of locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier else { return nil }
        return legacyCodes[code] ?? code
    }

    private static let legacyCodes = ["he": "iw", "jv": "jw", "nb": "no"]

    private static func logSumExp(_ values: [Double]) -> Double {
        guard let top = values.max(), top > -.infinity else { return -.infinity }
        return top + log(values.reduce(0) { $0 + exp($1 - top) })
    }
}
