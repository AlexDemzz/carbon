@preconcurrency import AVFoundation
import CarbonCore
import Foundation
import Synchronization
import Testing

@MainActor
struct LanguageIdentificationTests {
    let library = try! TemporaryFolder()
    let support = try! TemporaryFolder()
    let clock = TestClock(date("2026-10-23T13:15:00Z"))
    let meetingID = UUID(uuidString: "6F1C2B9E-3D4A-4C2E-9B71-0A5D8E3F4C21")!
    let microphone = PushAudioSource()
    let systemAudio = PushAudioSource()
    let english = Locale(identifier: "en_US")
    let french = Locale(identifier: "fr_FR")

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

    func makeRecorder(
        classifier: ReplayLanguageClassifier, speechGate: ScriptedSpeechGate = ScriptedSpeechGate(), candidates: [Locale]
    ) -> Recorder {
        let clock = clock
        let meetingID = meetingID
        let systemAudio = systemAudio
        let recorder = Recorder(
            microphone: microphone,
            systemAudio: { _ in systemAudio },
            systemAudioPermission: { .granted },
            transcriber: transcriber,
            diarizer: ScriptedDiarizer([.fail, .fail]),
            diarizationTimeout: { _ in .milliseconds(100) },
            languageClassifier: classifier,
            speechGate: speechGate,
            library: Library(folder: library.url, supportFolder: support.url, now: { clock.now }, moveToTrash: { _ in }),
            inProgressFolder: support.url.appending(path: "InProgress"),
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: { meetingID })
        recorder.meetingLanguageCandidates = { candidates }
        return recorder
    }

    /// Ten seconds of speech on both streams: more than the vote needs.
    func speak() {
        microphone.play(seconds: 10)
        systemAudio.play(seconds: 10)
    }

    @Test func aFrenchMeetingStartedInEnglishEndsWrittenInFrench() async throws {
        let classifier = ReplayLanguageClassifier(["fr": log(0.9), "en": log(0.01)])
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(classifier: classifier, speechGate: speechGate, candidates: [english, french])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }

        try await recorder.start(language: english)
        speak()
        try await eventually { !notices.isEmpty }
        #expect(notices == [.languageIdentified(LiveMeeting(
            id: meetingID, title: "Meeting Oct 23, 9:15 AM", start: date("2026-10-23T13:15:00Z"), language: french))])
        let file = try await recorder.stop()

        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(markdown.contains("language: fr-FR"))
        #expect(markdown.hasSuffix("**Me** [0:01] Bonjour à tous.\n\n**Them** [0:02] Salut.\n"))
        #expect(classifier.released, "the model is let go once the Meeting Language is decided")
        #expect(speechGate.released, "and the speech gate's with it")
    }

    @Test func anEnglishMeetingStartedInEnglishStaysInEnglishWithNothingToSee() async throws {
        let classifier = ReplayLanguageClassifier(["en": log(0.9), "fr": log(0.01)])
        let recorder = makeRecorder(classifier: classifier, candidates: [english, french])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }

        try await recorder.start(language: english)
        speak()
        try await eventually { classifier.released }
        speak()
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: en-US"))
        #expect(transcriber.sessions == ["en-US me 20.0 s", "en-US them 20.0 s"])
        #expect(classifier.windows == [4, 4], "it decides on the first 8 s of speech, then stops scoring")
        #expect(!notices.contains { if case .languageIdentified = $0 { true } else { false } })
    }

    @Test func aLanguageThePersonPicksBeforeTheDecisionIsNeverOverridden() async throws {
        let classifier = ReplayLanguageClassifier(["en": log(0.9), "fr": log(0.01)])
        let recorder = makeRecorder(classifier: classifier, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 2)
        systemAudio.play(seconds: 2)
        try await recorder.switchLanguage(to: french)
        speak()
        try await eventually { classifier.released }
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: fr-FR"))
        #expect(classifier.windows.isEmpty)
    }

    @Test func anOfferTranscribedInAnotherLanguageIsNeverIdentified() async throws {
        let classifier = ReplayLanguageClassifier(["en": log(0.9), "fr": log(0.01)])
        let recorder = makeRecorder(classifier: classifier, candidates: [english, french])
        recorder.detectionLanguage = english
        recorder.autoTranscribe = false
        let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")

        await recorder.runDetection(ScriptedSignalSource(clock, from: clock.now, [(0...20, [zoom])]))
        try await recorder.acceptOffer(language: french)
        speak()
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: fr-FR"))
        #expect(classifier.windows.isEmpty)
    }

    @Test func anOfferTranscribedInAnotherLanguageStaysChosenWhenTheDefaultChangesMeanwhile() async throws {
        let classifier = ReplayLanguageClassifier(["en": log(0.9), "fr": log(0.01)])
        let recorder = makeRecorder(classifier: classifier, candidates: [english, french])
        recorder.detectionLanguage = english
        recorder.autoTranscribe = false
        let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")

        await recorder.runDetection(ScriptedSignalSource(clock, from: clock.now, [(0...20, [zoom])]))
        recorder.detectionLanguage = french
        try await recorder.acceptOffer(language: french)
        speak()
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: fr-FR"))
        #expect(classifier.windows.isEmpty)
    }

    @Test func withOneCheckedLanguageTheModelIsNeverUsed() async throws {
        let classifier = ReplayLanguageClassifier(["fr": log(0.9), "en": log(0.01)])
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(classifier: classifier, speechGate: speechGate, candidates: [english])

        try await recorder.start(language: english)
        speak()
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: en-US"))
        #expect(classifier.windows.isEmpty)
        #expect(speechGate.chunks.isEmpty)
        #expect(!classifier.released && !speechGate.released, "never loaded, so never let go")
    }

    @Test func loudSoundTheSpeechGateDoesNotCallSpeechNeverReachesTheClassifier() async throws {
        let classifier = ReplayLanguageClassifier(["fr": log(0.9), "en": log(0.01)])
        let recorder = makeRecorder(classifier: classifier, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 10, amplitude: 0.05)
        systemAudio.play(seconds: 10, amplitude: 0.05)
        microphone.play(seconds: 5)
        try await eventually { !classifier.peaks.isEmpty }
        await recorder.discard()

        #expect(classifier.peaks.first! > 0.1, "the first window scored is the speech after 10 s of music")
    }

    @Test func aChunkTheSpeechGateIsLessThan85PercentSureOfIsNotSpeech() async throws {
        let classifier = ReplayLanguageClassifier(["fr": log(0.9), "en": log(0.01)])
        let speechGate = ScriptedSpeechGate(speech: 0.8)
        let recorder = makeRecorder(classifier: classifier, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        speak()
        try await eventually { speechGate.chunks.count >= 2 * speechGate.chunks(in: 10) }
        await recorder.discard()

        #expect(classifier.windows.isEmpty)
    }

    @Test func eachStreamIsJudgedAsItsOwnStream() async throws {
        let classifier = ReplayLanguageClassifier(["fr": log(0.9), "en": log(0.01)])
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(classifier: classifier, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 2)
        systemAudio.play(seconds: 1, amplitude: 0)
        try await eventually { speechGate.chunks.count >= speechGate.chunks(in: 2) + speechGate.chunks(in: 1) }
        await recorder.discard()

        #expect(speechGate.chunks.filter { $0.stream == .me }.allSatisfy { $0.peak > 0.1 })
        #expect(speechGate.chunks.filter { $0.stream == .them }.allSatisfy { $0.peak == 0 })
    }

    @Test func aMeetingStartedRightAfterAnotherIsJudgedOnlyOnceTheFirstLetTheGateGo() async throws {
        let classifier = ReplayLanguageClassifier(["fr": log(0.9), "en": log(0.01)])
        let speechGate = ScriptedSpeechGate(delay: .milliseconds(300))
        let recorder = makeRecorder(classifier: classifier, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 1)
        try await eventually { !speechGate.chunks.isEmpty }
        await recorder.discard()
        let judgedInTheFirst = speechGate.chunks.count
        try await recorder.start(language: english)
        microphone.play(seconds: 1)
        try await eventually { speechGate.chunks.count > judgedInTheFirst }
        await recorder.discard()

        #expect(
            speechGate.releases.first == judgedInTheFirst,
            "the first Meeting's release never wipes the second's stream state")
    }
}

