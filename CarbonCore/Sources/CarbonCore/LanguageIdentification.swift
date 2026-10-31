@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// Identifies a live Meeting's language from its own transcript, on each stream, for as long as the Meeting goes on
/// (ADR 0006). Two signals call for another of the checked languages:
///
/// - the lexical vote: the stream's final words, ten at a time, read as another language (`LexicalVote`);
/// - the rate guard: past `guardMinimumSpeech` of speech, the stream's transcript holds fewer than `guardRate` words
///   per second of speech, so its model doesn't understand what is said. Every other candidate is then tried.
///
/// Neither switches on its own: the stretch that called for it is first transcribed again in the candidate language,
/// which must confirm it (`LanguageProbe`). A rejected call backs off. A speech gate measures each stream's speech, so
/// silence, music and noise never count as speech the transcript missed. Gating, voting and probing run in one task;
/// the capture threads only resample. The gate outlives a Meeting, so an identification starts gating only once the
/// one before it has let it go: its release can't wipe the newer one's stream state.
final class LanguageIdentification: Sendable {
    /// The least probability of speech the gate must give a chunk for it to be speech: FluidAudio's default for Silero
    /// VAD. Measured on synthetic audio, speech scores 0.93–0.97, music and noise 0.00–0.01, notification sounds 0.03.
    static let speechProbability = 0.85
    /// The gate's sample rate.
    static let sampleRate = 16_000.0
    /// Below this many words per second of speech, the stream's model doesn't understand it. Correct models wrote
    /// 1.25–3.9 on the recordings measured, real Meetings 2.2–3.7; a model given accented or related speech 0.2–0.8.
    static let guardRate = 1.0
    /// The speech since the stream was last judged that the guard waits for.
    static let guardMinimumSpeech: TimeInterval = 20
    /// The latest speech the guard counts words over, and the candidates transcribe again.
    static let guardWindow: TimeInterval = 30
    /// The speech a stream waits for after its first rejected guard, and after a rejected vote, before calling again.
    /// Each further rejection in a row doubles it, so a Meeting in a language nobody checked isn't transcribed again
    /// in every candidate every minute.
    static let guardBackOff: TimeInterval = 60
    static let voteBackOff: TimeInterval = 20
    /// The audio after the vote's last word its stretch also takes, so a model transcribing it again can finish that word.
    static let voteMargin: TimeInterval = 1

    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    private enum Event {
        case audio(AudioStream, [Float])
        /// Final words from the stream's session numbered `session`.
        case words(AudioStream, session: Int, [TranscribedWord])
    }

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
    private let events: AsyncStream<Event>.Continuation
    /// The session each stream's words are taken from, numbered: words from an older one are dropped.
    private let listeners = Mutex<[AudioStream: (session: Int, task: Task<Void, Never>)]>([:])
    private let task = Mutex<Task<Void, Never>?>(nil)

