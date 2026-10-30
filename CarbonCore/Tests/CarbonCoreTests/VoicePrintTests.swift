import CarbonCore
import Foundation
import Testing

/// Naming a Speaker remembers their voice in `voiceprints.json`; Settings deletes what Carbon remembers.
@MainActor
struct VoicePrintTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-28T09:00:00Z"))
    let newYork = TimeZone(identifier: "America/New_York")!
    let id = UUID(uuidString: "6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61")!
    let otherID = UUID(uuidString: "7A2D3C9F-1B62-4D4B-8F1C-2E3D4C5B6A72")!
    let samPrint = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let newPrint = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!

    /// [0.6, 0.8] as `meetings.json` and `voiceprints.json` store it.
    let voice = "mpkZP83MTD8="

    func makeLibrary() -> Library {
        let clock = clock
        let newPrint = newPrint
        return Library(
            folder: folder.url, supportFolder: support.url, now: { clock.now }, moveToTrash: { _ in },
            makeVoicePrintID: { newPrint })
    }

    func meeting(_ id: UUID, speakers: [MeetingIndex.Speaker]) -> FinishedMeeting {
        FinishedMeeting(
            id: id, title: id == self.id ? "Remote control kickoff" : "Weekly sync", start: date("2026-10-27T14:00:00Z"),
            end: date("2026-10-27T14:17:29Z"), timeZone: newYork, language: Locale(identifier: "en_US"),
            provider: "Google Meet", participants: [Participant(name: "Sam Rivera", email: "sam@example.com")],
            transcriptKind: .speakers, speakers: speakers)
    }

    let transcript = """
        ## Transcript

        **Speaker A** [0:02] Hello all.

        """

    func createMeeting(_ library: Library, _ id: UUID? = nil, speaker: MeetingIndex.Speaker) throws -> URL {
        try library.create(meeting(id ?? self.id, speakers: [speaker]), transcript: transcript)
    }

    func speakerA(seconds: Double = 12.5) -> MeetingIndex.Speaker {
        MeetingIndex.Speaker(label: "Speaker A", cluster: "A", speechSeconds: seconds, centroid: voice)
    }

    var printsFile: URL { support.url.appending(path: "voiceprints.json") }

    func printsJSON() throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: printsFile)) as? NSDictionary)
    }

    func speakers(_ library: Library, _ id: UUID? = nil) throws -> [MeetingIndex.Speaker] {
        try #require(try library.loadIndex().meetings.first { $0.id == (id ?? self.id) }).speakers
    }

    /// Writes `voiceprints.json` as an earlier launch left it: Sam remembered from two Meetings.
    func rememberSam() throws {
        try Data("""
            {"version": 1, "prints": [{
              "id": "11111111-1111-4111-8111-111111111111", "name": "Sam Rivera", "email": "sam@example.com",
              "model": "fluidaudio/community-1@0.17.7", "centroid": "\(voice)", "recent": ["\(voice)"],
              "meetings": 2, "createdAt": "2026-10-01T10:00:00Z", "lastHeardAt": "2026-10-20T10:00:00Z"
            }]}
            """.utf8).write(to: printsFile)
    }

    let ownerPrint = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    /// Writes `voiceprints.json` with the owner's print, learnt from `meetings` solo Meetings.
    func rememberOwner(meetings: Int) throws {
        try Data("""
            {"version": 1, "prints": [{
              "id": "22222222-2222-4222-8222-222222222222", "name": "Me", "owner": true,
              "model": "fluidaudio/community-1@0.17.7", "centroid": "\(voice)", "recent": [],
              "meetings": \(meetings), "createdAt": "2026-10-01T10:00:00Z", "lastHeardAt": "2026-10-20T10:00:00Z"
            }]}
            """.utf8).write(to: printsFile)
    }

    /// A meeting room whose mic Speaker A was written as the owner, or not.
    func createRoom(_ library: Library, speaker: MeetingIndex.Speaker) throws -> URL {
        try library.create(
            meeting(id, speakers: [speaker]), transcript: "## Transcript\n\n**\(speaker.label)** [0:02] Hello all.\n")
    }

    @Test func inARoomAWrongMeIsRenamedAndTheOwnersPrintStaysAsItWas() throws {
        try rememberOwner(meetings: 1)
        let library = makeLibrary()
        let file = try createRoom(library, speaker: MeetingIndex.Speaker(
            label: "Me", cluster: "A", stream: .me, name: "Me", voicePrintId: ownerPrint, match: .auto,
            distance: 0.2, speechSeconds: 12.5, centroid: voice))

        try library.renameSpeaker(id, label: "Me", name: "Dana Park")

        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Dana Park** [0:02] Hello all."))
        #expect(try speakers(library).map(\.voicePrintId) == [newPrint])
        let owner = try #require(library.voicePrints.prints.first { $0.id == ownerPrint })
        #expect(owner.meetings == 1)
        #expect(owner.recent.isEmpty)
    }

    @Test func aMicSpeakerNamedMeIsTheOwnerAndUpdatesTheirPrint() throws {
        try rememberOwner(meetings: 3)
        let library = makeLibrary()
        let file = try createRoom(library, speaker: MeetingIndex.Speaker(
            label: "Speaker A", cluster: "A", stream: .me, speechSeconds: 12.5, centroid: voice))

        try library.renameSpeaker(id, label: "Speaker A", name: "me")

        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(markdown.contains("**Me** [0:02] Hello all."))
        #expect(!markdown.contains("  - Me"))
        #expect(try speakers(library) == [MeetingIndex.Speaker(
            label: "Me", cluster: "A", stream: .me, name: "Me", voicePrintId: ownerPrint, match: .user,
            speechSeconds: 12.5, centroid: voice)])
        #expect(try #require(library.loadIndex().meetings.first).participants.map(\.name) == ["Sam Rivera"])
        #expect(library.voicePrints.prints.map(\.meetings) == [4])
    }

    @Test func aMicSpeakerNamedMeEnrollsTheOwnersPrintWhenThereIsNone() throws {
        let library = makeLibrary()
        try createRoom(library, speaker: MeetingIndex.Speaker(
            label: "Speaker A", cluster: "A", stream: .me, speechSeconds: 12.5, centroid: voice))

        try library.renameSpeaker(id, label: "Speaker A", name: "Me")

        #expect(library.voicePrints.prints.map { "\($0.name) \($0.owner)" } == ["Me true"])
        #expect(try speakers(library).map(\.voicePrintId) == [newPrint])
    }

    @Test func aSpeakerOnTheCallIsNeverNamedMe() throws {
        let library = makeLibrary()
        try createMeeting(library, speaker: speakerA())

        #expect(throws: LibraryError.invalidSpeakerName) {
            try library.renameSpeaker(id, label: "Speaker A", name: "Me")
        }
    }

    @Test func namingASpeakerWithTenSecondsOfSpeechRemembersTheirVoice() throws {
        let library = makeLibrary()
        try createMeeting(library, speaker: speakerA())

        try library.renameSpeaker(id, label: "Speaker A", name: "Dana Park", email: "dana@example.com")

        #expect(try printsJSON() == [
            "version": 1,
            "prints": [[
                "id": "99999999-9999-4999-8999-999999999999", "name": "Dana Park", "email": "dana@example.com",
                "model": "fluidaudio/community-1@0.17.7", "centroid": voice, "recent": [],
                "meetings": 1, "createdAt": "2026-10-28T09:00:00Z", "lastHeardAt": "2026-10-27T14:00:00Z",
            ]],
        ] as NSDictionary)
        #expect(try speakers(library).map(\.voicePrintId) == [newPrint])
        #expect(library.voicePrints.prints.map(\.name) == ["Dana Park"])
    }

    @Test func theVoicePrintsFileIsKeptOutOfCarbonsBackups() throws {
        let library = makeLibrary()
        try createMeeting(library, speaker: speakerA())

        try library.renameSpeaker(id, label: "Speaker A", name: "Dana Park")
        // The next launch's first save takes a backup.
        try makeLibrary().setColor(id, color: "red")

        let backups = try FileManager.default.contentsOfDirectory(atPath: support.url.appending(path: "Backups").path)
        #expect(!backups.isEmpty)
        #expect(backups.allSatisfy { $0.hasPrefix("meetings-") })
    }

    @Test func aSpeakerWithLessThanTenSecondsGetsTheNameButNoVoicePrint() throws {
        let library = makeLibrary()
        try createMeeting(library, speaker: speakerA(seconds: 9.5))
        #expect(library.meetings[0].tooLittleSpeechToRemember("Speaker A"))

        try library.renameSpeaker(id, label: "Speaker A", name: "Dana Park")

        #expect(!FileManager.default.fileExists(atPath: printsFile.path))
        #expect(try speakers(library) == [MeetingIndex.Speaker(
            label: "Dana Park", cluster: "A", name: "Dana Park", match: .user, speechSeconds: 9.5, centroid: voice)])
        #expect(library.meetings[0].tooLittleSpeechToRemember("Dana Park"))
    }

    @Test func aSpeakerWithNoCleanVoiceGetsTheNameButNoVoicePrintHoweverLongTheySpoke() throws {
        let library = makeLibrary()
        try createMeeting(library, speaker: MeetingIndex.Speaker(label: "Speaker A", cluster: "A", speechSeconds: 60))
        #expect(library.meetings[0].tooLittleSpeechToRemember("Speaker A"))

        try library.renameSpeaker(id, label: "Speaker A", name: "Dana Park")

        #expect(!FileManager.default.fileExists(atPath: printsFile.path))
        #expect(library.meetings[0].tooLittleSpeechToRemember("Dana Park"))
    }

    @Test func theOtherAttendeeOfA1to1WithoutDiarizationIsNotSaidToHaveTooLittleSpeech() throws {
        let library = makeLibrary()
        try createMeeting(library, speaker: MeetingIndex.Speaker(
            label: "Dana Park", cluster: TranscriptBuilder.them, name: "Dana Park", match: .attendee1to1,
            speechSeconds: 0))

        #expect(!library.meetings[0].tooLittleSpeechToRemember("Dana Park"))
    }

    @Test func namingAnotherMeetingsSpeakerAfterARememberedPersonUpdatesTheirPrint() throws {
        try rememberSam()
        let library = makeLibrary()
        try createMeeting(library, speaker: speakerA())

        try library.renameSpeaker(id, label: "Speaker A", name: "Sam Rivera")

        let prints = try #require(try printsJSON()["prints"] as? [NSDictionary])
        #expect(prints.count == 1)
        #expect(prints[0]["meetings"] as? Int == 3)
        #expect(prints[0]["recent"] as? [String] == [voice, voice])
        #expect(prints[0]["lastHeardAt"] as? String == "2026-10-27T14:00:00Z")
        #expect(try speakers(library).map(\.voicePrintId) == [samPrint])
    }

    @Test func namingASpeakerAfterTheEmailOfARememberedPersonUpdatesTheirPrintWhateverTheName() throws {
        try rememberSam()
        let library = makeLibrary()
        try createMeeting(library, speaker: speakerA())

        try library.renameSpeaker(id, label: "Speaker A", name: "sam@example.com", email: "SAM@example.com")

        #expect(library.voicePrints.prints.map { "\($0.name) \($0.meetings)" } == ["Sam Rivera 3"])
        #expect(try speakers(library).map(\.voicePrintId) == [samPrint])
    }

    @Test func renamingAnAutoMatchedSpeakerAfterTheSamePersonsEmailKeepsTheLink() throws {
        try rememberSam()
        let library = makeLibrary()
        try createMeeting(library, speaker: MeetingIndex.Speaker(
            label: "Sam Rivera", cluster: "A", name: "Sam Rivera", voicePrintId: samPrint, match: .auto,
            speechSeconds: 12.5, centroid: voice))

        try library.renameSpeaker(id, label: "Sam Rivera", name: "sam@example.com", email: "sam@example.com")

        #expect(library.voicePrints.prints.map { "\($0.name) \($0.meetings)" } == ["Sam Rivera 2"])
        #expect(try speakers(library).map(\.voicePrintId) == [samPrint])
    }

    @Test func renamingAnAutoMatchedSpeakerMovesTheLinkAndLeavesTheFirstPrintsName() throws {
        try rememberSam()
        let library = makeLibrary()
        try createMeeting(library, speaker: MeetingIndex.Speaker(
            label: "Sam Rivera", cluster: "A", name: "Sam Rivera", voicePrintId: samPrint, match: .auto,
            distance: 0.12, speechSeconds: 12.5, centroid: voice))

        try library.renameSpeaker(id, label: "Sam Rivera", name: "Dana Park")

        #expect(try speakers(library) == [MeetingIndex.Speaker(
            label: "Dana Park", cluster: "A", name: "Dana Park", voicePrintId: newPrint, match: .user,
            distance: 0.12, speechSeconds: 12.5, centroid: voice)])
        let prints = library.voicePrints.prints.map { "\($0.name) \($0.meetings)" }
        #expect(prints.sorted() == ["Dana Park 1", "Sam Rivera 1"])
    }

    @Test func renamingAnAutoMatchedSpeakerTakesItsVoiceBackOutOfThePrint() throws {
        // Sam as `rememberSam` leaves him, after this Meeting auto-matched a voice of [1, 0] to him: the centroid
        // became the normalized sum of [0.6, 0.8], [0.6, 0.8] and [1, 0], [0.80874, 0.58817].
        try Data("""
            {"version": 1, "prints": [{
              "id": "11111111-1111-4111-8111-111111111111", "name": "Sam Rivera", "email": "sam@example.com",
              "model": "fluidaudio/community-1@0.17.7", "centroid": "VAlPP2ySFj8=",
              "recent": ["\(voice)", "AACAPwAAAAA="],
              "meetings": 3, "createdAt": "2026-10-01T10:00:00Z", "lastHeardAt": "2026-10-27T14:00:00Z"
            }]}
            """.utf8).write(to: printsFile)
        let library = makeLibrary()
        try createMeeting(library, speaker: MeetingIndex.Speaker(
            label: "Sam Rivera", cluster: "A", name: "Sam Rivera", voicePrintId: samPrint, match: .auto,
            distance: 0.3, speechSeconds: 4, centroid: "AACAPwAAAAA="))

        try library.renameSpeaker(id, label: "Sam Rivera", name: "Dana Park")

        let sam = try #require(library.voicePrints.prints.first { $0.id == samPrint })
        #expect(sam.meetings == 2)
        #expect(sam.recent == [[0.6, 0.8]])
        #expect(abs(sam.centroid[0] - 0.6) < 1e-5 && abs(sam.centroid[1] - 0.8) < 1e-5)
    }

    @Test func deletingAVoicePrintUnlinksEveryMeetingAndKeepsTheNamesInTheFiles() throws {
        try rememberSam()
        let library = makeLibrary()
        let sam = MeetingIndex.Speaker(
            label: "Sam Rivera", cluster: "A", name: "Sam Rivera", voicePrintId: samPrint, match: .auto,
            speechSeconds: 12.5)
        let first = try createMeeting(library, speaker: sam)
        try createMeeting(library, otherID, speaker: sam)
        let firstFile = try String(contentsOf: first, encoding: .utf8)

        try library.deleteVoicePrint(samPrint)

        #expect(try printsJSON()["prints"] as? NSArray == [])
        for meeting in [id, otherID] {
            #expect(try speakers(library, meeting).map(\.voicePrintId) == [nil])
            #expect(try speakers(library, meeting).map(\.name) == ["Sam Rivera"])
        }
        #expect(try String(contentsOf: first, encoding: .utf8) == firstFile)
    }

    @Test func deleteAllForgetsEveryVoice() throws {
        let library = makeLibrary()
        try createMeeting(library, speaker: speakerA())
        try library.renameSpeaker(id, label: "Speaker A", name: "Dana Park")

        try library.deleteAllVoicePrints()

        #expect(library.voicePrints.prints == [])
        #expect(try printsJSON()["prints"] as? NSArray == [])
        #expect(try speakers(library).map(\.voicePrintId) == [nil])
    }

    @Test func withRecognitionOffNamingRemembersNoVoice() throws {
        let library = makeLibrary()
        library.recognizesVoices = false
        try createMeeting(library, speaker: speakerA())

        try library.renameSpeaker(id, label: "Speaker A", name: "Dana Park")

        #expect(!FileManager.default.fileExists(atPath: printsFile.path))
        #expect(try speakers(library).map(\.voicePrintId) == [nil])
    }
}
