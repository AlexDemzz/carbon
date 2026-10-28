import AVFAudio
import AppKit
import CarbonCore
import EventKit
import UserNotifications

/// Reads the four permissions without prompting, and opens their System Settings pane.
enum PermissionsReader {
    static func current() async -> Permissions {
        let notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return Permissions(
            microphone: AVAudioApplication.shared.recordPermission == .granted ? .allowed : .notAllowed,
            systemAudioRecording: PermissionStatus(SystemAudioRecordingPermission.current()),
            calendar: EKEventStore.authorizationStatus(for: .event) == .fullAccess ? .allowed : .notAllowed,
            notifications: [.authorized, .provisional].contains(notifications) ? .allowed : .notAllowed)
    }

    static func openSystemSettings(for permission: Permission) {
        let pane = switch permission {
        case .microphone: "com.apple.preference.security?Privacy_Microphone"
        case .systemAudioRecording: "com.apple.preference.security?Privacy_AudioCapture"
        case .calendar: "com.apple.preference.security?Privacy_Calendars"
        case .notifications: "com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")"
        }
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
