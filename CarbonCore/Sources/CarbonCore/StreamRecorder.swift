@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// Takes one captured stream to the analyzer format, feeds it to its TranscriptionSession and appends it
/// to a CAF file, written to disk every `flushInterval` seconds of audio so a crash loses at most that much.
final class StreamRecorder: Sendable {
    static let flushInterval: TimeInterval = 5
    /// The session hears the stream in buffers of this much audio: a process tap delivers ~10 ms at a time, and each
    /// buffer handed to SpeechAnalyzer wakes it and its speech service.
    static let feedInterval: TimeInterval = 0.1
    /// Digital silence, such as a tap's zeros while the call plays nothing, costs the speech service as much as speech.
    /// Past this much of it after the last sound, the session skips it instead of hearing it.
    static let silenceHeard: TimeInterval = 1

    private struct State {
        var file: AVAudioFile
        var pending: AVAudioPCMBuffer
        var converter: AVAudioConverter?
        var session: any TranscriptionSession
        /// Audio not yet handed to the session, in the file's format, until it holds `feedInterval`.
        var feeding: AVAudioPCMBuffer?
        /// The frames of digital silence handed to the session since the last sound.
        var silenceFed: AVAudioFramePosition = 0
        /// Converts the file's format to the session's, for a session that wants another one.
        var sessionConverter: AVAudioConverter?
        /// While a new session catches up on the file, the audio that arrives meanwhile, in the file's format.
        var backlog: [AVAudioPCMBuffer]?
        var error: (any Error)?
        var closed = false
    }

