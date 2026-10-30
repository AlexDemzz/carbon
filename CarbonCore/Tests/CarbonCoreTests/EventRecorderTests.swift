import CarbonCore
import Foundation
import Synchronization
import Testing

/// Scripted afternoons with calendar Events: what the Event puts in the file and in `meetings.json`.
@MainActor
struct EventRecorderTests {
    typealias Attendee = CalendarEvent.Attendee

    let library = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let start = date("2026-10-23T13:00:00Z")
    let clock = TestClock(date("2026-10-23T13:00:00Z"))
    let chrome = MeetingApp(bundleID: "com.google.Chrome", name: "Google Chrome")
    let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")

    let me = Attendee(name: "Alex Joly", url: "mailto:alex@example.com", isCurrentUser: true)
    let sam = Attendee(name: "Sam Rivera", url: "mailto:sam@example.com")
    let kim = Attendee(name: "Kim Lee", url: nil)

    static let call: [AudioStream: [TranscribedWord]] = [
        .me: [TranscribedWord(text: "Hi.", start: 1, end: 1.4)],
        .them: [
            TranscribedWord(text: "Hello", start: 2, end: 2.5),
            TranscribedWord(text: "there.", start: 2.6, end: 3),
        ],
    ]

    static let oneVoice = Diarization(
        segments: [.init(start: 2, end: 4, cluster: "S1")],
        clusters: [.init(id: "S1", voice: [1, 0], speechSeconds: 12)])

    /// 13:00–13:30 on Google Meet.
    func sync(attendees: [Attendee]) -> CalendarEvent {
        CalendarEvent(
            id: "sync-ext-id", title: "Weekly sync", start: date("2026-10-23T13:00:00Z"),
            end: date("2026-10-23T13:30:00Z"),
            notes: "Join with Google Meet: https://meet.google.com/abc-defg-hij", attendees: attendees, organizer: sam)
    }

    func makeRecorder(diarizer: ScriptedDiarizer = ScriptedDiarizer([.fail, .fail])) -> Recorder {
        let clock = clock
        let ids = Mutex(0)
        let recorder = Recorder(
            microphone: FakeAudioSource(seconds: 3),
            systemAudio: { _ in FakeAudioSource(seconds: 3) },
            systemAudioPermission: { .granted },
            transcriber: ReplayTranscriber(words: Self.call),
            diarizer: diarizer,
            diarizationTimeout: { _ in .milliseconds(100) },
            library: Library(folder: library.url, supportFolder: support.url, now: { clock.now }),
            inProgressFolder: support.url.appending(path: "InProgress"),
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: {
                ids.withLock { count in
                    count += 1
                    return UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C2\(count)")!
                }
            })
        recorder.detectionLanguage = Locale(identifier: "en_US")
        return recorder
    }

    func markdown(_ name: String) throws -> String {
        try String(contentsOf: library.url.appending(path: "2026/\(name)"), encoding: .utf8)
    }

