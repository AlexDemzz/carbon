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
public enum AudioStream: String, Hashable, Sendable, Codable {
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
    /// The calendar events around `time`, reduced to plain values.
    public var events: [CalendarEvent]
    /// The power assertions, when they were polled at this snapshot (every 3 s at most); nil between polls.
    public var assertions: [PowerAssertion]?

    public init(
        time: Date, micHolders: [MeetingApp], events: [CalendarEvent] = [], assertions: [PowerAssertion]? = nil
    ) {
        self.time = time
        self.micHolders = micHolders
        self.events = events
        self.assertions = assertions
    }
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

/// Detection's signals, such as Core Audio's process list. Snapshots arrive at least once a second.
public protocol SignalSource: Sendable {
    func micSnapshots() -> AsyncStream<MicSnapshot>
}

/// Where the Meeting's sound plays. Headphones keep the call out of the mic, so the mic hears only the person;
/// `speakers` is the Mac's speakers, or any output not known to be headphones, where the mic may be shared.
public enum OutputRoute: Sendable, Equatable { case headphones, speakers }

/// Watches where sound plays, such as Core Audio's output devices.
public protocol OutputRouteSource: Sendable {
    /// The route now, then each settled change, until the stream is dropped.
    func routes() -> AsyncStream<OutputRoute>
}

/// Offline speaker diarization of one recorded stream, such as FluidAudio in a helper process.
public protocol Diarizer: Sendable {
    /// Diarizes the audio file. Each call starts afresh (a new process); cancelling the call must stop it.
    func diarize(_ audio: URL) async throws -> Diarization
}

/// Spoken language identification of a window of speech, such as SpeechBrain's VoxLingua107 classifier in Core ML.
public protocol SpokenLanguageClassifier: Sendable {
    /// The languages it scores, by VoxLingua107 label, such as "en" or "fr".
    var labels: Set<String> { get }
    /// Each label's log-probability for a window of 16 kHz mono speech. Loads the model on first use.
    func classify(_ speech: [Float]) async throws -> [String: Double]
    /// Lets the model go until the next `classify`.
    func release() async
}

/// Voice activity detection on 16 kHz mono audio, such as Silero VAD in Core ML: tells speech from silence, music
/// and noise.
public protocol SpeechGate: Sendable {
    /// The samples of each chunk it judges.
    var chunkSize: Int { get }
    /// The probability that `chunk` is speech, given the chunks of `stream` before it: each stream is judged on its
    /// own. Loads the model on first use.
    func speechProbability(of chunk: [Float], on stream: AudioStream) async throws -> Double
    /// Lets the model go and forgets every stream, until the next `speechProbability`.
    func release() async
}

/// A Meeting's recap: what was said and what comes next.
public struct Summary: Equatable, Sendable {
    public var keyPoints: [String]
    public var nextSteps: [String]

    public init(keyPoints: [String], nextSteps: [String]) {
        self.keyPoints = keyPoints
        self.nextSteps = nextSteps
    }
}

/// Summarizes a Meeting's Transcript once its file is on disk.
public protocol Summarizer: Sendable {
    /// `transcript` is the `## Transcript` section as written. Nil when summarizing is off.
    func summarize(transcript: String, language: Locale) async throws -> Summary?
}

/// v1's Summarizer: "On-device summary quality" dropped the Summary, so every Meeting keeps `summary: "off"`.
public struct NoSummarizer: Summarizer {
    public init() {}

    public func summarize(transcript: String, language: Locale) async throws -> Summary? { nil }
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
