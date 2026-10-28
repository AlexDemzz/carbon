// PROTOTYPE, throwaway: runs FluidAudio offline diarization on test-set WAVs and dumps
// segments + per-speaker centroids as JSON, one file per (input, clustering threshold).
// Usage: diarize <out dir> <thresholds comma-separated> <wav>...
import FluidAudio
import Foundation

func readWav(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    var offset = 12
    var fmtOK = false
    while offset + 8 <= data.count {
        let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let size = Int(data[offset + 4..<offset + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        let body = offset + 8
        if id == "fmt " {
            let format = data[body..<body + 2].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            let channels = data[body + 2..<body + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            let rate = data[body + 4..<body + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            let bits = data[body + 14..<body + 16].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            precondition(format == 1 && channels == 1 && rate == 16000 && bits == 16, "need 16 kHz mono PCM16: \(url.path)")
            fmtOK = true
        } else if id == "data" {
            precondition(fmtOK)
            let end = min(body + size, data.count)
            return data[body..<end].withUnsafeBytes { raw in
                raw.bindMemory(to: Int16.self).map { Float($0) / 32768 }
            }
        }
        offset = body + size + (size & 1)
    }
    fatalError("no data chunk: \(url.path)")
}

func normalized(_ v: [Float]) -> [Float] {
    let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
    return n > 0 ? v.map { $0 / n } : v
}

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args[1])
let thresholds = args[2].split(separator: ",").map { Double($0)! }
let inputs = args.dropFirst(3).map { URL(fileURLWithPath: $0) }
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let loader = OfflineDiarizerManager()
try await loader.prepareModels()
let models = try await OfflineDiarizerModels.load(from: OfflineDiarizerModels.defaultModelsDirectory())

for input in inputs {
    // <meeting dir>/<stream>.wav → "<meeting>__<stream>"
    let name = input.deletingLastPathComponent().lastPathComponent + "__" + input.deletingPathExtension().lastPathComponent
    let outputs = thresholds.map { outDir.appendingPathComponent("\(name)__t\($0).json") }
    if outputs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { continue }
    let audio = try readWav(input)
    let duration = Double(audio.count) / 16000
    let prepStart = Date()
    var prepared: PreparedDiarization?
    // CoreML occasionally times out a segmentation batch on a long file; a retry clears it.
    for attempt in 1...3 where prepared == nil {
        do {
            prepared = try await loader.prepare(audio: audio)
        } catch {
            print("\(name): prepare attempt \(attempt) failed: \(error.localizedDescription)")
        }
    }
    guard let prepared else { continue }
    let prepSeconds = Date().timeIntervalSince(prepStart)
    for threshold in thresholds {
        let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig(clusteringThreshold: threshold))
        manager.initialize(models: models)
        let clusterStart = Date()
        let result: DiarizationResult
        do {
            result = try manager.cluster(prepared)
        } catch {
            print("\(name) t=\(threshold): \(error)")
            continue
        }
        let clusterSeconds = Date().timeIntervalSince(clusterStart)
        var speechBySpeaker: [String: Double] = [:]
        for s in result.segments { speechBySpeaker[s.speakerId, default: 0] += Double(s.durationSeconds) }
        let json: [String: Any] = [
            "input": input.path,
            "threshold": threshold,
            "duration_s": duration,
            "prepare_s": prepSeconds,
            "cluster_s": clusterSeconds,
            "segments": result.segments.map { ["speaker": $0.speakerId, "start": $0.startTimeSeconds, "end": $0.endTimeSeconds] },
            "speech_s": speechBySpeaker,
            "centroids": (result.speakerDatabase ?? [:]).mapValues(normalized),
        ]
        let out = outDir.appendingPathComponent("\(name)__t\(threshold).json")
        try JSONSerialization.data(withJSONObject: json).write(to: out)
        print(String(format: "%@ t=%.2f: %d speakers, %d segments, %.0f s audio, prepare %.1f s, cluster %.2f s",
                     name, threshold, speechBySpeaker.count, result.segments.count, duration, prepSeconds, clusterSeconds))
    }
}
