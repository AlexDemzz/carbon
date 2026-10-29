import CarbonCore
import CoreML
import Foundation

/// SpeechBrain's VoxLingua107 classifier in Core ML, shipped in the app (`App/LanguageIdentificationModel`). The model
/// is loaded on the first window it scores and let go on `release()`. It runs on the CPU: about 11 ms per window
/// there, where the Neural Engine's dispatch costs more than it saves.
actor CoreMLLanguageClassifier: SpokenLanguageClassifier {
    enum Failure: LocalizedError {
        case missingModel
        case unexpectedOutput

        var errorDescription: String? {
            switch self {
            case .missingModel: "The language identification model is missing from the app bundle."
            case .unexpectedOutput: "The language identification model answered in an unexpected shape."
            }
        }
    }

    nonisolated let labels: Set<String>
    private let outputLabels: [String]
    private let folder: URL?
    private var model: MLModel?

    init(folder: URL? = Bundle.main.url(forResource: "LanguageIdentificationModel", withExtension: nil)) {
        struct Label: Decodable {
            let code: String
        }
        self.folder = folder
        outputLabels = folder
            .flatMap { try? Data(contentsOf: $0.appending(path: "labels.json")) }
            .flatMap { try? JSONDecoder().decode([Label].self, from: $0) }?
            .map(\.code) ?? []
        labels = Set(outputLabels)
    }

    func classify(_ speech: [Float]) async throws -> [String: Double] {
        let features = LogMel.features(of: speech)
        let input = try MLMultiArray(
            shape: [1, NSNumber(value: features.count), NSNumber(value: LogMel.bands)], dataType: .float32)
        input.withUnsafeMutableBufferPointer(ofType: Float.self) { values, strides in
            for (frame, row) in features.enumerated() {
                for (band, value) in row.enumerated() { values[frame * strides[1] + band * strides[2]] = value }
            }
        }
        let output = try Self.predict(try await loaded(), input)
        guard let scores = output.featureValue(for: "log_probabilities")?.multiArrayValue, scores.count == outputLabels.count
        else { throw Failure.unexpectedOutput }
        return Dictionary(uniqueKeysWithValues: outputLabels.enumerated().map { ($1, scores[$0].doubleValue) })
    }

    /// The synchronous prediction: MLModel isn't Sendable, so it never leaves this actor.
    private static func predict(_ model: MLModel, _ features: MLMultiArray) throws -> any MLFeatureProvider {
        try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mel_features": features]))
    }

    func release() {
        model = nil
    }

    private func loaded() async throws -> MLModel {
        if let model { return model }
        guard let url = folder?.appending(path: "SpeechBrainECAPAVoxLingua107.mlmodelc"), !outputLabels.isEmpty else {
            throw Failure.missingModel
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try await MLModel.load(contentsOf: url, configuration: configuration)
        self.model = model
        return model
    }
}
