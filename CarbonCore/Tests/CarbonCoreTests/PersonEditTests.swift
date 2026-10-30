import CarbonCore
import Foundation
import Testing

/// Editing a person's name and email: a Participant from its token, a Voice Print from Settings.
@MainActor
struct PersonEditTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-28T09:00:00Z"))
    let id = UUID(uuidString: "6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61")!
    let romainPrint = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let adifPrint = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    let ownerPrint = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    let romain = Participant(name: "Romain", email: "romain@yoojo.com")

    func makeLibrary() -> Library {
        let clock = clock
        return Library(folder: folder.url, supportFolder: support.url, now: { clock.now }, moveToTrash: { _ in })
    }

    /// Romain remembered with his email, Adif with hers, and the owner.
    func rememberPeople() throws {
        func print(_ id: UUID, _ fields: String) -> String {
            """
            {"id": "\(id.uuidString)", \(fields), "model": "fluidaudio/community-1@0.17.7", "centroid": "mpkZP83MTD8=",
             "recent": [], "meetings": 2, "createdAt": "2026-10-01T10:00:00Z", "lastHeardAt": "2026-10-20T10:00:00Z"}
            """
        }
        let prints = [
            print(romainPrint, #""name": "Romain", "email": "romain@yoojo.com""#),
            print(adifPrint, #""name": "Adif", "email": "adif@yoojo.com""#),
            print(ownerPrint, #""name": "Me", "owner": true"#),
        ]
        try Data("{\"version\": 1, \"prints\": [\(prints.joined(separator: ","))]}".utf8)
            .write(to: support.url.appending(path: "voiceprints.json"))
    }

    @discardableResult
    func createMeeting(_ library: Library) throws -> URL {
        try library.create(
            FinishedMeeting(
                id: id, title: "Remote sync", start: date("2026-10-27T14:00:00Z"), end: date("2026-10-27T14:17:29Z"),
                timeZone: TimeZone(identifier: "Europe/Paris")!, language: Locale(identifier: "fr_FR"),
                provider: "Google Meet", participants: [Participant(name: "Kim Lee"), romain],
                transcriptKind: .speakers,
                speakers: [MeetingIndex.Speaker(
                    label: "Romain", cluster: "A", name: "Romain", voicePrintId: romainPrint, match: .auto,
                    speechSeconds: 12)]),
            transcript: "## Transcript\n\n**Romain** [0:02] Salut.\n")
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func entry(_ library: Library) throws -> MeetingIndex.Entry {
        try #require(try library.loadIndex().meetings.first { $0.id == id })
    }

    @Test func editingAParticipantRenamesTheTurnsAndTheirVoicePrint() throws {
        try rememberPeople()
        let library = makeLibrary()
        let url = try createMeeting(library)

        try library.editParticipant(id, romain, name: " Romain Dupont ", email: " Romain.D@Yoojo.com ")

        #expect(try read(url).hasSuffix("""
            participants:
              - Kim Lee
              - Romain Dupont <romain.d@yoojo.com>
            ---

            ## Transcript

            **Romain Dupont** [0:02] Salut.

            """))
        #expect(try entry(library).participants.last == Participant(name: "Romain Dupont", email: "romain.d@yoojo.com"))
        #expect(try entry(library).speakers.map(\.label) == ["Romain Dupont"])
        let print = try #require(library.voicePrints.prints.first { $0.id == romainPrint })
        #expect("\(print.name) \(print.email ?? "-")" == "Romain Dupont romain.d@yoojo.com")
    }

    @Test func aParticipantWithoutANameIsCalledByTheirEmail() throws {
        let library = makeLibrary()
        let url = try createMeeting(library)

        try library.editParticipant(id, romain, name: "", email: "romain@yoojo.com")

        #expect(try read(url).contains("  - romain@yoojo.com <romain@yoojo.com>\n"))
        #expect(try read(url).hasSuffix("**romain@yoojo.com** [0:02] Salut.\n"))
    }

    @Test func clearingTheEmailClearsItFromTheVoicePrintToo() throws {
        try rememberPeople()
        let library = makeLibrary()
        try createMeeting(library)

        try library.editParticipant(id, romain, name: "Romain", email: "")

        #expect(try entry(library).participants.last == Participant(name: "Romain"))
        #expect(library.voicePrints.prints.first { $0.id == romainPrint }?.email == nil)
    }

    @Test(arguments: [
        ("", " ", LibraryError.missingNameAndEmail),
        ("Romain", "romain.yoojo.com", .invalidEmail),
        ("Romain", "romain @yoojo.com", .invalidEmail),
        ("Romain", "<romain@yoojo.com>", .invalidEmail),
        ("Romain", "ADIF@yoojo.com", .emailInUse("Adif")),
        ("Them", "", .invalidSpeakerName),
    ])
    func anInvalidEditIsRefusedAndChangesNothing(name: String, email: String, error: LibraryError) throws {
        try rememberPeople()
        let library = makeLibrary()
        let url = try createMeeting(library)
        let before = try read(url)

        #expect(throws: error) { try library.editParticipant(id, romain, name: name, email: email) }
        #expect(try read(url) == before)
        #expect(library.voicePrints.prints.first { $0.id == romainPrint }?.name == "Romain")
    }

    @Test func aParticipantsOwnEmailIsNotInUse() throws {
        try rememberPeople()
        let library = makeLibrary()
        try createMeeting(library)

        try library.editParticipant(id, romain, name: "Romain D", email: "romain@yoojo.com")

        #expect(try entry(library).participants.last == Participant(name: "Romain D", email: "romain@yoojo.com"))
    }

    @Test func takingAnotherSpeakersNameLeavesTheirVoicePrintAlone() throws {
        try rememberPeople()
        let library = makeLibrary()
        try library.create(
            FinishedMeeting(
                id: id, title: "Remote sync", start: date("2026-10-27T14:00:00Z"), end: date("2026-10-27T14:17:29Z"),
                timeZone: TimeZone(identifier: "Europe/Paris")!, language: Locale(identifier: "fr_FR"),
                provider: "Google Meet", participants: [romain, Participant(name: "Adif", email: "adif@yoojo.com")],
                transcriptKind: .speakers,
                speakers: [
                    MeetingIndex.Speaker(
                        label: "Romain", cluster: "A", name: "Romain", voicePrintId: romainPrint, match: .auto,
                        speechSeconds: 12),
                    MeetingIndex.Speaker(
                        label: "Adif", cluster: "B", name: "Adif", voicePrintId: adifPrint, match: .auto,
                        speechSeconds: 12),
                ]),
            transcript: "## Transcript\n\n**Romain** [0:02] Salut.\n\n**Adif** [0:05] Bonjour.\n")

        try library.editParticipant(id, romain, name: "Adif", email: "romain@yoojo.com")

        #expect(library.voicePrints.prints.filter { !$0.owner }.map { "\($0.name) \($0.email ?? "-")" }.sorted() == [
            "Adif adif@yoojo.com", "Adif romain@yoojo.com",
        ])
        #expect(try entry(library).speakers.map { $0.voicePrintId == adifPrint } == [false, true])
    }

    @Test func editingAVoicePrintChangesOnlyThePrint() throws {
        try rememberPeople()
        let library = makeLibrary()
        let url = try createMeeting(library)
        let before = try read(url)

        try library.editVoicePrint(romainPrint, name: "Romain Dupont", email: "")

        let print = try #require(library.voicePrints.prints.first { $0.id == romainPrint })
        #expect("\(print.name) \(print.email ?? "-")" == "Romain Dupont -")
        #expect(try read(url) == before, "past transcripts stay as they are")
    }

    @Test func aVoicePrintCannotTakeAnotherOnesEmail() throws {
        try rememberPeople()
        let library = makeLibrary()

        #expect(throws: LibraryError.emailInUse("Adif")) {
            try library.editVoicePrint(romainPrint, name: "Romain", email: "adif@yoojo.com")
        }
        #expect(library.voicePrints.prints.first { $0.id == romainPrint }?.email == "romain@yoojo.com")
    }
}
