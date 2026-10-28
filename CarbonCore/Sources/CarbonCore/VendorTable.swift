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
