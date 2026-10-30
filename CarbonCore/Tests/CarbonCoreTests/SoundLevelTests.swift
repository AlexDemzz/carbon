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
}
