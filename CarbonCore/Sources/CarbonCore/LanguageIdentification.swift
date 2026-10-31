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
/// language, which must confirm it (`LanguageProbe`). A rejected challenge backs off (`BackOff`).
///
/// A speech gate measures each stream's speech, so silence, music and noise never count as speech the transcript
/// missed. It only runs when a challenge needs it: the capture threads only tell sound from silence, and while the
/// stream's latest sound holds `guardRate` words per second of it, its speech does too, so the guard can't fire.
/// Otherwise the gate judges the sound the guard counts, or a vote's stretch holds, read back from the stream's
/// recording, each chunk once. Gating, voting and probing run in one task. The gate outlives a Meeting, so an
/// identification starts gating only once the one before it has let it go: its release can't wipe the newer one's
/// stream state.
final class LanguageIdentification: Sendable {
    /// The least probability of speech the gate must give a chunk for it to be speech: FluidAudio's default for Silero
    /// VAD. Measured on synthetic audio, speech scores 0.93–0.97, music and noise 0.00–0.01, notification sounds 0.03.
    static let speechProbability = 0.85
    static let sampleRate = 16_000.0
    /// The format the gate judges a stream in, read back from its recording.
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
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
    /// The gate's chunks a capture thread tells sound from silence over at once, about a second: the task wakes once
    /// per second of each stream.
    static let chunksHeardAtOnce = 4

    private enum Event {
        /// `chunks` more of a stream's audio, sound when any of it passed `SoundLevel.threshold`.
        case heard(AudioStream, chunks: Int, sound: Bool)
        /// Final words from the stream's session numbered `session`.
        case words(AudioStream, session: Int, [TranscribedWord])
    }

    /// One stream's audio short of `chunksHeardAtOnce` chunks, and whether any of it was sound.
    private struct Unheard {
        var seconds: TimeInterval = 0
        var sound = false
    }

    /// One lock per stream, so neither capture thread waits on the other.
    private let me = Mutex(Unheard())
    private let them = Mutex(Unheard())
    /// The audio in `chunksHeardAtOnce` chunks.
    private let heardAtOnce: TimeInterval
    private let stopped = Atomic(false)
    private let events: AsyncStream<Event>.Continuation
    /// The session each stream's words are taken from, numbered: words from an older one are dropped.
    private let listeners = Mutex<[AudioStream: (session: Int, task: Task<Void, Never>)]>([:])
    private let task = Mutex<Task<Void, Never>?>(nil)

