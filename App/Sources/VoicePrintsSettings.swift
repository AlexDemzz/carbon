import CarbonCore
import SwiftUI

/// Settings › Voice Prints: the voices Carbon remembers, and the switch that stops it remembering.
struct VoicePrintsSettings: View {
    @Bindable var model: AppModel

    private var prints: [VoicePrint] { model.library.voicePrints.prints }

    var body: some View {
        Form {
            Section {
                Toggle("Recognize voices", isOn: $model.recognizesVoices)
            } footer: {
                Text(
                    "When you name a Speaker, Carbon remembers their voice and recognizes it in later Meetings. Voice Prints are stored only on this Mac, and Carbon never sends them anywhere."
                )
                .foregroundStyle(.secondary)
            }
            Section {
                List(prints) { print in
                    VoicePrintRow(print: print) { model.deleteVoicePrint(print) }
                }
                .frame(minHeight: 180)
                .overlay {
                    if prints.isEmpty {
                        Text("No Voice Prints").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button("Delete All\u{2026}") { model.confirmDeleteAllVoicePrints() }
                        .disabled(prints.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct VoicePrintRow: View {
    let print: VoicePrint
    let delete: () -> Void

    private var details: String {
        let meetings = print.meetings == 1 ? "1 Meeting" : "\(print.meetings) Meetings"
        let last = print.lastHeardAt.formatted(.dateTime.month(.abbreviated).day())
        return "Heard in \(meetings) \u{00B7} last \(last)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(print.name)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Delete \(print.name)", systemImage: "trash", role: .destructive, action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete Voice Print")
        }
    }
}
