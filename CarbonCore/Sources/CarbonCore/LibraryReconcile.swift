import Foundation

extension Library {
    /// Follows what happened to the files outside Carbon, then rereads them for the list and Search.
    ///
    /// A file missing at its path is found again by its frontmatter `id` anywhere in the Library folder.
    /// A file found nowhere becomes a Deleted Meeting. Markdown files with an unknown `id` are the person's own.
    public func reconcile() throws {
        var index = try loadIndex()
        let missing = index.meetings.indices.filter {
            !FileManager.default.fileExists(atPath: folder.appending(path: index.meetings[$0].file).path)
        }
        if !missing.isEmpty {
            let found = markdownFilesByID()
            let deletedAt = now().formatted(.iso8601)
            for position in missing {
                if let file = found[index.meetings[position].id] {
                    index.meetings[position].file = file
                } else {
                    index.deleted.append(MeetingIndex.Tombstone(id: index.meetings[position].id, deletedAt: deletedAt))
                }
            }
            let deleted = Set(index.deleted.map(\.id))
            index.meetings.removeAll { deleted.contains($0.id) }
            try save(index)
        }
        meetings = index.meetings
            .compactMap { ListedMeeting($0, folder: folder) }
            .sorted(by: Self.newestFirst)
    }

    /// Every Markdown file in the Library folder that carries an `id`, by that `id`, relative to the folder.
    private func markdownFilesByID() -> [UUID: String] {
        guard let files = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [:] }
        let root = folder.resolvingSymlinksInPath().pathComponents
        var found: [UUID: String] = [:]
        for case let url as URL in files where url.pathExtension.lowercased() == "md" {
            guard
                let markdown = try? String(contentsOf: url, encoding: .utf8),
                let id = MarkdownFile.id(in: markdown)
            else { continue }
            found[id] = url.resolvingSymlinksInPath().pathComponents.dropFirst(root.count).joined(separator: "/")
        }
        return found
    }
}
