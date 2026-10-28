import CarbonCore
import Testing

/// Settings › Permissions and the menu bar menu's "Carbon needs <permission> access…".
struct PermissionsTests {
    @Test func theMenuFlagsEachPermissionThatIsNotAllowedInTheSettingsOrder() {
        let permissions = Permissions(
            microphone: .allowed, systemAudioRecording: .notAllowed, calendar: .notAllowed, notifications: .allowed)

        #expect(permissions.menuWarnings.map(\.title) == [
            "Carbon needs System Audio Recording access\u{2026}",
            "Carbon needs Calendar access\u{2026}",
        ])
    }

    @Test func anUnknownStatusIsNotFlagged() {
        let permissions = Permissions(
            microphone: .allowed, systemAudioRecording: .unknown, calendar: .allowed, notifications: .allowed)

        #expect(permissions.menuWarnings.isEmpty)
    }

    @Test func theSystemAudioRecordingPreflightReadsAsAStatus() {
        #expect(PermissionStatus(SystemAudioPermission.granted) == .allowed)
        #expect(PermissionStatus(SystemAudioPermission.denied) == .notAllowed)
        #expect(PermissionStatus(SystemAudioPermission.notDetermined) == .notAllowed)
        #expect(PermissionStatus(SystemAudioPermission.unknown) == .unknown)
    }
}
