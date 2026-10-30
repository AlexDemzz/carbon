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
        /// "Transcribe Meetings automatically": off, Detection only offers Meetings.
        public var autoTranscribe: Bool
        /// The calendar events around `time`; the Detector keeps the ones in their matching window.
        public var events: [CalendarEvent]

        public init(
            time: Date, micHolders: [MeetingApp], assertions: [PowerAssertion]? = nil, lastSound: Date? = nil,
            ignoredApps: Set<String> = [], autoTranscribe: Bool = true, events: [CalendarEvent] = []
        ) {
            self.time = time
            self.micHolders = micHolders
            self.assertions = assertions
            self.lastSound = lastSound
            self.ignoredApps = ignoredApps
            self.autoTranscribe = autoTranscribe
            self.events = events
        }
    }

    public enum Command: Equatable, Sendable {
        /// Start a Meeting on this Meeting App, belonging to this Event if any.
        case start(MeetingApp, event: CalendarEvent? = nil)
        /// Offer the person a Meeting on this Meeting App (auto-transcribe off), belonging to this Event if any.
        case offer(MeetingApp, event: CalendarEvent? = nil)
        /// Take back the offer: nobody answered it in time, or its app released the mic.
        case withdrawOffer(MeetingApp)
        /// The live Meeting belongs to this Event from now on: the hold began less than 10 min before it.
        case event(CalendarEvent)
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
        /// The Meeting App's WebRTC assertion and the mic were released for `webRTCReleaseGrace`. No silence is needed:
        /// the browser's other tabs keep playing after the call.
        case webRTCEnded
        /// A new call began: its Event ended and another one started while the mic stayed held, a new
        /// `AssertionId` while the mic stayed held, or a start signal after the Meeting App's mic and call
        /// assertion were both released for `backToBackGap`. A new Meeting follows.
        case backToBack
        /// The Meeting reached `cap`. The start rules run again, so a call still live becomes a new Meeting.
        case cap
    }

    public static let holdToStart: TimeInterval = 15
    /// Consecutive polls a call assertion must be seen on to start a Meeting.
    public static let callPollsToStart = 2
    public static let offerTimeout: TimeInterval = 60
    public static let declineMute: TimeInterval = 10 * 60
    /// With no call assertion and no Event: mic released + this much silence ends the Meeting.
    public static let silenceToEnd: TimeInterval = 10 * 60
    /// With an Event that is over: mic released + this much silence ends the Meeting.
    public static let silenceToEndAfterEvent: TimeInterval = 30
    /// With a call assertion: the assertion and the mic released this long, then `callSilenceToEnd` of silence.
    /// The Event, if any, need not be over.
    public static let callReleaseGrace: TimeInterval = 15
    public static let callSilenceToEnd: TimeInterval = 30
    /// With the Meeting App's WebRTC assertion seen during the Meeting: the assertion and the mic released this long.
    public static let webRTCReleaseGrace: TimeInterval = 10
    /// A call released this long and then back is a new call.
    public static let backToBackGap: TimeInterval = 5
    /// A hold that began this long before the next Event belongs to the earlier call, not to that Event.
    public static let holdBeforeNextEvent: TimeInterval = 10 * 60
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
        var event: CalendarEvent?
        /// The `AssertionId`s of the Meeting App's call, once confirmed during the Meeting: the call stop rule applies.
        var callIDs: Set<Int>?
        /// The Meeting App's WebRTC assertion, once seen during the Meeting: the WebRTC stop rule applies.
        var webRTC: WebRTC?
    }

    private enum WebRTC {
        case held
        case released(at: Date)
    }

    private let vendorTable: VendorTable
    private let matcher: EventMatcher
    private var events: [CalendarEvent] = []
    /// After Detection ends a Meeting: no start before `until`, and not on the Event that just ended back-to-back.
    private var cooldown: (until: Date, event: CalendarEvent?)?
    private var holds: [String: Hold] = [:]
    private var calls: [String: Call] = [:]
    /// The apps holding a WebRTC assertion, by bundle ID, from the polls.
    private var webRTCHolders: Set<String> = []
    /// Holds a manual Stop ended: they must be released before they can start a Meeting again.
    private var spent: Set<String> = []
    /// The `AssertionId`s of calls a manual Stop ended: only a new call can start a Meeting.
    private var spentCallIDs: Set<Int> = []
    private var live: Live?
    /// The offer waiting for an answer, `since` it was posted.
    private var offer: Hold?
    /// The Event of the pending offer.
    private var offerEvent: CalendarEvent?
    /// Apps whose offer the person declined, by bundle ID, until the mute ends.
    private var mutedUntil: [String: Date] = [:]
    /// Apps already offered a switch, until their start signal goes.
    private var offeredSwitch: Set<String> = []

    public init(vendorTable: VendorTable = .shipped) {
        self.vendorTable = vendorTable
        matcher = EventMatcher(vendorTable: vendorTable)
    }

    public func isIgnored(_ bundleID: String, ignoredApps: Set<String>) -> Bool {
        if Self.alwaysIgnored.contains(bundleID) { return true }
        if vendorTable.neverIgnored.contains(bundleID) { return false }
        return vendorTable.ignoredApps.contains(bundleID) || ignoredApps.contains(bundleID)
    }

    public mutating func observe(_ signals: Signals) -> [Command] {
        let time = signals.time
        updateHolds(signals.micHolders, at: time, ignoredApps: signals.ignoredApps)
        if let assertions = signals.assertions {
            updateAssertions(assertions, at: time, ignoredApps: signals.ignoredApps)
        }
        events = signals.events
        offeredSwitch = offeredSwitch.filter(isSignaling)
        if var meeting = live {
            if let commands = liveCommands(&meeting, signals) { return commands }
            live = meeting
            return overlap(with: meeting, signals)
        }
        if let pending = offer {
            if !isSignaling(pending.app.bundleID) {
                offer = nil
                return [.withdrawOffer(pending.app)]
            }
            guard time.timeIntervalSince(pending.since) >= Self.offerTimeout else { return [] }
            offer = nil
            spend(pending.app)
            return [.withdrawOffer(pending.app)]
        }
        if let cooldown, time < cooldown.until { return [] }
        guard let ready = readyToStart(at: time) else { return [] }
        return startOrOffer(ready.app, signals)
    }

    /// The live Meeting's end and Event rules. Nil while it goes on as it is.
    private mutating func liveCommands(_ meeting: inout Live, _ signals: Signals) -> [Command]? {
        let time = signals.time
        if let reason = endReason(of: &meeting, signals) {
            return end(reason, at: time)
        }
        if let hold = meeting.app.flatMap({ holds[$0.bundleID] }), let ended = meeting.event, ended.end <= time,
            let next = nextEvent(after: ended, at: time)
        {
            if next.start.timeIntervalSince(hold.since) >= Self.holdBeforeNextEvent {
                return end(.backToBack, at: time, event: ended)
            }
            meeting.event = next
            live = meeting
            return [.event(next)]
        }
        return nil
    }

    private mutating func end(_ reason: EndReason, at time: Date, event: CalendarEvent? = nil) -> [Command] {
        live = nil
        cooldown = (time + Self.cooldown, event)
        return [.end(reason)]
    }

    /// Updates the live Meeting's release and tells whether one of its end rules is met.
    private func endReason(of meeting: inout Live, _ signals: Signals) -> EndReason? {
        let time = signals.time
        if time.timeIntervalSince(meeting.start) >= Self.cap { return .cap }
        let call = meeting.app.flatMap { calls[$0.bundleID] }
        let micHeld = meeting.app.map { holds[$0.bundleID] != nil } ?? false
        // None of the call's `AssertionId`s left, with the mic held all along: a new call.
        if let known = meeting.callIDs, let call, known.isDisjoint(with: call.ids), micHeld { return .backToBack }
        if let call, meeting.callIDs != nil || call.polls >= Self.callPollsToStart { meeting.callIDs = call.ids }
        let hasCall = meeting.callIDs != nil
        if let app = meeting.app {
            if webRTCHolders.contains(app.bundleID) {
                meeting.webRTC = .held
            } else if case .held = meeting.webRTC {
                meeting.webRTC = .released(at: time)
            }
        }
        if micHeld || (hasCall && call != nil) {
            if hasCall, let releasedAt = meeting.releasedAt, time.timeIntervalSince(releasedAt) >= Self.backToBackGap {
                return .backToBack
            }
            meeting.releasedAt = nil
            return nil
        }
        let releasedAt = meeting.releasedAt ?? time
        meeting.releasedAt = releasedAt
        if hasCall {
            let graceEnd = releasedAt + Self.callReleaseGrace
            let silentSince = max(graceEnd, signals.lastSound ?? graceEnd)
            return time.timeIntervalSince(silentSince) >= Self.callSilenceToEnd ? .callEnded : nil
        }
        if case .released(let webRTCReleasedAt) = meeting.webRTC,
            time.timeIntervalSince(max(releasedAt, webRTCReleasedAt)) >= Self.webRTCReleaseGrace
        {
            return .webRTCEnded
        }
        let silence = time.timeIntervalSince(max(releasedAt, signals.lastSound ?? releasedAt))
        let eventOver = meeting.event.map { $0.end <= time } ?? false
        guard silence >= Self.silenceToEnd || (eventOver && silence >= Self.silenceToEndAfterEvent) else {
            return nil
        }
        return .silence
    }

    /// Another app's start signal while `meeting` is live. At most one Meeting is live: once the Meeting App has
    /// been released for `backToBackGap`, the other app takes over as back-to-back; until then it is only offered.
    private mutating func overlap(with meeting: Live, _ signals: Signals) -> [Command] {
        guard let other = readyToStart(at: signals.time, excluding: meeting.app) else { return [] }
        if meeting.app != nil, let releasedAt = meeting.releasedAt,
            signals.time.timeIntervalSince(releasedAt) >= Self.backToBackGap
        {
            live = nil
            return [.end(.backToBack)] + startOrOffer(other.app, signals)
        }
        guard offeredSwitch.insert(other.app.bundleID).inserted else { return [] }
        return [.offerSwitch(other.app)]
    }

    private mutating func startOrOffer(_ app: MeetingApp, _ signals: Signals) -> [Command] {
        let event = matcher.match(events, app: app, at: signals.time, excluding: cooldown?.event)
        cooldown = nil
        guard signals.autoTranscribe else {
            offer = Hold(app: app, since: signals.time)
            offerEvent = event
            return [.offer(app, event: event)]
        }
        live = Live(app: app, start: signals.time, event: event)
        return [.start(app, event: event)]
    }

    /// Another Event that has started by `time` while still in its window, for a back-to-back call.
    private func nextEvent(after ended: CalendarEvent, at time: Date) -> CalendarEvent? {
        events
            .filter {
                !$0.isOccurrence(of: ended) && $0.start > ended.start && $0.start <= time
                    && EventMatcher.isCandidate($0, at: time)
            }
            .min { $0.start < $1.start }
    }

    /// The app of the offer waiting for an answer.
    public var pendingOffer: MeetingApp? { offer?.app }

    /// The person chose Transcribe on the pending offer. Returns its app and Event, or nil when it was withdrawn.
    public mutating func offerAccepted(at time: Date) -> (app: MeetingApp, event: CalendarEvent?)? {
        guard let pending = offer else { return nil }
        offer = nil
        live = Live(app: pending.app, start: time, event: offerEvent)
        return (pending.app, offerEvent)
    }

    /// The person dismissed the pending offer, or chose Never: that app can't be offered again for 10 min.
    public mutating func offerDeclined(at time: Date) {
        guard let pending = offer else { return }
        offer = nil
        spend(pending.app)
        mutedUntil[pending.app.bundleID] = time + Self.declineMute
    }

    /// The person started a Meeting by hand. Returns its Meeting App, the app holding the mic longest if any, and
    /// the Event in its window from the last signals.
    public mutating func meetingStarted(
        at time: Date, ignoredApps: Set<String>
    ) -> (app: MeetingApp?, event: CalendarEvent?) {
        let app = holds.values
            .filter { !isIgnored($0.app.bundleID, ignoredApps: ignoredApps) }
            .min { $0.since < $1.since }?.app
        let event = matcher.match(events, app: app, at: time)
        cooldown = nil
        live = Live(app: app, start: time, releasedAt: app == nil ? time : nil, event: event)
        return (app, event)
    }

    /// The person took the "Switch to <app>" offer: the live Meeting ended and one starts on `app`. The old
    /// Meeting App's current hold and call are spent, so they don't offer to switch back. Returns `app`'s Event.
    public mutating func meetingSwitched(to app: MeetingApp, at time: Date) -> CalendarEvent? {
        if let old = live?.app, old != app { spend(old) }
        let event = matcher.match(events, app: app, at: time)
        live = Live(app: app, start: time, event: event)
        offeredSwitch.remove(app.bundleID)
        cooldown = nil
        return event
    }

    /// The live Meeting ended outside Detection: a manual Stop or Discard, or a start that failed.
    public mutating func meetingStopped() {
        live = nil
        spent.formUnion(holds.keys)
        spentCallIDs.formUnion(calls.values.flatMap(\.ids))
    }

    /// The app's current hold and call can't start a Meeting again: only a new hold or a new call can.
    private mutating func spend(_ app: MeetingApp) {
        if holds[app.bundleID] != nil { spent.insert(app.bundleID) }
        spentCallIDs.formUnion(calls[app.bundleID]?.ids ?? [])
    }

    /// Whether the app holds the mic or a call assertion.
    private func isSignaling(_ bundleID: String) -> Bool {
        holds[bundleID] != nil || calls[bundleID] != nil
    }

    /// The app whose start signal came first: a mic hold of 15 s or a call assertion confirmed on 2 polls.
    private mutating func readyToStart(at time: Date, excluding excluded: MeetingApp? = nil) -> Hold? {
        mutedUntil = mutedUntil.filter { time < $0.value }
        let micHolds = holds.values.filter {
            !spent.contains($0.app.bundleID) && time.timeIntervalSince($0.since) >= Self.holdToStart
        }
        let confirmedCalls = calls.values
            .filter { spentCallIDs.isDisjoint(with: $0.ids) && $0.polls >= Self.callPollsToStart }
            .map { Hold(app: $0.app, since: $0.since) }
        return (micHolds + confirmedCalls)
            .filter { $0.app != excluded && mutedUntil[$0.app.bundleID] == nil }
            .min { $0.since < $1.since }
    }

    private mutating func updateAssertions(_ assertions: [PowerAssertion], at time: Date, ignoredApps: Set<String>) {
        webRTCHolders = Set(assertions.filter { vendorTable.kind(of: $0) == .webRTC }.map(\.app.bundleID))
        var current: [String: Call] = [:]
        for assertion in assertions where vendorTable.kind(of: assertion) == .call {
            guard !isIgnored(assertion.app.bundleID, ignoredApps: ignoredApps) else { continue }
            current[assertion.app.bundleID, default: Call(app: assertion.app, ids: [], since: time, polls: 0)]
                .ids.insert(assertion.id)
        }
        for (bundleID, var call) in current {
            // Only new `AssertionId`s: the previous call ended and a new one began.
            if let previous = calls[bundleID], !previous.ids.isDisjoint(with: call.ids) {
                call.since = previous.since
                call.polls = previous.polls
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
        spent.formIntersection(holds.keys)
    }
}
