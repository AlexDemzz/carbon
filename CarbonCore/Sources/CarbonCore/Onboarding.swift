import Foundation

/// The first-launch onboarding's copy: a step per permission, then a Done step that says whether Carbon can transcribe.
extension Permission {
    /// Without these two, Carbon can't transcribe both sides of a Meeting.
    public var isRequired: Bool { self == .microphone || self == .systemAudioRecording }

    public var stepTitle: String {
        switch self {
        case .microphone: "Hear You"
        case .systemAudioRecording: "Hear the Others"
        case .calendar: "Name Your Meetings"
        case .notifications: "Know When Carbon Transcribes"
        }
    }

    public var reason: String {
        switch self {
        case .microphone: "Transcribes your side of a Meeting as Me."
        case .systemAudioRecording: "Transcribes everyone else on the call from its audio."
        case .calendar: "Names each Meeting and lists its Participants from the matching event."
        case .notifications:
            "Tells you when Carbon starts transcribing a Meeting, with Stop to discard it, and when its Transcript is ready."
        }
    }

    private var without: String {
        switch self {
        case .microphone: "Without it, Carbon can\u{2019}t transcribe any Meeting."
        case .systemAudioRecording: "Without it, the Transcript only has your side of the call."
        case .calendar: "Without it, Meetings are named after their Meeting App, with no Participants."
        case .notifications:
            "Without them, only the red dot in the menu bar shows Carbon is transcribing, and with automatic transcription off, Carbon can\u{2019}t offer you Meetings."
        }
    }

    /// What to switch on once the deep link lands in System Settings.
    private var fix: String {
        switch self {
        case .microphone: "In System Settings, turn on Carbon under Privacy & Security \u{203A} Microphone."
        case .systemAudioRecording: "In System Settings, turn on Carbon under System Audio Recording Only."
        case .calendar: "In System Settings, set Carbon to Full Access under Privacy & Security \u{203A} Calendars."
        case .notifications: "In System Settings, turn on Allow Notifications for Carbon."
        }
    }

    /// The line under a step or a Done row: what Carbon goes without while never asked, what to switch on once denied.
    public func hint(for status: PermissionStatus) -> String? {
        switch status {
        case .allowed: nil
        case .notAsked: isRequired ? without : "Optional. \(without)"
        case .denied: fix
        case .unknown: "Carbon can\u{2019}t check this. \(fix)"
        }
    }
}

extension Permissions {
    /// The Done step's title and subtitle: whether Carbon can transcribe at all, not how many permissions are allowed.
    /// A Required permission Carbon can't check counts as missing.
    public var onboardingConclusion: (title: String, subtitle: String) {
        let missingRequired = Permission.allCases.filter { $0.isRequired && self[$0] != .allowed }
        guard missingRequired.isEmpty else {
            let names = missingRequired.map(\.name).formatted(.list(type: .and).locale(Locale(identifier: "en_US")))
            return ("Carbon Can\u{2019}t Transcribe Yet", "Allow \(names) to transcribe your Meetings.")
        }
        let title = Permission.allCases.allSatisfy { self[$0] == .allowed } ? "You\u{2019}re All Set" : "Carbon Is Ready"
        return (
            title,
            "Carbon waits in the menu bar and starts transcribing on its own when a Meeting starts. Change these anytime in Settings \u{203A} Permissions."
        )
    }
}

/// What kind of account a calendar source in Apple Calendar is, shown under its title on the onboarding's Calendar step.
public enum CalendarAccountKind: Equatable, Sendable {
    case onMyMac, exchange, iCloud, google, internetAccount, subscribed, birthdays, other

    /// Google accounts reach EventKit as CalDAV sources titled with their address, so "CalDAV" would hide them.
    public init(calDAVTitle title: String, calendarIdentifiers: [String]) {
        let lowercased = title.lowercased()
        self =
            if title == "iCloud" {
                .iCloud
            } else if lowercased.contains("google") || lowercased.hasSuffix("@gmail.com")
                || calendarIdentifiers.contains(where: { $0.contains("google") })
            {
                .google
            } else {
                .internetAccount
            }
    }

    public var name: String {
        switch self {
        case .onMyMac: "On My Mac"
        case .exchange: "Exchange"
        case .iCloud: "iCloud"
        case .google: "Google"
        case .internetAccount: "Internet Account"
        case .subscribed: "Subscribed"
        case .birthdays: "Birthdays"
        case .other: "Other"
        }
    }

    /// The kind under an account's title, unless the title already says it, as an account titled "iCloud" does.
    public func subtitle(under title: String) -> String? {
        title.localizedCaseInsensitiveContains(name) ? nil : name
    }
}
