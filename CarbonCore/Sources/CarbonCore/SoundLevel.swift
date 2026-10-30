import Accelerate
@preconcurrency import AVFoundation

/// Tells sound from silence in a captured buffer. Full-rate zeros, as a tap delivers when nothing plays, are silence.
enum SoundLevel {
    /// RMS of −50 dBFS: above a quiet room's noise floor, below speech. Tuned by dogfooding.
    static let threshold: Float = 0.003_16

    static func isSound(_ buffer: AVAudioPCMBuffer) -> Bool {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return false }
        var sum: Float = 0
        var count = 0
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<frames {
                    let sample = channels[channel][frame * buffer.stride]
                    sum += sample * sample
                }
                count += frames
            }
        } else if let channels = buffer.int16ChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<frames {
                    let sample = Float(channels[channel][frame * buffer.stride]) / Float(Int16.max)
                    sum += sample * sample
                }
                count += frames
            }
        }
        guard count > 0 else { return false }
        return (sum / Float(count)).squareRoot() > threshold
    }

    /// Peak under −80 dBFS: the zeros a tap delivers while nothing plays, or a muted input, never a microphone's room.
    static func isDigitalSilence(_ buffer: AVAudioPCMBuffer) -> Bool {
        let frames = Int(buffer.frameLength)
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                var peak: Float = 0
                vDSP_maxmgv(channels[channel], buffer.stride, &peak, vDSP_Length(frames))
                if peak >= 0.000_1 { return false }
            }
            return true
        }
        if let channels = buffer.int16ChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<frames where abs(Int(channels[channel][frame * buffer.stride])) > 3 { return false }
            }
            return true
        }
        return false
    }
}
