// swift-tools-version: 6.2
import PackageDescription

// Mirrors the app target's Swift 6 + "Approachable Concurrency" settings so code
// keeps its semantics when it moves between the app and a package. The packages
// deliberately omit the app's MainActor default isolation (ARCHITECTURE.md §4).
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

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
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TransmissionRPCTests",
            dependencies: ["TransmissionRPC"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
