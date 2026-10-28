import CarbonCore
import Foundation
import Testing

struct TranscriptBuilderTests {
    @Test func theMeThemFallbackOfARealMeetingMatchesThePrototypeSampleByteForByte() throws {
        let me = try words(fixture: "ami-ES2004a-me-words")
        let them = try words(fixture: "ami-ES2004a-them-words")
        let sample = try String(contentsOf: fixtureURL("ami-ES2004a-fallback", extension: "md"), encoding: .utf8)
        let expected = try #require(sample.range(of: "## Transcript\n")).lowerBound

        let body = TranscriptBuilder.body(TranscriptBuilder.turns(me: me, them: them))

        #expect(body == String(sample[expected...]))
    }

    @Test func theDiarizedTranscriptOfARealMeetingMatchesThePrototypeSampleByteForByte() throws {
        let me = try words(fixture: "ami-ES2004a-me-words")
        let them = try words(fixture: "ami-ES2004a-them-words")
        let diarization = try JSONDecoder().decode(
            Diarization.self, from: Data(contentsOf: fixtureURL("ami-ES2004a-them-diarization", extension: "json")))
        let sample = try String(contentsOf: fixtureURL("ami-ES2004a-diarized", extension: "md"), encoding: .utf8)
        let expected = try #require(sample.range(of: "## Transcript\n")).lowerBound

        let body = TranscriptBuilder.body(TranscriptBuilder.turns(me: me, them: them, diarization: diarization))

        #expect(body == String(sample[expected...]))
    }

    @Test func recognisedTextNeverTurnsIntoMarkupAndEachTurnStartsWithACapital() {
        let me = spoken([("use", 1), ("*args", 1.3), ("and", 1.6), ("[x]_<tag>", 1.9), ("`code`\\.", 2.2)])

        let body = TranscriptBuilder.body(TranscriptBuilder.turns(me: me, them: []))

        #expect(body == """
            ## Transcript

            **Me** [0:01] Use \\*args and \\[x\\]\\_\\<tag\\> \\`code\\`\\\\.

            """)
    }

    @Test func pastAnHourTimestampsGainAnHourAndAreTruncatedToTheSecond() {
        let me = spoken([("Still", 3_725.99), ("here.", 3_726.2)])
        let them = spoken([("Yes.", 59.999)])

        let body = TranscriptBuilder.body(TranscriptBuilder.turns(me: me, them: them))

        #expect(body == """
            ## Transcript

            **Them** [0:59] Yes.

            **Me** [1:02:05] Still here.

            """)
    }

    @Test func overlappingTalkInterleavesBySentenceWithMeFirstOnATie() {
        let me = spoken([("okay…", 5), ("right", 6.5), ("so", 6.8)])
        let them = spoken([("we", 5), ("start", 5.3), ("now", 7.5), ("and", 7.8), ("then", 8.1), ("stop.", 8.4)])

        let body = TranscriptBuilder.body(TranscriptBuilder.turns(me: me, them: them))

        #expect(body == """
            ## Transcript

            **Me** [0:05] Okay…

            **Them** [0:05] We start

            **Me** [0:06] Right so

            **Them** [0:07] Now and then stop.

            """)
    }

    @Test func eachThemWordTakesTheMostOverlappingSegmentElseTheNearestWithinASecondElseThePreviousSpeaker() {
        let them = spoken([
            ("first", 0.2),  // nothing within 1 s: the next attributed word's Speaker
            ("hello", 2),  // overlaps S7 by 0.2 s and S3 by 0.1 s
            ("there.", 3.6),  // 0.95 s after S3 ends
            ("so", 6),  // inside S9, a cluster first heard third
            ("well", 9),  // 2.5 s from any segment: the previous word's Speaker
            ("named.", 11),  // S3 again, named by the caller
        ])
        let diarization = Diarization(
            segments: [
                .init(start: 1.5, end: 2.2, cluster: "S7"),
                .init(start: 2.2, end: 2.5, cluster: "S3"),
                .init(start: 2.5, end: 2.8, cluster: "S3"),
                .init(start: 5.5, end: 6.5, cluster: "S9"),
                .init(start: 10.9, end: 11.4, cluster: "S3"),
            ],
            clusters: [])

        let body = TranscriptBuilder.body(
            TranscriptBuilder.turns(me: [], them: them, diarization: diarization, labels: ["B": "Sam Rivera"]))

        #expect(TranscriptBuilder.clusterLetters(them: them, diarization: diarization) == ["S7": "A", "S3": "B", "S9": "C"])
        #expect(body == """
            ## Transcript

            **Speaker A** [0:00] First hello

            **Sam Rivera** [0:03] There.

            **Speaker C** [0:06] So well

            **Sam Rivera** [0:11] Named.

            """)
    }

    @Test func everyTurnWrittenForARealMeetingReadsBackThroughTheHeaderParser() throws {
        let me = try words(fixture: "ami-ES2004a-me-words")
        let them = try words(fixture: "ami-ES2004a-them-words")

        let read = TranscriptBuilder.turns(inMarkdown: TranscriptBuilder.body(TranscriptBuilder.turns(me: me, them: them)))

        #expect(read.count == 120)
        #expect(read.last == Turn(speaker: "Them", start: 1_048, text: "Yep."))
    }

    @Test func aPersonsNameBecomesALabelWithoutMarkupAndNeverAsAReservedOne() {
        #expect(TranscriptBuilder.label(forName: "Sam [Rivera]*") == "Sam Rivera")
        #expect(TranscriptBuilder.label(forName: "Priya\nNair") == "Priya Nair")
        #expect(TranscriptBuilder.label(forName: "Me") == nil)
        #expect(TranscriptBuilder.label(forName: " them ") == nil)
        #expect(TranscriptBuilder.label(forName: "**") == nil)
    }
}

private func spoken(_ words: [(String, TimeInterval)]) -> [TranscribedWord] {
    words.map { TranscribedWord(text: $0.0, start: $0.1, end: $0.1 + 0.3) }
}
