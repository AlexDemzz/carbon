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

/// Stands in for SpeechTranscriber: hears audio in the analyzer format and replays recorded final words.
final class ReplayTranscriber: Transcriber {
    let words: [TranscribedWord]
    private let heard = Mutex<[Locale]>([])

    init(words: [TranscribedWord]) {
        self.words = words
    }

    /// Replays the words of a fixture recorded in the transcription-eval prototype's `{w, s, e}` shape.
    convenience init(fixture name: String) throws {
        struct Recorded: Decodable {
            let w: String
            let s: Double
            let e: Double
        }
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        let recorded = try JSONDecoder().decode([Recorded].self, from: Data(contentsOf: url))
        self.init(words: recorded.map { TranscribedWord(text: $0.w, start: $0.s, end: $0.e) })
    }

    var localesHeard: [Locale] { heard.withLock { $0 } }

    func start(locale: Locale) async throws -> any TranscriptionSession {
        heard.withLock { $0.append(locale) }
        return Session(words: words)
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
