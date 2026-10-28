import CarbonCore
import Testing

struct OutputRouteTests {
    static let airPods = OutputDevice(name: "Alex's AirPods Pro", transport: .bluetooth)
    static let macBookSpeakers = OutputDevice(
        name: "MacBook Pro Speakers", transport: .builtIn, terminalTypes: [0x0301], dataSource: 0x6973_706B /* 'ispk' */)

    /// What the Mac plays to, as known hardware describes itself, and where its sound lands.
    static let knownHardware: [([OutputDevice], OutputRoute)] = [
        ([airPods], .headphones),
        ([OutputDevice(name: "WH-1000XM5", transport: .bluetooth)], .headphones),
        (
            [OutputDevice(name: "External Headphones", transport: .builtIn, dataSource: 0x6864_706E /* 'hdpn' */)],
            .headphones
        ),
        ([macBookSpeakers], .speakers),
        ([OutputDevice(name: "Jabra Evolve2 65", transport: .usb, terminalTypes: [0x0402])], .headphones),
        ([OutputDevice(name: "Jabra Speak 750", transport: .bluetooth)], .speakers),
        ([OutputDevice(name: "Jabra SPEAK 510", transport: .usb, terminalTypes: [0x0402])], .speakers),
        ([OutputDevice(name: "Sonos Move", transport: .bluetooth)], .speakers),
        ([OutputDevice(name: "LG HDR 4K", transport: .other)], .speakers),
        ([OutputDevice(name: "Multi-Output Device", transport: .other)], .speakers),
        ([airPods, macBookSpeakers], .speakers),
        ([], .speakers),
    ]

    @Test(arguments: knownHardware)
    func theRouteOfKnownHardware(outputs: [OutputDevice], route: OutputRoute) {
        #expect(OutputRoute.of(outputs) == route)
    }
}
