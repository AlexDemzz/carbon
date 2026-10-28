import Foundation

extension Library {
    /// Names the Speaker whose Turn headers read `label`. Only those header lines change in the file: the text,
    /// the Turns and everything else stay as they are, Local Edits included.
    ///
    /// A Speaker with at least 10 s of speech is remembered as a Voice Print of `name`; `email` is the attendee's.
    public func renameSpeaker(_ id: UUID, label: String, name: String, email: String? = nil) throws {
        guard label != TranscriptBuilder.me, let name = TranscriptBuilder.label(forName: name) else {
            throw LibraryError.invalidSpeakerName
        }
        let links = try rememberVoices(of: entry(id, in: loadIndex()), label: label, name: name, email: email)
        var isNewParticipant = false
        try writeSurgically(id, updating: { entry in
            isNewParticipant = !entry.participants.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if isNewParticipant { entry.participants.append(Participant(name: name)) }
            // A Them stream that isn't split has no `speakers` entry yet: its first naming records it as cluster `Them`.
            // That is every fallback Speaker, and Them in a meeting room whose call couldn't be diarized.
            if entry.transcript == .fallback || label == TranscriptBuilder.them,
               !entry.speakers.contains(where: { $0.label == label }) {
                entry.speakers.append(MeetingIndex.Speaker(label: label, cluster: TranscriptBuilder.them, speechSeconds: 0))
            }
            for position in entry.speakers.indices where entry.speakers[position].label == label {
                entry.speakers[position].label = name
                entry.speakers[position].name = name
                entry.speakers[position].match = .user
                entry.speakers[position].voicePrintId = links[entry.speakers[position].cluster] ?? nil
            }
        }) { markdown in
            let renamed = TranscriptBuilder.renamingSpeaker(label, to: name, in: markdown)
            return isNewParticipant ? MarkdownFile.addingParticipant(name, to: renamed) : renamed
        }
    }
}

extension MarkdownFile {
    /// The file with `name` appended to the frontmatter `participants`, every other line as it was.
    static func addingParticipant(_ name: String, to markdown: String) -> String {
        var lines = markdown.linesKeepingEnds
        func isFence(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }
        guard let first = lines.first, isFence(first),
              let end = lines.indices.dropFirst().first(where: { isFence(lines[$0]) })
        else { return markdown }
        let lineEnd = first.hasSuffix("\r") ? "\r" : ""
        let item = "  - \(yaml(name))\(lineEnd)"
        guard let key = lines[1..<end].firstIndex(where: { $0.hasPrefix("participants:") }) else {
            lines.insert(contentsOf: ["participants:\(lineEnd)", item], at: end)
            return lines.joined(separator: "\n")
        }
        switch lines[key].dropFirst("participants:".count).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "": break
        case "[]": lines[key] = "participants:\(lineEnd)"
        default: return markdown  // A flow list the person wrote: theirs to keep.
        }
        var last = key
        while last + 1 < end, lines[last + 1].trimmingCharacters(in: .whitespaces).hasPrefix("- ") { last += 1 }
        lines.insert(item, at: last + 1)
        return lines.joined(separator: "\n")
    }
}

extension TranscriptBuilder {
    /// The file with `label` replaced by `name` in the `## Transcript` Turn headers that read `label`.
    static func renamingSpeaker(_ label: String, to name: String, in markdown: String) -> String {
        var inTranscript = false
        return markdown.linesKeepingEnds.map { line in
            if line.hasPrefix("## ") {
                inTranscript = line.trimmingCharacters(in: .whitespacesAndNewlines) == "## Transcript"
                return line
            }
            guard inTranscript, let header = line.prefixMatch(of: header), header.output.1 == label else { return line }
            return "**\(name)** [\(header.output.2)] " + line[header.range.upperBound...]
        }.joined(separator: "\n")
    }
}
