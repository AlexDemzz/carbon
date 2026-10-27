// PROTOTYPE, throwaway: row, menus, Speaker renaming, editor window, Settings.
import SwiftUI

extension Meeting {
    var metadata: String {
        let date = isLive ? "Now" : date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US")))
        let minutes = isLive ? "live" : "\(Int(duration / 60)) min"
        let names = attendees.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        let people = names.count > 2 ? "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)" : names.joined(separator: ", ")
        return [date, minutes, people].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct MeetingRow: View {
    let meeting: Meeting
    var snippet: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(meeting.isLive ? .red : meeting.color?.color ?? .clear)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).fontWeight(.semibold).lineLimit(1)
                Text(meeting.isLive ? "Transcribing in \(meeting.language) · \(meeting.provider)" : meeting.metadata)
                    .font(.callout)
                    .foregroundStyle(meeting.isLive ? .red : .secondary)
                    .lineLimit(1)
                if let snippet {
                    Text(snippet).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .help(meeting.attendees.map(\.name).joined(separator: ", "))
        .accessibilityValue(meeting.color.map { "\($0.rawValue.capitalized) tag" } ?? "")
    }
}

/// The right-click menu from the product design.
struct MeetingContextMenu: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    let meeting: Meeting
    var delete: () -> Void

    var body: some View {
        Button("Copy Path") { store.copyPath(meeting) }.keyboardShortcut("c", modifiers: [.shift, .command])
        Button("Copy Markdown") { store.copy(meeting) }.keyboardShortcut("c")
        Button("Reveal in Finder") { store.revealInFinder() }
        Divider()
        Button("Edit") { openWindow(id: "editor", value: meeting.id) }.keyboardShortcut(.return, modifiers: [])
        Divider()
        Picker("Color", selection: Binding(
            get: { store.meetings.first { $0.id == meeting.id }?.color },
            set: { color in store.binding(meeting.id)?.wrappedValue.color = color })
        ) {
            Image(systemName: "circle.slash").tag(DotColor?.none)
            ForEach(DotColor.allCases) { color in
                Image(systemName: "circle.fill").tint(color.color).tag(DotColor?.some(color))
            }
        }
        .pickerStyle(.palette)
        Divider()
        Button("Delete", role: .destructive, action: delete).keyboardShortcut(.delete, modifiers: [])
    }
}

/// The Meeting's More (⋯) menu in the toolbar: actions on this Meeting only.
struct MoreMenu: View {
    @Environment(Store.self) private var store
    let meeting: Meeting
    var delete: () -> Void

    var body: some View {
        Menu {
            Button("Copy Path") { store.copyPath(meeting) }.keyboardShortcut("c", modifiers: [.shift, .command])
            Button("Copy Markdown") { store.copy(meeting) }.keyboardShortcut("c")
            Button("Reveal in Finder") { store.revealInFinder() }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
    }
}

struct DeleteConfirmation: ViewModifier {
    @Environment(Store.self) private var store
    @Binding var pending: Meeting?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \u{201C}\(pending?.title ?? "")\u{201D}?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Delete Meeting", role: .destructive) {
                if let pending { store.delete(pending.id) }
            }
        } message: {
            Text("Its Markdown file moves to the Trash, so you can still restore it from there.")
        }
    }
}

extension View {
    func confirmDelete(_ pending: Binding<Meeting?>) -> some View { modifier(DeleteConfirmation(pending: pending)) }
}

/// Picking a name for a Speaker from the calendar event's attendees.
struct SpeakerMenu<Label: View>: View {
    @Environment(Store.self) private var store
    let meeting: Meeting
    let speaker: String
    @ViewBuilder var label: () -> Label
    @State private var askingName = false
    @State private var typedName = ""

    var body: some View {
        if speaker == "Me" {
            label()
        } else {
            Menu {
                Section("Who is \(speaker)?") {
                    ForEach(meeting.attendees.filter { !meeting.speakers.contains($0.name) }, id: \.self) { attendee in
                        Button(attendee.name) { store.rename(speaker, to: attendee.name, in: meeting.id) }
                    }
                }
                Button("Other Name…") { askingName = true }
            } label: {
                label()
            }
            .menuIndicator(.hidden)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .alert("Name \(speaker)", isPresented: $askingName) {
                TextField("Name", text: $typedName)
                Button("Rename") { store.rename(speaker, to: typedName, in: meeting.id); typedName = "" }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Carbon will recognize this voice in later Meetings.")
            }
        }
    }
}

