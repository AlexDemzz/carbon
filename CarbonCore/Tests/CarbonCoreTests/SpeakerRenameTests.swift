import CarbonCore
import Foundation
import Testing

/// Naming a Speaker: only that Speaker's Turn headers change in the file, and `meetings.json` records the name.
@MainActor
struct SpeakerRenameTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-28T09:00:00Z"))
    let newYork = TimeZone(identifier: "America/New_York")!
    let id = UUID(uuidString: "6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61")!

    func makeLibrary() -> Library {
        let clock = clock
        return Library(folder: folder.url, supportFolder: support.url, now: { clock.now }, moveToTrash: { _ in })
    }

    func meeting(
        participants: [Participant], speakers: [MeetingIndex.Speaker], kind: FinishedMeeting.TranscriptKind = .speakers
    ) -> FinishedMeeting {
        FinishedMeeting(
            id: id, title: "Remote control kickoff", start: date("2026-10-27T14:00:00Z"),
            end: date("2026-10-27T14:17:29Z"), timeZone: newYork, language: Locale(identifier: "en_US"),
            provider: "Google Meet", participants: participants, transcriptKind: kind, speakers: speakers)
    }

    func speaker(_ letter: String, seconds: Double = 60) -> MeetingIndex.Speaker {
        MeetingIndex.Speaker(label: "Speaker \(letter)", cluster: letter, speechSeconds: seconds)
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func entry(_ library: Library) throws -> MeetingIndex.Entry {
        try #require(try library.loadIndex().meetings.first { $0.id == id })
    }

    /// The fixture's body: everything after its frontmatter.
    func body(ofFixture name: String) throws -> String {
        let sample = try String(contentsOf: fixtureURL(name, extension: "md"), encoding: .utf8)
        let end = try #require(sample.range(of: "\n---\n\n"))
        return String(sample[end.upperBound...])
    }

    let frontmatter = """
        ---
        provider: Google Meet
        id: 6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61
        date: 2026-10-27T10:00:00-04:00
        title: Remote control kickoff
        duration: 17:29
        language: en-US
        participants:
          - Sam Rivera <sam@example.com>
        ---


        """

    @Test func namingSpeakerBMatchesThePrototypesRenamedSample() throws {
        let library = makeLibrary()
        let url = try library.create(
            meeting(
                participants: [Participant(name: "Sam Rivera", email: "sam@example.com")],
                speakers: ["A", "B", "C"].map { speaker($0) }),
            transcript: body(ofFixture: "ami-ES2004a-diarized"))

        try library.renameSpeaker(id, label: "Speaker B", name: "Sam Rivera")

        #expect(try read(url) == frontmatter + body(ofFixture: "ami-ES2004a-renamed"))
        #expect(try entry(library).speakers == [
            speaker("A"),
            MeetingIndex.Speaker(label: "Sam Rivera", cluster: "B", name: "Sam Rivera", match: .user, speechSeconds: 60),
            speaker("C"),
        ])
        #expect(try entry(library).participants == [Participant(name: "Sam Rivera", email: "sam@example.com")])
        #expect(try !library.hasLocalEdit(id))
    }
}

extension SpeakerRenameTests {
    var shortBody: String {
        """
        ## Transcript

        **Me** [0:10] Hi, Speaker B.

        **Speaker A** [0:24] Hello.

        **Speaker B** [0:30] Thanks.

        **Speaker AB** [0:40] Not a Speaker of this Meeting.

        """
    }

    @discardableResult
    func createdShort(_ library: Library, participants: [Participant] = [Participant(name: "Sam Rivera")]) throws -> URL {
        try library.create(
            meeting(participants: participants, speakers: [speaker("A"), speaker("B")]), transcript: shortBody)
    }

