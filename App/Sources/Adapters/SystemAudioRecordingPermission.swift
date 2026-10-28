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
