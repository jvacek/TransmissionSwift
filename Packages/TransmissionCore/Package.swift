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
    name: "TransmissionCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "TransmissionCore", targets: ["TransmissionCore"]),
        .library(name: "TransmissionTestSupport", targets: ["TransmissionTestSupport"]),
    ],
    dependencies: [
        .package(path: "../TransmissionRPC")
    ],
    targets: [
        // libz, to gunzip DB-IP's compressed GeoIP dump. A system library, not a
        // third-party package; ships with macOS/iOS.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "TransmissionCore",
            dependencies: ["TransmissionRPC", "CZlib"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TransmissionTestSupport",
            dependencies: ["TransmissionCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TransmissionCoreTests",
            dependencies: ["TransmissionCore", "TransmissionRPC", "TransmissionTestSupport"],
            swiftSettings: swiftSettings
        ),
    ]
)
