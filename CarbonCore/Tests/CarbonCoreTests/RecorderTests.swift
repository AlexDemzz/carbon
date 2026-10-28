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

    /// The Library, whose Delete moves files into `trash`.
    func makeLibrary(trash: URL? = nil) -> Library {
        let clock = clock
        return Library(
            folder: library.url, supportFolder: support.url, now: { clock.now },
            moveToTrash: { url in
                guard let trash else { return }
                try FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent))
            })
    }

    func makeRecorder(
        transcriber: ReplayTranscriber, seconds: Double = 3,
        microphone: (any AudioSource)? = nil, systemAudio: (any AudioSource)? = nil,
        systemAudioPermission: SystemAudioPermission = .granted,
        diarizer: ScriptedDiarizer = ScriptedDiarizer([.fail, .fail]),
        keepAudio: Bool = false, trash: URL? = nil, summarizer: (any Summarizer)? = nil,
        recognizesVoices: Bool = true
    ) -> Recorder {
        let clock = clock
        let meetingID = meetingID
        let library = makeLibrary(trash: trash)
        library.recognizesVoices = recognizesVoices
        let them = systemAudio ?? FakeAudioSource(seconds: seconds)
        return Recorder(
            microphone: microphone ?? FakeAudioSource(seconds: seconds),
            systemAudio: { _ in them },
            systemAudioPermission: { systemAudioPermission },
            transcriber: transcriber,
            diarizer: diarizer,
            diarizationTimeout: { _ in .milliseconds(100) },
            summarizer: summarizer ?? NoSummarizer(),
            library: library,
            keepAudio: { keepAudio },
            inProgressFolder: support.url.appending(path: "InProgress"),
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: { meetingID }
        )
    }

    @Test func stoppingAManualMeetingWritesItsMarkdownFileAndIndexEntry() async throws {
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(me: "me-words"))

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

    @Test func theSummarizerGetsTheTranscriptInTheMeetingLanguageOnlyOnceTheFileIsOnDisk() async throws {
        let file = library.url.appending(path: "2026/2026-10-23-meeting-oct-23-9-15-am.md")
        let summarizer = SpySummarizer(file: file)
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(me: "me-words"), summarizer: summarizer)

        try await recorder.start(language: Locale(identifier: "fr_FR"))
        clock.advance(by: 125)
        try await recorder.stop()

        #expect(summarizer.calls == [SpySummarizer.Call(
            transcript: """
                ## Transcript

                **Me** [0:01] Hello everybody, can you hear me?

                **Me** [0:15] Okay, let's start with the agenda.

                """,
            language: Locale(identifier: "fr_FR"),
            fileWasOnDisk: true)])
        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(!markdown.contains("## Summary"))
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"]
            as? [NSDictionary])?.first)
        #expect(entry["summary"] as? String == "off")
    }

    @Test func aSummarizerThatThrowsStillLeavesTheMeetingFiledWithSummaryOff() async throws {
        let file = library.url.appending(path: "2026/2026-10-23-meeting-oct-23-9-15-am.md")
        let recorder = makeRecorder(
            transcriber: try ReplayTranscriber(me: "me-words"), summarizer: SpySummarizer(file: file, fails: true))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 125)
        let filed = try await recorder.stop()

        #expect(filed == file)
        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            ## Transcript

            **Me** [0:01] Hello everybody, can you hear me?

            **Me** [0:15] Okay, let's start with the agenda.

            """))
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"]
            as? [NSDictionary])?.first)
        #expect(entry["summary"] as? String == "off")
        #expect(!FileManager.default.fileExists(
            atPath: support.url.appending(path: "InProgress/6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21").path))
    }

    @Test func aLiveMeetingRecordsIntoItsInProgressFolderUntilItIsStopped() async throws {
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(me: "me-words"), seconds: 7)
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
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(me: "me-words"))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 60)
        await recorder.discard()

        #expect(recorder.state == .idle)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.url.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.url.appending(path: "InProgress").path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: support.url.appending(path: "meetings.json").path))
    }

    @Test func theMeetingIsTranscribedInTheChosenLanguage() async throws {
        let transcriber = try ReplayTranscriber(me: "me-words")
        let recorder = makeRecorder(transcriber: transcriber)

        try await recorder.start(language: Locale(identifier: "en_US"))
        #expect(recorder.state == .live(LiveMeeting(
            id: meetingID, title: "Meeting Oct 23, 9:15 AM", start: date("2026-10-23T13:15:00Z"),
            language: Locale(identifier: "en_US"))))
        try await recorder.stop()

        #expect(transcriber.localesHeard == [Locale(identifier: "en_US"), Locale(identifier: "en_US")], "Me and Them")
        #expect(recorder.state == .idle)
    }

    @Test func aMeetingTranscribesTheMicAsMeAndTheCallsAudioAsThem() async throws {
        let recorder = makeRecorder(
            transcriber: try ReplayTranscriber(me: "ami-ES2004a-me-opening", them: "ami-ES2004a-them-opening"),
            microphone: try WAVAudioSource(fixture: "ami-ES2004a-me-clip"),
            systemAudio: try WAVAudioSource(fixture: "ami-ES2004a-them-clip"))
        let folder = support.url.appending(path: "InProgress/6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")

        try await recorder.start(language: Locale(identifier: "en_US"))

        for stream in ["me.caf", "them.caf"] {
            let audio = try AVAudioFile(forReading: folder.appending(path: stream))
            #expect(Double(audio.length) / audio.fileFormat.sampleRate == 5, "\(stream): 6 s heard, the first 5 s flushed")
        }

        clock.advance(by: 40)
        let file = try await recorder.stop()

        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(markdown.hasSuffix("""
            ---

            ## Transcript

            **Me** [0:10] Are we - we're not allowed to dim the lights, so people can see that a bit better. Am I supposed to be standing up there? Um, yeah.

            **Them** [0:24] So we've got both of these clipped on. Is she gonna answer me or not?

            **Me** [0:29] Yeah, I've got. Yes.

            **Them** [0:31] Right, both of them. Okay.

            """))
    }

    static let twoVoices = Diarization(
        segments: [
            .init(start: 2, end: 4, cluster: "S2"),
            .init(start: 20, end: 23, cluster: "S1"),
        ],
        clusters: [
            .init(id: "S1", centroid: [1, 0], speechSeconds: 3),
            .init(id: "S2", centroid: [0.6, 0.8], speechSeconds: 12.5),
        ])

    static let groupCall: [AudioStream: [TranscribedWord]] = [
        .me: [TranscribedWord(text: "Hi.", start: 1, end: 1.4)],
        .them: [
            TranscribedWord(text: "Hello", start: 2, end: 2.5),
            TranscribedWord(text: "all.", start: 2.6, end: 3),
            TranscribedWord(text: "Morning.", start: 20.5, end: 21),
        ],
    ]

    @Test func theCallsAudioIsSplitIntoSpeakersLetteredByTheirFirstWord() async throws {
        let diarizer = ScriptedDiarizer([.replay(Self.twoVoices)])
        let recorder = makeRecorder(transcriber: ReplayTranscriber(words: Self.groupCall), diarizer: diarizer)

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(diarizer.audioHeard.map(\.lastPathComponent) == ["them.caf"])
        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            ---

            ## Transcript

            **Me** [0:01] Hi.

            **Speaker A** [0:02] Hello all.

            **Speaker B** [0:20] Morning.

            """))
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])?.first)
        #expect(entry["transcript"] as? String == "speakers")
        #expect(entry["speakers"] as? NSArray == [
            [
                "label": "Speaker A", "cluster": "A", "name": NSNull(), "voicePrintId": NSNull(), "match": NSNull(),
                "speechSeconds": 12.5, "centroid": "mpkZP83MTD8=",
            ],
            [
                "label": "Speaker B", "cluster": "B", "name": NSNull(), "voicePrintId": NSNull(), "match": NSNull(),
                "speechSeconds": 3, "centroid": "AACAPwAAAAA=",
            ],
        ] as NSArray)
    }

    /// Sam was named in an earlier Meeting with the voice of cluster S2, [0.6, 0.8].
    func rememberSam() throws {
        try Data("""
            {"version": 1, "prints": [{
              "id": "11111111-1111-4111-8111-111111111111", "name": "Sam Rivera", "email": "sam@example.com",
              "model": "fluidaudio/community-1@0.17.7", "centroid": "mpkZP83MTD8=", "recent": [],
              "meetings": 1, "createdAt": "2026-10-01T10:00:00Z", "lastHeardAt": "2026-10-01T10:00:00Z"
            }]}
            """.utf8).write(to: support.url.appending(path: "voiceprints.json"))
    }

    @Test func aRememberedVoiceIsNamedInTheFirstWrite() async throws {
        try rememberSam()
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall), diarizer: ScriptedDiarizer([.replay(Self.twoVoices)]))
        var diagnostics: [String] = []
        recorder.onDiagnostic = { diagnostics.append($0) }

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            participants:
              - Sam Rivera <sam@example.com>
            ---

            ## Transcript

            **Me** [0:01] Hi.

            **Sam Rivera** [0:02] Hello all.

            **Speaker B** [0:20] Morning.

            """))
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])?.first)
        #expect(entry["speakers"] as? NSArray == [
            [
                "label": "Sam Rivera", "cluster": "A", "name": "Sam Rivera",
                "voicePrintId": "11111111-1111-4111-8111-111111111111", "match": "auto", "distance": 0,
                "speechSeconds": 12.5, "centroid": "mpkZP83MTD8=",
            ],
            [
                "label": "Speaker B", "cluster": "B", "name": NSNull(), "voicePrintId": NSNull(), "match": NSNull(),
                "speechSeconds": 3, "centroid": "AACAPwAAAAA=",
            ],
        ] as NSArray)
        let print = try #require((try jsonObject(at: support.url.appending(path: "voiceprints.json"))["prints"] as? [NSDictionary])?.first)
        #expect(print["meetings"] as? Int == 2)
        #expect(print["recent"] as? [String] == ["mpkZP83MTD8="])
        #expect(print["lastHeardAt"] as? String == "2026-10-23T13:15:00Z")
        #expect(diagnostics == ["Voice Print best distance 0.000 for Speaker A: matched"])
    }

    @Test func withRecognitionOffARememberedVoiceStaysUnnamed() async throws {
        try rememberSam()
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall), diarizer: ScriptedDiarizer([.replay(Self.twoVoices)]),
            recognizesVoices: false)

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Speaker A** [0:02] Hello all."))
        let print = try #require((try jsonObject(at: support.url.appending(path: "voiceprints.json"))["prints"] as? [NSDictionary])?.first)
        #expect(print["meetings"] as? Int == 1)
    }

    @Test(arguments: [ScriptedDiarizer.Outcome.fail, .hang])
    func whenDiarizationFailsTwiceTheFileFallsBackToMeAndThem(outcome: ScriptedDiarizer.Outcome) async throws {
        let diarizer = ScriptedDiarizer([outcome, outcome])
        let recorder = makeRecorder(transcriber: ReplayTranscriber(words: Self.groupCall), diarizer: diarizer)

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(diarizer.audioHeard.count == 2, "one retry")
        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            ---

            ## Transcript

            **Me** [0:01] Hi.

            **Them** [0:02] Hello all.

            **Them** [0:20] Morning.

            """))
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])?.first)
        #expect(entry["transcript"] as? String == "fallback")
        #expect(entry["speakers"] as? NSArray == [])
    }

    @Test func aRetryAfterAHangStillGivesSpeakers() async throws {
        let diarizer = ScriptedDiarizer([.hang, .replay(Self.twoVoices)])
        let recorder = makeRecorder(transcriber: ReplayTranscriber(words: Self.groupCall), diarizer: diarizer)

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Speaker B** [0:20] Morning."))
    }

    @Test func theWatchdogAllowsTwoMinutesPlusTenSecondsPerAudioMinute() {
        #expect(Recorder.diarizationTimeout(forAudio: 0) == .seconds(120))
        #expect(Recorder.diarizationTimeout(forAudio: 30 * 60) == .seconds(420))
        #expect(Recorder.diarizationTimeout(forAudio: 90) == .seconds(135))
    }

    @Test func withoutSystemAudioRecordingPermissionNoMeetingStarts() async throws {
        let recorder = makeRecorder(
            transcriber: try ReplayTranscriber(me: "me-words"), systemAudioPermission: .denied)

        await #expect(throws: Recorder.Failure.systemAudioRecordingDenied) {
            try await recorder.start(language: Locale(identifier: "en_US"))
        }

        #expect(recorder.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: support.url.appending(path: "InProgress").path))
    }

    @Test(arguments: [SystemAudioPermission.notDetermined, .unknown])
    func aMeetingStillStartsWhenThePermissionIsNotKnownToBeDenied(permission: SystemAudioPermission) async throws {
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(me: "me-words"), systemAudioPermission: permission)

        try await recorder.start(language: Locale(identifier: "en_US"))

        guard case .live = recorder.state else {
            Issue.record("expected a live Meeting, got \(recorder.state)")
            return
        }
        await recorder.discard()
    }

    @Test func withKeepAudioTheMeetingsAudioIsKeptAsStereoAACNextToItsFileMeLeftThemRight() async throws {
        let trash = try TemporaryFolder()
        let recorder = makeRecorder(
            transcriber: try ReplayTranscriber(me: "me-words"),
            microphone: FakeAudioSource(seconds: 4), systemAudio: FakeAudioSource(seconds: 0),
            keepAudio: true, trash: trash.url)

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 4)
        try await recorder.stop()

        let audio = library.url.appending(path: "2026/2026-10-23-meeting-oct-23-9-15-am.m4a")
        let file = try AVAudioFile(forReading: audio)
        #expect(file.fileFormat.settings[AVFormatIDKey] as? UInt32 == kAudioFormatMPEG4AAC)
        #expect(file.fileFormat.channelCount == 2)
        #expect(abs(Double(file.length) / file.fileFormat.sampleRate - 4) < 0.1, "the 4 s recorded")
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let (left, right) = (rms(buffer, channel: 0), rms(buffer, channel: 1))
        #expect(left > 0.1, "Me's 440 Hz tone at 0.2 peak, RMS ≈ 0.14")
        #expect(right < 0.001, "Them was silent")

        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])?.first)
        #expect(entry["audio"] as? String == "2026/2026-10-23-meeting-oct-23-9-15-am.m4a")
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.url.appending(path: "InProgress").path).isEmpty)

        try makeLibrary(trash: trash.url).delete(meetingID)
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.url.path).sorted() == [
            "2026-10-23-meeting-oct-23-9-15-am.m4a", "2026-10-23-meeting-oct-23-9-15-am.md",
        ])
    }

    @Test func withoutKeepAudioNoAudioOutlivesTheTranscript() async throws {
        let recorder = makeRecorder(transcriber: try ReplayTranscriber(me: "me-words"))

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await recorder.stop()

        #expect(try FileManager.default.contentsOfDirectory(atPath: library.url.appending(path: "2026").path) == [
            "2026-10-23-meeting-oct-23-9-15-am.md"
        ])
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])?.first)
        #expect(entry["audio"] == nil)
    }

    @Test func whenTheMicStreamFailsToCloseTheCallsCaptureStillStopsAndTheRecorderIsIdle() async throws {
        let them = StopSpyAudioSource()
        let recorder = makeRecorder(
            transcriber: try ReplayTranscriber(me: "me-words"), microphone: UnconvertibleAudioSource(), systemAudio: them)
        try await recorder.start(language: Locale(identifier: "en_US"))

        await #expect(throws: (any Error).self) { try await recorder.stop() }

        #expect(them.stopped)
        #expect(recorder.state == .idle)
        try await recorder.start(language: Locale(identifier: "en_US"))
        #expect(recorder.state != .idle, "a failed close leaves nothing that blocks the next Meeting")
    }

    func rms(_ buffer: AVAudioPCMBuffer, channel: Int) -> Float {
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength))
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot()
    }

    func jsonObject(at url: URL) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
    }
}
