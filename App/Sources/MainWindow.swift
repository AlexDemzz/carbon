import CarbonCore
import SwiftUI

/// The native split window: Meetings and Search in the sidebar, the selected Meeting in the panel.
struct MainWindow: View {
    let library: Library
    @State private var query = ""
    @State private var selection: ListedMeeting.ID?

    var body: some View {
        let hits = library.search(query)
        NavigationSplitView {
            List(hits, id: \.meeting.id, selection: $selection) { hit in
                MeetingRow(meeting: hit.meeting, snippet: hit.snippet)
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search Meetings")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .overlay {
                if hits.isEmpty { EmptyLibrary(query: query) }
            }
        } detail: {
            if let meeting = library.meetings.first(where: { $0.id == selection }) {
                MeetingPanel(meeting: meeting)
            } else {
                ContentUnavailableView(
                    "No Meeting Selected", systemImage: "text.alignleft",
                    description: Text("Choose a Meeting to read its Transcript."))
            }
        }
        .frame(minWidth: 700, minHeight: 420)
        .onAppear { selection = selection ?? library.meetings.first?.id }
    }
}

private struct EmptyLibrary: View {
    let query: String

    var body: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView(
                "No Meetings Yet", systemImage: "waveform",
                description: Text("Join a call and Carbon transcribes it here."))
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

struct MeetingRow: View {
    let meeting: ListedMeeting
    let snippet: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(MeetingColor.color(meeting.color))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).fontWeight(.semibold).lineLimit(1)
                Text(meeting.rowDetails(in: .current))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let snippet {
                    Text(snippet).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .help(meeting.participantList)
        .accessibilityValue(meeting.color.map { "\($0.capitalized) tag" } ?? "")
    }
}

enum MeetingColor {
    static func color(_ name: String?) -> Color {
        switch name {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "blue": .blue
        case "purple": .purple
        case "gray": .gray
        default: .clear
        }
    }
}

struct MeetingPanel: View {
    let meeting: ListedMeeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !meeting.participants.isEmpty {
                    ParticipantTokens(participants: meeting.participants)
                }
                Text("Transcript")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(TranscriptBuilder.turns(inMarkdown: meeting.markdown).enumerated()), id: \.offset) {
                    TurnView(turn: $0.element)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(meeting.title)
        .navigationSubtitle(meeting.titleBarDetails(in: .current))
        .toolbar {
            // Edit and More get their actions in ticket 09.
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "square.and.pencil") {}
                    .help("Edit the Meeting's Markdown in a new window")
                    .disabled(true)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {}
                    .menuIndicator(.hidden)
                    .disabled(true)
            }
        }
    }
}

/// "Speaker · 0:19" above the Turn's text.
struct TurnView: View {
    let turn: Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(turn.speaker).fontWeight(.semibold)
                Text("·").accessibilityHidden(true)
                Text(turn.elapsed).monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text(turn.text).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
