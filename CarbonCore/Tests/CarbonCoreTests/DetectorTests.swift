import CarbonCore
import Foundation
import Testing

/// The mic rules of "Power assertions as a Detection signal", one test per rule.
struct DetectorTests {
    let chrome = MeetingApp(bundleID: "com.google.Chrome", name: "Google Chrome")
    let t0 = date("2026-10-23T13:00:00Z")

    /// Feeds one snapshot per second from `from` to `to` (seconds after t0), with `holders` on the mic.
    func play(
        _ detector: inout Detector, _ from: Int, _ to: Int, holders: [MeetingApp], lastSound: Int? = nil,
        ignoredApps: Set<String> = []
    ) -> [(Int, Detector.Command)] {
        var commands: [(Int, Detector.Command)] = []
        for second in from...to {
            let signals = Detector.Signals(
                time: t0 + TimeInterval(second), micHolders: holders,
                lastSound: lastSound.map { t0 + TimeInterval($0) }, ignoredApps: ignoredApps)
            commands += detector.observe(signals).map { (second, $0) }
        }
        return commands
    }

    @Test func theMicHeldFor15SecondsStartsAMeetingOnTheAppHoldingIt() {
        var detector = Detector()

        let commands = play(&detector, 0, 30, holders: [chrome])

        #expect(commands.map(\.0) == [15])
        #expect(commands.map(\.1) == [.start(chrome)])
    }

    @Test func theMeetingEndsOnceTheMicIsReleasedAnd10MinutesPassInSilence() {
        var detector = Detector()

        var commands = play(&detector, 0, 300, holders: [chrome], lastSound: 300)
        commands += play(&detector, 301, 1_000, holders: [], lastSound: 300)

        #expect(commands.map(\.0) == [15, 901])
        #expect(commands.map(\.1) == [.start(chrome), .end(.silence)])
    }

    @Test func soundAfterTheReleaseRestartsThe10MinuteCount() {
        var detector = Detector()

        var commands = play(&detector, 0, 300, holders: [chrome], lastSound: 300)
        commands += play(&detector, 301, 500, holders: [], lastSound: 300)
        commands += play(&detector, 501, 1_200, holders: [], lastSound: 500)

        #expect(commands.map(\.0) == [15, 1_100])
        #expect(commands.map(\.1) == [.start(chrome), .end(.silence)])
    }

    @Test func holdingTheMicAgainBefore10MinutesKeepsTheMeetingGoing() {
        var detector = Detector()

        var commands = play(&detector, 0, 300, holders: [chrome])
        commands += play(&detector, 301, 800, holders: [])
        commands += play(&detector, 801, 900, holders: [chrome])
        commands += play(&detector, 901, 1_600, holders: [])

        #expect(commands.map(\.0) == [15, 1_501])
        #expect(commands.map(\.1) == [.start(chrome), .end(.silence)])
    }

    @Test func coreSpeechHoldingTheMicIsNeitherAHoldNorARelease() {
        let coreSpeech = MeetingApp(bundleID: "com.apple.CoreSpeech", name: "CoreSpeech")
        var detector = Detector()

        var commands = play(&detector, 0, 100, holders: [chrome])
        commands += play(&detector, 101, 200, holders: [chrome, coreSpeech])
        commands += play(&detector, 201, 300, holders: [chrome])
        commands += play(&detector, 301, 1_000, holders: [coreSpeech])

        #expect(commands.map(\.0) == [15, 901])
        #expect(commands.map(\.1) == [.start(chrome), .end(.silence)])
    }

    @Test func afterAManualStopTheSameHoldNeverStartsAgain() {
        var detector = Detector()

        var commands = play(&detector, 0, 100, holders: [chrome])
        detector.meetingStopped()
        commands += play(&detector, 101, 2_000, holders: [chrome])

        #expect(commands.map(\.1) == [.start(chrome)], "Manual Stop wins over the mic still held")
    }

    @Test func afterAManualStopANewHoldStartsANewMeeting() {
        var detector = Detector()

        var commands = play(&detector, 0, 100, holders: [chrome])
        detector.meetingStopped()
        commands += play(&detector, 101, 110, holders: [])
        commands += play(&detector, 111, 130, holders: [chrome])

        #expect(commands.map(\.0) == [15, 126])
        #expect(commands.map(\.1) == [.start(chrome), .start(chrome)])
    }

