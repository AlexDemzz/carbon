import Foundation

extension Library {
    /// Debug mode: writes what a Meeting's Transcript was built from to `Debug/<id>.json` in Application Support,
    /// out of the Library folder, which holds only Meetings.
    func writeDebug(_ debug: MeetingDebug, of id: UUID) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: debugFolder, withIntermediateDirectories: true)
        try encoder.encode(debug).write(to: debugFile(of: id), options: .atomic)
    }

    func debugFile(of id: UUID) -> URL {
        debugFolder.appending(path: "\(id.uuidString).json")
    }
}
