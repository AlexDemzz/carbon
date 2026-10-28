import CarbonCore
import Foundation
import Testing

/// The Event rules of "Power assertions as a Detection signal": the stop rule with an Event and back-to-back calls.
struct DetectorEventTests {
    let chrome = MeetingApp(bundleID: "com.google.Chrome", name: "Google Chrome")
    let t0 = date("2026-10-23T13:00:00Z")
    /// 13:00–13:30.
    let sync = CalendarEvent(
        id: "sync", title: "Weekly sync", start: date("2026-10-23T13:00:00Z"), end: date("2026-10-23T13:30:00Z"),
        notes: "https://meet.google.com/abc-defg-hij")
    /// 13:30–14:00.
    let review = CalendarEvent(
        id: "review", title: "Design review", start: date("2026-10-23T13:30:00Z"), end: date("2026-10-23T14:00:00Z"),
        notes: "https://meet.google.com/xyz-abcd-efg")

    /// Feeds one snapshot per second from `from` to `to` (seconds after t0).
    func play(
        _ detector: inout Detector, _ from: Int, _ to: Int, holders: [MeetingApp], lastSound: Int? = nil,
        events: [CalendarEvent]
    ) -> [(Int, Detector.Command)] {
        var commands: [(Int, Detector.Command)] = []
        for second in from...to {
            let signals = Detector.Signals(
                time: t0 + TimeInterval(second), micHolders: holders,
                lastSound: lastSound.map { t0 + TimeInterval($0) }, events: events)
            commands += detector.observe(signals).map { (second, $0) }
        }
        return commands
    }

    @Test func aMeetingStartsWithTheEventInItsWindow() {
        var detector = Detector()

        let commands = play(&detector, 0, 20, holders: [chrome], events: [sync])

        #expect(commands.map(\.1) == [.start(chrome, event: sync)])
    }

    @Test func anEventAloneNeverStartsAMeeting() {
        var detector = Detector()

        #expect(play(&detector, 0, 600, holders: [], events: [sync]).isEmpty)
    }

    @Test func withAnEventTheMeetingEndsOnceTheMicIsReleased30SecondsInSilenceAndTheEventIsOver() {
        var detector = Detector()

        var commands = play(&detector, 0, 1_500, holders: [chrome], lastSound: 1_500, events: [sync])
        commands += play(&detector, 1_501, 2_000, holders: [], lastSound: 1_500, events: [sync])

        #expect(commands.map(\.0) == [15, 1_800], "released at 13:25, the Event ends at 13:30")
        #expect(commands.map(\.1) == [.start(chrome, event: sync), .end(.silence)])
    }

    @Test func leavingAfterTheEventEndedTakes30SecondsOfSilence() {
        var detector = Detector()

        var commands = play(&detector, 0, 1_900, holders: [chrome], lastSound: 1_900, events: [sync])
        commands += play(&detector, 1_901, 2_000, holders: [], lastSound: 1_900, events: [sync])

        #expect(commands.map(\.0) == [15, 1_931])
    }

    @Test func aBriefDropAfterTheEventDoesNotSplitTheMeeting() {
        var detector = Detector()

        var commands = play(&detector, 0, 1_900, holders: [chrome], lastSound: 1_900, events: [sync])
        commands += play(&detector, 1_901, 1_920, holders: [], lastSound: 1_900, events: [sync])
        commands += play(&detector, 1_921, 2_000, holders: [chrome], lastSound: 2_000, events: [sync])

        #expect(commands.map(\.1) == [.start(chrome, event: sync)])
    }

    @Test func leavingWhileTheEventRunsOnStillEndsAfter10MinutesOfSilence() {
        var detector = Detector()

        var commands = play(&detector, 0, 300, holders: [chrome], lastSound: 300, events: [sync])
        commands += play(&detector, 301, 1_000, holders: [], lastSound: 300, events: [sync])

        #expect(commands.map(\.0) == [15, 901])
    }

    @Test func backToBackEventsOnAHeldMicSplitTheMeetingAfterA5SecondCooldown() {
        var detector = Detector()

        let commands = play(&detector, 0, 2_000, holders: [chrome], lastSound: 2_000, events: [sync, review])

        #expect(commands.map(\.0) == [15, 1_800, 1_805])
        #expect(commands.map(\.1) == [
            .start(chrome, event: sync), .end(.backToBack), .start(chrome, event: review),
        ])
    }

    @Test func aHoldThatBeganLessThan10MinutesBeforeTheNextEventBelongsToIt() {
        var detector = Detector()

        var commands = play(&detector, 0, 1_319, holders: [], events: [sync, review])
        commands += play(&detector, 1_320, 2_000, holders: [chrome], lastSound: 2_000, events: [sync, review])

        #expect(commands.map(\.0) == [1_335, 1_800], "held from 13:22, 8 min before Design review")
        #expect(commands.map(\.1) == [.start(chrome, event: sync), .event(review)])
    }

    @Test func aManualStartTakesTheEventInItsWindow() {
        var detector = Detector()

        _ = play(&detector, 0, 5, holders: [chrome], events: [sync])
        let started = detector.meetingStarted(at: t0 + 5, ignoredApps: [])

        #expect(started.app == chrome)
        #expect(started.event == sync)
    }
}
