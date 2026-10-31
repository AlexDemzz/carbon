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
    /// The Settings tab in front, so the menu's missing-permission item can open Permissions.
    var settingsTab: SettingsTab = .general
    /// What Settings › Permissions, the menu bar menu and the onboarding show. Refreshed on launch, on activation and
    /// every minute, and every second while the onboarding is open.
    var permissions = Permissions(
        microphone: .allowed, systemAudioRecording: .allowed, calendar: .allowed, notifications: .allowed)
    /// Set by a view that can open SwiftUI windows, for the model's callers outside SwiftUI.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored var openEditor: ((UUID) -> Void)?
    @ObservationIgnored var openOnboarding: (() -> Void)? {
        didSet { if onboardingPending { showOnboarding() } }
    }
    /// The first launch asked for the onboarding before a view handed over `openOnboarding`.
    @ObservationIgnored private var onboardingPending = false
    @ObservationIgnored private var libraryWatcher: FolderWatcher?
    @ObservationIgnored let notifier = Notifier()
    /// Settings › Languages. Nil on the very first launch until `loadMeetingLanguages()` seeds it from the Mac's languages.
    var meetingLanguages: MeetingLanguages? {
        didSet { meetingLanguagesChanged(from: oldValue) }
    }
    let languageAssets = MeetingLanguageAssets()
    @ObservationIgnored var meetingLanguagesLoad: Task<Void, Never>?
    /// The last "Switch to <app>" offer posted, which its banner's action refers to.
    @ObservationIgnored private var switchOffer: Recorder.SwitchOffer?

    var isLive: Bool {
        if case .live = recorder.state { true } else { false }
    }

    init() {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let support = applicationSupport.appending(path: "Carbon")
        let libraryFolder = Library.folder(
            savedIn: .standard, key: SettingsKey.libraryFolder,
            home: fileManager.homeDirectoryForCurrentUser, documents: documents, supportFolder: support)
        library = Library(folder: libraryFolder, supportFolder: support)
        meetingLanguages = UserDefaults.standard.data(forKey: SettingsKey.meetingLanguages)
            .flatMap { try? JSONDecoder().decode(MeetingLanguages.self, from: $0) }
        recorder = Recorder(
            microphone: MicrophoneSource(),
            systemAudio: { app in SystemAudioTap(app: app) },
            systemAudioPermission: SystemAudioRecordingPermission.current,
            transcriber: SpeechTranscriberAdapter(),
            diarizer: HelperProcessDiarizer(),
            summarizer: NoSummarizer(),
            speechGate: CoreMLSpeechGate(),
            library: library,
            outputRoute: CoreAudioOutputRoute(),
            keepAudio: { UserDefaults.standard.bool(forKey: SettingsKey.keepAudio) },
            debugMode: { UserDefaults.standard.bool(forKey: SettingsKey.debugMode) },
            inProgressFolder: support.appending(path: "InProgress"))
        try? fileManager.createDirectory(at: library.folder, withIntermediateDirectories: true)
        reconcileLibrary()
        watchLibrary()
        UserDefaults.standard.register(defaults: [
            SettingsKey.autoTranscribe: true, SettingsKey.recognizeVoices: true,
        ])
        library.recognizesVoices = UserDefaults.standard.bool(forKey: SettingsKey.recognizeVoices)
        recorder.onDiagnostic = { DiagnosticLog.shared.write($0) }
        recorder.autoTranscribe = UserDefaults.standard.bool(forKey: SettingsKey.autoTranscribe)
        recorder.ignoredApps = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.ignoredApps) ?? [])
        recorder.onNotice = { [weak self] notice in self?.announce(notice) }
        recorder.meetingLanguageCandidates = { [weak self] in self?.meetingLanguageCandidates ?? [] }
        notifier.onResponse = { [weak self] response in self?.respond(to: response) }
        Task {
            if FirstLaunch.run() { showOnboarding() }
            Task { [weak self] in await self?.watchPermissions() }
            async let recovered: Void = recoverInterruptedMeetings()
            await startDetection()
            await recovered
        }
    }

    func watchLibrary() {
        libraryWatcher = FolderWatcher(folder: library.folder) { [weak self] in self?.reconcileLibrary() }
    }

    func stopWatchingLibrary() {
        libraryWatcher = nil
    }

    /// Permissions change in System Settings, outside Carbon: reread them when Carbon comes forward, and every minute.
    private func watchPermissions() async {
        let activations = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await self?.refreshPermissions()
            }
        }
        defer { activations.cancel() }
        while !Task.isCancelled {
            await refreshPermissions()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// "Transcribe Meetings automatically". Off, Detection only offers Meetings.
    var autoTranscribe: Bool {
        get { recorder.autoTranscribe }
        set {
            recorder.autoTranscribe = newValue
            UserDefaults.standard.set(newValue, forKey: SettingsKey.autoTranscribe)
        }
    }

    private func announce(_ notice: Recorder.Notice) {
        switch notice {
        case .started(let meeting):
            notifier.postStarted(meeting)
        case .offered(let offer):
            notifier.postOffer(offer)
        case .offerWithdrawn:
            notifier.withdrawOffer()
        case .transcriptReady(let id, let title, _):
            notifier.postReady(meetingID: id, title: title)
        case .switchOffered(let offer):
            switchOffer = offer
            notifier.postSwitchOffer(offer)
        case .languageIdentified(let meeting):
            meetingLanguageChanged(meeting)
        }
    }

    /// Whether `meetingID` is the live Meeting: a notification can outlive the Meeting it was about.
    private func isLive(_ meetingID: UUID) -> Bool {
        guard case .live(let meeting) = recorder.state else { return false }
        return meeting.id == meetingID
    }

    private func respond(to response: Notifier.Response) {
        switch response {
        case .stop(let meetingID):
            notifier.removeStarted(meetingID)
            // A banner left over from an earlier Meeting never discards the current one.
            guard isLive(meetingID) else { return }
            discard()
        case .transcribe(let app):
            guard recorder.pendingOffer?.bundleID == app else { return }
            Task {
                do {
                    try await recorder.acceptOffer()
                } catch Recorder.Failure.systemAudioRecordingDenied {
                    present(AppError.systemAudioRecordingDenied, title: "Carbon couldn't start transcribing")
                } catch {
                    present(error, title: "Carbon couldn't start transcribing")
                }
            }
        case .decline(let app):
            guard recorder.pendingOffer?.bundleID == app else { return }
            recorder.declineOffer()
        case .never(let app):
            guard recorder.pendingOffer?.bundleID == app else { return }
            recorder.neverOffer()
            saveIgnoredApps()
        case .show(let meetingID):
            showMeeting(meetingID)
        case .switchTo(let app, let meetingID):
            // An offer outlives its Meeting in Notification Center: only the Meeting it named can switch.
            guard let offer = switchOffer, offer.app.bundleID == app, offer.meeting.id == meetingID,
                isLive(meetingID)
            else { return }
            switchOffer = nil
            Task {
                do {
                    try await recorder.switchMeeting(to: offer.app)
                } catch {
                    present(error, title: "Carbon couldn't switch Meetings")
                }
            }
        }
    }

    /// Finishes the Meetings a crash interrupted, from the audio already on disk, and says what happened to each.
    private func recoverInterruptedMeetings() async {
        for recovery in await recorder.recover() {
            switch recovery {
            case .recovered(let title, let file):
                notifier.post(
                    "Recovered “\(title)” after Carbon quit unexpectedly.",
                    meetingID: library.meetings.first { $0.file.standardizedFileURL == file.standardizedFileURL }?.id)
            case .discarded(let title):
                notifier.post("Carbon couldn't read the audio of “\(title)”, so it was discarded.")
            case .failed(let title):
                let meeting = title.map { "“\($0)”" } ?? "a Meeting"
                notifier.post("Carbon couldn't recover \(meeting) and stopped trying.")
            }
        }
    }

    /// Detection runs for the whole launch: a Meeting App holding the mic starts and ends Meetings on its own.
    private func startDetection() async {
        recorder.onDetectionFailure = { [weak self] error in
            DiagnosticLog.shared.write("Detection couldn't start or save a Meeting: \(error.localizedDescription)")
            if case Recorder.Failure.systemAudioRecordingDenied = error {
                self?.present(AppError.systemAudioRecordingDenied, title: "Carbon couldn't start transcribing")
            } else {
                self?.present(error, title: "Carbon couldn't transcribe a Meeting")
            }
        }
        // Detection never prompts: the onboarding asks, and a skipped permission stays skipped until answered.
        // An unasked System Audio Recording would otherwise prompt from the first Meeting's audio tap.
        if !detectionMayCapture {
            DiagnosticLog.shared.write("Detection waits for microphone and System Audio Recording access")
            while !detectionMayCapture { try? await Task.sleep(for: .seconds(1)) }
        }
        await loadMeetingLanguages()
        await recorder.runDetection(SignalSampler())
    }

    func showMainWindow() {
        openMainWindow?()
        NSApp.activate()
    }

    private var detectionMayCapture: Bool {
        MicrophoneSource.isAllowed && SystemAudioRecordingPermission.current() != .notDetermined
    }

    /// The first launch's window, which asks for each permission in turn.
    func showOnboarding() {
        guard let openOnboarding else {
            onboardingPending = true
            return
        }
        onboardingPending = false
        // At launch, a menu bar app isn't active and SwiftUI may not open a window yet: the window would land behind
        // other apps, or not at all. Ask again until it exists, then bring it forward.
        Task {
            for _ in 0..<20 {
                NSApp.activate()
                openOnboarding()
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(Self.onboardingWindowID) == true }),
                    window.isVisible
                {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            DiagnosticLog.shared.write("The onboarding window didn't open")
        }
    }

    static let mainWindowID = "main"
    static let editorWindowID = "editor"
    static let onboardingWindowID = "onboarding"

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

    /// Names a Speaker: only its Turn headers change in the file. Returns false, after telling the person, when it couldn't.
    @discardableResult
    func renameSpeaker(_ meeting: ListedMeeting, label: String, to name: String) -> Bool {
        // Picking an attendee gives their Voice Print the attendee's email.
        let email = meeting.participants.first { $0.name == name }?.email
        do {
            try library.renameSpeaker(meeting.id, label: label, name: name, email: email)
            return true
        } catch {
            present(error, title: "Carbon couldn't name the Speaker")
            return false
        }
    }

    /// "Same Person As": `source` and `target` become one participant of the Meeting, and so do their Voice Prints.
    func mergeParticipant(_ meeting: ListedMeeting, _ source: Participant, into target: Participant) {
        perform("Carbon couldn't merge the participants") {
            try library.mergeParticipant(meeting.id, source, into: target)
        }
    }

    func editParticipant(_ meeting: ListedMeeting, _ participant: Participant, name: String, email: String) {
        perform("Carbon couldn't edit the participant") {
            try library.editParticipant(meeting.id, participant, name: name, email: email)
        }
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

    func perform(_ failureTitle: String, _ action: () throws -> Void) {
        do { try action() } catch { present(error, title: failureTitle) }
    }

    func start() {
        Task {
            do {
                guard await MicrophoneSource.requestAccess() else {
                    throw AppError.microphoneDenied
                }
                try await recorder.start(language: await nextMeetingLanguage())
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
        if case .live(let meeting) = recorder.state { notifier.removeStarted(meeting.id) }
        Task { await recorder.discard() }
    }

    func revealLibrary() {
        try? FileManager.default.createDirectory(at: library.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([library.folder])
    }

    func revealDebugFiles() {
        try? FileManager.default.createDirectory(at: library.debugFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([library.debugFolder])
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
    /// Writes what each Meeting's Transcript was built from to `Library.debugFolder`, off by default.
    static let debugMode = "debugMode"
    static let autoTranscribe = "autoTranscribe"
    /// The person's Ignored Apps, bundle IDs, sorted. Settings › Ignored Apps and the offer's Never edit them.
    static let ignoredApps = "ignoredApps"
    /// The Library folder's path, saved on the first launch and changed by Settings' Change….
    static let libraryFolder = "libraryFolder"
    /// Settings › Languages, a JSON `MeetingLanguages`, with the language the last Meeting was transcribed in.
    static let meetingLanguages = "meetingLanguages"
    /// "Recognize voices", on by default.
    static let recognizeVoices = "recognizeVoices"
    /// "Show app icon in", an `AppIconPlacement`, Dock and Menu Bar by default.
    static let appIconPlacement = "appIconPlacement"
}

enum AppError: LocalizedError {
    case microphoneDenied
    case systemAudioRecordingDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Carbon needs microphone access. Allow it in System Settings › Privacy & Security › Microphone."
        case .systemAudioRecordingDenied:
            "Carbon needs System Audio Recording access to hear the other participants. Allow it in System Settings › Privacy & Security › Screen & System Audio Recording."
        }
    }
}
