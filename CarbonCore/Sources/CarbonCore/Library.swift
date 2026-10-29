import CryptoKit
import Foundation
import Observation

/// The Meetings on the person's Mac: the Markdown files in the Library folder and their index, `meetings.json`.
@MainActor
@Observable
public final class Library {
    static let backupsKept = 14
    static let backupInterval: TimeInterval = 24 * 60 * 60

    public internal(set) var folder: URL
    let indexFile: URL
    let backupsFolder: URL
    /// Debug mode's files, one per Meeting, in `Debug/` next to `meetings.json`.
    public let debugFolder: URL
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var lastBackup: Date?
    @ObservationIgnored let moveToTrash: @Sendable (URL) throws -> Void
    @ObservationIgnored let makeVoicePrintID: @Sendable () -> UUID
    /// The voices Carbon remembers, in `voiceprints.json` next to `meetings.json`.
    public let voicePrints: VoicePrintStore
    /// "Recognize voices": off, Carbon neither matches nor enrolls Voice Prints.
    public var recognizesVoices = true
    /// The embedding model of this build's diarization: only prints it made are compared.
    @ObservationIgnored public let voicePrintModel: String

    /// The Meetings whose file Carbon could read, newest first. Filled by `load()`, kept current by Carbon's writes.
    public internal(set) var meetings: [ListedMeeting] = []

    /// - Parameters:
    ///   - folder: the Library folder, `folder(savedIn:key:home:documents:supportFolder:)`.
    ///   - supportFolder: where `meetings.json`, `Backups/` and `Debug/` live, `~/Library/Application Support/Carbon`.
    ///   - moveToTrash: how Delete gets rid of a file, the Finder's Trash by default.
    public init(
        folder: URL, supportFolder: URL, now: @escaping @Sendable () -> Date = Date.init,
        moveToTrash: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        },
        voicePrintModel: String = VoicePrint.currentModel,
        makeVoicePrintID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.folder = folder
        self.moveToTrash = moveToTrash
        self.voicePrintModel = voicePrintModel
        self.makeVoicePrintID = makeVoicePrintID
        voicePrints = VoicePrintStore(file: supportFolder.appending(path: "voiceprints.json"))
        indexFile = supportFolder.appending(path: "meetings.json")
        backupsFolder = supportFolder.appending(path: "Backups")
        debugFolder = supportFolder.appending(path: "Debug")
        self.now = now
    }

    /// The Library folder saved under `key`. On the first launch, where a Library the person never moved lives:
    /// `~/Carbon`, outside the folders macOS asks permission for, so the first launch shows no prompt. A Library from
    /// before that change, which `meetings.json` gives away, stays in `~/Documents/Carbon`, the folder its files are
    /// already in. The pick is saved, so the first Meeting's `meetings.json` doesn't move it to Documents next launch.
    nonisolated public static func folder(
        savedIn defaults: UserDefaults, key: String, home: URL, documents: URL, supportFolder: URL
    ) -> URL {
        if let saved = defaults.string(forKey: key) { return URL(filePath: saved, directoryHint: .isDirectory) }
        let index = supportFolder.appending(path: "meetings.json")
        let folder = (FileManager.default.fileExists(atPath: index.path) ? documents : home)
            .appending(path: "Carbon", directoryHint: .isDirectory)
        defaults.set(folder.path, forKey: key)
        return folder
    }

    /// Writes a new Meeting's Markdown file and its entry in `meetings.json`. Returns the file's URL.
    @discardableResult
    public func create(_ meeting: FinishedMeeting, transcript: String) throws -> URL {
        let relativePath = try uniqueRelativePath(for: meeting)
        let url = folder.appending(path: relativePath)
        let markdown = MarkdownFile.render(meeting, body: transcript)
        let data = Data(markdown.utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .withoutOverwriting)

        var index = try loadIndex()
        let entry = MeetingIndex.Entry(
            id: meeting.id,
            file: relativePath,
            title: meeting.title,
            start: MeetingFormat.timestamp(meeting.start, in: meeting.timeZone),
            end: MeetingFormat.timestamp(meeting.end, in: meeting.timeZone),
            language: MeetingFormat.bcp47(meeting.language),
            provider: meeting.provider,
            providerMeetingId: meeting.providerMeetingId,
            meetingApp: meeting.meetingApp,
            calendarEventId: meeting.calendarEventId,
            participants: meeting.participants,
            speakers: meeting.speakers,
            transcript: meeting.transcriptKind,
            summary: "off",
            writtenHash: Self.sha256(data))
        index.meetings.append(entry)
        try save(index)
        if let listed = ListedMeeting(entry, folder: folder) {
            meetings.append(listed)
            meetings.sort(by: Self.newestFirst)
        }
        return url
    }

    /// Reads `meetings.json` and every Meeting's file, for the list and Search.
    public func load() throws {
        meetings = try loadIndex().meetings
            .compactMap { ListedMeeting($0, folder: folder) }
            .sorted(by: Self.newestFirst)
    }

    static func newestFirst(_ a: ListedMeeting, _ b: ListedMeeting) -> Bool {
        a.start > b.start
    }

    public func loadIndex() throws -> MeetingIndex {
        guard FileManager.default.fileExists(atPath: indexFile.path) else { return MeetingIndex() }
        return try JSONDecoder().decode(MeetingIndex.self, from: Data(contentsOf: indexFile))
    }

    func save(_ index: MeetingIndex) throws {
        try FileManager.default.createDirectory(
            at: indexFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try backUpIfDue()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(index).write(to: indexFile, options: .atomic)
    }

    /// Copies `meetings.json` to `Backups/` before the first save of a launch, then at most once a day.
    private func backUpIfDue() throws {
        let now = now()
        if let lastBackup, now.timeIntervalSince(lastBackup) < Self.backupInterval { return }
        lastBackup = now
        guard FileManager.default.fileExists(atPath: indexFile.path) else { return }
        try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let stamp = now.formatted(.iso8601.dateSeparator(.omitted).timeSeparator(.omitted))
        try FileManager.default.copyItem(
            at: indexFile, to: backupsFolder.appending(path: "meetings-\(stamp).json"))

        let backups = try FileManager.default.contentsOfDirectory(atPath: backupsFolder.path)
            .filter { $0.hasPrefix("meetings-") && $0.hasSuffix(".json") }
            .sorted(by: >)
        for name in backups.dropFirst(Self.backupsKept) {
            try FileManager.default.removeItem(at: backupsFolder.appending(path: name))
        }
    }

    private func uniqueRelativePath(for meeting: FinishedMeeting) throws -> String {
        let year = MeetingFormat.year(meeting.start, in: meeting.timeZone)
        let stem = "\(MeetingFormat.day(meeting.start, in: meeting.timeZone))-\(Slug.make(meeting.title))"
        let taken = Set(try loadIndex().meetings.map(\.file))
        var suffix = 1
        while true {
            let name = suffix == 1 ? stem : "\(stem)-\(suffix)"
            let path = "\(year)/\(name).md"
            if !taken.contains(path), !FileManager.default.fileExists(atPath: folder.appending(path: path).path) {
                return path
            }
            suffix += 1
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
