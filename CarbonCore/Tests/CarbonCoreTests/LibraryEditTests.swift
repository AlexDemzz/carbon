import CarbonCore
import Foundation
import Testing

/// What the person does to a Meeting: rename, color, edit, delete. Carbon's writes never touch the person's text.
@MainActor
struct LibraryEditTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let trash = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-28T09:00:00Z"))
    let newYork = TimeZone(identifier: "America/New_York")!
    let id = UUID(uuidString: "6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61")!

    func makeLibrary() -> Library {
        let clock = clock
        let trash = trash.url
        return Library(
            folder: folder.url, supportFolder: support.url, now: { clock.now },
            moveToTrash: { url in
                try FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent))
            })
    }

    /// A Meeting Carbon just wrote, as `create` leaves it.
    func created(_ library: Library) throws -> URL {
        let meeting = FinishedMeeting(
            id: id, title: "Remote control kickoff", start: date("2026-10-27T14:00:00Z"),
            end: date("2026-10-27T14:42:10Z"), timeZone: newYork, language: Locale(identifier: "en_US"),
            provider: "Google Meet", participants: [Participant(name: "Priya Nair")], transcriptKind: .fallback)
        return try library.create(meeting, transcript: "## Transcript\n\n**Me** [0:00] Hello.\n")
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func entry(_ library: Library) throws -> MeetingIndex.Entry {
        try #require(try library.loadIndex().meetings.first { $0.id == id })
    }

    let createdMarkdown = """
        ---
        provider: Google Meet
        id: 6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61
        date: 2026-10-27T10:00:00-04:00
        title: Remote control kickoff
        duration: 42:10
        language: en-US
        participants:
          - Priya Nair
        ---

        ## Transcript

        **Me** [0:00] Hello.

        """

    // MARK: Rename

    @Test func renamingChangesOnlyTheFrontmatterTitleAndKeepsTheFileName() throws {
        let library = makeLibrary()
        let url = try created(library)

        try library.rename(id, title: "Remote: v2 kickoff")

        #expect(try read(url) == createdMarkdown.replacingOccurrences(
            of: "title: Remote control kickoff", with: "title: \"Remote: v2 kickoff\""))
        #expect(try entry(library).file == "2026/2026-10-27-remote-control-kickoff.md")
        #expect(try entry(library).title == "Remote: v2 kickoff")
        #expect(library.meetings.map(\.title) == ["Remote: v2 kickoff"])
        #expect(try !library.hasLocalEdit(id), "Carbon's own surgical write is not a Local Edit")
    }

    @Test func renamingAfterALocalEditKeepsThePersonsTextAndTheLocalEdit() throws {
        let library = makeLibrary()
        let url = try created(library)
        let edited = createdMarkdown.replacingOccurrences(of: "Hello.", with: "Hello, everyone. (fixed by hand)")
        try edited.write(to: url, atomically: true, encoding: .utf8)
        #expect(try library.hasLocalEdit(id))

        try library.rename(id, title: "Kickoff")

        #expect(try read(url) == edited.replacingOccurrences(of: "title: Remote control kickoff", with: "title: Kickoff"))
        #expect(try library.hasLocalEdit(id))
    }

    @Test func renamingAFileWhoseTitleThePersonRemovedLeavesTheFileAlone() throws {
        let library = makeLibrary()
        let url = try created(library)
        let edited = createdMarkdown.replacingOccurrences(of: "title: Remote control kickoff\n", with: "")
        try edited.write(to: url, atomically: true, encoding: .utf8)

        try library.rename(id, title: "Kickoff")

        #expect(try read(url) == edited)
        #expect(try entry(library).title == "Kickoff")
    }

    @Test func aRenamedMeetingKeepsItsFileNameSoANewMeetingWithTheOldTitleGetsANumber() throws {
        let library = makeLibrary()
        try created(library)
        try library.rename(id, title: "Kickoff")

        let next = FinishedMeeting(
            id: UUID(), title: "Remote control kickoff", start: date("2026-10-27T18:00:00Z"),
            end: date("2026-10-27T18:30:00Z"), timeZone: newYork, language: Locale(identifier: "en_US"),
            provider: "Zoom", transcriptKind: .fallback)
        let url = try library.create(next, transcript: "## Transcript\n")

        #expect(url.lastPathComponent == "2026-10-27-remote-control-kickoff-2.md")
    }

    @Test func renamingAWindowsLineEndingsFileKeepsItsLineEndings() throws {
        let library = makeLibrary()
        let url = try created(library)
        let crlf = createdMarkdown.replacingOccurrences(of: "\n", with: "\r\n")
        try crlf.write(to: url, atomically: true, encoding: .utf8)

        try library.rename(id, title: "Kickoff")

        #expect(try read(url) == crlf.replacingOccurrences(of: "title: Remote control kickoff", with: "title: Kickoff"))
    }

    // MARK: Color

    @Test func aColorDotIsKeptInTheIndexOnly() throws {
        let library = makeLibrary()
        let url = try created(library)

        try library.setColor(id, color: "red")
        #expect(try entry(library).color == "red")
        #expect(library.meetings.map(\.color) == ["red"])

        try library.setColor(id, color: nil)
        #expect(try entry(library).color == nil)
        #expect(try read(url) == createdMarkdown)
    }

    // MARK: Editor

    @Test func anEditorSaveWritesTheFileAsALocalEdit() throws {
        let library = makeLibrary()
        let url = try created(library)
        let edited = createdMarkdown + "\nMy notes.\n"

        try library.save(id, editedMarkdown: edited)

        #expect(try read(url) == edited)
        #expect(try library.hasLocalEdit(id))
        #expect(library.meetings.first?.markdown == edited)
        #expect(library.search("my notes").count == 1)
    }

    @Test func anEditorSaveCarriesTheFrontmatterTitleAndParticipantsIntoTheIndex() throws {
        let library = makeLibrary()
        try created(library)
        let edited = createdMarkdown
            .replacingOccurrences(of: "title: Remote control kickoff", with: "title: \"Remote: \\\"v2\\\" kickoff\"")
            .replacingOccurrences(of: "  - Priya Nair\n", with: "  - Priya Nair\n  - \"Sam Rivera <sam@example.com>\"\n")

        try library.save(id, editedMarkdown: edited)

        #expect(try entry(library).title == "Remote: \"v2\" kickoff")
        #expect(try entry(library).participants == [
            Participant(name: "Priya Nair"), Participant(name: "Sam Rivera", email: "sam@example.com"),
        ])
        #expect(library.meetings.map(\.title) == ["Remote: \"v2\" kickoff"])
        #expect(library.search("rivera").map(\.meeting.title) == ["Remote: \"v2\" kickoff"])
    }

    @Test func anEditorSaveWithAFlowListOfParticipantsReadsThem() throws {
        let library = makeLibrary()
        try created(library)
        let edited = createdMarkdown.replacingOccurrences(
            of: "participants:\n  - Priya Nair\n", with: "participants: [Priya Nair, 'Sam O''Neil']\n")

        try library.save(id, editedMarkdown: edited)

        #expect(try entry(library).participants == [Participant(name: "Priya Nair"), Participant(name: "Sam O'Neil")])
    }

    @Test func anEditorSaveWithoutTitleOrParticipantsKeepsTheIndexOnes() throws {
        let library = makeLibrary()
        try created(library)
        let edited = createdMarkdown
            .replacingOccurrences(of: "title: Remote control kickoff\n", with: "")
            .replacingOccurrences(of: "participants:\n  - Priya Nair\n", with: "")

        try library.save(id, editedMarkdown: edited)

        #expect(try entry(library).title == "Remote control kickoff")
        #expect(try entry(library).participants == [Participant(name: "Priya Nair")])
    }

    // MARK: Delete

    @Test func deleteMovesTheFileAndItsAudioToTheTrashAndLeavesATombstone() throws {
        let library = makeLibrary()
        let url = try created(library)
        var index = try library.loadIndex()
        index.meetings[0].audio = "2026/2026-10-27-remote-control-kickoff.m4a"
        try JSONEncoder().encode(index).write(to: support.url.appending(path: "meetings.json"))
        try Data("aac".utf8).write(to: folder.url.appending(path: "2026/2026-10-27-remote-control-kickoff.m4a"))

        try library.delete(id)

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.url.path).sorted() == [
            "2026-10-27-remote-control-kickoff.m4a", "2026-10-27-remote-control-kickoff.md",
        ])
        #expect(try library.loadIndex().meetings.isEmpty)
        #expect(try library.loadIndex().deleted == [MeetingIndex.Tombstone(id: id, deletedAt: "2026-10-28T09:00:00Z")])
        #expect(library.meetings.isEmpty)
    }

    @Test func deletingAMeetingWhoseFileIsAlreadyGoneStillRemovesIt() throws {
        let library = makeLibrary()
        let url = try created(library)
        try FileManager.default.removeItem(at: url)

        try library.delete(id)

        #expect(try library.loadIndex().meetings.isEmpty)
        #expect(try library.loadIndex().deleted.map(\.id) == [id])
    }
}
