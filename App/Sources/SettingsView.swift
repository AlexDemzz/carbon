import CarbonCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let updater: Updater

    var body: some View {
        TabView(selection: $model.settingsTab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralSettings(model: model, updater: updater)
            }
            Tab("Languages", systemImage: "globe", value: .languages) {
                LanguagesSettings(model: model)
            }
            Tab("Ignored Apps", systemImage: "nosign", value: .ignoredApps) {
                IgnoredAppsSettings(model: model)
            }
            Tab("Permissions", systemImage: "hand.raised", value: .permissions) {
                PermissionsSettings(model: model)
            }
            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                AboutSettings(model: model)
            }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @Bindable var updater: Updater
    @AppStorage(SettingsKey.keepAudio) private var keepAudio = false
    @State private var launchesAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Transcribe Meetings automatically", isOn: $model.autoTranscribe)
            } footer: {
                Text(
                    "Carbon shows a notification and a red dot whenever it transcribes. You\u{2019}re responsible for telling others they\u{2019}re being recorded."
                )
                .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Keep audio after transcribing", isOn: $keepAudio)
                LabeledContent("Library folder") {
                    HStack {
                        Text(model.library.folder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(model.library.folder.path(percentEncoded: false))
                        Button("Change\u{2026}") { model.changeLibraryFolder() }
                            .disabled(model.recorder.state != .idle)
                    }
                }
                LabeledContent("Show Carbon") {
                    ShortcutRecorder(shortcut: $model.showCarbonShortcut)
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, on in
                        guard on != model.launchesAtLogin else { return }
                        model.setLaunchesAtLogin(on)
                        launchesAtLogin = model.launchesAtLogin
                    }
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchesAtLogin = model.launchesAtLogin }
    }
}

/// The Meeting Languages: a checkbox per language SpeechTranscriber supports, each checked one with its download
/// state, and the default among the checked ones.
private struct LanguagesSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            if let languages = model.meetingLanguages {
                Section {
                    Picker("Default language", selection: defaultLanguage) {
                        ForEach(languages.chosen, id: \.self) { language in
                            Text(languages.name(of: language)).tag(language.identifier(.bcp47))
                        }
                    }
                } footer: {
                    Text("Meetings start in the default language. Switch while transcribing from the menu bar or the notification.")
                        .foregroundStyle(.secondary)
                }
                Section("Meeting Languages") {
                    ForEach(model.languageAssets.supported, id: \.self) { language in
                        LanguageRow(
                            name: Locale.current.localizedString(forIdentifier: language.identifier)
                                ?? language.identifier(.bcp47),
                            isChosen: chosen(language),
                            canUncheck: languages.canUncheck(language),
                            state: model.languageAssets.state(of: language))
                    }
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task {
            if model.languageAssets.supported.isEmpty { await model.languageAssets.loadSupported() }
        }
    }

    private var defaultLanguage: Binding<String> {
        Binding(
            get: { model.meetingLanguages?.defaultLanguage.identifier(.bcp47) ?? "" },
            set: { model.meetingLanguages?.defaultLanguage = Locale(identifier: Locale.identifier(.icu, from: $0)) })
    }

    private func chosen(_ language: Locale) -> Binding<Bool> {
        Binding(
            get: { model.meetingLanguages?.isChosen(language) ?? false },
            set: { model.meetingLanguages?.set(language, chosen: $0) })
    }
}

private struct LanguageRow: View {
    let name: String
    @Binding var isChosen: Bool
    let canUncheck: Bool
    let state: MeetingLanguageAssets.State?

    var body: some View {
        HStack {
            Toggle(name, isOn: $isChosen)
                .toggleStyle(.checkbox)
                .disabled(!canUncheck)
            Spacer()
            if isChosen, let state {
                switch state {
                case .downloading:
                    Text("Downloading\u{2026}").foregroundStyle(.secondary)
                case .ready:
                    Text("Ready").foregroundStyle(.secondary)
                case .failed:
                    Text("Couldn\u{2019}t download").foregroundStyle(.red)
                }
            }
        }
    }
}

private struct IgnoredAppsSettings: View {
    let model: AppModel
    @State private var selection: Set<String> = []

    var body: some View {
        Form {
            Section {
                List(model.ignoredApps, id: \.self, selection: $selection) { bundleID in
                    IgnoredAppRow(bundleID: bundleID)
                }
                .frame(minHeight: 180)
                .overlay {
                    if model.ignoredApps.isEmpty {
                        Text("No Ignored Apps").foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 0) {
                    Button("Add App", systemImage: "plus") { model.pickIgnoredApps() }
                    Button("Remove App", systemImage: "minus") {
                        model.removeIgnoredApps(selection)
                        selection = []
                    }
                    .disabled(selection.isEmpty)
                    Spacer()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            } footer: {
                Text("Carbon also ignores dictation apps, screen recorders and voice assistants it knows.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacing(/\.app$/, with: "") } ?? bundleID)
        }
    }
}

private struct PermissionsSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            ForEach(Permission.allCases, id: \.self) { permission in
                LabeledContent(permission.name) {
                    switch model.permissions[permission] {
                    case .allowed:
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .notAllowed:
                        HStack {
                            Text("Not allowed").foregroundStyle(.secondary)
                            Button("Open System Settings") { PermissionsReader.openSystemSettings(for: permission) }
                        }
                    case .unknown:
                        HStack {
                            Text("Unknown").foregroundStyle(.secondary)
                            Button("Open System Settings") { PermissionsReader.openSystemSettings(for: permission) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshPermissions() }
    }
}

private struct AboutSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            LabeledContent("Carbon", value: model.version)
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speaker diarization by FluidAudio. Models licensed CC BY 4.0.")
                    Link("FluidAudio models and license", destination: AboutLinks.fluidAudio)
                }
            }
            Section {
                Link("Privacy", destination: AboutLinks.privacy)
                Link("carbon.alexandrejoly.me", destination: AboutLinks.website)
                Button("Reveal Diagnostic Log") { model.revealDiagnosticLog() }
            }
        }
        .formStyle(.grouped)
    }
}

private enum AboutLinks {
    static let fluidAudio = URL(string: "https://huggingface.co/FluidInference/speaker-diarization-coreml")!
    static let privacy = URL(string: "https://carbon.alexandrejoly.me/privacy")!
    static let website = URL(string: "https://carbon.alexandrejoly.me")!
}

/// Click, then press the new shortcut. Escape cancels; a key without ⌘, ⌃ or ⌥ is refused with a beep.
private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var monitor: Any?

    var body: some View {
        Button(monitor == nil ? shortcut.description : "Type Shortcut\u{2026}") {
            monitor == nil ? startRecording() : stopRecording()
        }
        .monospaced()
        .accessibilityLabel("Show Carbon shortcut")
        .accessibilityValue(monitor == nil ? shortcut.description : "Recording")
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Escape
                stopRecording()
                return nil
            }
            var modifiers: Shortcut.Modifiers = []
            let flags = event.modifierFlags
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.command) { modifiers.insert(.command) }
            guard let key = event.charactersIgnoringModifiers, !key.isEmpty,
                let recorded = Shortcut(keyCode: Int(event.keyCode), key: key, modifiers: modifiers)
            else {
                NSSound.beep()
                return nil
            }
            shortcut = recorded
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
