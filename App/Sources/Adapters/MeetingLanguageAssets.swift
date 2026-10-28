import CarbonCore
import Observation
import Speech

/// Keeps the Meeting Languages' SpeechTranscriber assets on this Mac: reserved with `AssetInventory`, downloaded
/// when missing, and their download state for Settings › Languages.
@MainActor
@Observable
final class MeetingLanguageAssets {
    enum State: Equatable {
        case downloading
        case ready
        case failed
    }

    /// The languages SpeechTranscriber supports, in Settings order.
    private(set) var supported: [Locale] = []
    private var states: [String: State] = [:]
    @ObservationIgnored private var work: Task<Void, Never>?

    /// Nil while it hasn't been checked, or for an unchecked language.
    func state(of language: Locale) -> State? {
        states[language.identifier(.bcp47)]
    }

    func loadSupported() async {
        supported = MeetingLanguages.listed(await SpeechTranscriber.supportedLocales)
    }

    /// Reserves every language in `languages`, releases the others, and downloads what is missing.
    /// Calls run one after the other, so a quick series of checkbox clicks ends in the last one's state.
    func keep(_ languages: [Locale]) {
        work = Task { [previous = work] in
            await previous?.value
            await sync(languages)
        }
    }

    private func sync(_ languages: [Locale]) async {
        let wanted = Set(languages.map { $0.identifier(.bcp47) })
        states = states.filter { wanted.contains($0.key) }
        for reserved in await AssetInventory.reservedLocales where !wanted.contains(reserved.identifier(.bcp47)) {
            _ = await AssetInventory.release(reservedLocale: reserved)
        }
        for language in languages {
            await keep(language)
        }
    }

    private func keep(_ language: Locale) async {
        let id = language.identifier(.bcp47)
        do {
            if try await !AssetInventory.reserve(locale: language) {
                DiagnosticLog.shared.write(
                    "\(id) not reserved: at most \(AssetInventory.maximumReservedLocales) languages can be")
            }
            let module = SpeechTranscriberAdapter.module(for: language)
            guard await AssetInventory.status(forModules: [module]) != .installed else {
                states[id] = .ready
                return
            }
            states[id] = .downloading
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
            states[id] = .ready
        } catch {
            DiagnosticLog.shared.write("\(id) assets not downloaded: \(error.localizedDescription)")
            states[id] = .failed
        }
    }
}
