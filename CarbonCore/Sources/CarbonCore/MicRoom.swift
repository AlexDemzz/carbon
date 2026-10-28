import Foundation

/// Tells a meeting room, where several people share the Mac's mic, from one person at the mic, as
/// "Hybrid-room diarization" measured it. The call's echo is left out before the room is judged: otherwise a
/// solo call on speakers looks like a room.
enum MicRoom {
    /// Echo clusters sat at ≤ 0.134 from the call's voice, real people in the room at ≥ 0.329.
    static let echoDistance = 0.25
    /// Echo clusters overlapped Them speech ≥ 82 % of the time, real people in the room ≤ 19 %.
    static let echoOverlap = 0.5
    /// Speech each of at least 2 voices needs for the mic to count as a room.
    static let roomSpeechSeconds = 20.0

    private typealias Span = (start: TimeInterval, end: TimeInterval)

    /// The Me clusters that are the call heard back through the mic: close to a Them voice, or mostly spoken
    /// over Them speech. Them speech is the Them diarization's, else the Them words' when it failed.
    static func echo(in me: Diarization, them: Diarization?, themWords: [TranscribedWord]) -> Set<String> {
        let themSpeech = merged(them.map { $0.segments.map { ($0.start, $0.end) } } ?? themWords.map { ($0.start, $0.end) })
        let themVoices = them?.clusters.map(\.centroid) ?? []
        return Set(me.clusters.filter { cluster in
            if themVoices.contains(where: {
                VoicePrintMatcher.cosineDistance(cluster.centroid, $0) <= echoDistance
            }) { return true }
            let speech = merged(me.segments.filter { $0.cluster == cluster.id }.map { ($0.start, $0.end) })
            let seconds = speech.reduce(0) { $0 + $1.end - $1.start }
            return seconds > 0 && overlap(speech, themSpeech) / seconds > echoOverlap
        }.map(\.id))
    }

    /// At least 2 voices other than the echo each spoke `roomSpeechSeconds`.
    static func isRoom(_ me: Diarization, echo: Set<String>) -> Bool {
        me.clusters.filter { !echo.contains($0.id) && $0.speechSeconds >= roomSpeechSeconds }.count >= 2
    }

    /// The voice of the one person at the mic, which is the owner's: the main voice other than the echo, when it
    /// spoke enough to be remembered.
    static func owner(_ me: Diarization, echo: Set<String>) -> Diarization.Cluster? {
        me.clusters.filter { !echo.contains($0.id) }.max { $0.speechSeconds < $1.speechSeconds }
            .flatMap { $0.speechSeconds >= VoicePrintMatcher.minimumSpeechSeconds ? $0 : nil }
    }

    /// Sorted, disjoint intervals covering the same time.
    private static func merged(_ intervals: [Span]) -> [Span] {
        var merged: [Span] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) where interval.end > interval.start {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// Seconds two sets of merged intervals share.
    private static func overlap(_ a: [Span], _ b: [Span]) -> TimeInterval {
        a.reduce(0) { total, x in
            total + b.reduce(0) { $0 + max(0, min(x.end, $1.end) - max(x.start, $1.start)) }
        }
    }
}
