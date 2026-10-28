import Foundation

/// A Meeting that matches a Search, with the line to show under its row when the match is in the body.
public struct SearchHit: Equatable, Sendable {
    public var meeting: ListedMeeting
    public var snippet: String?
}

extension Library {
    /// Case- and diacritic-insensitive Search over the title, the participants and the body, newest first.
    public func search(_ query: String) -> [SearchHit] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return meetings.map { SearchHit(meeting: $0, snippet: nil) } }
        return meetings.compactMap { meeting in
            if meeting.title.matches(query) || meeting.participants.contains(where: { $0.name.matches(query) }) {
                return SearchHit(meeting: meeting, snippet: nil)
            }
            for line in meeting.searchLines {
                if let match = line.matchRange(query) {
                    return SearchHit(meeting: meeting, snippet: Self.cropped(line, before: match))
                }
            }
            return nil
        }
    }

    static let snippetLead = 40
    static let snippetContext = 30

    /// Keeps a match far into a long line visible under the row: "…words just before the match".
    private static func cropped(_ line: String, before match: Range<String.Index>) -> String {
        guard line.distance(from: line.startIndex, to: match.lowerBound) > snippetLead else { return line }
        let contextStart = line.index(match.lowerBound, offsetBy: -snippetContext)
        var start = contextStart
        if line[line.index(before: start)] != " " {
            start = line[start...].firstIndex(of: " ").map(line.index(after:)) ?? contextStart
        }
        return "…" + line[start...]
    }
}

extension String {
    fileprivate func matchRange(_ query: String) -> Range<String.Index>? {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    }

    fileprivate func matches(_ query: String) -> Bool {
        matchRange(query) != nil
    }
}
