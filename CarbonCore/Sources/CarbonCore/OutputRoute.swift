import Foundation

/// One output device sound plays to, as Core Audio describes it.
public struct OutputDevice: Sendable, Equatable {
    public enum Transport: Sendable, Equatable { case builtIn, usb, bluetooth, bluetoothLE, other }

    public var name: String
    public var transport: Transport
    /// Terminal types of the device's output streams (kAudioStreamPropertyTerminalType).
    public var terminalTypes: [UInt32]
    /// The current output data source (kAudioDevicePropertyDataSource), e.g. 'hdpn', 'ispk'.
    public var dataSource: UInt32?

    public init(name: String, transport: Transport, terminalTypes: [UInt32] = [], dataSource: UInt32? = nil) {
        self.name = name
        self.transport = transport
        self.terminalTypes = terminalTypes
        self.dataSource = dataSource
    }
}

/// A route source that can't tell where sound plays: the mic is always shared.
public struct UnknownOutputRoute: OutputRouteSource {
    public init() {}

    public func routes() -> AsyncStream<OutputRoute> {
        AsyncStream { continuation in
            continuation.yield(.speakers)
            continuation.finish()
        }
    }
}

extension OutputRoute {
    /// `headphones` only when there is at least one device and every one is a headphone; anything unsure is `speakers`.
    public static func of(_ devices: [OutputDevice]) -> OutputRoute {
        !devices.isEmpty && devices.allSatisfy(\.isHeadphone) ? .headphones : .speakers
    }
}

extension OutputDevice {
    /// Loudspeakers, and the speakerphones a room shares. These are never headphones, whatever they report.
    private static var speakerNames: some RegexComponent {
        /speaker|soundbar|soundlink|homepod|sonos|jbl (flip|charge|clip|go)|bose home|\becho\b|conference|meeting.?room|polycom|poly sync|jabra speak|powerconf|emeet|yealink/
            .ignoresCase()
    }

    /// `kAudioStreamTerminalTypeHeadphones` and `…HeadsetMicrophone` ('hdph', 'hmic'), and the USB Audio terminal
    /// codes some drivers report instead (IOAudioTypes.h): headphones 0x0302, head-mounted display 0x0303,
    /// headset 0x0402.
    private static let headphoneTerminals: Set<UInt32> = [0x6864_7068, 0x686D_6963, 0x0302, 0x0303, 0x0402]
    /// The built-in jack's headphone data source, 'hdpn'.
    private static let headphoneDataSource: UInt32 = 0x6864_706E

    var isHeadphone: Bool {
        if name.contains(Self.speakerNames) { return false }
        if terminalTypes.contains(where: Self.headphoneTerminals.contains) || dataSource == Self.headphoneDataSource {
            return true
        }
        return switch transport {
        // Most Bluetooth audio on a laptop is a headphone, and popular ones carry no keyword in their name.
        case .bluetooth, .bluetoothLE: true
        case .usb: name.contains(/headphone|headset|airpod|earbud/.ignoresCase())
        case .builtIn: name.localizedCaseInsensitiveContains("headphone")
        case .other: false
        }
    }
}
