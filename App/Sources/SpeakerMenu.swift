import CarbonCore
import SwiftUI

/// A Speaker's name in a badge with a menu: Me for a Speaker heard on a meeting room's mic, the Meeting's attendees, then
/// "Other Name…". Unnamed Speakers are blue. Me has no menu, except on a meeting room's mic.
struct SpeakerMenu: View {
    let model: AppModel
    let meeting: ListedMeeting
    let label: String
    /// Called after a rename was written, e.g. to reload an editor.
    var didRename: () -> Void = {}

    @State private var isHovered = false
    @State private var isAskingForName = false
    @State private var otherName = ""

    private var isUnnamed: Bool { meeting.isUnnamedSpeaker(label) }

    var body: some View {
        if label == TranscriptBuilder.me, !meeting.isOnMic(label) {
            // No badge, since there is no menu, but the same inset so Me lines up with the badged names.
            Text(label)
                .padding(.horizontal, PersonBadge.inset)
                .padding(.vertical, 1)
        } else {
            Menu {
                if model.recognizesVoices, meeting.tooLittleSpeechToRemember(label) {
                    Text("Not enough clear speech to remember this voice.")
                    Divider()
                }
                if meeting.isOnMic(label) {
                    Toggle(TranscriptBuilder.me, isOn: Binding(
                        get: { label == TranscriptBuilder.me }, set: { _ in rename(to: TranscriptBuilder.me) }))
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
                PersonBadge(name: label, isHovered: isHovered, style: isUnnamed ? AnyShapeStyle(.blue) : AnyShapeStyle(.primary))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { isHovered = $0 }
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
