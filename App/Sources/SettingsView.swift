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

    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
        }
        .formStyle(.grouped)
    }
}
