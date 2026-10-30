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

        Window("Welcome to Carbon", id: AppModel.onboardingWindowID) {
            OnboardingWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
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
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowDidBecomeMain), name: NSWindow.didBecomeMainNotification, object: nil)
        center.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: nil)
    }

    /// Carbon is a menu bar app (LSUIElement); it joins the Dock only while one of its windows is open.
    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing.canBecomeMain else { return }
        let othersOpen = NSApp.windows.contains {
            $0 !== closing && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
        }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
    }
}

/// Gives the model SwiftUI's `openWindow`, so the global shortcut can show the main window and the first launch
/// the onboarding.
private struct HandsOpenWindowToModel: ViewModifier {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            model.openMainWindow = { [openWindow] in openWindow(id: AppModel.mainWindowID) }
            model.openEditor = { [openWindow] id in openWindow(id: AppModel.editorWindowID, value: id) }
            model.openOnboarding = { [openWindow] in openWindow(id: AppModel.onboardingWindowID) }
            if ProcessInfo.processInfo.environment["CARBON_DEBUG_SEL"] != nil { model.showMainWindow() } // [DEBUG-sel4]
        }
    }
}
