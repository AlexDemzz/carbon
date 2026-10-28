// PROTOTYPE, throwaway: transcribes one test-set WAV with SpeechTranscriber or FluidAudio Parakeet
// and dumps the words with their timings, wall time and peak memory as JSON.
// Usage:
//   asr info [install]
//   asr st <locale> <wav> <out.json> [--realtime] [--context <terms.txt>]
//   asr load <v3|ultra> <model dir>   (times a cold Core ML load from a fresh copy of the models)
//   asr pk <v3|ultra> <wav> <out.json> [--language <en|fr>] [--vocab <terms.txt>]
@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import Speech

struct Word: Codable {
    let w: String
    let s: Double
    let e: Double
}

struct Output: Codable {
    let engine: String
    let model: String
    let input: String
    let duration: Double
    let loadSeconds: Double
    let wallSeconds: Double
    let peakRSSMB: Double
    let words: [Word]
    var volatileUpdates: Int?
    // Real-time runs only: how far behind the audio clock each final result arrived.
    var finalLagMedian: Double?
    var finalLagP95: Double?
    var finalLagMax: Double?
    // Parakeet with --vocab only: the transcript after CTC vocabulary rescoring (it carries no timings).
    var boostedText: String?
    var boostedTerms: [String]?
}

func peakRSSMB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576
}

func percentile(_ values: [Double], _ p: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
}

/// Splits a timed character stream into whitespace-separated words, each spanning its first to last timed piece.
struct WordBuilder {
    private(set) var words: [Word] = []
    private var text = ""
    private var start: Double?
    private var end: Double = 0

    mutating func append(_ piece: String, start pieceStart: Double, end pieceEnd: Double) {
        for character in piece {
            if character.isWhitespace {
                flush()
            } else {
                text.append(character)
                if start == nil { start = pieceStart }
                end = pieceEnd
            }
        }
    }

    mutating func flush() {
        if let start, !text.isEmpty { words.append(Word(w: text, s: start, e: end)) }
        text = ""
        start = nil
    }
}

func speechTranscriberWords(_ text: AttributedString) -> [Word] {
    var builder = WordBuilder()
    for run in text.runs {
        let piece = String(text[run.range].characters)
        guard let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else {
            builder.append(piece, start: 0, end: 0)
            continue
        }
        builder.append(piece, start: range.start.seconds, end: range.end.seconds)
    }
    builder.flush()
    return builder.words
}

func ensureAssets(_ modules: [any SpeechModule]) async throws -> Double {
    let started = Date()
    if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
        try await request.downloadAndInstall()
    }
    return Date().timeIntervalSince(started)
}

final class Collector: @unchecked Sendable {
    var builder = WordBuilder()
    var volatileUpdates = 0
    var lags: [Double] = []
}

func runSpeechTranscriber(locale: Locale, input: URL, realtime: Bool, contextTerms: [String]) async throws -> Output {
    precondition(SpeechTranscriber.isAvailable, "SpeechTranscriber is not available on this Mac")
    let loadStarted = Date()
    let transcriber = SpeechTranscriber(
        locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
        attributeOptions: [.audioTimeRange])
    _ = try await ensureAssets([transcriber])
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
        fatalError("no audio format for \(locale.identifier)")
    }
    try await analyzer.prepareToAnalyze(in: format)
    if !contextTerms.isEmpty {
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextTerms
        try await analyzer.setContext(context)
    }
    let loadSeconds = Date().timeIntervalSince(loadStarted)

    let file = try AVAudioFile(forReading: input)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    let collector = Collector()
    let started = Date()
    let collecting = Task {
        for try await result in transcriber.results {
            if result.isFinal {
                for word in speechTranscriberWords(result.text) {
                    collector.builder.append(word.w + " ", start: word.s, end: word.e)
                }
                if realtime { collector.lags.append(Date().timeIntervalSince(started) - result.range.end.seconds) }
            } else {
                collector.volatileUpdates += 1
            }
        }
    }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: stream)
    guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
        fatalError("cannot convert \(file.processingFormat) to \(format)")
    }
    let chunkFrames: AVAudioFrameCount = 1600  // 100 ms, roughly what a capture tap delivers
    var fed = 0.0
    while file.framePosition < file.length {
        let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames)!
        try file.read(into: source, frameCount: chunkFrames)
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        let target = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 16)!
        var consumed = false
        var error: NSError?
        converter.convert(to: target, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        if let error { throw error }
        continuation.yield(AnalyzerInput(buffer: target))
        fed += Double(source.frameLength) / file.processingFormat.sampleRate
        if realtime {
            let ahead = fed - Date().timeIntervalSince(started)
            if ahead > 0 { try await Task.sleep(for: .seconds(ahead)) }
        }
    }
    continuation.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    try await collecting.value
    collector.builder.flush()

    var output = Output(
        engine: "speechtranscriber", model: locale.identifier, input: input.path, duration: duration,
        loadSeconds: loadSeconds, wallSeconds: Date().timeIntervalSince(started), peakRSSMB: peakRSSMB(),
        words: collector.builder.words)
    output.volatileUpdates = collector.volatileUpdates
    if realtime {
        output.finalLagMedian = percentile(collector.lags, 0.5)
        output.finalLagP95 = percentile(collector.lags, 0.95)
        output.finalLagMax = collector.lags.max()
    }
    return output
}

