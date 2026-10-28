import Foundation

/// The remembered signature of a named Speaker's voice, one entry of `voiceprints.json`.
public struct VoicePrint: Identifiable, Equatable, Sendable, Codable {
    /// The embedding model Carbon ships: prints made by another model are never compared.
    public static let currentModel = "fluidaudio/community-1@0.17.7"
    static let recentKept = 3

    public var id: UUID
    public var name: String
    /// From the attendee picked, when there was one.
    public var email: String?
    public var model: String
    /// L2-normalized.
    public var centroid: [Float]
    /// The latest embeddings that updated the print, newest last, at most 3.
    public var recent: [[Float]]
    /// How many Meetings the voice was heard in.
    public var meetings: Int
    public var createdAt: Date
    public var lastHeardAt: Date

    public init(
        id: UUID, name: String, email: String? = nil, model: String, centroid: [Float], recent: [[Float]] = [],
        meetings: Int = 1, createdAt: Date, lastHeardAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.model = model
        self.centroid = centroid
        self.recent = recent
        self.meetings = meetings
        self.createdAt = createdAt
        self.lastHeardAt = lastHeardAt ?? createdAt
    }

    /// Adds a newly heard embedding: the centroid becomes the normalized mean of itself and the recent ones.
    mutating func hear(_ embedding: [Float], at date: Date, isNewMeeting: Bool = true) {
        guard embedding.count == centroid.count else { return }
        recent = Array((recent + [embedding]).suffix(Self.recentKept))
        let vectors = [centroid] + recent
        let mean = (0..<centroid.count).map { dimension in vectors.reduce(0) { $0 + $1[dimension] } }
        centroid = Self.normalized(mean)
        if isNewMeeting { meetings += 1 }
        lastHeardAt = max(lastHeardAt, date)
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? vector.map { $0 / norm } : vector
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, email, model, centroid, recent, meetings, createdAt, lastHeardAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        model = try container.decode(String.self, forKey: .model)
        centroid = try Self.decodeEmbedding(container.decode(String.self, forKey: .centroid), at: .centroid, in: container)
        recent = try container.decode([String].self, forKey: .recent).map {
            try Self.decodeEmbedding($0, at: .recent, in: container)
        }
        meetings = try container.decode(Int.self, forKey: .meetings)
        createdAt = try Date(container.decode(String.self, forKey: .createdAt), strategy: .iso8601)
        lastHeardAt = try Date(container.decode(String.self, forKey: .lastHeardAt), strategy: .iso8601)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(model, forKey: .model)
        try container.encode(MeetingIndex.Speaker.encode(centroid: centroid), forKey: .centroid)
        try container.encode(recent.map(MeetingIndex.Speaker.encode(centroid:)), forKey: .recent)
        try container.encode(meetings, forKey: .meetings)
        try container.encode(createdAt.formatted(.iso8601), forKey: .createdAt)
        try container.encode(lastHeardAt.formatted(.iso8601), forKey: .lastHeardAt)
    }

    private static func decodeEmbedding(
        _ base64: String, at key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [Float] {
        guard let embedding = MeetingIndex.Speaker.decode(centroid: base64) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not base64 Float32s")
        }
        return embedding
    }
}

extension MeetingIndex.Speaker {
    /// Reads back an embedding written by `encode(centroid:)`.
    public static func decode(centroid base64: String) -> [Float]? {
        guard let data = Data(base64Encoded: base64), data.count % 4 == 0 else { return nil }
        return stride(from: 0, to: data.count, by: 4).map { offset in
            let bits = data[data.startIndex + offset..<data.startIndex + offset + 4]
                .enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
            return Float(bitPattern: bits)
        }
    }

    /// The cluster's embedding, when it has one.
    public var embedding: [Float]? {
        centroid.flatMap(Self.decode(centroid:))
    }
}
