import Foundation

/// Who spoke when on the Them stream, as offline diarization found it.
/// Also the JSON the diarization helper process prints.
public struct Diarization: Equatable, Sendable, Codable {
    /// A stretch of the Them stream given to one cluster, in seconds from the start of the stream.
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

    /// One voice the diarizer found: its L2-normalized centroid embedding and how much it spoke.
    public struct Cluster: Equatable, Sendable, Codable {
        public var id: String
        public var centroid: [Float]
        public var speechSeconds: Double

        public init(id: String, centroid: [Float], speechSeconds: Double) {
            self.id = id
            self.centroid = centroid
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
