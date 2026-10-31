// swift-tools-version: 6.2
import PackageDescription

// Replays a recorded Meeting through Carbon's real Recorder and transcription adapters, at real-time pace.
// See docs/research/transcription-cpu-cost.md.
let package = Package(
    name: "Bench",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../CarbonCore")],
    targets: [.executableTarget(name: "Bench", dependencies: [.product(name: "CarbonCore", package: "CarbonCore")])]
)
