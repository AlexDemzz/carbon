import CarbonCore
import Foundation
import Speech
import SwiftUI

extension AppModel {
    /// Once permissions allow Detection, or when the onboarding's Languages step appears, whichever comes first: the
    /// saved Meeting Languages, or, the first time, the Mac's languages. Their assets are reserved and downloaded.
    /// The second caller waits for the first one's load.
    func loadMeetingLanguages() async {
        let load = meetingLanguagesLoad ?? Task { await loadMeetingLanguagesOnce() }
        meetingLanguagesLoad = load
        await load.value
    }

    private func loadMeetingLanguagesOnce() async {
        await languageAssets.loadSupported()
        if let meetingLanguages {
            recorder.detectionLanguage = meetingLanguages.defaultLanguage
            languageAssets.keep(meetingLanguages.chosen)
        } else {
            meetingLanguages = Self.macLanguages(supported: languageAssets.supported)
        }
    }

    /// System Settings › General › Language & Region's languages.
    private static func macLanguages(supported: [Locale]) -> MeetingLanguages {
        MeetingLanguages.seeded(
            from: Locale.preferredLanguages.map(Locale.init(identifier:)), supported: supported,
            cap: AssetInventory.maximumReservedLocales)
    }

    func meetingLanguagesChanged(from old: MeetingLanguages?) {
        guard let meetingLanguages, meetingLanguages != old else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(meetingLanguages), forKey: SettingsKey.meetingLanguages)
        recorder.detectionLanguage = meetingLanguages.defaultLanguage
        if meetingLanguages.chosen != old?.chosen { languageAssets.keep(meetingLanguages.chosen) }
    }

    /// The checked languages a Meeting may turn out to be spoken in: those whose assets are ready. None when
    /// "Identify the Meeting Language automatically" is off.
    var meetingLanguageCandidates: [Locale] {
        guard UserDefaults.standard.bool(forKey: SettingsKey.identifyMeetingLanguage), let meetingLanguages else {
            return []
        }
        return meetingLanguages.chosen.filter { languageAssets.state(of: $0) == .ready }
    }

    /// The language a manual Meeting starts in.
    func nextMeetingLanguage() async -> Locale {
        if let meetingLanguages { return meetingLanguages.defaultLanguage }
        return Self.macLanguages(supported: await SpeechTranscriber.supportedLocales).defaultLanguage
    }

    /// The language the menu bar's language submenu checks: the live Meeting's, or the next Meeting's.
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
                if case .live(let meeting) = recorder.state { meetingLanguageChanged(meeting) }
            } catch {
                present(error, title: "Carbon couldn't switch to \(languageName(language))")
            }
        }
    }

    /// The live Meeting is now transcribed in another language, picked by the person or identified.
    func meetingLanguageChanged(_ meeting: LiveMeeting) {
        notifier.restateStarted(meeting, languages: meetingLanguages)
        AccessibilityNotification.Announcement("Transcribing in \(languageName(meeting.language))").post()
    }
}
