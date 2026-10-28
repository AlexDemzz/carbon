import CarbonCore
import Foundation
import Testing

@MainActor
struct LibraryTests {
    let folder = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-27T14:00:00Z"))
    let newYork = TimeZone(identifier: "America/New_York")!

    func makeLibrary() -> Library {
        let clock = clock
        return Library(folder: folder.url, supportFolder: support.url, now: { clock.now })
    }

    func meeting(_ title: String, start: String = "2026-10-27T14:00:00Z") -> FinishedMeeting {
        FinishedMeeting(
            id: UUID(), title: title, start: date(start), end: date(start).addingTimeInterval(1_049),
            timeZone: newYork, language: Locale(identifier: "en_US"), provider: "Google Meet",
            participants: [Participant(name: "Sam Rivera", email: "sam@example.com"), Participant(name: "Priya Nair")],
            transcriptKind: .fallback)
    }

    func relativePath(_ url: URL) -> String {
        String(url.path.dropFirst(folder.url.path.count + 1))
    }

    @Test(arguments: [
        ("Remote control kickoff", "2026/2026-10-27-remote-control-kickoff.md"),
        ("Réunion d'équipe : budget 2027 !", "2026/2026-10-27-reunion-d-equipe-budget-2027.md"),
        ("Straße — Œuvre Ångström", "2026/2026-10-27-strasse-oeuvre-angstrom.md"),
        ("Quarterly planning review with the platform infrastructure and developer experience teams",
         "2026/2026-10-27-quarterly-planning-review-with-the-platform-infrastructure.md"),
        ("会议", "2026/2026-10-27-hui-yi.md"),
        ("!!!", "2026/2026-10-27-meeting.md"),
    ])
    func theFileNameIsTheDateAndASlugOfTheTitle(title: String, expected: String) throws {
        let url = try makeLibrary().create(meeting(title), transcript: "## Transcript\n")
        #expect(relativePath(url) == expected)
    }

    @Test func theFileGoesInTheYearOfTheMeetingInItsTimeZone() throws {
        let url = try makeLibrary().create(meeting("New year", start: "2027-01-01T03:00:00Z"), transcript: "## Transcript\n")
        #expect(relativePath(url) == "2026/2026-12-31-new-year.md")
    }

    @Test func aSecondMeetingWithTheSameTitleOnTheSameDayGetsANumber() throws {
        let library = makeLibrary()
        let first = try library.create(meeting("Standup"), transcript: "## Transcript\n")
        let second = try library.create(meeting("Standup"), transcript: "## Transcript\n")
        let third = try library.create(meeting("Standup"), transcript: "## Transcript\n")

        #expect([first, second, third].map(relativePath) == [
            "2026/2026-10-27-standup.md", "2026/2026-10-27-standup-2.md", "2026/2026-10-27-standup-3.md",
        ])
        #expect(try library.loadIndex().meetings.map(\.file) == [first, second, third].map(relativePath))
    }

    @Test func aNameTakenByAFileCarbonDoesNotKnowIsSkipped() throws {
        let year = folder.url.appending(path: "2026")
        try FileManager.default.createDirectory(at: year, withIntermediateDirectories: true)
        try "my notes".write(to: year.appending(path: "2026-10-27-standup.md"), atomically: true, encoding: .utf8)

        let url = try makeLibrary().create(meeting("Standup"), transcript: "## Transcript\n")

        #expect(relativePath(url) == "2026/2026-10-27-standup-2.md")
        #expect(try String(contentsOf: year.appending(path: "2026-10-27-standup.md"), encoding: .utf8) == "my notes")
    }

    @Test func participantsAndTitlesThatNeedQuotingStayValidYAML() throws {
        let url = try makeLibrary().create(meeting("Q4: \"plan\" review"), transcript: "## Transcript\n")
        let markdown = try String(contentsOf: url, encoding: .utf8)

        #expect(markdown.contains("\ntitle: \"Q4: \\\"plan\\\" review\"\n"))
        #expect(markdown.contains("""

            participants:
              - Sam Rivera <sam@example.com>
              - Priya Nair
            ---

            ## Transcript

            """))
    }

    // MARK: Backups

    func backups() throws -> [String] {
        let url = support.url.appending(path: "Backups")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    @Test func theFirstSaveOfALaunchBacksUpTheIndexAsItWas() throws {
        try makeLibrary().create(meeting("Monday"), transcript: "## Transcript\n")
        #expect(try backups().isEmpty, "nothing to back up before the first index exists")

        let relaunched = makeLibrary()
        clock.advance(by: 3_600)
        try relaunched.create(meeting("Tuesday"), transcript: "## Transcript\n")

        #expect(try backups() == ["meetings-20261027T150000Z.json"])
        let backup = try JSONDecoder().decode(
            MeetingIndex.self, from: Data(contentsOf: support.url.appending(path: "Backups/meetings-20261027T150000Z.json")))
        #expect(backup.meetings.map(\.title) == ["Monday"])
    }

    @Test func laterSavesBackUpAtMostOnceADay() throws {
        try makeLibrary().create(meeting("Setup"), transcript: "## Transcript\n")
        let library = makeLibrary()

        try library.create(meeting("One"), transcript: "## Transcript\n")
        clock.advance(by: 23 * 3_600)
        try library.create(meeting("Two"), transcript: "## Transcript\n")
        clock.advance(by: 3_600)
        try library.create(meeting("Three"), transcript: "## Transcript\n")

        #expect(try backups() == ["meetings-20261027T140000Z.json", "meetings-20261028T140000Z.json"])
    }

    @Test func onlyTheFourteenNewestBackupsAreKept() throws {
        try makeLibrary().create(meeting("Setup"), transcript: "## Transcript\n")
        let library = makeLibrary()
        for day in 1...16 {
            try library.create(meeting("Day \(day)"), transcript: "## Transcript\n")
            clock.advance(by: 24 * 3_600)
        }

        let kept = try backups()
        #expect(kept.count == 14)
        #expect(kept.first == "meetings-20261029T140000Z.json")
        #expect(kept.last == "meetings-20261111T140000Z.json")
    }
}
