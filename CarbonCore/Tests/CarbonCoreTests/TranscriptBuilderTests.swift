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

    @Test func wordsThatFinishASpeakersSentenceAcrossTheSegmentBoundaryStayWithThatSpeaker() {
        let them = timed([
            ("c'est", 154.9, 155.1), ("une", 155.1, 155.25), ("bonne", 155.25, 155.58),
            ("idée.", 155.58, 155.88),  // 0.11 s in A, 0.19 s in B
            ("Donc", 155.88, 156.1), ("c'est", 156.1, 156.3), ("parti.", 156.3, 156.7),
        ])
        let diarization = Diarization(
            segments: [.init(start: 153, end: 155.69, cluster: "S1"), .init(start: 155.69, end: 158, cluster: "S2")],
            clusters: [])

        let body = TranscriptBuilder.body(TranscriptBuilder.turns(me: [], them: them, diarization: diarization))

        #expect(body == """
            ## Transcript

            **Speaker A** [2:34] C'est une bonne idée.

            **Speaker B** [2:35] Donc c'est parti.

            """)
    }

    @Test func wordsThatStartTheNextSpeakersSentenceAcrossTheSegmentBoundaryGoToThatSpeaker() {
        let them = timed([
            ("c'est", 10, 10.3), ("actuellement.", 10.3, 11),
            ("Ouais", 11, 11.5),  // 0.3 s in A, 0.2 s in B
            ("c'est", 11.5, 11.7), ("quoi", 11.7, 11.9), ("?", 11.9, 12),
        ])
        let diarization = Diarization(
            segments: [.init(start: 8, end: 11.3, cluster: "S1"), .init(start: 11.3, end: 14, cluster: "S2")],
            clusters: [])

        let body = TranscriptBuilder.body(TranscriptBuilder.turns(me: [], them: them, diarization: diarization))

        #expect(body == """
            ## Transcript

            **Speaker A** [0:10] C'est actuellement.

            **Speaker B** [0:11] Ouais c'est quoi ?

            """)
    }

    @Test func aSpeakerChangeStaysPutAtASentenceEndOrWhenTheSentenceEndIsOverASecondAway() {
        let them = timed([
            ("Oui.", 1, 1.4), ("D'accord", 1.4, 1.8),  // already at a sentence end
            ("c'est", 4, 4.2), ("une", 4.2, 4.35), ("bonne", 4.35, 4.68),
            ("idée.", 4.68, 5.8),  // ends a sentence 1.12 s after the change
            ("Donc", 5.8, 6), ("voilà.", 6, 6.4),
        ])
        let diarization = Diarization(
            segments: [
                .init(start: 0, end: 1.5, cluster: "S1"), .init(start: 1.5, end: 3, cluster: "S2"),
                .init(start: 3.5, end: 4.79, cluster: "S1"), .init(start: 4.79, end: 7, cluster: "S2"),
            ],
            clusters: [])

        let body = TranscriptBuilder.body(TranscriptBuilder.turns(me: [], them: them, diarization: diarization))

        #expect(body == """
            ## Transcript

            **Speaker A** [0:01] Oui.

            **Speaker B** [0:01] D'accord

            **Speaker A** [0:04] C'est une bonne

            **Speaker B** [0:04] Idée. Donc voilà.

            """)
    }

    @Test func anEchoClusterLosesOnlyTheWordsHeardWhileThemSpeaksTheRestGoesToTheSpeakerNearby() {
        let me = timed([
            ("Hi.", 1, 1.4),
            ("can", 5, 5.3), ("you", 5.3, 5.5), ("hear", 5.5, 5.8), ("me?", 5.8, 6.5),
            ("Hello?", 6.7, 6.9),  // 0.2 s after Them stops: still the call, heard late
            ("Sorry,", 9.8, 10.1), ("go", 10.1, 10.3), ("ahead.", 10.3, 10.6),  // talking over a silent call
            ("Sure.", 13.2, 13.6),
        ])
        let them = timed([("Can", 5, 5.3), ("you", 5.3, 5.5), ("hear", 5.5, 5.8), ("me?", 5.8, 6.5)])
        let mic = Diarization(
            segments: [
                .init(start: 0.5, end: 1.5, cluster: "S1"), .init(start: 4, end: 10.4, cluster: "S2"),
                .init(start: 10.4, end: 15, cluster: "S3"),
            ],
            clusters: [])

        let body = TranscriptBuilder.body(
            TranscriptBuilder.turns(me: me, them: them, split: .init(me: mic, echo: ["S2"])))

        #expect(body == """
            ## Transcript

            **Speaker A** [0:01] Hi.

            **Them** [0:05] Can you hear me?

            **Speaker B** [0:09] Sorry, go ahead. Sure.

            """)
    }

    @Test func anEchoWordEndingASentenceIsNotSnappedOntoTheSpeakerBeforeIt() {
        let me = timed([
            ("I", 1, 1.2), ("think", 1.2, 1.5),
            ("Hello?", 1.6, 2),  // the call heard back, right after the boundary
            ("Are", 2.1, 2.3), ("you", 2.3, 2.5), ("there?", 2.5, 2.9),
        ])
        let them = timed([("Hello?", 1.6, 2), ("Are", 2.1, 2.3), ("you", 2.3, 2.5), ("there?", 2.5, 2.9)])
        let mic = Diarization(
            segments: [.init(start: 0.5, end: 1.55, cluster: "S1"), .init(start: 1.55, end: 3, cluster: "S2")],
            clusters: [])

        let body = TranscriptBuilder.body(
            TranscriptBuilder.turns(me: me, them: them, split: .init(me: mic, echo: ["S2"])))

        #expect(body == """
            ## Transcript

            **Speaker A** [0:01] I think

            **Them** [0:01] Hello? Are you there?

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

private func timed(_ words: [(String, TimeInterval, TimeInterval)]) -> [TranscribedWord] {
    words.map { TranscribedWord(text: $0.0, start: $0.1, end: $0.2) }
}
