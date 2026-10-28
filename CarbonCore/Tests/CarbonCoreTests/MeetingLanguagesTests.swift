import CarbonCore
import Foundation
import Testing

struct MeetingLanguagesTests {
    func bcp47(_ languages: [Locale]) -> [String] {
        languages.map { $0.identifier(.bcp47) }
    }

    func locales(_ identifiers: String...) -> [Locale] {
        identifiers.map(Locale.init(identifier:))
    }

    @Test func theListPutsEnglishThenFrenchVariantsFirstWithTheUSAndFranceLeading() {
        let supported = locales("de-DE", "fr-CA", "en-GB", "ja-JP", "en-US", "fr-FR", "es-ES", "en-AU")

        #expect(bcp47(MeetingLanguages.listed(supported)) == [
            "en-US", "en-AU", "en-GB", "fr-FR", "fr-CA", "de-DE", "es-ES", "ja-JP",
        ])
    }

    @Test func checkedLanguagesFollowTheListOrder() {
        var languages = MeetingLanguages(default: Locale(identifier: "fr-FR"))

        languages.set(Locale(identifier: "de-DE"), chosen: true)
        languages.set(Locale(identifier: "en-US"), chosen: true)

        #expect(bcp47(languages.chosen) == ["en-US", "fr-FR", "de-DE"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "fr-FR")
    }

    @Test func uncheckingTheDefaultMakesTheFirstCheckedLanguageTheDefault() {
        var languages = MeetingLanguages(default: Locale(identifier: "fr-FR"))
        languages.set(Locale(identifier: "es-ES"), chosen: true)
        languages.set(Locale(identifier: "en-GB"), chosen: true)

        languages.set(Locale(identifier: "fr-FR"), chosen: false)

        #expect(bcp47(languages.chosen) == ["en-GB", "es-ES"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "en-GB")
    }

    @Test func theLastCheckedLanguageStaysChecked() {
        var languages = MeetingLanguages(default: Locale(identifier: "en-US"))

        languages.set(Locale(identifier: "en-US"), chosen: false)

        #expect(bcp47(languages.chosen) == ["en-US"])
        #expect(!languages.canUncheck(Locale(identifier: "en-US")))
    }

    @Test func makingAnUncheckedLanguageTheDefaultChecksIt() {
        var languages = MeetingLanguages(default: Locale(identifier: "en-US"))

        languages.defaultLanguage = Locale(identifier: "fr-FR")

        #expect(bcp47(languages.chosen) == ["en-US", "fr-FR"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "fr-FR")
    }

    @Test func theSwitchChoicesAreTheOtherCheckedLanguages() {
        var languages = MeetingLanguages(default: Locale(identifier: "en-US"))
        languages.set(Locale(identifier: "fr-FR"), chosen: true)
        languages.set(Locale(identifier: "es-ES"), chosen: true)

        #expect(bcp47(languages.others(than: Locale(identifier: "fr_FR"))) == ["en-US", "es-ES"])
    }

    @Test func aLanguageIsNamedByItsRegionOnlyWhenAnotherCheckedVariantSharesItsName() {
        var languages = MeetingLanguages(default: Locale(identifier: "en-US"))
        languages.set(Locale(identifier: "en-GB"), chosen: true)
        languages.set(Locale(identifier: "fr-FR"), chosen: true)
        let english = Locale(identifier: "en_US")

        #expect(languages.name(of: Locale(identifier: "fr-FR"), in: english) == "French")
        #expect(languages.name(of: Locale(identifier: "en-GB"), in: english) == "English (United Kingdom)")
        #expect(languages.name(of: Locale(identifier: "en-US"), in: english) == "English (United States)")
    }

    @Test func theSettingSurvivesARoundTripThroughItsStoredForm() throws {
        var languages = MeetingLanguages(default: Locale(identifier: "en-US"))
        languages.set(Locale(identifier: "fr-CA"), chosen: true)
        languages.defaultLanguage = Locale(identifier: "fr-CA")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let stored = try encoder.encode(languages)

        #expect(String(decoding: stored, as: UTF8.self) == #"{"chosen":["en-US","fr-CA"],"default":"fr-CA"}"#)
        #expect(try JSONDecoder().decode(MeetingLanguages.self, from: stored) == languages)
    }
}
