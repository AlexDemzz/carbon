import CarbonCore
import Darwin
import Foundation

/// Reads the System Audio Recording permission with the private `TCCAccessPreflight`, loaded through `dlsym`.
enum SystemAudioRecordingPermission {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int

    private static let preflight: Preflight? = {
        guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
            let symbol = dlsym(tcc, "TCCAccessPreflight")
        else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)
    }()

    private typealias Request =
        @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let request: Request? = {
        guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
            let symbol = dlsym(tcc, "TCCAccessRequest")
        else { return nil }
        return unsafeBitCast(symbol, to: Request.self)
    }()

    /// Shows the system prompt when the person hasn't answered yet, through the private `TCCAccessRequest`.
    /// Without it, the prompt comes with the first tap instead.
    static func requestAccess() async {
        guard current() == .notDetermined, let request else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            request("kTCCServiceAudioCapture" as CFString, nil) { _ in continuation.resume() }
        }
    }

    static func current() -> SystemAudioPermission {
        guard let preflight else { return .unknown }
        return switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: .granted
        case 1: .denied
        case 2: .notDetermined
        default: .unknown
        }
    }
}
