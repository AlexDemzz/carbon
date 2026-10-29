import CarbonCore
import Foundation
import Testing

/// "Same Person As": two Participants of a Meeting become one, and so do the Voice Prints they were heard as.
@MainActor
struct ParticipantMergeTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-28T09:00:00Z"))
    let id = UUID(uuidString: "6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61")!
    let otherID = UUID(uuidString: "7A2D3C9F-1B62-4D4B-8F1C-2E3D4C5B6A72")!
    let romainPrint = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let emailPrint = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    let romainByEmail = Participant(name: "romain@yoojo.com", email: "romain@yoojo.com")
    let romain = Participant(name: "Romain")

    func makeLibrary() -> Library {
        let clock = clock
        return Library(folder: folder.url, supportFolder: support.url, now: { clock.now }, moveToTrash: { _ in })
    }

    @discardableResult
    func create(
        _ library: Library, _ id: UUID? = nil, participants: [Participant], speakers: [MeetingIndex.Speaker],
        transcript: String
    ) throws -> URL {
        try library.create(
            FinishedMeeting(
                id: id ?? self.id, title: id == nil ? "Remote sync" : "Room sync", start: date("2026-10-27T14:00:00Z"),
                end: date("2026-10-27T14:17:29Z"), timeZone: TimeZone(identifier: "Europe/Paris")!,
                language: Locale(identifier: "fr_FR"), provider: "Google Meet", participants: participants,
                transcriptKind: .speakers, speakers: speakers),
            transcript: transcript)
    }

    func speaker(_ label: String, cluster: String, print: UUID? = nil) -> MeetingIndex.Speaker {
        MeetingIndex.Speaker(
            label: label, cluster: cluster, name: label.hasPrefix("Speaker ") ? nil : label, voicePrintId: print,
            match: print == nil ? nil : .auto, speechSeconds: 12)
    }

    func print(_ id: UUID, name: String, email: String? = nil, meetings: Int, lastHeard: String) -> String {
        """
        {"id": "\(id.uuidString)", "name": "\(name)",\(email.map { " \"email\": \"\($0)\"," } ?? "")
         "model": "fluidaudio/community-1@0.17.7", "centroid": "mpkZP83MTD8=", "recent": [],
         "meetings": \(meetings), "createdAt": "2026-10-01T10:00:00Z", "lastHeardAt": "\(lastHeard)"}
        """
    }

    func remember(_ prints: String...) throws {
        try Data("{\"version\": 1, \"prints\": [\(prints.joined(separator: ","))]}".utf8)
            .write(to: support.url.appending(path: "voiceprints.json"))
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func entry(_ library: Library, _ id: UUID? = nil) throws -> MeetingIndex.Entry {
        try #require(try library.loadIndex().meetings.first { $0.id == (id ?? self.id) })
    }

    let romainSpoke = """
        ## Transcript

        **Romain** [0:02] Salut.

        **Speaker B** [0:05] Bonjour.

        """

    @Test func aVoiceNamedByHandBecomesTheAttendeeKnownOnlyByEmail() throws {
        try remember(print(romainPrint, name: "Romain", meetings: 2, lastHeard: "2026-10-20T10:00:00Z"))
        let library = makeLibrary()
        let url = try create(
            library, participants: [romainByEmail, romain],
            speakers: [speaker("Romain", cluster: "A", print: romainPrint), speaker("Speaker B", cluster: "B")],
            transcript: romainSpoke)

        try library.mergeParticipant(id, romain, into: romainByEmail)

        #expect(try read(url).contains("participants:\n  - Romain <romain@yoojo.com>\n---\n"))
        #expect(try read(url).hasSuffix(romainSpoke))
        #expect(try entry(library).participants == [Participant(name: "Romain", email: "romain@yoojo.com")])
        #expect(library.voicePrints.prints.map { "\($0.name) \($0.email ?? "-") \($0.meetings)" } == [
            "Romain romain@yoojo.com 2",
        ])
        #expect(try !library.hasLocalEdit(id))
    }

    @Test func theCalendarsFullNameRenamesTheTurnsAndTheVoicePrint() throws {
        try remember(print(romainPrint, name: "Bertrand", meetings: 1, lastHeard: "2026-10-20T10:00:00Z"))
        let library = makeLibrary()
        let bertrand = Participant(name: "Bertrand Tournier", email: "bertrand@yoojo.com")
        let url = try create(
            library, participants: [bertrand, Participant(name: "Bertrand")],
            speakers: [speaker("Bertrand", cluster: "A", print: romainPrint)],
            transcript: "## Transcript\n\n**Bertrand** [0:02] Salut.\n")

        try library.mergeParticipant(id, Participant(name: "Bertrand"), into: bertrand)

        #expect(try read(url).hasSuffix("""
            participants:
              - Bertrand Tournier <bertrand@yoojo.com>
            ---

            ## Transcript

            **Bertrand Tournier** [0:02] Salut.

            """))
        #expect(try entry(library).speakers.map { "\($0.label) \($0.name ?? "-")" } == [
            "Bertrand Tournier Bertrand Tournier",
        ])
        #expect(library.voicePrints.prints.map { "\($0.name) \($0.email ?? "-")" } == [
            "Bertrand Tournier bertrand@yoojo.com",
        ])
    }

    @Test func twoVoicePrintsOfOnePersonKeepTheMostHeardAndRelinkEveryMeeting() throws {
        try remember(
            print(romainPrint, name: "Romain", meetings: 3, lastHeard: "2026-10-20T10:00:00Z"),
            print(emailPrint, name: "romain@yoojo.com", email: "romain@yoojo.com", meetings: 1,
                  lastHeard: "2026-10-25T10:00:00Z"))
        let library = makeLibrary()
        try create(
            library, otherID, participants: [romainByEmail],
            speakers: [speaker("romain@yoojo.com", cluster: "A", print: emailPrint)],
            transcript: "## Transcript\n\n**romain@yoojo.com** [0:02] Salut.\n")
        try create(
            library, participants: [romainByEmail, romain],
            speakers: [speaker("Romain", cluster: "A", print: romainPrint)],
            transcript: "## Transcript\n\n**Romain** [0:02] Salut.\n")

        try library.mergeParticipant(id, romain, into: romainByEmail)

        let survivor = try #require(library.voicePrints.prints.first)
        #expect(library.voicePrints.prints.count == 1)
        #expect(survivor.id == romainPrint)
        #expect("\(survivor.name) \(survivor.email ?? "-") \(survivor.meetings)" == "Romain romain@yoojo.com 4")
        #expect(survivor.lastHeardAt == date("2026-10-25T10:00:00Z"))
        #expect(try entry(library, otherID).speakers.map(\.voicePrintId) == [romainPrint])
        #expect(try entry(library, otherID).speakers.map(\.label) == ["romain@yoojo.com"], "other files stay as they are")
    }

    @Test func aMeetingWhereBothVoicePrintsWereHeardCountsOnce() throws {
        try remember(
            print(romainPrint, name: "Romain", meetings: 2, lastHeard: "2026-10-20T10:00:00Z"),
            print(emailPrint, name: "romain@yoojo.com", email: "romain@yoojo.com", meetings: 1,
                  lastHeard: "2026-10-20T10:00:00Z"))
        let library = makeLibrary()
        try create(
            library, participants: [romainByEmail, romain],
            speakers: [
                speaker("Romain", cluster: "A", print: romainPrint),
                speaker("romain@yoojo.com", cluster: "B", print: emailPrint),
            ],
            transcript: "## Transcript\n\n**Romain** [0:02] Salut.\n\n**romain@yoojo.com** [0:05] Ça va ?\n")

        try library.mergeParticipant(id, romain, into: romainByEmail)

        #expect(library.voicePrints.prints.map(\.meetings) == [2])
        #expect(try entry(library).speakers.map { "\($0.label) \($0.voicePrintId == romainPrint)" } == [
            "Romain true", "Romain true",
        ])
        #expect(try read(try #require(library.meetings.first).file).hasSuffix(
            "**Romain** [0:02] Salut.\n\n**Romain** [0:05] Ça va ?\n"))
    }

    @Test func participantsWhoNeverSpokeChangeOnlyTheFrontmatter() throws {
        let library = makeLibrary()
        let url = try create(
            library, participants: [Participant(name: "Kim Lee", email: "kim@yoojo.com"), romainByEmail, romain],
            speakers: [speaker("Speaker A", cluster: "A")],
            transcript: "## Transcript\n\n**Speaker A** [0:02] Salut.\n")

        try library.mergeParticipant(id, romainByEmail, into: romain)

        #expect(try read(url).contains("""
            participants:
              - Kim Lee <kim@yoojo.com>
              - Romain <romain@yoojo.com>
            ---
            """))
        #expect(library.voicePrints.prints.isEmpty)
    }

    @Test func aParticipantsListWrittenByHandAsAFlowListIsRefused() throws {
        let library = makeLibrary()
        let url = try create(
            library, participants: [romainByEmail, romain], speakers: [], transcript: "## Transcript\n")
        let edited = try read(url).replacingOccurrences(
            of: "participants:\n  - romain@yoojo.com <romain@yoojo.com>\n  - Romain\n",
            with: "participants: [romain@yoojo.com <romain@yoojo.com>, Romain]\n")
        try edited.write(to: url, atomically: true, encoding: .utf8)

        #expect(throws: LibraryError.participantsNotInFile) {
            try library.mergeParticipant(id, romain, into: romainByEmail)
        }
        #expect(try read(url) == edited)
        #expect(try entry(library).participants == [romainByEmail, romain])
    }
}
