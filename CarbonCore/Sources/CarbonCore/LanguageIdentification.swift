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

    private struct Ear {
        var converter: AVAudioConverter?
        /// Audio not yet gated: less than one gate frame.
        var pending: [Float] = []
        /// Speech not yet scored: less than one window.
        var speech: [Float] = []
    }

    private struct State {
        var ears: [AudioStream: Ear] = [:]
        var stopped = false
    }

    private let state = Mutex(State())
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
            for await window in stream where !self.state.withLock({ $0.stopped }) {
                do {
                    let scores = try await classifier.classify(window)
                    let decision = vote.add(scores, speech: Double(window.count) / LogMel.sampleRate)
                    if decision != .undecided { outcome = .success(decision) }
                } catch {
                    outcome = .failure(error)
                }
                if outcome != nil { break }
            }
            let stopped = self.state.withLock { state in
                defer { state.stopped = true }
                return state.stopped
            }
            windows.finish()
            await classifier.release()
            if let outcome, !stopped { await onOutcome(outcome) }
        }
    }

    /// Takes in one captured buffer of `stream`, on the capture's thread.
    func hear(_ buffer: AVAudioPCMBuffer, on stream: AudioStream) {
        let ready = state.withLock { state -> [[Float]] in
            guard !state.stopped else { return [] }
            var ear = state.ears[stream, default: Ear()]
            defer { state.ears[stream] = ear }
            guard let converted = try? StreamRecorder.convert(buffer, to: Self.format, with: &ear.converter) else {
                return []
            }
            ear.pending += UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength))
            var start = 0
            while ear.pending.count - start >= Self.gateFrame {
                let frame = ear.pending[start..<start + Self.gateFrame]
                if Self.isSpeech(frame) { ear.speech += frame }
                start += Self.gateFrame
            }
            ear.pending.removeFirst(start)
            var ready: [[Float]] = []
            while ear.speech.count >= Self.windowSamples {
                ready.append(Array(ear.speech.prefix(Self.windowSamples)))
                ear.speech.removeFirst(Self.windowSamples)
            }
            return ready
        }
        for window in ready { windows.yield(window) }
    }

    /// Stops hearing and scoring. A window being scored is dropped, and the model is let go.
    func stop() {
        state.withLock { state in
            state.stopped = true
            state.ears = [:]
        }
        windows.finish()
    }

    private static func isSpeech(_ frame: ArraySlice<Float>) -> Bool {
        let power = frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)
        return power.squareRoot() > speechLevel
    }
}
