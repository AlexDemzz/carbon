import CarbonCore
import Testing

/// The first-launch onboarding: each step's hint, the Done step's verdict and the Calendar step's account kinds.
struct OnboardingTests {
    static func permissions(
        microphone: PermissionStatus = .allowed, systemAudioRecording: PermissionStatus = .allowed,
        calendar: PermissionStatus = .allowed, notifications: PermissionStatus = .allowed
    ) -> Permissions {
        Permissions(
            microphone: microphone, systemAudioRecording: systemAudioRecording, calendar: calendar,
            notifications: notifications)
    }

    @Test func anAllowedPermissionHasNoHint() {
        #expect(Permission.allCases.allSatisfy { $0.hint(for: .allowed) == nil })
    }

    @Test func neverAskedSaysWhatCarbonGoesWithoutAndFlagsOnlyTheOptionalOnes() {
        #expect(Permission.microphone.hint(for: .notAsked) == "Without it, Carbon can\u{2019}t transcribe any Meeting.")
        #expect(
            Permission.calendar.hint(for: .notAsked)
                == "Optional. Without it, Meetings are named after their Meeting App, with no Participants.")
    }

    @Test func deniedSaysWhatToSwitchOnInSystemSettings() {
        #expect(
            Permission.microphone.hint(for: .denied)
                == "In System Settings, turn on Carbon under Privacy & Security \u{203A} Microphone.")
        #expect(
            Permission.systemAudioRecording.hint(for: .unknown)
                == "Carbon can\u{2019}t check this. In System Settings, turn on Carbon under System Audio Recording Only.")
    }

    @Test func aMissingRequiredPermissionMeansCarbonCantTranscribeEvenWithTheOptionalOnesAllowed() {
        let conclusion = Self.permissions(microphone: .denied, systemAudioRecording: .notAsked).onboardingConclusion

        #expect(conclusion.title == "Carbon Can\u{2019}t Transcribe Yet")
        #expect(conclusion.subtitle == "Allow Microphone and System Audio Recording to transcribe your Meetings.")
    }

    @Test func aRequiredPermissionCarbonCantCheckCountsAsMissing() {
        let conclusion = Self.permissions(systemAudioRecording: .unknown).onboardingConclusion

        #expect(conclusion.subtitle == "Allow System Audio Recording to transcribe your Meetings.")
    }

    @Test func onlyOptionalPermissionsMissingMeansCarbonIsReady() {
        #expect(Self.permissions(calendar: .denied, notifications: .notAsked).onboardingConclusion.title == "Carbon Is Ready")
        #expect(Self.permissions().onboardingConclusion.title == "You\u{2019}re All Set")
    }

    static let calDAVAccounts: [(String, [String], CalendarAccountKind)] = [
        ("iCloud", [], .iCloud),
        ("alex@gmail.com", [], .google),
        ("Google", [], .google),
        ("alex@yoojo.com", ["https://www.google.com/calendar/dav/alex%40yoojo.com/events/"], .google),
        ("alex@fastmail.com", ["0F0E7C5A-1B2C-4D3E-8F90-123456789ABC"], .internetAccount),
    ]

    @Test(arguments: calDAVAccounts)
    func theKindOfACalDAVAccount(title: String, calendarIdentifiers: [String], kind: CalendarAccountKind) {
        #expect(CalendarAccountKind(calDAVTitle: title, calendarIdentifiers: calendarIdentifiers) == kind)
    }

    @Test func theKindIsShownOnlyWhenTheTitleDoesntSayIt() {
        #expect(CalendarAccountKind.iCloud.subtitle(under: "iCloud") == nil)
        #expect(CalendarAccountKind.google.subtitle(under: "alex@gmail.com") == "Google")
    }
}
