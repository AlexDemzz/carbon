import CarbonCore
import SwiftUI

/// A person's Name and Email fields, with what's wrong with them underneath. Shared by "Edit Participant…" and
/// Settings › Voice Prints.
struct PersonEditor: View {
    @Binding var name: String
    @Binding var email: String
    let error: String?
    var note: String?

    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .focused($isNameFocused)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let error { Text(error).foregroundStyle(.red) }
                    if let note { Text(note).foregroundStyle(.secondary) }
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear { isNameFocused = true }
    }
}

/// "Edit Participant…": a popover on the token. Closing it any way but Cancel saves a valid edit.
struct ParticipantEditPopover: View {
    let model: AppModel
    let meeting: ListedMeeting
    let participant: Participant

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String
    @State private var isCancelled = false
    private let voicePrints: [VoicePrint]

    init(model: AppModel, meeting: ListedMeeting, participant: Participant) {
        self.model = model
        self.meeting = meeting
        self.participant = participant
        _name = State(initialValue: participant.isNamedByEmail ? "" : participant.name)
        _email = State(initialValue: participant.email ?? "")
        voicePrints = model.library.voicePrints(of: participant, in: meeting.id)
    }

    private var error: String? {
        do {
            _ = try model.library.person(name: name, email: email, voicePrints: Set(voicePrints.map(\.id)))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            PersonEditor(
                name: $name, email: $email, error: error,
                note: voicePrints.first.map { "Also updates \($0.name)\u{2019}s Voice Print." })
            HStack {
                Button("Cancel", role: .cancel) {
                    isCancelled = true
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(error != nil)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 320)
        .onDisappear {
            guard !isCancelled, error == nil else { return }
            model.editParticipant(meeting, participant, name: name, email: email)
        }
    }
}

/// Settings › Voice Prints › Edit: a sheet with Cancel and Done.
struct VoicePrintEditSheet: View {
    let model: AppModel
    let print: VoicePrint

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String

    init(model: AppModel, print: VoicePrint) {
        self.model = model
        self.print = print
        _name = State(initialValue: print.person.isNamedByEmail ? "" : print.name)
        _email = State(initialValue: print.email ?? "")
    }

    private var error: String? {
        do {
            _ = try model.library.person(name: name, email: email, voicePrints: [print.id])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        PersonEditor(
            name: $name, email: $email, error: error,
            note: "Meetings already named after this voice keep the name they show.")
            .frame(width: 360)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if model.editVoicePrint(print, name: name, email: email) { dismiss() }
                    }
                    .disabled(error != nil)
                }
            }
    }
}
