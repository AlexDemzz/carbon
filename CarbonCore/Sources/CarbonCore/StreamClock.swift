import Foundation

/// Where a TranscriptionSession's stream is, in audio heard or skipped. A buffer heard right after a skip needs its
/// start time, so its words stay on the stream's clock.
public struct StreamClock: Sendable {
    public private(set) var position: TimeInterval = 0
    private var skipped = false

    public init() {}

    /// Moves past a buffer heard. Returns its start time when it follows a skip, nil when it follows the last buffer.
    public mutating func hear(_ duration: TimeInterval) -> TimeInterval? {
        defer {
            position += duration
            skipped = false
        }
        return skipped ? position : nil
    }

    public mutating func skip(_ duration: TimeInterval) {
        position += duration
        skipped = true
    }
}
