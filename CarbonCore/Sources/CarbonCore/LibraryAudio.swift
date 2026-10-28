@preconcurrency import AVFoundation
import Foundation

extension Library {
    nonisolated static let keptAudioBitRate = 64_000

    /// Keep audio: encodes the Meeting's two streams to one stereo AAC `.m4a` next to its Markdown file,
    /// Me on the left and Them on the right, and records its path in `meetings.json` `audio`.
    func keepAudio(_ id: UUID, me: URL, them: URL) async throws {
        guard let entry = try loadIndex().meetings.first(where: { $0.id == id }) else {
            throw LibraryError.unknownMeeting(id)
        }
        let path = (entry.file as NSString).deletingPathExtension + ".m4a"
        let destination = folder.appending(path: path)
        try await Task.detached { try Self.encodeStereo(left: me, right: them, to: destination) }.value
        try writeSurgically(id, updating: { $0.audio = path }) { _ in nil }
    }

    private nonisolated static func encodeStereo(left: URL, right: URL, to destination: URL) throws {
        let inputs = [left, right].map { try? AVAudioFile(forReading: $0) }
        guard let sampleRate = inputs.compactMap(\.self).first?.processingFormat.sampleRate,
              let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { throw CocoaError(.fileReadCorruptFile) }
        let output = try AVAudioFile(
            forWriting: destination,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: keptAudioBitRate,
            ],
            commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = AVAudioFrameCount(sampleRate)
        var converters: [AVAudioConverter?] = [nil, nil]
        while true {
            guard let frame = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: chunk) else {
                throw CocoaError(.featureUnsupported)
            }
            // A stream that ended early is silence on its side.
            for channel in 0..<2 {
                memset(frame.floatChannelData![channel], 0, Int(chunk) * MemoryLayout<Float>.size)
            }
            for (channel, input) in inputs.enumerated() {
                guard let input, input.framePosition < input.length,
                      let read = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: chunk)
                else { continue }
                try input.read(into: read)
                let samples = try StreamRecorder.convert(read, to: mono, with: &converters[channel])
                let count = min(samples.frameLength, chunk)
                memcpy(frame.floatChannelData![channel], samples.floatChannelData![0], Int(count) * MemoryLayout<Float>.size)
                frame.frameLength = max(frame.frameLength, count)
            }
            guard frame.frameLength > 0 else { break }
            try output.write(from: frame)
        }
    }
}
