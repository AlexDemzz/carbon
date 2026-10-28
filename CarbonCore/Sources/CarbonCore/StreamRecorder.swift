@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// Takes one captured stream to the analyzer format, feeds it to its TranscriptionSession and appends it
/// to a CAF file, written to disk every `flushInterval` seconds of audio so a crash loses at most that much.
final class StreamRecorder: Sendable {
    static let flushInterval: TimeInterval = 5

    private struct State {
        var file: AVAudioFile
        var pending: AVAudioPCMBuffer
        var converter: AVAudioConverter?
        var error: (any Error)?
        var closed = false
    }

    private let session: any TranscriptionSession
    private let state: Mutex<State>

    init(session: any TranscriptionSession, cafFile url: URL) throws {
        let format = session.audioFormat
        let file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: format.commonFormat,
            interleaved: format.isInterleaved)
        let capacity = AVAudioFrameCount(format.sampleRate * Self.flushInterval)
        guard let pending = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw CocoaError(.featureUnsupported)
        }
        self.session = session
        state = Mutex(State(file: file, pending: pending))
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLock { state in
            guard !state.closed, state.error == nil else { return }
            do {
                let converted = try Self.convert(buffer, to: session.audioFormat, with: &state.converter)
                session.append(converted)
                try Self.enqueue(converted, into: &state)
            } catch {
                state.error = error
            }
        }
    }

    /// Writes what is left and closes the file. Throws the first error met while recording.
    func close() throws {
        try state.withLock { state in
            guard !state.closed else { return }
            state.closed = true
            if state.error == nil {
                do { try Self.flush(&state) } catch { state.error = error }
            }
            if let error = state.error { throw error }
        }
    }

    static func convert(
        _ buffer: AVAudioPCMBuffer, to format: AVAudioFormat, with converter: inout AVAudioConverter?
    ) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { throw CocoaError(.featureUnsupported) }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw CocoaError(.featureUnsupported)
        }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return output
    }

    private static func enqueue(_ buffer: AVAudioPCMBuffer, into state: inout State) throws {
        var offset: AVAudioFrameCount = 0
        while offset < buffer.frameLength {
            let room = state.pending.frameCapacity - state.pending.frameLength
            let count = min(room, buffer.frameLength - offset)
            copy(count, framesFrom: buffer, at: offset, to: state.pending)
            offset += count
            if state.pending.frameLength == state.pending.frameCapacity {
                try flush(&state)
            }
        }
    }

    private static func flush(_ state: inout State) throws {
        guard state.pending.frameLength > 0 else { return }
        try state.file.write(from: state.pending)
        state.pending.frameLength = 0
    }

    private static func copy(
        _ count: AVAudioFrameCount, framesFrom source: AVAudioPCMBuffer, at offset: AVAudioFrameCount,
        to destination: AVAudioPCMBuffer
    ) {
        let bytesPerFrame = Int(source.format.streamDescription.pointee.mBytesPerFrame)
        let sources = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinations = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        for (from, to) in zip(sources, destinations) {
            memcpy(
                to.mData! + Int(destination.frameLength) * bytesPerFrame,
                from.mData! + Int(offset) * bytesPerFrame,
                Int(count) * bytesPerFrame)
        }
        destination.frameLength += count
    }
}
