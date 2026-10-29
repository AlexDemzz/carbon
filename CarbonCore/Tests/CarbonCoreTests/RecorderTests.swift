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
        keepAudio: Bool = false, debugMode: Bool = false, trash: URL? = nil, summarizer: (any Summarizer)? = nil,
        recognizesVoices: Bool = true, outputRoute: (any OutputRouteSource)? = nil
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
            outputRoute: outputRoute ?? UnknownOutputRoute(),
            keepAudio: { keepAudio },
            debugMode: { debugMode },
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
                "label": "Speaker A", "cluster": "A", "stream": "them", "name": NSNull(), "voicePrintId": NSNull(), "match": NSNull(),
                "speechSeconds": 12.5, "centroid": "mpkZP83MTD8=",
            ],
            [
                "label": "Speaker B", "cluster": "B", "stream": "them", "name": NSNull(), "voicePrintId": NSNull(), "match": NSNull(),
                "speechSeconds": 3, "centroid": "AACAPwAAAAA=",
            ],
        ] as NSArray)
    }

    /// The owner alone on the mic: one voice, or two when the diarizer splits theirs.
    nonisolated static let soloMic: [Diarization] = [
        Diarization(
            segments: [.init(start: 0.5, end: 1.5, cluster: "S1")],
            clusters: [.init(id: "S1", centroid: [0, 0, 1], speechSeconds: 30)]),
        Diarization(
            segments: [.init(start: 0.5, end: 1.5, cluster: "S1"), .init(start: 8, end: 9, cluster: "S2")],
            clusters: [
                .init(id: "S1", centroid: [0, 0, 1], speechSeconds: 30),
                .init(id: "S2", centroid: [0, 1, 0], speechSeconds: 19.9),
            ]),
    ]

    @Test(arguments: soloMic)
    func onHeadphonesTheWholeMicIsOneSpeakerMe(mic: Diarization) async throws {
        let diarizer = ScriptedDiarizer([.replay(Self.twoVoices)], me: [.replay(mic)])
        let route = ScriptedOutputRoute([.headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall), diarizer: diarizer, outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(diarizer.audioHeard.map(\.lastPathComponent) == ["them.caf", "me.caf"], "one helper at a time")
        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            ---

            ## Transcript

            **Me** [0:01] Hi.

            **Speaker A** [0:02] Hello all.

            **Speaker B** [0:20] Morning.

            """))
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])?.first)
        #expect((entry["speakers"] as? [NSDictionary])?.map { $0["label"] as? String } == ["Speaker A", "Speaker B"])
    }

    /// A meeting room: four people at the mic, one remote attendee on the call.
    static let room: [AudioStream: [TranscribedWord]] = [
        .me: [
            TranscribedWord(text: "Welcome.", start: 1, end: 1.5),
            TranscribedWord(text: "Thanks.", start: 5, end: 5.5),
            TranscribedWord(text: "Right.", start: 10, end: 10.5),
            TranscribedWord(text: "Agreed.", start: 15, end: 15.5),
        ],
        .them: [TranscribedWord(text: "Hello from home.", start: 3, end: 4)],
    ]

    static let remoteVoice = Diarization(
        segments: [.init(start: 3, end: 4, cluster: "S1")],
        clusters: [.init(id: "S1", centroid: [1, 0, 0, 0, 0], speechSeconds: 25)])

    /// FluidAudio numbers each run's clusters afresh: the room's S1 is not the call's S1.
    static let fourInTheRoom = Diarization(
        segments: [
            .init(start: 1, end: 1.5, cluster: "S2"),
            .init(start: 5, end: 5.5, cluster: "S1"),
            .init(start: 10, end: 10.5, cluster: "S3"),
            .init(start: 15, end: 15.5, cluster: "S4"),
        ],
        clusters: [
            .init(id: "S1", centroid: [0, 1, 0, 0, 0], speechSeconds: 40),
            .init(id: "S2", centroid: [0, 0, 1, 0, 0], speechSeconds: 30),
            .init(id: "S3", centroid: [0, 0, 0, 1, 0], speechSeconds: 25),
            .init(id: "S4", centroid: [0, 0, 0, 0, 1], speechSeconds: 20),
        ])

    func speakers() throws -> [String] {
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])?.first)
        return try #require(entry["speakers"] as? [NSDictionary]).map {
            "\($0["label"] ?? "") \($0["cluster"] ?? "") \($0["stream"] ?? "")"
        }
    }

    @Test func fourVoicesAtTheMicAndOneOnTheCallAreFiveSpeakersLetteredAcrossBothStreams() async throws {
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.room),
            diarizer: ScriptedDiarizer([.replay(Self.remoteVoice)], me: [.replay(Self.fourInTheRoom)]))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            ---

            ## Transcript

            **Speaker A** [0:01] Welcome.

            **Speaker B** [0:03] Hello from home.

            **Speaker C** [0:05] Thanks.

            **Speaker D** [0:10] Right.

            **Speaker E** [0:15] Agreed.

            """))
        #expect(try speakers() == [
            "Speaker A A me", "Speaker B B them", "Speaker C C me", "Speaker D D me", "Speaker E E me",
        ])
        #expect(!FileManager.default.fileExists(atPath: support.url.appending(path: "voiceprints.json").path),
                "a shared mic never enrolls the owner")
    }

    static let callOnSpeakers = Diarization(
        segments: [.init(start: 2, end: 4, cluster: "S1"), .init(start: 20, end: 23, cluster: "S1")],
        clusters: [.init(id: "S1", centroid: [1, 0, 0], speechSeconds: 30)])

    /// The owner, and the call heard back through the speakers, with the echo word the mic transcribed.
    nonisolated static let echoOnTheMic: [(mic: Diarization, echoWord: TranscribedWord)] = [
        // A voice 0.2 from the call's, heard over the call a third of the time.
        (
            Diarization(
                segments: [
                    .init(start: 0.5, end: 1.5, cluster: "S1"), .init(start: 20.5, end: 21, cluster: "S2"),
                    .init(start: 30, end: 31, cluster: "S2"),
                ],
                clusters: [
                    .init(id: "S1", centroid: [0, 0, 1], speechSeconds: 30),
                    .init(id: "S2", centroid: [0.8, 0, 0.6], speechSeconds: 25),
                ]),
            TranscribedWord(text: "Morning.", start: 20.6, end: 21)
        ),
        // A voice unlike the call's, heard only while the call speaks.
        (
            Diarization(
                segments: [
                    .init(start: 0.5, end: 1.5, cluster: "S1"), .init(start: 2, end: 4, cluster: "S2"),
                    .init(start: 20, end: 23, cluster: "S2"),
                ],
                clusters: [
                    .init(id: "S1", centroid: [0, 0, 1], speechSeconds: 30),
                    .init(id: "S2", centroid: [0, 1, 0], speechSeconds: 25),
                ]),
            TranscribedWord(text: "Morning.", start: 20.6, end: 21)
        ),
    ]

    @Test(arguments: echoOnTheMic)
    func whereSoundIsNotKnownToPlayOnHeadphonesTheMicIsSharedLessTheCallsEcho(
        mic: Diarization, echoWord: TranscribedWord
    ) async throws {
        var words = Self.groupCall
        words[.me]?.append(echoWord)
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: words),
            diarizer: ScriptedDiarizer([.replay(Self.callOnSpeakers)], me: [.replay(mic)]))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 40)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            ---

            ## Transcript

            **Speaker A** [0:01] Hi.

            **Speaker B** [0:02] Hello all.

            **Speaker B** [0:20] Morning.

            """))
        #expect(try speakers() == ["Speaker A A me", "Speaker B B them"])
        #expect(!FileManager.default.fileExists(atPath: support.url.appending(path: "voiceprints.json").path),
                "a shared mic never enrolls the owner")
    }

    @Test func onSpeakersOneVoiceOnTheMicIsStillASpeakerOfItsOwn() async throws {
        let route = ScriptedOutputRoute([.speakers])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.twoVoices)], me: [.replay(Self.soloMic[0])]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Speaker A** [0:01] Hi."))
        #expect(try speakers() == ["Speaker A A me", "Speaker B B them", "Speaker C C them"])
    }

    /// Writes `voiceprints.json` with these prints, each heard in 1 Meeting on Oct 1.
    func remember(_ prints: [(id: String, name: String, centroid: [Float], owner: Bool)]) throws {
        let entries = prints.map { print in
            """
            {"id": "\(print.id)", "name": "\(print.name)", "model": "fluidaudio/community-1@0.17.7",
             "centroid": "\(MeetingIndex.Speaker.encode(centroid: print.centroid))", "recent": [], "meetings": 1,
             "createdAt": "2026-10-01T10:00:00Z", "lastHeardAt": "2026-10-01T10:00:00Z"\(print.owner ? #", "owner": true"# : "")}
            """
        }
        try Data(#"{"version": 1, "prints": [\#(entries.joined(separator: ", "))]}"#.utf8)
            .write(to: support.url.appending(path: "voiceprints.json"))
    }

    func prints() throws -> [String: NSDictionary] {
        let prints = try #require(try jsonObject(at: support.url.appending(path: "voiceprints.json"))["prints"] as? [NSDictionary])
        return Dictionary(uniqueKeysWithValues: prints.map { ($0["name"] as! String, $0) })
    }

    static let owner = "22222222-2222-4222-8222-222222222222"
    static let sam = "11111111-1111-4111-8111-111111111111"

    @Test func inARoomTheOwnersPrintIsWrittenMeAndOtherVoicesTakeTheirPrintsNameOrStayLettered() async throws {
        try remember([
            (Self.owner, "Me", [0, 1, 0, 0, 0], true),
            (Self.sam, "Sam Rivera", [0, 0, 1, 0, 0], false),
        ])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.room),
            diarizer: ScriptedDiarizer([.replay(Self.remoteVoice)], me: [.replay(Self.fourInTheRoom)]))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(markdown.hasSuffix("""
            participants:
              - Sam Rivera
            ---

            ## Transcript

            **Sam Rivera** [0:01] Welcome.

            **Speaker B** [0:03] Hello from home.

            **Me** [0:05] Thanks.

            **Speaker D** [0:10] Right.

            **Speaker E** [0:15] Agreed.

            """))
        #expect(try speakers() == [
            "Sam Rivera A me", "Speaker B B them", "Me C me", "Speaker D D me", "Speaker E E me",
        ])
        let prints = try prints()
        #expect(prints["Me"]?["meetings"] as? Int == 1, "a shared mic never updates the owner's print")
        #expect(prints["Sam Rivera"]?["meetings"] as? Int == 2)
    }

    @Test func aPrintNamesOneClusterAcrossBothStreamsTheClosest() async throws {
        try remember([(Self.sam, "Sam Rivera", [0, 0, 1, 0, 0], false)])
        var remote = Self.remoteVoice
        remote.clusters[0].centroid = [0.6, 0, 0.8, 0, 0]
        var mic = Self.fourInTheRoom
        mic.clusters[1].centroid = [0, 0, 0.9, 0, 0.43589]
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.room),
            diarizer: ScriptedDiarizer([.replay(remote)], me: [.replay(mic)]))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        try await recorder.stop()

        #expect(try speakers() == [
            "Sam Rivera A me", "Speaker B B them", "Speaker C C me", "Speaker D D me", "Speaker E E me",
        ])
    }

    @Test func theOwnersPrintNeverNamesAVoiceOnTheCall() async throws {
        try remember([(Self.owner, "Me", [1, 0, 0, 0, 0], true)])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.room),
            diarizer: ScriptedDiarizer([.replay(Self.remoteVoice)], me: [.replay(Self.fourInTheRoom)]))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        try await recorder.stop()

        #expect(try speakers()[1] == "Speaker B B them")
    }

    @Test func onSpeakersTheOwnersPrintNamesTheirVoiceMeWithoutLearningFromIt() async throws {
        try remember([(Self.owner, "Me", [0, 0, 1], true)])
        let route = ScriptedOutputRoute([.speakers])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.twoVoices)], me: [.replay(Self.soloMic[0])]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Me** [0:01] Hi."))
        #expect(try speakers() == ["Me A me", "Speaker B B them", "Speaker C C them"])
        #expect(try prints()["Me"]?["meetings"] as? Int == 1)
    }

    /// The owner on headphones, split by the diarizer into two voices: 16 s at [0, 1, 0], 12 s at [0, 0, 1].
    static let ownerSplitInTwo = Diarization(
        segments: [.init(start: 0.5, end: 1.5, cluster: "S1"), .init(start: 8, end: 9, cluster: "S2")],
        clusters: [
            .init(id: "S1", centroid: [0, 1, 0], speechSeconds: 16),
            .init(id: "S2", centroid: [0, 0, 1], speechSeconds: 12),
        ])

    @Test func onHeadphonesEveryMicVoiceIsTheOwnerWhosePrintIsEnrolledFromAllOfThem() async throws {
        let route = ScriptedOutputRoute([.headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.twoVoices)], me: [.replay(Self.ownerSplitInTwo)]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            ---

            ## Transcript

            **Me** [0:01] Hi.

            **Speaker A** [0:02] Hello all.

            **Speaker B** [0:20] Morning.

            """))
        #expect(try speakers() == ["Speaker A A them", "Speaker B B them"])
        let owner = try #require(try prints()["Me"])
        #expect(owner["owner"] as? Bool == true)
        let encoded = try #require(owner["centroid"] as? String)
        let centroid = try #require(MeetingIndex.Speaker.decode(centroid: encoded))
        // 16 s of [0, 1, 0] and 12 s of [0, 0, 1] weigh in as [0, 16, 12], which is [0, 0.8, 0.6] at length 1.
        #expect(zip(centroid, [0, 0.8, 0.6] as [Float]).allSatisfy { abs($0 - $1) < 1e-6 })
        #expect(owner["meetings"] as? Int == 1)
        #expect(owner["lastHeardAt"] as? String == "2026-10-23T13:15:00Z")
    }

    @Test func onHeadphonesTheMicUpdatesTheOwnersPrint() async throws {
        try remember([(Self.owner, "Me", [0, 0.6, 0.8], true)])
        let route = ScriptedOutputRoute([.headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.callOnSpeakers)], me: [.replay(Self.soloMic[0])]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        try await recorder.stop()

        let prints = try prints()
        #expect(prints.count == 1)
        #expect(prints["Me"]?["meetings"] as? Int == 2)
        #expect(prints["Me"]?["recent"] as? [String] == [MeetingIndex.Speaker.encode(centroid: [0, 0, 1])])
    }

    @Test func onHeadphonesAVoiceFarFromTheOwnersPrintLeavesItAsItWas() async throws {
        try remember([(Self.owner, "Me", [0, 1, 0], true)])
        let route = ScriptedOutputRoute([.headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.callOnSpeakers)], me: [.replay(Self.soloMic[0])]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        try await recorder.stop()

        #expect(try prints()["Me"]?["meetings"] as? Int == 1)
    }

    @Test func oneRouteOtherThanHeadphonesSharesTheMicForTheWholeMeetingAndNeverEnrollsTheOwner() async throws {
        let route = ScriptedOutputRoute([.headphones, .speakers, .headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.twoVoices)], me: [.replay(Self.ownerSplitInTwo)]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Speaker A** [0:01] Hi."))
        #expect(try speakers() == ["Speaker A A me", "Speaker B B them", "Speaker C C them"])
        #expect(!FileManager.default.fileExists(atPath: support.url.appending(path: "voiceprints.json").path))
    }

    @Test func aMeetingBegunOnSpeakersStaysSharedOnceHeadphonesAreOnAndNeverEnrollsTheOwner() async throws {
        let route = ScriptedOutputRoute([.speakers, .headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.twoVoices)], me: [.replay(Self.ownerSplitInTwo)]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Speaker A** [0:01] Hi."))
        #expect(try speakers() == ["Speaker A A me", "Speaker B B them", "Speaker C C them"])
        #expect(!FileManager.default.fileExists(atPath: support.url.appending(path: "voiceprints.json").path))
    }

    @Test func onHeadphonesAMicVoiceOfAnotherLengthIsLeftOutOfTheOwnersPrint() async throws {
        let mic = Diarization(
            segments: [.init(start: 0.5, end: 1.5, cluster: "S1"), .init(start: 8, end: 9, cluster: "S2")],
            clusters: [
                .init(id: "S1", centroid: [0, 0, 1, 0], speechSeconds: 12),
                .init(id: "S2", centroid: [0, 1, 0], speechSeconds: 16),
            ])
        let route = ScriptedOutputRoute([.headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.twoVoices)], me: [.replay(mic)]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        try await recorder.stop()

        let encoded = try #require(try prints()["Me"]?["centroid"] as? String)
        #expect(MeetingIndex.Speaker.decode(centroid: encoded) == [0, 1, 0])
    }

    @Test func eachMeetingHearsItsOwnRoute() async throws {
        let route = ScriptedOutputRoute([.speakers], [.headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer(
                [.replay(Self.twoVoices), .replay(Self.twoVoices)],
                me: [.replay(Self.soloMic[0]), .replay(Self.soloMic[0])]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard(meetings: 1)
        clock.advance(by: 30)
        let shared = try await recorder.stop()
        clock.advance(by: 60)
        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard(meetings: 2)
        clock.advance(by: 30)
        let isolated = try await recorder.stop()

        #expect(try String(contentsOf: shared, encoding: .utf8).contains("**Speaker A** [0:01] Hi."))
        #expect(try String(contentsOf: isolated, encoding: .utf8).contains("**Me** [0:01] Hi."))
        #expect(try prints()["Me"]?["meetings"] as? Int == 1)
    }

    @Test func onHeadphonesUnderTenSecondsOfMicSpeechInAllLeavesTheOwnerUnenrolled() async throws {
        let mic = Diarization(
            segments: [.init(start: 0.5, end: 1.5, cluster: "S1"), .init(start: 8, end: 9, cluster: "S2")],
            clusters: [
                .init(id: "S1", centroid: [0, 0, 1], speechSeconds: 6),
                .init(id: "S2", centroid: [0, 1, 0], speechSeconds: 3.9),
            ])
        let route = ScriptedOutputRoute([.headphones])
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall),
            diarizer: ScriptedDiarizer([.replay(Self.twoVoices)], me: [.replay(mic)]),
            outputRoute: route)

        try await recorder.start(language: Locale(identifier: "en_US"))
        try await route.heard()
        clock.advance(by: 30)
        try await recorder.stop()

        #expect(!FileManager.default.fileExists(atPath: support.url.appending(path: "voiceprints.json").path))
    }

    @Test(arguments: [ScriptedDiarizer.Outcome.fail, .hang])
    func whenTheMicsDiarizationFailsMeStaysMeAndTheCallsSplitIsKept(outcome: ScriptedDiarizer.Outcome) async throws {
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.room),
            diarizer: ScriptedDiarizer([.replay(Self.remoteVoice)], me: [outcome, outcome]))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("""
            **Me** [0:01] Welcome.

            **Speaker A** [0:03] Hello from home.

            **Me** [0:05] Thanks.
            """))
        #expect(try speakers() == ["Speaker A A them"])
    }

    @Test(arguments: [ScriptedDiarizer.Outcome.fail, .hang])
    func whenTheCallsDiarizationFailsThemStaysThemAndTheRoomIsKept(outcome: ScriptedDiarizer.Outcome) async throws {
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.room),
            diarizer: ScriptedDiarizer([outcome, outcome], me: [.replay(Self.fourInTheRoom)]))

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("""
            ---

            ## Transcript

            **Speaker A** [0:01] Welcome.

            **Them** [0:03] Hello from home.

            **Speaker B** [0:05] Thanks.

            **Speaker C** [0:10] Right.

            **Speaker D** [0:15] Agreed.

            """))
        let entry = try #require((try jsonObject(at: support.url.appending(path: "meetings.json"))["meetings"] as? [NSDictionary])?.first)
        #expect(entry["transcript"] as? String == "speakers")
        #expect(try speakers() == ["Speaker A A me", "Speaker B B me", "Speaker C C me", "Speaker D D me"])
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
                "label": "Sam Rivera", "cluster": "A", "stream": "them", "name": "Sam Rivera",
                "voicePrintId": "11111111-1111-4111-8111-111111111111", "match": "auto", "distance": 0,
                "speechSeconds": 12.5, "centroid": "mpkZP83MTD8=",
            ],
            [
                "label": "Speaker B", "cluster": "B", "stream": "them", "name": NSNull(), "voicePrintId": NSNull(), "match": NSNull(),
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

        #expect(diarizer.audioHeard.filter { $0.lastPathComponent == "them.caf" }.count == 2, "one retry")
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

    @Test func inDebugModeWhatTheTranscriptWasBuiltFromIsWrittenToApplicationSupportAndTrashedWithTheMeeting()
        async throws
    {
        let trash = try TemporaryFolder()
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall), debugMode: true, trash: trash.url)

        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        try await recorder.stop()

        let debug = try JSONDecoder().decode(
            MeetingDebug.self,
            from: Data(contentsOf: support.url.appending(path: "Debug/6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21.json")))
        #expect(debug.me.words == [.init(text: "Hi.", start: 1, end: 1.4, cluster: nil, speaker: "Me")])
        #expect(debug.them.words.map(\.speaker) == ["Them", "Them", "Them"])
        #expect(
            try FileManager.default.subpathsOfDirectory(atPath: library.url.path).sorted() == [
                "2026", "2026/2026-10-23-meeting-oct-23-9-15-am.md",
            ], "the Library folder holds only Markdown")

        try makeLibrary(trash: trash.url).delete(meetingID)
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.url.path).sorted() == [
            "2026-10-23-meeting-oct-23-9-15-am.md", "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21.json",
        ])
    }

    @Test func aMeetingDeletedInTheFinderTakesItsDebugModeFileToTheTrash() async throws {
        let trash = try TemporaryFolder()
        let recorder = makeRecorder(
            transcriber: ReplayTranscriber(words: Self.groupCall), debugMode: true, trash: trash.url)
        try await recorder.start(language: Locale(identifier: "en_US"))
        clock.advance(by: 30)
        try await recorder.stop()

        try FileManager.default.removeItem(at: library.url.appending(path: "2026/2026-10-23-meeting-oct-23-9-15-am.md"))
        try makeLibrary(trash: trash.url).reconcile()

        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.url.path) == [
            "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21.json"
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
