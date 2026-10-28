import CarbonCore
import Foundation
import Synchronization
import Testing

/// Plays a scripted afternoon of mic holders, one snapshot per second, moving the clock to each snapshot's time
/// as the Recorder takes it.
struct ScriptedSignalSource: SignalSource {
    let snapshots: [MicSnapshot]
    let clock: TestClock

    init(
        _ clock: TestClock, from start: Date, events: [CalendarEvent] = [],
        _ script: [(seconds: ClosedRange<Int>, holders: [MeetingApp])]
    ) {
        self.clock = clock
        snapshots = script.flatMap { step in
            step.seconds.map {
                MicSnapshot(time: start + TimeInterval($0), micHolders: step.holders, events: events)
            }
        }
    }

    func micSnapshots() -> AsyncStream<MicSnapshot> {
        let next = Mutex(0)
        let snapshots = snapshots
        let clock = clock
        return AsyncStream {
            next.withLock { index -> MicSnapshot? in
                guard index < snapshots.count else { return nil }
                defer { index += 1 }
                clock.set(snapshots[index].time)
                return snapshots[index]
            }
        }
    }
}

/// The Meeting Apps the Recorder asked a Them stream for.
final class TappedApps: Sendable {
    let apps = Mutex<[MeetingApp?]>([])
}

@MainActor
struct DetectionRecorderTests {
    let library = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let start = date("2026-10-23T13:15:00Z")
    let clock = TestClock(date("2026-10-23T13:15:00Z"))
    let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")
    let superwhisper = MeetingApp(bundleID: "com.superduper.superwhisper", name: "superwhisper")

    func makeRecorder(tappedApps: TappedApps? = nil) throws -> Recorder {
        let clock = clock
        let recorder = Recorder(
            microphone: FakeAudioSource(seconds: 3),
            systemAudio: { app in
                tappedApps?.apps.withLock { $0.append(app) }
                return FakeAudioSource(seconds: 3)
            },
            systemAudioPermission: { .granted },
            transcriber: try ReplayTranscriber(me: "me-words"),
            diarizer: ScriptedDiarizer([.fail, .fail]),
            diarizationTimeout: { _ in .milliseconds(100) },
            library: Library(folder: library.url, supportFolder: support.url, now: { clock.now }),
            inProgressFolder: support.url.appending(path: "InProgress"),
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: { UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")! })
        recorder.detectionLanguage = Locale(identifier: "en_US")
        return recorder
    }

    @Test func aScriptedZoomCallEndsAsExactlyOneMarkdownFile() async throws {
        let recorder = try makeRecorder()
        let afternoon = ScriptedSignalSource(clock, from: start, [
            (0...59, [superwhisper]),
            (60...359, [superwhisper, zoom]),
            (360...1_400, []),
            (1_401...1_410, [zoom]),
            (1_411...2_100, []),
        ])

        await recorder.runDetection(afternoon)

        let year = library.url.appending(path: "2026")
        #expect(try FileManager.default.contentsOfDirectory(atPath: year.path) == ["2026-10-23-meeting-oct-23-9-16-am.md"])
        let markdown = try String(contentsOf: year.appending(path: "2026-10-23-meeting-oct-23-9-16-am.md"), encoding: .utf8)
        #expect(markdown.hasPrefix("""
            ---
            provider: Zoom
            id: 6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21
            date: 2026-10-23T09:16:15-04:00
            title: Meeting Oct 23, 9:16 AM
            duration: 14:45
            """))
        let index = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: support.url.appending(path: "meetings.json"))) as? NSDictionary)
        let meetings = try #require(index["meetings"] as? [NSDictionary])
        #expect(meetings.map { $0["meetingApp"] as? String } == ["us.zoom.xos"])
        #expect(recorder.state == .idle)
    }

    @Test func theCallsAudioIsTappedOnTheMeetingApp() async throws {
        let tapped = TappedApps()
        let recorder = try makeRecorder(tappedApps: tapped)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...20, [zoom])]))

        #expect(tapped.apps.withLock { $0 } == [zoom])
        await recorder.discard()
    }

    @Test func aManualStopWinsOverTheMicStillHeld() async throws {
        let recorder = try makeRecorder()

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...20, [zoom])]))
        try await recorder.stop()
        await recorder.runDetection(ScriptedSignalSource(clock, from: start + 21, [(0...3_000, [zoom])]))

        #expect(recorder.state == .idle)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.url.appending(path: "2026").path).count == 1)
    }

    // MARK: What the person is told

    func recordEvents(of recorder: Recorder) -> Events {
        let events = Events()
        recorder.onEvent = { events.list.append($0) }
        return events
    }

    var meetingID: UUID { UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")! }

    @Test func aMeetingDetectionStartsIsAnnouncedWithItsTitleProviderAndLanguage() async throws {
        let recorder = try makeRecorder()
        let events = recordEvents(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...20, [zoom])]))

        #expect(events.list == [
            .started(LiveMeeting(
                id: meetingID, title: "Meeting Oct 23, 9:15 AM", start: start + 15,
                language: Locale(identifier: "en_US"), app: zoom, provider: "Zoom")),
        ])
        await recorder.discard()
    }

    @Test func aWrittenTranscriptIsAnnouncedWithItsFile() async throws {
        let recorder = try makeRecorder()
        let events = recordEvents(of: recorder)
        try await recorder.start(language: Locale(identifier: "en_US"))

        try await recorder.stop()

        #expect(events.list == [
            .transcriptReady(
                id: meetingID, title: "Meeting Oct 23, 9:15 AM",
                file: library.url.appending(path: "2026/2026-10-23-meeting-oct-23-9-15-am.md")),
        ])
    }

    @Test func withAutoTranscribeOffDetectionOffersAMeetingAndStartsNothing() async throws {
        let recorder = try makeRecorder()
        recorder.autoTranscribe = false
        let events = recordEvents(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...100, [zoom])]))

        #expect(events.list == [
            .offered(.init(app: zoom, title: "Meeting Oct 23, 9:15 AM", provider: "Zoom", language: Locale(identifier: "en_US"))),
            .offerWithdrawn(zoom),
        ])
        #expect(recorder.state == .idle)
    }

    @Test func transcribingAnOfferStartsTheMeetingInTheChosenLanguage() async throws {
        let recorder = try makeRecorder()
        recorder.autoTranscribe = false
        let events = recordEvents(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...20, [zoom])]))
        try await recorder.acceptOffer(language: Locale(identifier: "fr_FR"))

        guard case .live(let meeting) = recorder.state else {
            Issue.record("no live Meeting")
            return
        }
        #expect(meeting.app == zoom)
        #expect(meeting.language == Locale(identifier: "fr_FR"))
        #expect(events.list.count == 1, "an accepted offer is not announced again")
        await recorder.discard()
    }

    @Test func neverAddsTheOfferedAppToIgnoredApps() async throws {
        let recorder = try makeRecorder()
        recorder.autoTranscribe = false
        let events = recordEvents(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...20, [zoom])]))
        recorder.neverOffer()
        await recorder.runDetection(ScriptedSignalSource(clock, from: start + 21, [(0...9, []), (10...1_500, [zoom])]))

        #expect(recorder.ignoredApps == ["us.zoom.xos"])
        #expect(events.list.count == 1, "no offer after Never, even once the mute is over")
    }
}

@MainActor
final class Events {
    var list: [Recorder.Event] = []
}