    /// Starts in `current` among `reader`'s candidates. `probe` transcribes a stretch of a stream again in a language,
    /// `recorded` reads a stretch of a stream back in `format`, `switchTo` switches the Meeting to the language
    /// confirmed and says whether it did. The audio heard while `previous` finishes waits for it.
    init(
        current: Locale, reader: TextLanguage, speechGate: any SpeechGate, after previous: LanguageIdentification?,
        probe: @escaping @MainActor @Sendable (Locale, AudioStream, ClosedRange<TimeInterval>) async throws
            -> [TranscribedWord],
        recorded: @escaping @MainActor @Sendable (AudioStream, ClosedRange<TimeInterval>) async throws -> [Float],
        switchTo: @escaping @MainActor @Sendable (Locale) async -> Bool,
        onDiagnostic: @escaping @MainActor @Sendable (String) -> Void
    ) {
        let (stream, events) = AsyncStream<Event>.makeStream()
        self.events = events
        let chunkSeconds = Double(speechGate.chunkSize) / Self.sampleRate
        heardAtOnce = chunkSeconds * Double(Self.chunksHeardAtOnce)
        let task = Task.detached { [self] in
            await previous?.finished()
            var evidence = LanguageEvidence(current: current, reader: reader, chunkSeconds: chunkSeconds)
            var gate = RecordedGate(
                speechGate: speechGate, recorded: recorded, stopped: { self.stopped.load(ordering: .acquiring) })
            // The events from before `stop()` are still in the stream: they are dropped unjudged.
            for await event in stream where !self.stopped.load(ordering: .acquiring) {
                let heardOn: AudioStream
                switch event {
                case .heard(let heard, let chunks, let sound):
                    heardOn = heard
                    evidence.heard(chunks, sound: sound, on: heard)
                case .words(let heard, let session, let words):
                    guard self.listeners.withLock({ $0[heard]?.session }) == session else { continue }
                    heardOn = heard
                    evidence.heard(words, on: heard)
                }
                let challenge: LanguageEvidence.Challenge
                do {
                    while let stretch = evidence.unjudgedGuardStretch(on: heardOn),
                        try await gate.judge(stretch, on: heardOn, into: &evidence)
                    {}
                    guard !self.stopped.load(ordering: .acquiring), let found = evidence.challenge(on: heardOn)
                    else { continue }
                    // A vote's stretch may hold sound the gate hasn't judged: its rates need its speech.
                    _ = try await gate.judge(found.range, on: found.stream, into: &evidence)
                    challenge = evidence.measured(found)
                } catch {
                    if !self.stopped.load(ordering: .acquiring) {
                        await onDiagnostic("Meeting Language identification stopped: \(error.localizedDescription)")
                    }
                    self.stop()
                    continue
                }
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
                let words = TextLanguage.words(try await probe(candidate, challenge.stream, challenge.range))
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

    /// Takes in `duration` more of `stream`, `sound` when it passed `SoundLevel.threshold`, on the capture's thread.
    func hear(_ duration: TimeInterval, sound: Bool, on stream: AudioStream) {
        guard !stopped.load(ordering: .acquiring) else { return }
        let period = heardAtOnce
        let heard = stream == .me
            ? me.withLock { Self.add(duration, sound: sound, to: &$0, every: period) }
            : them.withLock { Self.add(duration, sound: sound, to: &$0, every: period) }
        for sound in heard { events.yield(.heard(stream, chunks: Self.chunksHeardAtOnce, sound: sound)) }
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
                    for await run in words { events.yield(.words(stream, session: number, TextLanguage.words(run))) }
                })
            }
        }
    }

    /// Adds `duration` to `unheard`. Returns, for each `period` it completes, whether any of it was sound.
    private static func add(
        _ duration: TimeInterval, sound: Bool, to unheard: inout Unheard, every period: TimeInterval
    ) -> [Bool] {
        unheard.seconds += duration
        unheard.sound = unheard.sound || sound
        var heard: [Bool] = []
        while unheard.seconds >= period {
            heard.append(unheard.sound)
            unheard.seconds -= period
            unheard.sound = sound && unheard.seconds > 0
        }
        return heard
    }

    /// Returns once the gate is let go.
    func finished() async {
        await task.withLock { $0 }?.value
    }

    /// Stops hearing, gating and judging. A stretch being judged or transcribed again is dropped, and the gate is let
    /// go.
    func stop() {
        stopped.store(true, ordering: .releasing)
        events.finish()
        for listener in listeners.withLock({ $0.values }) { listener.task.cancel() }
    }
}

/// The speech gate, judging stretches of the streams read back from their recordings.
private struct RecordedGate {
    let speechGate: any SpeechGate
    let recorded: @MainActor @Sendable (AudioStream, ClosedRange<TimeInterval>) async throws -> [Float]
    let stopped: @Sendable () -> Bool
    /// The last chunk of each stream the gate judged, by number: the state it keeps holds only for the next one.
    private var lastJudged: [AudioStream: Int] = [:]

    init(
        speechGate: any SpeechGate,
        recorded: @escaping @MainActor @Sendable (AudioStream, ClosedRange<TimeInterval>) async throws -> [Float],
        stopped: @escaping @Sendable () -> Bool
    ) {
        self.speechGate = speechGate
        self.recorded = recorded
        self.stopped = stopped
    }

