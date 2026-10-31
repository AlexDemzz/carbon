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

    static let frenchSpeech = """
        Bonjour à tous, merci d'être venus ce matin. Nous allons commencer par le point sur le budget de l'année \
        prochaine, puis nous verrons ensemble le calendrier du projet. Je voudrais aussi que chacun présente \
        rapidement ce qu'il a fait cette semaine, et les difficultés qu'il a rencontrées avec l'équipe technique. \
        Ensuite nous parlerons des recrutements prévus pour le printemps et de la nouvelle organisation des bureaux.
        """
    static let englishSpeech = """
        Hello everyone, thanks for joining this morning. We are going to start with an update on the budget for next \
        year, and then we will walk through the project schedule together. I would also like each of you to share \
        what you worked on this week, and any problems you ran into with the engineering team. After that we will \
        talk about the hires planned for the spring and the new layout of the offices.
        """

    static let germanSpeech = """
        Guten Morgen zusammen, danke dass ihr heute dabei seid. Wir beginnen mit dem Haushalt für das nächste Jahr \
        und schauen uns danach gemeinsam den Zeitplan des Projekts an. Jeder sollte kurz erzählen, woran er diese \
        Woche gearbeitet hat und welche Probleme es mit dem technischen Team gab.
        """

    /// `text`'s words, one every `1 / perSecond` seconds from `start`, as a transcriber finalizes them.
    static func spoken(_ text: String, from start: TimeInterval = 0.5, perSecond rate: Double) -> [TranscribedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin = start + Double(index) / rate
            return TranscribedWord(text: String(word), start: begin, end: begin + 0.8 / rate)
        }
    }

    func makeRecorder(
        transcriber: LanguageReplayTranscriber, speechGate: ScriptedSpeechGate = ScriptedSpeechGate(),
        candidates: [Locale]
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
            speechGate: speechGate,
            library: Library(folder: library.url, supportFolder: support.url, now: { clock.now }, moveToTrash: { _ in }),
            inProgressFolder: support.url.appending(path: "InProgress"),
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { clock.now },
            makeID: { meetingID })
        recorder.meetingLanguageCandidates = { candidates }
        return recorder
    }

    /// The sessions started in `language` on `stream`: the Meeting's own, then each stretch transcribed again in it.
    func sessions(_ transcriber: LanguageReplayTranscriber, _ language: String, _ stream: AudioStream) -> Int {
        transcriber.sessions.filter { $0.hasPrefix("\(language) \(stream) ") }.count
    }

    func languageIdentified(_ notices: [Recorder.Notice]) -> [Locale] {
        notices.compactMap { if case .languageIdentified(let meeting) = $0 { meeting.language } else { nil } }
    }

    /// Lets the identification take in the audio played so far: hearing it costs it next to nothing.
    func settled() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test func aFrenchMeetingStartedInEnglishIsSwitchedOnceItsTranscriptReadsAsFrench() async throws {
        // The English model, given native French, still writes French words.
        let transcriber = LanguageReplayTranscriber([
            "en-US": [.them: Self.spoken(Self.frenchSpeech, perSecond: 3)],
            "fr-FR": [.them: Self.spoken(Self.frenchSpeech, perSecond: 3)],
        ], heardOnly: true)
        let recorder = makeRecorder(transcriber: transcriber, candidates: [english, french])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }

        try await recorder.start(language: english)
        microphone.play(seconds: 20, amplitude: 0)
        systemAudio.play(seconds: 20)
        try await eventually { !notices.isEmpty }
        #expect(notices == [.languageIdentified(LiveMeeting(
            id: meetingID, title: "Meeting Oct 23, 9:15 AM", start: date("2026-10-23T13:15:00Z"), language: french))])
        let file = try await recorder.stop()

        let markdown = try String(contentsOf: file, encoding: .utf8)
        #expect(markdown.contains("language: fr-FR"))
        #expect(markdown.contains("**Them** [0:00] Bonjour à tous, merci d'être venus ce matin."))
    }

    @Test func accentedEnglishTheFrenchModelBarelyWritesIsSwitchedToEnglishByTheRateGuard() async throws {
        // Measured on French-accented English: the French model writes a word here and there.
        let transcriber = LanguageReplayTranscriber([
            "fr-FR": [.me: Self.spoken("Ok alors le prix euh", from: 2, perSecond: 0.2)],
            "en-US": [.me: Self.spoken(Self.englishSpeech, perSecond: 2.5)],
        ], heardOnly: true)
        let recorder = makeRecorder(transcriber: transcriber, candidates: [french, english])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }

        try await recorder.start(language: french)
        microphone.play(seconds: 25)
        try await eventually { !notices.isEmpty }
        let file = try await recorder.stop()

        #expect(languageIdentified(notices) == [english])
        #expect(try String(contentsOf: file, encoding: .utf8).contains("**Me** [0:00] Hello everyone,"))
    }

    @Test func ofTheLanguagesTheRateGuardConfirmsItKeepsTheOneWritingMostOfItsOwnWords() async throws {
        let german = Locale(identifier: "de_DE")
        let transcriber = LanguageReplayTranscriber([
            "fr-FR": [.me: Self.spoken("Ok alors le prix euh", from: 2, perSecond: 0.2)],
            "de-DE": [.me: Self.spoken(Self.germanSpeech, perSecond: 1.5)],
            "en-US": [.me: Self.spoken(Self.englishSpeech, perSecond: 2.5)],
        ], heardOnly: true)
        let recorder = makeRecorder(transcriber: transcriber, candidates: [french, german, english])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }
        var diagnostics: [String] = []
        recorder.onDiagnostic = { diagnostics.append($0) }

        try await recorder.start(language: french)
        microphone.play(seconds: 30)
        try await eventually { !notices.isEmpty }
        await recorder.discard()

        #expect(languageIdentified(notices) == [english])
        #expect(diagnostics.contains { $0.hasPrefix("Me: de-DE writes") && $0.hasSuffix("confirmed") })
    }

    @Test func aMeetingThatChangesLanguageHalfwayIsFollowedBothWays() async throws {
        // Each model, given native speech in the other language, writes that language.
        let them = Self.spoken(Self.englishSpeech, perSecond: 3) + Self.spoken(Self.frenchSpeech, from: 30, perSecond: 3)
        let transcriber = LanguageReplayTranscriber(
            ["fr-FR": [.them: them], "en-US": [.them: them]], heardOnly: true)
        let recorder = makeRecorder(transcriber: transcriber, candidates: [french, english])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }

        try await recorder.start(language: french)
        microphone.play(seconds: 60, amplitude: 0)
        systemAudio.play(seconds: 60)
        try await eventually { languageIdentified(notices).count == 2 }
        await recorder.discard()

        #expect(languageIdentified(notices) == [english, french])
    }

    @Test func noLanguageThatWritesMoreWordsMeansNoSwitchAndAMinuteOfSpeechBeforeTheNextTry() async throws {
        // A language nobody checked: neither model makes words of it.
        let transcriber = LanguageReplayTranscriber([:], heardOnly: true)
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }

        try await recorder.start(language: english)
        microphone.play(seconds: 75)
        try await eventually { sessions(transcriber, "fr-FR", .me) == 1 }
        try await settled()
        #expect(sessions(transcriber, "fr-FR", .me) == 1, "tried once after 20 s of speech, then backs off for 60 s")
        microphone.play(seconds: 15)
        try await eventually { sessions(transcriber, "fr-FR", .me) == 2 }
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: en-US"))
        #expect(languageIdentified(notices).isEmpty)
    }

    @Test func aTranscriptThatReadsAsFrenchIsSwitchedEvenWhenTheFrenchModelWritesFewerWordsThanTheEnglishOne() async throws {
        // Measured on a Meeting going from English to French: on the French stretch, the English model wrote 2.7 words
        // per second of speech, the French one 2.3.
        let transcriber = LanguageReplayTranscriber([
            "en-US": [.me: Self.spoken(Self.frenchSpeech, perSecond: 3)],
            "fr-FR": [.me: Self.spoken(Self.frenchSpeech, perSecond: 2)],
        ], heardOnly: true)
        let recorder = makeRecorder(transcriber: transcriber, candidates: [english, french])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }

        try await recorder.start(language: english)
        microphone.play(seconds: 20)
        try await eventually { !notices.isEmpty }
        await recorder.discard()

        #expect(languageIdentified(notices) == [french])
    }

    @Test func aTranscriptThatReadsAsFrenchStaysEnglishWhenTheFrenchModelBarelyWrites() async throws {
        let transcriber = LanguageReplayTranscriber([
            "en-US": [.me: Self.spoken(Self.frenchSpeech, perSecond: 3)],
            "fr-FR": [.me: Self.spoken(Self.frenchSpeech, perSecond: 0.5)],
        ], heardOnly: true)
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])
        var diagnostics: [String] = []
        recorder.onDiagnostic = { diagnostics.append($0) }

        try await recorder.start(language: english)
        microphone.play(seconds: 15)
        try await eventually { diagnostics.contains { $0.hasPrefix("Me: stays en-US") } }
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: en-US"))
        #expect(sessions(transcriber, "fr-FR", .me) == 1)
        #expect(diagnostics.contains { $0.hasPrefix("Me: fr-FR writes") && $0.hasSuffix("rejected") })
    }

    @Test func anEnglishMeetingInEnglishIsNeverTranscribedAgainNorGated() async throws {
        let transcriber = LanguageReplayTranscriber([
            "en-US": [
                .me: Self.spoken(Self.englishSpeech, perSecond: 2.5),
                .them: Self.spoken(Self.englishSpeech, from: 1, perSecond: 2.5),
            ],
        ], heardOnly: true)
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }

        try await recorder.start(language: english)
        microphone.play(seconds: 30)
        systemAudio.play(seconds: 30)
        try await settled()
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: en-US"))
        #expect(transcriber.sessions == ["en-US me 30.0 s", "en-US them 30.0 s"])
        #expect(languageIdentified(notices).isEmpty)
        #expect(speechGate.chunks.isEmpty, "a transcript keeping up with the sound can't have missed speech")
    }

    @Test func aFewWordlessSecondsAfterALongSilenceAreTooLittleSpeechForTheGuard() async throws {
        // Measured on a real French Meeting: 1 word over the 1.8 s of speech in the last 120 s.
        let transcriber = LanguageReplayTranscriber([
            "en-US": [.me: Self.spoken(Self.englishSpeech, perSecond: 2.5)]
        ], heardOnly: true)
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 25)
        microphone.play(seconds: 120, amplitude: 0)
        microphone.play(seconds: 15)
        try await settled()
        await recorder.discard()

        #expect(sessions(transcriber, "fr-FR", .me) == 0)
    }

    @Test func aLanguageThePersonPicksIsNeverOverridden() async throws {
        // Native English through the French model reads as English.
        let transcriber = LanguageReplayTranscriber([
            "fr-FR": [.them: Self.spoken(Self.englishSpeech, perSecond: 3)],
            "en-US": [.them: Self.spoken(Self.englishSpeech, perSecond: 3)],
        ], heardOnly: true)
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        systemAudio.play(seconds: 2)
        try await recorder.switchLanguage(to: french)
        systemAudio.play(seconds: 20)
        try await Task.sleep(for: .milliseconds(200))
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: fr-FR"))
        #expect(transcriber.sessions == ["en-US me 0.0 s", "en-US them 2.0 s", "fr-FR me 0.0 s", "fr-FR them 22.0 s"])
    }

    @Test func anAcceptedOfferHasItsLanguageIdentified() async throws {
        let transcriber = LanguageReplayTranscriber([
            "en-US": [.them: Self.spoken(Self.frenchSpeech, perSecond: 3)],
            "fr-FR": [.them: Self.spoken(Self.frenchSpeech, perSecond: 3)],
        ], heardOnly: true)
        let recorder = makeRecorder(transcriber: transcriber, candidates: [english, french])
        recorder.detectionLanguage = english
        recorder.autoTranscribe = false
        var notices: [Recorder.Notice] = []
        recorder.onNotice = { notices.append($0) }
        let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")

        await recorder.runDetection(ScriptedSignalSource(clock, from: clock.now, [(0...20, [zoom])]))
        try await recorder.acceptOffer(language: english)
        systemAudio.play(seconds: 20)
        try await eventually { !languageIdentified(notices).isEmpty }
        let file = try await recorder.stop()

        #expect(languageIdentified(notices) == [french])
        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: fr-FR"))
    }

    @Test func anOfferTranscribedInAnotherLanguageIsNeverIdentified() async throws {
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(
            transcriber: LanguageReplayTranscriber([:]), speechGate: speechGate, candidates: [english, french])
        recorder.detectionLanguage = english
        recorder.autoTranscribe = false
        let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")

        await recorder.runDetection(ScriptedSignalSource(clock, from: clock.now, [(0...20, [zoom])]))
        try await recorder.acceptOffer(language: french)
        microphone.play(seconds: 10)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: fr-FR"))
        #expect(speechGate.chunks.isEmpty)
    }

    @Test func anOfferTranscribedInAnotherLanguageStaysChosenWhenTheDefaultChangesMeanwhile() async throws {
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(
            transcriber: LanguageReplayTranscriber([:]), speechGate: speechGate, candidates: [english, french])
        recorder.detectionLanguage = english
        recorder.autoTranscribe = false
        let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")

        await recorder.runDetection(ScriptedSignalSource(clock, from: clock.now, [(0...20, [zoom])]))
        recorder.detectionLanguage = french
        try await recorder.acceptOffer(language: french)
        microphone.play(seconds: 10)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: fr-FR"))
        #expect(speechGate.chunks.isEmpty)
    }

    @Test func withOneCheckedLanguageTheSpeechGateIsNeverUsed() async throws {
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(
            transcriber: LanguageReplayTranscriber([:]), speechGate: speechGate, candidates: [english])

        try await recorder.start(language: english)
        microphone.play(seconds: 30)
        let file = try await recorder.stop()

        #expect(try String(contentsOf: file, encoding: .utf8).contains("language: en-US"))
        #expect(speechGate.chunks.isEmpty)
        #expect(!speechGate.released, "never loaded, so never let go")
    }

    @Test func soundTheSpeechGateDoesNotCallSpeechIsNotSpeechTheTranscriptMissed() async throws {
        let transcriber = LanguageReplayTranscriber([:], heardOnly: true)
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 40, amplitude: 0.05)
        try await eventually { speechGate.chunks.count >= speechGate.chunks(in: 20) }
        try await settled()
        await recorder.discard()

        #expect(sessions(transcriber, "fr-FR", .me) == 0, "40 s of music and no words")
        #expect(speechGate.chunks.allSatisfy { abs($0.peak - 0.05) < 0.01 }, "judged as recorded")
        #expect(speechGate.released)
    }

    @Test func aChunkTheSpeechGateIsLessThan85PercentSureOfIsNotSpeech() async throws {
        let transcriber = LanguageReplayTranscriber([:], heardOnly: true)
        let speechGate = ScriptedSpeechGate(speech: 0.8)
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 40)
        try await eventually { speechGate.chunks.count >= speechGate.chunks(in: 20) }
        try await settled()
        await recorder.discard()

        #expect(sessions(transcriber, "fr-FR", .me) == 0)
    }

    @Test func audioUnderTheSilenceThresholdIsNeverSpeechNorGated() async throws {
        let transcriber = LanguageReplayTranscriber([:], heardOnly: true)
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 40, amplitude: 0.002)
        systemAudio.play(seconds: 40, amplitude: 0)
        try await settled()
        await recorder.discard()

        #expect(sessions(transcriber, "fr-FR", .me) == 0)
        #expect(speechGate.chunks.isEmpty)
    }

    @Test func eachStreamIsJudgedAsItsOwnStream() async throws {
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(
            transcriber: LanguageReplayTranscriber([:]), speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 30)
        systemAudio.play(seconds: 30, amplitude: 0.05)
        try await eventually {
            speechGate.chunks.filter { $0.stream == .me }.count >= speechGate.chunks(in: 20)
                && speechGate.chunks.filter { $0.stream == .them }.count >= speechGate.chunks(in: 20)
        }
        await recorder.discard()

        #expect(speechGate.chunks.filter { $0.stream == .me }.allSatisfy { $0.peak > 0.1 })
        #expect(speechGate.chunks.filter { $0.stream == .them }.allSatisfy { abs($0.peak - 0.05) < 0.01 })
    }

    @Test func noChunkIsJudgedTwice() async throws {
        let transcriber = LanguageReplayTranscriber([:], heardOnly: true)
        let speechGate = ScriptedSpeechGate()
        let recorder = makeRecorder(transcriber: transcriber, speechGate: speechGate, candidates: [english, french])

        try await recorder.start(language: english)
        microphone.play(seconds: 90, amplitude: 0.05)
        try await eventually { speechGate.chunks.count >= speechGate.chunks(in: 60) }
        try await settled()
        await recorder.discard()

        #expect(speechGate.chunks.count <= speechGate.chunks(in: 90))
    }

    @Test func aMeetingStartedRightAfterAnotherIsJudgedOnlyOnceTheFirstLetTheGateGo() async throws {
        let speechGate = ScriptedSpeechGate(delay: .milliseconds(300))
        let recorder = makeRecorder(
            transcriber: LanguageReplayTranscriber([:]), speechGate: speechGate, candidates: [english, french])

        // Sound and no words: the gate judges what the guard counts.
        try await recorder.start(language: english)
        microphone.play(seconds: 30)
        try await eventually { !speechGate.chunks.isEmpty }
        await recorder.discard()
        let judgedInTheFirst = speechGate.chunks.count
        try await recorder.start(language: english)
        microphone.play(seconds: 30)
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

    /// The whole chunks in `seconds` of one stream, at the gate's 16 kHz.
    func chunks(in seconds: Double) -> Int {
        Int(seconds * 16_000) / chunkSize
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
