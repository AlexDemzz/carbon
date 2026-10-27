// swift-tools-version: 6.2
// PROTOTYPE, throwaway. See README.md.
import PackageDescription

let package = Package(
    name: "CarbonMock",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "CarbonMock", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
