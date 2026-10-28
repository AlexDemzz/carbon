import Foundation

/// The app a Meeting is held through, resolved from its processes' responsible app.
public struct MeetingApp: Hashable, Sendable, Codable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Decides when a Meeting starts and ends from timestamped signals. Pure: no clock, no I/O.
public struct Detector: Sendable {
    public struct Signals: Sendable {
        public var time: Date
        /// The apps holding the microphone, each resolved to its owning app.
        public var micHolders: [MeetingApp]
        /// The power assertions when they were polled at this time, nil between polls.
        public var assertions: [PowerAssertion]?
        /// The last time the live Meeting's audio was not silent.
        public var lastSound: Date?
        /// The person's Ignored Apps, by bundle ID.
        public var ignoredApps: Set<String>

        public init(
            time: Date, micHolders: [MeetingApp], assertions: [PowerAssertion]? = nil, lastSound: Date? = nil,
            ignoredApps: Set<String> = []
        ) {
            self.time = time
            self.micHolders = micHolders
            self.assertions = assertions
            self.lastSound = lastSound
            self.ignoredApps = ignoredApps
        }
    }

    public enum Command: Equatable, Sendable {
        /// Start a Meeting on this Meeting App.
        case start(MeetingApp)
        /// End the live Meeting.
        case end(EndReason)
        /// Another app's start signal during the live Meeting: offer to switch the Meeting to it.
        case offerSwitch(MeetingApp)
    }

    public enum EndReason: Equatable, Sendable {
        /// The mic was released and the Meeting stayed silent long enough.
        case silence
        /// The call assertion and the mic were released for the grace period, then 30 s passed in silence.
        case callEnded
        /// A new call began: a new `AssertionId` while the mic stayed held, or a start signal (from the same app or
        /// another) after the Meeting App's mic and call assertion were both released for `backToBackGap`.
        case backToBack
        /// The Meeting reached `cap`. The start rules run again, so a call still live becomes a new Meeting.
        case cap
    }

    public static let holdToStart: TimeInterval = 15
    /// Consecutive polls a call assertion must be seen on to start a Meeting.
    public static let callPollsToStart = 2
    /// With no call assertion and no Event: mic released + this much silence ends the Meeting.
    public static let silenceToEnd: TimeInterval = 10 * 60
    /// With a call assertion: the assertion and the mic released this long, then `callSilenceToEnd` of silence.
    public static let callReleaseGrace: TimeInterval = 15
    public static let callSilenceToEnd: TimeInterval = 30
    /// A call released this long and then back is a new call.
    public static let backToBackGap: TimeInterval = 5
    /// After Detection ends a Meeting, nothing starts for this long.
    public static let cooldown: TimeInterval = 5
    public static let cap: TimeInterval = 4 * 60 * 60
    public static let carbonBundleID = "me.alexandrejoly.carbon"
    /// Never a hold and never a release, whatever the tables or the person say.
    public static let alwaysIgnored: Set<String> = [carbonBundleID, "com.apple.CoreSpeech"]

    /// A start signal: a mic hold, or a call assertion seen since `since`.
    private struct Hold {
        var app: MeetingApp
        var since: Date
    }

    /// A native call assertion, by its app, from the polls.
    private struct Call {
        var app: MeetingApp
        var ids: Set<Int>
        var since: Date
        var polls: Int
    }

    private struct Live {
        var app: MeetingApp?
        var start: Date
        /// When the Meeting App last stopped holding the mic (and its call assertion), nil while it holds it.
        var releasedAt: Date?
        /// The `AssertionId`s of the Meeting App's call, once confirmed during the Meeting: the call stop rule applies.
        var callIDs: Set<Int>?
    }

    private let vendorTable: VendorTable
    private var holds: [String: Hold] = [:]
    private var calls: [String: Call] = [:]
    /// Holds a manual Stop ended: they must be released before they can start a Meeting again.
    private var spentHolds: Set<String> = []
    /// The `AssertionId`s of calls a manual Stop ended: only a new call can start a Meeting.
    private var spentCallIDs: Set<Int> = []
    private var live: Live?
    /// Detection ended a Meeting: nothing starts before this time.
    private var cooldownUntil: Date?
    /// Apps already offered a switch, until their start signal goes.
    private var offeredSwitch: Set<String> = []

    public init(vendorTable: VendorTable = .shipped) {
        self.vendorTable = vendorTable
    }

    public func isIgnored(_ bundleID: String, ignoredApps: Set<String>) -> Bool {
        if Self.alwaysIgnored.contains(bundleID) { return true }
        if vendorTable.neverIgnored.contains(bundleID) { return false }
        return vendorTable.ignoredApps.contains(bundleID) || ignoredApps.contains(bundleID)
    }

    public mutating func observe(_ signals: Signals) -> [Command] {
        updateHolds(signals.micHolders, at: signals.time, ignoredApps: signals.ignoredApps)
        if let assertions = signals.assertions {
            updateCalls(assertions, at: signals.time, ignoredApps: signals.ignoredApps)
        }
        offeredSwitch = offeredSwitch.filter { holds[$0] != nil || calls[$0] != nil }
        if var meeting = live {
            if let reason = endReason(of: &meeting, signals) {
                live = nil
                cooldownUntil = signals.time + Self.cooldown
                return [.end(reason)]
            }
            live = meeting
            return overlap(with: meeting, at: signals.time)
        }
        if let cooldownUntil, signals.time < cooldownUntil { return [] }
        guard let ready = readyToStart(at: signals.time) else { return [] }
        live = Live(app: ready.app, start: signals.time)
        return [.start(ready.app)]
    }

