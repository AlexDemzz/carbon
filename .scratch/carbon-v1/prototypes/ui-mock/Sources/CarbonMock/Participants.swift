// PROTOTYPE, throwaway. The participants above the Summary as Mail-style tokens (picked in round 3).
import AppKit
import SwiftUI

struct Monogram: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(.quaternary))
            .accessibilityHidden(true)
    }
}

/// One token per attendee; each opens a menu with the email address.
struct ParticipantTokens: View {
    let meeting: Meeting

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(meeting.attendees, id: \.self) { attendee in
                Menu {
                    Text(attendee.email)
                    Button("Copy Email Address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(attendee.email, forType: .string)
                    }
                    Button("New Email") { NSWorkspace.shared.open(URL(string: "mailto:\(attendee.email)")!) }
                } label: {
                    HStack(spacing: 6) {
                        Monogram(name: attendee.name, size: 20)
                        Text(attendee.name)
                    }
                    .padding(.leading, 2)
                    .padding(.trailing, 10)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quinary))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(attendee.email)
            }
        }
    }
}

/// Wraps tokens onto new lines when a Meeting has more people than fit on one.
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

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: [Int] = [], x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.isEmpty, x + size.width > width {
                rows.append((current, y, x - spacing, height))
                y += height + spacing
                current = []; x = 0; height = 0
            }
            current.append(index)
            x += size.width + spacing
            height = max(height, size.height)
        }
        if !current.isEmpty { rows.append((current, y, x - spacing, height)) }
        return rows
    }
}
