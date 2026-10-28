@preconcurrency import AVFoundation
import CarbonCore
import Synchronization

/// The Me stream: the default input device, through AVAudioEngine.
final class MicrophoneSource: AudioSource {
    private let engine = Mutex<AVAudioEngine?>(nil)

    static func requestAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        try engine.withLock { engine in
            let running = AVAudioEngine()
            let input = running.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 10), format: format) { buffer, _ in
                onBuffer(buffer)
            }
            running.prepare()
            try running.start()
            engine = running
        }
    }

    func stop() {
        engine.withLock { engine in
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
        }
    }
}
