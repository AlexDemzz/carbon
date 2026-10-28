import CarbonCore
import Foundation
import Testing

/// Settings › General › Show Carbon: the shortcut recorder.
struct ShortcutTests {
    @Test func showCarbonIsOptionCommandCByDefault() {
        #expect(Shortcut.showCarbon.description == "⌥⌘C")
    }

    @Test func modifiersReadInTheMacOrderWhateverOrderTheyWerePressedIn() throws {
        let shortcut = try #require(Shortcut(keyCode: 40, key: "k", modifiers: [.command, .shift, .control, .option]))

        #expect(shortcut.description == "⌃⌥⇧⌘K")
    }

    @Test func aShortcutNeedsCommandControlOrOption() {
        #expect(Shortcut(keyCode: 40, key: "k", modifiers: []) == nil)
        #expect(Shortcut(keyCode: 40, key: "k", modifiers: [.shift]) == nil)
        #expect(Shortcut(keyCode: 40, key: "k", modifiers: [.control]) != nil)
    }

    @Test func itSurvivesARelaunch() throws {
        let saved = try JSONEncoder().encode(#require(Shortcut(keyCode: 40, key: "k", modifiers: [.control, .shift])))

        #expect(try JSONDecoder().decode(Shortcut.self, from: saved).description == "⌃⇧K")
    }
}
