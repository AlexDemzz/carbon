import SwiftUI

/// A person's name in a bordered badge that opens a menu, sized by the name alone. On hover a fill fades in and the
/// chevron floats over the name's end, which fades out beneath it, so nothing reserves room or moves.
struct PersonBadge: View {
    let name: String
    let isHovered: Bool
    /// Kept on hover. Without one, the name is grey and turns primary on hover.
    var style: AnyShapeStyle?

    var body: some View {
        Text(name)
            .foregroundStyle(style ?? (isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(isHovered ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                }
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PersonBadge.inset)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quinary).opacity(isHovered ? 1 : 0))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    /// How far the name sits inside the border, for lining it up with text outside a badge.
    static let inset: CGFloat = 6
}
