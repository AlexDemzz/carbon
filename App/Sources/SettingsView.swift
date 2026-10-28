import SwiftUI

struct SettingsView: View {
    let updater: Updater

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(updater: updater)
            }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @Bindable var updater: Updater
    @AppStorage(SettingsKey.keepAudio) private var keepAudio = false

    var body: some View {
        Form {
            Toggle("Keep audio after transcribing", isOn: $keepAudio)
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
        }
        .formStyle(.grouped)
    }
}
