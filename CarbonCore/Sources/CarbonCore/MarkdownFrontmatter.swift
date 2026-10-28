import Foundation

/// Reads back the frontmatter fields the person may edit by hand, the way YAML would.
extension MarkdownFile {
    /// The frontmatter `title`, or nil when it has none.
    static func title(in markdown: String) -> String? {
        frontmatterLines(markdown)?.lazy.compactMap { line in
            line.hasPrefix("title:") ? scalar(line.dropFirst("title:".count)) : nil
        }.first
    }

    /// The frontmatter `participants`, as a block or a flow list, or nil when it has none or can't be read.
    static func participants(in markdown: String) -> [Participant]? {
        guard let lines = frontmatterLines(markdown),
              let key = lines.firstIndex(where: { $0.hasPrefix("participants:") })
        else { return nil }
        let value = lines[key].dropFirst("participants:".count).trimmingCharacters(in: .whitespaces)
        let items: [String]
        if value.isEmpty {
            items = lines[(key + 1)...]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .prefix { $0.hasPrefix("- ") }
                .map { scalar($0.dropFirst(2)) }
        } else if value.hasPrefix("["), value.hasSuffix("]") {
            items = flowItems(value.dropFirst().dropLast()).map(scalar)
        } else {
            return nil
        }
        return items.filter { !$0.isEmpty }.map(participant)
    }

    /// `Name <email>` as `yaml(_:)` writes an attendee, or a bare name.
    private static func participant(_ entry: String) -> Participant {
        guard let match = entry.wholeMatch(of: #/(.*?)\s*<([^<>\s]+)>/#), !match.output.1.isEmpty else {
            return Participant(name: entry)
        }
        return Participant(name: String(match.output.1), email: String(match.output.2))
    }

    /// A YAML scalar: double-quoted with escapes, single-quoted, or plain up to a ` #` comment.
    private static func scalar(_ raw: some StringProtocol) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            var unescaped = ""
            var escaping = false
            for character in value.dropFirst().dropLast() {
                if escaping {
                    unescaped.append(character == "n" ? "\n" : character == "t" ? "\t" : character)
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else {
                    unescaped.append(character)
                }
            }
            return unescaped
        }
        if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
            return value.dropFirst().dropLast().replacingOccurrences(of: "''", with: "'")
        }
        let comment = value.range(of: " #")?.lowerBound ?? value.endIndex
        return value[..<comment].trimmingCharacters(in: .whitespaces)
    }

    /// The items of a flow list's inside, split at the commas outside quotes.
    private static func flowItems(_ inside: some StringProtocol) -> [String] {
        var items: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for character in inside {
            current.append(character)
            if escaping {
                escaping = false
            } else if quote == "\"", character == "\\" {
                escaping = true
            } else if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "," {
                items.append(String(current.dropLast()))
                current = ""
            }
        }
        items.append(current)
        return items
    }
}
