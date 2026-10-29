@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// Identifies a live Meeting's language once: hears both streams, keeps only their speech, has each window of
/// `window` seconds scored and votes, until the vote decides or gives up, or `stop()`. The model is let go as soon as
/// it is no longer needed, before the outcome is handed over.
final class LanguageIdentification: Sendable {
    /// Seconds of speech per window the classifier scores, within the 3–5 s the research note measured.
    static let window: TimeInterval = 4
    /// RMS of −40 dBFS over `gateFrame`: above a quiet room, below speech. Untuned: an energy gate, not a voice
    /// activity model, so music or loud noise gets through.
    static let speechLevel: Float = 0.01
    /// 30 ms at 16 kHz.
    static let gateFrame = 480

    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: LogMel.sampleRate, channels: 1, interleaved: false)!
    private static var windowSamples: Int { Int(window * LogMel.sampleRate) }

    /// One stream's audio on its way to the classifier.
    private struct StreamSpeech {
        var converter: AVAudioConverter?
        /// Audio not yet gated: less than one gate frame.
        var pending: [Float] = []
        /// Speech not yet scored: less than one window.
        var speech: [Float] = []
    }

    /// One lock per stream, so neither capture thread waits on the other's resampling.
    private let me = Mutex(StreamSpeech())
    private let them = Mutex(StreamSpeech())
    private let stopped = Atomic(false)
    private let windows: AsyncStream<[Float]>.Continuation

    /// `onOutcome` gets the vote's decision, or `gaveUp`, or the classifier's failure; never after `stop()`.
    init(
        vote: LanguageVote, classifier: any SpokenLanguageClassifier,
        onOutcome: @escaping @MainActor @Sendable (Result<LanguageVote.Outcome, any Error>) async -> Void
    ) {
        let (stream, windows) = AsyncStream<[Float]>.makeStream()
        self.windows = windows
        Task.detached { [self] in
            var vote = vote
            var outcome: Result<LanguageVote.Outcome, any Error>?
            // The windows heard before `stop()` are still in the stream: they are dropped unscored.
            for await window in stream where !self.stopped.load(ordering: .acquiring) {
                do {
                    let scores = try await classifier.classify(window)
                    let decision = vote.add(scores, speech: Double(window.count) / LogMel.sampleRate)
                    if decision != .undecided { outcome = .success(decision) }
                } catch {
                    outcome = .failure(error)
                }
                if outcome != nil { break }
            }
            let stopped = self.stopped.exchange(true, ordering: .acquiringAndReleasing)
            windows.finish()
            await classifier.release()
            if let outcome, !stopped { await onOutcome(outcome) }
        }
    }

    /// Takes in one captured buffer of `stream`, on the capture's thread.
    func hear(_ buffer: AVAudioPCMBuffer, on stream: AudioStream) {
        guard !stopped.load(ordering: .acquiring) else { return }
        let ready = stream == .me
            ? me.withLock { Self.gate(buffer, into: &$0) }
            : them.withLock { Self.gate(buffer, into: &$0) }
        for window in ready { windows.yield(window) }
    }

    /// Adds `buffer`'s speech to `audio`. Returns the windows it completes.
    private static func gate(_ buffer: AVAudioPCMBuffer, into audio: inout StreamSpeech) -> [[Float]] {
        guard let converted = try? StreamRecorder.convert(buffer, to: format, with: &audio.converter) else {
            return []
        }
        audio.pending += UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength))
        var start = 0
        while audio.pending.count - start >= gateFrame {
            let frame = audio.pending[start..<start + gateFrame]
            if isSpeech(frame) { audio.speech += frame }
            start += gateFrame
        }
        audio.pending.removeFirst(start)
        var ready: [[Float]] = []
        while audio.speech.count >= windowSamples {
            ready.append(Array(audio.speech.prefix(windowSamples)))
            audio.speech.removeFirst(windowSamples)
        }
        return ready
    }

    /// Stops hearing and scoring. A window being scored is dropped, and the model is let go.
    func stop() {
        stopped.store(true, ordering: .releasing)
        windows.finish()
    }

    private static func isSpeech(_ frame: ArraySlice<Float>) -> Bool {
        let power = frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)
        return power.squareRoot() > speechLevel
    }
}
