import CarbonCore
import CoreAudio
import Darwin
import Foundation

/// Core Audio's process objects, read fresh on every call: process object IDs are never cached.
enum AudioProcesses {
    struct Process {
        var id: AudioObjectID
        var owner: MeetingApp?
        var isRunningInput: Bool
        var isRunningOutput: Bool
    }

    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Every audio process, through `kAudioHardwarePropertyProcessObjectList`.
    static func ids() -> [AudioObjectID] {
        objectList(of: system, kAudioHardwarePropertyProcessObjectList) ?? []
    }

    /// Every audio device, through `kAudioHardwarePropertyDevices`.
    static func devices() -> [AudioObjectID] {
        objectList(of: system, kAudioHardwarePropertyDevices) ?? []
    }

    static func all() -> [Process] {
        ids().map { id in
            Process(
                id: id, owner: owner(of: id), isRunningInput: flag(kAudioProcessPropertyIsRunningInput, of: id),
                isRunningOutput: flag(kAudioProcessPropertyIsRunningOutput, of: id))
        }
    }

    /// The processes owned by `app`: the ones a Meeting's tap targets.
    static func owned(by app: MeetingApp) -> [Process] {
        all().filter { $0.owner?.bundleID == app.bundleID }
    }

    /// Carbon's own process object, or nil while Carbon has none yet.
    static func carbon() -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var process = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = AudioObjectGetPropertyData(
            system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process)
        return status == noErr && process != kAudioObjectUnknown ? process : nil
    }

    /// The app that owns a process: its responsible process's outermost `.app`, else the process's own bundle.
    static func owner(of id: AudioObjectID) -> MeetingApp? {
        var pid = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = address(kAudioProcessPropertyPID)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &pid) == noErr else { return nil }
        if let responsible = responsiblePID(pid), let app = outermostApp(of: responsible) { return app }
        if let app = outermostApp(of: pid) { return app }
        guard let bundleID = string(kAudioProcessPropertyBundleID, of: id), !bundleID.isEmpty else { return nil }
        let name = path(of: pid).map { URL(filePath: $0).lastPathComponent } ?? bundleID
        return MeetingApp(bundleID: bundleID, name: name)
    }

    /// The app that owns any process, such as a power assertion's: its responsible process's outermost `.app`.
    static func owner(ofPID pid: pid_t) -> MeetingApp? {
        if let responsible = responsiblePID(pid), let app = outermostApp(of: responsible) { return app }
        return outermostApp(of: pid)
    }

    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t

    /// The private `responsibility_get_pid_responsible_for_pid`, loaded through `dlsym`. Nil if the OS drops it.
    private static let responsibility: ResponsiblePID? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePID.self)
    }()

    private static func responsiblePID(_ pid: pid_t) -> pid_t? {
        guard let responsible = responsibility?(pid), responsible > 0 else { return nil }
        return responsible
    }

    private static func outermostApp(of pid: pid_t) -> MeetingApp? {
        guard let path = path(of: pid) else { return nil }
        let components = URL(filePath: path).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let url = URL(filePath: NSString.path(withComponents: Array(components[...index])), directoryHint: .isDirectory)
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        let name =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return MeetingApp(bundleID: bundleID, name: name)
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// The object IDs a property lists, or nil when the read fails.
    static func objectList(
        of object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID]? {
        var address = address(selector)
        address.mScope = scope
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return nil }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// A `UInt32` property, or nil when the read fails.
    static func uint32(
        _ selector: AudioObjectPropertySelector, of id: AudioObjectID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(selector)
        address.mScope = scope
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func flag(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> Bool {
        (uint32(selector, of: id) ?? 0) != 0
    }

    static func string(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(selector)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
