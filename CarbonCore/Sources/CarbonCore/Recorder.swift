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
    /// The calendar Event the Meeting belongs to, if any.
    public var event: CalendarEvent?

    public init(
        id: UUID, title: String, start: Date, language: Locale, app: MeetingApp? = nil, provider: String = "Unknown",
        event: CalendarEvent? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.language = language
        self.app = app
        self.provider = provider
        self.event = event
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
    private let diarizer: any Diarizer
    private let diarizationTimeout: @Sendable (TimeInterval) -> Duration
    private let library: Library
    private let vendorTable: VendorTable
    private let matcher: EventMatcher
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
        var mode: InProgressMeeting.State.Mode
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
        diarizer: any Diarizer,
        diarizationTimeout: @escaping @Sendable (TimeInterval) -> Duration = Recorder.diarizationTimeout(forAudio:),
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
        self.diarizer = diarizer
        self.diarizationTimeout = diarizationTimeout
        self.library = library
        self.vendorTable = vendorTable
        matcher = EventMatcher(vendorTable: vendorTable)
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
        diarizer: any Diarizer,
        diarizationTimeout: @escaping @Sendable (TimeInterval) -> Duration = Recorder.diarizationTimeout(forAudio:),
        library: Library,
        inProgressFolder: URL,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.init(
            microphone: microphone, systemAudio: { _ in systemAudio }, systemAudioPermission: systemAudioPermission,
            transcriber: transcriber, diarizer: diarizer, diarizationTimeout: diarizationTimeout, library: library,
            inProgressFolder: inProgressFolder, timeZone: timeZone, now: now, makeID: makeID)
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
            ignoredApps: ignoredApps, events: snapshot.events)
        for command in detector.observe(signals) {
            do {
                switch command {
                case .start(let app, let event):
                    guard let language = detectionLanguage, state == .idle else {
                        detector.meetingStopped()
                        continue
                    }
                    try await begin(language: language, app: app, event: event, mode: .auto)
                case .event(let event):
                    try retarget(to: event)
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
        let (app, event) = detector.meetingStarted(at: now(), ignoredApps: ignoredApps)
        try await begin(language: language, app: app, event: event, mode: .manual)
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

    private func begin(
        language: Locale, app: MeetingApp?, event: CalendarEvent?, mode: InProgressMeeting.State.Mode
    ) async throws {
        guard state == .idle, recording == nil else { throw Failure.notIdle }
        do {
            try await open(language: language, app: app, event: event, mode: mode)
        } catch {
            detector.meetingStopped()
            throw error
        }
    }

    private func open(
        language: Locale, app: MeetingApp?, event: CalendarEvent?, mode: InProgressMeeting.State.Mode
    ) async throws {
        guard systemAudioPermission() != .denied else { throw Failure.systemAudioRecordingDenied }
        var meeting = LiveMeeting(id: makeID(), title: "", start: now(), language: language, app: app)
        name(&meeting, after: event)
        let folder = InProgressMeeting(root: inProgressRoot, id: meeting.id)
        state = .live(meeting)
        lastSound.value = nil
        var opened: [Stream] = []
        do {
            try folder.create(state(of: meeting, mode: mode))
            let me = try await open(.me, from: microphone, into: folder.meAudio, language: language)
            opened.append(me)
            let them = try await open(.them, from: systemAudio(app), into: folder.themAudio, language: language)
            opened.append(them)
            // With a Meeting App, its audio tells whether the call goes on; without one, only the mic can.
            try capture(me, tracksSound: app == nil)
            try capture(them, tracksSound: app != nil)
            recording = Recording(meeting: meeting, folder: folder, mode: mode, me: me, them: them)
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

    /// Titles the Meeting after its Event, or by default, and resolves its Provider.
    private func name(_ meeting: inout LiveMeeting, after event: CalendarEvent?) {
        meeting.event = event
        meeting.title = event?.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? MeetingFormat.defaultTitle(start: meeting.start, in: timeZone)
        meeting.provider = vendorTable.provider(for: meeting.app, link: event.flatMap(matcher.link(in:)))
    }

    private func state(of meeting: LiveMeeting, mode: InProgressMeeting.State.Mode) -> InProgressMeeting.State {
        InProgressMeeting.State(
            id: meeting.id, start: MeetingFormat.timestamp(meeting.start, in: timeZone),
            meetingApp: meeting.app?.bundleID, language: MeetingFormat.bcp47(meeting.language), mode: mode,
            event: meeting.event)
    }

    /// The live Meeting belongs to another Event from now on.
    private func retarget(to event: CalendarEvent) throws {
        guard var recording, case .live(var meeting) = state else { return }
        name(&meeting, after: event)
        recording.meeting = meeting
        self.recording = recording
        state = .live(meeting)
        try recording.folder.create(state(of: meeting, mode: recording.mode))
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
        async let meWords = recording.me.session.finish()
        async let themWords = recording.them.session.finish()
        async let diarized = Self.diarize(
            recording.folder.themAudio, with: diarizer,
            timeout: diarizationTimeout(end.timeIntervalSince(meeting.start)))
        let (me, them, diarization) = (try await meWords, try await themWords, await diarized)
        let letters = diarization.map { TranscriptBuilder.clusterLetters(them: them, diarization: $0) } ?? [:]
        // A diarization that reaches no Them word has nothing to split: the file stays Me / Them.
        let split = letters.isEmpty ? nil : diarization
        let participants = meeting.event.map(EventMatcher.participants(of:)) ?? []
        // In a 1:1 Event, the lone Them Speaker (or Them) is the other attendee.
        let attendee = participants.count == 1 ? TranscriptBuilder.label(forName: participants[0].name) : nil
        var speakers = split.map { Self.speakers($0, letters: letters) } ?? []
        var labels: [String: String] = [:]
        if let attendee, speakers.count == 1 {
            labels[speakers[0].cluster] = attendee
            speakers[0].label = attendee
            speakers[0].name = attendee
            speakers[0].match = "attendee1to1"
        }
        var turns = TranscriptBuilder.turns(me: me, them: them, diarization: split, labels: labels)
        if let attendee, split == nil {
            turns = turns.map { turn in
                var turn = turn
                if turn.speaker == TranscriptBuilder.them { turn.speaker = attendee }
                return turn
            }
        }
        let file = try library.create(
            FinishedMeeting(
                id: meeting.id, title: meeting.title, start: meeting.start, end: end, timeZone: timeZone,
                language: meeting.language, provider: meeting.provider, meetingApp: meeting.app?.bundleID,
                providerMeetingId: meeting.event.flatMap(matcher.link(in:))?.meetingId,
                calendarEventId: meeting.event?.id, participants: participants,
                transcriptKind: split == nil ? .fallback : .speakers, speakers: speakers),
            transcript: TranscriptBuilder.body(turns))
        recording.folder.remove()
        return file
    }

    /// The diarization watchdog's limit for one attempt: 2 min plus 10 s per minute of audio.
    public nonisolated static func diarizationTimeout(forAudio seconds: TimeInterval) -> Duration {
        .seconds(120) + .seconds(10) * (seconds / 60)
    }

    struct DiarizationTimedOut: Error {}

    /// Diarizes the Them audio under the watchdog: one retry after a failure or a timeout, then nil (Me / Them).
    private nonisolated static func diarize(
        _ audio: URL, with diarizer: any Diarizer, timeout: Duration
    ) async -> Diarization? {
        for _ in 1...2 {
            let attempt = try? await withThrowingTaskGroup(of: Diarization?.self) { group in
                group.addTask { try await diarizer.diarize(audio) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let diarization = first else { throw DiarizationTimedOut() }
                return diarization
            }
            if let attempt { return attempt }
        }
        return nil
    }

    private static func speakers(_ diarization: Diarization, letters: [String: String]) -> [MeetingIndex.Speaker] {
        diarization.clusters.compactMap { cluster in
            letters[cluster.id].map { letter in
                MeetingIndex.Speaker(
                    label: "Speaker \(letter)", cluster: letter, speechSeconds: cluster.speechSeconds,
                    centroid: MeetingIndex.Speaker.encode(centroid: cluster.centroid))
            }
        }
        .sorted { ($0.cluster.count, $0.cluster) < ($1.cluster.count, $1.cluster) }
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
