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

    func start(locale: Locale, stream: AudioStream) async throws -> any TranscriptionSession {
        heard.withLock { $0.append(locale) }
        return Session(words: words[stream] ?? [])
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

        func finish() async throws -> [TranscribedWord] {
            words
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
