import CarbonCore
import SwiftUI

/// The items of a Meeting's context menu and of the panel's More menu.
struct MeetingMenuItems: View {
    enum Place { case contextMenu, more }

    let model: AppModel
    let meeting: ListedMeeting
    let place: Place

    var body: some View {
        // The shortcuts are shown in the context menu; the list handles the keys themselves (MainWindow).
        Button("Copy Path") { model.copyPath(meeting) }
            .keyboardShortcut(place == .contextMenu ? KeyboardShortcut("c", modifiers: [.command, .shift]) : nil)
        Button("Copy Markdown") { model.copyMarkdown(meeting) }
            .keyboardShortcut(place == .contextMenu ? KeyboardShortcut("c") : nil)
        Button("Reveal in Finder") { model.revealInFinder(meeting) }
        if place == .contextMenu {
            Divider()
            Button("Edit") { model.edit(meeting) }
                .keyboardShortcut(.return, modifiers: [])
            Divider()
            ColorPalette(model: model, meeting: meeting)
        }
        Divider()
        Button("Rename…") { model.pendingRename = meeting }
        Divider()
        Button("Delete") { model.pendingDelete = meeting }
            .keyboardShortcut(place == .contextMenu ? KeyboardShortcut(.delete, modifiers: []) : nil)
    }
}

/// The color dots, Finder-tag style, with "No Color" first.
private struct ColorPalette: View {
    let model: AppModel
    let meeting: ListedMeeting

    var body: some View {
        Picker("Color", selection: Binding(get: { meeting.color }, set: { model.setColor(meeting, $0) })) {
            Label("No Color", systemImage: "circle.slash").tag(String?.none)
            ForEach(MeetingColor.names, id: \.self) { name in
                Label(name.capitalized, systemImage: "circle.fill")
                    .tint(MeetingColor.color(name))
                    .tag(String?.some(name))
            }
        }
        .pickerStyle(.palette)
        .paletteSelectionEffect(.symbolVariant(.circle))
    }
}

/// The Delete confirmation and the Rename… prompt, shown over the main window.
struct MeetingDialogs: ViewModifier {
    @Bindable var model: AppModel
    @State private var newTitle = ""

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete \u{201C}\(model.pendingDelete?.title ?? "")\u{201D}?",
                isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }),
                presenting: model.pendingDelete
            ) { meeting in
                Button("Delete Meeting", role: .destructive) { model.delete(meeting) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The Markdown file moves to the Trash.")
            }
            .alert(
                "Rename Meeting",
                isPresented: Binding(get: { model.pendingRename != nil }, set: { if !$0 { model.pendingRename = nil } }),
                presenting: model.pendingRename
            ) { meeting in
                TextField("Title", text: $newTitle)
                Button("Rename") { model.rename(meeting, to: newTitle) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The file keeps its name, so paths you shared still work.")
            }
            .onChange(of: model.pendingRename) { _, meeting in
                if let meeting { newTitle = meeting.title }
            }
    }
}
