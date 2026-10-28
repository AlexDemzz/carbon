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
    }

    public private(set) var state: State = .idle

    private let audioSource: any AudioSource
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
        var session: any TranscriptionSession
        var me: StreamRecorder
    }

    public init(
        audioSource: any AudioSource,
        transcriber: any Transcriber,
        library: Library,
        inProgressFolder: URL,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.audioSource = audioSource
        self.transcriber = transcriber
        self.library = library
        inProgressRoot = inProgressFolder
        self.timeZone = timeZone
        self.now = now
        self.makeID = makeID
    }

    /// Starts a manual Meeting on the microphone, transcribed in `language`.
    public func start(language: Locale) async throws {
        guard state == .idle, recording == nil else { throw Failure.notIdle }
        let start = now()
        let meeting = LiveMeeting(
            id: makeID(), title: MeetingFormat.defaultTitle(start: start, in: timeZone), start: start,
            language: language)
        let folder = InProgressMeeting(root: inProgressRoot, id: meeting.id)
        state = .live(meeting)
        do {
            try folder.create(
                .init(
                    id: meeting.id, start: MeetingFormat.timestamp(start, in: timeZone),
                    language: MeetingFormat.bcp47(language), mode: .manual))
            let session = try await transcriber.start(locale: language)
            let me = try StreamRecorder(session: session, cafFile: folder.meAudio)
            recording = Recording(meeting: meeting, folder: folder, session: session, me: me)
            try audioSource.start { buffer in me.append(buffer) }
        } catch {
            recording = nil
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
        audioSource.stop()
        try recording.me.close()
        let words = try await recording.session.finish()
        let transcript = TranscriptBuilder.body(TranscriptBuilder.turns(me: words))
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
        audioSource.stop()
        try? recording.me.close()
        _ = try? await recording.session.finish()
        recording.folder.remove()
        self.recording = nil
        state = .idle
    }
}
