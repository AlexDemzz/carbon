@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// Identifies a live Meeting's language once: hears both streams, has a speech gate keep only their speech, has each
/// window of `window` seconds scored and votes, until the vote decides or gives up, or `stop()`. The capture threads
/// only resample: gating and scoring run in one task. The models are let go as soon as they are no longer needed,
/// before the outcome is handed over. The gate and the classifier outlive a Meeting, so an identification starts
/// judging only once the one before it has let them go: its release can't wipe the newer one's stream state.
final class LanguageIdentification: Sendable {
    /// Seconds of speech per window the classifier scores, within the 3–5 s the research note measured.
    static let window: TimeInterval = 4
    /// The least probability of speech the gate must give a chunk for it to be speech: FluidAudio's default for Silero
    /// VAD. Measured on synthetic audio, speech scores 0.93–0.97, music and noise 0.00–0.01, notification sounds 0.03.
    static let speechProbability = 0.85

    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: LogMel.sampleRate, channels: 1, interleaved: false)!
    private static var windowSamples: Int { Int(window * LogMel.sampleRate) }

    /// One stream's audio on its way to the speech gate.
    private struct StreamAudio {
        var converter: AVAudioConverter?
        /// Audio not yet gated: less than one chunk.
        var pending: [Float] = []
    }

    /// One lock per stream, so neither capture thread waits on the other's resampling.
    private let me = Mutex(StreamAudio())
    private let them = Mutex(StreamAudio())
    private let chunkSize: Int
    private let stopped = Atomic(false)
    private let chunks: AsyncStream<(stream: AudioStream, audio: [Float])>.Continuation
    private let task = Mutex<Task<Void, Never>?>(nil)

    /// `onOutcome` gets the vote's decision, or `gaveUp`, or the gate's or the classifier's failure; never after
    /// `stop()`. The chunks heard while `previous` finishes wait for it.
    init(
        vote: LanguageVote, speechGate: any SpeechGate, classifier: any SpokenLanguageClassifier,
        after previous: LanguageIdentification?,
        onOutcome: @escaping @MainActor @Sendable (Result<LanguageVote.Outcome, any Error>) async -> Void
    ) {
        let (stream, chunks) = AsyncStream<(stream: AudioStream, audio: [Float])>.makeStream()
        self.chunks = chunks
        chunkSize = speechGate.chunkSize
        let task = Task.detached { [self] in
            await previous?.finished()
            var vote = vote
            var speech: [AudioStream: [Float]] = [:]
            var outcome: Result<LanguageVote.Outcome, any Error>?
            // The chunks heard before `stop()` are still in the stream: they are dropped unjudged.
            for await chunk in stream where !self.stopped.load(ordering: .acquiring) {
                do {
                    guard try await speechGate.speechProbability(of: chunk.audio, on: chunk.stream)
                        >= Self.speechProbability
                    else { continue }
                    var heard = speech[chunk.stream, default: []] + chunk.audio
                    defer { speech[chunk.stream] = heard }
                    guard heard.count >= Self.windowSamples else { continue }
                    let window = Array(heard.prefix(Self.windowSamples))
                    heard.removeFirst(Self.windowSamples)
                    let scores = try await classifier.classify(window)
                    let decision = vote.add(scores, speech: Self.window)
                    if decision != .undecided { outcome = .success(decision) }
                } catch {
                    outcome = .failure(error)
                }
                if outcome != nil { break }
            }
            let stopped = self.stopped.exchange(true, ordering: .acquiringAndReleasing)
            chunks.finish()
            await classifier.release()
            await speechGate.release()
            if let outcome, !stopped { await onOutcome(outcome) }
        }
        self.task.withLock { $0 = task }
    }

    /// Takes in one captured buffer of `stream`, on the capture's thread.
    func hear(_ buffer: AVAudioPCMBuffer, on stream: AudioStream) {
        guard !stopped.load(ordering: .acquiring) else { return }
        let ready = stream == .me
            ? me.withLock { Self.chunk(buffer, into: &$0, size: chunkSize) }
            : them.withLock { Self.chunk(buffer, into: &$0, size: chunkSize) }
        for chunk in ready { chunks.yield((stream, chunk)) }
    }

    /// Adds `buffer`, resampled, to `audio`. Returns the chunks it completes.
    private static func chunk(_ buffer: AVAudioPCMBuffer, into audio: inout StreamAudio, size: Int) -> [[Float]] {
        guard let converted = try? StreamRecorder.convert(buffer, to: format, with: &audio.converter) else {
            return []
        }
        audio.pending += UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength))
        var ready: [[Float]] = []
        while audio.pending.count >= size {
            ready.append(Array(audio.pending.prefix(size)))
            audio.pending.removeFirst(size)
        }
        return ready
    }

    /// Returns once the models are let go and the outcome, if any, is handed over.
    func finished() async {
        await task.withLock { $0 }?.value
    }

    /// Stops hearing, gating and scoring. A chunk being gated or a window being scored is dropped, and the models are
    /// let go.
    func stop() {
        stopped.store(true, ordering: .releasing)
        chunks.finish()
    }
}
