import CoreServices
import Foundation

/// Calls `onChange` on the main actor when anything changes under a folder, through FSEvents.
@MainActor
final class FolderWatcher {
    private final class Callback {
        let onChange: @MainActor () -> Void
        init(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    }

    private var stream: FSEventStreamRef?
    private let callback: Callback

    init?(folder: URL, latency: TimeInterval = 0.5, onChange: @escaping @MainActor () -> Void) {
        callback = Callback(onChange)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(callback).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let handler: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { callback.onChange() }
        }
        guard let stream = FSEventStreamCreate(
            nil, handler, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot))
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    isolated deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
