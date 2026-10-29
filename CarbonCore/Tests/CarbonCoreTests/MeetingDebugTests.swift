import CarbonCore
import Foundation
import Testing

struct MeetingDebugTests {
    @Test func everyWordShowsTheSpeakerItIsWrittenAsOrWhyItWasLeftOut() {
        let me = [
            TranscribedWord(text: "Hi.", start: 1, end: 1.4),
            TranscribedWord(text: "Hello?", start: 5, end: 5.6),
            TranscribedWord(text: "Sorry.", start: 9.8, end: 10.4),
        ]
        let them = [TranscribedWord(text: "Hello?", start: 5, end: 5.6)]
        let mic = Diarization(
            segments: [
                .init(start: 0.5, end: 1.5, cluster: "S1"), .init(start: 4, end: 10.2, cluster: "S2"),
                .init(start: 10.2, end: 15, cluster: "S3"),
            ],
            clusters: [])
        let call = Diarization(segments: [.init(start: 4.8, end: 6, cluster: "S1")], clusters: [])

        let debug = MeetingDebug(
            me: me, them: them, split: .init(me: mic, them: call, echo: ["S2"]), labels: ["A": "Me"])

        #expect(debug.me == MeetingDebug.Stream(
            segments: mic.segments, echo: ["S2"],
            words: [
                .init(text: "Hi.", start: 1, end: 1.4, cluster: "S1", speaker: "Me"),
                .init(
                    text: "Hello?", start: 5, end: 5.6, cluster: "S2",
                    dropped: .init(reason: .echo, themSpeech: .init(start: 4.8, end: 6))),
                .init(text: "Sorry.", start: 9.8, end: 10.4, cluster: "S3", speaker: "Speaker C"),
            ]))
        #expect(debug.them == MeetingDebug.Stream(
            segments: call.segments, echo: [],
            words: [.init(text: "Hello?", start: 5, end: 5.6, cluster: "S1", speaker: "Speaker B")]))
    }
}
