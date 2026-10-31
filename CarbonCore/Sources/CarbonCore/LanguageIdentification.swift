@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// Identifies a live Meeting's language from its own transcript, on each stream, for as long as the Meeting goes on
/// (ADR 0006). Two signals challenge the current language for another of the checked ones:
///
/// - the lexical vote: the stream's final words, ten at a time, read as another language (`LexicalVote`);
/// - the rate guard: past `guardMinimumSpeech` of speech, the stream's transcript holds fewer than `guardRate` words
///   per second of speech, so its model doesn't understand what is said. Every other candidate is then tried.
///
/// Neither switches on its own: the stretch that made the challenge is first transcribed again in the candidate
/// language, which must confirm it (`LanguageProbe`). A rejected challenge backs off (`BackOff`). A speech gate measures each stream's speech, so
/// silence, music and noise never count as speech the transcript missed. Gating, voting and probing run in one task;
/// the capture threads only resample. The gate outlives a Meeting, so an identification starts gating only once the
/// one before it has let it go: its release can't wipe the newer one's stream state.
final class LanguageIdentification: Sendable {
    /// The least probability of speech the gate must give a chunk for it to be speech: FluidAudio's default for Silero
    /// VAD. Measured on synthetic audio, speech scores 0.93–0.97, music and noise 0.00–0.01, notification sounds 0.03.
    static let speechProbability = 0.85
    static let sampleRate = 16_000.0
    /// Below this many words per second of speech, the stream's model doesn't understand it. Correct models wrote
    /// 1.25–3.9 on the recordings measured, real Meetings 2.2–3.7; a model given accented or related speech 0.2–0.8.
    static let guardRate = 1.0
    /// The speech since the stream was last judged that the guard waits for.
    static let guardMinimumSpeech: TimeInterval = 20
    /// The latest speech the guard counts words over, and the candidates transcribe again.
    static let guardWindow: TimeInterval = 30
    /// The speech a stream waits for after its first rejected guard, or its first rejected vote, before challenging
    /// that way again (`BackOff`): a Meeting in a language nobody checked isn't transcribed again in every candidate
    /// every 20 s.
    static let guardBackOff: TimeInterval = 60
    static let voteBackOff: TimeInterval = 20
    /// The audio around the vote's words its stretch also takes, so a model transcribing it again can finish them.
    static let voteMargin: TimeInterval = 1
    /// The most audio a challenge's stretch spans, however little speech it holds: a stream quiet for an hour isn't
    /// transcribed again for an hour.
    static let maximumStretch: TimeInterval = 120
    /// How far SpeechTranscriber's final words may lag behind the audio: the guard doesn't count the latest speech
    /// as speech without words until then.
    static let finalizationLag: TimeInterval = 5

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
        /// The converter's output, reused from buffer to buffer: allocating and freeing one per capture buffer costs as
        /// much as resampling it.
        var converted: AVAudioPCMBuffer?
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

