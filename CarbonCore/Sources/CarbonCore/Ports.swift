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

/// The two streams of a Meeting: the microphone (Me) and the call's audio (Them).
public enum AudioStream: Hashable, Sendable {
    case me
    case them
}

/// The System Audio Recording permission, as `TCCAccessPreflight` reports it. Never inferred from audio.
public enum SystemAudioPermission: Sendable {
    case granted
    case denied
    case notDetermined
    /// The private preflight could not be loaded.
    case unknown
}

/// A live audio stream, such as the microphone (Me) or a system audio tap (Them).
public protocol AudioSource: Sendable {
    /// Starts capture. `onBuffer` receives every captured buffer in order, on any thread.
    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

/// Speech-to-text for one stream, such as SpeechTranscriber.
public protocol Transcriber: Sendable {
    func start(locale: Locale, stream: AudioStream) async throws -> any TranscriptionSession
}

/// What the microphone looked like at one moment: the apps holding it, each resolved to its owning app.
public struct MicSnapshot: Equatable, Sendable {
    public var time: Date
    public var micHolders: [MeetingApp]

    public init(time: Date, micHolders: [MeetingApp]) {
        self.time = time
        self.micHolders = micHolders
    }
}

/// Detection's signals, such as Core Audio's process list. Snapshots arrive at least once a second.
public protocol SignalSource: Sendable {
    func micSnapshots() -> AsyncStream<MicSnapshot>
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
