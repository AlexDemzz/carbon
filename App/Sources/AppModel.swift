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
    /// Set by a view that can open SwiftUI windows, since the global shortcut fires outside SwiftUI.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored private var showCarbonShortcut: GlobalHotKey?

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
            audioSource: MicrophoneSource(),
            transcriber: SpeechTranscriberAdapter(),
            library: library,
            inProgressFolder: support.appending(path: "InProgress"))
        do {
            try library.load()
        } catch {
            present(error, title: "Carbon couldn't read its Library")
        }
        showCarbonShortcut = GlobalHotKey { [weak self] in self?.toggleMainWindow() }
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

    private func present(_ error: any Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}

enum AppError: LocalizedError {
    case microphoneDenied
    case languageUnsupported(Locale)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Carbon needs microphone access. Allow it in System Settings › Privacy & Security › Microphone."
        case .languageUnsupported(let locale):
            "On-device transcription doesn't support \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)."
        }
    }
}