    private let url: URL
    private let fileFormat: AVAudioFormat
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
        self.url = url
        fileFormat = format
        state = Mutex(State(file: file, pending: pending, session: session))
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLock { state in
            guard !state.closed, state.error == nil else { return }
            do {
                let converted = try Self.convert(buffer, to: fileFormat, with: &state.converter)
                if state.backlog != nil {
                    state.backlog?.append(try Self.copy(converted))
                } else {
                    try Self.batch(converted, into: &state)
                }
                try Self.enqueue(converted, into: &state)
            } catch {
                state.error = error
            }
        }
    }

    /// Hands the stream to `session` from now on. It first hears everything recorded so far, read back from the
    /// file, then the audio that arrived meanwhile, then the live audio: no gap. Returns the session it replaces.
    /// On failure the old session keeps the stream. Reads the whole file, so keep it off the main actor.
    func hand(to session: any TranscriptionSession) throws -> any TranscriptionSession {
        let (old, recorded) = try state.withLock { state in
            if state.closed { throw CocoaError(.fileWriteUnknown) }
            if let error = state.error { throw error }
            try Self.flush(&state)
            try Self.feedBatch(&state)
            let old = state.session
            state.session = session
            state.sessionConverter = nil
            state.silenceFed = 0
            state.backlog = []
            return (old, state.file.length)
        }
        do {
            try replay(recorded, to: session)
        } catch {
            state.withLock { state in
                state.session = old
                state.sessionConverter = nil
                Self.drainBacklog(&state)
            }
            throw error
        }
        state.withLock { Self.drainBacklog(&$0) }
        return old
    }

    /// Hands the stream back to a session that heard it before, without replaying anything.
    func giveBack(_ session: any TranscriptionSession) {
        state.withLock { state in
            state.session = session
            state.sessionConverter = nil
        }
    }

    /// Has `session` hear the stretch of the stream recorded between `range`'s bounds, in seconds, on the stream's
    /// clock: it skips to the stretch's start first. Reads the file, so keep it off the main actor.
    func replay(_ range: ClosedRange<TimeInterval>, to session: any TranscriptionSession) throws {
        let recorded = try flushed()
        let start = AVAudioFramePosition(range.lowerBound * fileFormat.sampleRate)
        guard start < recorded else { return }
        if start > 0 { session.skip(Double(start) / fileFormat.sampleRate) }
        try replay(
            min(recorded, AVAudioFramePosition(range.upperBound * fileFormat.sampleRate)), from: start, to: session,
            skippingSilence: true)
    }

    /// The stretch of the stream recorded between `range`'s bounds, in seconds, as the first channel of `format`.
    /// Reads the file, so keep it off the main actor.
    func samples(_ range: ClosedRange<TimeInterval>, in format: AVAudioFormat) throws -> [Float] {
        let recorded = try flushed()
        let end = min(recorded, AVAudioFramePosition(range.upperBound * fileFormat.sampleRate))
        let file = try AVAudioFile(
            forReading: url, commonFormat: fileFormat.commonFormat, interleaved: fileFormat.isInterleaved)
        file.framePosition = AVAudioFramePosition(range.lowerBound * fileFormat.sampleRate)
        guard file.framePosition < end,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(fileFormat.sampleRate))
        else { return [] }
        var converter: AVAudioConverter?
        var converted: AVAudioPCMBuffer?
        var samples: [Float] = []
        while file.framePosition < end {
            let count = min(buffer.frameCapacity, AVAudioFrameCount(end - file.framePosition))
            try file.read(into: buffer, frameCount: count)
            if buffer.frameLength == 0 { break }
            let output = try Self.convert(buffer, to: format, with: &converter, reusing: &converted)
            samples += UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
        }
        return samples
    }

    /// The frames recorded so far, all of them written to the file.
    private func flushed() throws -> AVAudioFramePosition {
        try state.withLock { state in
            if state.closed { throw CocoaError(.fileWriteUnknown) }
            if let error = state.error { throw error }
            try Self.flush(&state)
            return state.file.length
        }
    }

    /// `skippingSilence` skips each second of digital silence instead of having the session hear it.
    private func replay(
        _ frames: AVAudioFramePosition, from start: AVAudioFramePosition = 0, to session: any TranscriptionSession,
        skippingSilence: Bool = false
    ) throws {
        let file = try AVAudioFile(
            forReading: url, commonFormat: fileFormat.commonFormat, interleaved: fileFormat.isInterleaved)
        file.framePosition = start
        let chunk = AVAudioFrameCount(fileFormat.sampleRate)
        var converter: AVAudioConverter?
        while file.framePosition < frames {
            let count = min(chunk, AVAudioFrameCount(frames - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else {
                throw CocoaError(.featureUnsupported)
            }
            try file.read(into: buffer, frameCount: count)
            if buffer.frameLength == 0 { break }
            if skippingSilence, SoundLevel.isDigitalSilence(buffer) {
                session.skip(Double(buffer.frameLength) / fileFormat.sampleRate)
                continue
            }
            session.append(try Self.convert(buffer, to: session.audioFormat, with: &converter))
        }
    }

    private static func drainBacklog(_ state: inout State) {
        let backlog = state.backlog ?? []
        state.backlog = nil
        do {
            for buffer in backlog { try batch(buffer, into: &state) }
        } catch {
            state.error = error
        }
    }

    /// Adds `buffer` to the audio waiting for the session, and hands it over each time it holds `feedInterval`.
    private static func batch(_ buffer: AVAudioPCMBuffer, into state: inout State) throws {
        var offset: AVAudioFrameCount = 0
        while offset < buffer.frameLength {
            if state.feeding == nil {
                let capacity = AVAudioFrameCount(buffer.format.sampleRate * feedInterval)
                guard let feeding = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: capacity) else {
                    throw CocoaError(.featureUnsupported)
                }
                state.feeding = feeding
            }
            let feeding = state.feeding!
            let count = min(feeding.frameCapacity - feeding.frameLength, buffer.frameLength - offset)
            copy(count, framesFrom: buffer, at: offset, to: feeding)
            offset += count
            if feeding.frameLength == feeding.frameCapacity { try feedBatch(&state) }
        }
    }

    /// Hands the session the audio waiting for it, or skips it once the session heard `silenceHeard` of silence.
    private static func feedBatch(_ state: inout State) throws {
        guard let feeding = state.feeding, feeding.frameLength > 0 else { return }
        state.feeding = nil
        guard SoundLevel.isDigitalSilence(feeding) else {
            state.silenceFed = 0
            return try feed(feeding, to: &state)
        }
        if Double(state.silenceFed) >= silenceHeard * feeding.format.sampleRate {
            state.session.skip(Double(feeding.frameLength) / feeding.format.sampleRate)
        } else {
            state.silenceFed += AVAudioFramePosition(feeding.frameLength)
            try feed(feeding, to: &state)
        }
    }

    private static func feed(_ buffer: AVAudioPCMBuffer, to state: inout State) throws {
        state.session.append(try convert(buffer, to: state.session.audioFormat, with: &state.sessionConverter))
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            throw CocoaError(.featureUnsupported)
        }
        Self.copy(buffer.frameLength, framesFrom: buffer, at: 0, to: copy)
        return copy
    }

    /// Writes what is left and closes the file. Throws the first error met while recording.
    func close() throws {
        try state.withLock { state in
            guard !state.closed else { return }
            state.closed = true
            if state.error == nil {
                do {
                    try Self.feedBatch(&state)
                    try Self.flush(&state)
                } catch { state.error = error }
            }
            if let error = state.error { throw error }
        }
    }

    static func convert(
        _ buffer: AVAudioPCMBuffer, to format: AVAudioFormat, with converter: inout AVAudioConverter?
    ) throws -> AVAudioPCMBuffer {
        var output: AVAudioPCMBuffer?
        return try convert(buffer, to: format, with: &converter, reusing: &output)
    }

    /// Converts into `output` when it is big enough, else into a new buffer left in `output`: the result is only
    /// valid until the next conversion.
    static func convert(
        _ buffer: AVAudioPCMBuffer, to format: AVAudioFormat, with converter: inout AVAudioConverter?,
        reusing output: inout AVAudioPCMBuffer?
    ) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { throw CocoaError(.featureUnsupported) }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        if output?.format != format || (output?.frameCapacity ?? 0) < capacity {
            output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        }
        guard let output else { throw CocoaError(.featureUnsupported) }
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
