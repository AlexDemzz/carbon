import Foundation

extension Library {
    /// How many files "Change…" will move: every visible file in the Library folder, the person's own included.
    public func filesToMove() throws -> Int {
        try files(includingHidden: false).count
    }

    /// Moves the whole Library into `destination`, merging with what is already there, then follows it.
    /// `meetings.json` paths are relative to the Library folder, so they stay valid; reconcile rereads the files.
    /// Nothing moves when `destination` is inside the Library or already holds a file at one of the Library's paths.
    public func move(to destination: URL) throws {
        let source = folder.standardizedFileURL.resolvingSymlinksInPath()
        let target = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !target.pathComponents.starts(with: source.pathComponents) else {
            throw LibraryMoveError.destinationInsideLibrary
        }
        let files = try files(includingHidden: true)
        if let taken = files.first(where: { FileManager.default.fileExists(atPath: destination.appending(path: $0).path) }) {
            throw LibraryMoveError.destinationHasFile(taken)
        }
        for file in files {
            let to = destination.appending(path: file)
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: folder.appending(path: file), to: to)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: folder)
        folder = destination
        try reconcile()
    }

    /// The Library's regular files, relative to its folder.
    private func files(includingHidden: Bool) throws -> [String] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let root = folder.resolvingSymlinksInPath().pathComponents
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: includingHidden ? [] : [.skipsHiddenFiles])
        else { return [] }
        var files: [String] = []
        for case let url as URL in enumerator
        where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files.append(url.resolvingSymlinksInPath().pathComponents.dropFirst(root.count).joined(separator: "/"))
        }
        return files
    }
}

public enum LibraryMoveError: LocalizedError, Equatable {
    case destinationInsideLibrary
    case destinationHasFile(String)

    public var errorDescription: String? {
        switch self {
        case .destinationInsideLibrary:
            "The new folder is inside the Library. Choose a folder outside it."
        case .destinationHasFile(let file):
            "The new folder already has a file at \u{201C}\(file)\u{201D}. Nothing was moved."
        }
    }
}
