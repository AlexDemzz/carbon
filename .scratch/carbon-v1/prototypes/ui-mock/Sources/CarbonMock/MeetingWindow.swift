// PROTOTYPE, throwaway. The main window: Meeting list in the sidebar, the selected Meeting's Summary and Transcript in the detail.
import SwiftUI

struct SplitWindow: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var selection: Meeting.ID?
    @State private var pendingDelete: Meeting?

    var body: some View {
        let meetings = store.filtered(query)
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(meetings) { meeting in
                    MeetingRow(meeting: meeting, snippet: store.snippet(meeting, query))
                }
            }
            .contextMenu(forSelectionType: Meeting.ID.self) { ids in
                if let meeting = meetings.first(where: { ids.contains($0.id) }) {
                    MeetingContextMenu(meeting: meeting, delete: { pendingDelete = meeting })
                }
            } primaryAction: { ids in
                if let id = ids.first { openWindow(id: "editor", value: id) }
            }
            .onDeleteCommand { pendingDelete = meetings.first { $0.id == selection } }
            .searchable(text: $query, placement: .sidebar, prompt: "Search Meetings")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .overlay { if meetings.isEmpty { EmptyLibrary(query: query) } }
        } detail: {
            if let selection, let meeting = store.meetings.first(where: { $0.id == selection }) {
                MeetingPanel(meeting: meeting) { pendingDelete = meeting }
            } else {
                ContentUnavailableView("No Meeting Selected", systemImage: "text.alignleft",
                                       description: Text("Choose a Meeting to read its Transcript."))
            }
        }
        .onAppear { selection = selection ?? meetings.first?.id }
        .confirmDelete($pendingDelete)
    }
}

struct EmptyLibrary: View {
    let query: String

    var body: some View {
        if query.isEmpty {
            ContentUnavailableView("No Meetings Yet", systemImage: "waveform",
                                   description: Text("Join a call and Carbon transcribes it here."))
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

extension Meeting {
    func isUnnamed(_ speaker: String) -> Bool {
        speaker.hasPrefix("Speaker ") || speaker == "Them"
    }
}

struct MeetingPanel: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    let meeting: Meeting
    var delete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if meeting.isLive {
                    HStack {
                        Label {
                            Text("Transcribing in \(meeting.language)")
                        } icon: {
                            Image(systemName: "record.circle").foregroundStyle(.red)
                        }
                        Spacer()
                        Button("Stop and Discard") { store.stopAndDiscard() }
                    }
                    .padding(12)
                    .background(.red.opacity(0.08), in: .rect(cornerRadius: 10))
                }
                if !meeting.attendees.isEmpty { ParticipantTokens(meeting: meeting) }
                ForEach(Array(meeting.summaryNotes.enumerated()), id: \.offset) { _, block in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(block.heading).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        ForEach(block.bullets, id: \.self) { bullet in
                            Label { Text(LocalizedStringKey(bullet)) } icon: {
                                Circle().fill(.secondary).frame(width: 5, height: 5)
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
                Text("Transcript").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .padding(.top, 16)
                ForEach(Array(meeting.transcriptLines.enumerated()), id: \.offset) { _, line in
                    TranscriptLineView(meeting: meeting, line: line)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(meeting.title)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "square.and.pencil") { openWindow(id: "editor", value: meeting.id) }
                    .help("Edit the Transcript in a new window")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                MoreMenu(meeting: meeting, delete: delete)
            }
        }
    }

    private var subtitle: String {
        let date = meeting.isLive ? "Now" : meeting.date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US")))
        let length = meeting.isLive ? nil : "\(Int(meeting.duration / 60)) min"
        return [date, length, meeting.provider, meeting.language].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One spoken line: "Speaker · 1:02" above the text, Granola-style.
struct TranscriptLineView: View {
    let meeting: Meeting
    let line: TranscriptLine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SpeakerMenu(meeting: meeting, speaker: line.speaker) {
                    HStack(spacing: 3) {
                        Text(line.speaker)
                        if line.speaker != "Me" {
                            Image(systemName: "chevron.down").imageScale(.small).accessibilityHidden(true)
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(meeting.isUnnamed(line.speaker) ? Color.accentColor : .secondary)
                }
                .accessibilityHint(line.speaker == "Me" ? "" : "Choose who this is")
                Text(line.elapsed)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("at \(line.elapsed)")
            }
            .font(.callout)
            Text(line.text)
                .textSelection(.enabled)
        }
    }
}