/// Stands in for Silero VAD: a chunk whose loudest sample passes 0.1 is speech with probability `speech`, any other
/// is speech with probability 0.01, after `delay`. Notes every chunk it was asked about, and how many it had judged
/// at each release.
final class ScriptedSpeechGate: SpeechGate {
    let chunkSize = 4096
    let speech: Double
    let delay: Duration
    private let state = Mutex((chunks: [(stream: AudioStream, peak: Float)](), releases: [Int]()))

    init(speech: Double = 0.97, delay: Duration = .zero) {
        self.speech = speech
        self.delay = delay
    }

    var chunks: [(stream: AudioStream, peak: Float)] { state.withLock { $0.chunks } }
    var releases: [Int] { state.withLock { $0.releases } }
    var released: Bool { !releases.isEmpty }

    /// The whole chunks in `seconds` of one stream.
    func chunks(in seconds: Double) -> Int {
        Int(seconds * LogMel.sampleRate) / chunkSize
    }

    func speechProbability(of chunk: [Float], on stream: AudioStream) async throws -> Double {
        let peak = chunk.map(abs).max() ?? 0
        state.withLock { $0.chunks.append((stream, peak)) }
        try await Task.sleep(for: delay)
        return peak > 0.1 ? speech : 0.01
    }

    func release() async {
        state.withLock { $0.releases.append($0.chunks.count) }
    }
}

/// Stands in for the VoxLingua107 classifier: scores every window the same, and notes what it was asked.
final class ReplayLanguageClassifier: SpokenLanguageClassifier {
    let labels: Set<String> = ["en", "fr", "de"]
    let scores: [String: Double]
    private let state = Mutex((windows: [Double](), peaks: [Float](), released: false))

    init(_ scores: [String: Double]) {
        self.scores = scores
    }

    /// The seconds of speech in each window classified.
    var windows: [Double] { state.withLock { $0.windows } }
    /// The loudest sample of each window classified.
    var peaks: [Float] { state.withLock { $0.peaks } }
    var released: Bool { state.withLock { $0.released } }

    func classify(_ speech: [Float]) async throws -> [String: Double] {
        state.withLock {
            $0.windows.append(Double(speech.count) / LogMel.sampleRate)
            $0.peaks.append(speech.map(abs).max() ?? 0)
        }
        return scores
    }

    func release() async {
        state.withLock { $0.released = true }
    }
}
