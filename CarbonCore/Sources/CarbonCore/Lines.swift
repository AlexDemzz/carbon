import Foundation

extension String {
    /// The text cut at each `\n`, a `\r` before it kept on its line, so `joined(separator: "\n")` gives the text
    /// back. Not `split(separator: "\n")`: Swift reads `\r\n` as one Character, so it would never cut a CRLF file.
    var linesKeepingEnds: [String] {
        components(separatedBy: "\n")
    }

    /// The text's lines without their `\n` or `\r\n` ending.
    var lines: [String] {
        linesKeepingEnds.map(\.withoutCarriageReturn)
    }

    /// The line with the `\r` of a `\r\n` ending removed.
    var withoutCarriageReturn: String {
        hasSuffix("\r") ? String(dropLast()) : self
    }
}
