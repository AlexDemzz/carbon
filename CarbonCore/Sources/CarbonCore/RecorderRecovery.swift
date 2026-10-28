@preconcurrency import AVFoundation
import Foundation

/// What launch recovery did with one interrupted Meeting, for its notification.
public enum Recovery: Equatable, Sendable {
    /// Finished from the audio on disk and written to the Library.
    case recovered(title: String, file: URL)
    /// No audio could be read: the folder is gone.
    case discarded(title: String)
    /// Recovery crashed twice on it (or its `state.json` is unreadable): set aside in `InProgress/Failed/`.
    case failed(title: String?)
}

extension Recorder {
    static let recoveryAttemptsAllowed = 2

    /// Finishes every Meeting a crash interrupted, from the audio flushed to its in-progress folder.
    /// Call at launch, before any Meeting starts. A folder whose recovery fails stays for the next launch.
    public func recover() async -> [Recovery] {
        guard state == .idle, recording == nil else { return [] }
        var recoveries: [Recovery] = []
        for folder in InProgressMeeting.interrupted(in: inProgressRoot) {
            if let recovery = await recover(folder) { recoveries.append(recovery) }
        }
        return recoveries
    }

    private func recover(_ folder: InProgressMeeting) async -> Recovery? {
        guard var saved = try? folder.state(), let start = try? Date(saved.start, strategy: .iso8601) else {
            folder.moveToFailed()
            return .failed(title: nil)
        }
        let meeting = LiveMeeting(
            id: saved.id, title: MeetingFormat.defaultTitle(start: start, in: timeZone), start: start,
            language: Locale(identifier: Locale.identifier(.icu, from: saved.language)))
        guard saved.recoveryAttempts < Self.recoveryAttemptsAllowed else {
            folder.moveToFailed()
            return .failed(title: meeting.title)
        }
        // Counted before the work, so a crash during it still counts.
        saved.recoveryAttempts += 1
        try? folder.write(saved)

        let me = Self.readableAudio(at: folder.meAudio)
        let them = Self.readableAudio(at: folder.themAudio)
        guard let seconds = [me, them].compactMap(\.self).max(), seconds > 0 else {
            folder.remove()
            return .discarded(title: meeting.title)
        }
        state = .finishing(meeting)
        defer { state = .idle }
        let transcriber = transcriber
        let file = try? await finish(meeting, end: start + seconds, folder: folder) {
            async let meWords = Self.transcribe(
                me == nil ? nil : folder.meAudio, as: .me, in: meeting.language, with: transcriber)
            async let themWords = Self.transcribe(
                them == nil ? nil : folder.themAudio, as: .them, in: meeting.language, with: transcriber)
            return (try await meWords, try await themWords)
        }
        return file.map { .recovered(title: meeting.title, file: $0) }
    }

    /// The seconds of audio in the file, or nil when it can't be read.
    private static func readableAudio(at url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Batch-transcribes a recorded stream by feeding the file to a fresh session. No file, no words.
    private nonisolated static func transcribe(
        _ url: URL?, as stream: AudioStream, in language: Locale, with transcriber: any Transcriber
    ) async throws -> [TranscribedWord] {
        guard let url else { return [] }
        let session = try await transcriber.start(locale: language, stream: stream)
        let format = session.audioFormat
        let file = try AVAudioFile(forReading: url, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate)
        var converter: AVAudioConverter?
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
                throw CocoaError(.featureUnsupported)
            }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            session.append(try StreamRecorder.convert(buffer, to: format, with: &converter))
        }
        return try await session.finish()
    }
}
