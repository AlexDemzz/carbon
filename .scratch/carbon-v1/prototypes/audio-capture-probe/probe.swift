// PROTOTYPE — throwaway probe for "Audio capture probe across meeting apps". Not production code.
//
// Usage:
//   ./probe                       watch which processes run audio input/output (JSON lines)
//   ./probe <bundle-id> [secs]    also open 3 taps side by side and record each to WAV:
//                                   bundle  — macOS 26 `bundleIDs = [<bundle-id>]` (+ process restore)
//                                   prefix  — process objects whose bundle ID starts with <bundle-id>, or whose executable path
//                                             contains it (helpers included), resolved at start
//                                   global  — every process
//
// Output: JSON lines on stdout, mirrored with WAVs to ~/CarbonProbe/<timestamp>/.

import AVFoundation
import CoreAudio
import Darwin
import Foundation

// MARK: - Logging

let runDir: URL = {
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("CarbonProbe/\(stamp)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()
let logHandle: FileHandle = {
    let url = runDir.appendingPathComponent("log.jsonl")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    return try! FileHandle(forWritingTo: url)
}()
let logQueue = DispatchQueue(label: "log")
let start = Date()

func log(_ event: String, _ fields: [String: Any] = [:]) {
    var all = fields
    all["event"] = event
    all["t"] = (Date().timeIntervalSince(start) * 10).rounded() / 10
    let data = try! JSONSerialization.data(withJSONObject: all, options: [.sortedKeys])
    logQueue.async {
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        logHandle.write(data + Data("\n".utf8))
    }
}

// MARK: - Core Audio helpers

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

func readArray<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _: T.Type) -> [T] {
    var addr = address(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<T>.stride
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
    defer { pointer.deallocate() }
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, pointer) == noErr else { return [] }
    return Array(UnsafeBufferPointer(start: pointer.bindMemory(to: T.self, capacity: count), count: count))
}

func readValue<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
    var addr = address(selector)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
}

func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

func executablePath(pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
}

struct AudioProcess: Equatable {
    let object: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let path: String
    let input: Bool
    let output: Bool
    let devices: [String]
}

func deviceName(_ id: AudioObjectID) -> String {
    readString(id, kAudioObjectPropertyName) ?? "#\(id)"
}

func audioProcesses() -> [AudioProcess] {
    readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList, AudioObjectID.self).map { object in
        let pid = readValue(object, kAudioProcessPropertyPID, pid_t(0)) ?? 0
        return AudioProcess(
            object: object,
            pid: pid,
            bundleID: readString(object, kAudioProcessPropertyBundleID) ?? "",
            path: executablePath(pid: pid),
            input: (readValue(object, kAudioProcessPropertyIsRunningInput, UInt32(0)) ?? 0) != 0,
            output: (readValue(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) != 0,
            devices: readArray(object, kAudioProcessPropertyDevices, AudioObjectID.self).map(deviceName)
        )
    }
}

func describeDevice(_ selector: AudioObjectPropertySelector) -> [String: Any] {
    guard let id = readValue(AudioObjectID(kAudioObjectSystemObject), selector, AudioObjectID(0)) else { return [:] }
    return [
        "name": deviceName(id),
        "nominalRate": readValue(id, kAudioDevicePropertyNominalSampleRate, Float64(0)) ?? 0,
        "transport": fourCC(readValue(id, kAudioDevicePropertyTransportType, UInt32(0)) ?? 0),
    ]
}

func fourCC(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii) ?? "\(value)"
}

// MARK: - Process watcher

var lastSeen: [AudioObjectID: AudioProcess] = [:]

func pollProcesses() {
    var current: [AudioObjectID: AudioProcess] = [:]
    for process in audioProcesses() where process.input || process.output {
        current[process.object] = process
    }
    for (object, process) in current where lastSeen[object] != process {
        log("process", [
            "pid": process.pid, "bundleID": process.bundleID, "path": process.path,
            "input": process.input, "output": process.output, "devices": process.devices,
        ])
    }
    for (object, process) in lastSeen where current[object] == nil {
        log("process", ["pid": process.pid, "bundleID": process.bundleID, "input": false, "output": false])
    }
    lastSeen = current
}

func watchDefaultDevices() {
    for (selector, name) in [(kAudioHardwarePropertyDefaultInputDevice, "defaultInput"), (kAudioHardwarePropertyDefaultOutputDevice, "defaultOutput")] {
        log(name, describeDevice(selector))
        var addr = address(selector)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
            log(name, describeDevice(selector))
        }
    }
}

// MARK: - Taps

final class TapRecorder {
    let label: String
    let description: CATapDescription
    var tapID = AudioObjectID(kAudioObjectUnknown)
    var aggregateID = AudioObjectID(kAudioObjectUnknown)
    var procID: AudioDeviceIOProcID?
    var file: AVAudioFile?
    var format: AVAudioFormat?
    let queue: DispatchQueue

