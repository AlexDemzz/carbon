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
            microphone: MicrophoneSource(),
            systemAudio: { app in SystemAudioTap(app: app) },
            systemAudioPermission: SystemAudioRecordingPermission.current,
            transcriber: SpeechTranscriberAdapter(),
            library: library,
            inProgressFolder: support.appending(path: "InProgress"))
        do {
            try library.load()
        } catch {
            present(error, title: "Carbon couldn't read its Library")
        }
        showCarbonShortcut = GlobalHotKey { [weak self] in self?.toggleMainWindow() }
        startDetection()
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
