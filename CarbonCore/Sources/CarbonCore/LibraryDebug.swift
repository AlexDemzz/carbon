import Foundation

extension Library {
    /// Debug mode: writes what a Meeting's Transcript was built from as `.debug.json` next to its Markdown file.
    /// Only Markdown files are Meetings, so the Library never lists it.
    func writeDebug(_ debug: MeetingDebug, of id: UUID) throws {
        let entry = try entry(id, in: loadIndex())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(debug).write(to: folder.appending(path: Self.debugFile(of: entry.file)), options: .atomic)
    }

    /// The debug sidecar of a Meeting's Markdown file, both relative to the Library folder.
    static func debugFile(of file: String) -> String {
        (file as NSString).deletingPathExtension + ".debug.json"
    }
}
