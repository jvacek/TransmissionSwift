// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TransmissionCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "TransmissionCore", targets: ["TransmissionCore"])
    ],
    dependencies: [
        .package(path: "../TransmissionRPC")
    ],
    targets: [
        .target(
            name: "TransmissionCore",
            dependencies: ["TransmissionRPC"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "TransmissionCoreTests",
            dependencies: ["TransmissionCore", "TransmissionRPC"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
