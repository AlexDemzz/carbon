import CarbonCore
import Foundation
import Testing

struct LanguageVoteTests {
    let english = Locale(identifier: "en_US")
    let french = Locale(identifier: "fr_FR")
    let labels: Set<String> = ["en", "fr", "oc", "iw", "de", "fa", "tl"]

    /// A window the classifier scored: each label's probability, as log-probabilities.
    func scored(_ probabilities: [String: Double]) -> [String: Double] {
        probabilities.mapValues(log)
    }

    @Test func decidesOnlyOnceThereIsEnoughSpeech() throws {
        var vote = try #require(LanguageVote(candidates: [english, french], labels: labels))
        let french = scored(["fr": 0.9, "en": 0.01])

        #expect(vote.add(french, speech: 4) == .undecided)
        #expect(vote.add(french, speech: 4) == .decided(self.french))
    }

    @Test func aWindowTheClassifierIsSureIsAnotherLanguageDoesNotCount() throws {
        var vote = try #require(LanguageVote(candidates: [english, french], labels: labels))
        let hebrew = scored(["iw": 0.9995, "en": 0.0004, "fr": 0.00001])
        let french = scored(["fr": 0.9, "en": 0.01])

        #expect(vote.add(hebrew, speech: 4) == .undecided)
        #expect(vote.add(hebrew, speech: 4) == .undecided, "8 s of Hebrew is not 8 s of English")
        #expect(vote.add(french, speech: 4) == .undecided, "the Hebrew didn't count toward the minimum speech")
        #expect(vote.add(french, speech: 4) == .decided(self.french))
    }

    @Test func accentedSpeechScatteredOverOtherLanguagesStillCounts() throws {
        var vote = try #require(LanguageVote(candidates: [french, english], labels: labels))
        // French-accented English, as measured on two Meetings: most of each window on unrelated languages.
        let persianLooking = scored(["fa": 0.86, "en": 0.007, "fr": 0.0001])
        let tagalogLooking = scored(["tl": 0.45, "en": 0.043, "fr": 0.005])

        #expect(vote.add(persianLooking, speech: 4) == .undecided)
        #expect(vote.add(tagalogLooking, speech: 4) == .decided(english))
    }

    @Test func givesUpAfterFortyWindowsInNoCandidateLanguage() throws {
        var vote = try #require(LanguageVote(candidates: [english, french], labels: labels))
        let german = scored(["de": 0.999, "en": 0.0005, "fr": 0.0002])

        for _ in 1...39 {
            #expect(vote.add(german, speech: 4) == .undecided)
        }
        #expect(vote.add(german, speech: 4) == .gaveUp, "a German Meeting isn't scored for its whole length")
    }

    @Test func aSmallLeadStaysUndecided() throws {
        var vote = try #require(LanguageVote(candidates: [english, french], labels: labels))
        let leaningFrench = scored(["fr": 0.6, "en": 0.4])

        for _ in 1...5 {
            #expect(vote.add(leaningFrench, speech: 4) == .undecided)
        }
    }

    @Test func aMeetingInAnUncheckedLanguageTheCandidatesSplitEvenlyIsNeverDecided() throws {
        var vote = try #require(LanguageVote(candidates: [english, french], labels: labels))
        let german = scored(["de": 0.95, "en": 0.02, "fr": 0.01])

        for _ in 1...14 {
            #expect(vote.add(german, speech: 4) == .undecided)
        }
        #expect(vote.add(german, speech: 4) == .gaveUp)
    }

    @Test func givesUpAfterAMinuteOfSpeechWithoutAClearLeader() throws {
        var vote = try #require(LanguageVote(candidates: [english, french], labels: labels))
        let leaningFrench = scored(["fr": 0.6, "en": 0.4])

        for _ in 1...14 {
            #expect(vote.add(leaningFrench, speech: 4) == .undecided)
        }
        #expect(vote.add(leaningFrench, speech: 4) == .gaveUp, "60 s of speech")
    }

    @Test func onlyTheCandidatesCountAndTheirScoresAreRenormalized() throws {
        var vote = try #require(LanguageVote(candidates: [english, french], labels: labels))
        // Degraded French, as the research note measured it: Occitan on top over 107 labels, French below, English
        // lower still. Between the candidates, French is a clear 30 to 1.
        let degradedFrench = scored(["oc": 0.6, "fr": 0.15, "en": 0.005])

        _ = vote.add(degradedFrench, speech: 4)
        #expect(vote.add(degradedFrench, speech: 4) == .decided(french))
    }

    @Test func aLeadEarlierWindowsContradictIsNotADecision() throws {
        var vote = try #require(LanguageVote(candidates: [english, french], labels: labels))

        _ = vote.add(scored(["en": 0.95, "fr": 0.05]), speech: 4)
        #expect(vote.add(scored(["fr": 0.95, "en": 0.05]), speech: 4) == .undecided)
    }

    @Test func withFewerThanTwoLanguagesItCanTellApartThereIsNoVote() {
        #expect(LanguageVote(candidates: [english], labels: labels) == nil)
        #expect(LanguageVote(candidates: [english, Locale(identifier: "en_GB")], labels: labels) == nil,
            "both are English to the classifier")
        #expect(LanguageVote(candidates: [english, Locale(identifier: "yue_CN")], labels: labels) == nil,
            "Cantonese has no label")
    }

    @Test func candidatesSharingALabelAreDecidedAsTheFirstOfThem() throws {
        let british = Locale(identifier: "en_GB")
        var vote = try #require(LanguageVote(candidates: [british, french, english], labels: labels))
        let english = scored(["en": 0.9, "fr": 0.01])

        _ = vote.add(english, speech: 4)
        #expect(vote.add(english, speech: 4) == .decided(british))
    }

    @Test func eachLocaleMapsToItsLanguageLabel() {
        #expect(LanguageVote.label(of: Locale(identifier: "en_US")) == "en")
        #expect(LanguageVote.label(of: Locale(identifier: "fr_CA")) == "fr")
        #expect(LanguageVote.label(of: Locale(identifier: "he_IL")) == "iw", "VoxLingua107 keeps the legacy code")
        #expect(LanguageVote.label(of: Locale(identifier: "nb_NO")) == "no")
    }
}
