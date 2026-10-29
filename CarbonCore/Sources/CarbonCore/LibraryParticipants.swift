import Foundation

extension Participant {
    /// A Participant the calendar knew only by email: their name is that email.
    public var isNamedByEmail: Bool {
        email?.caseInsensitiveCompare(name) == .orderedSame
    }

    /// Whether `other` is this person: by email when both have one, by name otherwise.
    func isPerson(_ other: Participant) -> Bool {
        if let email, let otherEmail = other.email { return email.caseInsensitiveCompare(otherEmail) == .orderedSame }
        return name.caseInsensitiveCompare(other.name) == .orderedSame
    }

    /// This person and `other` as one: a real name beats an email, then this one's name and email come first.
    func merging(_ other: Participant) -> Participant {
        Participant(name: isNamedByEmail && !other.isNamedByEmail ? other.name : name, email: email ?? other.email)
    }
}

extension [Participant] {
    /// The first Participant who is `person`: by email first, then by name where one of them has no email.
    func firstIndex(ofPerson person: Participant) -> Int? {
        firstIndex { $0.email != nil && person.email != nil && $0.isPerson(person) } ?? firstIndex { $0.isPerson(person) }
    }
}

extension VoicePrint {
    /// The person the print names, as a Participant.
    public var person: Participant { Participant(name: name, email: email) }
}

extension Library {
    /// "Same Person As": `source` and `target` become one Participant in `target`'s place, named as `merging(_:)`
    /// says. The Turn headers of either one are renamed to that name, and the Voice Prints either one was heard as
    /// become one. Other Meetings' files stay as they are.
    ///
    /// Throws when the file's `participants` isn't a block list holding both, e.g. a flow list the person wrote:
    /// the file and `meetings.json` would no longer agree.
    public func mergeParticipant(_ id: UUID, _ source: Participant, into target: Participant) throws {
        guard source != target else { return }
        try replace(target, with: target.merging(source), removing: source, in: id)
    }

    /// "Edit Participant…": the Participant takes `name` and `email` as `person(name:email:voicePrints:)` reads
    /// them, and so do their Turn headers in this Meeting and their Voice Print.
    public func editParticipant(_ id: UUID, _ participant: Participant, name: String, email: String) throws {
        let edited = try person(
            name: name, email: email, voicePrints: Set(voicePrints(of: participant, in: id).map(\.id)))
        guard edited != participant else { return }
        try replace(participant, with: edited, removing: nil, in: id)
    }

    /// Settings › Voice Prints: the print takes `name` and `email` as `person(name:email:voicePrints:)` reads them.
    /// Meetings that named the voice keep the name they wrote.
    public func editVoicePrint(_ printID: UUID, name: String, email: String) throws {
        let edited = try person(name: name, email: email, voicePrints: [printID])
        try voicePrints.update { prints in
            guard let position = prints.firstIndex(where: { $0.id == printID && !$0.owner }) else { return }
            prints[position].name = edited.name
            prints[position].email = edited.email
        }
    }

    /// A person as typed: trimmed, the email lowercased, named by their email when the name is empty. Throws when
    /// both are empty, the email has no `@`, another Voice Print than `own` has the email, or the name is reserved.
    public func person(name: String, email: String, voicePrints own: Set<UUID>) throws -> Participant {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty || !email.isEmpty else { throw LibraryError.missingNameAndEmail }
        guard email.isEmpty || email.contains("@") else { throw LibraryError.invalidEmail }
        if !email.isEmpty, let other = voicePrints.prints.first(where: {
            !own.contains($0.id) && $0.email?.caseInsensitiveCompare(email) == .orderedSame
        }) {
            throw LibraryError.emailInUse(other.name)
        }
        let person = Participant(name: name.isEmpty ? email : name, email: email.isEmpty ? nil : email)
        guard TranscriptBuilder.label(forName: person.name) != nil else { throw LibraryError.invalidSpeakerName }
        return person
    }

    /// The Voice Prints `participant` was heard as in the Meeting, or is by email, or by name for a print with none.
    public func voicePrints(of participant: Participant, in id: UUID) -> [VoicePrint] {
        let linked = (try? entry(id, in: loadIndex())).map { entry in
            Set(entry.speakers.filter { $0.label == TranscriptBuilder.label(forName: participant.name) }
                .compactMap(\.voicePrintId))
        } ?? []
        return voicePrints.prints.filter { isVoicePrint($0, of: [participant], linked: linked) }
    }

    private func isVoicePrint(_ print: VoicePrint, of people: [Participant], linked: Set<UUID>) -> Bool {
        !print.owner && (linked.contains(print.id) || people.contains {
            (print.email == nil || $0.email != nil) && $0.isPerson(print.person)
        })
    }

