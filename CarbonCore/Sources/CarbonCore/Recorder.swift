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
        id: UUID, title: String, start: Date, language: Locale, app: MeetingApp? = nil, provider: String = Provider.unknown,
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
    public enum Notice: Equatable, Sendable {
        /// Detection started a Meeting on its own.
        case started(LiveMeeting)
        /// Detection offers a Meeting (auto-transcribe off).
        case offered(Offer)
        /// The offer went away: nobody answered within 60 s, or its app released the mic.
        case offerWithdrawn(MeetingApp)
        case transcriptReady(id: UUID, title: String, file: URL)
        /// Another app's start signal during the live Meeting: offer "Switch to <app>".
        case switchOffered(SwitchOffer)
        /// The live Meeting is spoken in another of the checked languages: it is re-transcribed in it.
        case languageIdentified(LiveMeeting)
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
    /// The checked Meeting Languages a Meeting may turn out to be spoken in, read as each Meeting starts: those
    /// whose assets are ready, or none when the person turned identification off.
    @ObservationIgnored public var meetingLanguageCandidates: @MainActor () -> [Locale] = { [] }
    @ObservationIgnored public var onNotice: (@MainActor (Notice) -> Void)?
    /// How loud the live Meeting's microphone is, from 0 (silence) to 1, about ten times a second, for a meter.
    @ObservationIgnored public var onMicLevel: (@MainActor (Float) -> Void)?
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
    private let speechGate: (any SpeechGate)?
    private let library: Library
    private let outputRoute: any OutputRouteSource
    private let keepAudio: @Sendable () -> Bool
    private let debugMode: @Sendable () -> Bool
    let vendorTable: VendorTable
    let matcher: EventMatcher
    let inProgressRoot: URL
    let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var detector: Detector
    var liveCapture: LiveCapture?
    /// The Meeting Language switch under way, which every end of the Meeting waits for.
    private var languageSwitch: Task<Void, any Error>?
    /// The live Meeting's language identification, until the Meeting ends or the person picks a language.
    private var languageIdentification: (meeting: UUID, identification: LanguageIdentification)?
    /// The language the pending offer's Transcribe starts in.
    private var offeredLanguage: Locale?
    /// The last language identification started, which the next one waits for.
    private var lastLanguageIdentification: LanguageIdentification?
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

    /// The live Meeting's capture: its in-progress folder and its two streams.
    struct LiveCapture {
        var meeting: LiveMeeting
        var folder: InProgressMeeting
        var mode: InProgressMeeting.State.Mode
        var me: Stream
        var them: Stream
        var micIsolated: Bool?
        var routeWatch: Task<Void, Never>?
    }

    struct Stream {
        var source: any AudioSource
        var session: any TranscriptionSession
        var recorder: StreamRecorder

        func close() throws {
            source.stop()
            try recorder.close()
        }

        /// Stops the stream and drops its words, keeping nothing.
        func tearDown() async {
            try? close()
            _ = try? await session.finish()
        }
    }

    /// `systemAudio` makes the Them stream for a Meeting App: a tap on every process it owns, or, for nil,
    /// everything the Mac plays except Carbon. `keepAudio` is the Keep audio setting, `debugMode` the Debug mode
    /// one, each read as each Meeting ends.
    public init(
        microphone: any AudioSource,
        systemAudio: @escaping @Sendable (MeetingApp?) -> any AudioSource,
        systemAudioPermission: @escaping @Sendable () -> SystemAudioPermission,
        transcriber: any Transcriber,
        diarizer: any Diarizer,
        diarizationTimeout: @escaping @Sendable (TimeInterval) -> Duration = Recorder.diarizationTimeout(forAudio:),
        summarizer: any Summarizer = NoSummarizer(),
        speechGate: (any SpeechGate)? = nil,
        library: Library,
        outputRoute: any OutputRouteSource = UnknownOutputRoute(),
        keepAudio: @escaping @Sendable () -> Bool = { false },
        debugMode: @escaping @Sendable () -> Bool = { false },
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
        self.speechGate = speechGate
        self.library = library
        self.outputRoute = outputRoute
        self.keepAudio = keepAudio
        self.debugMode = debugMode
        self.vendorTable = vendorTable
        matcher = EventMatcher(vendorTable: vendorTable)
        detector = Detector(vendorTable: vendorTable)
        inProgressRoot = inProgressFolder
        self.timeZone = timeZone
        self.now = now
        self.makeID = makeID
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
                    guard let language = detectionLanguage, liveCapture == nil else {
                        detector.meetingStopped()
                        continue
                    }
                    try await begin(language: language, app: app, event: event, mode: .auto)
                    onDiagnostic?("Detection started a Meeting on \(app.bundleID)")
                    if case .live(let meeting) = state { onNotice?(.started(meeting)) }
                case .event(let event):
                    try retarget(to: event)
                case .end(let reason):
                    guard liveCapture != nil else { continue }
                    onDiagnostic?("Detection ended the Meeting: \(reason)")
                    try await finishInBackground()
                case .offerSwitch(let app):
                    guard case .live(let meeting) = state else { continue }
                    onNotice?(.switchOffered(
                        SwitchOffer(app: app, provider: vendorTable.provider(for: app), meeting: meeting)))
                case .offer(let app, let event):
                    guard let language = detectionLanguage, liveCapture == nil else {
                        detector.offerDeclined(at: snapshot.time)
                        continue
                    }
                    offeredLanguage = language
                    onNotice?(.offered(Offer(
                        app: app, title: title(of: event, startingAt: now()),
                        provider: vendorTable.provider(for: app, link: event.flatMap(matcher.link(in:))),
                        language: language)))
                case .withdrawOffer(let app):
                    onNotice?(.offerWithdrawn(app))
                }
            } catch {
                onDetectionFailure?(error)
            }
        }
    }

    /// Starts a manual Meeting on the microphone (Me) and the call's audio (Them), transcribed in `language`.
    /// The app holding the mic, if any, becomes its Meeting App, and the usual stop rules apply.
    public func start(language: Locale) async throws {
        guard liveCapture == nil else { throw Failure.notIdle }
        let (app, event) = detector.meetingStarted(at: now(), ignoredApps: ignoredApps)
        try await begin(language: language, app: app, event: event, mode: .manual)
    }

    /// The app of the offer waiting for an answer.
    public var pendingOffer: MeetingApp? { detector.pendingOffer }

    /// Transcribe (or Transcribe in <language>) on the offer. Does nothing once the offer is withdrawn.
    /// Transcribe in <language> is the person's choice, so that Meeting's language is never identified.
    public func acceptOffer(language: Locale) async throws {
        guard liveCapture == nil, let (app, event) = detector.offerAccepted(at: now()) else { return }
        let chosen = language.identifier(.bcp47) != offeredLanguage?.identifier(.bcp47)
        try await begin(language: language, app: app, event: event, mode: .auto, identifies: !chosen)
        onDiagnostic?("Detection started a Meeting on \(app.bundleID) from its offer")
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
        guard liveCapture != nil, case .live = state else { throw Failure.notLive }
        detector.meetingStopped()
        return try await finish()
    }

    /// The person took "Switch to <app>": ends the live Meeting as usual and starts one on `app` at once,
    /// in the same Meeting Language. The ended Meeting is filed meanwhile.
    public func switchMeeting(to app: MeetingApp) async throws {
        try? await languageSwitch?.value
        guard liveCapture != nil, case .live(let meeting) = state else { throw Failure.notLive }
        let event = detector.meetingSwitched(to: app, at: now())
        try await finishInBackground()
        try await begin(language: meeting.language, app: app, event: event, mode: .auto)
        if case .live(let started) = state { onNotice?(.started(started)) }
    }

    /// Ends the live Meeting and keeps nothing.
    public func discard() async {
        try? await languageSwitch?.value
        guard let liveCapture else { return }
        detector.meetingStopped()
        stopIdentifyingLanguage()
        liveCapture.routeWatch?.cancel()
        for stream in [liveCapture.me, liveCapture.them] { await stream.tearDown() }
        liveCapture.folder.remove()
        self.liveCapture = nil
        state = .idle
    }

    private func begin(
        language: Locale, app: MeetingApp?, event: CalendarEvent?, mode: InProgressMeeting.State.Mode,
        identifies: Bool = true
    ) async throws {
        guard liveCapture == nil else { throw Failure.notIdle }
        do {
            try await open(language: language, app: app, event: event, mode: mode, identifies: identifies)
        } catch {
            detector.meetingStopped()
            throw error
        }
    }

    private func open(
        language: Locale, app: MeetingApp?, event: CalendarEvent?, mode: InProgressMeeting.State.Mode,
        identifies: Bool
    ) async throws {
        guard systemAudioPermission() != .denied else { throw Failure.systemAudioRecordingDenied }
        var meeting = LiveMeeting(id: makeID(), title: "", start: now(), language: language, app: app)
        name(&meeting, after: event)
        let folder = InProgressMeeting(root: inProgressRoot, id: meeting.id)
        state = .live(meeting)
        lastSound.value = nil
        var opened: [Stream] = []
        do {
            try folder.create(state(of: meeting, mode: mode, micIsolated: nil))
            let me = try await open(.me, from: microphone, into: folder.meAudio, language: language)
            opened.append(me)
            let them = try await open(.them, from: systemAudio(app), into: folder.themAudio, language: language)
            opened.append(them)
            let identification = identifies ? identifyLanguage(of: meeting.id, startingIn: language) : nil
            identification?.listen(me: me.session, them: them.session)
            // With a Meeting App, its audio tells whether the call goes on; without one, only the mic can.
            try capture(me, as: .me, tracksSound: app == nil, identification: identification)
            try capture(them, as: .them, tracksSound: app != nil, identification: identification)
            liveCapture = LiveCapture(
                meeting: meeting, folder: folder, mode: mode, me: me, them: them, routeWatch: watchRoute(of: meeting.id))
        } catch {
            stopIdentifyingLanguage()
            for stream in opened { await stream.tearDown() }
            folder.remove()
            state = .idle
            throw error
        }
    }

    /// Takes in where sound plays until the Meeting ends, which cancels it. One route other than headphones
    /// shares the mic for the whole Meeting.
    private func watchRoute(of id: UUID) -> Task<Void, Never> {
        let routes = outputRoute.routes()
        return Task { [weak self] in
            var isolated: Bool?
            for await route in routes {
                isolated = isolated != false && route == .headphones
                // Without this Meeting's capture there is nothing to write to: the next route brings it up to date.
                guard let self, var capture = liveCapture, capture.meeting.id == id,
                    capture.micIsolated != isolated
                else { continue }
                capture.micIsolated = isolated
                try? goOn(with: capture)
            }
        }
    }

    /// Titles the Meeting after its Event, or by default, and resolves its Provider.
    func name(_ meeting: inout LiveMeeting, after event: CalendarEvent?) {
        meeting.event = event
        meeting.title = title(of: event, startingAt: meeting.start)
        meeting.provider = vendorTable.provider(for: meeting.app, link: event.flatMap(matcher.link(in:)))
    }

    /// The Event's title, or the default one for a Meeting starting at `start`.
    private func title(of event: CalendarEvent?, startingAt start: Date) -> String {
        event?.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? MeetingFormat.defaultTitle(start: start, in: timeZone)
    }

    private func state(
        of meeting: LiveMeeting, mode: InProgressMeeting.State.Mode, micIsolated: Bool?
    ) -> InProgressMeeting.State {
        InProgressMeeting.State(
            id: meeting.id, start: MeetingFormat.timestamp(meeting.start, in: timeZone),
            meetingApp: meeting.app?.bundleID, language: MeetingFormat.bcp47(meeting.language), mode: mode,
            event: meeting.event, micIsolated: micIsolated)
    }

    /// The person changes the live Meeting's Meeting Language, which also ends its language identification: Carbon
    /// never overrides their choice. See `changeLanguage(to:)`.
    public func switchLanguage(to language: Locale) async throws {
        stopIdentifyingLanguage()
        try await changeLanguage(to: language)
    }

    /// Changes the live Meeting's Meeting Language: a new pair of sessions in `language` hears both streams again
    /// from the start, then goes on live, and the old pair's words are dropped. The file is written entirely in
    /// `language`. If the new sessions can't start, the Meeting goes on in its old language and this throws.
    private func changeLanguage(to language: Locale) async throws {
        try? await languageSwitch?.value
        guard liveCapture != nil, case .live(let meeting) = state else { throw Failure.notLive }
        guard language != meeting.language else { return }
        let task = Task { try await handStreams(of: meeting.id, to: language) }
        languageSwitch = task
        defer { if languageSwitch == task { languageSwitch = nil } }
        try await task.value
    }

    /// Starts identifying the language of the Meeting starting in `language`, when there are at least two checked
    /// languages to tell apart. Nil otherwise: the speech gate is never loaded.
    private func identifyLanguage(of id: UUID, startingIn language: Locale) -> LanguageIdentification? {
        guard let speechGate else { return nil }
        let candidates = [language] + meetingLanguageCandidates()
        guard let reader = TextLanguage(candidates: candidates) else {
            let listed = candidates.map(MeetingFormat.bcp47).joined(separator: ", ")
            onDiagnostic?("Meeting Language not identified: nothing to tell apart among \(listed)")
            return nil
        }
        onDiagnostic?(
            "Identifying the Meeting Language among \(reader.candidates.map(MeetingFormat.bcp47).joined(separator: ", "))")
        let identification = LanguageIdentification(
            current: language, reader: reader, speechGate: speechGate, after: lastLanguageIdentification,
            probe: { [weak self] language, stream, range in
                guard let self else { throw Failure.notLive }
                return try await transcribe(stream, of: id, in: language, over: range)
            },
            switchTo: { [weak self] language in
                await self?.identified(language, meeting: id) ?? false
            },
            onDiagnostic: { [weak self] line in self?.onDiagnostic?(line) })
        languageIdentification = (id, identification)
        lastLanguageIdentification = identification
        return identification
    }

    /// Transcribes the stretch `range` of the live Meeting's `stream` again in `language`, apart from the Meeting.
    private func transcribe(
        _ stream: AudioStream, of id: UUID, in language: Locale, over range: ClosedRange<TimeInterval>
    ) async throws -> [TranscribedWord] {
        guard let capture = liveCapture, capture.meeting.id == id else { throw Failure.notLive }
        let recorder = stream == .me ? capture.me.recorder : capture.them.recorder
        let session = try await transcriber.start(locale: language, stream: stream)
        do {
            try await Task.detached { try recorder.replay(range, to: session) }.value
        } catch {
            _ = try? await session.finish()
            throw error
        }
        return try await session.finish()
    }

    /// Re-transcribes the Meeting in the language its identification confirmed. Returns whether it did.
    private func identified(_ language: Locale, meeting id: UUID) async -> Bool {
        guard languageIdentification?.meeting == id, case .live(let meeting) = state else { return false }
        onDiagnostic?(
            "Meeting Language identified as \(MeetingFormat.bcp47(language)), switching from "
                + MeetingFormat.bcp47(meeting.language))
        do {
            try await changeLanguage(to: language)
        } catch {
            onDiagnostic?("Couldn't switch to the identified Meeting Language: \(error.localizedDescription)")
            return false
        }
        guard case .live(let switched) = state, switched.id == id, switched.language == language else { return false }
        onNotice?(.languageIdentified(switched))
        return true
    }

    private func stopIdentifyingLanguage() {
        languageIdentification?.identification.stop()
        languageIdentification = nil
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
        guard var capture = liveCapture, capture.meeting.id == id else {
            _ = try? await me.finish()
            _ = try? await them.finish()
            throw Failure.notLive
        }
        let (meRecorder, themRecorder) = (capture.me.recorder, capture.them.recorder)
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
        if let languageIdentification, languageIdentification.meeting == id {
            languageIdentification.identification.listen(me: me, them: them)
        }
        // An Event or an output route may have come in meanwhile.
        if let current = liveCapture, current.meeting.id == id { capture = current }
        capture.me.session = me
        capture.them.session = them
        capture.meeting.language = language
        try? goOn(with: capture)
        for session in replaced { _ = try? await session.finish() }
    }

    /// The live Meeting belongs to another Event from now on.
    private func retarget(to event: CalendarEvent) throws {
        guard var capture = liveCapture, case .live = state else { return }
        name(&capture.meeting, after: event)
        try goOn(with: capture)
    }

    /// The live Meeting goes on as `capture` says, which its `state.json` follows for recovery.
    private func goOn(with capture: LiveCapture) throws {
        liveCapture = capture
        state = .live(capture.meeting)
        try capture.folder.write(state(of: capture.meeting, mode: capture.mode, micIsolated: capture.micIsolated))
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
    /// Wait for a Meeting Language switch first: until it settles, its sessions are not the capture's yet.
    private func close() throws -> (LiveMeeting, @MainActor () async throws -> URL) {
        guard let capture = liveCapture, case .live(let meeting) = state else { throw Failure.notLive }
        let end = now()
        state = .finishing(meeting)
        liveCapture = nil
        stopIdentifyingLanguage()
        capture.routeWatch?.cancel()
        // Both captures stop whatever happens to the other: a failed Me must not leave the call's tap running.
        var failure: (any Error)?
        for stream in [capture.me, capture.them] {
            do { try stream.close() } catch { failure = failure ?? error }
        }
        if let failure {
            detector.meetingStopped()
            state = .idle
            throw failure
        }
        let (me, them) = (capture.me.session, capture.them.session)
        let micIsolated = state(of: meeting, mode: capture.mode, micIsolated: capture.micIsolated).isMicIsolated
        return (meeting, {
            let file = try await self.file(meeting, end: end, folder: capture.folder, micIsolated: micIsolated) {
                async let meWords = me.finish()
                async let themWords = them.finish()
                return (try await meWords, try await themWords)
            }
            self.onNotice?(.transcriptReady(id: meeting.id, title: meeting.title, file: file))
            return file
        })
    }

    /// A filed Meeting leaves the state, unless another Meeting has started meanwhile.
    private func settle(_ meeting: LiveMeeting) {
        if state == .finishing(meeting) { state = .idle }
    }

    /// The end of a Meeting, live or recovered: diarization, Library write, Debug mode file, Summary, kept audio,
    /// cleanup.
    func file(
        _ meeting: LiveMeeting, end: Date, folder: InProgressMeeting, micIsolated: Bool,
        words: @escaping @Sendable () async throws -> (me: [TranscribedWord], them: [TranscribedWord])
    ) async throws -> URL {
        let heard = try await diarize(meeting, end: end, folder: folder, micIsolated: micIsolated, words: words)
        var naming = nameSpeakers(of: meeting, in: heard)
        let transcript = transcript(of: heard, naming: &naming)
        let file = try write(
            meeting, end: end, transcript: transcript, split: heard.split.me != nil || heard.split.them != nil,
            naming: naming)
        // Before anything awaits: a Meeting deleted meanwhile would leave its file behind, out of the index.
        if debugMode() {
            try? library.writeDebug(
                MeetingDebug(me: heard.me, them: heard.them, split: heard.split, labels: naming.labels), of: meeting.id)
        }
        // The file is what matters: a print that couldn't be updated stays as it was.
        try? library.hearVoices(naming.heard, at: meeting.start)
        if let owner = heard.owner { try? library.hearOwner(owner, at: meeting.start) }
        // v1 inserts no Summary: NoSummarizer answers nil, and a failure leaves `summary: "off"` too.
        _ = try? await summarizer.summarize(transcript: transcript, language: meeting.language)
        if keepAudio() {
            // The Transcript is what matters: a Meeting whose audio couldn't be encoded is kept without it.
            try? await library.keepAudio(meeting.id, me: folder.meAudio, them: folder.themAudio)
        }
        folder.remove()
        return file
    }

    /// A cluster that reaches a word, with the letter it is written as and the stream it was heard on.
    private typealias HeardCluster = (letter: String, stream: AudioStream, cluster: Diarization.Cluster)

    /// What was said in a Meeting, and by which cluster of either stream.
    private struct Heard {
        var me: [TranscribedWord]
        var them: [TranscribedWord]
        /// How the streams are split into Speakers: Them when diarized, Me only when the mic is shared.
        var split: TranscriptBuilder.Split
        /// Each cluster that reaches a word, with the letter it is written as, in letter order.
        var clusters: [HeardCluster]
        /// The owner's voice, from an isolated mic, which feeds their Voice Print.
        var owner: [Float]?
    }

    /// Who the Speakers are: their `meetings.json` entries, the label each cluster letter is written as, and the
    /// frontmatter participants.
    private struct SpeakerNaming {
        var speakers: [MeetingIndex.Speaker]
        var labels: [String: String] = [:]
        var participants: [Participant]
        /// The other attendee of a 1:1 Event, as a label: the lone Them Speaker, or Them.
        var attendee: String?
        /// Each Voice Print auto-matched, with the voice it was heard with.
        var heard: [(print: UUID, embedding: [Float])] = []
    }

    /// The words of both streams, with both audio files diarized meanwhile, each under the watchdog. A shared mic
    /// is split by Speaker, less the call's echo; an isolated one stays `Me` and only tells the owner's voice.
    private func diarize(
        _ meeting: LiveMeeting, end: Date, folder: InProgressMeeting, micIsolated: Bool,
        words: @escaping @Sendable () async throws -> (me: [TranscribedWord], them: [TranscribedWord])
    ) async throws -> Heard {
        let (diarizer, timeout) = (diarizer, diarizationTimeout(end.timeIntervalSince(meeting.start)))
        // One helper process at a time; each stream fails on its own.
        async let diarized = (
            them: await Self.diarize(folder.themAudio, with: diarizer, timeout: timeout),
            me: await Self.diarize(folder.meAudio, with: diarizer, timeout: timeout))
        let (me, them) = try await words()
        let (themDiarization, micDiarization) = await diarized
        var split = TranscriptBuilder.Split(them: themDiarization)
        var owner: [Float]?
        if let micDiarization {
            if micIsolated {
                owner = Self.ownerVoice(micDiarization)
            } else {
                split.me = micDiarization
                split.echo = MicEcho.echo(in: micDiarization, them: themDiarization, themWords: them)
            }
        }
        let letters = TranscriptBuilder.clusterLetters(me: me, them: them, split: split)
        // A diarization that reaches no word of its stream has nothing to split: the stream stays Me or Them.
        if !letters.keys.contains(where: { $0.stream == .them }) { split.them = nil }
        if !letters.keys.contains(where: { $0.stream == .me }) { split = .init(them: split.them) }
        let clusters = [(AudioStream.me, split.me), (.them, split.them)].flatMap { stream, diarization in
            (diarization?.clusters ?? []).compactMap { cluster in
                letters[.init(stream, cluster.id)].map { HeardCluster(letter: $0, stream: stream, cluster: cluster) }
            }
        }
        .sorted { ($0.letter.count, $0.letter) < ($1.letter.count, $1.letter) }
        return Heard(me: me, them: them, split: split, clusters: clusters, owner: owner)
    }

    /// The voice of an isolated mic, which is all the owner's however the diarizer split it: every cluster's clean
    /// voice weighed by its speech. Nil under `VoicePrintMatcher.minimumSpeechSeconds` in all.
    private static func ownerVoice(_ mic: Diarization) -> [Float]? {
        let voiced = mic.clusters.compactMap { cluster in cluster.voice.map { (voice: $0, seconds: cluster.speechSeconds) } }
        guard let length = voiced.max(by: { $0.seconds < $1.seconds })?.voice.count else { return nil }
        // A voice of another length can't be weighed in with the main voice: it is left out.
        let clusters = voiced.filter { $0.voice.count == length }
        guard clusters.reduce(0, { $0 + $1.seconds }) >= VoicePrintMatcher.minimumSpeechSeconds else { return nil }
        let sum = clusters.reduce(into: [Float](repeating: 0, count: length)) { sum, cluster in
            for (index, value) in cluster.voice.enumerated() { sum[index] += value * Float(cluster.seconds) }
        }
        return VoicePrint.normalized(sum)
    }

    /// Names the diarized Speakers after their Voice Print, or after the other attendee of a 1:1 Event.
    private func nameSpeakers(of meeting: LiveMeeting, in heard: Heard) -> SpeakerNaming {
        let participants = meeting.event.map(EventMatcher.participants(of:)) ?? []
        var naming = SpeakerNaming(
            speakers: heard.clusters.map { letter, stream, cluster in
                MeetingIndex.Speaker(
                    label: "Speaker \(letter)", cluster: letter, stream: stream, speechSeconds: cluster.speechSeconds,
                    centroid: cluster.voice.map(MeetingIndex.Speaker.encode(centroid:)))
            },
            participants: participants,
            attendee: participants.count == 1 ? TranscriptBuilder.label(forName: participants[0].name) : nil)
        if !heard.clusters.isEmpty, library.recognizesVoices {
            recognizeVoices(in: heard.clusters, naming: &naming)
        }
        let them = naming.speakers.indices.filter { naming.speakers[$0].stream == .them }
        if let attendee = naming.attendee, them.count == 1, naming.speakers[them[0]].match == nil {
            naming.labels[naming.speakers[them[0]].cluster] = attendee
            naming.speakers[them[0]].label = attendee
            naming.speakers[them[0]].name = attendee
            naming.speakers[them[0]].match = .attendee1to1
        }
        return naming
    }

    /// The `## Transcript` body. In the fallback of a 1:1 Event, Them is written as the other attendee.
    private func transcript(of heard: Heard, naming: inout SpeakerNaming) -> String {
        var turns = TranscriptBuilder.turns(me: heard.me, them: heard.them, split: heard.split, labels: naming.labels)
        if let attendee = naming.attendee, heard.split.them == nil,
           turns.contains(where: { $0.speaker == TranscriptBuilder.them }) {
            turns = turns.map { turn in
                var turn = turn
                if turn.speaker == TranscriptBuilder.them { turn.speaker = attendee }
                return turn
            }
            // As `renameSpeaker` records a named Them, so the label reads as a Speaker named after the attendee.
            naming.speakers.append(MeetingIndex.Speaker(
                label: attendee, cluster: TranscriptBuilder.them, name: attendee, match: .attendee1to1,
                speechSeconds: 0))
        }
        return TranscriptBuilder.body(turns)
    }

    /// Writes the Meeting's file and `meetings.json` entry. Returns the file.
    private func write(
        _ meeting: LiveMeeting, end: Date, transcript: String, split: Bool, naming: SpeakerNaming
    ) throws -> URL {
        try library.create(
            FinishedMeeting(
                id: meeting.id, title: meeting.title, start: meeting.start, end: end, timeZone: timeZone,
                language: meeting.language, provider: meeting.provider, meetingApp: meeting.app?.bundleID,
                providerMeetingId: meeting.event.flatMap(matcher.link(in:))?.meetingId,
                calendarEventId: meeting.event?.id, participants: naming.participants,
                transcriptKind: split ? .speakers : .fallback, speakers: naming.speakers),
            transcript: transcript)
    }

    /// Names the Speakers of both streams whose voice matches a Voice Print, and logs every best distance.
    /// Matching runs over all of them at once, so a print names at most one Speaker.
    private func recognizeVoices(
        in clusters: [HeardCluster], naming: inout SpeakerNaming
    ) {
        let prints = library.voicePrints.prints
        let matches = VoicePrintMatcher.match(
            clusters.map { letter, _, cluster in
                var lettered = cluster
                lettered.id = letter
                return lettered
            },
            prints: prints, model: library.voicePrintModel,
            ownerCandidates: Set(clusters.filter { $0.stream == .me }.map(\.letter)))
        for (letter, _, cluster) in clusters {
            guard let match = matches[letter], let position = naming.speakers.firstIndex(where: { $0.cluster == letter })
            else { continue }
            let print = match.printID.flatMap { id in prints.first { $0.id == id } }
            onDiagnostic?(
                "Voice Print best distance \(String(format: "%.3f", match.distance)) for Speaker \(letter): "
                    + (print == nil ? "not matched" : "matched"))
            naming.speakers[position].distance = match.distance
            guard let print else { continue }
            naming.speakers[position].voicePrintId = print.id
            naming.speakers[position].match = .auto
            if print.owner {
                // Written as on headphones. A shared mic never updates the owner's print: a wrong match can't poison it.
                naming.speakers[position].label = TranscriptBuilder.me
                naming.speakers[position].name = TranscriptBuilder.me
                naming.labels[letter] = TranscriptBuilder.me
                continue
            }
            // The Speaker takes the name of the Participant who is this person: a calendar name over the print's,
            // and the print's for a Participant known only by email.
            let label: String
            if let participant = naming.participants.firstIndex(ofPerson: print.person) {
                naming.participants[participant] = naming.participants[participant].merging(print.person)
                label = TranscriptBuilder.label(forName: naming.participants[participant].name) ?? print.name
            } else {
                naming.participants.append(print.person)
                label = print.name
            }
            naming.speakers[position].label = label
            naming.speakers[position].name = label
            naming.labels[letter] = label
            if let voice = cluster.voice { naming.heard.append((print.id, voice)) }
        }
    }

    /// The diarization watchdog's limit for one attempt: 2 min plus 10 s per minute of audio.
    public nonisolated static func diarizationTimeout(forAudio seconds: TimeInterval) -> Duration {
        .seconds(120) + .seconds(10) * (seconds / 60)
    }

    struct DiarizationTimedOut: Error {}

    /// Diarizes one stream's audio under the watchdog: one retry after a failure or a timeout, then nil (Me / Them).
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

    private func open(
        _ stream: AudioStream, from source: any AudioSource, into file: URL, language: Locale
    ) async throws -> Stream {
        let session = try await transcriber.start(locale: language, stream: stream)
        return Stream(source: source, session: session, recorder: try StreamRecorder(session: session, cafFile: file))
    }

    private func capture(
        _ stream: Stream, as kind: AudioStream, tracksSound: Bool, identification: LanguageIdentification?
    ) throws {
        let recorder = stream.recorder
        let lastSound = tracksSound ? lastSound : nil
        let now = now
        let meterWindow = kind == .me ? MeterWindow() : nil
        try stream.source.start { [weak self] buffer in
            let rms = lastSound != nil || meterWindow != nil ? SoundLevel.rms(buffer) : 0
            if let lastSound, rms > SoundLevel.threshold { lastSound.value = now() }
            if let level = meterWindow?.add(
                SoundLevel.meter(rms: rms), frames: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate)
            {
                Task { @MainActor in self?.onMicLevel?(level) }
            }
            recorder.append(buffer)
            identification?.hear(buffer, on: kind)
        }
    }
}
