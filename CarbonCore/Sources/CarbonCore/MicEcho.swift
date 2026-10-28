import Foundation

/// Finds the call heard back through the mic when sound plays on speakers, as "Hybrid-room diarization" measured
/// it, so a shared mic's split leaves the call's voices out.
enum MicEcho {
    /// Echo clusters sat at ≤ 0.134 from the call's voice, real people in the room at ≥ 0.329.
    static let echoDistance = 0.25
    /// Echo clusters overlapped Them speech ≥ 82 % of the time, real people in the room ≤ 19 %.
    static let echoOverlap = 0.5

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
