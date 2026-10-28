import EventKit
import Foundation
import ServiceManagement

/// The first launch: the system prompts in a row, then launch at login. No window, no onboarding.
enum FirstLaunch {
    private static let doneKey = "firstLaunchDone"

    /// Asks every permission in a row; the system shows a prompt only for the ones not answered yet,
    /// so later launches stay silent. Launch at login is registered once, so turning it off later sticks.
    @MainActor
    static func run(notifier: Notifier) async {
        await notifier.requestAuthorization()
        _ = try? await EKEventStore().requestFullAccessToEvents()
        _ = await MicrophoneSource.requestAccess()
        await SystemAudioRecordingPermission.requestAccess()
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            DiagnosticLog.shared.write("Launch at login not registered: \(error.localizedDescription)")
        }
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