    // Per-second window, touched only on `queue`.
    var frames = 0
    var sampleCount = 0
    var sumSquares: Double = 0
    var peak: Float = 0
    var callbacks = 0
    var totalFrames = 0
    var silentSeconds = 0

    init(label: String, description: CATapDescription) {
        self.label = label
        self.description = description
        self.queue = DispatchQueue(label: "tap.\(label)")
    }

    func start() {
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { return log("tapError", ["tap": label, "step": "createTap", "status": status]) }

        guard var asbd = readValue(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription()),
              let format = AVAudioFormat(streamDescription: &asbd)
        else { return log("tapError", ["tap": label, "step": "readFormat"]) }
        self.format = format
        log("tapFormat", ["tap": label, "sampleRate": asbd.mSampleRate, "channels": asbd.mChannelsPerFrame, "interleaved": format.isInterleaved])

        var formatAddr = address(kAudioTapPropertyFormat)
        AudioObjectAddPropertyListenerBlock(tapID, &formatAddr, .main) { [label, tapID] _, _ in
            let rate = readValue(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription())?.mSampleRate ?? 0
            log("tapFormatChanged", ["tap": label, "sampleRate": rate])
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Carbon Probe \(label)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { return log("tapError", ["tap": label, "step": "createAggregate", "status": status]) }

        do {
            file = try AVAudioFile(forWriting: runDir.appendingPathComponent("\(label).wav"), settings: format.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        } catch {
            log("tapError", ["tap": label, "step": "openFile", "error": "\(error)"])
        }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            guard let self, let format = self.format,
                  let wrapped = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil)
            else { return }
            self.consume(wrapped)
        }
        guard status == noErr else { return log("tapError", ["tap": label, "step": "createIOProc", "status": status]) }
        status = AudioDeviceStart(aggregateID, procID)
        log("tapStarted", ["tap": label, "status": status, "aggregateRate": readValue(aggregateID, kAudioDevicePropertyNominalSampleRate, Float64(0)) ?? 0])
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        callbacks += 1
        let count = Int(buffer.frameLength)
        frames += count
        totalFrames += count
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            guard let data = audioBuffer.mData else { continue }
            let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: Int(audioBuffer.mDataByteSize) / 4)
            sampleCount += samples.count
            for sample in samples {
                sumSquares += Double(sample * sample)
                peak = max(peak, abs(sample))
            }
        }
        do { try file?.write(from: buffer) } catch { log("tapError", ["tap": label, "step": "writeFile", "error": "\(error)"]) ; file = nil }
    }

    func report() {
        queue.async { [self] in
            let rms = sampleCount > 0 ? sqrt(sumSquares / Double(sampleCount)) : 0
            let dbfs = rms > 0 ? (20 * log10(rms) * 10).rounded() / 10 : -999
            silentSeconds = dbfs < -60 ? silentSeconds + 1 : 0
            log("level", ["tap": label, "framesPerSec": frames, "callbacks": callbacks, "rmsDbfs": dbfs, "peak": (Double(peak) * 1000).rounded() / 1000, "silentFor": silentSeconds])
            frames = 0; sampleCount = 0; sumSquares = 0; peak = 0; callbacks = 0
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        queue.sync { file?.close(); file = nil }
        queue.sync { log("tapStopped", ["tap": label, "totalFrames": totalFrames, "file": "\(label).wav"]) }
    }
}

// MARK: - Main

let arguments = CommandLine.arguments.dropFirst()
let target = arguments.first
let duration = arguments.dropFirst().first.flatMap(Double.init)

log("run", ["dir": runDir.path, "target": target ?? NSNull(), "seconds": duration ?? NSNull()])
watchDefaultDevices()
pollProcesses()
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in pollProcesses() }

var recorders: [TapRecorder] = []
if let target {
    let bundle = CATapDescription(stereoMixdownOfProcesses: [])
    bundle.bundleIDs = [target]
    bundle.isProcessRestoreEnabled = true

    let matched = audioProcesses().filter { $0.bundleID.hasPrefix(target) || $0.path.localizedCaseInsensitiveContains(target) }
    log("prefixMatch", ["processes": matched.map { "\($0.pid) \($0.bundleID)" }])
    let prefix = CATapDescription(stereoMixdownOfProcesses: matched.map(\.object))

    let global = CATapDescription(stereoGlobalTapButExcludeProcesses: [])

    recorders = [TapRecorder(label: "bundle", description: bundle), TapRecorder(label: "global", description: global)]
    if matched.isEmpty {
        log("tapError", ["tap": "prefix", "step": "noMatchingProcess"])
    } else {
        recorders.insert(TapRecorder(label: "prefix", description: prefix), at: 1)
    }
    recorders.forEach { $0.start() }
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in recorders.forEach { $0.report() } }
}

func finish() -> Never {
    recorders.forEach { $0.stop() }
    logQueue.sync {}
    exit(0)
}

signal(SIGINT, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler { finish() }
interrupt.resume()
if let duration {
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { finish() }
}

RunLoop.main.run()
