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
        self.init(clock, from: start, events: events, script.map { ($0.seconds, $0.holders, []) })
    }

    /// The assertions are polled on every second divisible by 3, as the SignalSampler does.
    init(
        _ clock: TestClock, from start: Date, events: [CalendarEvent] = [],
        _ script: [(seconds: ClosedRange<Int>, holders: [MeetingApp], assertions: [PowerAssertion])]
    ) {
        self.clock = clock
        snapshots = script.flatMap { step in
            step.seconds.map {
                MicSnapshot(
                    time: start + TimeInterval($0), micHolders: step.holders, events: events,
                    assertions: $0 % 3 == 0 ? step.assertions : nil)
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

    let chrome = MeetingApp(bundleID: "com.google.Chrome", name: "Google Chrome")

    func zoomCall(_ id: Int) -> PowerAssertion {
        PowerAssertion(app: zoom, name: "Describe Activity Type", type: "PreventUserIdleDisplaySleep", id: id)
    }

    func makeRecorder(
        tappedApps: TappedApps? = nil, diarizer: any Diarizer = ScriptedDiarizer([.fail, .fail, .fail, .fail]),
        diarizationTimeout: Duration = .milliseconds(100)
    ) throws -> Recorder {
        let clock = clock
        let made = Mutex(0)
        let recorder = Recorder(
            microphone: FakeAudioSource(seconds: 3),
            systemAudio: { app in
                tappedApps?.apps.withLock { $0.append(app) }
                return FakeAudioSource(seconds: 3)
            },
            systemAudioPermission: { .granted },
            transcriber: try ReplayTranscriber(me: "me-words"),
            diarizer: diarizer,
            diarizationTimeout: { _ in diarizationTimeout },
            library: Library(folder: library.url, supportFolder: support.url, now: { clock.now }),
            inProgressFolder: support.url.appending(path: "InProgress"),
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: {
                let n = made.withLock { n in
                    defer { n += 1 }
                    return n
                }
                return UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C\(21 + n)")!
            })
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

    func recordNotices(of recorder: Recorder) -> Notices {
        let notices = Notices()
        recorder.onNotice = { notices.list.append($0) }
        return notices
    }

    var meetingID: UUID { UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")! }

    @Test func aMeetingDetectionStartsIsAnnouncedWithItsTitleProviderAndLanguage() async throws {
        let recorder = try makeRecorder()
        let notices = recordNotices(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...20, [zoom])]))

        #expect(notices.list == [
            .started(LiveMeeting(
                id: meetingID, title: "Meeting Oct 23, 9:15 AM", start: start + 15,
                language: Locale(identifier: "en_US"), app: zoom, provider: "Zoom")),
        ])
        await recorder.discard()
    }

    @Test func aWrittenTranscriptIsAnnouncedWithItsFile() async throws {
        let recorder = try makeRecorder()
        let notices = recordNotices(of: recorder)
        try await recorder.start(language: Locale(identifier: "en_US"))

        try await recorder.stop()

        #expect(notices.list == [
            .transcriptReady(
                id: meetingID, title: "Meeting Oct 23, 9:15 AM",
                file: library.url.appending(path: "2026/2026-10-23-meeting-oct-23-9-15-am.md")),
        ])
    }

    @Test func withAutoTranscribeOffDetectionOffersAMeetingAndStartsNothing() async throws {
        let recorder = try makeRecorder()
        recorder.autoTranscribe = false
        let notices = recordNotices(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...100, [zoom])]))

        #expect(notices.list == [
            .offered(.init(app: zoom, title: "Meeting Oct 23, 9:15 AM", provider: "Zoom")),
            .offerWithdrawn(zoom),
        ])
        #expect(recorder.state == .idle)
    }

    @Test func transcribingAnOfferStartsTheMeetingInTheDetectionLanguage() async throws {
        let recorder = try makeRecorder()
        recorder.autoTranscribe = false
        recorder.detectionLanguage = Locale(identifier: "fr_FR")
        let notices = recordNotices(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...20, [zoom])]))
        try await recorder.acceptOffer()

        guard case .live(let meeting) = recorder.state else {
            Issue.record("no live Meeting")
            return
        }
        #expect(meeting.app == zoom)
        #expect(meeting.language == Locale(identifier: "fr_FR"))
        #expect(notices.list.count == 1, "an accepted offer is not announced again")
        await recorder.discard()
    }

    @Test func neverAddsTheOfferedAppToIgnoredApps() async throws {
        let recorder = try makeRecorder()
        recorder.autoTranscribe = false
        let notices = recordNotices(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(0...20, [zoom])]))
        recorder.neverOffer()
        await recorder.runDetection(ScriptedSignalSource(clock, from: start + 21, [(0...9, []), (10...1_500, [zoom])]))

        #expect(recorder.ignoredApps == ["us.zoom.xos"])
        #expect(notices.list.count == 1, "no offer after Never, even once the mute is over")
    }

    // MARK: Call assertions, back-to-back and overlap

    func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: library.url.appending(path: "2026").path).sorted()
    }

    /// The `duration` of each file, in file name order.
    func durations() throws -> [String] {
        try files().map { name in
            let markdown = try String(contentsOf: library.url.appending(path: "2026/\(name)"), encoding: .utf8)
            let line = markdown.split(separator: "\n").first { $0.hasPrefix("duration: ") } ?? ""
            return String(line.dropFirst("duration: ".count))
        }
    }

    func providers() throws -> [String] {
        try files().map { name in
            let markdown = try String(contentsOf: library.url.appending(path: "2026/\(name)"), encoding: .utf8)
            let line = markdown.split(separator: "\n").first { $0.hasPrefix("provider: ") } ?? ""
            return String(line.dropFirst("provider: ".count))
        }
    }

    @Test func backToBackZoomCallsBecomeTwoMeetings() async throws {
        let recorder = try makeRecorder()

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [
            (0...600, [zoom], [zoomCall(1)]),
            (601...700, [zoom], [zoomCall(2)]),
            (701...800, [], []),
        ]))

        #expect(try files() == ["2026-10-23-meeting-oct-23-9-15-am.md", "2026-10-23-meeting-oct-23-9-25-am.md"])
        #expect(try durations() == ["10:00", "2:19"])
        #expect(recorder.state == .idle)
    }

    @Test func theNextMeetingStartsWithoutWaitingForThePreviousOnesDiarization() async throws {
        let diarizer = WaitingDiarizer()
        let recorder = try makeRecorder(
            tappedApps: diarizer.tapped, diarizer: diarizer, diarizationTimeout: .seconds(10))

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [
            (0...600, [zoom], [zoomCall(1)]),
            (601...700, [zoom], [zoomCall(2)]),
            (701...800, [], []),
        ]))

        let attempts = diarizer.sawTheNextMeeting.withLock { $0 }
        #expect(!attempts.isEmpty && attempts.allSatisfy { $0 })
        #expect(try files().count == 2)
    }

    @Test func aSecondCallAppOffersASwitchAndSwitchingFilesTheFirstMeeting() async throws {
        let recorder = try makeRecorder()
        let notices = recordNotices(of: recorder)

        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [
            (0...100, [chrome], []),
            (101...130, [chrome, zoom], [zoomCall(1)]),
        ]))
        guard case .live(let chromeMeeting) = recorder.state else { Issue.record("no live Meeting"); return }
        #expect(notices.list.dropFirst() == [
            .switchOffered(.init(app: zoom, provider: "Zoom", meeting: chromeMeeting)),
        ])
        #expect(chromeMeeting.provider == "Google Chrome")

        try await recorder.switchMeeting(to: zoom)
        guard case .live(let switched) = recorder.state else { Issue.record("not live: \(recorder.state)"); return }
        #expect(switched.app == zoom)
        #expect(switched.start == start + 130)
        await recorder.runDetection(ScriptedSignalSource(clock, from: start, [(131...300, [chrome], [])]))

        #expect(try providers() == ["Google Chrome", "Zoom"])
        #expect(try durations() == ["1:55", "0:47"])
        #expect(recorder.state == .idle)
    }
}

/// Fails every diarization, after waiting up to 3 s for a second Meeting's Them stream to open.
final class WaitingDiarizer: Diarizer {
    let tapped = TappedApps()
    let sawTheNextMeeting = Mutex<[Bool]>([])

    func diarize(_ audio: URL) async throws -> Diarization {
        var saw = false
        for _ in 0..<300 {
            saw = tapped.apps.withLock { $0.count } >= 2
            if saw { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        sawTheNextMeeting.withLock { $0.append(saw) }
        throw ScriptedDiarizer.Failed()
    }
}

@MainActor
final class Notices {
    var list: [Recorder.Notice] = []
}
