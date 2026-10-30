// CarbonDiarizer: FluidAudio offline diarization (community-1) of one recorded Them stream.
// Usage: CarbonDiarizer <audio file> <output.json>
// Writes a `Diarization` as JSON and exits 0, or exits 1 with the error on stderr.
// The app runs one process per attempt and kills it when its watchdog fires.
import CarbonCore
import FluidAudio
import Foundation

/// FluidAudio's default and the threshold measured in "Diarization and Voice Print quality on real calls".
let clusteringThreshold = 0.6

func normalized(_ vector: [Float]) -> [Float] {
    let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
    return norm > 0 ? vector.map { $0 / norm } : vector
}

/// The models ship in the app (App/DiarizationModels), so diarization never touches the network.
func bundledModelsDirectory() throws -> URL {
    guard let resources = Bundle.main.resourceURL else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "No app bundle around CarbonDiarizer"])
    }
    return resources.appending(path: "DiarizationModels", directoryHint: .isDirectory)
}

func diarize(_ audio: URL) async throws -> Diarization {
    ModelHub.offlineMode = true
    var config = OfflineDiarizerConfig(clusteringThreshold: clusteringThreshold)
    config.exposeChunkEmbeddings = true
    // Same output and speed as the default 32 windows per call, at about half the peak memory on a 23-minute call.
    config.segmentation.batchSize = 8
    let manager = OfflineDiarizerManager(config: config)
    manager.initialize(models: try await OfflineDiarizerModels.load(from: try bundledModelsDirectory()))
    let result = try await manager.process(audio)
    var speech: [String: Double] = [:]
    for segment in result.segments {
        speech[segment.speakerId, default: 0] += Double(segment.durationSeconds)
    }
    let centroids = result.speakerDatabase ?? [:]
    let voices = SpeakerUtilities.cleanEmbeddingsBySpeaker(result)
    return Diarization(
        segments: result.segments.map {
            .init(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), cluster: $0.speakerId)
        },
        clusters: speech.keys.sorted().map {
            .init(id: $0, centroid: normalized(centroids[$0] ?? []), voice: voices[$0], speechSeconds: speech[$0]!)
        })
}

/// Exits when the app that launched this helper is gone, so a stalled run never outlives it.
func exitWithParent() {
    let parent = getppid()
    Thread.detachNewThread {
        while getppid() == parent { sleep(5) }
        exit(2)
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: CarbonDiarizer <audio file> <output.json>\n".utf8))
    exit(64)
}
exitWithParent()
do {
    let diarization = try await diarize(URL(fileURLWithPath: arguments[1]))
    try JSONEncoder().encode(diarization).write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("CarbonDiarizer: \(error)\n".utf8))
    exit(1)
}
