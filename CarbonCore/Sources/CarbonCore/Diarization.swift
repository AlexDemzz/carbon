import Foundation

/// Who spoke when on one stream, as offline diarization found it.
/// Also the JSON the diarization helper process prints.
public struct Diarization: Equatable, Sendable, Codable {
    /// A stretch of the stream given to one cluster, in seconds from the start of the stream.
    public struct Segment: Equatable, Sendable, Codable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var cluster: String

        public init(start: TimeInterval, end: TimeInterval, cluster: String) {
            self.start = start
            self.end = end
            self.cluster = cluster
        }
    }

    /// One voice the diarizer found, and how much it spoke.
    public struct Cluster: Equatable, Sendable, Codable {
        public var id: String
        /// L2-normalized mean embedding of all its speech, crosstalk and clustering mistakes included.
        public var centroid: [Float]
        /// L2-normalized embedding of its clean speech only, what Voice Prints are matched and made from. Nil
        /// when that speech is too short or too mixed to tell one voice: the cluster is neither matched nor enrolled.
        public var voice: [Float]?
        public var speechSeconds: Double

        public init(id: String, centroid: [Float], voice: [Float]? = nil, speechSeconds: Double) {
            self.id = id
            self.centroid = centroid
            self.voice = voice
            self.speechSeconds = speechSeconds
        }
    }

    public var segments: [Segment]
    public var clusters: [Cluster]

    public init(segments: [Segment], clusters: [Cluster]) {
        self.segments = segments
        self.clusters = clusters
    }
}
