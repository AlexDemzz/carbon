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
