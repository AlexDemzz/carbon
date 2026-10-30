@preconcurrency import AVFoundation
import CarbonCore
import Foundation
import Testing

struct LogMelTests {
    struct Reference: Decodable {
        let frames: Int
        let mels: Int
        let features: [[Float]]
    }

    @Test func matchesTheReferenceFrontendOnAClipOfSpeech() throws {
        let file = try AVAudioFile(forReading: fixtureURL("ami-ES2004a-me-clip", extension: "wav"))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000))
        try file.read(into: buffer, frameCount: 16_000)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let reference = try JSONDecoder().decode(
            Reference.self, from: Data(contentsOf: fixtureURL("ami-ES2004a-me-fbank", extension: "json")))

        let features = LogMel.features(of: samples)

        #expect(features.count == reference.frames)
        #expect(features.allSatisfy { $0.count == reference.mels })
        let error = zip(features, reference.features).flatMap { zip($0, $1).map { abs($0 - $1) } }.max() ?? .infinity
        #expect(error < 0.001, "the largest difference, in dB")
    }
}