    func entries() throws -> [NSDictionary] {
        let index = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: support.url.appending(path: "meetings.json")))
                as? NSDictionary)
        return try #require(index["meetings"] as? [NSDictionary])
    }

    @Test func aBrowserCallTakesItsTitleParticipantsAndProviderFromTheEvent() async throws {
        let recorder = makeRecorder()
        let event = sync(attendees: [me, sam, kim])

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [event], [
            (0...1_500, [chrome]),
            (1_501...1_900, []),
        ]))

        #expect(try markdown("2026-10-23-weekly-sync.md") == """
            ---
            provider: Google Meet
            id: 6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21
            date: 2026-10-23T09:00:15-04:00
            title: Weekly sync
            duration: 29:45
            language: en-US
            participants:
              - Sam Rivera <sam@example.com>
              - Kim Lee
            ---

            ## Transcript

            **Me** [0:01] Hi.

            **Them** [0:02] Hello there.

            """)
        let entry = try #require(try entries().first)
        #expect(entry["provider"] as? String == "Google Meet")
        #expect(entry["providerMeetingId"] as? String == "abc-defg-hij")
        #expect(entry["calendarEventId"] as? String == "sync-ext-id")
        #expect(entry["meetingApp"] as? String == "com.google.Chrome")
        #expect(entry["participants"] as? NSArray == [
            ["name": "Sam Rivera", "email": "sam@example.com"], ["name": "Kim Lee"],
        ] as NSArray)
    }

    @Test func aNativeAppKeepsItsOwnProviderWhateverTheEventLinkSays() async throws {
        let recorder = makeRecorder()

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [sync(attendees: [me, sam, kim])], [
            (0...1_500, [zoom]),
            (1_501...1_900, []),
        ]))

        let entry = try #require(try entries().first)
        #expect(entry["provider"] as? String == "Zoom")
        #expect(entry["providerMeetingId"] as? String == "abc-defg-hij")
    }

    @Test func inA1To1TheOtherAttendeesNameReplacesThemInTheFallback() async throws {
        let recorder = makeRecorder()

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [sync(attendees: [me, sam])], [
            (0...1_500, [chrome]),
            (1_501...1_900, []),
        ]))

        #expect(try markdown("2026-10-23-weekly-sync.md").hasSuffix("""
            ## Transcript

            **Me** [0:01] Hi.

            **Sam Rivera** [0:02] Hello there.

            """))
        #expect(try entries().first?["speakers"] as? [NSDictionary] == [[
            "label": "Sam Rivera", "cluster": "Them", "stream": "them", "name": "Sam Rivera", "voicePrintId": NSNull(),
            "match": "attendee1to1", "speechSeconds": 0,
        ]])
    }

    @Test func inA1To1TheLoneSpeakerIsWrittenAsTheOtherAttendee() async throws {
        let recorder = makeRecorder(diarizer: ScriptedDiarizer([.replay(Self.oneVoice)]))

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [sync(attendees: [me, sam])], [
            (0...1_500, [chrome]),
            (1_501...1_900, []),
        ]))

        #expect(try markdown("2026-10-23-weekly-sync.md").hasSuffix("""
            **Sam Rivera** [0:02] Hello there.

            """))
        let speakers = try #require(try entries().first?["speakers"] as? [NSDictionary])
        #expect(speakers.map { $0["label"] as? String } == ["Sam Rivera"])
        #expect(speakers.map { $0["cluster"] as? String } == ["A"])
        #expect(speakers.map { $0["name"] as? String } == ["Sam Rivera"])
        #expect(speakers.map { $0["match"] as? String } == ["attendee1to1"])
    }

    /// Sam remembered as "Sam" with his email, from the voice of `oneVoice`.
    func rememberSam() throws {
        try Data("""
            {"version": 1, "prints": [{
              "id": "11111111-1111-4111-8111-111111111111", "name": "Sam", "email": "sam@example.com",
              "model": "fluidaudio/community-1@0.17.7", "centroid": "AACAPwAAAAA=", "recent": [],
              "meetings": 1, "createdAt": "2026-10-01T10:00:00Z", "lastHeardAt": "2026-10-01T10:00:00Z"
            }]}
            """.utf8).write(to: support.url.appending(path: "voiceprints.json"))
    }

    @Test func aRecognizedVoicePrintNamesTheParticipantKnownOnlyByEmail() async throws {
        try rememberSam()
        let recorder = makeRecorder(diarizer: ScriptedDiarizer([.replay(Self.oneVoice)]))
        let samByEmail = Attendee(name: nil, url: "mailto:sam@example.com")

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [sync(attendees: [me, samByEmail, kim])], [
            (0...1_500, [chrome]),
            (1_501...1_900, []),
        ]))

        #expect(try markdown("2026-10-23-weekly-sync.md").hasSuffix("""
            participants:
              - Sam <sam@example.com>
              - Kim Lee
            ---

            ## Transcript

            **Me** [0:01] Hi.

            **Sam** [0:02] Hello there.

            """))
    }

    @Test func aRecognizedVoicePrintPrefersTheParticipantWithItsEmailOverOneWithItsName() async throws {
        try rememberSam()
        let recorder = makeRecorder(diarizer: ScriptedDiarizer([.replay(Self.oneVoice)]))
        let samByName = Attendee(name: "Sam", url: nil)
        let samByEmail = Attendee(name: nil, url: "mailto:sam@example.com")

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [sync(attendees: [me, samByName, samByEmail])], [
            (0...1_500, [chrome]),
            (1_501...1_900, []),
        ]))

        #expect(try markdown("2026-10-23-weekly-sync.md").contains("""
            participants:
              - Sam
              - Sam <sam@example.com>
            ---
            """))
    }

    @Test func aRecognizedVoicePrintTakesTheCalendarsNameOfTheParticipantWithItsEmail() async throws {
        try rememberSam()
        let recorder = makeRecorder(diarizer: ScriptedDiarizer([.replay(Self.oneVoice)]))

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [sync(attendees: [me, sam, kim])], [
            (0...1_500, [chrome]),
            (1_501...1_900, []),
        ]))

        #expect(try markdown("2026-10-23-weekly-sync.md").hasSuffix("""
            participants:
              - Sam Rivera <sam@example.com>
              - Kim Lee
            ---

            ## Transcript

            **Me** [0:01] Hi.

            **Sam Rivera** [0:02] Hello there.

            """))
        let speakers = try #require(try entries().first?["speakers"] as? [NSDictionary])
        #expect(speakers.map { $0["voicePrintId"] as? String } == ["11111111-1111-4111-8111-111111111111"])
    }

    @Test func backToBackEventsOnTheSameCallBecomeTwoMeetings() async throws {
        let recorder = makeRecorder()
        let review = CalendarEvent(
            id: "review-ext-id", title: "Design review", start: date("2026-10-23T13:30:00Z"),
            end: date("2026-10-23T14:00:00Z"), notes: "https://meet.google.com/xyz-abcd-efg", attendees: [me, sam, kim])

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [sync(attendees: [me, sam, kim]), review], [
            (0...3_000, [chrome]),
            (3_001...3_700, []),
        ]))

        let entries = try entries()
        #expect(entries.map { $0["title"] as? String } == ["Weekly sync", "Design review"])
        #expect(entries.map { $0["start"] as? String } == ["2026-10-23T09:00:15-04:00", "2026-10-23T09:30:05-04:00"])
        #expect(entries.map { $0["end"] as? String } == ["2026-10-23T09:30:00-04:00", "2026-10-23T10:00:00-04:00"])
        #expect(entries.map { $0["providerMeetingId"] as? String } == ["abc-defg-hij", "xyz-abcd-efg"])
    }

    @Test func theInProgressStateRecordsTheMatchedEvent() async throws {
        let recorder = makeRecorder()

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, events: [sync(attendees: [me, sam])], [
            (0...20, [chrome]),
        ]))

        let state = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: support.url.appending(
                path: "InProgress/6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21/state.json"))) as? NSDictionary)
        #expect((state["event"] as? NSDictionary)?["id"] as? String == "sync-ext-id")
        if case .live(let meeting) = recorder.state {
            #expect(meeting.title == "Weekly sync")
            #expect(meeting.provider == "Google Meet")
        } else {
            Issue.record("the Meeting is live")
        }
        await recorder.discard()
    }
}
