import CarbonCore
import CoreAudio
import Foundation
import Synchronization

/// Where the Mac's sound plays, from Core Audio: the output devices other processes play to, or the default output
/// when nothing plays. `OutputRoute.of(_:)` decides from the devices' facts; any failed read is `speakers`.
/// Listeners on the default output, the device list and the process list sample at once; a 2 s poll is the backstop,
/// as a process's devices give no reliable change notification. A change is yielded only once two consecutive
/// samples, at least a second apart, agree on it.
final class CoreAudioOutputRoute: OutputRouteSource {
    func routes() -> AsyncStream<OutputRoute> {
        let (stream, continuation) = AsyncStream.makeStream(of: OutputRoute.self, bufferingPolicy: .bufferingNewest(1))
        let running = Running { continuation.yield($0) }
        continuation.onTermination = { _ in running.stop() }
        running.start()
        return stream
    }

    /// The facts of every output device another process plays to, or of the default output when none plays.
    /// Nil when anything can't be read.
    static func playingDevices() -> [OutputDevice]? {
        guard let ids = playingDeviceIDs() else { return nil }
        var devices: [OutputDevice] = []
        for id in ids {
            guard let name = AudioProcesses.string(kAudioObjectPropertyName, of: id) else { return nil }
            if name == SystemAudioTap.aggregateName { continue }
            guard let device = OutputDevices.facts(of: id, named: name) else { return nil }
            devices.append(device)
        }
        return devices
    }

    private static func playingDeviceIDs() -> [AudioObjectID]? {
        guard let processes = AudioProcesses.objectList(of: AudioProcesses.system, kAudioHardwarePropertyProcessObjectList)
        else { return nil }
        let carbon = AudioProcesses.carbon()
        var ids: [AudioObjectID] = []
        for process in processes where process != carbon {
            guard let playing = AudioProcesses.uint32(kAudioProcessPropertyIsRunningOutput, of: process) else {
                return nil
            }
            guard playing != 0 else { continue }
            guard
                let devices = AudioProcesses.objectList(
                    of: process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
            else { return nil }
            for device in devices where !ids.contains(device) { ids.append(device) }
        }
        if !ids.isEmpty { return ids }
        guard
            let fallback = AudioProcesses.uint32(kAudioHardwarePropertyDefaultOutputDevice, of: AudioProcesses.system),
            fallback != kAudioObjectUnknown
        else { return nil }
        return [fallback]
    }

    private final class Running: Sendable {
        private let emit: @Sendable (OutputRoute) -> Void
        private let queue = DispatchQueue(label: "me.alexandrejoly.carbon.output-route")
        /// The listener and the timer, so `start` and `stop` hold in either order. Listener blocks never take it.
        private let lifecycle = Mutex(Lifecycle())
        private let state = Mutex(State())

        private struct Lifecycle: @unchecked Sendable {
            var timer: DispatchSourceTimer?
            var listener: AudioObjectPropertyListenerBlock?
            var stopped = false
        }

        private struct State: Sendable {
            var stopped = false
            var yielded: OutputRoute?
            /// A route differing from the one yielded, and when it was first sampled.
            var candidate: (route: OutputRoute, since: Date)?
        }

        private static let watched = [
            kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyProcessObjectList,
        ]
        private static let interval: TimeInterval = 2
        /// Two samples closer than this, such as two listener callbacks in one switch, don't confirm a change.
        private static let settle: TimeInterval = 1

        init(emit: @escaping @Sendable (OutputRoute) -> Void) {
            self.emit = emit
        }

        func start() {
            lifecycle.withLock { lifecycle in
                guard !lifecycle.stopped, lifecycle.timer == nil else { return }
                let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.sample() }
                for selector in Self.watched {
                    var address = AudioProcesses.address(selector)
                    AudioObjectAddPropertyListenerBlock(AudioProcesses.system, &address, queue, listener)
                }
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now(), repeating: Self.interval)
                timer.setEventHandler { [weak self] in self?.sample() }
                timer.resume()
                lifecycle.listener = listener
                lifecycle.timer = timer
            }
        }

        func stop() {
            state.withLock { $0.stopped = true }
            lifecycle.withLock { lifecycle in
                guard !lifecycle.stopped else { return }
                lifecycle.stopped = true
                lifecycle.timer?.cancel()
                if let listener = lifecycle.listener {
                    for selector in Self.watched {
                        var address = AudioProcesses.address(selector)
                        AudioObjectRemovePropertyListenerBlock(AudioProcesses.system, &address, queue, listener)
                    }
                }
                lifecycle.timer = nil
                lifecycle.listener = nil
            }
        }

        private func sample() {
            let route = CoreAudioOutputRoute.playingDevices().map(OutputRoute.of) ?? .speakers
            let now = Date()
            let settled: OutputRoute? = state.withLock { state in
                guard !state.stopped else { return nil }
                guard let yielded = state.yielded else {
                    state.yielded = route
                    return route
                }
                guard route != yielded else {
                    state.candidate = nil
                    return nil
                }
                guard let candidate = state.candidate, candidate.route == route else {
                    state.candidate = (route, now)
                    return nil
                }
                guard now.timeIntervalSince(candidate.since) >= Self.settle else { return nil }
                state.yielded = route
                state.candidate = nil
                return route
            }
            if let settled { emit(settled) }
        }
    }
}

/// Core Audio reads for output devices. Each returns nil when the read fails.
private enum OutputDevices {
    static func facts(of device: AudioObjectID, named name: String) -> OutputDevice? {
        guard let transport = AudioProcesses.uint32(kAudioDevicePropertyTransportType, of: device),
            let streams = AudioProcesses.objectList(
                of: device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        else { return nil }
        var terminalTypes: [UInt32] = []
        for stream in streams {
            guard let terminalType = AudioProcesses.uint32(kAudioStreamPropertyTerminalType, of: stream) else {
                return nil
            }
            terminalTypes.append(terminalType)
        }
        var dataSource: UInt32?
        var address = AudioProcesses.address(kAudioDevicePropertyDataSource)
        address.mScope = kAudioObjectPropertyScopeOutput
        if AudioObjectHasProperty(device, &address) {
            guard
                let source = AudioProcesses.uint32(
                    kAudioDevicePropertyDataSource, of: device, scope: kAudioObjectPropertyScopeOutput)
            else { return nil }
            dataSource = source
        }
        return OutputDevice(
            name: name, transport: Self.transport(transport), terminalTypes: terminalTypes, dataSource: dataSource)
    }

    static func transport(_ type: UInt32) -> OutputDevice.Transport {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBluetooth: .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE: .bluetoothLE
        default: .other
        }
    }
}
