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

    @Test func turnHeadersAreReadBackWithTheAnchoredPattern() {
        #expect(TranscriptBuilder.header(#"**Sam Rivera** [1:02:05] Use \*args, ok."#)
            == TurnHeader(speaker: "Sam Rivera", start: 3_725, text: #"Use \*args, ok."#))
        #expect(TranscriptBuilder.header("**Me** [0:10] Hello.") == TurnHeader(speaker: "Me", start: 10, text: "Hello."))
        #expect(TranscriptBuilder.header("Notes: **Me** [0:10] Hello.") == nil)
        #expect(TranscriptBuilder.header("**Me** [0:1] Hello.") == nil)
        #expect(TranscriptBuilder.header("**Me**[0:10] Hello.") == nil)
    }

    @Test func everyTurnOfTheRealSampleReadsBackAsAHeader() throws {
        let sample = try String(contentsOf: fixtureURL("ami-ES2004a-fallback", extension: "md"), encoding: .utf8)
        let headers = sample.split(separator: "\n").compactMap(TranscriptBuilder.header)

        #expect(headers.count == 120)
        #expect(headers.last == TurnHeader(speaker: "Them", start: 1_048, text: "Yep."))
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
