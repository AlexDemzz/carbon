import AppKit
import CarbonCore
import SwiftUI

/// Mail-style tokens, one per participant, wrapping onto new lines.
struct ParticipantTokens: View {
    let participants: [Participant]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(participants.enumerated()), id: \.offset) { _, participant in
                if let email = participant.email {
                    Menu {
                        Text(email)
                        Button("Copy Email Address") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(email, forType: .string)
                        }
                        Button("New Email") {
                            if let url = URL(string: "mailto:\(email)") { NSWorkspace.shared.open(url) }
                        }
                    } label: {
                        Token(name: participant.name)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(email)
                } else {
                    Token(name: participant.name)
                }
            }
        }
    }
}

private struct Token: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Monogram(name: name)
            Text(name)
        }
        .padding(.leading, 2)
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .background(Capsule().fill(.quinary))
    }
}

private struct Monogram: View {
    let name: String
    private let size: CGFloat = 20

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size)
            .background(Circle().fill(.quaternary))
            .accessibilityHidden(true)
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
