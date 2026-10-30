@preconcurrency import AVFoundation
import Foundation
import Synchronization
import Testing

@testable import CarbonCore

struct StreamRecorderTests {
    /// What a session was handed, in order: "<ms> ms" per buffer heard, "skip <ms> ms" per skip.
    final class LoggingSession: TranscriptionSession {
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        private let events = Mutex<[String]>([])

        var log: [String] { events.withLock { $0 } }

        func append(_ buffer: AVAudioPCMBuffer) {
            events.withLock { $0.append("\(Int(buffer.frameLength) / 16) ms") }
        }

        func skip(_ duration: TimeInterval) {
            events.withLock { $0.append("skip \(Int((duration * 1_000).rounded())) ms") }
        }

        func finish() async throws -> [TranscribedWord] { [] }
    }

    /// 10 ms of audio, as a process tap delivers it, already in the session's format: a tone, or zeros.
    func tapBuffer(sound: Bool, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        for frame in 0..<160 {
            buffer.int16ChannelData![0][frame] = sound ? Int16(6_000 * sin(Double(frame) * 2 * .pi * 440 / 16_000)) : 0
        }
        return buffer
    }

    func record(_ pattern: [(sound: Bool, seconds: Double)]) throws -> [String] {
        let session = LoggingSession()
        let file = FileManager.default.temporaryDirectory.appending(path: "stream-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: file) }
        let recorder = try StreamRecorder(session: session, cafFile: file)
        for (sound, seconds) in pattern {
            for _ in 0..<Int((seconds * 100).rounded()) { recorder.append(tapBuffer(sound: sound, format: session.audioFormat)) }
        }
        try recorder.close()
        #expect(try AVAudioFile(forReading: file).length == AVAudioFramePosition(pattern.map(\.seconds).reduce(0, +) * 16_000))
        return session.log
    }

    @Test func theSessionHearsATapsTenMillisecondBuffersAHundredMillisecondsAtATime() throws {
        let log = try record([(sound: true, seconds: 0.35)])

        #expect(log == ["100 ms", "100 ms", "100 ms", "50 ms"])
    }

    @Test func digitalSilencePastOneSecondIsSkippedAndTheFileKeepsIt() throws {
        let log = try record([(sound: true, seconds: 0.2), (sound: false, seconds: 1.5), (sound: true, seconds: 0.1)])

        #expect(log == ["100 ms", "100 ms"] + Array(repeating: "100 ms", count: 10) + Array(repeating: "skip 100 ms", count: 5) + ["100 ms"])
    }

    @Test func aStreamOfZerosOnlyCostsTheSessionItsFirstSecond() throws {
        let log = try record([(sound: false, seconds: 3)])

        #expect(log.filter { !$0.hasPrefix("skip") }.count == 10)
        #expect(log.count == 30)
    }

    @Test func onlyZerosAreDigitalSilenceNotAQuietRoom() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        #expect(SoundLevel.isDigitalSilence(buffer))
        // A quiet room through a microphone, about −60 dBFS.
        for frame in 0..<4_800 { buffer.floatChannelData![0][frame] = frame.isMultiple(of: 2) ? 0.001 : -0.001 }
        #expect(!SoundLevel.isDigitalSilence(buffer))
    }
}
