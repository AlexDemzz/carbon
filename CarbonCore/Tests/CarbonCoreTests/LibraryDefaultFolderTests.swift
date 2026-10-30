import CarbonCore
import Foundation
import Testing

/// Where the Library goes when the person never moved it, launch after launch.
final class LibraryDefaultFolderTests {
    let home = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let defaults: UserDefaults
    let suite = "LibraryDefaultFolderTests-\(UUID().uuidString)"
    var documents: URL { home.url.appending(path: "Documents") }

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    func launch() -> URL {
        Library.folder(savedIn: defaults, key: "libraryFolder", home: home.url, documents: documents, supportFolder: support.url)
    }

    func writeIndex() throws {
        try Data("{}".utf8).write(to: support.url.appending(path: "meetings.json"))
    }

    @Test func aNewLibraryGoesToCarbonInTheHomeFolderOutsideDocuments() {
        #expect(launch().path == home.url.appending(path: "Carbon").path)
    }

    @Test func aNewLibraryStaysInTheHomeFolderOnceItsFirstMeetingWroteMeetingsJSON() throws {
        _ = launch()
        try writeIndex()

        #expect(launch().path == home.url.appending(path: "Carbon").path)
    }

    @Test func aLibraryStartedInDocumentsStaysThereSoItsMeetingsAreNotLost() throws {
        try writeIndex()

        #expect(launch().path == documents.appending(path: "Carbon").path)
    }

    @Test func aFolderThePersonMovedTheLibraryToWins() throws {
        defaults.set("/Users/dana/Notes/Meetings", forKey: "libraryFolder")
        try writeIndex()

        #expect(launch().path == "/Users/dana/Notes/Meetings")
    }
}
