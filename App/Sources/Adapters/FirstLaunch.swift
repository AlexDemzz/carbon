import Foundation
import ServiceManagement

/// The first launch: launch at login, then the onboarding window, which asks for each permission in turn.
/// Later launches stay silent, even about the permissions skipped: the menu bar menu and Settings › Permissions
/// show what's missing.
enum FirstLaunch {
    private static let doneKey = "firstLaunchDone"

    /// Registers launch at login once, so turning it off later sticks. True on the very first launch only.
    static func run() -> Bool {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return false }
        do {
            try SMAppService.mainApp.register()
        } catch {
            DiagnosticLog.shared.write("Launch at login not registered: \(error.localizedDescription)")
        }
        UserDefaults.standard.set(true, forKey: doneKey)
        return true
    }
}
