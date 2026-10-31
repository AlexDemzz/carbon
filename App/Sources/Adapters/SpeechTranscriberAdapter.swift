@preconcurrency import AVFoundation
import CarbonCore
import Speech
import Synchronization

/// Transcribes one stream live with SpeechAnalyzer + SpeechTranscriber, with volatile results and word timings.
final class SpeechTranscriberAdapter: Transcriber {
    enum Failure: LocalizedError {
        case noAudioFormat(Locale)

        var errorDescription: String? {
            switch self {
            case .noAudioFormat(let locale): "No audio format is available to transcribe \(locale.identifier)."
            }
        }
    }

    /// The module every session runs, which is also the one whose assets Carbon reserves.
    static func module(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [],
            attributeOptions: [.audioTimeRange])
    }

    /// Downloads the language's assets again first, when they are missing.
    func start(locale: Locale, stream: AudioStream) async throws -> any TranscriptionSession {
        let transcriber = Self.module(for: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.noAudioFormat(locale)
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let (finalWords, finalized) = AsyncStream<[TranscribedWord]>.makeStream()
        let collecting = Task {
            defer { finalized.finish() }
            var words = WordBuilder()
            for try await result in transcriber.results where result.isFinal {
                finalized.yield(words.append(result.text))
            }
            return words.finish()
        }
        try await analyzer.start(inputSequence: input)
        return Session(
            audioFormat: format, analyzer: analyzer, input: continuation, finalWords: finalWords, collecting: collecting)
    }

    final class Session: TranscriptionSession {
        let audioFormat: AVAudioFormat
        let finalWords: AsyncStream<[TranscribedWord]>
        private let analyzer: SpeechAnalyzer
        private let input: AsyncStream<AnalyzerInput>.Continuation
        private let collecting: Task<[TranscribedWord], any Error>
        private let clock = Mutex(StreamClock())

        init(
            audioFormat: AVAudioFormat, analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation,
            finalWords: AsyncStream<[TranscribedWord]>, collecting: Task<[TranscribedWord], any Error>
        ) {
            self.audioFormat = audioFormat
            self.finalWords = finalWords
            self.analyzer = analyzer
            self.input = input
            self.collecting = collecting
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            let start = clock.withLock { $0.hear(Double(buffer.frameLength) / audioFormat.sampleRate) }
            input.yield(AnalyzerInput(
                buffer: buffer,
                bufferStartTime: start.map { CMTime(seconds: $0, preferredTimescale: CMTimeScale(audioFormat.sampleRate)) }))
        }

        func skip(_ duration: TimeInterval) {
            clock.withLock { $0.skip(duration) }
        }

        func finish() async throws -> [TranscribedWord] {
            input.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await collecting.value
        }
    }
}

/// Splits SpeechTranscriber's timed text runs into whitespace-separated words, each spanning its first to last timed run.
private struct WordBuilder {
    private var words: [TranscribedWord] = []
    private var text = ""
    private var start: TimeInterval?
    private var end: TimeInterval = 0

    /// Returns the words `result` completes.
    mutating func append(_ result: AttributedString) -> [TranscribedWord] {
        let before = words.count
        for run in result.runs {
            let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self]
            for character in result[run.range].characters {
                if character.isWhitespace {
                    flush()
                } else {
                    text.append(character)
                    if start == nil { start = range?.start.seconds ?? end }
                    end = range?.end.seconds ?? end
                }
            }
        }
        flush()
        return Array(words[before...])
    }

    mutating func finish() -> [TranscribedWord] {
        flush()
        return words
    }

    private mutating func flush() {
        if let start, !text.isEmpty { words.append(TranscribedWord(text: text, start: start, end: end)) }
        text = ""
        start = nil
    }
}