    /// Writes `edited` in `target`'s place and removes `source`, in the index and surgically in the file; renames
    /// their Turn headers; makes their Voice Prints one, named as `edited`.
    private func replace(_ target: Participant, with edited: Participant, removing source: Participant?, in id: UUID) throws {
        let entry = try entry(id, in: loadIndex())
        let people = [target] + (source.map { [$0] } ?? [])
        guard people.allSatisfy(entry.participants.contains) else { return }
        guard let label = TranscriptBuilder.label(forName: edited.name) else { throw LibraryError.invalidSpeakerName }
        let labels = Set(people.map(\.name).compactMap(TranscriptBuilder.label(forName:)) + [label])
        if let markdown = try? String(contentsOf: folder.appending(path: entry.file), encoding: .utf8),
           MarkdownFile.replacingParticipant(target, with: edited, removing: source, in: markdown) == nil {
            throw LibraryError.participantsNotInFile
        }
        let linked = Set(entry.speakers.filter { labels.contains($0.label) }.compactMap(\.voicePrintId))
        try writeSurgically(id, updating: { entry in
            // Only the first of each, as in the file.
            if let position = entry.participants.firstIndex(of: target) { entry.participants[position] = edited }
            if let source, let position = entry.participants.firstIndex(of: source) {
                entry.participants.remove(at: position)
            }
            for position in entry.speakers.indices where labels.contains(entry.speakers[position].label) {
                entry.speakers[position].label = label
                entry.speakers[position].name = label
            }
        }) { markdown in
            MarkdownFile.replacingParticipant(target, with: edited, removing: source, in: markdown).map { rewritten in
                labels.subtracting([label]).reduce(rewritten) { TranscriptBuilder.renamingSpeaker($1, to: label, in: $0) }
            }
        }
        try mergeVoicePrints(of: people, as: edited, linked: linked, keepingEmail: source != nil)
    }

    /// Makes the Voice Prints of `people`, and those `linked`, one. The one heard in the most Meetings keeps its
    /// voice and takes `merged`'s name and email, or keeps its own email when `merged` has none and `keepingEmail`;
    /// every Meeting that linked another links it instead.
    private func mergeVoicePrints(
        of people: [Participant], as merged: Participant, linked: Set<UUID>, keepingEmail: Bool
    ) throws {
        var index = try loadIndex()
        var survivorID: UUID?
        var gone: Set<UUID> = []
        try voicePrints.update { prints in
            let theirs = prints.indices.filter { isVoicePrint(prints[$0], of: people, linked: linked) }
            guard let survivor = theirs.max(by: { prints[$0].meetings < prints[$1].meetings }) else { return }
            let ids = Set(theirs.map { prints[$0].id })
            // A Meeting that heard two of them counts once.
            let overlap = index.meetings.reduce(0) { count, meeting in
                count + max(0, ids.intersection(meeting.speakers.compactMap(\.voicePrintId)).count - 1)
            }
            for position in theirs where position != survivor {
                prints[survivor].meetings += prints[position].meetings
                prints[survivor].createdAt = min(prints[survivor].createdAt, prints[position].createdAt)
                prints[survivor].lastHeardAt = max(prints[survivor].lastHeardAt, prints[position].lastHeardAt)
            }
            prints[survivor].meetings -= overlap
            prints[survivor].name = merged.name
            prints[survivor].email = keepingEmail ? merged.email ?? prints[survivor].email : merged.email
            survivorID = prints[survivor].id
            gone = ids.subtracting([prints[survivor].id])
            prints.removeAll { gone.contains($0.id) }
        }
        guard let survivorID, !gone.isEmpty else { return }
        var changed: [MeetingIndex.Entry] = []
        for meeting in index.meetings.indices {
            var relinked = false
            for speaker in index.meetings[meeting].speakers.indices {
                guard let link = index.meetings[meeting].speakers[speaker].voicePrintId, gone.contains(link) else {
                    continue
                }
                index.meetings[meeting].speakers[speaker].voicePrintId = survivorID
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
    /// The file with `target`'s frontmatter `participants` item written as `edited` and `source`'s removed, every
    /// other line as it was. Nil unless `participants` is a block list holding them.
    static func replacingParticipant(
        _ target: Participant, with edited: Participant, removing source: Participant?, in markdown: String
    ) -> String? {
        guard let frontmatter = frontmatterLines(markdown),
              let key = frontmatter.firstIndex(where: { $0.hasPrefix("participants:") }),
              frontmatter[key].dropFirst("participants:".count).trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        let items = frontmatter[(key + 1)...].prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
        func isItem(_ position: Int, of participant: Participant) -> Bool {
            self.participant(scalar(frontmatter[position].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                == participant
        }
        guard let targetLine = items.indices.first(where: { isItem($0, of: target) }) else { return nil }
        let sourceLine = source.flatMap { source in items.indices.first { isItem($0, of: source) } }
        guard source == nil || sourceLine != nil else { return nil }
        var lines = markdown.linesKeepingEnds
        let lineEnd = lines[targetLine].hasSuffix("\r") ? "\r" : ""
        lines[targetLine] = "  - \(yaml(item(edited)))\(lineEnd)"
        if let sourceLine { lines.remove(at: sourceLine) }
        return lines.joined(separator: "\n")
    }
}
