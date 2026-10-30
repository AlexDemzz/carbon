import AppKit
import CarbonCore
import SwiftUI

/// A Mail message header above the Transcript: one labelled line per detail, the Participants last, then a divider.
struct MeetingHeader: View {
    let model: AppModel
    let meeting: ListedMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(meeting.headerDetails(in: .current), id: \.label) { detail in
                    HeaderLine(label: detail.label) { Text(detail.value).textSelection(.enabled) }
                }
                if !meeting.participants.isEmpty {
                    HeaderLine(label: "With") {
                        FlowLayout(spacing: 4) {
                            ForEach(Array(meeting.participants.enumerated()), id: \.offset) { _, participant in
                                ParticipantToken(model: model, meeting: meeting, participant: participant)
                            }
                        }
                    }
                }
            }
            .font(.system(size: 12))
            Divider()
        }
    }
}

/// "Label:" then its value in grey, like "To:" in Mail.
private struct HeaderLine<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(label):")
            value.foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ParticipantToken: View {
    let model: AppModel
    let meeting: ListedMeeting
    let participant: Participant

    @State private var isHovered = false
    @State private var isEditing = false

    private var others: [Participant] { meeting.participants.filter { $0 != participant } }

    var body: some View {
        Menu { actions } label: { Token(name: participant.name, showsChevron: isHovered) }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .contextMenu { actions }
            .onHover { isHovered = $0 }
            .help(participant.email ?? participant.name)
            .accessibilityHint("Shows actions")
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                ParticipantEditPopover(model: model, meeting: meeting, participant: participant)
            }
    }

    @ViewBuilder private var actions: some View {
        if let email = participant.email {
            Text(email)
            Button("Copy Email Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(email, forType: .string)
            }
            Button("New Email") {
                if let url = URL(string: "mailto:\(email)") { NSWorkspace.shared.open(url) }
            }
            Divider()
        }
        Button("Edit Participant\u{2026}") { isEditing = true }
        Menu("Same Person As") {
            ForEach(Array(others.enumerated()), id: \.offset) { _, other in
                Button(other.isNamedByEmail ? other.name : other.email.map { "\(other.name) (\($0))" } ?? other.name) {
                    model.mergeParticipant(meeting, participant, into: other)
                }
            }
        }
        .disabled(others.isEmpty)
    }
}

/// A bordered badge sized by the name alone. On hover a fill fades in and the chevron floats over the name's end,
/// which fades out beneath it, so nothing reserves room or moves.
private struct Token: View {
    let name: String
    let showsChevron: Bool

    var body: some View {
        Text(name)
            .foregroundStyle(showsChevron ? .primary : .secondary)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(showsChevron ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                }
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(showsChevron ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quinary).opacity(showsChevron ? 1 : 0))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
            .animation(.easeOut(duration: 0.15), value: showsChevron)
    }
}

/// Lays subviews out left to right, starting a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let x = row.indices.isEmpty ? 0 : row.width + spacing
            if !row.indices.isEmpty, x + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
