import CarbonCore
import Testing

/// Settings › Permissions and the menu bar menu's "Carbon needs <permission> access…".
struct PermissionsTests {
    @Test func theMenuFlagsEachPermissionThatIsNotAllowedInTheSettingsOrder() {
        let permissions = Permissions(
            microphone: .allowed, systemAudioRecording: .denied, calendar: .notAsked, notifications: .allowed)

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
}
