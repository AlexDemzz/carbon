// PROTOTYPE, throwaway: in-memory state only, nothing touches disk.
import AppKit
import SwiftUI
import UserNotifications

enum DotColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple
    var id: Self { self }
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}

struct Attendee: Hashable {
    var name: String
    var email: String
}

struct Meeting: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var date: Date
    var duration: TimeInterval
    var provider: String
    var attendees: [Attendee]
    var language: String
    var color: DotColor?
    var body: String
    var isLive = false

    var slug: String {
        title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }

    var path: String {
        let day = date.formatted(.iso8601.year().month().day())
        return "~/Documents/Carbon/\(day.prefix(4))/\(day)-\(slug).md"
    }

    var markdown: String {
        """
        ---
        provider: \(provider)
        date: \(date.formatted(.iso8601))
        title: \(title)
        duration: \(Int(duration / 60))
        participants: [\(attendees.map(\.name).joined(separator: ", "))]
        ---

        \(body)
        """
    }

    /// Speakers in order of first appearance, read back from the `**Name** [time]` lines.
    var speakers: [String] {
        var seen: [String] = []
        for line in body.split(separator: "\n") {
            if let name = TranscriptLine(String(line))?.speaker, !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    var summary: String {
        guard let start = body.range(of: "## Summary\n"), let end = body.range(of: "## Transcript") else { return "" }
        return String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Summary as notes: an optional bold heading, then bullets.
    var summaryNotes: [(heading: String, bullets: [String])] {
        var blocks: [(heading: String, bullets: [String])] = [("Key points", [])]
        for raw in summary.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("**"), line.hasSuffix("**") {
                blocks.append((line.trimmingCharacters(in: CharacterSet(charactersIn: "*")), []))
            } else if !line.isEmpty {
                blocks[blocks.count - 1].bullets.append(line.hasPrefix("- ") ? String(line.dropFirst(2)) : line)
            }
        }
        return blocks.filter { !$0.bullets.isEmpty }
    }

    var transcriptLines: [TranscriptLine] {
        body.split(separator: "\n").compactMap { TranscriptLine(String($0)) }
    }
}

struct TranscriptLine: Hashable {
    var speaker: String
    var time: String
    var text: String

    /// "0:04", "12:40" or "1:02:15": elapsed time without the leading zero hours.
    var elapsed: String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return time }
        return parts[0] > 0
            ? String(format: "%d:%02d:%02d", parts[0], parts[1], parts[2])
            : String(format: "%d:%02d", parts[1], parts[2])
    }

    init?(_ line: String) {
        guard let match = line.wholeMatch(of: #/\*\*(.+?)\*\* \[(.+?)\] (.*)/#) else { return nil }
        speaker = String(match.1)
        time = String(match.2)
        text = String(match.3)
    }
}

@Observable
final class Store: NSObject, UNUserNotificationCenterDelegate {
    var meetings = MockData.meetings
    var autoTranscribe = true
    var keepAudio = false
    var meetingLanguages = ["English", "French", "Spanish"]
    var defaultLanguage = "English"
    var voicePrints: [String] = ["Dana Whitfield", "Marcus Lee"]
    var live: Meeting.ID?
    var liveStart: Date?

    var liveMeeting: Meeting? { meetings.first { $0.id == live } }

    func binding(_ id: Meeting.ID) -> Binding<Meeting>? {
        guard meetings.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.meetings.first { $0.id == id } ?? self.meetings[0] },
            set: { new in if let i = self.meetings.firstIndex(where: { $0.id == id }) { self.meetings[i] = new } }
        )
    }

    func filtered(_ query: String) -> [Meeting] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let sorted = meetings.sorted { $0.date > $1.date }
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.attendees.contains { $0.name.localizedCaseInsensitiveContains(q) }
                || $0.body.localizedCaseInsensitiveContains(q)
        }
    }

    /// The transcript line that matched a full-text query, for result snippets.
    func snippet(_ meeting: Meeting, _ query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !meeting.title.localizedCaseInsensitiveContains(q) else { return nil }
        return meeting.transcriptLines.first { $0.text.localizedCaseInsensitiveContains(q) }.map { "\($0.speaker): \($0.text)" }
    }

    func delete(_ id: Meeting.ID) {
        meetings.removeAll { $0.id == id }
    }

    func rename(_ speaker: String, to name: String, in id: Meeting.ID) {
        guard let i = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[i].body = meetings[i].body.replacingOccurrences(of: "**\(speaker)**", with: "**\(name)**")
        if speaker != "Me", !voicePrints.contains(name) { voicePrints.append(name) }
    }

    func copy(_ meeting: Meeting) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(meeting.markdown, forType: .string)
    }

    func copyPath(_ meeting: Meeting) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((meeting.path as NSString).expandingTildeInPath, forType: .string)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents")])
    }

    // MARK: Simulated Meeting

    func detectMeeting() {
        guard live == nil else { return }
        if autoTranscribe {
            startTranscribing(language: defaultLanguage)
        } else {
            notify(id: "detected", title: "Weekly design sync", body: "Google Meet is using the microphone.",
                   actions: [UNNotificationAction(identifier: "transcribe", title: "Transcribe")]
                       + otherLanguages(than: defaultLanguage).map { UNNotificationAction(identifier: "transcribe.\($0)", title: "Transcribe in \($0)") })
        }
    }

    func startTranscribing(language: String) {
        guard live == nil else { return }
        var meeting = MockData.liveMeeting
        meeting.language = language
        meetings.append(meeting)
        live = meeting.id
        liveStart = .now
        postTranscribing(language)
    }

    func switchLanguage(_ language: String) {
        guard let i = meetings.firstIndex(where: { $0.id == live }) else {
            defaultLanguage = language
            return
        }
        meetings[i].language = language
        postTranscribing(language)
    }

    /// Stop from the notification or the menu discards the captured audio.
    func stopAndDiscard() {
        if let live { delete(live) }
        live = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transcribing"])
    }

    /// What auto-stop does when the Meeting ends: the Meeting stays in the Library.
    func endMeeting() {
        guard let i = meetings.firstIndex(where: { $0.id == live }) else { return }
        meetings[i].isLive = false
        meetings[i].duration = max(60, Date.now.timeIntervalSince(liveStart ?? .now))
        live = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transcribing"])
    }

    private func otherLanguages(than language: String) -> [String] {
        meetingLanguages.filter { $0 != language }
    }

    private func postTranscribing(_ language: String) {
        notify(id: "transcribing", title: "Transcribing in \(language)", body: "Weekly design sync · Google Meet",
               actions: [UNNotificationAction(identifier: "stop", title: "Stop", options: .destructive)]
                   + otherLanguages(than: language).map { UNNotificationAction(identifier: "lang.\($0)", title: "Switch to \($0)") })
    }

    private func notify(id: String, title: String, body: String, actions: [UNNotificationAction]) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [])])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = id
        center.requestAuthorization(options: [.alert]) { _, _ in
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case "stop": stopAndDiscard()
            case "transcribe": startTranscribing(language: defaultLanguage)
            case let a where a.hasPrefix("lang."): switchLanguage(String(a.dropFirst(5)))
            case let a where a.hasPrefix("transcribe."): startTranscribing(language: String(a.dropFirst(11)))
            default: break
            }
        }
    }
}
