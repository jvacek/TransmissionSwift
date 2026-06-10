// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TransmissionRPC",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "TransmissionRPC", targets: ["TransmissionRPC"])
    ],
    targets: [
        .target(
            name: "TransmissionRPC",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "TransmissionRPCTests",
            dependencies: ["TransmissionRPC"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
