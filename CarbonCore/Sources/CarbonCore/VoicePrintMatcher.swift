import Foundation

/// Finds which of this Meeting's clusters are voices Carbon remembers. It never names a voice it is unsure about.
public enum VoicePrintMatcher {
    /// Shorter clusters are neither matched nor enrolled.
    public static let minimumSpeechSeconds = 10.0
    static let maximumDistance = 0.30
    static let minimumMargin = 0.10

    /// A cluster's best distance to a Voice Print, and that print when the distance is a confident match.
    public struct Match: Equatable, Sendable {
        public var printID: UUID?
        /// Cosine distance, rounded to 3 decimals: what the diagnostic log and `meetings.json` record.
        public var distance: Double

        public init(printID: UUID?, distance: Double) {
            self.printID = printID
            self.distance = distance
        }
    }

    /// Keyed by cluster id. A cluster appears when it has enough speech, a clean voice, and at least one print of
    /// `model` exists.
    /// The owner's print is compared only with `ownerCandidates`, the clusters heard on the mic (nil: every cluster).
    public static func match(
        _ clusters: [Diarization.Cluster], prints: [VoicePrint], model: String, ownerCandidates: Set<String>? = nil
    ) -> [String: Match] {
        let prints = prints.filter { $0.model == model }
        var best: [String: (print: UUID, distance: Double)] = [:]
        var candidates: [(cluster: String, print: UUID, distance: Double)] = []
        for cluster in clusters where cluster.speechSeconds >= minimumSpeechSeconds {
            guard let voice = cluster.voice else { continue }
            let ranked = prints
                .filter { !$0.owner || ownerCandidates?.contains(cluster.id) ?? true }
                .map { (print: $0.id, distance: cosineDistance(voice, $0.centroid)) }
                .sorted { $0.distance < $1.distance }
            guard let first = ranked.first else { continue }
            best[cluster.id] = first
            let margin = ranked.count > 1 ? ranked[1].distance - first.distance : .infinity
            if first.distance < maximumDistance, margin >= minimumMargin {
                candidates.append((cluster.id, first.print, first.distance))
            }
        }
        var taken: Set<UUID> = []
        var matched: [String: UUID] = [:]
        for candidate in candidates.sorted(by: { $0.distance < $1.distance }) where !taken.contains(candidate.print) {
            taken.insert(candidate.print)
            matched[candidate.cluster] = candidate.print
        }
        var matches: [String: Match] = [:]
        for (cluster, first) in best {
            matches[cluster] = Match(printID: matched[cluster], distance: rounded(first.distance))
        }
        return matches
    }

    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count else { return .infinity }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for (x, y) in zip(a, b) {
            dot += Double(x) * Double(y)
            normA += Double(x) * Double(x)
            normB += Double(y) * Double(y)
        }
        guard normA > 0, normB > 0 else { return .infinity }
        return 1 - dot / (normA.squareRoot() * normB.squareRoot())
    }

    private static func rounded(_ distance: Double) -> Double {
        (distance * 1000).rounded() / 1000
    }
}
