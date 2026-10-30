import CarbonCore
import Foundation
import Testing

/// Boundary cases from the diarization-eval Voice Print distances: the farthest same-person pair (0.237) and the
/// nearest impostor (0.312).
struct VoicePrintMatcherTests {
    static let model = "fluidaudio/community-1@0.17.7"
    let sam = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let dana = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    /// A unit vector at cosine distance `distance` from [1, 0, 0], on the side `sign` of the y axis.
    func embedding(atDistance distance: Double, sign: Double = 1) -> [Float] {
        let cosine = 1 - distance
        return [Float(cosine), Float(sign * (1 - cosine * cosine).squareRoot()), 0]
    }

    func print(_ id: UUID, _ name: String, at distance: Double, sign: Double = 1, model: String = Self.model)
        -> VoicePrint
    {
        VoicePrint(
            id: id, name: name, model: model, centroid: embedding(atDistance: distance, sign: sign),
            createdAt: date("2026-10-01T10:00:00Z"))
    }

    func cluster(_ id: String, seconds: Double = 60) -> Diarization.Cluster {
        .init(id: id, voice: [1, 0, 0], speechSeconds: seconds)
    }

    @Test func theFarthestSamePersonPairStillMatches() {
        let matches = VoicePrintMatcher.match(
            [cluster("S1")], prints: [print(sam, "Sam Rivera", at: 0.237)], model: Self.model)

        #expect(matches == ["S1": .init(printID: sam, distance: 0.237)])
    }

    @Test func theNearestImpostorDoesNotMatchButItsDistanceIsKept() {
        let matches = VoicePrintMatcher.match(
            [cluster("S1")], prints: [print(sam, "Sam Rivera", at: 0.312)], model: Self.model)

        #expect(matches == ["S1": .init(printID: nil, distance: 0.312)])
    }

    @Test func aRunnerUpWithinTheMarginLeavesTheSpeakerUnnamed() {
        let matches = VoicePrintMatcher.match(
            [cluster("S1")],
            prints: [print(sam, "Sam Rivera", at: 0.05), print(dana, "Dana Park", at: 0.14, sign: -1)],
            model: Self.model)

        #expect(matches == ["S1": .init(printID: nil, distance: 0.05)])
    }

    @Test func aRunnerUpPastTheMarginLetsTheBestMatch() {
        let matches = VoicePrintMatcher.match(
            [cluster("S1")],
            prints: [print(sam, "Sam Rivera", at: 0.05), print(dana, "Dana Park", at: 0.16, sign: -1)],
            model: Self.model)

        #expect(matches == ["S1": .init(printID: sam, distance: 0.05)])
    }

    @Test func printsFromAnotherModelAreIgnored() {
        let matches = VoicePrintMatcher.match(
            [cluster("S1")],
            prints: [
                print(sam, "Sam Rivera", at: 0.0, model: "fluidaudio/community-1@0.16.0"),
                print(dana, "Dana Park", at: 0.2),
            ],
            model: Self.model)

        #expect(matches == ["S1": .init(printID: dana, distance: 0.2)])
    }

    @Test func eachPrintNamesOneClusterTheClosest() {
        let matches = VoicePrintMatcher.match(
            [
                .init(id: "S1", voice: embedding(atDistance: 0.2), speechSeconds: 40),
                .init(id: "S2", voice: embedding(atDistance: 0.1, sign: -1), speechSeconds: 40),
            ],
            prints: [VoicePrint(
                id: sam, name: "Sam Rivera", model: Self.model, centroid: [1, 0, 0],
                createdAt: date("2026-10-01T10:00:00Z"))],
            model: Self.model)

        #expect(matches == [
            "S1": .init(printID: nil, distance: 0.2),
            "S2": .init(printID: sam, distance: 0.1),
        ])
    }

    @Test func aClusterWithLessThanTenSecondsOfSpeechIsNotMatched() {
        let matches = VoicePrintMatcher.match(
            [cluster("S1", seconds: 9.9)], prints: [print(sam, "Sam Rivera", at: 0.05)], model: Self.model)

        #expect(matches == [:])
    }

    @Test func aClusterWithNoCleanVoiceIsNotMatchedHoweverCloseAllItsSpeechIs() {
        let matches = VoicePrintMatcher.match(
            [.init(id: "S1", centroid: [1, 0, 0], speechSeconds: 60)],
            prints: [print(sam, "Sam Rivera", at: 0)], model: Self.model)

        #expect(matches == [:])
    }

    @Test func aClusterIsMatchedByItsCleanVoiceNotAllItsSpeech() {
        let matches = VoicePrintMatcher.match(
            [.init(id: "S1", centroid: [0, 0, 1], voice: [1, 0, 0], speechSeconds: 60)],
            prints: [print(sam, "Sam Rivera", at: 0.1)], model: Self.model)

        #expect(matches == ["S1": .init(printID: sam, distance: 0.1)])
    }
}
