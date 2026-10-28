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

/// One entry of `IOPMCopyAssertionsByProcess()`, with its process resolved to its owning app.
public struct PowerAssertion: Equatable, Sendable {
    public var app: MeetingApp
    /// `AssertName`.
    public var name: String
    /// `AssertType`, as created: modern (`PreventUserIdleDisplaySleep`) or legacy (`NoDisplaySleepAssertion`).
    public var type: String
    /// `AssertionId`. A native call app creates a new one per call.
    public var id: Int

    public init(app: MeetingApp, name: String, type: String, id: Int) {
        self.app = app
        self.name = name
        self.type = type
        self.id = id
    }
}

/// What the microphone looked like at one moment: the apps holding it, each resolved to its owning app.
public struct MicSnapshot: Equatable, Sendable {
    public var time: Date
    public var micHolders: [MeetingApp]
    /// The power assertions, when they were polled at this snapshot (every 3 s at most); nil between polls.
    public var assertions: [PowerAssertion]?

    public init(time: Date, micHolders: [MeetingApp], assertions: [PowerAssertion]? = nil) {
        self.time = time
        self.micHolders = micHolders
        self.assertions = assertions
    }
}

/// Detection's signals, such as Core Audio's process list. Snapshots arrive at least once a second.
public protocol SignalSource: Sendable {
    func micSnapshots() -> AsyncStream<MicSnapshot>
}

/// Offline speaker diarization of a recorded Them stream, such as FluidAudio in a helper process.
public protocol Diarizer: Sendable {
    /// Diarizes the audio file. Each call starts afresh (a new process); cancelling the call must stop it.
    func diarize(_ audio: URL) async throws -> Diarization
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
