import Foundation
import Observation
import Synchronization

/// A Meeting while it is being transcribed.
public struct LiveMeeting: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var language: Locale
    /// The app the Meeting is held through, nil for a manual Meeting with no app on the mic.
    public var app: MeetingApp?
    public var provider: String

    public init(
        id: UUID, title: String, start: Date, language: Locale, app: MeetingApp? = nil, provider: String = "Unknown"
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.language = language
        self.app = app
        self.provider = provider
    }
}

/// Runs a Meeting's lifecycle: Detection, in-progress folder, live transcription, end, Library write, cleanup.
@MainActor
@Observable
public final class Recorder {
    public enum State: Equatable, Sendable {
        case idle
        case live(LiveMeeting)
        case finishing(LiveMeeting)
    }

    public enum Failure: Error, Equatable {
        case notIdle
        case notLive
        case systemAudioRecordingDenied
    }

    public private(set) var state: State = .idle
    /// The person's Ignored Apps, by bundle ID.
    public var ignoredApps: Set<String> = []
    /// The Meeting Language Detection starts Meetings in. Nil until it is known; Detection starts nothing meanwhile.
    public var detectionLanguage: Locale?
    /// Called when Detection could not start or save a Meeting.
    @ObservationIgnored public var onDetectionFailure: (@MainActor (any Error) -> Void)?

    private let microphone: any AudioSource
    private let systemAudio: @Sendable (MeetingApp?) -> any AudioSource
    private let systemAudioPermission: @Sendable () -> SystemAudioPermission
    private let transcriber: any Transcriber
    private let library: Library
    private let vendorTable: VendorTable
    private let inProgressRoot: URL
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var detector: Detector
    private var recording: Recording?
    /// The last time the stream that tells whether the Meeting is still going was not silent.
    private let lastSound = LastSound()

    private final class LastSound: Sendable {
        private let date = Mutex<Date?>(nil)

        var value: Date? {
            get { date.withLock { $0 } }
            set { date.withLock { $0 = newValue } }
        }
    }

    private struct Recording {
        var meeting: LiveMeeting
        var folder: InProgressMeeting
        var me: Stream
        var them: Stream
    }

    private struct Stream {
        var source: any AudioSource
        var session: any TranscriptionSession
        var recorder: StreamRecorder

        func close() throws {
            source.stop()
            try recorder.close()
        }
    }

    /// `systemAudio` makes the Them stream for a Meeting App: a tap on every process it owns, or, for nil,
    /// everything the Mac plays except Carbon.
    public init(
        microphone: any AudioSource,
        systemAudio: @escaping @Sendable (MeetingApp?) -> any AudioSource,
        systemAudioPermission: @escaping @Sendable () -> SystemAudioPermission,
        transcriber: any Transcriber,
        library: Library,
        inProgressFolder: URL,
        vendorTable: VendorTable = .shipped,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.systemAudioPermission = systemAudioPermission
        self.transcriber = transcriber
        self.library = library
        self.vendorTable = vendorTable
        detector = Detector(vendorTable: vendorTable)
        inProgressRoot = inProgressFolder
        self.timeZone = timeZone
        self.now = now
        self.makeID = makeID
    }

    /// One Them source for every Meeting, whatever its app.
    public convenience init(
        microphone: any AudioSource,
        systemAudio: any AudioSource,
        systemAudioPermission: @escaping @Sendable () -> SystemAudioPermission,
        transcriber: any Transcriber,
        library: Library,
        inProgressFolder: URL,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.init(
            microphone: microphone, systemAudio: { _ in systemAudio }, systemAudioPermission: systemAudioPermission,
            transcriber: transcriber, library: library, inProgressFolder: inProgressFolder, timeZone: timeZone,
            now: now, makeID: makeID)
    }

    /// Runs Detection on `source` until its snapshots end: starts and ends Meetings without a click.
    public func runDetection(_ source: any SignalSource) async {
        for await snapshot in source.micSnapshots() {
            await observe(snapshot)
        }
    }

    private func observe(_ snapshot: MicSnapshot) async {
        let signals = Detector.Signals(
            time: snapshot.time, micHolders: snapshot.micHolders, lastSound: lastSound.value,
            ignoredApps: ignoredApps)
        for command in detector.observe(signals) {
            do {
                switch command {
                case .start(let app):
                    guard let language = detectionLanguage, state == .idle else {
                        detector.meetingStopped()
                        continue
                    }
                    try await begin(language: language, app: app, mode: .auto)
                case .end:
                    if case .live = state { try await finish() }
                }
            } catch {
                onDetectionFailure?(error)
            }
        }
    }

