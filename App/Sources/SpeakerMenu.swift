import CarbonCore
import SwiftUI

/// A Speaker's name with a chevron: the Meeting's attendees, then "Other Name…". Unnamed Speakers are blue.
/// Me has no menu.
struct SpeakerMenu: View {
    let model: AppModel
    let meeting: ListedMeeting
    let label: String
    /// Called after a rename was written, e.g. to reload an editor.
    var didRename: () -> Void = {}

    @State private var isAskingForName = false
    @State private var otherName = ""

    private var isUnnamed: Bool { meeting.isUnnamedSpeaker(label) }

    var body: some View {
        if label == TranscriptBuilder.me {
            Text(label)
        } else {
            Menu {
                if model.recognizesVoices, meeting.tooLittleSpeechToRemember(label) {
                    Text("Not enough speech to remember this voice.")
                    Divider()
                }
                ForEach(meeting.participants.map(\.name), id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { name == label }, set: { _ in rename(to: name) }))
                }
                if !meeting.participants.isEmpty { Divider() }
                Button("Other Name…") {
                    otherName = isUnnamed ? "" : label
                    isAskingForName = true
                }
            } label: {
                Text(label)
                    .foregroundStyle(isUnnamed ? AnyShapeStyle(.blue) : AnyShapeStyle(.primary))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .accessibilityLabel(isUnnamed ? "\(label), unnamed, rename" : "\(label), rename")
            .alert("Name \(label)", isPresented: $isAskingForName) {
                TextField("Name", text: $otherName)
                Button("Rename") { rename(to: otherName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only this Speaker's Turn headers change in the file.")
            }
        }
    }

    private func rename(to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != label else { return }
        if model.renameSpeaker(meeting, label: label, to: name) { didRename() }
    }
}
