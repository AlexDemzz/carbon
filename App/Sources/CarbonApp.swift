import AppKit
import Speech
import SwiftUI

@main
struct CarbonApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()
    @State private var updater = Updater()

    var body: some Scene {
        Window("Carbon", id: AppModel.mainWindowID) {
            MainWindow(model: model)
        }
        .defaultSize(width: 980, height: 640)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        WindowGroup("Edit Meeting", id: AppModel.editorWindowID, for: UUID.self) { $id in
            if let id { EditorWindow(model: model, id: id) }
        }
        .defaultSize(width: 720, height: 640)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarMenu(model: model, updater: updater)
        } label: {
            MenuBarGlyph(isLive: model.isLive)
                .modifier(HandsOpenWindowToModel(model: model))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model, updater: updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SpeechTranscriber.isAvailable else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Carbon can't transcribe on this Mac"
            alert.informativeText = "On-device speech transcription isn't available. Carbon will quit."
            alert.addButton(withTitle: "Quit Carbon")
            NSApp.activate()
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
    }
}

/// Gives the model SwiftUI's `openWindow`, so the global shortcut can show the main window.
private struct HandsOpenWindowToModel: ViewModifier {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            model.openMainWindow = { [openWindow] in openWindow(id: AppModel.mainWindowID) }
            model.openEditor = { [openWindow] id in openWindow(id: AppModel.editorWindowID, value: id) }
        }
    }
}
