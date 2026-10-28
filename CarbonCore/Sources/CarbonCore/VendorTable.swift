import Foundation

/// The vendor strings Detection depends on, shipped as data in each release (`Resources/VendorTable.json`).
/// The person's own additions live in Settings, never here.
public struct VendorTable: Sendable, Decodable {
    /// Apps whose mic use never counts toward Detection: dictation tools, screen recorders, voice assistants.
    public var ignoredApps: Set<String>
    /// Call apps and helpers that are never ignored, even when the person adds them to Ignored Apps.
    public var neverIgnored: Set<String>
    /// Native Meeting App bundle ID → Provider.
    public var providers: [String: String]
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

    /// Whether the table says anything about `bundleID`. A mic holder it doesn't know goes to the diagnostic log.
    public func knows(_ bundleID: String) -> Bool {
        Detector.alwaysIgnored.contains(bundleID) || ignoredApps.contains(bundleID)
            || neverIgnored.contains(bundleID) || providers[bundleID] != nil
    }
}
