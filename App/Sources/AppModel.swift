import AppKit
import CarbonCore
import Observation
import Speech

/// Wires the Recorder to the Mac's microphone, SpeechTranscriber and the Library folders.
@MainActor
@Observable
final class AppModel {
    let recorder: Recorder
    let library: Library
    /// The Meeting shown in the main window's panel.
    var selection: UUID?
    /// The Meeting waiting for the Delete confirmation, or for a new title.
    var pendingDelete: ListedMeeting?
    var pendingRename: ListedMeeting?
    /// Set by a view that can open SwiftUI windows, since the global shortcut fires outside SwiftUI.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored var openEditor: ((UUID) -> Void)?
    @ObservationIgnored private var showCarbonShortcut: GlobalHotKey?
    @ObservationIgnored private var libraryWatcher: FolderWatcher?

    var isLive: Bool {
        if case .live = recorder.state { true } else { false }
    }

    init() {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let support = applicationSupport.appending(path: "Carbon")
        library = Library(folder: documents.appending(path: "Carbon"), supportFolder: support)
        recorder = Recorder(
            microphone: MicrophoneSource(),
            systemAudio: { app in SystemAudioTap(app: app) },
            systemAudioPermission: SystemAudioRecordingPermission.current,
            transcriber: SpeechTranscriberAdapter(),
            diarizer: HelperProcessDiarizer(),
            library: library,
            keepAudio: { UserDefaults.standard.bool(forKey: SettingsKey.keepAudio) },
            inProgressFolder: support.appending(path: "InProgress"))
        try? fileManager.createDirectory(at: library.folder, withIntermediateDirectories: true)
        reconcileLibrary()
        libraryWatcher = FolderWatcher(folder: library.folder) { [weak self] in self?.reconcileLibrary() }
        showCarbonShortcut = GlobalHotKey { [weak self] in self?.toggleMainWindow() }
        Task { await recoverInterruptedMeetings() }
        startDetection()
    }

    /// Finishes the Meetings a crash interrupted, from the audio already on disk, and says what happened to each.
    private func recoverInterruptedMeetings() async {
        for recovery in await recorder.recover() {
            switch recovery {
            case .recovered(let title, _):
                await Notifier.post("Recovered “\(title)” after Carbon quit unexpectedly.")
            case .discarded(let title):
                await Notifier.post("Carbon couldn't read the audio of “\(title)”, so it was discarded.")
            case .failed(let title):
                let meeting = title.map { "“\($0)”" } ?? "a Meeting"
                await Notifier.post("Carbon couldn't recover \(meeting) and stopped trying.")
            }
        }
    }

    /// Detection runs for the whole launch: a Meeting App holding the mic starts and ends Meetings on its own.
    private func startDetection() {
        recorder.onDetectionFailure = { [weak self] error in
            DiagnosticLog.shared.write("Detection couldn't start or save a Meeting: \(error.localizedDescription)")
            if case Recorder.Failure.systemAudioRecordingDenied = error {
                self?.present(AppError.systemAudioRecordingDenied, title: "Carbon couldn't start transcribing")
            } else {
                self?.present(error, title: "Carbon couldn't transcribe a Meeting")
            }
        }
        let recorder = recorder
        Task {
            guard await MicrophoneSource.requestAccess() else {
                DiagnosticLog.shared.write("Detection is off: no microphone access")
                return
            }
            recorder.detectionLanguage = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
            await recorder.runDetection(SignalSampler())
        }
    }

    /// Show Carbon: brings the main window forward, or hides Carbon when it is already in front.
    func toggleMainWindow() {
        if NSApp.isActive, NSApp.keyWindow?.identifier?.rawValue.hasPrefix(Self.mainWindowID) == true {
            NSApp.hide(nil)
        } else {
            showMainWindow()
        }
    }

    func showMainWindow() {
        openMainWindow?()
        NSApp.activate()
    }

