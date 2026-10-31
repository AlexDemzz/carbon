import CarbonCore
import Foundation
import Testing

struct LexicalVoteTests {
    let english = Locale(identifier: "en_US")
    let french = Locale(identifier: "fr_FR")
    let german = Locale(identifier: "de_DE")

    @Test func threeOfTheLastFourChunksInAnotherLanguageCallForIt() {
        var vote = LexicalVote(current: french)

        #expect(vote.add([english: 0.99, french: 0.01]) == nil)
        #expect(vote.add([english: 0.42, french: 0.58]) == nil)
        #expect(vote.add([english: 1.0]) == nil)
        #expect(vote.add([english: 0.97, french: 0.03]) == english)
    }

    @Test func aChunkUnder90PercentSureCountsForNoLanguage() {
        var vote = LexicalVote(current: french)

        for _ in 1...6 {
            #expect(vote.add([english: 0.89, french: 0.11]) == nil)
        }
    }

    @Test func chunksInTheCurrentLanguageNeverCallForASwitch() {
        var vote = LexicalVote(current: french)

        for _ in 1...6 {
            #expect(vote.add([french: 0.99, english: 0.01]) == nil)
        }
    }

    @Test func chunksSplitBetweenTwoOtherLanguagesAgreeOnNeither() {
        var vote = LexicalVote(current: french)

        #expect(vote.add([english: 0.99]) == nil)
        #expect(vote.add([german: 0.99]) == nil)
        #expect(vote.add([english: 0.99]) == nil)
        #expect(vote.add([german: 0.99]) == nil)
        #expect(vote.add([english: 0.99]) == nil, "2 English and 2 German among the last four")
    }

    @Test func onlyTheLastFourChunksCount() {
        var vote = LexicalVote(current: french)

        #expect(vote.add([english: 0.99]) == nil)
        #expect(vote.add([english: 0.99]) == nil)
        #expect(vote.add([french: 0.99]) == nil)
        #expect(vote.add([french: 0.99]) == nil)
        #expect(vote.add([english: 0.99]) == nil, "the first two English chunks fell out of the last four")
        #expect(vote.add([english: 0.99]) == nil)
        #expect(vote.add([english: 0.99]) == english)
    }

    @Test func aResetVoteNeedsThreeFreshChunks() {
        var vote = LexicalVote(current: french)
        _ = vote.add([english: 0.99])
        _ = vote.add([english: 0.99])

        vote.reset()

        #expect(vote.add([english: 0.99]) == nil)
        #expect(vote.add([english: 0.99]) == nil)
        #expect(vote.add([english: 0.99]) == english)
    }
}
