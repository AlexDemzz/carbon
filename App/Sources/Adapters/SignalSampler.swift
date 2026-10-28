import CarbonCore
import CoreAudio
import Foundation
import Synchronization

/// Detection's mic signal: which apps hold the microphone, from Core Audio's process list.
/// Property listeners on the list and on each process's `IsRunningInput` / `IsRunningOutput` sample at once;
/// a 1 s poll is the backstop, so a snapshot arrives at least every second for the Detector's timers.
final class SignalSampler: SignalSource {
    private let vendorTable: VendorTable
    private let log: DiagnosticLog
    private let calendar: CalendarEvents

    init(vendorTable: VendorTable = .shipped, log: DiagnosticLog = .shared, calendar: CalendarEvents = CalendarEvents()) {
        self.vendorTable = vendorTable
        self.log = log
        self.calendar = calendar
    }

    func micSnapshots() -> AsyncStream<MicSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: MicSnapshot.self, bufferingPolicy: .bufferingNewest(4))
        let running = Running(vendorTable: vendorTable, log: log, calendar: calendar) { continuation.yield($0) }
        continuation.onTermination = { _ in running.stop() }
        running.start()
        return stream
    }

    private final class Running: Sendable {
        private let vendorTable: VendorTable
        private let log: DiagnosticLog
        private let calendar: CalendarEvents
        private let emit: @Sendable (MicSnapshot) -> Void
        private let queue = DispatchQueue(label: "me.alexandrejoly.carbon.signal-sampler")
        private let state = Mutex(State())

        private struct State: @unchecked Sendable {
            var timer: DispatchSourceTimer?
            var listListener: AudioObjectPropertyListenerBlock?
            /// The listeners installed on each process, to remove them when the process goes. Never read for sampling.
            var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
            var stopped = false
            var lastAssertionPoll: Date?
            /// The last poll found a call or WebRTC assertion.
            var callAssertionsSeen = false
        }

        private static let watched = [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput]

        init(
            vendorTable: VendorTable, log: DiagnosticLog, calendar: CalendarEvents,
            emit: @escaping @Sendable (MicSnapshot) -> Void
        ) {
            self.calendar = calendar
            self.vendorTable = vendorTable
            self.log = log
            self.emit = emit
        }

        func start() {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.relisten()
                self?.sample()
            }
            var address = AudioProcesses.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectAddPropertyListenerBlock(AudioProcesses.system, &address, queue, listener)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1)
            timer.setEventHandler { [weak self] in self?.sample() }
            state.withLock {
                $0.listListener = listener
                $0.timer = timer
            }
            queue.async { [weak self] in self?.relisten() }
            timer.resume()
        }

        func stop() {
            // Listener blocks take the lock: remove them outside it.
            let stopped = state.withLock { state in
                defer { state = State(stopped: true) }
                return state
            }
            stopped.timer?.cancel()
            if let listener = stopped.listListener {
                var address = AudioProcesses.address(kAudioHardwarePropertyProcessObjectList)
                AudioObjectRemovePropertyListenerBlock(AudioProcesses.system, &address, queue, listener)
            }
            for (id, listener) in stopped.processListeners {
                for selector in Self.watched {
                    var address = AudioProcesses.address(selector)
                    AudioObjectRemovePropertyListenerBlock(id, &address, queue, listener)
                }
            }
        }

        /// Moves the per-process listeners onto the current process list.
        private func relisten() {
            let current = Set(AudioProcesses.ids())
            state.withLock { state in
                guard !state.stopped else { return }
                for (id, listener) in state.processListeners where !current.contains(id) {
                    for selector in Self.watched {
                        var address = AudioProcesses.address(selector)
                        AudioObjectRemovePropertyListenerBlock(id, &address, queue, listener)
                    }
                    state.processListeners[id] = nil
                }
                for id in current where state.processListeners[id] == nil {
                    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.sample() }
                    for selector in Self.watched {
                        var address = AudioProcesses.address(selector)
                        AudioObjectAddPropertyListenerBlock(id, &address, queue, listener)
                    }
                    state.processListeners[id] = listener
                }
            }
        }

        private func sample() {
            var holders: [MeetingApp] = []
            for process in AudioProcesses.all() where process.isRunningInput {
                guard let owner = process.owner, !holders.contains(owner) else { continue }
                holders.append(owner)
                if !vendorTable.knows(owner.bundleID) {
                    log.writeOnce(
                        key: "mic-holder:\(owner.bundleID)",
                        "Unmatched mic holder: \(owner.bundleID) (\(owner.name))")
                }
            }
            let now = Date()
            let events = calendar.current
            let inWindow = events.contains { EventMatcher.isCandidate($0, at: now) }
            let assertions = pollAssertions(at: now, wanted: !holders.isEmpty || inWindow)
            emit(MicSnapshot(time: now, micHolders: holders, events: events, assertions: assertions))
        }

        /// Polls the power assertions every 3 s while the mic is held or an Event is in its window, and on until the
        /// last call or WebRTC assertion seen is gone, so the Detector sees a call's assertion released after its mic.
        private func pollAssertions(at now: Date, wanted: Bool) -> [PowerAssertion]? {
            let due = state.withLock { state in
                guard wanted || state.callAssertionsSeen,
                    state.lastAssertionPoll.map({ now.timeIntervalSince($0) >= Self.assertionPollInterval }) ?? true
                else { return false }
                state.lastAssertionPoll = now
                return true
            }
            guard due else { return nil }
            let assertions = PowerAssertions.all()
            var seen = false
            for assertion in assertions {
                guard let kind = vendorTable.kind(of: assertion) else { continue }
                seen = true
                let label = kind == .call ? "Call" : "WebRTC"
                log.writeOnce(
                    key: "assertion:\(label):\(assertion.app.bundleID):\(assertion.name)",
                    "\(label) assertion: \(assertion.app.bundleID) (\(assertion.app.name)) "
                        + "\"\(assertion.name)\" \(assertion.type)")
            }
            state.withLock { $0.callAssertionsSeen = seen }
            return assertions
        }

        private static let assertionPollInterval: TimeInterval = 3
    }
}
