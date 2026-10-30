import CarbonCore
import CoreML
import Foundation

/// Silero VAD in Core ML, shipped in the app (`App/SpeechGateModel`). It judges 4096 samples at a time, after the
/// last 64 samples of the stream's chunk before and the LSTM state that chunk left, so each stream keeps its own. The
/// model is loaded on the first chunk it judges and let go, with every stream's state, on `release()`. It runs on the
/// CPU, like the classifier: about 0.2 ms per chunk there, no faster on the Neural Engine, which takes longer to load.
actor CoreMLSpeechGate: SpeechGate {
    enum Failure: LocalizedError {
        case missingModel
        case unexpectedOutput

        var errorDescription: String? {
            switch self {
            case .missingModel: "The speech gate model is missing from the app bundle."
            case .unexpectedOutput: "The speech gate model answered in an unexpected shape."
            }
        }
    }

    nonisolated let chunkSize = 4096
    private static let contextSize = 64
    private static let stateSize = 128

    /// What one stream's chunks so far leave for its next one.
    private struct StreamState {
        var context = [Float](repeating: 0, count: CoreMLSpeechGate.contextSize)
        var hidden = [Float](repeating: 0, count: CoreMLSpeechGate.stateSize)
        var cell = [Float](repeating: 0, count: CoreMLSpeechGate.stateSize)
    }

    private let folder: URL?
    private var model: MLModel?
    private var streams: [AudioStream: StreamState] = [:]

    init(folder: URL? = Bundle.main.url(forResource: "SpeechGateModel", withExtension: nil)) {
        self.folder = folder
    }

    func speechProbability(of chunk: [Float], on stream: AudioStream) async throws -> Double {
        let model = try await loaded()
        let state = streams[stream] ?? StreamState()
        let audio = try Self.array(state.context + chunk)
        let hidden = try Self.array(state.hidden)
        let cell = try Self.array(state.cell)
        let output = try Self.predict(model, audio, hidden, cell)
        guard let probability = output.featureValue(for: "vad_output")?.multiArrayValue,
            let newHidden = output.featureValue(for: "new_hidden_state")?.multiArrayValue,
            let newCell = output.featureValue(for: "new_cell_state")?.multiArrayValue,
            newHidden.count == Self.stateSize, newCell.count == Self.stateSize
        else { throw Failure.unexpectedOutput }
        streams[stream] = StreamState(
            context: Array(chunk.suffix(Self.contextSize)), hidden: Self.values(of: newHidden),
            cell: Self.values(of: newCell))
        return probability[0].doubleValue
    }

    func release() {
        model = nil
        streams = [:]
    }

    /// The synchronous prediction: MLModel isn't Sendable, so it never leaves this actor.
    private static func predict(
        _ model: MLModel, _ audio: MLMultiArray, _ hidden: MLMultiArray, _ cell: MLMultiArray
    ) throws -> any MLFeatureProvider {
        try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "audio_input": audio, "hidden_state": hidden, "cell_state": cell,
        ]))
    }

    private static func array(_ values: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .float32)
        array.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            _ = buffer.initialize(from: values)
        }
        return array
    }

    private static func values(of array: MLMultiArray) -> [Float] {
        (0..<array.count).map { array[$0].floatValue }
    }

    private func loaded() async throws -> MLModel {
        if let model { return model }
        guard let url = folder?.appending(path: "silero-vad-unified-256ms-v6.2.1.mlmodelc") else {
            throw Failure.missingModel
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try await MLModel.load(contentsOf: url, configuration: configuration)
        self.model = model
        return model
    }
}
