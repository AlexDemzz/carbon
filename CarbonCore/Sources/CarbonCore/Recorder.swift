import Foundation
import Observation

/// A Meeting while it is being transcribed.
public struct LiveMeeting: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var language: Locale

    public init(id: UUID, title: String, start: Date, language: Locale) {
        self.id = id
        self.title = title
        self.start = start
        self.language = language
    }
}

/// Runs a Meeting's lifecycle: in-progress folder, live transcription, end, Library write, cleanup.
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

    public internal(set) var state: State = .idle

    private let microphone: any AudioSource
    private let systemAudio: any AudioSource
    private let systemAudioPermission: @Sendable () -> SystemAudioPermission
    let transcriber: any Transcriber
    private let diarizer: any Diarizer
    private let diarizationTimeout: @Sendable (TimeInterval) -> Duration
    private let library: Library
    private let keepAudio: @Sendable () -> Bool
    let inProgressRoot: URL
    let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    var recording: Recording?

    struct Recording {
        var meeting: LiveMeeting
        var folder: InProgressMeeting
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

    public init(
        microphone: any AudioSource,
        systemAudio: any AudioSource,
        systemAudioPermission: @escaping @Sendable () -> SystemAudioPermission,
        transcriber: any Transcriber,
        diarizer: any Diarizer,
        diarizationTimeout: @escaping @Sendable (TimeInterval) -> Duration = Recorder.diarizationTimeout(forAudio:),
        library: Library,
        keepAudio: @escaping @Sendable () -> Bool = { false },
        inProgressFolder: URL,
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
        self.keepAudio = keepAudio
        inProgressRoot = inProgressFolder
        self.timeZone = timeZone
        self.now = now
        self.makeID = makeID
    }

    /// Starts a manual Meeting on the microphone (Me) and the call's audio (Them), transcribed in `language`.
    public func start(language: Locale) async throws {
        guard state == .idle, recording == nil else { throw Failure.notIdle }
        guard systemAudioPermission() != .denied else { throw Failure.systemAudioRecordingDenied }
        let start = now()
        let meeting = LiveMeeting(
            id: makeID(), title: MeetingFormat.defaultTitle(start: start, in: timeZone), start: start,
            language: language)
        let folder = InProgressMeeting(root: inProgressRoot, id: meeting.id)
        state = .live(meeting)
        var opened: [Stream] = []
        do {
            try folder.create(
                .init(
                    id: meeting.id, start: MeetingFormat.timestamp(start, in: timeZone),
                    language: MeetingFormat.bcp47(language), mode: .manual))
            let me = try await open(.me, from: microphone, into: folder.meAudio, language: language)
            opened.append(me)
            let them = try await open(.them, from: systemAudio, into: folder.themAudio, language: language)
            opened.append(them)
            try capture(me)
            try capture(them)
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

    /// Ends the live Meeting and keeps it. Returns the Markdown file written to the Library.
    @discardableResult
    public func stop() async throws -> URL {
        guard let recording, case .live(let meeting) = state else { throw Failure.notLive }
        let end = now()
        state = .finishing(meeting)
        defer {
            self.recording = nil
            state = .idle
        }
        try recording.me.close()
        try recording.them.close()
        let (me, them) = (recording.me.session, recording.them.session)
        return try await finish(meeting, end: end, folder: recording.folder) {
            async let meWords = me.finish()
            async let themWords = them.finish()
            return (try await meWords, try await themWords)
        }
    }

    /// The normal end of a Meeting, live or recovered: diarization, Library write, kept audio, cleanup.
    func finish(
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
        let transcript = TranscriptBuilder.body(TranscriptBuilder.turns(me: me, them: them, diarization: split))
        let file = try library.create(
            FinishedMeeting(
                id: meeting.id, title: meeting.title, start: meeting.start, end: end, timeZone: timeZone,
                language: meeting.language, provider: "Unknown", transcriptKind: split == nil ? .fallback : .speakers,
                speakers: split.map { Self.speakers($0, letters: letters) } ?? []),
            transcript: transcript)
        if keepAudio() {
            // The Transcript is what matters: a Meeting whose audio couldn't be encoded is kept without it.
            try? await library.keepAudio(meeting.id, me: folder.meAudio, them: folder.themAudio)
        }
        folder.remove()
        return file
    }

    /// Ends the live Meeting and keeps nothing.
    public func discard() async {
        guard let recording else { return }
        for stream in [recording.me, recording.them] {
            try? stream.close()
            _ = try? await stream.session.finish()
        }
        recording.folder.remove()
        self.recording = nil
        state = .idle
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

    private func capture(_ stream: Stream) throws {
        let recorder = stream.recorder
        try stream.source.start { buffer in recorder.append(buffer) }
    }
}
