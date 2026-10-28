import Foundation

/// The file-name part of a Meeting's title: lowercased, ASCII-folded, non-alphanumerics as `-`, at most 60 characters.
enum Slug {
    static let maxLength = 60
    private static let asciiFolding = StringTransform("Any-Latin; Latin-ASCII")

    static func make(_ title: String) -> String {
        let folded = (title.applyingTransform(asciiFolding, reverse: false) ?? title).lowercased()
        let words = folded
            .split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
            .map(String.init)
        var slug = ""
        for word in words {
            let candidate = slug.isEmpty ? word : "\(slug)-\(word)"
            if candidate.count > maxLength {
                if slug.isEmpty { slug = String(word.prefix(maxLength)) }
                break
            }
            slug = candidate
        }
        return slug.isEmpty ? "meeting" : slug
    }
}
