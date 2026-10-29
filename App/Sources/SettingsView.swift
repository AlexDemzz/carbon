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
            Tab("Voice Prints", systemImage: "waveform", value: .voicePrints) {
                VoicePrintsSettings(model: model)
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
    @AppStorage(SettingsKey.debugMode) private var debugMode = false
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
            Section {
                Toggle("Debug mode", isOn: $debugMode)
                Button("Show debug files in Finder") { model.revealDebugFiles() }
            } footer: {
                Text(
                    "Each new Meeting also gets a debug file, kept out of the Library folder, with every word heard, who it went to and why any was left out. Turn on \u{201C}Keep audio after transcribing\u{201D} to keep the recording too."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchesAtLogin = model.launchesAtLogin }
    }
}

/// The Meeting Languages: a checkbox per language SpeechTranscriber supports, each checked one with its download
/// state, and, with several checked, the one Meetings start in and whether Carbon identifies the one spoken.
private struct LanguagesSettings: View {
    let model: AppModel
    @AppStorage(SettingsKey.identifyMeetingLanguage) private var identifiesMeetingLanguage = true

    var body: some View {
        Form {
            if let languages = model.meetingLanguages {
                if languages.chosen.count > 1 {
                    Section {
                        Picker("Start Meetings in", selection: defaultLanguage) {
                            ForEach(languages.chosen, id: \.self) { language in
                                Text(languages.name(of: language)).tag(language.identifier(.bcp47))
                            }
                        }
                        Toggle("Identify the Meeting Language automatically", isOn: $identifiesMeetingLanguage)
                    } footer: {
                        Text(
                            identifiesMeetingLanguage
                                ? "After a few seconds of speech, Carbon switches to the checked language it hears, on your Mac. If it can\u{2019}t tell, the Meeting stays in the one it started in. Switch by hand from the menu bar or the notification."
                                : "Switch while transcribing from the menu bar or the notification."
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                Section("Languages You Speak in Meetings") {
                    ForEach(model.languageAssets.supported, id: \.self) { language in
                        LanguageRow(model: model, language: language, languages: languages)
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
}

/// A Meeting Language's checkbox and, once checked, its download state. Also the onboarding's Languages step's rows.
struct LanguageRow: View {
    let model: AppModel
    let language: Locale
    let languages: MeetingLanguages

    var body: some View {
        let canUncheck = languages.canUncheck(language)
        HStack {
            Toggle(Locale.current.localizedString(forIdentifier: language.identifier) ?? language.identifier(.bcp47), isOn: isChosen)
                .toggleStyle(.checkbox)
                .disabled(!canUncheck)
                .help(canUncheck ? "" : "At least one language stays checked.")
                .accessibilityHint(canUncheck ? "" : "At least one language stays checked.")
            Spacer()
            if languages.isChosen(language), let state = model.languageAssets.state(of: language) {
                switch state {
                case .downloading:
                    Text("Downloading\u{2026}").foregroundStyle(.secondary)
                case .ready:
                    Text("Ready").foregroundStyle(.secondary)
                case .failed:
                    Label("Couldn\u{2019}t download", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        // One element: "English (United States), Ready", checkbox.
        .accessibilityElement(children: .combine)
    }

    private var isChosen: Binding<Bool> {
        Binding(
            get: { languages.isChosen(language) },
            set: { model.meetingLanguages?.set(language, chosen: $0) })
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
                    case .notAsked:
                        // System Settings lists Carbon only once the system has asked, so a skipped one asks here.
                        HStack {
                            Text("Not allowed").foregroundStyle(.secondary)
                            Button("Allow\u{2026}") { Task { await model.allow(permission) } }
                                .accessibilityLabel("Allow \(permission.name)\u{2026}")
                        }
                    case .denied:
                        HStack {
                            Text("Not allowed").foregroundStyle(.secondary)
                            OpenSystemSettingsButton(permission: permission)
                        }
                    case .unknown:
                        HStack {
                            Text("Unknown").foregroundStyle(.secondary)
                            OpenSystemSettingsButton(permission: permission)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshPermissions() }
    }
}

/// Each row has one, so the accessible name says which permission it opens.
private struct OpenSystemSettingsButton: View {
    let permission: Permission

    var body: some View {
        Button("Open System Settings") { PermissionsReader.openSystemSettings(for: permission) }
            .accessibilityLabel("Open System Settings for \(permission.name)")
    }
}

private struct AboutSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            LabeledContent("Carbon", value: model.version)
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speaker diarization by FluidAudio, with models built into Carbon: Fluid Inference's modified Core ML conversion of pyannote's speaker-diarization-community-1 (pyannote, WeSpeaker, BUT Speech@FIT). Models licensed CC BY 4.0.")
                    Link("FluidAudio models", destination: AboutLinks.fluidAudio)
                    Link("CC BY 4.0 license", destination: AboutLinks.ccBy)
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
    static let ccBy = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    static let privacy = URL(string: "https://carbon.alexandrejoly.me/privacy")!
    static let website = URL(string: "https://carbon.alexandrejoly.me")!
}
