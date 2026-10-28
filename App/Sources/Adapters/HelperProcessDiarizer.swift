import CarbonCore
import Foundation
import Synchronization

/// Runs FluidAudio diarization in the `CarbonDiarizer` helper, one fresh process per call, so a CoreML stall
/// can be killed without touching the app. The Recorder's watchdog cancels a call that runs too long.
struct HelperProcessDiarizer: Diarizer {
    struct Failed: Error, CustomStringConvertible {
        var description: String
    }

    let executable: URL? = Bundle.main.url(forAuxiliaryExecutable: "CarbonDiarizer")

    func diarize(_ audio: URL) async throws -> Diarization {
        guard let executable else { throw Failed(description: "CarbonDiarizer is missing from the app bundle") }
        let output = FileManager.default.temporaryDirectory.appending(path: "carbon-diarization-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = executable
        process.arguments = [audio.path, output.path]
        process.standardOutput = FileHandle.nullDevice
        let launched = Mutex(false)
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try launched.withLock { started in
                        guard !Task.isCancelled else { throw CancellationError() }
                        try process.run()
                        started = true
                    }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            // SIGKILL: a stalled CoreML prediction is exactly the case this watchdog exists for.
            launched.withLock { started in
                if started { kill(process.processIdentifier, SIGKILL) }
            }
        }
        try Task.checkCancellation()
        guard status == 0 else { throw Failed(description: "CarbonDiarizer exited with status \(status)") }
        return try JSONDecoder().decode(Diarization.self, from: Data(contentsOf: output))
    }
}
