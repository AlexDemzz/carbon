import Foundation

/// The Providers Carbon names itself. Every other one comes from the vendor table or the Meeting App's name.
public enum Provider {
    /// A Meeting with no native app, no Event link and no Meeting App to name its Provider after.
    public static let unknown = "Unknown"
}

/// The vendor strings Detection depends on, shipped as data in each release (`Resources/VendorTable.json`).
/// The person's own additions live in Settings, never here.
public struct VendorTable: Sendable, Decodable {
    /// Apps whose mic use never counts toward Detection: dictation tools, screen recorders, voice assistants.
    public var ignoredApps: Set<String>
    /// Call apps and helpers that are never ignored, even when the person adds them to Ignored Apps.
    public var neverIgnored: Set<String>
    /// Native Meeting App bundle ID → Provider.
    public var providers: [String: String]
    /// Conference link host → Provider, tried in order. A link counts only if its path matches `path`, whose first
    /// capture group, when it has one, is the Provider's meeting code.
    public var links: [LinkRule]
    /// Native call assertions: one means a call is live in that app.
    public var callAssertions: [AssertionMatcher]
    /// Chromium's WebRTC assertion: logged only, it never starts anything.
    public var webRTCAssertions: [AssertionMatcher]

    /// Matches an assertion on its owning app, its name and its type. A field left out matches anything.
    public struct AssertionMatcher: Sendable, Decodable {
        public var apps: Set<String>?
        public var name: String?
        /// Modern type names; their legacy spellings match too.
        public var types: Set<String>?

        func matches(_ assertion: PowerAssertion) -> Bool {
            (apps?.contains(assertion.app.bundleID) ?? true)
                && (name.map { $0.caseInsensitiveCompare(assertion.name) == .orderedSame } ?? true)
                && (types?.contains(VendorTable.modernType(assertion.type)) ?? true)
        }
    }

    public enum AssertionKind: Equatable, Sendable {
        case call
        case webRTC
    }

    /// Legacy assertion types, as Chromium and older apps still create them, to their modern names.
    static let legacyTypes = [
        "NoDisplaySleepAssertion": "PreventUserIdleDisplaySleep",
        "NoIdleSleepAssertion": "PreventUserIdleSystemSleep",
    ]

    static func modernType(_ type: String) -> String {
        legacyTypes[type] ?? type
    }

    /// Whether `assertion` is a native call, Chromium's WebRTC assertion, or neither.
    public func kind(of assertion: PowerAssertion) -> AssertionKind? {
        if callAssertions.contains(where: { $0.matches(assertion) }) { return .call }
        if webRTCAssertions.contains(where: { $0.matches(assertion) }) { return .webRTC }
        return nil
    }

    public struct LinkRule: Sendable, Decodable {
        /// Matches this host and its subdomains (`zoom.us` matches `us02web.zoom.us`).
        public var host: String
        public var provider: String
        public var path: String
    }

    public static let shipped: VendorTable = {
        guard let url = Bundle.module.url(forResource: "VendorTable", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { preconditionFailure("VendorTable.json is missing from the CarbonCore bundle") }
        do {
            return try JSONDecoder().decode(VendorTable.self, from: data)
        } catch {
            preconditionFailure("VendorTable.json is invalid: \(error)")
        }
    }()

    /// The Provider of a Meeting held through `app`: a native app's own Provider, else the app's display name.
    public func provider(for app: MeetingApp) -> String {
        providers[app.bundleID] ?? app.name
    }

    /// Provider resolution: a native app's bundle ID wins, else the matched Event's link, else the Meeting App's
    /// display name. `Unknown` when there is none of these.
    public func provider(for app: MeetingApp?, link: ConferenceLink?) -> String {
        if let app, let native = providers[app.bundleID] { return native }
        return link?.provider ?? app?.name ?? Provider.unknown
    }

    /// Whether the table says anything about `bundleID`. A mic holder it doesn't know goes to the diagnostic log.
    public func knows(_ bundleID: String) -> Bool {
        Detector.alwaysIgnored.contains(bundleID) || ignoredApps.contains(bundleID)
            || neverIgnored.contains(bundleID) || providers[bundleID] != nil
    }
}