/// Speaker chips shown above the editor, so renaming works on raw Markdown too.
struct SpeakerBar: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 6) {
            Text("Speakers").font(.callout).foregroundStyle(.secondary)
            ForEach(meeting.speakers, id: \.self) { speaker in
                SpeakerMenu(meeting: meeting, speaker: speaker) {
                    HStack(spacing: 3) {
                        Text(speaker)
                        if speaker != "Me" { Image(systemName: "chevron.down").imageScale(.small) }
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isUnnamed(speaker) ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
                }
            }
            Spacer()
        }
    }

    private func isUnnamed(_ speaker: String) -> Bool {
        speaker.hasPrefix("Speaker ") || speaker == "Them"
    }
}

struct EditorWindow: View {
    @Binding var meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $meeting.title).textFieldStyle(.plain).font(.title2.weight(.semibold))
            Text("\(meeting.metadata) · \(meeting.provider) · \(meeting.language)").foregroundStyle(.secondary)
            SpeakerBar(meeting: meeting)
            TextEditor(text: $meeting.body)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
            Text(meeting.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(20)
        .navigationTitle(meeting.title)
    }
}

struct SettingsView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form {
                    Toggle("Transcribe Meetings automatically", isOn: $store.autoTranscribe)
                    Toggle("Keep audio after transcribing", isOn: $store.keepAudio)
                    LabeledContent("Library folder") {
                        HStack { Text("~/Documents/Carbon"); Button("Change…") {} }
                    }
                    LabeledContent("Show Carbon shortcut") { Text("⌥⌘C").monospaced() }
                    Toggle("Launch at login", isOn: .constant(true))
                    Toggle("Check for updates automatically", isOn: .constant(true))
                }
                .formStyle(.grouped)
            }
            Tab("Languages", systemImage: "globe") {
                Form {
                    Section("Meeting Languages") {
                        ForEach(["English", "French", "Spanish", "German", "Italian", "Portuguese"], id: \.self) { language in
                            Toggle(language, isOn: Binding(
                                get: { store.meetingLanguages.contains(language) },
                                set: { on in
                                    if on { store.meetingLanguages.append(language) } else { store.meetingLanguages.removeAll { $0 == language } }
                                }))
                        }
                    }
                    Picker("Default", selection: $store.defaultLanguage) {
                        ForEach(store.meetingLanguages, id: \.self) { Text($0) }
                    }
                }
                .formStyle(.grouped)
            }
            Tab("Permissions", systemImage: "lock") {
                Form {
                    permission("Microphone", "Hears you.", granted: true)
                    permission("System Audio Recording", "Hears the other people in the Meeting.", granted: true)
                    permission("Calendars", "Names Meetings and their participants.", granted: false)
                }
                .formStyle(.grouped)
            }
            Tab("Voice Prints", systemImage: "waveform") {
                Form {
                    Section {
                        ForEach(store.voicePrints, id: \.self) { name in
                            LabeledContent(name) {
                                Button("Delete", role: .destructive) { store.voicePrints.removeAll { $0 == name } }
                            }
                        }
                    } footer: {
                        Text("Carbon remembers a voice when you name a Speaker, and recognizes it in later Meetings. Voice Prints never leave this Mac.")
                    }
                }
                .formStyle(.grouped)
            }
            Tab("About", systemImage: "info.circle") {
                VStack(spacing: 8) {
                    Image(nsImage: MenuBarGlyph.idle).resizable().frame(width: 64, height: 64)
                    Text("Carbon").font(.title2.weight(.semibold))
                    Text("Speaker diarization by FluidAudio, models licensed CC BY 4.0.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 520, height: 420)
    }

    private func permission(_ name: String, _ why: String, granted: Bool) -> some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open System Settings") {}
            }
        } label: {
            Text(name)
            Text(why)
        }
    }
}
