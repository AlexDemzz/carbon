import AppKit
import CarbonCore

extension AppModel {
    /// "Recognize voices". Turned off, Carbon neither matches nor enrolls, and asks once whether to forget the
    /// voices it already remembers.
    var recognizesVoices: Bool {
        get { library.recognizesVoices }
        set {
            library.recognizesVoices = newValue
            UserDefaults.standard.set(newValue, forKey: SettingsKey.recognizeVoices)
            if !newValue { offerToDeleteVoicePrints() }
        }
    }

    private func offerToDeleteVoicePrints() {
        let count = library.voicePrints.prints.count
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Delete the Voice Print?" : "Delete all \(count) Voice Prints?"
        alert.informativeText = "Carbon has stopped recognizing voices. Names already in your Transcripts stay."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Keep")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("Carbon couldn't delete the Voice Prints") { try library.deleteAllVoicePrints() }
    }

    /// "Delete All…": asks first.
    func confirmDeleteAllVoicePrints() {
        let count = library.voicePrints.prints.count
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Delete the Voice Print?" : "Delete all \(count) Voice Prints?"
        alert.informativeText = "Carbon will stop recognizing these voices. Names already in your Transcripts stay."
        alert.addButton(withTitle: "Delete All").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("Carbon couldn't delete the Voice Prints") { try library.deleteAllVoicePrints() }
    }

    func deleteVoicePrint(_ print: VoicePrint) {
        perform("Carbon couldn't delete the Voice Print") { try library.deleteVoicePrint(print.id) }
    }
}
