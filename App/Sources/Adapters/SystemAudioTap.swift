@preconcurrency import AVFoundation
import CarbonCore
import CoreAudio
import Foundation
import Synchronization

/// The Them stream: one Core Audio process tap on every process the Meeting App owns, read through a private
/// tap-only aggregate device. Without a Meeting App, a global tap on everything the Mac plays except Carbon.
///
/// - When the Meeting App's processes change, the running tap's `kAudioTapPropertyDescription` is updated in place.
/// - The aggregate is rebuilt only when the device list changes.
/// - Fallback: the Meeting App reports output but the tap has had no callbacks for 5 s → re-resolve its processes;
///   still nothing 5 s later → switch to a global tap excluding Carbon.
final class SystemAudioTap: AudioSource {
    enum Failure: LocalizedError {
        case coreAudio(step: String, status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .coreAudio(let step, let status): "Carbon couldn't capture the call's audio (\(step), error \(status))."
            }
        }
    }

    static let silentTapTimeout: TimeInterval = 5
    /// The name of Carbon's private aggregate device, which other adapters leave out of the Mac's devices.
    static let aggregateName = "Carbon Them"

    private enum Target: Equatable {
        case app([AudioObjectID])
        case global
    }

    private struct Running: @unchecked Sendable {
        var description: CATapDescription?
        var target = Target.global
        var tap = AudioObjectID(kAudioObjectUnknown)
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        var ioProc: AudioDeviceIOProcID?
        var devices: Set<AudioObjectID> = []
        var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
        var processListener: AudioObjectPropertyListenerBlock?
        var deviceListener: AudioObjectPropertyListenerBlock?
        var watchdog: DispatchSourceTimer?
        /// Set once the fallback re-resolved the processes, so the next silent stretch goes global.
        var reResolved = false
    }

    /// When the tap last delivered a callback.
    private final class Heartbeat: Sendable {
        private let date = Mutex(Date())

        var last: Date { date.withLock { $0 } }

        func beat() {
            date.withLock { $0 = Date() }
        }
    }

    private let app: MeetingApp?
    private let log: DiagnosticLog
    private let running = Mutex(Running())
    private let lastCallback = Heartbeat()
    private let queue = DispatchQueue(label: "me.alexandrejoly.carbon.system-audio-tap")

    init(app: MeetingApp?, log: DiagnosticLog = .shared) {
        self.app = app
        self.log = log
    }

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        try running.withLock { running in
            do {
                running.onBuffer = onBuffer
                try startTap(&running)
                try startAggregate(&running)
                listen(&running)
            } catch {
                tearDown(&running)
                throw error
            }
        }
    }

    func stop() {
        // Listener blocks take the lock: remove them outside it, after the listeners already see a stopped tap.
        var stopped = running.withLock { running in
            defer { running = Running() }
            return running
        }
        tearDown(&stopped)
    }

    // MARK: Tap

    private func currentTarget() -> Target {
        guard let app else { return .global }
        return .app(AudioProcesses.owned(by: app).map(\.id).sorted())
    }

    private static func makeDescription(for target: Target) -> CATapDescription {
        switch target {
        case .app(let processes):
            return CATapDescription(stereoMixdownOfProcesses: processes)
        case .global:
            return CATapDescription(stereoGlobalTapButExcludeProcesses: AudioProcesses.carbon().map { [$0] } ?? [])
        }
    }

    private func startTap(_ running: inout Running) throws {
        let target = currentTarget()
        let description = Self.makeDescription(for: target)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check("createTap", AudioHardwareCreateProcessTap(description, &running.tap))
        running.description = description
        running.target = target
        if let app { log.write("Tap on \(app.bundleID): \(target)") }
    }

    /// Points the running tap at `target` without rebuilding anything.
    private func retarget(_ running: inout Running, to target: Target) {
        guard let description = running.description, target != running.target else { return }
        switch target {
        case .app(let processes):
            description.processes = processes
            description.isExclusive = false
        case .global:
            description.processes = AudioProcesses.carbon().map { [$0] } ?? []
            description.isExclusive = true
        }
        var object = Unmanaged.passUnretained(description).toOpaque()
        var address = AudioProcesses.address(kAudioTapPropertyDescription)
        let status = AudioObjectSetPropertyData(
            running.tap, &address, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &object)
        if status == noErr {
            running.target = target
            log.write("Tap updated to \(target)")
        } else {
            log.write("Tap update to \(target) failed: \(status)")
        }
    }

    // MARK: Aggregate

    private func startAggregate(_ running: inout Running) throws {
        guard let description = running.description, let onBuffer = running.onBuffer else { return }
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioProcesses.address(kAudioTapPropertyFormat)
        try check("readFormat", AudioObjectGetPropertyData(running.tap, &address, 0, nil, &size, &streamDescription))
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw Failure.coreAudio(step: "readFormat", status: kAudioHardwareUnsupportedOperationError)
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.aggregateName,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
            ],
        ]
        try check("createAggregate", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &running.aggregate))

        let lastCallback = lastCallback
        lastCallback.beat()
        try check(
            "createIOProc",
            AudioDeviceCreateIOProcIDWithBlock(&running.ioProc, running.aggregate, queue) { _, input, _, _, _ in
                lastCallback.beat()
                // The callback's buffers are only valid during the call: hand on a copy.
                guard let wrapped = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil),
                    let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: wrapped.frameLength)
                else { return }
                copy.frameLength = wrapped.frameLength
                let from = UnsafeMutableAudioBufferListPointer(wrapped.mutableAudioBufferList)
                let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                for (source, destination) in zip(from, to) {
                    guard let data = source.mData, let target = destination.mData else { continue }
                    memcpy(target, data, Int(min(source.mDataByteSize, destination.mDataByteSize)))
                }
                onBuffer(copy)
            })
        try check("startDevice", AudioDeviceStart(running.aggregate, running.ioProc))
        running.devices = otherDevices(than: running.aggregate)
    }

    private func stopAggregate(_ running: inout Running) {
        if let ioProc = running.ioProc {
            AudioDeviceStop(running.aggregate, ioProc)
            AudioDeviceDestroyIOProcID(running.aggregate, ioProc)
        }
        if running.aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(running.aggregate) }
        running.ioProc = nil
        running.aggregate = AudioObjectID(kAudioObjectUnknown)
    }

    /// The device list, without Carbon's own aggregate, whose creation changes the list too.
    private func otherDevices(than aggregate: AudioObjectID) -> Set<AudioObjectID> {
        Set(AudioProcesses.devices()).subtracting([aggregate])
    }

    // MARK: Listeners

    private func listen(_ running: inout Running) {
        let processListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.processesChanged() }
        var processes = AudioProcesses.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioProcesses.system, &processes, queue, processListener)
        running.processListener = processListener

        let deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.devicesChanged() }
        var devices = AudioProcesses.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioProcesses.system, &devices, queue, deviceListener)
        running.deviceListener = deviceListener

        guard app != nil else { return }
        let watchdog = DispatchSource.makeTimerSource(queue: queue)
        watchdog.schedule(deadline: .now() + 1, repeating: 1)
        watchdog.setEventHandler { [weak self] in self?.checkCallbacks() }
        watchdog.resume()
        running.watchdog = watchdog
    }

    private func processesChanged() {
        running.withLock { running in
            guard running.target != .global else { return }
            retarget(&running, to: currentTarget())
        }
    }

    private func devicesChanged() {
        running.withLock { running in
            guard running.aggregate != kAudioObjectUnknown,
                otherDevices(than: running.aggregate) != running.devices
            else { return }
            log.write("Device list changed: rebuilding the Them aggregate")
            stopAggregate(&running)
            do {
                try startAggregate(&running)
            } catch {
                log.write("Rebuilding the Them aggregate failed: \(error.localizedDescription)")
            }
        }
    }

    private func checkCallbacks() {
        guard let app else { return }
        let silentFor = Date().timeIntervalSince(lastCallback.last)
        guard silentFor >= Self.silentTapTimeout,
            AudioProcesses.owned(by: app).contains(where: \.isRunningOutput)
        else { return }
        running.withLock { running in
            guard running.target != .global else { return }
            if running.reResolved {
                log.write("No tap callbacks for 5 s while \(app.bundleID) plays: switching to a global tap")
                retarget(&running, to: .global)
            } else {
                log.write("No tap callbacks for 5 s while \(app.bundleID) plays: re-resolving its processes")
                running.reResolved = true
                retarget(&running, to: currentTarget())
            }
        }
        lastCallback.beat()
    }

    private func tearDown(_ running: inout Running) {
        running.watchdog?.cancel()
        if let listener = running.processListener {
            var address = AudioProcesses.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioProcesses.system, &address, queue, listener)
        }
        if let listener = running.deviceListener {
            var address = AudioProcesses.address(kAudioHardwarePropertyDevices)
            AudioObjectRemovePropertyListenerBlock(AudioProcesses.system, &address, queue, listener)
        }
        stopAggregate(&running)
        if running.tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(running.tap) }
        running = Running()
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw Failure.coreAudio(step: step, status: status) }
    }
}
