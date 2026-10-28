import CarbonCore
import Foundation
import Testing

/// Settings › General › Library folder › Change…: the whole Library moves to the folder the person picks.
@MainActor
struct LibraryMoveTests {
    let documents = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let elsewhere = try! TemporaryFolder()
    var folder: URL { documents.url.appending(path: "Carbon") }

    init() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Library", withExtension: nil, subdirectory: "Fixtures"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.appending(path: "Documents/2026"), to: folder.appending(path: "2026"))
        try FileManager.default.copyItem(
            at: fixture.appending(path: "Support/meetings.json"), to: support.url.appending(path: "meetings.json"))
    }

    func makeLibrary() throws -> Library {
        let library = Library(folder: folder, supportFolder: support.url)
        try library.load()
        return library
    }

    @Test func theConfirmationCountsEveryFileInTheLibraryIncludingThePersonsOwnNotes() throws {
        let library = try makeLibrary()

        #expect(try library.filesToMove() == 4)
    }

    @Test func movingTakesEveryFileToTheNewFolderAndTheListFollows() throws {
        let library = try makeLibrary()
        let destination = elsewhere.url.appending(path: "Dropbox/Meetings")

        try library.move(to: destination)

        #expect(library.folder == destination)
        #expect(!FileManager.default.fileExists(atPath: folder.path), "the old folder is gone")
        let moved = try FileManager.default.contentsOfDirectory(atPath: destination.appending(path: "2026").path).sorted()
        #expect(moved == [
            "2026-10-23-reunion-budget.md", "2026-10-25-standup.md", "2026-10-27-remote-control-kickoff.md", "my-own-notes.md",
        ])
        #expect(library.meetings.map(\.file) == [
            destination.appending(path: "2026/2026-10-27-remote-control-kickoff.md"),
            destination.appending(path: "2026/2026-10-25-standup.md"),
            destination.appending(path: "2026/2026-10-23-reunion-budget.md"),
        ])
        #expect(try library.loadIndex().deleted.isEmpty, "no Meeting was lost on the way")
    }

    @Test func movingIntoAFolderThatHasOtherFilesKeepsThem() throws {
        let library = try makeLibrary()
        let destination = elsewhere.url
        try FileManager.default.createDirectory(at: destination.appending(path: "2026"), withIntermediateDirectories: true)
        try "Mine.".write(to: destination.appending(path: "2026/groceries.md"), atomically: true, encoding: .utf8)

        try library.move(to: destination)

        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.appending(path: "2026").path).count == 5)
        #expect(library.meetings.count == 3)
    }

    @Test func aFileAlreadyAtTheSamePathInTheNewFolderStopsTheMoveBeforeAnythingMoves() throws {
        let library = try makeLibrary()
        let destination = elsewhere.url
        try FileManager.default.createDirectory(at: destination.appending(path: "2026"), withIntermediateDirectories: true)
        try "Other.".write(to: destination.appending(path: "2026/2026-10-25-standup.md"), atomically: true, encoding: .utf8)

        #expect(throws: LibraryMoveError.destinationHasFile("2026/2026-10-25-standup.md")) {
            try library.move(to: destination)
        }
        #expect(library.folder == folder)
        #expect(try library.filesToMove() == 4)
    }

    @Test func theNewFolderCannotBeInsideTheLibrary() throws {
        let library = try makeLibrary()

        #expect(throws: LibraryMoveError.destinationInsideLibrary) {
            try library.move(to: folder.appending(path: "Archive"))
        }
        #expect(throws: LibraryMoveError.destinationInsideLibrary) {
            try library.move(to: folder)
        }
        #expect(try library.filesToMove() == 4)
    }
}
