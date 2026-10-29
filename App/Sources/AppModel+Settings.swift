import AppKit
import CarbonCore
import ServiceManagement
import UniformTypeIdentifiers

enum SettingsTab: Hashable {
    case general, languages, ignoredApps, permissions, voicePrints, about
}

extension AppModel {
    // MARK: Library folder

    /// "Change…": picks a folder, says how many files will move, then moves the whole Library there.
    func changeLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = library.folder.deletingLastPathComponent()
        panel.prompt = "Choose"
        panel.message = "Choose the folder for Carbon\u{2019}s Library."
        NSApp.activate()
        guard panel.runModal() == .OK, let destination = panel.url,
            destination.standardizedFileURL != library.folder.standardizedFileURL
        else { return }
        do {
            let count = try library.filesToMove()
            let files = count == 1 ? "1 file" : "\(count) files"
            let alert = NSAlert()
            alert.messageText = "Move the Library to \u{201C}\(destination.lastPathComponent)\u{201D}?"
            alert.informativeText = "Carbon will move \(files) from \(library.folder.path) to \(destination.path)."
            alert.addButton(withTitle: count == 0 ? "Move Library" : "Move \(files.capitalized)")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            stopWatchingLibrary()
            defer { watchLibrary() }
            try library.move(to: destination)
            UserDefaults.standard.set(destination.path, forKey: SettingsKey.libraryFolder)
        } catch {
            present(error, title: "Carbon couldn't move the Library")
        }
    }

    // MARK: Ignored Apps

    /// The person's Ignored Apps, by bundle ID. The vendor table's built-in entries are not listed.
    var ignoredApps: [String] { recorder.ignoredApps.sorted() }

    /// "+": an app picker in /Applications.
    func pickIgnoredApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.prompt = "Ignore"
        panel.message = "Choose the apps Carbon should never transcribe."
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            recorder.ignoredApps.insert(bundleID)
        }
        saveIgnoredApps()
    }

    func removeIgnoredApps(_ bundleIDs: Set<String>) {
        recorder.ignoredApps.subtract(bundleIDs)
        saveIgnoredApps()
    }

    func saveIgnoredApps() {
        UserDefaults.standard.set(ignoredApps, forKey: SettingsKey.ignoredApps)
    }

    // MARK: Launch at login

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchesAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            present(error, title: on ? "Carbon couldn't turn on launch at login" : "Carbon couldn't turn off launch at login")
        }
    }

    // MARK: Permissions

    func refreshPermissions() async {
        let fresh = await PermissionsReader.current()
        // The onboarding rereads every second: an unchanged read redraws nothing.
        if fresh != permissions { permissions = fresh }
    }

    /// The menu's "Carbon needs <permission> access…": Settings, on the Permissions tab.
    func showPermissions(openSettings: () -> Void) {
        settingsTab = .permissions
        NSApp.activate()
        openSettings()
        Task { await refreshPermissions() }
    }

    /// The onboarding's primary action. Never asked, it shows the system prompt, the only way into System Settings'
    /// list; once answered, only System Settings can change it.
    func allow(_ permission: Permission) async {
        guard permissions[permission] == .notAsked else {
            PermissionsReader.openSystemSettings(for: permission)
            return
        }
        NSApp.activate()
        switch permission {
        case .microphone: _ = await MicrophoneSource.requestAccess()
        case .systemAudioRecording: await SystemAudioRecordingPermission.requestAccess()
        case .calendar: await CalendarEvents.requestAccess()
        case .notifications: await notifier.requestAuthorization()
        }
        await refreshPermissions()
    }

    // MARK: About

    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    func revealDiagnosticLog() {
        let file = DiagnosticLog.shared.file
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}
