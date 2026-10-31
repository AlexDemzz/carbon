import Foundation

/// The Meeting Languages the person checked in Settings › Languages, and the default one Meetings start in: the last
/// Meeting's while it is checked, else the first checked.
/// Languages are kept by BCP 47 identifier, in the order `listed(_:)` gives; at least one stays checked.
public struct MeetingLanguages: Equatable, Sendable, Codable {
    private var chosenIDs: [String]
    private var defaultID: String

    private enum CodingKeys: String, CodingKey {
        case chosenIDs = "chosen"
        case defaultID = "default"
    }

    /// Only `defaultLanguage` checked.
    public init(default language: Locale) {
        defaultID = Self.id(language)
        chosenIDs = [defaultID]
    }

    /// The first launch's: the Mac's languages (`preferred`, in the Mac's order), each as a supported variant, one per
    /// language code, at most `cap` of them, the first the default. en-US when none is supported.
    public static func seeded(from preferred: [Locale], supported: [Locale], cap: Int) -> MeetingLanguages {
        let supported = listed(supported)
        var seenCodes: Set<String> = []
        let seeds = preferred.compactMap { variant(of: $0, in: supported) }.filter {
            seenCodes.insert($0.language.languageCode?.identifier ?? id($0)).inserted
        }
        var languages = MeetingLanguages(default: seeds.first ?? Locale(identifier: "en_US"))
        for language in seeds.prefix(cap).dropFirst() {
            languages.set(language, chosen: true)
        }
        return languages
    }

    /// `language` itself, else its language in its main region (en-FR → en-US), else its language's first listed
    /// variant. SpeechTranscriber's `supportedLocale(equivalentTo:)` isn't used: it maps en-FR to en-IN or en-NZ,
    /// differently from one call to the next.
    private static func variant(of language: Locale, in supported: [Locale]) -> Locale? {
        if let exact = supported.first(where: { id($0) == id(language) }) { return exact }
        guard let code = language.language.languageCode else { return nil }
        let main = Locale.Language(languageCode: code, script: language.language.script, region: nil).maximalIdentifier
        if let region = Locale.Language(identifier: main).region,
            let inMainRegion = supported.first(where: { id($0) == "\(code.identifier)-\(region.identifier)" })
        {
            return inMainRegion
        }
        return supported.first { $0.language.languageCode == code }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultID = try container.decode(String.self, forKey: .defaultID)
        chosenIDs = Self.sorted(Set(try container.decode([String].self, forKey: .chosenIDs) + [defaultID]))
    }

    /// The checked languages, in list order.
    public var chosen: [Locale] { chosenIDs.map(Self.locale) }

    /// The language the next Meeting starts in.
    public var defaultLanguage: Locale { Self.locale(defaultID) }

    /// The Meeting just transcribed in `language`: the next one starts in it, unless it is unchecked.
    public mutating func meetingWasIn(_ language: Locale) {
        if isChosen(language) { defaultID = Self.id(language) }
    }

    public func isChosen(_ language: Locale) -> Bool {
        chosenIDs.contains(Self.id(language))
    }

    /// False for the last checked language: there is always one to transcribe in.
    public func canUncheck(_ language: Locale) -> Bool {
        !isChosen(language) || chosenIDs.count > 1
    }

    /// Checks or unchecks a language. Unchecking the default makes the first checked language the default.
    public mutating func set(_ language: Locale, chosen: Bool) {
        let id = Self.id(language)
        if chosen {
            chosenIDs = Self.sorted(Set(chosenIDs + [id]))
        } else if canUncheck(language) {
            chosenIDs.removeAll { $0 == id }
            if defaultID == id { defaultID = chosenIDs[0] }
        }
    }

    /// "French", or "English (United Kingdom)" when another checked language would also be "English".
    public func name(of language: Locale, in displayLocale: Locale = .current) -> String {
        let code = language.language.languageCode?.identifier
        if sharesCode(language), let full = displayLocale.localizedString(forIdentifier: language.identifier) {
            return full
        }
        return code.flatMap { displayLocale.localizedString(forLanguageCode: $0) } ?? Self.id(language)
    }

    private func sharesCode(_ language: Locale) -> Bool {
        let id = Self.id(language)
        let code = language.language.languageCode?.identifier
        return chosenIDs.contains { $0 != id && Self.locale($0).language.languageCode?.identifier == code }
    }

    /// The supported languages in the order Settings lists them: English, then French variants (the US-first
    /// launch languages, en-US and fr-FR leading), then the rest by identifier.
    public static func listed(_ supported: [Locale]) -> [Locale] {
        sorted(Set(supported.map(id))).map(locale)
    }

    private static func sorted(_ ids: Set<String>) -> [String] {
        ids.sorted { (rank($0), $0) < (rank($1), $1) }
    }

    private static func rank(_ id: String) -> Int {
        switch id {
        case "en-US": 0
        case _ where id.hasPrefix("en-"): 1
        case "fr-FR": 2
        case _ where id.hasPrefix("fr-"): 3
        default: 4
        }
    }

    private static func id(_ language: Locale) -> String {
        language.identifier(.bcp47)
    }

    private static func locale(_ id: String) -> Locale {
        Locale(identifier: Locale.identifier(.icu, from: id))
    }
}
