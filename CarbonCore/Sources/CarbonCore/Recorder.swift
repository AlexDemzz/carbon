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

    public private(set) var state: State = .idle

    private let microphone: any AudioSource
    private let systemAudio: any AudioSource
    private let systemAudioPermission: @Sendable () -> SystemAudioPermission
    private let transcriber: any Transcriber
    private let library: Library
    private let inProgressRoot: URL
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private var recording: Recording?

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

    public init(
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
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.systemAudioPermission = systemAudioPermission
        self.transcriber = transcriber
        self.library = library
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
        async let me = recording.me.session.finish()
        async let them = recording.them.session.finish()
        let transcript = TranscriptBuilder.body(TranscriptBuilder.turns(me: try await me, them: try await them))
        let file = try library.create(
            FinishedMeeting(
                id: meeting.id, title: meeting.title, start: meeting.start, end: end, timeZone: timeZone,
                language: meeting.language, provider: "Unknown", transcriptKind: .fallback),
            transcript: transcript)
        recording.folder.remove()
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