    @Test func aManualStartTakesTheAppHoldingTheMicAndFollowsTheSameStopRules() {
        var detector = Detector()

        var commands = play(&detector, 0, 5, holders: [chrome])
        #expect(detector.meetingStarted(at: t0 + 5, ignoredApps: []) == chrome)
        commands += play(&detector, 6, 300, holders: [chrome], lastSound: 300)
        commands += play(&detector, 301, 1_000, holders: [], lastSound: 300)

        #expect(commands.map(\.0) == [901], "never a second start, then the 10 min silence stop")
        #expect(commands.map(\.1) == [.end(.silence)])
    }

    @Test func aManualStartWithNoAppOnTheMicEndsAfter10MinutesOfSilence() {
        var detector = Detector()

        #expect(detector.meetingStarted(at: t0, ignoredApps: []) == nil)
        var commands = play(&detector, 0, 1_200, holders: [], lastSound: 400)
        commands += play(&detector, 1_201, 1_300, holders: [chrome], lastSound: 400)

        #expect(commands.map(\.0) == [1_000, 1_216])
        #expect(commands.map(\.1) == [.end(.silence), .start(chrome)])
    }

    @Test func holdsBrokenByAReleaseNeverAddUpTo15Seconds() {
        var detector = Detector()

        var commands = play(&detector, 0, 10, holders: [chrome])
        commands += play(&detector, 11, 12, holders: [])
        commands += play(&detector, 13, 26, holders: [chrome])

        #expect(commands.isEmpty)
    }

    @Test(arguments: [
        MeetingApp(bundleID: "com.superduper.superwhisper", name: "superwhisper"),
        MeetingApp(bundleID: "com.loom.desktop", name: "Loom"),
        MeetingApp(bundleID: "com.apple.CoreSpeech", name: "CoreSpeech"),
        MeetingApp(bundleID: Detector.carbonBundleID, name: "Carbon"),
    ])
    func anIgnoredAppHoldingTheMicNeverStartsAMeeting(app: MeetingApp) {
        var detector = Detector()

        #expect(play(&detector, 0, 120, holders: [app]).isEmpty)
    }

    @Test func anAppThePersonIgnoredNeverStartsAMeeting() {
        var detector = Detector()

        #expect(play(&detector, 0, 120, holders: [chrome], ignoredApps: ["com.google.Chrome"]).isEmpty)
    }

    @Test func callAppsOnTheNeverIgnoredListStartEvenWhenThePersonIgnoredThem() {
        let faceTime = MeetingApp(bundleID: "com.apple.avconferenced", name: "avconferenced")
        var detector = Detector()

        let commands = play(&detector, 0, 20, holders: [faceTime], ignoredApps: ["com.apple.avconferenced"])

        #expect(commands.map(\.1) == [.start(faceTime)])
    }

    @Test func anIgnoredAppHoldingTheMicAlongsideACallAppDoesNotDelayIt() {
        let superwhisper = MeetingApp(bundleID: "com.superduper.superwhisper", name: "superwhisper")
        var detector = Detector()

        var commands = play(&detector, 0, 9, holders: [superwhisper])
        commands += play(&detector, 10, 30, holders: [superwhisper, chrome])

        #expect(commands.map(\.0) == [25])
        #expect(commands.map(\.1) == [.start(chrome)])
    }
}

/// The call assertion, back-to-back, cap and overlap rules of "Power assertions as a Detection signal".
struct CallDetectorTests {
    let chrome = MeetingApp(bundleID: "com.google.Chrome", name: "Google Chrome")
    let zoom = MeetingApp(bundleID: "us.zoom.xos", name: "zoom.us")
    let teams = MeetingApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams")
    let t0 = date("2026-10-23T13:00:00Z")

    func zoomCall(_ id: Int = 1) -> PowerAssertion {
        PowerAssertion(app: zoom, name: "Describe Activity Type", type: "PreventUserIdleDisplaySleep", id: id)
    }