    /// The person started a Meeting by hand. Returns the Meeting App: the app holding the mic longest, if any.
    public mutating func meetingStarted(at time: Date, ignoredApps: Set<String>) -> MeetingApp? {
        let app = holds.values
            .filter { !isIgnored($0.app.bundleID, ignoredApps: ignoredApps) }
            .min { $0.since < $1.since }?.app
        live = Live(app: app, start: time, releasedAt: app == nil ? time : nil)
        return app
    }

    /// The person took the "Switch to <app>" offer: the live Meeting ended and one started on `app`. The old
    /// Meeting App's current hold and call are spent, so they don't offer to switch back.
    public mutating func meetingSwitched(to app: MeetingApp, at time: Date) {
        if let old = live?.app, old != app {
            if holds[old.bundleID] != nil { spentHolds.insert(old.bundleID) }
            spentCallIDs.formUnion(calls[old.bundleID]?.ids ?? [])
        }
        live = Live(app: app, start: time)
        offeredSwitch.remove(app.bundleID)
        cooldownUntil = nil
    }

    /// The live Meeting ended outside Detection: a manual Stop or Discard, or a start that failed.
    public mutating func meetingStopped() {
        live = nil
        spentHolds.formUnion(holds.keys)
        spentCallIDs.formUnion(calls.values.flatMap(\.ids))
    }

    /// Updates the live Meeting's release and tells whether one of its end rules is met.
    private func endReason(of meeting: inout Live, _ signals: Signals) -> EndReason? {
        if signals.time.timeIntervalSince(meeting.start) >= Self.cap { return .cap }
        let call = meeting.app.flatMap { calls[$0.bundleID] }
        let micHeld = meeting.app.map { holds[$0.bundleID] != nil } ?? false
        // A call the Meeting didn't start with, on the same app, with the mic held all along: a new call.
        if let known = meeting.callIDs, let call, known.isDisjoint(with: call.ids), micHeld { return .backToBack }
        if let call, meeting.callIDs != nil || call.polls >= Self.callPollsToStart { meeting.callIDs = call.ids }
        let hasCall = meeting.callIDs != nil
        if micHeld || (hasCall && call != nil) {
            if hasCall, let releasedAt = meeting.releasedAt,
                signals.time.timeIntervalSince(releasedAt) >= Self.backToBackGap
            {
                return .backToBack
            }
            meeting.releasedAt = nil
            return nil
        }
        let releasedAt = meeting.releasedAt ?? signals.time
        meeting.releasedAt = releasedAt
        if hasCall {
            let graceEnd = releasedAt + Self.callReleaseGrace
            let silentSince = max(graceEnd, signals.lastSound ?? graceEnd)
            return signals.time.timeIntervalSince(silentSince) >= Self.callSilenceToEnd ? .callEnded : nil
        }
        let silentSince = max(releasedAt, signals.lastSound ?? releasedAt)
        return signals.time.timeIntervalSince(silentSince) >= Self.silenceToEnd ? .silence : nil
    }

    /// Another app's start signal while `meeting` is live. At most one Meeting is live: once the Meeting App has
    /// been released for `backToBackGap`, the other app takes over as back-to-back; until then it is only offered.
    private mutating func overlap(with meeting: Live, at time: Date) -> [Command] {
        guard let other = readyToStart(at: time, excluding: meeting.app) else { return [] }
        if meeting.app != nil, let releasedAt = meeting.releasedAt,
            time.timeIntervalSince(releasedAt) >= Self.backToBackGap
        {
            live = Live(app: other.app, start: time)
            return [.end(.backToBack), .start(other.app)]
        }
        guard offeredSwitch.insert(other.app.bundleID).inserted else { return [] }
        return [.offerSwitch(other.app)]
    }

    /// The app whose start signal came first: a mic hold of 15 s or a call assertion confirmed on 2 polls.
    private func readyToStart(at time: Date, excluding excluded: MeetingApp? = nil) -> Hold? {
        let micHolds = holds.values.filter {
            !spentHolds.contains($0.app.bundleID) && time.timeIntervalSince($0.since) >= Self.holdToStart
        }
        let confirmedCalls = calls.values
            .filter { spentCallIDs.isDisjoint(with: $0.ids) && $0.polls >= Self.callPollsToStart }
            .map { Hold(app: $0.app, since: $0.since) }
        return (micHolds + confirmedCalls).filter { $0.app != excluded }.min { $0.since < $1.since }
    }

    private mutating func updateCalls(_ assertions: [PowerAssertion], at time: Date, ignoredApps: Set<String>) {
        var current: [String: Call] = [:]
        for assertion in assertions where vendorTable.kind(of: assertion) == .call {
            guard !isIgnored(assertion.app.bundleID, ignoredApps: ignoredApps) else { continue }
            current[assertion.app.bundleID, default: Call(app: assertion.app, ids: [], since: time, polls: 0)]
                .ids.insert(assertion.id)
        }
        for (bundleID, var call) in current {
            if let previous = calls[bundleID] {
                // Only new `AssertionId`s: the previous call ended and a new one began.
                if !previous.ids.isDisjoint(with: call.ids) {
                    call.since = previous.since
                    call.polls = previous.polls
                }
            }
            call.polls += 1
            current[bundleID] = call
        }
        calls = current
    }

    private mutating func updateHolds(_ holders: [MeetingApp], at time: Date, ignoredApps: Set<String>) {
        var current: [String: Hold] = [:]
        for app in holders where !isIgnored(app.bundleID, ignoredApps: ignoredApps) {
            current[app.bundleID] = holds[app.bundleID] ?? Hold(app: app, since: time)
        }
        holds = current
        spentHolds.formIntersection(holds.keys)
    }
}
