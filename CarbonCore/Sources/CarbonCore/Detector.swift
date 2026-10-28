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

        public init(
            time: Date, micHolders: [MeetingApp], lastSound: Date? = nil, ignoredApps: Set<String> = [],
            autoTranscribe: Bool = true
        ) {
            self.time = time
            self.micHolders = micHolders
            self.lastSound = lastSound
            self.ignoredApps = ignoredApps
            self.autoTranscribe = autoTranscribe
        }
    }

    public enum Command: Equatable, Sendable {
        /// Start a Meeting on this Meeting App.
        case start(MeetingApp)
        /// Offer the person a Meeting on this Meeting App (auto-transcribe off).
        case offer(MeetingApp)
        /// Take back the offer: nobody answered it in time, or its app released the mic.
        case withdrawOffer(MeetingApp)
        /// End the live Meeting.
        case end(EndReason)
    }

    public enum EndReason: Equatable, Sendable {
        /// The mic was released and the Meeting stayed silent long enough.
        case silence
    }

    public static let holdToStart: TimeInterval = 15
    public static let offerTimeout: TimeInterval = 60
    public static let declineMute: TimeInterval = 10 * 60
    /// With no call assertion and no Event: mic released + this much silence ends the Meeting.
    public static let silenceToEnd: TimeInterval = 10 * 60
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
    }

    private let vendorTable: VendorTable
    private var holds: [String: Hold] = [:]
    /// Holds a manual Stop ended: they must be released before they can start a Meeting again.
    private var spent: Set<String> = []
    private var live: Live?
    /// The offer waiting for an answer, `since` it was posted.
    private var offer: Hold?
    /// Apps whose offer the person declined, by bundle ID, until the mute ends.
    private var mutedUntil: [String: Date] = [:]

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
        if var meeting = live {
            if let app = meeting.app, holds[app.bundleID] != nil {
                meeting.releasedAt = nil
            } else {
                meeting.releasedAt = meeting.releasedAt ?? signals.time
            }
            live = meeting
            guard let releasedAt = meeting.releasedAt else { return [] }
            let silentSince = max(releasedAt, signals.lastSound ?? releasedAt)
            guard signals.time.timeIntervalSince(silentSince) >= Self.silenceToEnd else { return [] }
            live = nil
            return [.end(.silence)]
        }
        if let pending = offer {
            if holds[pending.app.bundleID] == nil {
                offer = nil
                return [.withdrawOffer(pending.app)]
            }
            guard signals.time.timeIntervalSince(pending.since) >= Self.offerTimeout else { return [] }
            offer = nil
            spent.insert(pending.app.bundleID)
            return [.withdrawOffer(pending.app)]
        }
        mutedUntil = mutedUntil.filter { signals.time < $0.value }
        let ready = holds.values
            .filter { !spent.contains($0.app.bundleID) && mutedUntil[$0.app.bundleID] == nil }
            .filter { signals.time.timeIntervalSince($0.since) >= Self.holdToStart }
            .min { $0.since < $1.since }
        guard let ready else { return [] }
        guard signals.autoTranscribe else {
            offer = Hold(app: ready.app, since: signals.time)
            return [.offer(ready.app)]
        }
        live = Live(app: ready.app)
        return [.start(ready.app)]
    }

    /// The app of the offer waiting for an answer.
    public var pendingOffer: MeetingApp? { offer?.app }

    /// The person chose Transcribe on the pending offer. Returns its app, or nil when the offer was withdrawn.
    public mutating func offerAccepted() -> MeetingApp? {
        guard let pending = offer else { return nil }
        offer = nil
        live = Live(app: pending.app)
        return pending.app
    }

    /// The person dismissed the pending offer, or chose Never: that app can't be offered again for 10 min.
    public mutating func offerDeclined(at time: Date) {
        guard let pending = offer else { return }
        offer = nil
        spent.insert(pending.app.bundleID)
        mutedUntil[pending.app.bundleID] = time + Self.declineMute
    }

    /// The person started a Meeting by hand. Returns the Meeting App: the app holding the mic longest, if any.
    public mutating func meetingStarted(at time: Date, ignoredApps: Set<String>) -> MeetingApp? {
        let app = holds.values
            .filter { !isIgnored($0.app.bundleID, ignoredApps: ignoredApps) }
            .min { $0.since < $1.since }?.app
        live = Live(app: app, releasedAt: app == nil ? time : nil)
        return app
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