    func teamsCall(_ id: Int = 7) -> PowerAssertion {
        PowerAssertion(app: teams, name: "call in progress", type: "PreventUserIdleSystemSleep", id: id)
    }

    /// Feeds one snapshot per second from `from` to `to` (seconds after t0). The assertions are polled on every
    /// second divisible by 3, as the SignalSampler does.
    func play(
        _ detector: inout Detector, _ from: Int, _ to: Int, holders: [MeetingApp] = [],
        assertions: [PowerAssertion] = [], lastSound: Int? = nil
    ) -> [(Int, Detector.Command)] {
        var commands: [(Int, Detector.Command)] = []
        for second in from...to {
            let signals = Detector.Signals(
                time: t0 + TimeInterval(second), micHolders: holders,
                assertions: second % 3 == 0 ? assertions : nil, lastSound: lastSound.map { t0 + TimeInterval($0) })
            commands += detector.observe(signals).map { (second, $0) }
        }
        return commands
    }

    @Test func aCallAssertionOnTwoConsecutivePollsStartsAMeetingWithoutTheMic() {
        var detector = Detector()

        let commands = play(&detector, 1, 10, assertions: [zoomCall()])

        #expect(commands.map(\.0) == [6])
        #expect(commands.map(\.1) == [.start(zoom)])
    }

    @Test func aCallAssertionSeenOnASinglePollStartsNothing() {
        var detector = Detector()

        var commands = play(&detector, 1, 3, assertions: [zoomCall()])
        commands += play(&detector, 4, 30)

        #expect(commands.isEmpty)
    }

    @Test func aBrowserWebRTCAssertionStartsNothing() {
        let webRTC = PowerAssertion(
            app: chrome, name: "WebRTC has active PeerConnections", type: "NoIdleSleepAssertion", id: 3)
        var detector = Detector()

        #expect(play(&detector, 1, 12, holders: [], assertions: [webRTC]).isEmpty)
    }

    @Test func aCallEnds15SecondsAfterTheAssertionAndTheMicAreReleasedThen30SecondsOfSilence() {
        var detector = Detector()

        var commands = play(&detector, 0, 600, holders: [zoom], assertions: [zoomCall()], lastSound: 600)
        commands += play(&detector, 601, 2_000, lastSound: 600)

        #expect(commands.map(\.0) == [3, 648], "the assertion is seen released on the 603 poll")
        #expect(commands.map(\.1) == [.start(zoom), .end(.callEnded)])
    }

    @Test func soundAfterTheCallIsReleasedPushesTheEndBack() {
        var detector = Detector()

        var commands = play(&detector, 0, 600, holders: [zoom], assertions: [zoomCall()], lastSound: 600)
        commands += play(&detector, 601, 2_000, lastSound: 630)

        #expect(commands.map(\.0) == [3, 660])
    }

    @Test func aCallWhoseAssertionStaysDoesNotEndWhenTheMicIsReleased() {
        var detector = Detector()

        var commands = play(&detector, 0, 600, holders: [zoom], assertions: [zoomCall()], lastSound: 600)
        commands += play(&detector, 601, 2_000, assertions: [zoomCall()], lastSound: 600)

        #expect(commands.map(\.1) == [.start(zoom)])
    }

    @Test func aCallWhoseMicStaysHeldDoesNotEndWhenTheAssertionIsReleased() {
        var detector = Detector()

        var commands = play(&detector, 0, 600, holders: [zoom], assertions: [zoomCall()], lastSound: 600)
        commands += play(&detector, 601, 2_000, holders: [zoom], lastSound: 600)

        #expect(commands.map(\.1) == [.start(zoom)])
    }

    @Test func afterAManualStopTheSameCallNeverStartsAgain() {
        var detector = Detector()

        var commands = play(&detector, 0, 100, assertions: [zoomCall()])
        detector.meetingStopped()
        commands += play(&detector, 101, 1_000, assertions: [zoomCall()])
        commands += play(&detector, 1_001, 1_100, assertions: [zoomCall(2)])

        #expect(commands.map(\.0) == [3, 1_005], "only the next call starts, after 2 polls")
    }