func runParakeet(
    version: AsrModelVersion, name: String, input: URL, language: Language?, vocabulary: [String]
) async throws -> Output {
    let loadStarted = Date()
    let models = try await AsrModels.downloadAndLoad(version: version)
    let manager = AsrManager(config: .default)
    try await manager.loadModels(models)
    let loadSeconds = Date().timeIntervalSince(loadStarted)

    let started = Date()
    var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
    let result = try await manager.transcribe(input, decoderState: &state, language: language)
    var builder = WordBuilder()
    for timing in result.tokenTimings ?? [] {
        // SentencePiece marks a word start with "▁".
        builder.append(timing.token.replacingOccurrences(of: "▁", with: " "), start: timing.startTime, end: timing.endTime)
    }
    builder.flush()
    var output = Output(
        engine: "parakeet", model: name + (language.map { "-" + $0.rawValue } ?? ""), input: input.path,
        duration: result.duration, loadSeconds: loadSeconds, wallSeconds: Date().timeIntervalSince(started),
        peakRSSMB: peakRSSMB(), words: builder.words)
    if !vocabulary.isEmpty {
        let session = try await VocabularyBoostingSession(
            vocabulary: CustomVocabularyContext(terms: vocabulary.map { CustomVocabularyTerm(text: $0) }),
            ctcModels: try await CtcModels.downloadAndLoad())
        let samples = try AudioConverter().resampleAudioFile(input)
        let rescored = await session.rescore(text: result.text, tokenTimings: result.tokenTimings ?? [], audioSamples: samples)
        output.boostedText = rescored?.text ?? result.text
        output.boostedTerms = rescored?.replacements.filter(\.shouldReplace).compactMap(\.replacementWord)
    }
    return output
}

func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func lines(ofFileIn option: String?) throws -> [String] {
    try option.map { try String(contentsOfFile: $0, encoding: .utf8).split(separator: "\n").map(String.init) } ?? []
}

func write(_ output: Output, to path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(output).write(to: URL(fileURLWithPath: path))
    print(String(format: "%@ %@ %.0fs audio: load %.1fs, run %.1fs (%.0f× RT), peak %.0f MB, %d words",
                 output.engine, output.model, output.duration, output.loadSeconds, output.wallSeconds,
                 output.duration / output.wallSeconds, output.peakRSSMB, output.words.count))
}

let args = CommandLine.arguments
switch args[1] {
case "info":
    print("isAvailable:", SpeechTranscriber.isAvailable)
    print("supported:", await SpeechTranscriber.supportedLocales.map(\.identifier).sorted().joined(separator: " "))
    print("installed:", await SpeechTranscriber.installedLocales.map(\.identifier).sorted().joined(separator: " "))
    for identifier in ["en_US", "fr_FR"] {
        let module = SpeechTranscriber(locale: Locale(identifier: identifier), preset: .transcription)
        print(identifier, "status:", await AssetInventory.status(forModules: [module]))
        if args.count > 2, args[2] == "install" {
            let seconds = try await ensureAssets([module])
            print(identifier, String(format: "installed in %.1fs", seconds), await AssetInventory.status(forModules: [module]))
        }
    }
    print("reserved:", await AssetInventory.reservedLocales.map(\.identifier))
case "st":
    let output = try await runSpeechTranscriber(
        locale: Locale(identifier: args[2]), input: URL(fileURLWithPath: args[3]),
        realtime: args.contains("--realtime"), contextTerms: try lines(ofFileIn: option("--context", in: args)))
    try write(output, to: args[4])
case "load":
    let started = Date()
    _ = try await AsrModels.load(from: URL(fileURLWithPath: args[3]), version: args[2] == "ultra" ? .ultra : .v3)
    print(String(format: "loaded %@ in %.1fs, peak %.0f MB", args[2], Date().timeIntervalSince(started), peakRSSMB()))
case "pk":
    let version: AsrModelVersion = args[2] == "ultra" ? .ultra : .v3
    let output = try await runParakeet(
        version: version, name: args[2], input: URL(fileURLWithPath: args[3]),
        language: option("--language", in: args).flatMap(Language.init(rawValue:)),
        vocabulary: try lines(ofFileIn: option("--vocab", in: args)))
    try write(output, to: args[4])
default:
    fatalError("unknown command \(args[1])")
}