    /// Starts in `current` among `reader`'s candidates. `probe` transcribes a stretch of a stream again in a language,
    /// `switchTo` switches the Meeting to the language confirmed and says whether it did. The chunks heard while
    /// `previous` finishes wait for it.
    init(
        current: Locale, reader: TextLanguage, speechGate: any SpeechGate, after previous: LanguageIdentification?,
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
            var evidence = LanguageEvidence(current: current, reader: reader, chunkSeconds: chunkSeconds)
            // The events from before `stop()` are still in the stream: they are dropped unjudged.
            for await event in stream where !self.stopped.load(ordering: .acquiring) {
                let heardOn: AudioStream
                switch event {
                case .audio(let heard, let chunk):
                    heardOn = heard
                    do {
                        let probability = try await speechGate.speechProbability(of: chunk, on: heard)
                        evidence.heard(speech: probability >= Self.speechProbability, on: heard)
                    } catch {
                        await onDiagnostic("Meeting Language identification stopped: \(error.localizedDescription)")
                        self.stop()
                        continue
                    }
                case .words(let heard, let session, let words):
                    guard self.listeners.withLock({ $0[heard]?.session }) == session else { continue }
                    heardOn = heard
                    evidence.heard(words, on: heard)
                }
                guard let challenge = evidence.challenge(on: heardOn) else { continue }
                await onDiagnostic("\(challenge.stream.label): \(challenge.reason)")
                let confirmed = await self.confirm(
                    challenge, reader: evidence.reader, probe: probe, onDiagnostic: onDiagnostic)
                if self.stopped.load(ordering: .acquiring) { break }
                if let confirmed, await switchTo(confirmed) {
                    evidence.switched(to: confirmed)
                } else {
                    let wait = evidence.rejected(challenge)
                    await onDiagnostic(
                        "\(challenge.stream.label): stays \(MeetingFormat.bcp47(evidence.current)), next challenge "
                            + "after \(Int(wait)) s of speech")
                }
            }
            self.stop()
            await speechGate.release()
        }
        self.task.withLock { $0 = task }
    }

    /// The candidate the challenge's stretch confirms once transcribed again, if any: the vote's language, or the
    /// guard's best-confirmed candidate by words per second times its share.
    private func confirm(
        _ challenge: LanguageEvidence.Challenge, reader: TextLanguage,
        probe: @MainActor @Sendable (Locale, AudioStream, ClosedRange<TimeInterval>) async throws -> [TranscribedWord],
        onDiagnostic: @MainActor @Sendable (String) -> Void
    ) async -> Locale? {
        var confirmed: [LanguageProbe] = []
        for candidate in challenge.candidates {
            guard !stopped.load(ordering: .acquiring) else { return nil }
            do {
                let words = try await probe(candidate, challenge.stream, challenge.range)
                let result = LanguageProbe(
                    candidate, wrote: words, against: challenge.currentWords, speech: challenge.speech, reader: reader)
                await onDiagnostic(
                    "\(challenge.stream.label): \(result.summary) on \(challenge.rangeSummary): "
                        + (result.confirms ? "confirmed" : "rejected"))
                if result.confirms { confirmed.append(result) }
            } catch {
                await onDiagnostic(
                    "\(challenge.stream.label): couldn't transcribe again in \(MeetingFormat.bcp47(candidate)): "
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

    /// Takes each stream's final words from `me` and `them` from now on, instead of from their sessions before.
    func listen(me: any TranscriptionSession, them: any TranscriptionSession) {
        guard !stopped.load(ordering: .acquiring) else { return }
        let events = events
        listeners.withLock { listeners in
            for (stream, session) in [(AudioStream.me, me), (.them, them)] {
                listeners[stream]?.task.cancel()
                let number = (listeners[stream]?.session ?? 0) + 1
                let words = session.finalWords
                listeners[stream] = (number, Task {
                    for await run in words { events.yield(.words(stream, session: number, run)) }
                })
            }
        }
    }

    /// Adds `buffer`, resampled, to `audio`. Returns the chunks it completes.
    private static func chunk(_ buffer: AVAudioPCMBuffer, into audio: inout StreamAudio, size: Int) -> [[Float]] {
        guard
            let converted = try? StreamRecorder.convert(
                buffer, to: format, with: &audio.converter, reusing: &audio.converted)
        else { return [] }
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
struct LanguageEvidence {
    /// A stream challenging the current language, with the stretch its candidates are transcribed again on.
    struct Challenge {
        enum Kind { case vote, rateGuard }

        var kind: Kind
        var stream: AudioStream
        /// The vote's language, or every other candidate for the guard.
        var candidates: [Locale]
        var range: ClosedRange<TimeInterval>
        var speech: TimeInterval
        /// The words the current language wrote over `range`.
        var currentWords: Int
        /// What made the challenge, for the diagnostic log.
        var reason: String

        var rangeSummary: String {
            String(format: "%.1f–%.1f s (%.1f s of speech)", range.lowerBound, range.upperBound, speech)
        }
    }

    let reader: TextLanguage
    private(set) var current: Locale
    private var streams: [AudioStream: StreamEvidence] = [:]

    init(current: Locale, reader: TextLanguage, chunkSeconds: TimeInterval) {
        self.reader = reader
        self.current = current
        for stream in [AudioStream.me, .them] {
            streams[stream] = StreamEvidence(stream: stream, current: current, chunkSeconds: chunkSeconds)
        }
    }

    mutating func heard(speech: Bool, on stream: AudioStream) {
        streams[stream]!.speech.add(speech)
    }

    mutating func heard(_ words: [TranscribedWord], on stream: AudioStream) {
        streams[stream]!.add(words)
    }

    /// `stream`'s challenge to the current language, if its evidence makes one now.
    mutating func challenge(on stream: AudioStream) -> Challenge? {
        streams[stream]!.challenge(reader: reader, current: current)
    }

    /// Both streams' sessions were switched to `language`: their evidence starts again from what they heard so far.
    mutating func switched(to language: Locale) {
        current = language
        for stream in [AudioStream.me, .them] {
            streams[stream]!.restart(current: language)
        }
    }

    /// `challenge` was rejected. Returns the speech its stream waits for before challenging that way again.
    mutating func rejected(_ challenge: Challenge) -> TimeInterval {
        streams[challenge.stream]!.backOff(challenge.kind)
    }
}

/// How long a stream waits, in speech, before challenging again after a rejection: `first`, doubled by each further
/// rejection since the last switch, up to 8 times `first`.
struct BackOff {
    let first: TimeInterval
    /// The stream's total speech before which it doesn't challenge.
    private(set) var until: TimeInterval = 0
    private var rejections = 0

    init(first: TimeInterval) {
        self.first = first
    }

    /// Backs off from `speech`, the stream's total speech now. Returns the wait.
    mutating func reject(at speech: TimeInterval) -> TimeInterval {
        let wait = first * pow(2, Double(min(rejections, 3)))
        rejections += 1
        until = speech + wait
        return wait
    }
}

/// One stream's evidence, since the Meeting was last switched.
struct StreamEvidence {
    let stream: AudioStream
    var speech: SpeechTimeline
    private var vote: LexicalVote
    /// Where the words counted start: the stream's time at the Meeting's last switch.
    private var since: TimeInterval = 0
    /// Final words not yet in a chunk.
    private var pending: [TranscribedWord] = []
    /// The end of every final word counted, in order.
    private var wordEnds: [TimeInterval] = []
    /// The stretches of the last chunks voted on, oldest first, with their shares.
    private var chunks: [(range: ClosedRange<TimeInterval>, shares: [Locale: Double])] = []
    /// Where the last chunk taken in ended.
    private var lastChunkEnd: TimeInterval?
    private var voteBackOff = BackOff(first: LanguageIdentification.voteBackOff)
    private var guardBackOff = BackOff(first: LanguageIdentification.guardBackOff)

    init(stream: AudioStream, current: Locale, chunkSeconds: TimeInterval) {
        self.init(stream: stream, current: current, speech: SpeechTimeline(chunkSeconds: chunkSeconds))
    }

    private init(stream: AudioStream, current: Locale, speech: SpeechTimeline) {
        self.stream = stream
        self.speech = speech
        vote = LexicalVote(current: current)
        since = speech.end
    }

    /// Starts again in `current` from the speech heard so far, with no words, votes or back-offs.
    mutating func restart(current: Locale) {
        self = StreamEvidence(stream: stream, current: current, speech: speech)
    }

    mutating func add(_ words: [TranscribedWord]) {
        for word in words where word.end > since {
            pending.append(word)
            wordEnds.insert(word.end, at: wordsEnding(atOrBefore: word.end))
        }
    }

    /// Votes on each chunk of words whose speech the gate has judged, then checks the guard.
    mutating func challenge(reader: TextLanguage, current: Locale) -> LanguageEvidence.Challenge? {
        while pending.count >= TextLanguage.chunkWords, pending[TextLanguage.chunkWords - 1].end <= speech.end {
            let words = pending.prefix(TextLanguage.chunkWords)
            pending.removeFirst(TextLanguage.chunkWords)
            let start = lastChunkEnd ?? max(since, words.first!.start - LanguageIdentification.voteMargin)
            lastChunkEnd = words.last!.end
            let shares = reader.shares(of: words)
            chunks.append((start...words.last!.end, shares))
            if chunks.count > LexicalVote.window { chunks.removeFirst() }
            guard let language = vote.add(shares), speech.total >= voteBackOff.until else { continue }
            let range = chunks.first!.range.lowerBound
                ... chunks.last!.range.upperBound + LanguageIdentification.voteMargin
            let read = chunks.map { LanguageProbe.format($0.shares[language] ?? 0) }.joined(separator: ", ")
            return challenge(
                .vote, for: [language], over: range,
                reason: "\(LexicalVote.agreeing) of the last \(chunks.count) chunks read as "
                    + "\(MeetingFormat.bcp47(language)) (\(read)) while transcribed in \(MeetingFormat.bcp47(current))")
        }
        return rateGuard(reader: reader, current: current)
    }

    /// The guard's challenge, if the latest speech holds too few words. The words of the last
    /// `LanguageIdentification.finalizationLag` of audio may not be final yet, so that audio is left out unless words
    /// already reach into it.
    private func rateGuard(reader: TextLanguage, current: Locale) -> LanguageEvidence.Challenge? {
        let end = min(speech.end, max(wordEnds.last ?? 0, speech.end - LanguageIdentification.finalizationLag))
        guard end > since, speech.speech(from: since, to: end) >= LanguageIdentification.guardMinimumSpeech,
            speech.total >= guardBackOff.until
        else { return nil }
        let start = max(since, speech.start(ofLast: LanguageIdentification.guardWindow, before: end))
        let words = count(in: start...end)
        let seconds = speech.speech(from: start, to: end)
        guard Double(words) / seconds < LanguageIdentification.guardRate else { return nil }
        return challenge(
            .rateGuard, for: reader.candidates.filter { !reader.same($0, current) }, over: start...end,
            reason: "\(LanguageProbe.format(Double(words) / seconds)) words per second of speech in "
                + "\(MeetingFormat.bcp47(current)), \(words) words over \(String(format: "%.1f", seconds)) s of speech")
    }

    private func challenge(
        _ kind: LanguageEvidence.Challenge.Kind, for candidates: [Locale], over range: ClosedRange<TimeInterval>,
        reason: String
    ) -> LanguageEvidence.Challenge {
        let range = max(range.lowerBound, range.upperBound - LanguageIdentification.maximumStretch)...range.upperBound
        return LanguageEvidence.Challenge(
            kind: kind, stream: stream, candidates: candidates, range: range,
            speech: speech.speech(from: range.lowerBound, to: range.upperBound), currentWords: count(in: range),
            reason: reason)
    }

    /// The words that end within `range`, start excluded.
    private func count(in range: ClosedRange<TimeInterval>) -> Int {
        wordsEnding(atOrBefore: range.upperBound) - wordsEnding(atOrBefore: range.lowerBound)
    }

    /// The words that end at or before `time`, found in the sorted `wordEnds`.
    private func wordsEnding(atOrBefore time: TimeInterval) -> Int {
        var (low, high) = (0, wordEnds.count)
        while low < high {
            let middle = (low + high) / 2
            if wordEnds[middle] <= time { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Backs the guard, or the vote, off. Returns the speech it waits for.
    mutating func backOff(_ kind: LanguageEvidence.Challenge.Kind) -> TimeInterval {
        vote.reset()
        chunks = []
        switch kind {
        case .vote: return voteBackOff.reject(at: speech.total)
        case .rateGuard: return guardBackOff.reject(at: speech.total)
        }
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

    /// The time from which the stream holds `seconds` of speech up to `end`, or its start if it holds less.
    func start(ofLast seconds: TimeInterval, before end: TimeInterval) -> TimeInterval {
        let target = cumulative[index(end)] - seconds
        guard target > 0 else { return 0 }
        let position = cumulative.lastIndex { $0 <= target } ?? 0
        return Double(position) * chunkSeconds
    }

    private func index(_ time: TimeInterval) -> Int {
        min(max(0, Int((time / chunkSeconds).rounded())), cumulative.count - 1)
    }
}
