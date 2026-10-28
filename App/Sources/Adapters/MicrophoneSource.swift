@preconcurrency import AVFoundation
import CarbonCore
import Synchronization

/// The Me stream: the default input device, through AVAudioEngine. When the device list changes (AirPods on),
/// AVAudioEngine reports a configuration change and the capture is rebuilt on the new input.
final class MicrophoneSource: AudioSource {
    private struct Running: @unchecked Sendable {
        var engine: AVAudioEngine?
        var observer: (any NSObjectProtocol)?
        var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    }

    private let running = Mutex(Running())
    private let log: DiagnosticLog

    init(log: DiagnosticLog = .shared) {
        self.log = log
    }

    static func requestAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        try running.withLock { running in
            running.onBuffer = onBuffer
            try Self.startEngine(&running)
        }
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil
        ) { [weak self] notification in
            self?.rebuild(after: notification)
        }
        running.withLock { $0.observer = observer }
    }

    func stop() {
        let observer = running.withLock { running in
            defer { running = Running() }
            running.engine?.inputNode.removeTap(onBus: 0)
            running.engine?.stop()
            return running.observer
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func rebuild(after notification: Notification) {
        running.withLock { running in
            guard let engine = running.engine, notification.object as? AVAudioEngine === engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            do {
                try Self.startEngine(&running)
                log.write("Input device changed: microphone capture rebuilt")
            } catch {
                log.write("Rebuilding the microphone capture failed: \(error.localizedDescription)")
            }
        }
    }

    private static func startEngine(_ running: inout Running) throws {
        guard let onBuffer = running.onBuffer else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 10), format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
        running.engine = engine
    }
}
