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

    func create(_ state: State) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateFile, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}
