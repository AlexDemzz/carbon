@preconcurrency import AVFoundation
import CarbonCore
import Foundation
import Synchronization
import Testing

/// Plays a synthetic microphone signal: `seconds` of a 440 Hz tone, in 100 ms buffers, as soon as capture starts.
final class FakeAudioSource: AudioSource {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let seconds: Double

    init(seconds: Double) {
        self.seconds = seconds
    }

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let chunk = AVAudioFrameCount(format.sampleRate / 10)
        var remaining = AVAudioFrameCount(seconds * format.sampleRate)
        var phase = 0.0
        while remaining > 0 {
            let frames = min(chunk, remaining)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            let samples = buffer.floatChannelData![0]
            for index in 0..<Int(frames) {
                samples[index] = Float(sin(phase) * 0.2)
                phase += 2 * .pi * 440 / format.sampleRate
            }
            onBuffer(buffer)
            remaining -= frames
        }
    }

    func stop() {}
}

/// Captures nothing and notes whether capture was stopped.
final class StopSpyAudioSource: AudioSource {
    private let isStopped = Mutex(false)
    var stopped: Bool { isStopped.withLock { $0 } }

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {}

    func stop() {
        isStopped.withLock { $0 = true }
    }
}

/// Pushes one buffer at 1 Hz, which no converter turns into the analyzer format, so its stream fails to close.
final class UnconvertibleAudioSource: AudioSource {
    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat64, sampleRate: 1, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        buffer.frameLength = 4
        onBuffer(buffer)
    }

    func stop() {}
}

/// Plays a WAV fixture as one captured stream, in 100 ms buffers, as soon as capture starts.
final class WAVAudioSource: AudioSource {
    let url: URL

    init(fixture name: String) throws {
        url = try fixtureURL(name, extension: "wav")
    }

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let file = try AVAudioFile(forReading: url)
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
            try file.read(into: buffer)
            onBuffer(buffer)
        }
    }

    func stop() {}
}

/// Stands in for SpeechTranscriber: hears audio in the analyzer format and replays recorded final words per stream.
final class ReplayTranscriber: Transcriber {
    let words: [AudioStream: [TranscribedWord]]
    private let heard = Mutex<[Locale]>([])

    init(words: [AudioStream: [TranscribedWord]]) {
        self.words = words
    }

    /// Replays word fixtures recorded in the transcription-eval prototype's `{w, s, e}` shape.
    convenience init(me: String, them: String? = nil) throws {
        self.init(words: [
            .me: try CarbonCoreTests.words(fixture: me),
            .them: try them.map { try CarbonCoreTests.words(fixture: $0) } ?? [],
        ])
    }

    var localesHeard: [Locale] { heard.withLock { $0 } }
    /// Seconds of audio each stream's sessions were fed, in the analyzer format.
    var secondsHeard: [AudioStream: Double] { sessions.withLock { $0.mapValues { $0.seconds } } }
    private let sessions = Mutex<[AudioStream: Session]>([:])

    func start(locale: Locale, stream: AudioStream) async throws -> any TranscriptionSession {
        heard.withLock { $0.append(locale) }
        let session = Session(words: words[stream] ?? [])
        sessions.withLock { $0[stream] = session }
        return session
    }

    final class Session: TranscriptionSession {
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        let words: [TranscribedWord]
        private let frames = Mutex<AVAudioFramePosition>(0)

        init(words: [TranscribedWord]) {
            self.words = words
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            precondition(buffer.format == audioFormat, "the transcriber only accepts its analyzer format")
            frames.withLock { $0 += AVAudioFramePosition(buffer.frameLength) }
        }

        var seconds: Double { Double(frames.withLock { $0 }) / audioFormat.sampleRate }

        func finish() async throws -> [TranscribedWord] {
            words
        }
    }
}

/// Stands in for the diarization helper process: each call plays the next scripted outcome.
final class ScriptedDiarizer: Diarizer {
    enum Outcome: Sendable {
        /// Returns recorded FluidAudio segments and embeddings.
        case replay(Diarization)
        case fail
        /// Never answers until cancelled, like a stalled CoreML prediction.
        case hang
    }

    struct Failed: Error {}

    private let outcomes: Mutex<[Outcome]>
    private let heard = Mutex<[URL]>([])

    init(_ outcomes: [Outcome]) {
        self.outcomes = Mutex(outcomes)
    }

    var audioHeard: [URL] { heard.withLock { $0 } }

    func diarize(_ audio: URL) async throws -> Diarization {
        heard.withLock { $0.append(audio) }
        let outcome = outcomes.withLock { $0.isEmpty ? .fail : $0.removeFirst() }
        switch outcome {
        case .replay(let diarization):
            return diarization
        case .fail:
            throw Failed()
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw Failed()
        }
    }
}

/// A clock the test moves by hand.
final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ start: Date) {
        current = Mutex(start)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 += seconds }
    }

    func set(_ date: Date) {
        current.withLock { $0 = date }
    }
}

/// A fresh folder under the system temporary directory, removed when the value is released.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "CarbonCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func date(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

func fixtureURL(_ name: String, extension ext: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
}

/// Words recorded in the transcription-eval prototype's `{w, s, e}` shape.
func words(fixture name: String) throws -> [TranscribedWord] {
    struct Recorded: Decodable {
        let w: String
        let s: Double
        let e: Double
    }
    let recorded = try JSONDecoder().decode([Recorded].self, from: Data(contentsOf: fixtureURL(name, extension: "json")))
    return recorded.map { TranscribedWord(text: $0.w, start: $0.s, end: $0.e) }
}

/// A Summarizer that writes nothing, like v1's no-op, or throws. It notes what each call got and what was on disk then.
final class SpySummarizer: Summarizer {
    struct Call: Equatable {
        var transcript: String
        var language: Locale
        var fileWasOnDisk: Bool
    }

    struct Failed: Error {}

    private let fails: Bool
    private let file: URL
    private let heard = Mutex<[Call]>([])

    /// `file` is where the Meeting's Markdown file is expected once the Transcript is final.
    init(file: URL, fails: Bool = false) {
        self.file = file
        self.fails = fails
    }

    var calls: [Call] { heard.withLock { $0 } }

    func summarize(transcript: String, language: Locale) async throws -> Summary? {
        let onDisk = FileManager.default.fileExists(atPath: file.path)
        heard.withLock { $0.append(Call(transcript: transcript, language: language, fileWasOnDisk: onDisk)) }
        if fails { throw Failed() }
        return nil
    }
}
