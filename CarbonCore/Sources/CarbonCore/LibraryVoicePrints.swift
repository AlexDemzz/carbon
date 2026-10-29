import Foundation

extension Library {
    /// Forgets one voice. Meetings that linked it keep their names, in the files and in `meetings.json`.
    public func deleteVoicePrint(_ printID: UUID) throws {
        try voicePrints.update { $0.removeAll { $0.id == printID } }
        try unlinkVoicePrints { $0 == printID }
    }

    /// Forgets every voice.
    public func deleteAllVoicePrints() throws {
        try voicePrints.update { $0.removeAll() }
        try unlinkVoicePrints { _ in true }
    }

    /// Updates each print a Meeting auto-matched with the voice it heard there.
    func hearVoices(_ heard: [(print: UUID, embedding: [Float])], at date: Date) throws {
        guard !heard.isEmpty else { return }
        try voicePrints.update { prints in
            for (id, embedding) in heard {
                guard let position = prints.firstIndex(where: { $0.id == id }) else { continue }
                prints[position].hear(embedding, at: date)
            }
        }
    }

    /// Updates the owner's print with the mic voice of a Meeting on headphones, or enrolls it from that voice. A voice
    /// too far from the print to match it is someone else's: it leaves the print as it was.
    func hearOwner(_ embedding: [Float], at date: Date) throws {
        guard recognizesVoices else { return }
        try voicePrints.update { prints in
            if let position = prints.firstIndex(where: { $0.owner && $0.model == voicePrintModel }) {
                guard VoicePrintMatcher.cosineDistance(embedding, prints[position].centroid)
                    < VoicePrintMatcher.maximumDistance
                else { return }
                prints[position].hear(embedding, at: date)
            } else {
                prints.append(VoicePrint(
                    id: makeVoicePrintID(), name: TranscriptBuilder.me, model: voicePrintModel,
                    centroid: VoicePrint.normalized(embedding), createdAt: now(), lastHeardAt: date, owner: true))
            }
        }
    }

    private func unlinkVoicePrints(where isForgotten: (UUID) -> Bool) throws {
        var index = try loadIndex()
        var changed: [MeetingIndex.Entry] = []
        for meeting in index.meetings.indices {
            var unlinked = false
            for speaker in index.meetings[meeting].speakers.indices {
                guard let link = index.meetings[meeting].speakers[speaker].voicePrintId, isForgotten(link) else {
                    continue
                }
                index.meetings[meeting].speakers[speaker].voicePrintId = nil
                unlinked = true
            }
            if unlinked { changed.append(index.meetings[meeting]) }
        }
        guard !changed.isEmpty else { return }
        try save(index)
        changed.forEach(refreshListed)
    }

    /// Enrolls or updates the Voice Print of `name` from each named cluster with enough speech, and returns the
    /// print each cluster now links to (nil: none). A cluster that linked another print moves off it.
    /// `isOwner`: the clusters are the owner's, whose print is the one flagged `owner`.
    func rememberVoices(
        of entry: MeetingIndex.Entry, label: String, name: String, email: String?, isOwner: Bool = false
    ) throws -> [String: UUID?] {
        let named = entry.speakers.filter { $0.label == label }
        let heard = (try? Date(entry.start, strategy: .iso8601)) ?? now()
        var links: [String: UUID?] = [:]
        try voicePrints.update { prints in
            // Prints this Meeting already counts, through Speakers that keep their link.
            var counted = Set(entry.speakers.filter { $0.label != label }.compactMap(\.voicePrintId))
            for speaker in named {
                if let old = speaker.voicePrintId, let position = prints.firstIndex(where: { $0.id == old }) {
                    if prints[position].person.isPerson(named: name, email: email) {
                        links[speaker.cluster] = old
                        counted.insert(old)
                        continue
                    }
                    // Only auto-matched or person-confirmed Speakers update a print: this one no longer is.
                    // A shared mic's auto match never updated the owner's print, so there is nothing to take back.
                    if !(prints[position].owner && speaker.match == .auto) {
                        if let embedding = speaker.embedding { prints[position].unhear(embedding) }
                        prints[position].meetings -= 1
                        if prints[position].meetings <= 0 { prints.remove(at: position) }
                    }
                }
                guard recognizesVoices, speaker.speechSeconds >= VoicePrintMatcher.minimumSpeechSeconds,
                      let embedding = speaker.embedding
                else {
                    links[speaker.cluster] = .some(nil)
                    continue
                }
                // By email first: picking an attendee names the Speaker after them, whatever the print is called.
                let candidates = prints.indices.filter { prints[$0].model == voicePrintModel && prints[$0].owner == isOwner }
                let byEmail = email.flatMap { email in
                    candidates.first { prints[$0].email?.caseInsensitiveCompare(email) == .orderedSame }
                }
                if let position = isOwner ? candidates.first : byEmail ?? candidates.first(where: {
                    prints[$0].person.isPerson(named: name, email: email)
                }) {
                    let isNewMeeting = counted.insert(prints[position].id).inserted
                    prints[position].hear(embedding, at: heard, isNewMeeting: isNewMeeting)
                    if prints[position].email == nil { prints[position].email = email }
                    links[speaker.cluster] = prints[position].id
                } else {
                    let print = VoicePrint(
                        id: makeVoicePrintID(), name: name, email: email, model: voicePrintModel,
                        centroid: VoicePrint.normalized(embedding), createdAt: now(), lastHeardAt: heard, owner: isOwner)
                    prints.append(print)
                    counted.insert(print.id)
                    links[speaker.cluster] = print.id
                }
            }
        }
        return links
    }
}
