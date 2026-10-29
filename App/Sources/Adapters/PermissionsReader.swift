import AVFAudio
import AppKit
import CarbonCore
import EventKit
import UserNotifications

/// Reads the four permissions without prompting, and opens their System Settings pane.
enum PermissionsReader {
    static func current() async -> Permissions {
        let notifications: PermissionStatus =
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        let microphone: PermissionStatus =
            switch AVAudioApplication.shared.recordPermission {
            case .granted: .allowed
            case .undetermined: .notAsked
            default: .denied
            }
        let calendar: PermissionStatus =
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: .allowed
            case .notDetermined: .notAsked
            default: .denied
            }
        return Permissions(
            microphone: microphone, systemAudioRecording: PermissionStatus(SystemAudioRecordingPermission.current()),
            calendar: calendar, notifications: notifications)
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
