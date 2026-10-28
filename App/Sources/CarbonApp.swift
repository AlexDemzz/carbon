import AppKit
import Speech
import SwiftUI

@main
struct CarbonApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()
    @State private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(model: model, updater: updater)
        } label: {
            MenuBarGlyph(isLive: model.isLive)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(updater: updater)
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
