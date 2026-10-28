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

    /// What the person is told about, as notifications.
    public enum Event: Equatable, Sendable {
        /// Detection started a Meeting on its own.
        case started(LiveMeeting)
        /// Detection offers a Meeting (auto-transcribe off).
        case offered(Offer)
        /// The offer went away: nobody answered within 60 s, or its app released the mic.
        case offerWithdrawn(MeetingApp)
        case transcriptReady(id: UUID, title: String, file: URL)
        /// Another app's start signal during the live Meeting: offer "Switch to <app>".
        case switchOffered(SwitchOffer)
    }

    /// Another Meeting App wants the microphone while `meeting` is live.
    public struct SwitchOffer: Equatable, Sendable {
        public var app: MeetingApp
        public var provider: String
        public var meeting: LiveMeeting

        public init(app: MeetingApp, provider: String, meeting: LiveMeeting) {
            self.app = app
            self.provider = provider
            self.meeting = meeting
        }
    }

    public struct Offer: Equatable, Sendable {
        public var app: MeetingApp
        public var title: String
        public var provider: String
        /// The language Transcribe starts the Meeting in.
        public var language: Locale

        public init(app: MeetingApp, title: String, provider: String, language: Locale) {
            self.app = app
            self.title = title
            self.provider = provider
            self.language = language
        }
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
    /// "Transcribe Meetings automatically": off, Detection offers Meetings instead of starting them.
    public var autoTranscribe = true
    @ObservationIgnored public var onEvent: (@MainActor (Event) -> Void)?
    /// A line for the diagnostic log, e.g. each Voice Print best distance.
    @ObservationIgnored public var onDiagnostic: (@MainActor (String) -> Void)?
    /// Called when Detection could not start or save a Meeting.
    @ObservationIgnored public var onDetectionFailure: (@MainActor (any Error) -> Void)?

    private let microphone: any AudioSource
    private let systemAudio: @Sendable (MeetingApp?) -> any AudioSource
    private let systemAudioPermission: @Sendable () -> SystemAudioPermission
    let transcriber: any Transcriber
    private let diarizer: any Diarizer
    private let diarizationTimeout: @Sendable (TimeInterval) -> Duration
    private let summarizer: any Summarizer
    private let library: Library
    private let keepAudio: @Sendable () -> Bool
    let vendorTable: VendorTable
    let matcher: EventMatcher
    let inProgressRoot: URL
    let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var detector: Detector
    var recording: Recording?
    /// The Meeting Language switch under way, which every end of the Meeting waits for.
    private var languageSwitch: Task<Void, any Error>?
    /// Meetings Detection ended that are still being filed, so the next Meeting never waits on a diarization.
    private var filings: [UUID: Task<Void, Never>] = [:]
    /// The last time the stream that tells whether the Meeting is still going was not silent.
    private let lastSound = LastSound()

    private final class LastSound: Sendable {
        private let date = Mutex<Date?>(nil)

        var value: Date? {
            get { date.withLock { $0 } }
            set { date.withLock { $0 = newValue } }
        }
    }

    struct Recording {
        var meeting: LiveMeeting
        var folder: InProgressMeeting
        var mode: InProgressMeeting.State.Mode
        var me: Stream
        var them: Stream
    }

    struct Stream {
        var source: any AudioSource
        var session: any TranscriptionSession
        var recorder: StreamRecorder

        func close() throws {
            source.stop()
            try recorder.close()
        }
    }

    /// `systemAudio` makes the Them stream for a Meeting App: a tap on every process it owns, or, for nil,
    /// everything the Mac plays except Carbon. `keepAudio` is the Keep audio setting, read as each Meeting ends.
    public init(
        microphone: any AudioSource,
        systemAudio: @escaping @Sendable (MeetingApp?) -> any AudioSource,
        systemAudioPermission: @escaping @Sendable () -> SystemAudioPermission,
        transcriber: any Transcriber,
        diarizer: any Diarizer,
        diarizationTimeout: @escaping @Sendable (TimeInterval) -> Duration = Recorder.diarizationTimeout(forAudio:),
        summarizer: any Summarizer = NoSummarizer(),
        library: Library,
        keepAudio: @escaping @Sendable () -> Bool = { false },
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
        self.summarizer = summarizer
        self.library = library
        self.keepAudio = keepAudio
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
        summarizer: any Summarizer = NoSummarizer(),
        library: Library,
        keepAudio: @escaping @Sendable () -> Bool = { false },
        inProgressFolder: URL,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.init(
            microphone: microphone, systemAudio: { _ in systemAudio }, systemAudioPermission: systemAudioPermission,
            transcriber: transcriber, diarizer: diarizer, diarizationTimeout: diarizationTimeout,
            summarizer: summarizer, library: library,
            keepAudio: keepAudio, inProgressFolder: inProgressFolder, timeZone: timeZone, now: now, makeID: makeID)
    }

    /// Runs Detection on `source` until its snapshots end: starts and ends Meetings without a click.
    public func runDetection(_ source: any SignalSource) async {
        for await snapshot in source.micSnapshots() {
            await observe(snapshot)
        }
        while let filing = filings.values.first {
            await filing.value
        }
    }

    private func observe(_ snapshot: MicSnapshot) async {
        let signals = Detector.Signals(
            time: snapshot.time, micHolders: snapshot.micHolders, assertions: snapshot.assertions,
            lastSound: lastSound.value, ignoredApps: ignoredApps, autoTranscribe: autoTranscribe,
            events: snapshot.events)
        for command in detector.observe(signals) {
            do {
                switch command {
                case .start(let app, let event):
                    guard let language = detectionLanguage, recording == nil else {
                        detector.meetingStopped()
                        continue
                    }
                    try await begin(language: language, app: app, event: event, mode: .auto)
                    if case .live(let meeting) = state { onEvent?(.started(meeting)) }
                case .event(let event):
                    try retarget(to: event)
                case .end:
                    if recording != nil { try await finishInBackground() }
                case .offerSwitch(let app):
                    guard case .live(let meeting) = state else { continue }
                    onEvent?(.switchOffered(
                        SwitchOffer(app: app, provider: vendorTable.provider(for: app), meeting: meeting)))
                case .offer(let app, let event):
                    guard let language = detectionLanguage, recording == nil else {
                        detector.offerDeclined(at: snapshot.time)
                        continue
                    }
                    onEvent?(.offered(Offer(
                        app: app, title: Self.title(of: event) ?? MeetingFormat.defaultTitle(start: now(), in: timeZone),
                        provider: vendorTable.provider(for: app, link: event.flatMap(matcher.link(in:))),
                        language: language)))
                case .withdrawOffer(let app):
                    onEvent?(.offerWithdrawn(app))
                }
            } catch {
                onDetectionFailure?(error)
            }
        }
    }

    /// Starts a manual Meeting on the microphone (Me) and the call's audio (Them), transcribed in `language`.
    /// The app holding the mic, if any, becomes its Meeting App, and the usual stop rules apply.
    public func start(language: Locale) async throws {
        guard recording == nil else { throw Failure.notIdle }
        let (app, event) = detector.meetingStarted(at: now(), ignoredApps: ignoredApps)
        try await begin(language: language, app: app, event: event, mode: .manual)
    }

    /// The app of the offer waiting for an answer.
    public var pendingOffer: MeetingApp? { detector.pendingOffer }

    /// Transcribe (or Transcribe in <language>) on the offer. Does nothing once the offer is withdrawn.
    public func acceptOffer(language: Locale) async throws {
        guard recording == nil, let (app, event) = detector.offerAccepted(at: now()) else { return }
        try await begin(language: language, app: app, event: event, mode: .auto)
    }

    /// The offer was dismissed: its app is not offered again for 10 min.
    public func declineOffer() {
        detector.offerDeclined(at: now())
    }

    /// Never on the offer: its app joins the person's Ignored Apps.
    public func neverOffer() {
        guard let app = detector.pendingOffer else { return }
        detector.offerDeclined(at: now())
        ignoredApps.insert(app.bundleID)
    }

    /// Ends the live Meeting and keeps it. Returns the Markdown file written to the Library.
    @discardableResult
    public func stop() async throws -> URL {
        guard recording != nil, case .live = state else { throw Failure.notLive }
        detector.meetingStopped()
        return try await finish()
    }

    /// The person took "Switch to <app>": ends the live Meeting as usual and starts one on `app` at once,
    /// in the same Meeting Language. The ended Meeting is filed meanwhile.
    public func switchMeeting(to app: MeetingApp) async throws {
        try? await languageSwitch?.value
        guard recording != nil, case .live(let meeting) = state else { throw Failure.notLive }
        let event = detector.meetingSwitched(to: app, at: now())
        try await finishInBackground()
        try await begin(language: meeting.language, app: app, event: event, mode: .auto)
        if case .live(let started) = state { onEvent?(.started(started)) }
    }

    /// Ends the live Meeting and keeps nothing.
    public func discard() async {
        try? await languageSwitch?.value
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
        guard recording == nil else { throw Failure.notIdle }
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
    func name(_ meeting: inout LiveMeeting, after event: CalendarEvent?) {
        meeting.event = event
        meeting.title = Self.title(of: event) ?? MeetingFormat.defaultTitle(start: meeting.start, in: timeZone)
        meeting.provider = vendorTable.provider(for: meeting.app, link: event.flatMap(matcher.link(in:)))
    }

    private static func title(of event: CalendarEvent?) -> String? {
        event?.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private func state(of meeting: LiveMeeting, mode: InProgressMeeting.State.Mode) -> InProgressMeeting.State {
        InProgressMeeting.State(
            id: meeting.id, start: MeetingFormat.timestamp(meeting.start, in: timeZone),
            meetingApp: meeting.app?.bundleID, language: MeetingFormat.bcp47(meeting.language), mode: mode,
            event: meeting.event)
    }

    /// Changes the live Meeting's Meeting Language: a new pair of sessions in `language` hears both streams again
    /// from the start, then goes on live, and the old pair's words are dropped. The file is written entirely in
    /// `language`. If the new sessions can't start, the Meeting goes on in its old language and this throws.
    public func switchLanguage(to language: Locale) async throws {
        try? await languageSwitch?.value
        guard recording != nil, case .live(let meeting) = state else { throw Failure.notLive }
        guard language != meeting.language else { return }
        let task = Task { try await handStreams(of: meeting.id, to: language) }
        languageSwitch = task
        defer { if languageSwitch == task { languageSwitch = nil } }
        try await task.value
    }

    private func handStreams(of id: UUID, to language: Locale) async throws {
        let me = try await transcriber.start(locale: language, stream: .me)
        let them: any TranscriptionSession
        do {
            them = try await transcriber.start(locale: language, stream: .them)
        } catch {
            _ = try? await me.finish()
            throw error
        }
        guard var recording, recording.meeting.id == id else {
            _ = try? await me.finish()
            _ = try? await them.finish()
            throw Failure.notLive
        }
        let (meRecorder, themRecorder) = (recording.me.recorder, recording.them.recorder)
        let replaced: [any TranscriptionSession]
        do {
            replaced = try await Task.detached {
                let oldMe = try meRecorder.hand(to: me)
                do {
                    return [oldMe, try themRecorder.hand(to: them)]
                } catch {
                    // Me already moved on: give it back, so both streams stay in one language. The old session
                    // misses the audio of the attempt, which beats a file in two languages.
                    meRecorder.giveBack(oldMe)
                    throw error
                }
            }.value
        } catch {
            _ = try? await me.finish()
            _ = try? await them.finish()
            throw error
        }
        recording.me.session = me
        recording.them.session = them
        recording.meeting.language = language
        self.recording = recording
        state = .live(recording.meeting)
        try? recording.folder.create(state(of: recording.meeting, mode: recording.mode))
        for session in replaced { _ = try? await session.finish() }
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
        try? await languageSwitch?.value
        let (meeting, file) = try close()
        defer { settle(meeting) }
        return try await file()
    }

    /// Ends a Meeting Detection ended without holding up Detection: the next Meeting can start while it is filed.
    private func finishInBackground() async throws {
        try? await languageSwitch?.value
        let (meeting, file) = try close()
        filings[meeting.id] = Task {
            do {
                _ = try await file()
            } catch {
                onDetectionFailure?(error)
            }
            settle(meeting)
            filings[meeting.id] = nil
        }
    }

    /// Stops the live Meeting's capture. Returns the work that files it and says the Transcript is ready.
    /// Wait for a Meeting Language switch first: until it settles, its sessions are not the Recording's yet.
    private func close() throws -> (LiveMeeting, @MainActor () async throws -> URL) {
        guard let recording, case .live(let meeting) = state else { throw Failure.notLive }
        let end = now()
        state = .finishing(meeting)
        self.recording = nil
        // Both captures stop whatever happens to the other: a failed Me must not leave the call's tap running.
        var failure: (any Error)?
        for stream in [recording.me, recording.them] {
            do { try stream.close() } catch { failure = failure ?? error }
        }
        if let failure {
            detector.meetingStopped()
            state = .idle
            throw failure
        }
        let (me, them) = (recording.me.session, recording.them.session)
        return (meeting, {
            let file = try await self.file(meeting, end: end, folder: recording.folder) {
                async let meWords = me.finish()
                async let themWords = them.finish()
                return (try await meWords, try await themWords)
            }
            self.onEvent?(.transcriptReady(id: meeting.id, title: meeting.title, file: file))
            return file
        })
    }

    /// A filed Meeting leaves the state, unless another Meeting has started meanwhile.
    private func settle(_ meeting: LiveMeeting) {
        if state == .finishing(meeting) { state = .idle }
    }

    /// The end of a Meeting, live or recovered: diarization, Library write, Summary, kept audio, cleanup.
    func file(
        _ meeting: LiveMeeting, end: Date, folder: InProgressMeeting,
        words: @escaping @Sendable () async throws -> (me: [TranscribedWord], them: [TranscribedWord])
    ) async throws -> URL {
        async let diarized = Self.diarize(
            folder.themAudio, with: diarizer, timeout: diarizationTimeout(end.timeIntervalSince(meeting.start)))
        let (me, them) = try await words()
        let diarization = await diarized
        let letters = diarization.map { TranscriptBuilder.clusterLetters(them: them, diarization: $0) } ?? [:]
        // A diarization that reaches no Them word has nothing to split: the file stays Me / Them.
        let split = letters.isEmpty ? nil : diarization
        var participants = meeting.event.map(EventMatcher.participants(of:)) ?? []
        // In a 1:1 Event, the lone Them Speaker (or Them) is the other attendee.
        let attendee = participants.count == 1 ? TranscriptBuilder.label(forName: participants[0].name) : nil
        var speakers = split.map { Self.speakers($0, letters: letters) } ?? []
        var labels: [String: String] = [:]
        var heard: [(print: UUID, embedding: [Float])] = []
        if let split, library.recognizesVoices {
            heard = recognizeVoices(in: split, letters: letters, speakers: &speakers, labels: &labels, participants: &participants)
        }
        if let attendee, speakers.count == 1, speakers[0].match == nil {
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
        let transcript = TranscriptBuilder.body(turns)
        let file = try library.create(
            FinishedMeeting(
                id: meeting.id, title: meeting.title, start: meeting.start, end: end, timeZone: timeZone,
                language: meeting.language, provider: meeting.provider, meetingApp: meeting.app?.bundleID,
                providerMeetingId: meeting.event.flatMap(matcher.link(in:))?.meetingId,
                calendarEventId: meeting.event?.id, participants: participants,
                transcriptKind: split == nil ? .fallback : .speakers, speakers: speakers),
            transcript: transcript)
        // The file is what matters: a print that couldn't be updated stays as it was.
        try? library.hearVoices(heard, at: meeting.start)
        // v1 inserts no Summary: NoSummarizer answers nil, and a failure leaves `summary: "off"` too.
        _ = try? await summarizer.summarize(transcript: transcript, language: meeting.language)
        if keepAudio() {
            // The Transcript is what matters: a Meeting whose audio couldn't be encoded is kept without it.
            try? await library.keepAudio(meeting.id, me: folder.meAudio, them: folder.themAudio)
        }
        folder.remove()
        return file
    }

    /// Names the Speakers whose voice matches a Voice Print, and logs every best distance. Returns what was heard.
    private func recognizeVoices(
        in diarization: Diarization, letters: [String: String], speakers: inout [MeetingIndex.Speaker],
        labels: inout [String: String], participants: inout [Participant]
    ) -> [(print: UUID, embedding: [Float])] {
        let prints = library.voicePrints.prints
        let matches = VoicePrintMatcher.match(
            diarization.clusters.filter { letters[$0.id] != nil }, prints: prints, model: library.voicePrintModel)
        var heard: [(print: UUID, embedding: [Float])] = []
        for cluster in diarization.clusters {
            guard let letter = letters[cluster.id], let match = matches[cluster.id],
                  let position = speakers.firstIndex(where: { $0.cluster == letter })
            else { continue }
            let print = match.printID.flatMap { id in prints.first { $0.id == id } }
            onDiagnostic?(
                "Voice Print best distance \(String(format: "%.3f", match.distance)) for Speaker \(letter): "
                    + (print == nil ? "not matched" : "matched"))
            speakers[position].distance = match.distance
            guard let print else { continue }
            speakers[position].label = print.name
            speakers[position].name = print.name
            speakers[position].voicePrintId = print.id
            speakers[position].match = "auto"
            labels[letter] = print.name
            heard.append((print.id, cluster.centroid))
            if !participants.contains(where: { $0.name.caseInsensitiveCompare(print.name) == .orderedSame }) {
                participants.append(Participant(name: print.name, email: print.email))
            }
        }
        return heard
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
