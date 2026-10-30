import Accelerate
@preconcurrency import AVFoundation

/// Tells sound from silence in a captured buffer. Full-rate zeros, as a tap delivers when nothing plays, are silence.
enum SoundLevel {
    /// RMS of −50 dBFS: above a quiet room's noise floor, below speech. Tuned by dogfooding.
    static let threshold: Float = 0.003_16

    /// How loud an RMS is for a meter, from 0 at the silence threshold (−50 dBFS) to 1 at −10 dBFS.
    static func meter(rms: Float) -> Float {
        guard rms > threshold else { return 0 }
        return min(1, (20 * log10(rms) + 50) / 40)
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return 0 }
        var sum: Float = 0
        if let channels = buffer.floatChannelData {
            for channel in 0..<channelCount {
                var channelRMS: Float = 0
                vDSP_rmsqv(channels[channel], buffer.stride, &channelRMS, vDSP_Length(frames))
                sum += channelRMS * channelRMS
            }
        } else if let channels = buffer.int16ChannelData {
            for channel in 0..<channelCount {
                for frame in 0..<frames {
                    let sample = Float(channels[channel][frame * buffer.stride]) / Float(Int16.max)
                    sum += sample * sample / Float(frames)
                }
            }
        } else {
            return 0
        }
        return (sum / Float(channelCount)).squareRoot()
    }
}
