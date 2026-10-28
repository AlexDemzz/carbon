/// What Settings › Permissions shows for one permission.
public enum PermissionStatus: Equatable, Sendable {
    case allowed
    /// Denied, or not asked yet: either way Carbon goes without it.
    case notAllowed
    /// The private preflight is missing, so Carbon can't tell.
    case unknown

    public init(_ systemAudio: SystemAudioPermission) {
        self = switch systemAudio {
        case .granted: .allowed
        case .denied, .notDetermined: .notAllowed
        case .unknown: .unknown
        }
    }
}

public enum Permission: CaseIterable, Sendable {
    case microphone, systemAudioRecording, calendar, notifications

    public var name: String {
        switch self {
        case .microphone: "Microphone"
        case .systemAudioRecording: "System Audio Recording"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        }
    }

    /// The menu bar menu's item for a missing permission.
    public var title: String { "Carbon needs \(name) access\u{2026}" }
}

/// The four permissions Carbon asks for at first launch, in the order Settings › Permissions lists them.
public struct Permissions: Equatable, Sendable {
    public var microphone: PermissionStatus
    public var systemAudioRecording: PermissionStatus
    public var calendar: PermissionStatus
    public var notifications: PermissionStatus

    public init(
        microphone: PermissionStatus, systemAudioRecording: PermissionStatus, calendar: PermissionStatus,
        notifications: PermissionStatus
    ) {
        self.microphone = microphone
        self.systemAudioRecording = systemAudioRecording
        self.calendar = calendar
        self.notifications = notifications
    }

    public subscript(permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone: microphone
        case .systemAudioRecording: systemAudioRecording
        case .calendar: calendar
        case .notifications: notifications
        }
    }

    /// The permissions to flag at the top of the menu bar menu. An unknown status is not flagged.
    public var menuWarnings: [Permission] {
        Permission.allCases.filter { self[$0] == .notAllowed }
    }
}
