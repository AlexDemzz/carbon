@preconcurrency import AVFoundation
import CarbonCore
import Foundation
import Testing

@MainActor
struct RecoveryTests {
    let library = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let crashed = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-23T13:15:00Z"))
    let meetingID = UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")!

    var inProgress: URL { support.url.appending(path: "InProgress") }
    var folder: URL { inProgress.appending(path: meetingID.uuidString) }

    func makeRecorder(
        transcriber: any Transcriber, me: Double = 3, them: Double = 3
    ) -> Recorder {
        let clock = clock
        let meetingID = meetingID
        return Recorder(
            microphone: FakeAudioSource(seconds: me),
            systemAudio: FakeAudioSource(seconds: them),
            systemAudioPermission: { .granted },
            transcriber: transcriber,
            diarizer: ScriptedDiarizer([.fail, .fail]),
            diarizationTimeout: { _ in .milliseconds(100) },
            library: Library(folder: library.url, supportFolder: support.url, now: { clock.now }),
            inProgressFolder: inProgress,
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: { meetingID })
    }

    /// Records a Meeting and leaves its in-progress folder as a crash would: what was flushed, never closed.
    func crashDuringAMeeting(me: Double, them: Double, language: String = "en_US") async throws {
        let recorder = makeRecorder(transcriber: ReplayTranscriber(words: [:]), me: me, them: them)
        try await recorder.start(language: Locale(identifier: language))
        let onDisk = crashed.url.appending(path: meetingID.uuidString)
        try FileManager.default.copyItem(at: folder, to: onDisk)
        await recorder.discard()
        try FileManager.default.copyItem(at: onDisk, to: folder)
    }

    @Test func theNextLaunchFinishesAMeetingKilledBetweenFlushesFromTheFlushedAudio() async throws {
        try await crashDuringAMeeting(me: 12, them: 7)
        clock.advance(by: 3600)
        let transcriber = try ReplayTranscriber(me: "me-words")
        let relaunched = makeRecorder(transcriber: transcriber)

        let recoveries = await relaunched.recover()

        let file = library.url.appending(path: "2026/2026-10-23-meeting-oct-23-9-15-am.md")
        #expect(recoveries == [.recovered(title: "Meeting Oct 23, 9:15 AM", file: file)])
        #expect(transcriber.secondsHeard == [.me: 10, .them: 5], "only what was flushed every 5 s")
        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(markdown == """
            ---
            provider: Unknown
            id: 6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21
            date: 2026-10-23T09:15:00-04:00
            title: Meeting Oct 23, 9:15 AM
            duration: 0:10
            language: en-US
            participants: []
            ---

            ## Transcript

            **Me** [0:01] Hello everybody, can you hear me?

            **Me** [0:15] Okay, let's start with the agenda.

            """)
        let entries = try #require(try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])
        #expect(entries.map { $0["end"] as? String } == ["2026-10-23T09:15:10-04:00"], "the end of the recorded audio")
        #expect(try FileManager.default.contentsOfDirectory(atPath: inProgress.path).isEmpty)

        #expect(await makeRecorder(transcriber: transcriber).recover() == [], "nothing is left to recover twice")
    }

    @Test func aRecoveredMeetingIsTranscribedInTheMeetingLanguageSavedInItsState() async throws {
        try await crashDuringAMeeting(me: 6, them: 6, language: "fr_FR")
        let transcriber = ReplayTranscriber(words: [:])

        _ = await makeRecorder(transcriber: transcriber).recover()

        #expect(transcriber.localesHeard == [Locale(identifier: "fr_FR"), Locale(identifier: "fr_FR")], "Me and Them")
        let entries = try #require(try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])
        #expect(entries.map { $0["language"] as? String } == ["fr-FR"])
    }

    @Test func aMeetingWhoseAudioCantBeReadIsDiscardedAndReported() async throws {
        try await crashDuringAMeeting(me: 6, them: 6)
        for stream in ["me.caf", "them.caf"] {
            try Data("not audio".utf8).write(to: folder.appending(path: stream))
        }

        let recoveries = await makeRecorder(transcriber: ReplayTranscriber(words: [:])).recover()

        #expect(recoveries == [.discarded(title: "Meeting Oct 23, 9:15 AM")])
        #expect(try FileManager.default.contentsOfDirectory(atPath: inProgress.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.url.path).isEmpty)
    }

    @Test func aMeetingKilledBeforeItsFirstFlushHasNoAudioAndIsDiscarded() async throws {
        try await crashDuringAMeeting(me: 3, them: 3)

        let recoveries = await makeRecorder(transcriber: ReplayTranscriber(words: [:])).recover()

        #expect(recoveries == [.discarded(title: "Meeting Oct 23, 9:15 AM")])
        #expect(try FileManager.default.contentsOfDirectory(atPath: inProgress.path).isEmpty)
    }

    @Test func afterTwoRecoveriesThatNeverFinishedTheFolderIsSetAsideAndNoLongerRetried() async throws {
        try await crashDuringAMeeting(me: 6, them: 6)
        let crashing = FailingTranscriber()

        #expect(await makeRecorder(transcriber: crashing).recover() == [])
        #expect(try jsonObject(at: folder.appending(path: "state.json"))["recoveryAttempts"] as? Int == 1)
        #expect(await makeRecorder(transcriber: crashing).recover() == [])
        #expect(try jsonObject(at: folder.appending(path: "state.json"))["recoveryAttempts"] as? Int == 2)

        let transcriber = try ReplayTranscriber(me: "me-words")
        #expect(await makeRecorder(transcriber: transcriber).recover() == [.failed(title: "Meeting Oct 23, 9:15 AM")])
        #expect(transcriber.localesHeard.isEmpty, "not retried")
        #expect(try FileManager.default.contentsOfDirectory(atPath: inProgress.path) == ["Failed"])
        let failed = inProgress.appending(path: "Failed/\(meetingID.uuidString)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: failed.path).sorted() == ["me.caf", "state.json", "them.caf"])
        #expect(await makeRecorder(transcriber: transcriber).recover() == [], "Failed/ is never looked at again")
    }

    func jsonObject(at url: URL) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
    }
}

/// A transcriber that never gets going, standing in for a recovery that dies before it finishes.
final class FailingTranscriber: Transcriber {
    struct Failed: Error {}

    func start(locale: Locale, stream: AudioStream) async throws -> any TranscriptionSession {
        throw Failed()
    }
}
