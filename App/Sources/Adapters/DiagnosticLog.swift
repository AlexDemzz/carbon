import Foundation
import Synchronization
import os

/// The diagnostic log the person can reveal and send back: what Detection and Capture saw, one line per event.
/// Lives at `~/Library/Logs/Carbon/Diagnostics.log`.
final class DiagnosticLog: Sendable {
    static let shared = DiagnosticLog()

    let file: URL
    private let logger = Logger(subsystem: "me.alexandrejoly.carbon", category: "diagnostics")
    private let written = Mutex<Set<String>>([])
    private let queue = DispatchQueue(label: "me.alexandrejoly.carbon.diagnostic-log")

    private init() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        file = library.appending(path: "Logs/Carbon/Diagnostics.log")
    }

    func write(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(Date().ISO8601Format()) \(message)\n"
        let file = file
        queue.async {
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let handle = try? FileHandle(forWritingTo: file) else {
                try? Data(line.utf8).write(to: file)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    /// Writes `message` the first time `key` is seen in this launch.
    func writeOnce(key: String, _ message: String) {
        guard written.withLock({ $0.insert(key).inserted }) else { return }
        write(message)
    }
}