    /// Starts a manual Meeting on the microphone (Me) and the call's audio (Them), transcribed in `language`.
    /// The app holding the mic, if any, becomes its Meeting App, and the usual stop rules apply.
    public func start(language: Locale) async throws {
        guard state == .idle, recording == nil else { throw Failure.notIdle }
        let app = detector.meetingStarted(at: now(), ignoredApps: ignoredApps)
        try await begin(language: language, app: app, mode: .manual)
    }

    /// Ends the live Meeting and keeps it. Returns the Markdown file written to the Library.
    @discardableResult
    public func stop() async throws -> URL {
        guard recording != nil, case .live = state else { throw Failure.notLive }
        detector.meetingStopped()
        return try await finish()
    }

    /// Ends the live Meeting and keeps nothing.
    public func discard() async {
        guard let recording else { return }
        detector.meetingStopped()
        for stream in [recording.me, recording.them] {
            try? stream.close()
            _ = try? await stream.session.finish()
        }
        recording.folder.remove()
        self.recording = nil
        state = .idle
    }

    private func begin(language: Locale, app: MeetingApp?, mode: InProgressMeeting.State.Mode) async throws {
        guard state == .idle, recording == nil else { throw Failure.notIdle }
        do {
            try await open(language: language, app: app, mode: mode)
        } catch {
            detector.meetingStopped()
            throw error
        }
    }

    private func open(language: Locale, app: MeetingApp?, mode: InProgressMeeting.State.Mode) async throws {
        guard systemAudioPermission() != .denied else { throw Failure.systemAudioRecordingDenied }
        let start = now()
        let meeting = LiveMeeting(
            id: makeID(), title: MeetingFormat.defaultTitle(start: start, in: timeZone), start: start,
            language: language, app: app, provider: app.map(vendorTable.provider(for:)) ?? "Unknown")
        let folder = InProgressMeeting(root: inProgressRoot, id: meeting.id)
        state = .live(meeting)
        lastSound.value = nil
        var opened: [Stream] = []
        do {
            try folder.create(
                .init(
                    id: meeting.id, start: MeetingFormat.timestamp(start, in: timeZone), meetingApp: app?.bundleID,
                    language: MeetingFormat.bcp47(language), mode: mode))
            let me = try await open(.me, from: microphone, into: folder.meAudio, language: language)
            opened.append(me)
            let them = try await open(.them, from: systemAudio(app), into: folder.themAudio, language: language)
            opened.append(them)
            // With a Meeting App, its audio tells whether the call goes on; without one, only the mic can.
            try capture(me, tracksSound: app == nil)
            try capture(them, tracksSound: app != nil)
            recording = Recording(meeting: meeting, folder: folder, me: me, them: them)
        } catch {
            for stream in opened {
                try? stream.close()
                _ = try? await stream.session.finish()
            }
            folder.remove()
            state = .idle
            throw error
        }
    }

    @discardableResult
    private func finish() async throws -> URL {
        guard let recording, case .live(let meeting) = state else { throw Failure.notLive }
        let end = now()
        state = .finishing(meeting)
        defer {
            self.recording = nil
            state = .idle
        }
        try recording.me.close()
        try recording.them.close()
        async let me = recording.me.session.finish()
        async let them = recording.them.session.finish()
        let transcript = TranscriptBuilder.body(TranscriptBuilder.turns(me: try await me, them: try await them))
        let file = try library.create(
            FinishedMeeting(
                id: meeting.id, title: meeting.title, start: meeting.start, end: end, timeZone: timeZone,
                language: meeting.language, provider: meeting.provider, meetingApp: meeting.app?.bundleID,
                transcriptKind: .fallback),
            transcript: transcript)
        recording.folder.remove()
        return file
    }

    private func open(
        _ stream: AudioStream, from source: any AudioSource, into file: URL, language: Locale
    ) async throws -> Stream {
        let session = try await transcriber.start(locale: language, stream: stream)
        return Stream(source: source, session: session, recorder: try StreamRecorder(session: session, cafFile: file))
    }

    private func capture(_ stream: Stream, tracksSound: Bool) throws {
        let recorder = stream.recorder
        let lastSound = tracksSound ? lastSound : nil
        let now = now
        try stream.source.start { buffer in
            if let lastSound, SoundLevel.isSound(buffer) {
                let heard = now()
                lastSound.value = heard
            }
            recorder.append(buffer)
        }
    }
}
