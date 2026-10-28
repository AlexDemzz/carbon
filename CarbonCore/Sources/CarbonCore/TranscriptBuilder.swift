import Foundation

/// One stretch of a Transcript attributed to a single Speaker, stamped with the time it starts.
public struct Turn: Equatable, Sendable {
    public var speaker: String
    public var start: TimeInterval
    public var text: String
}

/// Turns the Transcriber's words into Turns and the `## Transcript` body.
public enum TranscriptBuilder {
    static let me = "Me"
    static let silenceBetweenTurns: TimeInterval = 10

    public static func turns(me words: [TranscribedWord]) -> [Turn] {
        var turns: [Turn] = []
        var previousEnd: TimeInterval?
        for word in words {
            if let previousEnd, word.start - previousEnd < silenceBetweenTurns, !turns.isEmpty {
                turns[turns.count - 1].text += " " + word.text
            } else {
                turns.append(Turn(speaker: me, start: word.start, text: word.text))
            }
            previousEnd = word.end
        }
        return turns
    }

    /// The `## Transcript` section: one `**Speaker** [m:ss] text` line per Turn, separated by blank lines.
    public static func body(_ turns: [Turn]) -> String {
        let lines = turns.map { "**\($0.speaker)** [\(MeetingFormat.clock($0.start))] \(capitalized($0.text))" }
        return (["## Transcript"] + lines).joined(separator: "\n\n") + "\n"
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
