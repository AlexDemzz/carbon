import CarbonCore
import Foundation
import Testing

/// Reconcile: the Library follows what the person did to its files in Finder.
@MainActor
struct LibraryReconcileTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-28T09:00:00Z"))

    init() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Library", withExtension: nil, subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture.appending(path: "Documents/2026"), to: folder.url.appending(path: "2026"))
        try FileManager.default.copyItem(
            at: fixture.appending(path: "Support/meetings.json"), to: support.url.appending(path: "meetings.json"))
    }

    func makeLibrary() -> Library {
        let clock = clock
        return Library(folder: folder.url, supportFolder: support.url, now: { clock.now })
    }

    func move(_ from: String, to: String) throws {
        let destination = folder.url.appending(path: to)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder.url.appending(path: from), to: destination)
    }

    @Test func aFileRenamedOrMovedInFinderIsFoundAgainByItsID() throws {
        try move("2026/2026-10-25-standup.md", to: "Work/Standups/monday standup.md")
        let library = makeLibrary()

        try library.reconcile()

        let index = try library.loadIndex()
        #expect(index.meetings.first { $0.title == "Standup" }?.file == "Work/Standups/monday standup.md")
        #expect(index.deleted.isEmpty)
        #expect(library.meetings.map(\.title) == ["Remote control kickoff", "Standup", "Réunion budget"])
        #expect(library.meetings[1].file == folder.url.appending(path: "Work/Standups/monday standup.md"))
    }

    @Test func aFileDeletedInFinderBecomesADeletedMeeting() throws {
        try FileManager.default.removeItem(at: folder.url.appending(path: "2026/2026-10-25-standup.md"))
        let library = makeLibrary()

        try library.reconcile()

        let index = try library.loadIndex()
        #expect(index.meetings.map(\.title).sorted() == ["Remote control kickoff", "Réunion budget"])
        #expect(index.deleted == [
            MeetingIndex.Tombstone(id: UUID(uuidString: "0B9D7A3C-5E2F-4D10-8C6B-2A3E4F5D6C72")!, deletedAt: "2026-10-28T09:00:00Z"),
        ])
        #expect(library.meetings.map(\.title) == ["Remote control kickoff", "Réunion budget"])
    }

    @Test func aFileMovedOutOfTheLibraryFolderIsADeletedMeetingToo() throws {
        let outside = try TemporaryFolder()
        try FileManager.default.moveItem(
            at: folder.url.appending(path: "2026/2026-10-25-standup.md"), to: outside.url.appending(path: "standup.md"))
        let library = makeLibrary()

        try library.reconcile()

        #expect(try library.loadIndex().deleted.map(\.id.uuidString) == ["0B9D7A3C-5E2F-4D10-8C6B-2A3E4F5D6C72"])
    }

    @Test func notesWithAnUnknownIDAreIgnored() throws {
        try """
            ---
            id: 11111111-2222-3333-4444-555555555555
            title: My own Meeting
            ---

            Notes.
            """.write(to: folder.url.appending(path: "2026/copied.md"), atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: support.url.appending(path: "meetings.json"))
        let library = makeLibrary()

        try library.reconcile()

        #expect(library.meetings.map(\.title) == ["Remote control kickoff", "Standup", "Réunion budget"])
        #expect(try Data(contentsOf: support.url.appending(path: "meetings.json")) == before, "nothing changed, nothing written")
    }

    @Test func aTombstonedFileThatReappearsStaysDeleted() throws {
        let standup = folder.url.appending(path: "2026/2026-10-25-standup.md")
        let kept = try Data(contentsOf: standup)
        try FileManager.default.removeItem(at: standup)
        let library = makeLibrary()
        try library.reconcile()

        try kept.write(to: folder.url.appending(path: "2026/restored.md"))
        try library.reconcile()

        #expect(library.meetings.map(\.title) == ["Remote control kickoff", "Réunion budget"])
        #expect(try library.loadIndex().deleted.count == 1)
    }

    @Test func reconcilePicksUpWhatThePersonTypedInTheFile() throws {
        let library = makeLibrary()
        try library.load()
        let standup = folder.url.appending(path: "2026/2026-10-25-standup.md")
        try (String(contentsOf: standup, encoding: .utf8) + "\n**Me** [1:05:00] Added by hand about pelicans.\n")
            .write(to: standup, atomically: true, encoding: .utf8)

        try library.reconcile()

        #expect(library.search("pelicans").map(\.meeting.title) == ["Standup"])
    }

    @Test func aWindowsLineEndingsFileMovedInFinderIsFoundAgainByItsID() throws {
        let standup = folder.url.appending(path: "2026/2026-10-25-standup.md")
        let crlf = try String(contentsOf: standup, encoding: .utf8).replacingOccurrences(of: "\n", with: "\r\n")
        try FileManager.default.removeItem(at: standup)
        try crlf.write(to: folder.url.appending(path: "2026/moved standup.md"), atomically: true, encoding: .utf8)
        let library = makeLibrary()

        try library.reconcile()

        let index = try library.loadIndex()
        #expect(index.deleted.isEmpty)
        #expect(index.meetings.first { $0.title == "Standup" }?.file == "2026/moved standup.md")
    }

    @Test func searchReadsTheTurnsOfAWindowsLineEndingsFile() throws {
        let standup = folder.url.appending(path: "2026/2026-10-25-standup.md")
        try String(contentsOf: standup, encoding: .utf8).replacingOccurrences(of: "\n", with: "\r\n")
            .write(to: standup, atomically: true, encoding: .utf8)
        let library = makeLibrary()

        try library.reconcile()

        #expect(library.search("export bug").map { $0.snippet } == ["Me: Yesterday I fixed the export bug."])
        #expect(library.search("microsoft").isEmpty, "the frontmatter is not searched")
    }
}
