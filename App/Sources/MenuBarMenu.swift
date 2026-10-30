import CarbonCore
import SwiftUI

/// The menu bar icon, followed while transcribing by the Meeting Language's badge, "FR".
struct MenuBarGlyph: View {
    let isLive: Bool
    let language: (badge: String, name: String)?

    var body: some View {
        HStack(spacing: 4) {
            Image(isLive ? "MenuBarRecording" : "MenuBarIdle")
            if let language { Text(language.badge) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard isLive else { return "Carbon" }
        return language.map { "Carbon, transcribing in \($0.name)" } ?? "Carbon, transcribing"
    }
}

struct MenuBarMenu: View {
    let model: AppModel
    let updater: Updater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !model.permissions.menuWarnings.isEmpty {
            ForEach(model.permissions.menuWarnings, id: \.self) { permission in
                Button(permission.title) { model.showPermissions(openSettings: { openSettings() }) }
            }
            Divider()
        }
        switch model.recorder.state {
        case .idle:
            Button("Start Transcribing") { model.start() }
        case .live(let meeting):
            Text("Transcribing \u{201C}\(meeting.title)\u{201D}")
            if meeting.app != nil {
                Text("\(meeting.provider) \u{00B7} since \(meeting.start.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("since \(meeting.start.formatted(date: .omitted, time: .shortened))")
            }
            if model.liveMeetingLanguages(meeting).count > 1 {
                LiveMeetingLanguageMenu(model: model, meeting: meeting)
            }
            Button("Stop") { model.stop() }
            Button("Discard") { model.discard() }
        case .finishing(let meeting):
            Text("Finishing \u{201C}\(meeting.title)\u{201D}\u{2026}")
        }
        Divider()
        Button("Show Carbon") { model.showMainWindow() }
        Button("Reveal in Finder") { model.revealLibrary() }
        Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
        Button("Settings\u{2026}") {
            model.settingsTab = .general
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Carbon") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Meeting Language ▸ while transcribing, with a check on the live Meeting's: picking another re-transcribes it.
private struct LiveMeetingLanguageMenu: View {
    let model: AppModel
    let meeting: LiveMeeting

    var body: some View {
        Menu("Meeting Language") {
            Picker(
                "Meeting Language",
                selection: Binding(
                    get: { meeting.language.identifier(.bcp47) },
                    set: { id in model.switchLanguage(to: Locale(identifier: Locale.identifier(.icu, from: id))) })
            ) {
                ForEach(model.liveMeetingLanguages(meeting), id: \.self) { language in
                    Text(model.languageName(language)).tag(language.identifier(.bcp47))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}
