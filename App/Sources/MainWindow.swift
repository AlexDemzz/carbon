import CarbonCore
import SwiftUI

/// The native split window: Meetings and Search in the sidebar, the selected Meeting in the panel.
struct MainWindow: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var library: Library { model.library }
    private var selected: ListedMeeting? { library.meetings.first { $0.id == model.selection } }

    private func meeting(_ ids: Set<UUID>) -> ListedMeeting? {
        ids.first.flatMap { id in library.meetings.first { $0.id == id } }
    }

    var body: some View {
        let hits = library.search(query)
        NavigationSplitView {
            List(hits, id: \.meeting.id, selection: $model.selection) { hit in
                MeetingRow(meeting: hit.meeting, snippet: hit.snippet)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let meeting = meeting(ids) {
                    MeetingMenuItems(model: model, meeting: meeting, place: .contextMenu)
                }
            } primaryAction: { ids in
                // Return and double-click.
                if let meeting = meeting(ids) { model.edit(meeting) }
            }
            .onCopyCommand {
                guard let selected else { return [] }
                return [NSItemProvider(object: model.currentMarkdown(selected) as NSString)]
            }
            .onDeleteCommand { model.pendingDelete = selected }
            .searchable(text: $query, placement: .sidebar, prompt: "Search Meetings")
            .searchFocused($isSearchFocused)
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .overlay {
                if hits.isEmpty { EmptyLibrary(query: query) }
            }
        } detail: {
            if let selected {
                MeetingPanel(model: model, meeting: selected)
            } else {
                ContentUnavailableView(
                    "No Meeting Selected", systemImage: "text.alignleft",
                    description: Text("Choose a Meeting to read its Transcript."))
            }
        }
        .frame(minWidth: 700, minHeight: 420)
        .background {
            // ⇧⌘C anywhere in the window. The list's own ⌘C (onCopyCommand) leaves text selection's ⌘C alone.
            Button("Copy Path") { selected.map(model.copyPath) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(selected == nil)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            // Carbon has no menu bar of its own (LSUIElement), so no Find menu item brings ⌘F.
            Button("Search") { isSearchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .modifier(MeetingDialogs(model: model))
        .onAppear { model.selection = model.selection ?? library.meetings.first?.id }
        .task { await debugCycleSelection() } // [DEBUG-sel4]
    }
}

extension MainWindow { // [DEBUG-sel4]
    func debugCycleSelection() async { // [DEBUG-sel4]
        guard ProcessInfo.processInfo.environment["CARBON_DEBUG_SEL"] != nil else { return } // [DEBUG-sel4]
        try? await Task.sleep(for: .seconds(2)) // [DEBUG-sel4]
        for _ in 0..<3 { // [DEBUG-sel4]
            for meeting in library.meetings { // [DEBUG-sel4]
                let start = ContinuousClock.now // [DEBUG-sel4]
                model.selection = meeting.id // [DEBUG-sel4]
                await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } // [DEBUG-sel4]
                let ms = (ContinuousClock.now - start) / .milliseconds(1) // [DEBUG-sel4]
                let turns = TranscriptBuilder.turns(inMarkdown: meeting.markdown).count // [DEBUG-sel4]
                FileHandle.standardError.write("[DEBUG-sel4] \(turns) turns: \(Int(ms)) ms\n".data(using: .utf8)!) // [DEBUG-sel4]
                try? await Task.sleep(for: .milliseconds(400)) // [DEBUG-sel4]
            } // [DEBUG-sel4]
        } // [DEBUG-sel4]
        exit(0) // [DEBUG-sel4]
    } // [DEBUG-sel4]
} // [DEBUG-sel4]

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
        .accessibilityElement(children: .combine)
        .accessibilityValue(meeting.color.map { "\($0.capitalized) tag" } ?? "")
    }
}

enum MeetingColor {
    static let names = ["red", "orange", "yellow", "green", "blue", "purple", "gray"]

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
    let model: AppModel
    let meeting: ListedMeeting

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !meeting.participants.isEmpty {
                    ParticipantTokens(model: model, meeting: meeting)
                }
                Text("Transcript")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(TranscriptBuilder.turns(inMarkdown: meeting.markdown).enumerated()), id: \.offset) {
                    TurnView(model: model, meeting: meeting, turn: $0.element)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // An editable title: double-click it in the title bar to rename the Meeting.
        .navigationTitle(Binding(get: { meeting.title }, set: { model.rename(meeting, to: $0) }))
        .navigationSubtitle(meeting.titleBarDetails(in: .current))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "square.and.pencil") { model.edit(meeting) }
                    .help("Edit the Meeting's Markdown in a new window")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    MeetingMenuItems(model: model, meeting: meeting, place: .more)
                }
                .menuIndicator(.hidden)
            }
        }
    }
}

/// "Speaker · 0:19" above the Turn's text.
struct TurnView: View {
    let model: AppModel
    let meeting: ListedMeeting
    let turn: Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SpeakerMenu(model: model, meeting: meeting, label: turn.speaker).fontWeight(.semibold)
                Text("·").accessibilityHidden(true)
                Text(turn.elapsed).monospacedDigit()
                    .accessibilityLabel(turn.spokenElapsed())
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Text(turn.text).textSelection(.enabled)
        }
        // VoiceOver reads the Turn in one go; interacting with it reaches the Speaker menu and the text.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(turn.speaker), \(turn.spokenElapsed()), \(turn.text)")
    }
}
