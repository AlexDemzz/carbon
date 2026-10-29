import Foundation

public enum LibraryError: LocalizedError, Equatable {
    case unknownMeeting(UUID)
    /// The name is empty once `*`, `[`, `]` and line breaks are dropped, or is `Me` / `Them`, or names Me.
    case invalidSpeakerName

    public var errorDescription: String? {
        switch self {
        case .unknownMeeting: "This Meeting is no longer in the Library."
        case .invalidSpeakerName: "“Me” and “Them” are reserved. Choose another name."
        }
    }
}

extension Library {
    /// Changes the Meeting's title. In the file, only the frontmatter `title` line changes; the file name stays.
    public func rename(_ id: UUID, title: String) throws {
        try writeSurgically(id, updating: { $0.title = title }) { MarkdownFile.replacingTitle(in: $0, with: title) }
    }

    /// Sets or clears the Meeting's color dot, e.g. `"red"`. Only `meetings.json` changes.
    public func setColor(_ id: UUID, color: String?) throws {
        try writeSurgically(id, updating: { $0.color = color }) { _ in nil }
    }

    /// Writes what the person typed in the editor. It is theirs: a Local Edit that Carbon never overwrites.
    /// The frontmatter `title` and `participants` they typed become the Meeting's, for the list and Search.
    public func save(_ id: UUID, editedMarkdown: String) throws {
        var index = try loadIndex()
        guard let position = index.meetings.firstIndex(where: { $0.id == id }) else {
            throw LibraryError.unknownMeeting(id)
        }
        try Data(editedMarkdown.utf8).write(to: folder.appending(path: index.meetings[position].file), options: .atomic)
        let before = index.meetings[position]
        if let title = MarkdownFile.title(in: editedMarkdown) { index.meetings[position].title = title }
        if let participants = MarkdownFile.participants(in: editedMarkdown) {
            index.meetings[position].participants = participants
        }
        if index.meetings[position] != before { try save(index) }
        refreshListed(index.meetings[position])
    }

    /// True when the file differs from what Carbon last wrote.
    public func hasLocalEdit(_ id: UUID) throws -> Bool {
        let entry = try entry(id, in: loadIndex())
        let data = try Data(contentsOf: folder.appending(path: entry.file))
        return Self.sha256(data) != entry.writtenHash
    }

    /// Moves the Markdown file, any kept audio and any debug sidecar to the Trash, and leaves a tombstone so the
    /// Meeting never comes back.
    public func delete(_ id: UUID) throws {
        var index = try loadIndex()
        let entry = try entry(id, in: index)
        for file in [entry.file, Self.debugFile(of: entry.file)] + [entry.audio].compactMap(\.self) {
            let url = folder.appending(path: file)
            if FileManager.default.fileExists(atPath: url.path) { try moveToTrash(url) }
        }
        index.meetings.removeAll { $0.id == id }
        index.deleted.append(MeetingIndex.Tombstone(id: id, deletedAt: now().formatted(.iso8601)))
        try save(index)
        meetings.removeAll { $0.id == id }
    }

    /// Every Carbon write after `create` goes through here.
    ///
    /// `transform` returns the new file, changing only Carbon's own lines, or nil to leave the file alone.
    /// `writtenHash` follows the write only when the file was as Carbon last wrote it; a Local Edit stays one.
    func writeSurgically(
        _ id: UUID, updating change: (inout MeetingIndex.Entry) -> Void, file transform: (String) -> String?
    ) throws {
        var index = try loadIndex()
        guard let position = index.meetings.firstIndex(where: { $0.id == id }) else {
            throw LibraryError.unknownMeeting(id)
        }
        change(&index.meetings[position])
        let url = folder.appending(path: index.meetings[position].file)
        if let data = try? Data(contentsOf: url),
           let markdown = String(data: data, encoding: .utf8),
           let rewritten = transform(markdown), rewritten != markdown {
            let wasUntouched = Self.sha256(data) == index.meetings[position].writtenHash
            let newData = Data(rewritten.utf8)
            try newData.write(to: url, options: .atomic)
            if wasUntouched { index.meetings[position].writtenHash = Self.sha256(newData) }
        }
        try save(index)
        refreshListed(index.meetings[position])
    }

    func entry(_ id: UUID, in index: MeetingIndex) throws -> MeetingIndex.Entry {
        guard let entry = index.meetings.first(where: { $0.id == id }) else { throw LibraryError.unknownMeeting(id) }
        return entry
    }

    func refreshListed(_ entry: MeetingIndex.Entry) {
        meetings.removeAll { $0.id == entry.id }
        if let listed = ListedMeeting(entry, folder: folder) { meetings.append(listed) }
        meetings.sort(by: Self.newestFirst)
    }
}
