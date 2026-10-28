import CarbonCore
import SwiftUI

struct MenuBarGlyph: View {
    let isLive: Bool

    var body: some View {
        Image(isLive ? "MenuBarRecording" : "MenuBarIdle")
            .accessibilityLabel(isLive ? "Carbon, transcribing" : "Carbon")
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
            Button("Stop") { model.stop() }
            Button("Discard") { model.discard() }
        case .finishing(let meeting):
            Text("Finishing \u{201C}\(meeting.title)\u{201D}\u{2026}")
        }
        Divider()
        Button("Show Carbon") { model.showMainWindow() }
            .keyboardShortcut(model.showCarbonShortcut.keyboardShortcut)
        Button("Reveal in Finder") { model.revealLibrary() }
        MeetingLanguageMenu(model: model)
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

/// Meeting Language ▸, with a check on the live Meeting's language, or on the next Meeting's outside one.
private struct MeetingLanguageMenu: View {
    let model: AppModel

    var body: some View {
        Picker(
            "Meeting Language",
            selection: Binding(
                get: { model.menuLanguage?.identifier(.bcp47) ?? "" },
                set: { id in model.chooseMeetingLanguage(Locale(identifier: Locale.identifier(.icu, from: id))) })
        ) {
            ForEach(model.menuLanguages, id: \.self) { language in
                Text(model.languageName(language)).tag(language.identifier(.bcp47))
            }
        }
        .pickerStyle(.menu)
        .disabled(model.menuLanguages.isEmpty || isFinishing)
    }

    private var isFinishing: Bool {
        if case .finishing = model.recorder.state { true } else { false }
    }
}

extension Shortcut {
    /// The menu item's key equivalent, which shows the shortcut next to Show Carbon.
    var keyboardShortcut: KeyboardShortcut {
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(key.lowercased().first ?? "c"), modifiers: modifiers)
    }
}
