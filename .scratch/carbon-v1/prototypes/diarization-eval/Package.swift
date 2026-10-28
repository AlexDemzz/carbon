// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "diarize",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7")
    ],
    targets: [
        .executableTarget(name: "diarize", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])
    ]
)
