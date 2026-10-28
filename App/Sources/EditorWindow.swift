import AppKit
import CarbonCore
import SwiftUI

/// The whole Markdown file in a plain-text editor, with the Meeting's Speakers as chips on top.
struct EditorWindow: View {
    let model: AppModel
    let id: UUID
    @State private var text = ""
    @State private var savedText: String?

    private var meeting: ListedMeeting? { model.library.meetings.first { $0.id == id } }
    private var hasUnsavedChanges: Bool { savedText.map { $0 != text } ?? false }

    var body: some View {
        if let meeting {
            VStack(spacing: 0) {
                SpeakerChips(
                    model: model, meeting: meeting, speakers: Self.speakers(in: text),
                    isRenameBlocked: hasUnsavedChanges
                ) {
                    text = model.currentMarkdown(model.library.meetings.first { $0.id == id } ?? meeting)
                    savedText = text
                }
                Divider()
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .accessibilityLabel("Markdown")
            }
            .navigationTitle(meeting.title)
            .navigationSubtitle(hasUnsavedChanges ? "Edited" : "")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save", systemImage: "square.and.arrow.down") { _ = save() }
                        .keyboardShortcut("s")
                        .disabled(!hasUnsavedChanges)
                }
            }
            .background(CloseGuard(title: meeting.title, hasUnsavedChanges: hasUnsavedChanges, save: save))
            .frame(minWidth: 480, minHeight: 320)
            .task(id: id) {
                guard savedText == nil else { return }
                text = model.currentMarkdown(meeting)
                savedText = text
            }
        } else {
            ContentUnavailableView(
                "Meeting Deleted", systemImage: "trash",
                description: Text("This Meeting is no longer in the Library."))
                .frame(minWidth: 480, minHeight: 320)
        }
    }

    private func save() -> Bool {
        guard model.save(id, editedMarkdown: text) else { return false }
        savedText = text
        return true
    }

    /// Each Speaker once, in order of first Turn.
    static func speakers(in markdown: String) -> [String] {
        var seen = Set<String>()
        return TranscriptBuilder.turns(inMarkdown: markdown).map(\.speaker).filter { seen.insert($0).inserted }
    }
}

/// A rename writes the file on disk, so it waits until the person's own changes are saved.
private struct SpeakerChips: View {
    let model: AppModel
    let meeting: ListedMeeting
    let speakers: [String]
    let isRenameBlocked: Bool
    let didRename: () -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(speakers, id: \.self) { speaker in
                SpeakerMenu(model: model, meeting: meeting, label: speaker, didRename: didRename)
                    .disabled(isRenameBlocked)
                    .help(
                        isRenameBlocked && (speaker != TranscriptBuilder.me || meeting.isOnMic(speaker))
                            ? "Save your changes to rename Speakers." : "")
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Speakers")
    }
}

/// Asks before closing the window with unsaved changes, and marks the close button as edited.
private struct CloseGuard: NSViewRepresentable {
    let title: String
    let hasUnsavedChanges: Bool
    let save: () -> Bool

    func makeNSView(context: Context) -> GuardView { GuardView() }

    func updateNSView(_ view: GuardView, context: Context) {
        view.title = title
        view.save = save
        view.hasUnsavedChanges = hasUnsavedChanges
    }

    final class GuardView: NSView {
        var title = ""
        var save: () -> Bool = { true }
        var hasUnsavedChanges = false {
            didSet { window?.isDocumentEdited = hasUnsavedChanges }
        }
        private var proxy: DelegateProxy?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, proxy?.window !== window else { return }
            let proxy = DelegateProxy(window: window, guardView: self)
            self.proxy = proxy
            window.delegate = proxy
            window.isDocumentEdited = hasUnsavedChanges
        }
    }

    /// Stands in front of SwiftUI's own window delegate, which gets every other message.
    final class DelegateProxy: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var original: (any NSWindowDelegate)?
        weak var guardView: GuardView?

        init(window: NSWindow, guardView: GuardView) {
            self.window = window
            original = window.delegate
            self.guardView = guardView
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if original?.windowShouldClose?(sender) == false { return false }
            guard let guardView, guardView.hasUnsavedChanges else { return true }
            let alert = NSAlert()
            alert.messageText = "Do you want to save the changes you made to \u{201C}\(guardView.title)\u{201D}?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: sender) { response in
                switch response {
                case .alertFirstButtonReturn:
                    if guardView.save() { sender.close() }
                case .alertSecondButtonReturn:
                    guardView.hasUnsavedChanges = false
                    sender.close()
                default:
                    break
                }
            }
            return false
        }
    }
}
