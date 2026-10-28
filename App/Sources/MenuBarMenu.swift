import CarbonCore
import SwiftUI

struct MenuBarGlyph: View {
    let isLive: Bool

    var body: some View {
        Image(isLive ? "MenuBarRecording" : "MenuBarIdle")
            .accessibilityLabel(isLive ? "Carbon, transcribing" : "Carbon")
    }
}

struct MenuBarMenu: View {
    let model: AppModel

    var body: some View {
        switch model.recorder.state {
        case .idle:
            Button("Start Transcribing") { model.start() }
        case .live(let meeting):
            Text("Transcribing \u{201C}\(meeting.title)\u{201D}")
            Text("since \(meeting.start.formatted(date: .omitted, time: .shortened))")
            Button("Stop") { model.stop() }
            Button("Discard") { model.discard() }
        case .finishing(let meeting):
            Text("Finishing \u{201C}\(meeting.title)\u{201D}\u{2026}")
        }
        Divider()
        Button("Show Carbon") { model.showMainWindow() }
            .keyboardShortcut("c", modifiers: [.option, .command])
        Button("Reveal in Finder") { model.revealLibrary() }
        Divider()
        Button("Quit Carbon") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
