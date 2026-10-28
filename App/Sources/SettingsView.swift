import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let updater: Updater

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(model: model, updater: updater)
            }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @Bindable var updater: Updater
    @AppStorage(SettingsKey.keepAudio) private var keepAudio = false

    var body: some View {
        Form {
            Section {
                Toggle("Transcribe Meetings automatically", isOn: $model.autoTranscribe)
            } footer: {
                Text(
                    "Carbon shows a notification and a red dot whenever it transcribes. You\u{2019}re responsible for telling others they\u{2019}re being recorded."
                )
                .foregroundStyle(.secondary)
            }
            Toggle("Keep audio after transcribing", isOn: $keepAudio)
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
        }
        .formStyle(.grouped)
    }
}
