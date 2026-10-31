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

    @Test func theNextMeetingStartsInTheLastMeetingsLanguage() {
        var languages = MeetingLanguages(default: Locale(identifier: "en-US"))
        languages.set(Locale(identifier: "fr-FR"), chosen: true)

        languages.meetingWasIn(Locale(identifier: "fr_FR"))

        #expect(languages.defaultLanguage.identifier(.bcp47) == "fr-FR")
    }

    @Test func aMeetingInAnUncheckedLanguageNeitherChecksItNorStartsTheNextOneInIt() {
        var languages = MeetingLanguages(default: Locale(identifier: "en-US"))
        languages.set(Locale(identifier: "fr-FR"), chosen: true)

        languages.meetingWasIn(Locale(identifier: "de-DE"))

        #expect(bcp47(languages.chosen) == ["en-US", "fr-FR"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "en-US")
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

    @Test func theFirstLaunchChecksTheMacsLanguagesWithTheFirstOneAsDefault() {
        let languages = MeetingLanguages.seeded(
            from: locales("fr-FR", "en-US"), supported: locales("en-US", "fr-FR", "de-DE"), cap: 5)

        #expect(bcp47(languages.chosen) == ["en-US", "fr-FR"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "fr-FR")
    }

    @Test func aMacLanguageSpeechTranscriberLacksIsLeftUnchecked() {
        let languages = MeetingLanguages.seeded(
            from: locales("nb-NO", "fr-FR"), supported: locales("en-US", "fr-FR"), cap: 5)

        #expect(bcp47(languages.chosen) == ["fr-FR"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "fr-FR")
    }

    @Test func onlyTheFirstOfTheMacsVariantsOfALanguageIsChecked() {
        let languages = MeetingLanguages.seeded(
            from: locales("en-GB", "fr-FR", "en-US", "fr-CA"),
            supported: locales("en-US", "en-GB", "fr-FR", "fr-CA"), cap: 5)

        #expect(bcp47(languages.chosen) == ["en-GB", "fr-FR"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "en-GB")
    }

    @Test func noMoreMacLanguagesAreCheckedThanCanBeReserved() {
        let languages = MeetingLanguages.seeded(
            from: locales("de-DE", "fr-FR", "es-ES"), supported: locales("en-US", "fr-FR", "de-DE", "es-ES"), cap: 2)

        #expect(bcp47(languages.chosen) == ["fr-FR", "de-DE"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "de-DE")
    }

    @Test func aMacWhoseLanguagesSpeechTranscriberLacksStartsInUSEnglish() {
        let languages = MeetingLanguages.seeded(from: locales("nb-NO"), supported: locales("en-US", "fr-FR"), cap: 5)

        #expect(bcp47(languages.chosen) == ["en-US"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "en-US")
    }

    @Test func aMacLanguageInARegionSpeechTranscriberLacksTakesItsLanguagesMainRegion() {
        let languages = MeetingLanguages.seeded(
            from: locales("en-FR", "de-FR", "zh-Hant-FR"),
            supported: locales("en-IN", "en-NZ", "en-US", "de-CH", "de-DE", "zh-CN", "zh-TW"), cap: 5)

        #expect(bcp47(languages.chosen) == ["en-US", "de-DE", "zh-TW"])
        #expect(languages.defaultLanguage.identifier(.bcp47) == "en-US")
    }

    @Test func aMacLanguageWithNoRegionAndItsVariantsInOtherRegionsAreOneLanguage() {
        let languages = MeetingLanguages.seeded(
            from: locales("en", "en-FR", "en-US"), supported: locales("en-IN", "en-GB", "en-US"), cap: 5)

        #expect(bcp47(languages.chosen) == ["en-US"])
    }

    @Test func aMacLanguageWhoseMainRegionSpeechTranscriberLacksTakesItsFirstListedVariant() {
        let languages = MeetingLanguages.seeded(
            from: locales("yue-Hant-HK"), supported: locales("en-US", "yue-CN"), cap: 5)

        #expect(bcp47(languages.chosen) == ["yue-CN"])
    }

    @Test func theSettingSurvivesARoundTripThroughItsStoredForm() throws {
        var languages = MeetingLanguages(default: Locale(identifier: "en-US"))
        languages.set(Locale(identifier: "fr-CA"), chosen: true)
        languages.meetingWasIn(Locale(identifier: "fr-CA"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let stored = try encoder.encode(languages)

        #expect(String(decoding: stored, as: UTF8.self) == #"{"chosen":["en-US","fr-CA"],"default":"fr-CA"}"#)
        #expect(try JSONDecoder().decode(MeetingLanguages.self, from: stored) == languages)
    }
}