    /// Starts in `current` among `text`'s candidates. `probe` transcribes a stretch of a stream again in a language,
    /// `switchTo` switches the Meeting to the language confirmed and says whether it did. The chunks heard while
    /// `previous` finishes wait for it.
    init(
        current: Locale, text: TextLanguage, speechGate: any SpeechGate, after previous: LanguageIdentification?,
        probe: @escaping @MainActor @Sendable (Locale, AudioStream, ClosedRange<TimeInterval>) async throws
            -> [TranscribedWord],
        switchTo: @escaping @MainActor @Sendable (Locale) async -> Bool,
        onDiagnostic: @escaping @MainActor @Sendable (String) -> Void
    ) {
        let (stream, events) = AsyncStream<Event>.makeStream()
        self.events = events
        chunkSize = speechGate.chunkSize
        let chunkSeconds = Double(chunkSize) / Self.sampleRate
        let task = Task.detached { [self] in
            await previous?.finished()
            var judge = Judge(current: current, text: text, chunkSeconds: chunkSeconds)
            // The events from before `stop()` are still in the stream: they are dropped unjudged.
            for await event in stream where !self.stopped.load(ordering: .acquiring) {
                let heardOn: AudioStream
                switch event {
                case .audio(let heard, let chunk):
                    heardOn = heard
                    do {
                        let probability = try await speechGate.speechProbability(of: chunk, on: heard)
                        judge.heard(speech: probability >= Self.speechProbability, on: heard)
                    } catch {
                        await onDiagnostic("Meeting Language identification stopped: \(error.localizedDescription)")
                        self.stop()
                        continue
                    }
                case .words(let heard, let session, let words):
                    guard self.listeners.withLock({ $0[heard]?.session }) == session else { continue }
                    heardOn = heard
                    judge.heard(words, on: heard)
                }
                guard let call = judge.call(on: heardOn) else { continue }
                await onDiagnostic("\(call.stream.label): \(call.summary)")
                let confirmed = await self.confirm(call, judge: judge, probe: probe, onDiagnostic: onDiagnostic)
                if self.stopped.load(ordering: .acquiring) { break }
                if let confirmed, await switchTo(confirmed) {
                    judge.switched(to: confirmed)
                } else {
                    let wait = judge.rejected(call)
                    await onDiagnostic(
                        "\(call.stream.label): stays \(MeetingFormat.bcp47(judge.current)), next call after "
                            + "\(Int(wait)) s of speech")
                }
            }
            self.stopped.store(true, ordering: .releasing)
            events.finish()
            for listener in self.listeners.withLock({ $0.values }) { listener.task.cancel() }
            await speechGate.release()
        }
        self.task.withLock { $0 = task }
    }

    /// The candidate the call's stretch confirms once transcribed again, if any: the vote's language, or the guard's
    /// best-confirmed candidate by words per second times its share.
    private func confirm(
        _ call: Judge.Call, judge: Judge,
        probe: @MainActor @Sendable (Locale, AudioStream, ClosedRange<TimeInterval>) async throws -> [TranscribedWord],
        onDiagnostic: @MainActor @Sendable (String) -> Void
    ) async -> Locale? {
        var confirmed: [LanguageProbe] = []
        for candidate in call.candidates {
            guard !stopped.load(ordering: .acquiring) else { return nil }
            do {
                let words = try await probe(candidate, call.stream, call.range)
                let probe = LanguageProbe(
                    candidate, wrote: words, against: call.currentWords, speech: call.speech, text: judge.text)
                await onDiagnostic(
                    "\(call.stream.label): \(probe.summary) on \(call.rangeSummary): "
                        + (probe.confirms ? "confirmed" : "rejected"))
                if probe.confirms { confirmed.append(probe) }
            } catch {
                await onDiagnostic(
                    "\(call.stream.label): couldn't transcribe again in \(MeetingFormat.bcp47(candidate)): "
                        + error.localizedDescription)
            }
        }
        return confirmed.max { $0.rate * $0.share < $1.rate * $1.share }?.candidate
    }

    /// Takes in one captured buffer of `stream`, on the capture's thread.
    func hear(_ buffer: AVAudioPCMBuffer, on stream: AudioStream) {
        guard !stopped.load(ordering: .acquiring) else { return }
        let ready = stream == .me
            ? me.withLock { Self.chunk(buffer, into: &$0, size: chunkSize) }
            : them.withLock { Self.chunk(buffer, into: &$0, size: chunkSize) }
        for chunk in ready { events.yield(.audio(stream, chunk)) }
    }

    /// Takes `stream`'s final words from `words` from now on, instead of from its session before.
    func listen(to words: AsyncStream<[TranscribedWord]>, on stream: AudioStream) {
        guard !stopped.load(ordering: .acquiring) else { return }
        listeners.withLock { listeners in
            listeners[stream]?.task.cancel()
            let session = (listeners[stream]?.session ?? 0) + 1
            let events = events
            listeners[stream] = (session, Task {
                for await run in words { events.yield(.words(stream, session: session, run)) }
            })
        }
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

    /// Returns once the gate is let go.
    func finished() async {
        await task.withLock { $0 }?.value
    }

    /// Stops hearing, gating and judging. A chunk being gated or a stretch being transcribed again is dropped, and the
    /// gate is let go.
    func stop() {
        stopped.store(true, ordering: .releasing)
        events.finish()
        for listener in listeners.withLock({ $0.values }) { listener.task.cancel() }
    }
}

extension AudioStream {
    /// "Me" or "Them", as a Transcript writes them.
    var label: String { self == .me ? TranscriptBuilder.me : TranscriptBuilder.them }
}

/// Both streams' evidence about the Meeting Language: their speech, their words since the Meeting was last switched,
/// their votes and their back-offs.
struct Judge {
    /// A stream calling for another language, with the stretch its candidates are transcribed again on.
    struct Call {
        enum Kind { case vote, rateGuard }

