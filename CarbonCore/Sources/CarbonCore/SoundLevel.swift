import Accelerate
@preconcurrency import AVFoundation
import Synchronization

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

/// Turns the mic's buffers into meter levels every 100 ms of audio, whatever size the buffers come in: the loudest
/// level heard in each window. The meter then moves at the same pace on every input device.
final class MeterWindow: Sendable {
    private let window = Mutex<(frames: Int, loudest: Float)>((0, 0))

    /// The window's level once `frames` complete it, nil until then.
    func add(_ level: Float, frames: Int, sampleRate: Double) -> Float? {
        window.withLock { window in
            window.frames += frames
            window.loudest = max(window.loudest, level)
            guard Double(window.frames) >= sampleRate / 10 else { return nil }
            defer { window = (0, 0) }
            return window.loudest
        }
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