    static let mainWindowID = "main"
    static let editorWindowID = "editor"

    /// The "Transcript ready." notification's Show action: the Meeting, selected in the main window.
    func showMeeting(_ id: UUID) {
        selection = id
        showMainWindow()
    }

    private func reconcileLibrary() {
        do {
            try library.reconcile()
        } catch {
            present(error, title: "Carbon couldn't read its Library")
        }
    }

    // MARK: Meeting actions

    func copyPath(_ meeting: ListedMeeting) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(meeting.file.path, forType: .string)
    }

    func copyMarkdown(_ meeting: ListedMeeting) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentMarkdown(meeting), forType: .string)
    }

    /// The file as it is on disk now, falling back to what Carbon last read.
    func currentMarkdown(_ meeting: ListedMeeting) -> String {
        (try? String(contentsOf: meeting.file, encoding: .utf8)) ?? meeting.markdown
    }

    func revealInFinder(_ meeting: ListedMeeting) {
        NSWorkspace.shared.activateFileViewerSelecting([meeting.file])
    }

    func edit(_ meeting: ListedMeeting) {
        openEditor?(meeting.id)
        NSApp.activate()
    }

    func setColor(_ meeting: ListedMeeting, _ color: String?) {
        perform("Carbon couldn't change the color") { try library.setColor(meeting.id, color: color) }
    }

    func rename(_ meeting: ListedMeeting, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != meeting.title else { return }
        perform("Carbon couldn't rename the Meeting") { try library.rename(meeting.id, title: title) }
    }

    func delete(_ meeting: ListedMeeting) {
        let list = library.meetings
        perform("Carbon couldn't delete the Meeting") {
            try library.delete(meeting.id)
            guard selection == meeting.id, let position = list.firstIndex(where: { $0.id == meeting.id }) else { return }
            let rest = list.filter { $0.id != meeting.id }
            selection = rest.isEmpty ? nil : rest[min(position, rest.count - 1)].id
        }
    }

    /// Writes the editor's text. Returns false, after telling the person, when it couldn't.
    func save(_ id: UUID, editedMarkdown: String) -> Bool {
        do {
            try library.save(id, editedMarkdown: editedMarkdown)
            return true
        } catch {
            present(error, title: "Carbon couldn't save the Meeting")
            return false
        }
    }

    private func perform(_ failureTitle: String, _ action: () throws -> Void) {
        do { try action() } catch { present(error, title: failureTitle) }
    }

    func start() {
        Task {
            do {
                guard await MicrophoneSource.requestAccess() else {
                    throw AppError.microphoneDenied
                }
                guard let language = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                    throw AppError.languageUnsupported(Locale.current)
                }
                try await recorder.start(language: language)
            } catch Recorder.Failure.systemAudioRecordingDenied {
                present(AppError.systemAudioRecordingDenied, title: "Carbon couldn't start transcribing")
            } catch {
                present(error, title: "Carbon couldn't start transcribing")
            }
        }
    }

    func stop() {
        Task {
            do {
                try await recorder.stop()
            } catch {
                present(error, title: "Carbon couldn't save the Meeting")
            }
        }
    }

    func discard() {
        Task { await recorder.discard() }
    }

    func revealLibrary() {
        try? FileManager.default.createDirectory(at: library.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([library.folder])
    }

    func present(_ error: any Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}

/// UserDefaults keys of Settings.
enum SettingsKey {
    static let keepAudio = "keepAudio"
}

enum AppError: LocalizedError {
    case microphoneDenied
    case systemAudioRecordingDenied
    case languageUnsupported(Locale)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Carbon needs microphone access. Allow it in System Settings › Privacy & Security › Microphone."
        case .systemAudioRecordingDenied:
            "Carbon needs System Audio Recording access to hear the other participants. Allow it in System Settings › Privacy & Security › Screen & System Audio Recording."
        case .languageUnsupported(let locale):
            "On-device transcription doesn't support \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)."
        }
    }
}
