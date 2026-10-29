import CarbonCore
import Foundation
import Speech
import SwiftUI

extension AppModel {
    /// At launch: the saved Meeting Languages, or, the first time, the system's language (en-US when
    /// SpeechTranscriber doesn't have it). Their assets are reserved and downloaded.
    func loadMeetingLanguages() async {
        await languageAssets.loadSupported()
        if let meetingLanguages {
            recorder.detectionLanguage = meetingLanguages.defaultLanguage
            languageAssets.keep(meetingLanguages.chosen)
        } else {
            let system = await supportedSystemLanguage() ?? Locale(identifier: "en_US")
            meetingLanguages = MeetingLanguages(default: system)
        }
    }

    func meetingLanguagesChanged(from old: MeetingLanguages?) {
        guard let meetingLanguages, meetingLanguages != old else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(meetingLanguages), forKey: SettingsKey.meetingLanguages)
        recorder.detectionLanguage = meetingLanguages.defaultLanguage
        if meetingLanguages.chosen != old?.chosen { languageAssets.keep(meetingLanguages.chosen) }
    }

    /// The language a manual Meeting starts in.
    func nextMeetingLanguage() async -> Locale? {
        if let meetingLanguages { return meetingLanguages.defaultLanguage }
        return await supportedSystemLanguage()
    }

    /// `supportedLocale(equivalentTo:)` has been seen echoing unsupported tags such as nb-NO, so its answer must
    /// also be in `supportedLocales`.
    private func supportedSystemLanguage() async -> Locale? {
        guard let language = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { return nil }
        let tag = language.identifier(.bcp47)
        guard await SpeechTranscriber.supportedLocales.contains(where: { $0.identifier(.bcp47) == tag }) else { return nil }
        return language
    }

    /// The language the Meeting Language submenu checks: the live Meeting's, or the next Meeting's.
    var menuLanguage: Locale? {
        switch recorder.state {
        case .live(let meeting), .finishing(let meeting): meeting.language
        case .idle: meetingLanguages?.defaultLanguage
        }
    }

    /// The submenu's languages: the checked ones, plus the live Meeting's if it was unchecked since.
    var menuLanguages: [Locale] {
        let chosen = meetingLanguages?.chosen ?? []
        guard let current = menuLanguage, !chosen.contains(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) })
        else { return chosen }
        return MeetingLanguages.listed(chosen + [current])
    }

    func languageName(_ language: Locale) -> String {
        meetingLanguages?.name(of: language) ?? Notifier.languageName(language)
    }

    /// The submenu's choice: while live, re-transcribes the Meeting in it; otherwise, the next Meeting starts in it.
    func chooseMeetingLanguage(_ language: Locale) {
        switch recorder.state {
        case .live: switchLanguage(to: language)
        case .idle: meetingLanguages?.defaultLanguage = language
        case .finishing: break
        }
    }

    /// Re-transcribes the live Meeting from the start in `language`. The start banner then says the new language.
    func switchLanguage(to language: Locale) {
        Task {
            do {
                try await recorder.switchLanguage(to: language)
                if case .live(let meeting) = recorder.state {
                    notifier.restateStarted(meeting, languages: meetingLanguages)
                    AccessibilityNotification.Announcement("Transcribing in \(languageName(language))").post()
                }
            } catch {
                present(error, title: "Carbon couldn't switch to \(languageName(language))")
            }
        }
    }
}
