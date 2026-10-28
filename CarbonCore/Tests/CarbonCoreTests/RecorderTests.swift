@preconcurrency import AVFoundation
import CarbonCore
import CryptoKit
import Foundation
import Testing

@MainActor
struct RecorderTests {
    let library = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-23T13:15:00Z"))
    let meetingID = UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")!

    func makeRecorder(transcriber: ReplayTranscriber, seconds: Double = 3) -> Recorder {
        let clock = clock
        let meetingID = meetingID
        return Recorder(
            audioSource: FakeAudioSource(seconds: seconds),
            transcriber: transcriber,
            library: Library(folder: library.url, supportFolder: support.url, now: { clock.now }),
            inProgressFolder: support.url.appending(path: "InProgress"),
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: { meetingID }
        )
    }

    @Test func stoppingAManualMeetingWritesItsMarkdownFileAndIndexEntry() async throws {
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(fixture: "me-words"))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 125)
        let file = try await recorder.stop()

        #expect(file == library.url.appending(path: "2026/2026-10-23-meeting-oct-23-9-15-am.md"))
        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(markdown == """
            ---
            provider: Unknown
            id: 6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21
            date: 2026-10-23T09:15:00-04:00
            title: Meeting Oct 23, 9:15 AM
            duration: 2:05
            language: en-US
            participants: []
            ---

            ## Transcript

            **Me** [0:01] Hello everybody, can you hear me?

            **Me** [0:15] Okay, let's start with the agenda.

            """)

        let index = try jsonObject(at: support.url.appending(path: "meetings.json"))
        let hash = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        #expect(index == [
            "version": 1,
            "meetings": [[
                "id": "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21",
                "file": "2026/2026-10-23-meeting-oct-23-9-15-am.md",
                "title": "Meeting Oct 23, 9:15 AM",
                "start": "2026-10-23T09:15:00-04:00",
                "end": "2026-10-23T09:17:05-04:00",
                "language": "en-US",
                "provider": "Unknown",
                "participants": [],
                "speakers": [],
                "transcript": "fallback",
                "summary": "off",
                "color": NSNull(),
                "writtenHash": hash,
            ]],
            "deleted": [],
        ] as NSDictionary)
    }

    @Test func aLiveMeetingRecordsIntoItsInProgressFolderUntilItIsStopped() async throws {
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(fixture: "me-words"), seconds: 7)
        let folder = support.url.appending(path: "InProgress/6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")

        try await recorder.start(language: Locale(identifier: "en_US"))

        #expect(try jsonObject(at: folder.appending(path: "state.json")) == [
            "id": "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21",
            "start": "2026-10-23T09:15:00-04:00",
            "language": "en-US",
            "mode": "manual",
            "recoveryAttempts": 0,
        ] as NSDictionary)
        let audio = try AVAudioFile(forReading: folder.appending(path: "me.caf"))
        #expect(audio.fileFormat.sampleRate == 16_000)
        #expect(Double(audio.length) / 16_000 == 5, "7 s heard, the first 5 s flushed")

        clock.advance(by: 60)
        try await recorder.stop()

        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func discardingAMeetingKeepsNothing() async throws {
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(fixture: "me-words"))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 60)
        await recorder.discard()

        #expect(recorder.state == .idle)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.url.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.url.appending(path: "InProgress").path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: support.url.appending(path: "meetings.json").path))
    }

    @Test func theMeetingIsTranscribedInTheChosenLanguage() async throws {
        let transcriber = try ReplayTranscriber(fixture: "me-words")
        let recorder = makeRecorder(transcriber: transcriber)

        try await recorder.start(language: Locale(identifier: "en_US"))
        #expect(recorder.state == .live(LiveMeeting(
            id: meetingID, title: "Meeting Oct 23, 9:15 AM", start: date("2026-10-23T13:15:00Z"),
            language: Locale(identifier: "en_US"))))
        try await recorder.stop()

        #expect(transcriber.localesHeard == [Locale(identifier: "en_US")])
        #expect(recorder.state == .idle)
    }

    func jsonObject(at url: URL) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
    }
}