    /// Judges the sound of `stream` within `range` not judged yet, read back from the recording at once. A chunk that
    /// doesn't follow the one judged last is judged as after silence. Returns whether it judged any: audio the
    /// recording doesn't hold yet stays unjudged.
    mutating func judge(
        _ range: ClosedRange<TimeInterval>, on stream: AudioStream, into evidence: inout LanguageEvidence
    ) async throws -> Bool {
        let chunks = evidence.unjudged(in: range, on: stream)
        guard let first = chunks.first, let last = chunks.last else { return false }
        let size = speechGate.chunkSize
        let chunkSeconds = Double(size) / LanguageIdentification.sampleRate
        let samples = try await recorded(stream, Double(first) * chunkSeconds...Double(last + 1) * chunkSeconds)
        var speech: [Int: Bool] = [:]
        for chunk in chunks where !stopped() {
            let offset = (chunk - first) * size
            guard offset + size <= samples.count else { break }
            if lastJudged[stream] != chunk - 1 { await speechGate.forget(stream) }
            let probability = try await speechGate.speechProbability(
                of: Array(samples[offset..<offset + size]), on: stream)
            lastJudged[stream] = chunk
            speech[chunk] = probability >= LanguageIdentification.speechProbability
        }
        evidence.judge(speech, on: stream)
        return !speech.isEmpty
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

    mutating func heard(_ chunks: Int, sound: Bool, on stream: AudioStream) {
        streams[stream]!.speech.add(chunks, sound: sound)
    }

    mutating func heard(_ words: [TranscribedWord], on stream: AudioStream) {
        streams[stream]!.add(words)
    }

    /// The stretch of `stream` the gate must judge before its guard can be checked, if any.
    func unjudgedGuardStretch(on stream: AudioStream) -> ClosedRange<TimeInterval>? {
        streams[stream]!.unjudgedGuardStretch()
    }

    /// The chunks of `stream` within `range` that are sound the gate hasn't judged, by number.
    func unjudged(in range: ClosedRange<TimeInterval>, on stream: AudioStream) -> [Int] {
        streams[stream]!.speech.unjudged(from: range.lowerBound, to: range.upperBound)
    }

    /// The gate judged each of `stream`'s chunks, by number, speech or not.
    mutating func judge(_ speech: [Int: Bool], on stream: AudioStream) {
        streams[stream]!.speech.judge(speech)
    }

    /// `challenge` with the speech its stretch holds, as judged now.
    func measured(_ challenge: Challenge) -> Challenge {
        var measured = challenge
        measured.speech = streams[challenge.stream]!.speech.speech(
            from: challenge.range.lowerBound, to: challenge.range.upperBound)
        return measured
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
    /// The stream time of the last rejection, if any.
    private(set) var since: TimeInterval?
    /// The speech the stream waits for from `since`.
    private(set) var wait: TimeInterval = 0
    private var rejections = 0

    init(first: TimeInterval) {
        self.first = first
    }

    /// Backs off from `time`, the stream time now. Returns the wait.
    mutating func reject(at time: TimeInterval) -> TimeInterval {
        wait = first * pow(2, Double(min(rejections, 3)))
        rejections += 1
        since = time
        return wait
    }

    /// Whether `speech` holds the wait since the last rejection, or there was none. Sound the gate hasn't judged
    /// counts as speech.
    func isOver(in speech: SpeechTimeline) -> Bool {
        guard let since else { return true }
        return speech.speech(from: since, to: speech.end) >= wait
    }

    /// Whether the speech the gate judged since the last rejection holds the wait, or there was none.
    func isSurelyOver(in speech: SpeechTimeline) -> Bool {
        guard let since else { return true }
        return speech.judgedSpeech(from: since, to: speech.end) >= wait
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

    /// Votes on each chunk of words whose audio the stream has heard, then checks the guard.
    mutating func challenge(reader: TextLanguage, current: Locale) -> LanguageEvidence.Challenge? {
        while pending.count >= TextLanguage.chunkWords, pending[TextLanguage.chunkWords - 1].end <= speech.end {
            let words = pending.prefix(TextLanguage.chunkWords)
            pending.removeFirst(TextLanguage.chunkWords)
            let start = lastChunkEnd ?? max(since, words.first!.start - LanguageIdentification.voteMargin)
            lastChunkEnd = words.last!.end
            let shares = reader.shares(of: words)
            chunks.append((start...words.last!.end, shares))
            if chunks.count > LexicalVote.window { chunks.removeFirst() }
            guard let language = vote.add(shares), voteBackOff.isOver(in: speech) else { continue }
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

    /// The stretch the guard counts words over: the latest `guardWindow` of speech since the stream was last judged,
    /// within `maximumStretch` and up to `guardEnd`, once it holds `guardMinimumSpeech` of speech and the guard doesn't
    /// back off. Sound the gate hasn't judged counts as speech.
    private func guardStretch() -> ClosedRange<TimeInterval>? {
        let end = guardEnd
        guard end > since, guardBackOff.isSurelyOver(in: speech) else { return nil }
        let start = max(
            since, speech.start(ofLast: LanguageIdentification.guardWindow, before: end),
            end - LanguageIdentification.maximumStretch)
        guard speech.speech(from: start, to: end) >= LanguageIdentification.guardMinimumSpeech else { return nil }
        return start...end
    }

    /// The stretch the gate must judge before the guard can be checked, if any: from the guard's first sound the gate
    /// hasn't judged to all the stream heard, so the guard's next seconds, which leave out the latest
    /// `finalizationLag`, are judged with it. None while the latest `guardWindow` of sound holds `guardRate` words per
    /// second of it: speech is never more than sound, so the latest speech holds as many, and the guard can't fire
    /// whatever the gate says.
    ///
    /// Once the guard's wait after a rejection seems over, the sound since the rejection is judged first, latest first
    /// and `guardWindow` at a time, until the speech judged holds the wait: music doesn't count as the
    /// speech it waits for, and a long stretch the transcript kept up with isn't judged for it.
    func unjudgedGuardStretch() -> ClosedRange<TimeInterval>? {
        let end = guardEnd
        guard end > since else { return nil }
        let soundStart = max(
            since, speech.start(ofLastSound: LanguageIdentification.guardWindow, before: end),
            end - LanguageIdentification.maximumStretch)
        let sound = speech.sound(from: soundStart, to: end)
        guard Double(count(in: soundStart...end)) < LanguageIdentification.guardRate * sound,
            guardBackOff.isOver(in: speech)
        else { return nil }
        if let rejected = guardBackOff.since, !guardBackOff.isSurelyOver(in: speech),
            let last = speech.lastUnjudgedEnd(from: rejected, to: end)
        {
            return max(rejected, last - LanguageIdentification.guardWindow)...speech.end
        }
        guard let stretch = guardStretch(), let first = speech.firstUnjudged(from: stretch.lowerBound, to: end)
        else { return nil }
        return first...speech.end
    }

    /// Where the guard's stretch ends: the words of the last `finalizationLag` of audio may not be final yet, so that
    /// audio is left out unless words already reach into it.
    private var guardEnd: TimeInterval {
        min(speech.end, max(wordEnds.last ?? 0, speech.end - LanguageIdentification.finalizationLag))
    }

    /// The guard's challenge, if the latest speech, all of it judged by the gate, holds too few words.
    private func rateGuard(reader: TextLanguage, current: Locale) -> LanguageEvidence.Challenge? {
        guard let stretch = guardStretch(),
            speech.firstUnjudged(from: stretch.lowerBound, to: stretch.upperBound) == nil
        else { return nil }
        let words = count(in: stretch)
        let seconds = speech.speech(from: stretch.lowerBound, to: stretch.upperBound)
        guard Double(words) / seconds < LanguageIdentification.guardRate else { return nil }
        return challenge(
            .rateGuard, for: reader.candidates.filter { !reader.same($0, current) }, over: stretch,
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
        case .vote: return voteBackOff.reject(at: speech.end)
        case .rateGuard: return guardBackOff.reject(at: speech.end)
        }
    }
}

/// A stream's chunks from its start: silence, sound the speech gate hasn't judged, or judged speech or not. Sound the
/// gate hasn't judged counts as speech.
struct SpeechTimeline {
    private enum Chunk { case silence, sound, speech, notSpeech }

    let chunkSeconds: TimeInterval
    private var chunks: [Chunk] = []
    /// The speech in the stream's first n chunks, at n.
    private var cumulative: [TimeInterval] = [0]
    /// The sound in the stream's first n chunks, at n.
    private var soundCumulative: [TimeInterval] = [0]
    /// The sound the gate hasn't judged in the stream's first n chunks, at n.
    private var unjudgedCumulative: [TimeInterval] = [0]

    init(chunkSeconds: TimeInterval) {
        self.chunkSeconds = chunkSeconds
    }

    mutating func add(_ count: Int, sound: Bool) {
        for _ in 0..<count {
            chunks.append(sound ? .sound : .silence)
            cumulative.append(cumulative.last! + (sound ? chunkSeconds : 0))
            soundCumulative.append(soundCumulative.last! + (sound ? chunkSeconds : 0))
            unjudgedCumulative.append(unjudgedCumulative.last! + (sound ? chunkSeconds : 0))
        }
    }

    /// Sets the gate's judgement of each chunk, by number, it hasn't judged yet.
    mutating func judge(_ speech: [Int: Bool]) {
        guard let first = speech.keys.min() else { return }
        for (chunk, isSpeech) in speech where chunks[chunk] == .sound {
            chunks[chunk] = isSpeech ? .speech : .notSpeech
        }
        for chunk in first..<chunks.count {
            let counts = chunks[chunk] == .sound || chunks[chunk] == .speech
            cumulative[chunk + 1] = cumulative[chunk] + (counts ? chunkSeconds : 0)
            unjudgedCumulative[chunk + 1] = unjudgedCumulative[chunk] + (chunks[chunk] == .sound ? chunkSeconds : 0)
        }
    }

    /// The speech the gate judged from `start` to `end`, leaving out the sound it hasn't judged.
    func judgedSpeech(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        speech(from: start, to: end) - (unjudgedCumulative[index(end)] - unjudgedCumulative[index(start)])
    }

    /// Where the last chunk from `start` to `end` that is sound the gate hasn't judged ends, if any.
    func lastUnjudgedEnd(from start: TimeInterval, to end: TimeInterval) -> TimeInterval? {
        (index(start)..<index(end)).last { chunks[$0] == .sound }.map { Double($0 + 1) * chunkSeconds }
    }

    /// The stream time heard up to.
    var end: TimeInterval { Double(chunks.count) * chunkSeconds }

    func speech(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        cumulative[index(end)] - cumulative[index(start)]
    }

    func sound(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        soundCumulative[index(end)] - soundCumulative[index(start)]
    }

    /// The chunks from `start` to `end` that are sound the gate hasn't judged, by number.
    func unjudged(from start: TimeInterval, to end: TimeInterval) -> [Int] {
        (index(start)..<index(end)).filter { chunks[$0] == .sound }
    }

    /// Where the first chunk from `start` to `end` that is sound the gate hasn't judged starts, if any.
    func firstUnjudged(from start: TimeInterval, to end: TimeInterval) -> TimeInterval? {
        (index(start)..<index(end)).first { chunks[$0] == .sound }.map { Double($0) * chunkSeconds }
    }

    /// The time from which the stream holds `seconds` of speech up to `end`, or its start if it holds less.
    func start(ofLast seconds: TimeInterval, before end: TimeInterval) -> TimeInterval {
        Self.start(ofLast: seconds, before: index(end), in: cumulative, chunkSeconds: chunkSeconds)
    }

    /// The time from which the stream holds `seconds` of sound up to `end`, or its start if it holds less.
    func start(ofLastSound seconds: TimeInterval, before end: TimeInterval) -> TimeInterval {
        Self.start(ofLast: seconds, before: index(end), in: soundCumulative, chunkSeconds: chunkSeconds)
    }

    private static func start(
        ofLast seconds: TimeInterval, before end: Int, in cumulative: [TimeInterval], chunkSeconds: TimeInterval
    ) -> TimeInterval {
        let target = cumulative[end] - seconds
        guard target > 0 else { return 0 }
        let position = cumulative.lastIndex { $0 <= target } ?? 0
        return Double(position) * chunkSeconds
    }

    private func index(_ time: TimeInterval) -> Int {
        min(max(0, Int((time / chunkSeconds).rounded())), chunks.count)
    }
}
