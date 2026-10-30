@preconcurrency import AVFoundation
import Testing

@testable import CarbonCore

struct SoundLevelTests {
    @Test func theMeterRunsFromTheSilenceThresholdToMinusTenDecibels() {
        #expect(SoundLevel.meter(rms: 0) == 0)
        #expect(SoundLevel.meter(rms: 0.002) == 0)
        #expect(abs(SoundLevel.meter(rms: 0.031_6) - 0.5) < 0.01)
        #expect(SoundLevel.meter(rms: 0.8) == 1)
    }

    @Test func theRMSAveragesThePowerOfEveryChannel() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        for frame in 0..<1_600 {
            buffer.floatChannelData![0][frame] = frame.isMultiple(of: 2) ? 0.3 : -0.3
            buffer.floatChannelData![1][frame] = 0.4
        }
        #expect(abs(SoundLevel.rms(buffer) - 0.353_6) < 0.001)
    }

    @Test func theMeterTakesTheLoudestLevelOfEach100msWhateverTheBufferSize() {
        let small = MeterWindow()
        #expect(small.add(0.2, frames: 1_200, sampleRate: 48_000) == nil)
        #expect(small.add(0.7, frames: 1_200, sampleRate: 48_000) == nil)
        #expect(small.add(0.1, frames: 1_200, sampleRate: 48_000) == nil)
        #expect(small.add(0.3, frames: 1_200, sampleRate: 48_000) == 0.7)
        #expect(small.add(0.4, frames: 1_200, sampleRate: 48_000) == nil)

        let large = MeterWindow()
        #expect(large.add(0.5, frames: 4_800, sampleRate: 48_000) == 0.5)
        #expect(large.add(0, frames: 4_800, sampleRate: 48_000) == 0)
    }
}
