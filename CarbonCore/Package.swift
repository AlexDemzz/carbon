// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CarbonCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CarbonCore", targets: ["CarbonCore"])
    ],
    targets: [
        .target(name: "CarbonCore", resources: [.copy("Resources/VendorTable.json")]),
        .testTarget(
            name: "CarbonCoreTests",
            dependencies: ["CarbonCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
