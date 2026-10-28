import Foundation

extension TranscriptBuilder {
    /// The anchored Turn header `**Speaker** [m:ss] `, as `body(_:)` writes it.
    static var header: Regex<(Substring, Substring, Substring)> {
        #/^\*\*(.+?)\*\* \[(\d+(?::\d{2}){1,2})\] /#
    }

    /// The Turns of a Meeting's `## Transcript` section. Lines without a header continue the Turn above them.
    public static func turns(inMarkdown markdown: String) -> [Turn] {
        var turns: [Turn] = []
        var inTranscript = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                inTranscript = line.trimmingCharacters(in: .whitespaces) == "## Transcript"
                continue
            }
            guard inTranscript else { continue }
            if let turn = turn(atHeaderOf: line) {
                turns.append(turn)
            } else if !turns.isEmpty, !line.allSatisfy(\.isWhitespace) {
                turns[turns.count - 1].text += "\n" + line
            }
        }
        return turns
    }

    /// The Turn a header line opens, with the text that follows the header on that line.
    static func turn(atHeaderOf line: Substring) -> Turn? {
        guard let match = line.prefixMatch(of: header) else { return nil }
        let start = match.output.2.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
        return Turn(speaker: String(match.output.1), start: TimeInterval(start), text: String(line[match.range.upperBound...]))
    }
}

extension Turn {
    /// The Turn's start as written in the file: `0:19`, `1:02:10`.
    public var elapsed: String {
        MeetingFormat.clock(start)
    }
}
