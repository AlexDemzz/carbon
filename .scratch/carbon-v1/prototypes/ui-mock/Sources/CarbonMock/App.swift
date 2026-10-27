// PROTOTYPE, throwaway. The split main window behind one real menu bar item,
// real notifications, a Settings window and an "Edit in New Window" editor. See README.md.
import AppKit
import SwiftUI

@main
struct CarbonMockApp: App {
    @State private var store = Store()

    var body: some Scene {
        Window("Carbon", id: "main") {
            MainWindow().environment(store)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 640)
        .defaultLaunchBehavior(.presented)

        MenuBarExtra {
            MenuBarMenu().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }

        WindowGroup("Transcript", id: "editor", for: Meeting.ID.self) { $id in
            if let id, let meeting = store.binding(id) {
                EditorWindow(meeting: meeting).environment(store)
            }
        }
        .defaultSize(width: 720, height: 760)

        Settings {
            SettingsView().environment(store)
        }
    }
}

enum MenuBarGlyph {
    static let idle: NSImage = {
        let url = Bundle.main.url(forResource: "menubar-idle", withExtension: "svg")!
        let image = NSImage(contentsOf: url)!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    /// Non-template so the dot can be red; strokes follow the menu bar's label color at draw time.
    static let recording: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            idle.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 9 - 1.9, y: 10.025 - 1.9, width: 3.8, height: 3.8)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }()
}

/// Also opens the main window once at launch, so the prototype shows something without hunting for the icon.
struct MenuBarLabel: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var launched = false

    var body: some View {
        Image(nsImage: store.live == nil ? MenuBarGlyph.idle : MenuBarGlyph.recording)
            .task {
                guard !launched else { return }
                launched = true
                openWindow(id: "main")
                NSApp.activate()
            }
    }
}

struct MenuBarMenu: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let live = store.liveMeeting {
            Text("Transcribing \u{201C}\(live.title)\u{201D}")
            Text("\(live.provider) · since \(store.liveStart?.formatted(date: .omitted, time: .shortened) ?? "")")
            Button("Stop and Discard") { store.stopAndDiscard() }
            Divider()
        }
        if store.live == nil {
            Button("Start Transcribing") { store.startTranscribing(language: store.defaultLanguage) }
            Divider()
        }
        Button("Show Carbon") { show() }
            .keyboardShortcut("c", modifiers: [.option, .command])
        Button("Reveal in Finder") { store.revealInFinder() }
        Menu(store.live == nil ? "Meeting Language" : "Transcribing In") {
            ForEach(store.meetingLanguages, id: \.self) { language in
                Toggle(language, isOn: Binding(
                    get: { (store.liveMeeting?.language ?? store.defaultLanguage) == language },
                    set: { _ in store.switchLanguage(language) }))
            }
        }
        Divider()
        Button("Check for Updates…") {}
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Menu("Prototype") {
            Button("Simulate Meeting Detected") { store.detectMeeting() }.disabled(store.live != nil)
            Button("Simulate Meeting Ended (auto-stop)") { store.endMeeting() }.disabled(store.live == nil)
            Toggle("Auto-transcribe", isOn: Bindable(store).autoTranscribe)
        }
        Button("Quit Carbon") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct MainWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        SplitWindow()
        .frame(minWidth: 700, minHeight: 420)
    }
}