    @Test func aRenameAfterALocalEditChangesOnlyTheHeadersThatStillMatch() throws {
        let library = makeLibrary()
        let url = try createdShort(library)
        let edited = try read(url)
            .replacingOccurrences(
                of: "**Speaker B** [0:30] Thanks.",
                with: "**Speaker B** [0:30] Thanks, Speaker B.\n**Speaker B** said this, by hand.")
            .replacingOccurrences(of: "Hello.", with: "Hello. **Speaker B** [0:31] quoted in the text.")
        try edited.write(to: url, atomically: true, encoding: .utf8)

        try library.renameSpeaker(id, label: "Speaker B", name: "Sam Rivera")

        #expect(try read(url) == edited.replacingOccurrences(
            of: "\n**Speaker B** [0:30] Thanks, Speaker B.", with: "\n**Sam Rivera** [0:30] Thanks, Speaker B."))
        #expect(try library.hasLocalEdit(id), "the file stays a Local Edit")
    }

    @Test func aRenameKeepsWindowsLineEndings() throws {
        let library = makeLibrary()
        let url = try createdShort(library)
        let crlf = try read(url).replacingOccurrences(of: "\n", with: "\r\n")
        try crlf.write(to: url, atomically: true, encoding: .utf8)

        try library.renameSpeaker(id, label: "Speaker A", name: "Sam Rivera")

        #expect(try read(url) == crlf.replacingOccurrences(of: "**Speaker A** [0:24]", with: "**Sam Rivera** [0:24]"))
    }

    @Test func namesDropMarkupCharactersAndLineBreaks() throws {
        let library = makeLibrary()
        let url = try createdShort(library)

        try library.renameSpeaker(id, label: "Speaker A", name: " *Sam* [Rivera]\nJr ")

        #expect(try read(url).contains("\n**Sam Rivera Jr** [0:24] Hello.\n"))
        #expect(try entry(library).speakers[0].name == "Sam Rivera Jr")
    }

    @Test(arguments: ["Me", "them", "**", " \n"])
    func reservedOrEmptyNamesAreRefusedAndChangeNothing(name: String) throws {
        let library = makeLibrary()
        let url = try createdShort(library)
        let before = try read(url)

        #expect(throws: LibraryError.invalidSpeakerName) {
            try library.renameSpeaker(id, label: "Speaker A", name: name)
        }
        #expect(try read(url) == before)
        #expect(try entry(library).speakers == [speaker("A"), speaker("B")])
    }

    @Test func aNameNotYetAParticipantJoinsTheFrontmatterAndTheIndex() throws {
        let library = makeLibrary()
        let url = try createdShort(library, participants: [Participant(name: "Sam Rivera", email: "sam@example.com")])

        try library.renameSpeaker(id, label: "Speaker A", name: "Priya: Nair")

        #expect(try read(url).contains("""
            participants:
              - Sam Rivera <sam@example.com>
              - "Priya: Nair"
            ---
            """))
        #expect(try entry(library).participants == [
            Participant(name: "Sam Rivera", email: "sam@example.com"), Participant(name: "Priya: Nair"),
        ])
        #expect(try !library.hasLocalEdit(id))
    }

    @Test func theFirstParticipantReplacesAnEmptyList() throws {
        let library = makeLibrary()
        let url = try createdShort(library, participants: [])

        try library.renameSpeaker(id, label: "Speaker A", name: "Priya Nair")

        #expect(try read(url).contains("\nlanguage: en-US\nparticipants:\n  - Priya Nair\n---\n"))
        #expect(try entry(library).participants == [Participant(name: "Priya Nair")])
    }

    @Test func aParticipantAlreadyListedIsNotAddedAgain() throws {
        let library = makeLibrary()
        let url = try createdShort(library, participants: [Participant(name: "Sam Rivera", email: "sam@example.com")])
        try library.renameSpeaker(id, label: "Speaker A", name: "sam rivera")

        #expect(try entry(library).participants == [Participant(name: "Sam Rivera", email: "sam@example.com")])
        #expect(try read(url).contains("participants:\n  - Sam Rivera <sam@example.com>\n---\n"))
    }

    @Test func renamingANamedSpeakerAgainWorksTheSameWay() throws {
        let library = makeLibrary()
        let url = try createdShort(library)
        try library.renameSpeaker(id, label: "Speaker B", name: "Sam Rivera")

        try library.renameSpeaker(id, label: "Sam Rivera", name: "Jordan Lee")

        #expect(try read(url).contains("\n**Speaker A** [0:24] Hello.\n\n**Jordan Lee** [0:30] Thanks.\n"))
        #expect(try entry(library).speakers[1] == MeetingIndex.Speaker(
            label: "Jordan Lee", cluster: "B", name: "Jordan Lee", match: .user, speechSeconds: 60))
        #expect(try entry(library).participants.map(\.name) == ["Sam Rivera", "Jordan Lee"])
    }

    @Test func twoSpeakersNamedTheSameShareTheNameAndThenRenameTogether() throws {
        let library = makeLibrary()
        let url = try createdShort(library)
        try library.renameSpeaker(id, label: "Speaker A", name: "Sam Rivera")
        try library.renameSpeaker(id, label: "Speaker B", name: "Sam Rivera")
        #expect(try read(url).contains("\n**Sam Rivera** [0:24] Hello.\n\n**Sam Rivera** [0:30] Thanks.\n"))

        try library.renameSpeaker(id, label: "Sam Rivera", name: "Priya Nair")

        #expect(try read(url).contains("\n**Priya Nair** [0:24] Hello.\n\n**Priya Nair** [0:30] Thanks.\n"))
        #expect(try entry(library).speakers.map(\.label) == ["Priya Nair", "Priya Nair"])
    }

    @Test func inAFallbackFileNamingThemRecordsAThemSpeaker() throws {
        let library = makeLibrary()
        let url = try library.create(
            meeting(participants: [], speakers: [], kind: .fallback),
            transcript: "## Transcript\n\n**Me** [0:10] Hi.\n\n**Them** [0:12] Hello.\n")

        try library.renameSpeaker(id, label: "Them", name: "Sam Rivera")

        #expect(try read(url).hasSuffix("## Transcript\n\n**Me** [0:10] Hi.\n\n**Sam Rivera** [0:12] Hello.\n"))
        #expect(try entry(library).speakers == [MeetingIndex.Speaker(
            label: "Sam Rivera", cluster: "Them", name: "Sam Rivera", match: .user, speechSeconds: 0)])
    }

    @Test func inAOneToOneFallbackFileTheAttendeeLabelIsTheThemSpeaker() throws {
        let library = makeLibrary()
        try library.create(
            meeting(participants: [Participant(name: "Sam Rivera")], speakers: [], kind: .fallback),
            transcript: "## Transcript\n\n**Me** [0:10] Hi.\n\n**Sam Rivera** [0:12] Hello.\n")

        try library.renameSpeaker(id, label: "Sam Rivera", name: "Samuel Rivera")
        try library.renameSpeaker(id, label: "Samuel Rivera", name: "Sam R")

        #expect(try entry(library).speakers == [MeetingIndex.Speaker(
            label: "Sam R", cluster: "Them", name: "Sam R", match: .user, speechSeconds: 0)])
    }

    @Test func aSpeakerIsUnnamedUntilSomeoneNamesIt() throws {
        let library = makeLibrary()
        try createdShort(library)
        #expect(library.meetings[0].isUnnamedSpeaker("Speaker A"))
        #expect(!library.meetings[0].isUnnamedSpeaker("Me"))

        try library.renameSpeaker(id, label: "Speaker A", name: "Sam Rivera")

        #expect(!library.meetings[0].isUnnamedSpeaker("Sam Rivera"))
        #expect(library.meetings[0].isUnnamedSpeaker("Speaker B"))
    }

    @Test func themIsUnnamedInAFallbackFile() throws {
        let library = makeLibrary()
        try library.create(
            meeting(participants: [], speakers: [], kind: .fallback), transcript: "## Transcript\n\n**Them** [0:12] Hello.\n")

        #expect(library.meetings[0].isUnnamedSpeaker("Them"))
    }

    @Test func meCannotBeRenamed() throws {
        let library = makeLibrary()
        let url = try createdShort(library)
        let before = try read(url)

        #expect(throws: LibraryError.invalidSpeakerName) {
            try library.renameSpeaker(id, label: "Me", name: "Alex")
        }
        #expect(try read(url) == before)
    }
}