    @Test func aNewAssertionIdWhileTheMicStaysHeldSplitsTheMeetingAfterA5SecondCooldown() {
        var detector = Detector()

        var commands = play(&detector, 0, 600, holders: [zoom], assertions: [zoomCall(1)])
        commands += play(&detector, 601, 700, holders: [zoom], assertions: [zoomCall(2)])

        #expect(commands.map(\.0) == [3, 603, 608])
        #expect(commands.map(\.1) == [.start(zoom), .end(.backToBack), .start(zoom)])
    }

    @Test func aCallBackAfterTheMicAndTheAssertionWereReleased5SecondsIsANewMeeting() {
        var detector = Detector()

        var commands = play(&detector, 0, 600, holders: [zoom], assertions: [zoomCall(1)])
        commands += play(&detector, 601, 608)
        commands += play(&detector, 609, 700, holders: [zoom], assertions: [zoomCall(2)])

        #expect(commands.map(\.0) == [3, 609, 614], "released on the 603 poll; the new call waits out the cooldown")
        #expect(commands.map(\.1) == [.start(zoom), .end(.backToBack), .start(zoom)])
    }

    @Test func aReleaseShorterThan5SecondsKeepsTheSameMeeting() {
        var detector = Detector()

        var commands = play(&detector, 0, 600, holders: [zoom], assertions: [zoomCall(1)])
        commands += play(&detector, 601, 604)
        commands += play(&detector, 605, 2_000, holders: [zoom], assertions: [zoomCall(1)])

        #expect(commands.map(\.1) == [.start(zoom)])
    }

    @Test func aMeetingEndsAt4HoursAndStartsAgainWhenTheCallIsStillLive() {
        var detector = Detector()

        let commands = play(&detector, 0, 14_430, holders: [chrome])

        #expect(commands.map(\.0) == [15, 14_415, 14_420])
        #expect(commands.map(\.1) == [.start(chrome), .end(.cap), .start(chrome)])
    }

    @Test func anotherAppsStartSignalDuringAMeetingOffersASwitchOnceAndNeverStartsASecondMeeting() {
        var detector = Detector()

        var commands = play(&detector, 0, 100, holders: [chrome])
        commands += play(&detector, 101, 1_000, holders: [chrome, zoom], assertions: [zoomCall()])

        #expect(commands.map(\.0) == [15, 105])
        #expect(commands.map(\.1) == [.start(chrome), .offerSwitch(zoom)])
    }

    @Test func switchingEndsOnTheOtherAppsRulesAndTheOldHoldNeverStartsAgain() {
        var detector = Detector()

        var commands = play(&detector, 0, 100, holders: [chrome])
        commands += play(&detector, 101, 200, holders: [chrome, zoom], assertions: [zoomCall()])
        detector.meetingSwitched(to: zoom, at: t0 + 200)
        commands += play(&detector, 201, 300, holders: [chrome, zoom], assertions: [zoomCall()])
        commands += play(&detector, 301, 2_000, holders: [chrome])

        #expect(commands.map(\.0) == [15, 105, 348], "Zoom's call rule: released on the 303 poll, + 15 s + 30 s")
        #expect(commands.map(\.1) == [.start(chrome), .offerSwitch(zoom), .end(.callEnded)])
    }

    @Test func anotherAppStartingAfterTheMeetingAppReleased5SecondsTakesOverAsBackToBack() {
        var detector = Detector()

        var commands = play(&detector, 0, 100, holders: [chrome])
        commands += play(&detector, 101, 109)
        commands += play(&detector, 110, 200, holders: [zoom], assertions: [zoomCall()])

        #expect(commands.map(\.0) == [15, 114, 114])
        #expect(commands.map(\.1) == [.start(chrome), .end(.backToBack), .start(zoom)])
    }

    @Test func aManualMeetingWithNoAppOnlyOffersTheSwitch() {
        var detector = Detector()

        _ = detector.meetingStarted(at: t0, ignoredApps: [])
        let commands = play(&detector, 0, 300, holders: [chrome], lastSound: 300)

        #expect(commands.map(\.0) == [15])
        #expect(commands.map(\.1) == [.offerSwitch(chrome)])
    }
}
