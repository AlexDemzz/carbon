import Foundation

/// The folder a live Meeting records into, `InProgress/<id>/`, until it ends: `state.json` and one CAF file per stream.
struct InProgressMeeting {
    struct State: Codable, Equatable {
        enum Mode: String, Codable {
            case auto
            case manual
        }

        var id: UUID
        var start: String
        var meetingApp: String?
        var language: String
        var mode: Mode
        /// The matched calendar Event, as Detection last saw it.
        var event: CalendarEvent?
        var recoveryAttempts = 0
    }

    let folder: URL

    var stateFile: URL { folder.appending(path: "state.json") }
    var meAudio: URL { folder.appending(path: "me.caf") }
    var themAudio: URL { folder.appending(path: "them.caf") }

    init(root: URL, id: UUID) {
        folder = root.appending(path: id.uuidString)
    }

    private init(folder: URL) {
        self.folder = folder
    }

    /// The folders left by Meetings that never ended, i.e. interrupted by a crash. `Failed/` is not one.
    static func interrupted(in root: URL) -> [InProgressMeeting] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return folders
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(InProgressMeeting.init(folder:))
    }

    func create(_ state: State) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(state)
    }

    func state() throws -> State {
        try JSONDecoder().decode(State.self, from: Data(contentsOf: stateFile))
    }

    func write(_ state: State) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateFile, options: .atomic)
    }

    /// Sets the folder aside in `InProgress/Failed/`, where recovery never looks again.
    func moveToFailed() {
        let failed = folder.deletingLastPathComponent().appending(path: "Failed")
        try? FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true)
        let destination = failed.appending(path: folder.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: folder, to: destination)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}
