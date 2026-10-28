@preconcurrency import AVFoundation
import CarbonCore
import Foundation
import Synchronization
import Testing

@MainActor
struct LanguageSwitchTests {
    let library = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-23T13:15:00Z"))
    let meetingID = UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")!
    let microphone = PushAudioSource()
    let systemAudio = PushAudioSource()
    let english = Locale(identifier: "en_US")
    let french = Locale(identifier: "fr_FR")

    var folder: URL { support.url.appending(path: "InProgress/6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21") }

    let transcriber = LanguageReplayTranscriber([
        "en-US": [
            .me: [TranscribedWord(text: "Hello", start: 1, end: 1.4), TranscribedWord(text: "everyone.", start: 1.4, end: 2)],
            .them: [TranscribedWord(text: "Hi.", start: 2.5, end: 2.8)],
        ],
        "fr-FR": [
            .me: [TranscribedWord(text: "Bonjour", start: 1, end: 1.4), TranscribedWord(text: "à tous.", start: 1.4, end: 2)],
            .them: [TranscribedWord(text: "Salut.", start: 2.5, end: 2.8)],
        ],
    ])

    func makeRecorder(transcriber: any Transcriber) -> Recorder {
        let clock = clock
        let meetingID = meetingID
        return Recorder(
            microphone: microphone,
            systemAudio: systemAudio,
            systemAudioPermission: { .granted },
            transcriber: transcriber,
            diarizer: ScriptedDiarizer([.fail, .fail]),
            diarizationTimeout: { _ in .milliseconds(100) },
            library: Library(folder: library.url, supportFolder: support.url, now: { clock.now }, moveToTrash: { _ in }),
            inProgressFolder: support.url.appending(path: "InProgress"),
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: { meetingID })
    }

    @Test func switchingMidMeetingRetranscribesTheWholeMeetingFromTheStartInTheNewLanguage() async throws {
        let recorder = makeRecorder(transcriber: transcriber)

        try await recorder.start(language: english)
        microphone.play(seconds: 7)
        systemAudio.play(seconds: 7)
        clock.advance(by: 60)
        try await recorder.switchLanguage(to: french)

        #expect(recorder.state == .live(LiveMeeting(
            id: meetingID, title: "Meeting Oct 23, 9:15 AM", start: date("2026-10-23T13:15:00Z"), language: french)))
        #expect(try jsonObject(at: folder.appending(path: "state.json"))["language"] as? String == "fr-FR")

        microphone.play(seconds: 1)
        systemAudio.play(seconds: 1)
        clock.advance(by: 60)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8) == """
            ---
            provider: Unknown
            id: 6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21
            date: 2026-10-23T09:15:00-04:00
            title: Meeting Oct 23, 9:15 AM
            duration: 2:00
            language: fr-FR
            participants: []
            ---

            ## Transcript

            **Me** [0:01] Bonjour à tous.

            **Them** [0:02] Salut.

            """)
        #expect(transcriber.sessions == [
            "en-US me 7.0 s", "en-US them 7.0 s", "fr-FR me 8.0 s", "fr-FR them 8.0 s",
        ], "the French pair hears the 7 s recorded before the switch (5 s flushed, 2 s pending), then the 1 s after it, with no gap")
    }

    @Test func whenTheNewLanguageCannotStartTheMeetingGoesOnInTheOldOne() async throws {
        let recorder = makeRecorder(transcriber: transcriber)
        transcriber.failing = ["fr-FR"]

        try await recorder.start(language: english)
        microphone.play(seconds: 2)
        await #expect(throws: LanguageReplayTranscriber.Unavailable.self) {
            try await recorder.switchLanguage(to: french)
        }
        microphone.play(seconds: 1)
        let file = try await recorder.stop()

        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(markdown.contains("language: en-US"))
        #expect(markdown.hasSuffix("**Me** [0:01] Hello everyone.\n\n**Them** [0:02] Hi.\n"))
        #expect(transcriber.sessions == ["en-US me 3.0 s", "en-US them 0.0 s"])
    }

    @Test func switchingWithNoLiveMeetingFails() async throws {
        let recorder = makeRecorder(transcriber: transcriber)

        await #expect(throws: Recorder.Failure.notLive) {
            try await recorder.switchLanguage(to: french)
        }
    }

    func jsonObject(at url: URL) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
    }
}

/// A captured stream the test plays by hand: each `play` pushes that much of a 440 Hz tone, at 48 kHz.
final class PushAudioSource: AudioSource {
    private let onBuffer = Mutex<(@Sendable (AVAudioPCMBuffer) -> Void)?>(nil)

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        self.onBuffer.withLock { $0 = onBuffer }
    }

    func stop() {
        onBuffer.withLock { $0 = nil }
    }

    func play(seconds: Double) {
        guard let onBuffer = onBuffer.withLock({ $0 }) else { return }
        let source = FakeAudioSource(seconds: seconds)
        try? source.start(onBuffer)
    }
}

/// Replays recorded final words per Meeting Language (BCP 47) and stream, and records every session it started.
final class LanguageReplayTranscriber: Transcriber {
    struct Unavailable: Error {}

    let words: [String: [AudioStream: [TranscribedWord]]]
    private let started = Mutex<[(language: String, stream: AudioStream, session: ReplayTranscriber.Session)]>([])
    private let failingLanguages = Mutex<Set<String>>([])

    init(_ words: [String: [AudioStream: [TranscribedWord]]]) {
        self.words = words
    }

    /// Languages whose session fails to start, like a locale whose assets are missing.
    var failing: Set<String> {
        get { failingLanguages.withLock { $0 } }
        set { failingLanguages.withLock { $0 = newValue } }
    }

    /// Every session started, in order, as "<language> <stream> <seconds heard> s".
    var sessions: [String] {
        started.withLock { sessions in
            sessions.map { "\($0.language) \($0.stream) \(String(format: "%.1f", $0.session.seconds)) s" }
        }
    }

    func start(locale: Locale, stream: AudioStream) async throws -> any TranscriptionSession {
        let language = locale.identifier(.bcp47)
        if failing.contains(language) { throw Unavailable() }
        let session = ReplayTranscriber.Session(words: words[language]?[stream] ?? [])
        started.withLock { $0.append((language, stream, session)) }
        return session
    }
}
