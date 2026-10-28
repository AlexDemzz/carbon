/// A global keyboard shortcut, such as Show Carbon's ⌥⌘C.
public struct Shortcut: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The virtual key code, layout independent (`kVK_ANSI_C` is 8).
    public let keyCode: Int
    /// What the key types on the person's layout, shown in the recorder.
    public let key: String
    public let modifiers: Modifiers

    /// Nil without ⌘, ⌃ or ⌥: a bare or shifted key would fire while the person types.
    public init?(keyCode: Int, key: String, modifiers: Modifiers) {
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    public static let showCarbon = Shortcut(keyCode: 8, key: "c", modifiers: [.option, .command])!

    public var description: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.uppercased()
    }
}
