import Foundation
import CarbonCore
import Testing

struct TranscriptParserTests {
    func turns(_ markdown: String) -> [String] {
        TranscriptBuilder.turns(inMarkdown: markdown).map { "\($0.speaker) · \($0.elapsed) · \($0.text)" }
    }

    @Test func turnsComeFromTheTranscriptSectionOnly() {
        let markdown = """
            ---
            title: Kickoff
            ---

            ## Summary

            ### Key points

            - **Me** [0:00] is not a Turn here.

            ## Transcript

            **Me** [0:00] Hello everyone.

            **Speaker A** [0:19] Hi, can you hear me?

            **Sam Rivera** [1:02:10] Let's wrap up.
            """
        #expect(turns(markdown) == [
            "Me · 0:00 · Hello everyone.",
            "Speaker A · 0:19 · Hi, can you hear me?",
            "Sam Rivera · 1:02:10 · Let's wrap up.",
        ])
    }

    @Test func aLineWithoutAHeaderContinuesTheTurnAboveIt() {
        let markdown = """
            ## Transcript

            Notes the person typed before the first Turn.

            **Me** [0:00] First thought.
            A line the person added.

            **Them** [0:12] **Bold** words [0:13] stay text.
            """
        #expect(turns(markdown) == [
            "Me · 0:00 · First thought.\nA line the person added.",
            "Them · 0:12 · **Bold** words [0:13] stay text.",
        ])
    }

    @Test func aHeaderMustStartTheLine() {
        #expect(turns("## Transcript\n\n **Me** [0:00] Indented.\n").isEmpty)
    }

    @Test func voiceOverHearsATurnStartAsADurationNotAClockTime() {
        let english = Locale(identifier: "en_US")
        let spoken = TranscriptBuilder.turns(inMarkdown: """
            ## Transcript

            **Me** [0:00] Hello.

            **Speaker A** [0:19] Hi.

            **Me** [1:00] Agenda.

            **Sam Rivera** [1:02:10] Let's wrap up.
            """).map { $0.spokenElapsed(locale: english) }
        #expect(spoken == ["0 seconds", "19 seconds", "1 minute", "1 hour, 2 minutes, 10 seconds"])
    }
}
