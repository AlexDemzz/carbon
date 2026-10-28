import CarbonCore
import Foundation
import Testing

/// The Library's Meeting list and Search, over a copy of `Fixtures/Library`.
@MainActor
struct LibraryListTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let newYork = TimeZone(identifier: "America/New_York")!

    init() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Library", withExtension: nil, subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture.appending(path: "Documents/2026"), to: folder.url.appending(path: "2026"))
        try FileManager.default.copyItem(
            at: fixture.appending(path: "Support/meetings.json"), to: support.url.appending(path: "meetings.json"))
    }

    func loadedLibrary() throws -> Library {
        let library = Library(folder: folder.url, supportFolder: support.url)
        try library.load()
        return library
    }

    @Test func meetingsAreListedNewestFirst() throws {
        #expect(try loadedLibrary().meetings.map(\.title) == ["Remote control kickoff", "Standup", "Réunion budget"])
    }

    @Test func aMeetingCarbonWritesJoinsTheListInDateOrder() throws {
        let library = try loadedLibrary()
        let meeting = FinishedMeeting(
            id: UUID(), title: "Design review", start: date("2026-10-26T15:00:00Z"), end: date("2026-10-26T15:30:00Z"),
            timeZone: newYork, language: Locale(identifier: "en_US"), provider: "Unknown", transcriptKind: .fallback)

        try library.create(meeting, transcript: "## Transcript\n\n**Me** [0:00] Hello.\n")

        #expect(library.meetings.map(\.title) == ["Remote control kickoff", "Design review", "Standup", "Réunion budget"])
        #expect(library.meetings[1].markdown.hasSuffix("## Transcript\n\n**Me** [0:00] Hello.\n"))
    }

    @Test func rowsShowDateLengthAndUpToTwoFirstNames() throws {
        #expect(try loadedLibrary().meetings.map { $0.rowDetails(in: newYork) } == [
            "Oct 27 at 10:00 AM · 42 min · Dana, Marcus +1",
            "Oct 25 at 9:30 AM · 1 hr 5 min",
            "Oct 23 at 9:00 AM · 1 min · Élodie",
        ])
    }

    @Test func theTitleBarShowsDateLengthProviderAndMeetingLanguage() throws {
        #expect(try loadedLibrary().meetings.map { $0.titleBarDetails(in: newYork) } == [
            "Oct 27 at 10:00 AM · 42 min · Google Meet · English",
            "Oct 25 at 9:30 AM · 1 hr 5 min · Microsoft Teams · English",
            "Oct 23 at 9:00 AM · 1 min · Zoom · French",
        ])
    }

    // MARK: Search

    func search(_ query: String) throws -> [String] {
        try loadedLibrary().search(query).map { hit in
            hit.snippet.map { "\(hit.meeting.title) | \($0)" } ?? hit.meeting.title
        }
    }

    @Test func anEmptySearchListsEveryMeeting() throws {
        #expect(try search("  ") == ["Remote control kickoff", "Standup", "Réunion budget"])
    }

    @Test func searchFindsTitlesWhateverTheCaseAndAccents() throws {
        #expect(try search("REUNION") == ["Réunion budget"])
    }

    @Test func searchFindsParticipants() throws {
        #expect(try search("elodie") == ["Réunion budget"])
        #expect(try search("nair") == ["Remote control kickoff"])
    }

    @Test func searchFindsWhatWasSaidAndShowsTheFirstMatchingTurn() throws {
        #expect(try search("cafe") == [
            "Remote control kickoff | Speaker A: We met at the café last week and sketched the button layout.",
            "Standup | …are going to take before the CAFE opens.",
        ])
    }

    @Test func aTitleMatchNeedsNoLineUnderTheRow() throws {
        #expect(try search("budget") == ["Réunion budget"])
    }

    @Test func searchSkipsTheFrontmatterAndHeadings() throws {
        #expect(try search("google").isEmpty)
        #expect(try search("transcript").isEmpty)
    }
}
