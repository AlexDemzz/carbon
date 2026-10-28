@preconcurrency import AVFoundation
import CarbonCore
import CoreAudio
import Foundation
import Synchronization

/// The Them stream: a global Core Audio process tap on everything the Mac plays except Carbon,
/// read through a private tap-only aggregate device. Ticket 03 narrows it to the Meeting App.
final class SystemAudioTap: AudioSource {
    enum Failure: LocalizedError {
        case coreAudio(step: String, status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .coreAudio(let step, let status): "Carbon couldn't capture the call's audio (\(step), error \(status))."
            }
        }
    }

    private struct Running {
        var tap = AudioObjectID(kAudioObjectUnknown)
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        var ioProc: AudioDeviceIOProcID?
    }

    private let running = Mutex(Running())
    private let queue = DispatchQueue(label: "me.alexandrejoly.carbon.system-audio-tap")

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        try running.withLock { running in
            do {
                try Self.start(&running, queue: queue, onBuffer: onBuffer)
            } catch {
                Self.tearDown(&running)
                throw error
            }
        }
    }

    func stop() {
        running.withLock { Self.tearDown(&$0) }
    }

    private static func start(
        _ running: inout Running, queue: DispatchQueue, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: try carbonProcess().map { [$0] } ?? [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check("createTap", AudioHardwareCreateProcessTap(description, &running.tap))

        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        try check("readFormat", AudioObjectGetPropertyData(running.tap, &address, 0, nil, &size, &streamDescription))
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw Failure.coreAudio(step: "readFormat", status: kAudioHardwareUnsupportedOperationError)
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Carbon Them",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
            ],
        ]
        try check("createAggregate", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &running.aggregate))

        try check(
            "createIOProc",
            AudioDeviceCreateIOProcIDWithBlock(&running.ioProc, running.aggregate, queue) { _, input, _, _, _ in
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
    }

    private static func tearDown(_ running: inout Running) {
        if let ioProc = running.ioProc {
            AudioDeviceStop(running.aggregate, ioProc)
            AudioDeviceDestroyIOProcID(running.aggregate, ioProc)
        }
        if running.aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(running.aggregate) }
        if running.tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(running.tap) }
        running = Running()
    }

    /// Carbon's own Core Audio process object, or nil while Carbon has no audio process yet.
    private static func carbonProcess() throws -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var process = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        try check(
            "findCarbon",
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size,
                &process))
        return process == kAudioObjectUnknown ? nil : process
    }

    private static func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw Failure.coreAudio(step: step, status: status) }
    }
}
