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
        /// The last time the live Meeting's audio was not silent.
        public var lastSound: Date?
        /// The person's Ignored Apps, by bundle ID.
        public var ignoredApps: Set<String>
        /// "Transcribe Meetings automatically": off, Detection only offers Meetings.
        public var autoTranscribe: Bool
        /// The calendar events around `time`; the Detector keeps the ones in their matching window.
        public var events: [CalendarEvent]

        public init(
            time: Date, micHolders: [MeetingApp], lastSound: Date? = nil, ignoredApps: Set<String> = [],
            autoTranscribe: Bool = true, events: [CalendarEvent] = []
        ) {
            self.time = time
            self.micHolders = micHolders
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
    }

    public enum EndReason: Equatable, Sendable {
        /// The mic was released and the Meeting stayed silent long enough.
        case silence
        /// Its Event ended and another one started while the mic stayed held: a new Meeting follows.
        case backToBack
    }

    public static let holdToStart: TimeInterval = 15
    public static let offerTimeout: TimeInterval = 60
    public static let declineMute: TimeInterval = 10 * 60
    /// With no call assertion and no Event: mic released + this much silence ends the Meeting.
    public static let silenceToEnd: TimeInterval = 10 * 60
    /// With an Event that is over: mic released + this much silence ends the Meeting.
    public static let silenceToEndAfterEvent: TimeInterval = 30
    /// A hold that began this long before the next Event belongs to the earlier call (Hyprnote's rule).
    public static let holdBeforeNextEvent: TimeInterval = 10 * 60
    /// Between a back-to-back end and the next start.
    public static let cooldown: TimeInterval = 5
    public static let carbonBundleID = "me.alexandrejoly.carbon"
    /// Never a hold and never a release, whatever the tables or the person say.
    public static let alwaysIgnored: Set<String> = [carbonBundleID, "com.apple.CoreSpeech"]

    private struct Hold {
        var app: MeetingApp
        var since: Date
    }

    private struct Live {
        var app: MeetingApp?
        /// When the Meeting App last stopped holding the mic, nil while it holds it.
        var releasedAt: Date?
        var event: CalendarEvent?
    }

    private let vendorTable: VendorTable
    private let matcher: EventMatcher
    private var events: [CalendarEvent] = []
    /// After a back-to-back end: no start before `until`, and not on the Event that just ended.
    private var cooldown: (until: Date, event: CalendarEvent?)?
    private var holds: [String: Hold] = [:]
    /// Holds a manual Stop ended: they must be released before they can start a Meeting again.
    private var spent: Set<String> = []
    private var live: Live?
    /// The offer waiting for an answer, `since` it was posted.
    private var offer: Hold?
    /// The Event of the pending offer.
    private var offerEvent: CalendarEvent?
    /// Apps whose offer the person declined, by bundle ID, until the mute ends.
    private var mutedUntil: [String: Date] = [:]

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
        events = signals.events
        if var meeting = live {
            let hold = meeting.app.flatMap { holds[$0.bundleID] }
            meeting.releasedAt = hold == nil ? meeting.releasedAt ?? time : nil
            live = meeting
            if let hold, let ended = meeting.event, ended.end <= time, let next = nextEvent(after: ended, at: time) {
                if next.start.timeIntervalSince(hold.since) >= Self.holdBeforeNextEvent {
                    live = nil
                    cooldown = (time.addingTimeInterval(Self.cooldown), ended)
                    return [.end(.backToBack)]
                }
                live?.event = next
                return [.event(next)]
            }
            guard let releasedAt = meeting.releasedAt else { return [] }
            let silence = time.timeIntervalSince(max(releasedAt, signals.lastSound ?? releasedAt))
            let eventOver = meeting.event.map { $0.end <= time } ?? false
            guard silence >= Self.silenceToEnd || (eventOver && silence >= Self.silenceToEndAfterEvent) else {
                return []
            }
            live = nil
            return [.end(.silence)]
        }
        if let pending = offer {
            if holds[pending.app.bundleID] == nil {
                offer = nil
                return [.withdrawOffer(pending.app)]
            }
            guard time.timeIntervalSince(pending.since) >= Self.offerTimeout else { return [] }
            offer = nil
            spent.insert(pending.app.bundleID)
            return [.withdrawOffer(pending.app)]
        }
        if let cooldown, time < cooldown.until { return [] }
        mutedUntil = mutedUntil.filter { time < $0.value }
        let ready = holds.values
            .filter { !spent.contains($0.app.bundleID) && mutedUntil[$0.app.bundleID] == nil }
            .filter { time.timeIntervalSince($0.since) >= Self.holdToStart }
            .min { $0.since < $1.since }
        guard let ready else { return [] }
        let event = matcher.match(events, app: ready.app, at: time, excluding: cooldown?.event)
        cooldown = nil
        guard signals.autoTranscribe else {
            offer = Hold(app: ready.app, since: time)
            offerEvent = event
            return [.offer(ready.app, event: event)]
        }
        live = Live(app: ready.app, event: event)
        return [.start(ready.app, event: event)]
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
    public mutating func offerAccepted() -> (app: MeetingApp, event: CalendarEvent?)? {
        guard let pending = offer else { return nil }
        offer = nil
        live = Live(app: pending.app, event: offerEvent)
        return (pending.app, offerEvent)
    }

    /// The person dismissed the pending offer, or chose Never: that app can't be offered again for 10 min.
    public mutating func offerDeclined(at time: Date) {
        guard let pending = offer else { return }
        offer = nil
        spent.insert(pending.app.bundleID)
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
        live = Live(app: app, releasedAt: app == nil ? time : nil, event: event)
        return (app, event)
    }

    /// The live Meeting ended outside Detection: a manual Stop or Discard, or a start that failed.
    public mutating func meetingStopped() {
        live = nil
        spent.formUnion(holds.keys)
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
