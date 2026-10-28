import Foundation
import Observation

/// `voiceprints.json`: the Voice Prints, kept apart from `meetings.json` so that forgetting voices is one clear
/// action. The file stays on this Mac: it is outside the Library folder, out of Carbon's backups and Time Machine's.
@MainActor
@Observable
public final class VoicePrintStore {
    private struct File: Codable {
        var version = 1
        var prints: [VoicePrint] = []
    }

    public let file: URL
    /// Newest first by when the voice was last heard.
    public private(set) var prints: [VoicePrint] = []

    public init(file: URL) {
        self.file = file
        prints = (try? read().prints).map(Self.sorted) ?? []
    }

    /// Rereads the file, applies `change` and writes it. An unreadable file is never overwritten: this throws.
    func update(_ change: (inout [VoicePrint]) throws -> Void) throws {
        var contents = try read()
        let before = contents.prints
        try change(&contents.prints)
        prints = Self.sorted(contents.prints)
        guard contents.prints != before else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(contents).write(to: file, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = file
        try url.setResourceValues(values)
    }

    private func read() throws -> File {
        guard FileManager.default.fileExists(atPath: file.path) else { return File() }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: file))
    }

    private static func sorted(_ prints: [VoicePrint]) -> [VoicePrint] {
        prints.sorted { ($0.lastHeardAt, $1.name) > ($1.lastHeardAt, $0.name) }
    }
}
