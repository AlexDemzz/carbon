import Foundation

extension Participant {
    /// An attendee the calendar knew only by email: their name is that email.
    var isNamedByEmail: Bool {
        email?.caseInsensitiveCompare(name) == .orderedSame
    }

    /// Whether `name` and `email` are this person: by email when both have one, by name otherwise.
    func isPerson(named name: String, email: String?) -> Bool {
        if let email, let own = self.email { return own.caseInsensitiveCompare(email) == .orderedSame }
        return self.name.caseInsensitiveCompare(name) == .orderedSame
    }

    /// This person and `other` as one: a real name beats an email, then this one's name and email come first.
    func merging(_ other: Participant) -> Participant {
        Participant(name: isNamedByEmail && !other.isNamedByEmail ? other.name : name, email: email ?? other.email)
    }
}

extension VoicePrint {
    /// The person the print names, as a Participant.
    var person: Participant { Participant(name: name, email: email) }
}

extension Library {
    /// "Same Person As": `source` and `target` become one Participant in `target`'s place, named as `merging(_:)`
    /// says. The Turn headers of either one are renamed to that name, and the Voice Prints either one was heard as
    /// become one. Other Meetings' files stay as they are.
    ///
    /// Throws when the file's `participants` isn't a block list holding both, e.g. a flow list the person wrote:
    /// the file and `meetings.json` would no longer agree.
    public func mergeParticipant(_ id: UUID, _ source: Participant, into target: Participant) throws {
        let entry = try entry(id, in: loadIndex())
        guard source != target, entry.participants.contains(source), entry.participants.contains(target) else { return }
        let merged = target.merging(source)
        guard let label = TranscriptBuilder.label(forName: merged.name) else { throw LibraryError.invalidSpeakerName }
        let labels = Set([source.name, target.name].compactMap(TranscriptBuilder.label(forName:)) + [label])
        if let markdown = try? String(contentsOf: folder.appending(path: entry.file), encoding: .utf8),
           MarkdownFile.mergingParticipant(source, into: target, as: merged, in: markdown) == nil {
            throw LibraryError.participantsNotInFile
        }
        try mergeVoicePrints(
            of: [source, target], as: merged,
            linked: Set(entry.speakers.filter { labels.contains($0.label) }.compactMap(\.voicePrintId)))
        try writeSurgically(id, updating: { entry in
            entry.participants = entry.participants.compactMap { $0 == target ? merged : $0 == source ? nil : $0 }
            for position in entry.speakers.indices where labels.contains(entry.speakers[position].label) {
                entry.speakers[position].label = label
                entry.speakers[position].name = label
            }
        }) { markdown in
            MarkdownFile.mergingParticipant(source, into: target, as: merged, in: markdown).map { rewritten in
                labels.subtracting([label]).reduce(rewritten) { TranscriptBuilder.renamingSpeaker($1, to: label, in: $0) }
            }
        }
    }

    /// Makes the Voice Prints of `people`, and those `linked`, one. The one heard in the most Meetings keeps its
    /// voice and takes `merged`'s name and email; every Meeting that linked another links it instead.
    private func mergeVoicePrints(of people: [Participant], as merged: Participant, linked: Set<UUID>) throws {
        var index = try loadIndex()
        var kept: UUID?
        var gone: Set<UUID> = []
        try voicePrints.update { prints in
            let same = prints.indices.filter { position in
                let print = prints[position]
                return !print.owner
                    && (linked.contains(print.id) || people.contains { $0.isPerson(named: print.name, email: print.email) })
            }
            guard let keep = same.max(by: { prints[$0].meetings < prints[$1].meetings }) else { return }
            let ids = Set(same.map { prints[$0].id })
            // A Meeting that heard two of them counts once.
            let overlap = index.meetings.reduce(0) { count, meeting in
                count + max(0, ids.intersection(meeting.speakers.compactMap(\.voicePrintId)).count - 1)
            }
            for position in same where position != keep {
                prints[keep].meetings += prints[position].meetings
                prints[keep].createdAt = min(prints[keep].createdAt, prints[position].createdAt)
                prints[keep].lastHeardAt = max(prints[keep].lastHeardAt, prints[position].lastHeardAt)
            }
            prints[keep].meetings -= overlap
            prints[keep].name = merged.name
            prints[keep].email = merged.email ?? prints[keep].email
            kept = prints[keep].id
            gone = ids.subtracting([prints[keep].id])
            prints.removeAll { gone.contains($0.id) }
        }
        guard let kept, !gone.isEmpty else { return }
        var changed: [MeetingIndex.Entry] = []
        for meeting in index.meetings.indices {
            var relinked = false
            for speaker in index.meetings[meeting].speakers.indices {
                guard let link = index.meetings[meeting].speakers[speaker].voicePrintId, gone.contains(link) else {
                    continue
                }
                index.meetings[meeting].speakers[speaker].voicePrintId = kept
                relinked = true
            }
            if relinked { changed.append(index.meetings[meeting]) }
        }
        guard !changed.isEmpty else { return }
        try save(index)
        changed.forEach(refreshListed)
    }
}

extension MarkdownFile {
    /// The file with `target`'s frontmatter `participants` item written as `merged` and `source`'s removed, every
    /// other line as it was. Nil unless `participants` is a block list holding both.
    static func mergingParticipant(
        _ source: Participant, into target: Participant, as merged: Participant, in markdown: String
    ) -> String? {
        guard let frontmatter = frontmatterLines(markdown),
              let key = frontmatter.firstIndex(where: { $0.hasPrefix("participants:") }),
              frontmatter[key].dropFirst("participants:".count).trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        let items = frontmatter[(key + 1)...].prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
        func reads(_ position: Int, as participant: Participant) -> Bool {
            self.participant(scalar(frontmatter[position].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                == participant
        }
        guard let targetLine = items.indices.first(where: { reads($0, as: target) }),
              let sourceLine = items.indices.first(where: { reads($0, as: source) })
        else { return nil }
        var lines = markdown.linesKeepingEnds
        let lineEnd = lines[targetLine].hasSuffix("\r") ? "\r" : ""
        lines[targetLine] = "  - \(yaml(item(merged)))\(lineEnd)"
        lines.remove(at: sourceLine)
        return lines.joined(separator: "\n")
    }
}
