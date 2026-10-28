@preconcurrency import AVFoundation
import Foundation

/// One final word from a Transcriber, timed in seconds from the start of its stream.
public struct TranscribedWord: Equatable, Sendable, Codable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A live audio stream, such as the microphone (the Me stream).
public protocol AudioSource: Sendable {
    /// Starts capture. `onBuffer` receives every captured buffer in order, on any thread.
    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

/// Speech-to-text for one stream, such as SpeechTranscriber.
public protocol Transcriber: Sendable {
    func start(locale: Locale) async throws -> any TranscriptionSession
}

/// One stream being transcribed live.
public protocol TranscriptionSession: AnyObject, Sendable {
    /// The format `append` expects (the analyzer format).
    var audioFormat: AVAudioFormat { get }
    /// Feeds audio already converted to `audioFormat`. Called in order, from one thread at a time.
    func append(_ buffer: AVAudioPCMBuffer)
    /// Ends the input and returns every final word of the stream.
    func finish() async throws -> [TranscribedWord]
}
