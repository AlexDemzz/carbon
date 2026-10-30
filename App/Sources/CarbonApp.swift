import CarbonCore
import AppKit
import Speech
import SwiftUI

@main
struct CarbonApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()
    @State private var updater = Updater()
    @AppStorage(SettingsKey.appIconPlacement) private var appIconPlacement = AppIconPlacement.dockAndMenuBar

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

        MenuBarExtra(isInserted: .constant(appIconPlacement.showsInMenuBar)) {
            MenuBarMenu(model: model, updater: updater)
        } label: {
            MenuBarGlyph(isLive: model.isLive, language: model.liveMeetingLanguage)
                .modifier(HandsOpenWindowToModel(model: model))
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: appIconPlacement, initial: true) {
            delegate.model = model
            delegate.updateActivationPolicy()
        }

        Settings {
            SettingsView(model: model, updater: updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

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

    /// Carbon launches as a menu bar app (LSUIElement). It joins the Dock unless "Show app icon in" says Menu Bar
    /// Only, and then only while one of its windows is open.
    func updateActivationPolicy(closing: NSWindow? = nil) {
        let windowOpen = NSApp.windows.contains {
            $0 !== closing && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
        }
        NSApp.setActivationPolicy(AppIconPlacement.current.showsInDock || windowOpen ? .regular : .accessory)
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing.canBecomeMain else { return }
        updateActivationPolicy(closing: closing)
    }

    /// A click on the Dock icon with no window open shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { model?.showMainWindow() }
        return true
    }

    /// With Dock Only there's no menu bar menu: the Dock icon's menu starts and stops transcribing.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let model else { return nil }
        let menu = NSMenu()
        switch model.recorder.state {
        case .idle:
            menu.addItem(ActionMenuItem("Start Transcribing") { model.start() })
        case .live(let meeting):
            if model.liveMeetingLanguages(meeting).count > 1 {
                menu.addItem(Self.meetingLanguageItem(meeting, model: model))
            }
            menu.addItem(ActionMenuItem("Stop") { model.stop() })
            menu.addItem(ActionMenuItem("Discard") { model.discard() })
        case .finishing:
            return nil
        }
        return menu
    }

    /// Meeting Language ▸ with a check on the live Meeting's, as in the menu bar menu.
    @MainActor private static func meetingLanguageItem(_ meeting: LiveMeeting, model: AppModel) -> NSMenuItem {
        let submenu = NSMenu()
        for language in model.liveMeetingLanguages(meeting) {
            let item = ActionMenuItem(model.languageName(language)) { model.switchLanguage(to: language) }
            item.state = language.identifier(.bcp47) == meeting.language.identifier(.bcp47) ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Meeting Language", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(choose), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func choose() { run() }
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
        }
    }
}
