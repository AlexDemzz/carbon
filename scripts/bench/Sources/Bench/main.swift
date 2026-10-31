// Bench <recording.m4a> [seconds = 150] [offset = 60]
// Runs Carbon's real Recorder, SpeechTranscriber sessions and Core ML models on a recorded Meeting from the Library:
// channel 0 replays as the mic, channel 1 as the call, at real-time pace. Needs no microphone or audio permission
// and plays nothing aloud. scripts/bench/run.sh measures it; see docs/research/transcription-cpu-cost.md.
// Environment: BENCH_SILENT_THEM=1 replaces the call with zeros; BENCH_OUT=<path> keeps the Transcript.
@preconcurrency import AVFoundation
import CarbonCore
import Foundation

/// One channel at 48 kHz, delivered on the wall clock in `chunk` buffers: 100 ms like the mic tap, 10 ms like a
/// process tap.
final class ReplaySource: AudioSource, @unchecked Sendable {
    private let samples: [Float]
    private let chunk: Int
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var position = 0

    init(samples: [Float], chunkSeconds: Double, label: String) {
        self.samples = samples
        chunk = Int(48_000 * chunkSeconds)
        queue = DispatchQueue(label: label, qos: .userInteractive)
    }

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let start = DispatchTime.now()
        timer.schedule(deadline: .now(), repeating: .milliseconds(chunk / 48), leeway: .milliseconds(1))
        timer.setEventHandler { [self] in
            let due = Int(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9 * 48_000)
            while position + chunk <= min(due + chunk, samples.count) {
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk))!
                buffer.frameLength = AVAudioFrameCount(chunk)
                samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress! + position, count: chunk) }
                position += chunk
                onBuffer(buffer)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() { timer?.cancel() }
}

/// Diarization runs after the Meeting, in its own process: measured on its own with CarbonDiarizer.
struct NoDiarizer: Diarizer {
    func diarize(_ audio: URL) async throws -> Diarization { throw CancellationError() }
}

/// Every channel of `file` from `offset`, for `seconds`, at 48 kHz, decoded before the clock starts.
func load(_ file: URL, offset: Double, seconds: Double) throws -> [[Float]] {
    let input = try AVAudioFile(forReading: file)
    let inFormat = input.processingFormat
    input.framePosition = AVAudioFramePosition(offset * inFormat.sampleRate)
    let frames = AVAudioFrameCount(seconds * inFormat.sampleRate)
    let source = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames)!
    try input.read(into: source, frameCount: frames)
    let outFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: inFormat.channelCount)!
    let converter = AVAudioConverter(from: inFormat, to: outFormat)!
    let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(seconds * 48_000) + 1024)!
    nonisolated(unsafe) var done = false
    converter.convert(to: out, error: nil) { _, status in
        if done {
            status.pointee = .endOfStream
            return nil
        }
        done = true
        status.pointee = .haveData
        return source
    }
    return (0..<Int(outFormat.channelCount)).map {
        Array(UnsafeBufferPointer(start: out.floatChannelData![$0], count: Int(out.frameLength)))
    }
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("Usage: Bench <recording.m4a> [seconds = 150] [offset = 60]")
    exit(2)
}
let seconds = arguments.count > 2 ? Double(arguments[2]) ?? 150 : 150
let offset = arguments.count > 3 ? Double(arguments[3]) ?? 60 : 60
let channels = try load(URL(filePath: arguments[1]), offset: offset, seconds: seconds + 5)
let silentThem = ProcessInfo.processInfo.environment["BENCH_SILENT_THEM"] != nil
let them = silentThem ? [Float](repeating: 0, count: channels[0].count) : channels[min(1, channels.count - 1)]
let app = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../App").standardized
let root = FileManager.default.temporaryDirectory.appending(path: "carbon-bench-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root.appending(path: "Library"), withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

let recorder = await MainActor.run {
    let recorder = Recorder(
        microphone: ReplaySource(samples: channels[0], chunkSeconds: 0.1, label: "mic"),
        systemAudio: { _ in ReplaySource(samples: them, chunkSeconds: 0.01, label: "tap") },
        systemAudioPermission: { .granted },
        transcriber: SpeechTranscriberAdapter(), diarizer: NoDiarizer(),
        speechGate: CoreMLSpeechGate(folder: app.appending(path: "SpeechGateModel")),
        library: Library(folder: root.appending(path: "Library"), supportFolder: root),
        inProgressFolder: root.appending(path: "InProgress"))
    recorder.meetingLanguageCandidates = { [Locale(identifier: "en-US")] }
    recorder.onDiagnostic = { print("diag:", $0) }
    return recorder
}
try await recorder.start(language: Locale(identifier: "fr-FR"))
print("READY pid=\(ProcessInfo.processInfo.processIdentifier)")
fflush(stdout)
try await Task.sleep(for: .seconds(seconds))
let url = try await recorder.stop()
let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
print("DONE words=\(text.split(separator: " ").count)")
if let out = ProcessInfo.processInfo.environment["BENCH_OUT"] {
    try text.write(toFile: out, atomically: true, encoding: .utf8)
}