        var kind: Kind
        var stream: AudioStream
        /// The vote's language, or every other candidate for the guard.
        var candidates: [Locale]
        var range: ClosedRange<TimeInterval>
        var speech: TimeInterval
        /// The words the current language wrote over `range`.
        var currentWords: Int
        var summary: String

        var rangeSummary: String {
            String(format: "%.1f–%.1f s (%.1f s of speech)", range.lowerBound, range.upperBound, speech)
        }
    }

    let text: TextLanguage
    private(set) var current: Locale
    private let chunkSeconds: TimeInterval
    private var streams: [AudioStream: StreamEvidence] = [:]

    init(current: Locale, text: TextLanguage, chunkSeconds: TimeInterval) {
        self.text = text
        self.current = current
        self.chunkSeconds = chunkSeconds
        for stream in [AudioStream.me, .them] {
            streams[stream] = StreamEvidence(current: current, chunkSeconds: chunkSeconds)
        }
    }

    mutating func heard(speech: Bool, on stream: AudioStream) {
        streams[stream]!.speech.add(speech)
    }

    mutating func heard(_ words: [TranscribedWord], on stream: AudioStream) {
        streams[stream]!.add(words)
    }

    /// A call for another language on `stream`, if its evidence makes one now.
    mutating func call(on stream: AudioStream) -> Call? {
        streams[stream]!.call(on: stream, text: text, current: current)
    }

    /// Both streams' sessions were switched to `language`: their evidence starts again from what they heard so far.
    mutating func switched(to language: Locale) {
        current = language
        for stream in [AudioStream.me, .them] {
            streams[stream]!.restart(current: language)
        }
    }

    /// `call` was rejected. Returns the speech its stream waits for before calling again.
    mutating func rejected(_ call: Call) -> TimeInterval {
        streams[call.stream]!.backOff(call.kind)
    }
}

/// One stream's evidence, since its words were last restarted.
struct StreamEvidence {
    var speech: SpeechTimeline
    private var vote: LexicalVote
    /// Where the words counted start: the stream's time at the Meeting's last switch.
    private var since: TimeInterval = 0
    /// Final words not yet in a chunk.
    private var pending: [TranscribedWord] = []
    /// The end of every final word counted, in order.
    private var wordEnds: [TimeInterval] = []
    /// The stretches of the last chunks voted on, oldest first, with their shares for the vote's language.
    private var chunks: [(range: ClosedRange<TimeInterval>, shares: [Locale: Double])] = []
    /// The total speech of the stream before which the guard, or the vote, doesn't call.
    private var guardAfter: TimeInterval = 0
    private var voteAfter: TimeInterval = 0
    private var guardRejections = 0
    private var voteRejections = 0

    init(current: Locale, chunkSeconds: TimeInterval) {
        speech = SpeechTimeline(chunkSeconds: chunkSeconds)
        vote = LexicalVote(current: current)
    }

    mutating func restart(current: Locale) {
        vote = LexicalVote(current: current)
        since = speech.end
        pending = []
        wordEnds = []
        chunks = []
        guardAfter = 0
        voteAfter = 0
        guardRejections = 0
        voteRejections = 0
    }

    mutating func add(_ words: [TranscribedWord]) {
        for word in words where word.end > since {
            pending.append(word)
            let position = wordEnds.lastIndex { $0 <= word.end }.map { $0 + 1 } ?? 0
            wordEnds.insert(word.end, at: position)
        }
    }

