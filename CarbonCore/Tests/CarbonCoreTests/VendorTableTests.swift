import CarbonCore
import Foundation
import Testing

/// The call-assertion matchers of the shipped vendor table, from "Power assertions as a Detection signal" §4.
struct VendorTableTests {
    static let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")
    static let teams = MeetingApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams")
    static let webex = MeetingApp(bundleID: "Cisco-Systems.Spark", name: "Webex")
    static let chrome = MeetingApp(bundleID: "com.google.Chrome", name: "Google Chrome")
    static let slack = MeetingApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")

    static func assertion(_ app: MeetingApp, _ name: String, _ type: String) -> PowerAssertion {
        PowerAssertion(app: app, name: name, type: type, id: 1)
    }

    @Test(arguments: [
        assertion(zoom, "Describe Activity Type", "PreventUserIdleDisplaySleep"),
        assertion(zoom, "Describe Activity Type", "NoDisplaySleepAssertion"),
        assertion(teams, "call in progress", "PreventUserIdleSystemSleep"),
        assertion(teams, "call in progress", "NoIdleSleepAssertion"),
        assertion(webex, "On a call", "PreventUserIdleDisplaySleep"),
        assertion(webex, "On a call", "NoDisplaySleepAssertion"),
    ])
    func nativeCallAssertionsAreCalls(assertion: PowerAssertion) {
        #expect(VendorTable.shipped.kind(of: assertion) == .call)
    }

    @Test(arguments: [
        assertion(chrome, "WebRTC has active PeerConnections", "NoIdleSleepAssertion"),
        assertion(slack, "WebRTC has active PeerConnections", "PreventUserIdleSystemSleep"),
    ])
    func chromiumPeerConnectionsAreWebRTC(assertion: PowerAssertion) {
        #expect(VendorTable.shipped.kind(of: assertion) == .webRTC)
    }

    @Test(arguments: [
        assertion(teams, "Video Wake Lock", "NoDisplaySleepAssertion"),
        assertion(webex, "io avilable", "PreventUserIdleSystemSleep"),
        assertion(zoom, "Zoom background task", "PreventUserIdleSystemSleep"),
        assertion(chrome, "Video Wake Lock", "NoDisplaySleepAssertion"),
        assertion(MeetingApp(bundleID: "com.example.notes", name: "Notes"), "call in progress", "NoIdleSleepAssertion"),
    ])
    func otherAssertionsAreNothing(assertion: PowerAssertion) {
        #expect(VendorTable.shipped.kind(of: assertion) == nil)
    }
}
