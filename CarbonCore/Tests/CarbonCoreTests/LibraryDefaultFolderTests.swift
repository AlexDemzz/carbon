import CarbonCore
import Foundation
import Testing

/// Where the Library goes when the person never moved it.
struct LibraryDefaultFolderTests {
    let home = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    var documents: URL { home.url.appending(path: "Documents") }

    @Test func aNewLibraryGoesToCarbonInTheHomeFolderOutsideDocuments() {
        let folder = Library.defaultFolder(home: home.url, documents: documents, supportFolder: support.url)

        #expect(folder.path == home.url.appending(path: "Carbon").path)
    }

    @Test func aLibraryStartedInDocumentsStaysThereSoItsMeetingsAreNotLost() throws {
        try Data("{}".utf8).write(to: support.url.appending(path: "meetings.json"))

        let folder = Library.defaultFolder(home: home.url, documents: documents, supportFolder: support.url)

        #expect(folder.path == documents.appending(path: "Carbon").path)
    }
}