    /// Votes on each chunk of words whose speech the gate has judged, then checks the guard.
    mutating func call(on stream: AudioStream, text: TextLanguage, current: Locale) -> Judge.Call? {
        while pending.count >= TextLanguage.chunkWords, pending[TextLanguage.chunkWords - 1].end <= speech.end {
            let words = pending.prefix(TextLanguage.chunkWords)
            pending.removeFirst(TextLanguage.chunkWords)
            let shares = text.shares(of: words)
            chunks.append(((chunks.last?.range.upperBound ?? since)...words.last!.end, shares))
            if chunks.count > LexicalVote.window { chunks.removeFirst() }
            guard let language = vote.add(shares), speech.total >= voteAfter else { continue }
            let range = chunks.first!.range.lowerBound
                ... chunks.last!.range.upperBound + LanguageIdentification.voteMargin
            let read = chunks.map { String(format: "%.2f", $0.shares[language] ?? 0) }.joined(separator: ", ")
            return call(
                .vote, on: stream, for: [language], over: range,
                summary: "\(LexicalVote.agreeing) of the last \(chunks.count) chunks read as "
                    + "\(MeetingFormat.bcp47(language)) (\(read)) while transcribed in \(MeetingFormat.bcp47(current))")
        }
        guard speech.speech(from: since, to: speech.end) >= LanguageIdentification.guardMinimumSpeech,
            speech.total >= guardAfter
        else { return nil }
        let start = max(since, speech.start(ofLast: LanguageIdentification.guardWindow))
        let range = start...speech.end
        let words = count(in: range)
        let seconds = speech.speech(from: start, to: speech.end)
        guard Double(words) / seconds < LanguageIdentification.guardRate else { return nil }
        return call(
            .rateGuard, on: stream, for: text.candidates.filter { !text.same($0, current) }, over: range,
            summary: String(format: "%.2f", Double(words) / seconds) + " words per second of speech in "
                + "\(MeetingFormat.bcp47(current)), \(words) words over \(String(format: "%.1f", seconds)) s of speech")
    }

    private func call(
        _ kind: Judge.Call.Kind, on stream: AudioStream, for candidates: [Locale], over range: ClosedRange<TimeInterval>,
        summary: String
    ) -> Judge.Call {
        Judge.Call(
            kind: kind, stream: stream, candidates: candidates, range: range,
            speech: speech.speech(from: range.lowerBound, to: range.upperBound), currentWords: count(in: range),
            summary: summary)
    }

    /// The words that end within `range`, start excluded.
    private func count(in range: ClosedRange<TimeInterval>) -> Int {
        wordEnds.filter { $0 > range.lowerBound && $0 <= range.upperBound }.count
    }

    /// Backs the guard, or the vote, off. Returns the speech it waits for.
    mutating func backOff(_ kind: Judge.Call.Kind) -> TimeInterval {
        vote.reset()
        chunks = []
        if kind == .rateGuard {
            let wait = LanguageIdentification.guardBackOff * pow(2, Double(guardRejections))
            guardRejections += 1
            guardAfter = speech.total + wait
            return wait
        }
        let wait = LanguageIdentification.voteBackOff * pow(2, Double(voteRejections))
        voteRejections += 1
        voteAfter = speech.total + wait
        return wait
    }
}

/// Which of a stream's chunks the speech gate judged speech, from the start of the stream.
struct SpeechTimeline {
    let chunkSeconds: TimeInterval
    /// The speech in the stream's first n chunks, at n.
    private var cumulative: [TimeInterval] = [0]

    init(chunkSeconds: TimeInterval) {
        self.chunkSeconds = chunkSeconds
    }

    mutating func add(_ isSpeech: Bool) {
        cumulative.append(cumulative.last! + (isSpeech ? chunkSeconds : 0))
    }

    /// The stream time the gate has judged up to.
    var end: TimeInterval { Double(cumulative.count - 1) * chunkSeconds }
    var total: TimeInterval { cumulative.last! }

    func speech(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        cumulative[index(end)] - cumulative[index(start)]
    }

    /// The time from which the stream holds `seconds` of speech up to its end, or its start if it holds less.
    func start(ofLast seconds: TimeInterval) -> TimeInterval {
        let target = total - seconds
        guard target > 0 else { return 0 }
        let position = cumulative.lastIndex { $0 <= target } ?? 0
        return Double(position) * chunkSeconds
    }

    private func index(_ time: TimeInterval) -> Int {
        min(max(0, Int((time / chunkSeconds).rounded())), cumulative.count - 1)
    }
}
